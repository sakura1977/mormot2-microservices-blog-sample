/// <summary>
///   Token-bucket rate limiter for protecting hot endpoints (auth, search, etc.) against brute-force and
///   abusive request bursts.
///
///   <em>Why a token bucket?</em> A token bucket allows a configurable burst (capacity) and a sustained rate
///   (refill per second). Honest clients see no friction below the burst, while abusive clients are throttled
///   to the refill rate. Per-key buckets isolate clients from each other so one abusive caller cannot starve
///   the rest.
///
///   The limiter is intentionally implemented on top of a plain dynamic array (not <c>TSynDictionary</c>) so
///   that the storage layer can later be swapped (e.g. against a hashed map, a fixed-size LRU cache, or a
///   distributed Redis-backed store) without touching the call sites.
///
///   <em>Two layers of brute-force defence in this project:</em>
///   <list>
///   <item>The gateway runs an instance keyed by client IP and protects all <c>/api/Auth/*</c> endpoints
///         against blanket request floods, before any backend call is made.</item>
///   <item>The auth service runs an instance keyed by email address and is decremented on every failed
///         <c>Authenticate</c> proof. A successful login refunds the email's bucket via <c>Reset</c>, so
///         honest users with the right password are never locked out.</item>
///   </list>
///
///   The implementation is thread-safe via <c>TLightLock</c>. Locks are held only for the brief window of a
///   bucket lookup, refill and decrement; never across IO.
/// </summary>
unit ms.shared.ratelimiter;

{$SCOPEDENUMS ON}
{$I mormot.defines.inc}
{$WARN SYMBOL_PLATFORM OFF}
{$WARN UNIT_PLATFORM OFF}

interface

uses
  System.SysUtils,
  mormot.core.base,
  mormot.core.log,
  mormot.core.os,
  mormot.core.rtti,
  mormot.core.text;

const

  /// <summary>
  ///   Default capacity (burst size) of a single bucket, in tokens. A client may issue this many requests
  ///   back-to-back before being throttled to the refill rate.
  /// </summary>
  DEFAULT_BUCKET_CAPACITY = 10.0;

  /// <summary>
  ///   Default sustained refill rate of a bucket, in tokens per second. With the default capacity of 10
  ///   this allows a 10-request burst followed by 1 request every 6 seconds in steady state.
  /// </summary>
  DEFAULT_REFILL_PER_SEC = 0.1667;

  /// <summary>
  ///   Default idle time after which an unused bucket is evicted, in milliseconds. Eviction prevents the
  ///   bucket array from growing without bound under churn (e.g. many distinct client IPs).
  /// </summary>
  DEFAULT_IDLE_TTL_MS = 600000;

type

  /// <summary>
  ///   A single per-key token bucket. Tokens are stored as a floating-point value so that fractional refill
  ///   over short intervals stays accurate.
  /// </summary>
  TRateBucket = record
  public

    /// <summary>
    ///   The lookup key this bucket belongs to (e.g. a client IP, an email address, or a composite key).
    /// </summary>
    Key: RawUtf8;

    /// <summary>
    ///   Current number of available tokens. Decremented on every successful acquire, refilled lazily on
    ///   the next access.
    /// </summary>
    Tokens: Double;

    /// <summary>
    ///   Tick count (from <c>GetTickCount64</c>) at which <c>Tokens</c> was last refilled. Used to compute
    ///   the elapsed time on the next access.
    /// </summary>
    LastRefillTick: Int64;

    /// <summary>
    ///   Tick count of the last access of any kind (acquire or reset). Used by the idle eviction sweep.
    /// </summary>
    LastAccessTick: Int64;
  end;

  /// <summary>
  ///   Dynamic array of token buckets. Storage is intentionally a flat array so the implementation can be
  ///   swapped without touching the public surface.
  /// </summary>
  TRateBuckets = array of TRateBucket;

  /// <summary>
  ///   Thread-safe token-bucket rate limiter. One instance protects one logical resource with a single
  ///   capacity/refill policy. Multiple instances coexist freely (e.g. one per endpoint, one per identity
  ///   namespace).
  ///
  ///   Usage pattern at the call site:
  ///   <code>
  ///   if not Limiter.TryAcquire(ClientKey) then
  ///     Exit(HTTP_TOOMANYREQUESTS);
  ///   try
  ///     ResultValue := DoExpensiveOperation;
  ///     if SuccessfulOutcome then
  ///       Limiter.Reset(ClientKey); // refund honest callers
  ///   except
  ///     // failure path: token already consumed, that is the brute-force cost
  ///   end;
  ///   </code>
  /// </summary>
  TRateLimiter = class
  strict private

    /// <summary>
    ///   Identifier used in log messages, e.g. <c>'gateway.auth'</c> or <c>'auth.email'</c>.
    /// </summary>
    FName: RawUtf8;

    /// <summary>
    ///   Maximum number of tokens a bucket may hold. Equivalent to the allowed burst size.
    /// </summary>
    FCapacity: Double;

    /// <summary>
    ///   Sustained refill rate, in tokens per second. The bucket gains <c>FRefillPerSec * elapsedSeconds</c>
    ///   tokens between accesses, capped at <c>FCapacity</c>.
    /// </summary>
    FRefillPerSec: Double;

    /// <summary>
    ///   Idle time after which an unused bucket is evicted, in milliseconds.
    /// </summary>
    FIdleTtlMs: Int64;

    /// <summary>
    ///   Backing storage for all per-key buckets. Guarded by <c>FLock</c>.
    /// </summary>
    FBuckets: TRateBuckets;

    /// <summary>
    ///   Tick count of the last idle eviction sweep. Used to amortise the sweep cost so it does not run on
    ///   every acquire.
    /// </summary>
    FLastEvictTick: Int64;

    /// <summary>
    ///   Lightweight spin lock guarding all mutable state. Held only for the brief window of a lookup,
    ///   refill and decrement; never across IO or upstream calls.
    /// </summary>
    FLock: TLightLock;

    /// <summary>
    ///   Linear search for a bucket with the given key. The caller must already hold <c>FLock</c>.
    /// </summary>
    /// <param name="aKey">
    ///   The key to look up.
    /// </param>
    /// <returns>
    ///   The index of the bucket in <c>FBuckets</c>, or <c>-1</c> if no bucket exists for the key.
    /// </returns>
    function FindBucketIdx(
      const aKey: RawUtf8
      ): PtrInt;

    /// <summary>
    ///   Refills the given bucket based on the elapsed time since its last refill, capped at the
    ///   configured capacity. The caller must already hold <c>FLock</c>.
    /// </summary>
    /// <param name="aBucket">
    ///   The bucket to refill.
    /// </param>
    /// <param name="aNowTick">
    ///   The current tick count from <c>GetTickCount64</c>.
    /// </param>
    procedure RefillBucket(
      var aBucket: TRateBucket;
      const aNowTick: Int64
      );

    /// <summary>
    ///   Removes buckets that have not been accessed for at least <c>FIdleTtlMs</c> milliseconds. The
    ///   caller must already hold <c>FLock</c>. Bucketed by <c>FLastEvictTick</c> so the sweep runs at most
    ///   once per idle TTL window.
    /// </summary>
    /// <param name="aNowTick">
    ///   The current tick count from <c>GetTickCount64</c>.
    /// </param>
    procedure EvictIdle(
      const aNowTick: Int64
      );
  public

    /// <summary>
    ///   Creates a new rate limiter with the given policy. All buckets created by this instance share the
    ///   same capacity and refill rate.
    /// </summary>
    /// <param name="aName">
    ///   Identifier used in log messages.
    /// </param>
    /// <param name="aCapacity">
    ///   Maximum number of tokens per bucket (burst size).
    /// </param>
    /// <param name="aRefillPerSec">
    ///   Sustained refill rate in tokens per second.
    /// </param>
    /// <param name="aIdleTtlMs">
    ///   Idle time after which an unused bucket is evicted, in milliseconds.
    /// </param>
    constructor Create(
      const aName: RawUtf8;
      const aCapacity: Double = DEFAULT_BUCKET_CAPACITY;
      const aRefillPerSec: Double = DEFAULT_REFILL_PER_SEC;
      const aIdleTtlMs: Int64 = DEFAULT_IDLE_TTL_MS
      );

    /// <summary>
    ///   Attempts to consume a single token from the bucket identified by <c>aKey</c>. Creates the bucket
    ///   on first use, refills it lazily, and decrements one token if at least one is available.
    /// </summary>
    /// <param name="aKey">
    ///   The lookup key (e.g. client IP or email address).
    /// </param>
    /// <returns>
    ///   <c>True</c> if a token was consumed and the caller may proceed; <c>False</c> if the bucket is
    ///   empty and the caller should be rejected.
    /// </returns>
    function TryAcquire(
      const aKey: RawUtf8
      ): Boolean;

    /// <summary>
    ///   Attempts to consume <c>aTokens</c> tokens from the bucket identified by <c>aKey</c>. Useful for
    ///   weighting expensive operations more heavily than cheap ones under the same policy.
    /// </summary>
    /// <param name="aKey">
    ///   The lookup key.
    /// </param>
    /// <param name="aTokens">
    ///   The number of tokens to consume. Must be greater than zero.
    /// </param>
    /// <returns>
    ///   <c>True</c> if the requested number of tokens was consumed; <c>False</c> if the bucket does not
    ///   currently hold enough tokens.
    /// </returns>
    function TryAcquireN(
      const aKey: RawUtf8;
      const aTokens: Double
      ): Boolean;

    /// <summary>
    ///   Restores the bucket identified by <c>aKey</c> to full capacity. Used by callers that want to
    ///   refund honest clients on a successful outcome (e.g. successful login refunds the email bucket so
    ///   typos do not lock the user out).
    /// </summary>
    /// <param name="aKey">
    ///   The lookup key.
    /// </param>
    procedure Reset(
      const aKey: RawUtf8
      );

    /// <summary>
    ///   Returns the number of currently tracked buckets. Useful for tests and metrics; the value is a
    ///   snapshot and may change immediately after the call returns.
    /// </summary>
    /// <returns>
    ///   The current bucket count.
    /// </returns>
    function BucketCount: PtrInt;

    /// <summary>
    ///   Identifier used in log messages.
    /// </summary>
    property Name: RawUtf8 read FName;

    /// <summary>
    ///   Maximum number of tokens per bucket (burst size).
    /// </summary>
    property Capacity: Double read FCapacity;

    /// <summary>
    ///   Sustained refill rate in tokens per second.
    /// </summary>
    property RefillPerSec: Double read FRefillPerSec;

    /// <summary>
    ///   Idle time after which an unused bucket is evicted, in milliseconds.
    /// </summary>
    property IdleTtlMs: Int64 read FIdleTtlMs;
  end;

implementation

function TRateLimiter.BucketCount: PtrInt;
begin
  FLock.Lock;
  try
    Result := Length(FBuckets);
  finally
    FLock.UnLock;
  end;
end;

constructor TRateLimiter.Create(
  const aName: RawUtf8;
  const aCapacity: Double;
  const aRefillPerSec: Double;
  const aIdleTtlMs: Int64
  );
begin
  inherited Create;
  FName := aName;
  FCapacity := aCapacity;
  FRefillPerSec := aRefillPerSec;
  FIdleTtlMs := aIdleTtlMs;
  FLastEvictTick := GetTickCount64;
end;

procedure TRateLimiter.EvictIdle(
  const aNowTick: Int64
  );
var
  BucketIdx, RemainingCount: PtrInt;
begin
  // Amortise: only sweep once per idle-TTL window so the cost stays O(1) per acquire on average.
  if (aNowTick - FLastEvictTick) < FIdleTtlMs then
    Exit;
  FLastEvictTick := aNowTick;
  RemainingCount := Length(FBuckets);
  BucketIdx := 0;
  while BucketIdx < RemainingCount do
  begin
    if (aNowTick - FBuckets[BucketIdx].LastAccessTick) >= FIdleTtlMs then
    begin
      Dec(RemainingCount);
      if BucketIdx < RemainingCount then
        FBuckets[BucketIdx] := FBuckets[RemainingCount];
      SetLength(FBuckets, RemainingCount);
    end
    else
      Inc(BucketIdx);
  end;
end;

function TRateLimiter.FindBucketIdx(
  const aKey: RawUtf8
  ): PtrInt;
var
  BucketIdx: PtrInt;
begin
  for BucketIdx := 0 to High(FBuckets) do
    if FBuckets[BucketIdx].Key = aKey then
      Exit(BucketIdx);
  Result := -1;
end;

procedure TRateLimiter.RefillBucket(
  var aBucket: TRateBucket;
  const aNowTick: Int64
  );
var
  ElapsedMs: Int64;
  Added: Double;
begin
  ElapsedMs := aNowTick - aBucket.LastRefillTick;
  if ElapsedMs <= 0 then
    Exit;
  Added := (ElapsedMs / 1000.0) * FRefillPerSec;
  aBucket.Tokens := aBucket.Tokens + Added;
  if aBucket.Tokens > FCapacity then
    aBucket.Tokens := FCapacity;
  aBucket.LastRefillTick := aNowTick;
end;

procedure TRateLimiter.Reset(
  const aKey: RawUtf8
  );
var
  BucketIdx: PtrInt;
  NowTick: Int64;
begin
  NowTick := GetTickCount64;
  FLock.Lock;
  try
    BucketIdx := FindBucketIdx(aKey);
    if BucketIdx < 0 then
      Exit;
    FBuckets[BucketIdx].Tokens := FCapacity;
    FBuckets[BucketIdx].LastRefillTick := NowTick;
    FBuckets[BucketIdx].LastAccessTick := NowTick;
  finally
    FLock.UnLock;
  end;
end;

function TRateLimiter.TryAcquire(
  const aKey: RawUtf8
  ): Boolean;
begin
  Result := TryAcquireN(aKey, 1.0);
end;

function TRateLimiter.TryAcquireN(
  const aKey: RawUtf8;
  const aTokens: Double
  ): Boolean;
var
  BucketIdx, NewIdx: PtrInt;
  NowTick: Int64;
begin
  if aTokens <= 0 then
    Exit(True);
  NowTick := GetTickCount64;
  FLock.Lock;
  try
    EvictIdle(NowTick);
    BucketIdx := FindBucketIdx(aKey);
    if BucketIdx < 0 then
    begin
      // First contact for this key: create a full bucket so the very first request always succeeds.
      NewIdx := Length(FBuckets);
      SetLength(FBuckets, NewIdx + 1);
      FBuckets[NewIdx].Key := aKey;
      FBuckets[NewIdx].Tokens := FCapacity;
      FBuckets[NewIdx].LastRefillTick := NowTick;
      FBuckets[NewIdx].LastAccessTick := NowTick;
      BucketIdx := NewIdx;
    end
    else
      RefillBucket(FBuckets[BucketIdx], NowTick);
    FBuckets[BucketIdx].LastAccessTick := NowTick;
    if FBuckets[BucketIdx].Tokens >= aTokens then
    begin
      FBuckets[BucketIdx].Tokens := FBuckets[BucketIdx].Tokens - aTokens;
      Exit(True);
    end;
    TSynLog.Add.Log(sllInfo, 'RateLimiter[%]: throttled key=% tokens=%/% requested=%',
      [FName, aKey, FBuckets[BucketIdx].Tokens, FCapacity, aTokens], self);
    Result := False;
  finally
    FLock.UnLock;
  end;
end;

end.
