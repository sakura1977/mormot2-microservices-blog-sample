/// <summary>
///   Circuit breaker pattern implementation for protecting upstream service calls in the gateway and other
///   client-side code.
///
///   <em>Why a circuit breaker?</em> When an upstream backend becomes slow or unreachable, naive try/except
///   "graceful degradation" still pays the full per-request timeout cost. Under load every request thread sits
///   in the timeout, exhausting the worker pool, and a recovering backend gets hammered by a request storm the
///   moment it comes back. A circuit breaker fixes both: once a configured number of consecutive failures has
///   been observed, subsequent calls are short-circuited (no socket, no timeout) until a single probe verifies
///   that the backend has recovered.
///
///   The breaker has three states (<c>TCircuitBreakerState</c>):
///   <list>
///   <item><c>Closed</c>: normal operation, calls pass through, failures are counted.</item>
///   <item><c>Open</c>: upstream considered unhealthy, calls are rejected immediately for the configured
///         cooldown period.</item>
///   <item><c>HalfOpen</c>: cooldown elapsed, exactly one probe call is allowed; success closes the breaker,
///         failure re-opens it for another cooldown.</item>
///   </list>
///
///   The implementation is fully thread-safe via <c>TLightLock</c> and intended to be created once per
///   protected upstream and shared across request threads.
/// </summary>
unit ms.shared.circuitbreaker;

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
  ///   Default number of consecutive failures that will trip the breaker from <c>Closed</c> to <c>Open</c>.
  ///   Set deliberately low (3) so that under per-call timeouts in the multi-second range a tripping
  ///   condition becomes user-visible after a few unsuccessful refreshes rather than dozens.
  /// </summary>
  DEFAULT_FAILURE_THRESHOLD = 3;

  /// <summary>
  ///   Default cooldown period the breaker stays <c>Open</c> before it permits a <c>HalfOpen</c> probe,
  ///   in milliseconds.
  /// </summary>
  DEFAULT_OPEN_TIMEOUT_MS = 30000;

type

  /// <summary>
  ///   Operational state of a <c>TCircuitBreaker</c>.
  /// </summary>
  TCircuitBreakerState = (
    /// <summary>
    ///   Normal operation: calls pass through, failures are counted toward the trip threshold.
    /// </summary>
    Closed,

    /// <summary>
    ///   Upstream considered unhealthy: <c>AllowRequest</c> returns <c>False</c> immediately, no socket is
    ///   opened, no timeout is paid. Lasts for the configured cooldown period.
    /// </summary>
    Open,

    /// <summary>
    ///   Recovery probe: a single trial request is permitted. Success closes the breaker, failure re-opens
    ///   it for another cooldown period.
    /// </summary>
    HalfOpen
    );

  /// <summary>
  ///   Thread-safe circuit breaker that protects a single upstream dependency. One instance per protected
  ///   upstream, shared across all request threads that may call into that upstream.
  ///
  ///   Usage pattern at the call site:
  ///   <code>
  ///   if Breaker.AllowRequest then
  ///     try
  ///       Result := Upstream.Call(...);
  ///       Breaker.RecordSuccess;
  ///     except
  ///       Breaker.RecordFailure;
  ///       // fall back / set Unavailable flag
  ///     end
  ///   else
  ///     // fast-fail path: set Unavailable flag without calling the upstream
  ///   </code>
  /// </summary>
  TCircuitBreaker = class
  strict private
    /// <summary>
    ///   Identifier used in log messages, e.g. the upstream service name (<c>'ms.users'</c>).
    /// </summary>
    FName: RawUtf8;

    /// <summary>
    ///   Number of consecutive failures that will trip the breaker from <c>Closed</c> to <c>Open</c>.
    /// </summary>
    FFailureThreshold: Integer;

    /// <summary>
    ///   Cooldown the breaker stays <c>Open</c> before allowing a <c>HalfOpen</c> probe, in milliseconds.
    /// </summary>
    FOpenTimeoutMs: Int64;

    /// <summary>
    ///   Current operational state. Guarded by <c>FLock</c>.
    /// </summary>
    FState: TCircuitBreakerState;

    /// <summary>
    ///   Number of consecutive failures observed since the last success while in <c>Closed</c> state.
    ///   Reset on every success and on every transition to <c>Closed</c>.
    /// </summary>
    FConsecutiveFailures: Integer;

    /// <summary>
    ///   Tick count (from <c>GetTickCount64</c>) at which the breaker last entered the <c>Open</c> state.
    ///   Used to decide when the <c>HalfOpen</c> probe slot becomes available.
    /// </summary>
    FOpenedAtTick: Int64;

    /// <summary>
    ///   Set while a <c>HalfOpen</c> probe is currently in flight. Prevents multiple concurrent probes
    ///   from hitting a recovering backend simultaneously.
    /// </summary>
    FProbeInFlight: Boolean;

    /// <summary>
    ///   Lightweight spin lock guarding all mutable state. Held only for the very short duration of a
    ///   state inspection or transition; never held across the upstream call itself.
    /// </summary>
    FLock: TLightLock;

    /// <summary>
    ///   Performs a state transition and logs it via <c>TSynLog</c>. The caller must already hold
    ///   <c>FLock</c>. Transitions to <c>Closed</c> reset the consecutive-failure counter.
    /// </summary>
    /// <param name="aNew">
    ///   The target state.
    /// </param>
    procedure TransitionTo(
      const aNew: TCircuitBreakerState
      );
  public

    /// <summary>
    ///   Creates a new circuit breaker in the <c>Closed</c> state.
    /// </summary>
    /// <param name="aName">
    ///   Identifier used in log messages, e.g. the upstream service name (<c>'ms.users'</c>).
    /// </param>
    /// <param name="aFailureThreshold">
    ///   Number of consecutive failures that trips the breaker from <c>Closed</c> to <c>Open</c>.
    /// </param>
    /// <param name="aOpenTimeoutMs">
    ///   Cooldown the breaker stays <c>Open</c> before permitting a <c>HalfOpen</c> probe, in milliseconds.
    /// </param>
    constructor Create(
      const aName: RawUtf8;
      const aFailureThreshold: Integer = DEFAULT_FAILURE_THRESHOLD;
      const aOpenTimeoutMs: Int64 = DEFAULT_OPEN_TIMEOUT_MS
      );

    /// <summary>
    ///   Asks whether a request to the protected upstream is currently allowed. In <c>HalfOpen</c> state
    ///   this also reserves the single probe slot, so a follow-up <c>RecordSuccess</c> or
    ///   <c>RecordFailure</c> from the same caller is required to release it.
    /// </summary>
    /// <returns>
    ///   <c>True</c> if the caller may proceed (<c>Closed</c>, or a <c>HalfOpen</c> probe slot was just
    ///   acquired). <c>False</c> if the breaker is <c>Open</c>, or another <c>HalfOpen</c> probe is in
    ///   flight.
    /// </returns>
    function AllowRequest: Boolean;

    /// <summary>
    ///   Records a successful upstream call. In <c>Closed</c> state this resets the consecutive-failure
    ///   counter; in <c>HalfOpen</c> state it transitions the breaker back to <c>Closed</c>.
    /// </summary>
    procedure RecordSuccess;

    /// <summary>
    ///   Records a failed upstream call. In <c>Closed</c> state this increments the consecutive-failure
    ///   counter and trips the breaker if the threshold is reached. In <c>HalfOpen</c> state it bounces
    ///   the breaker back to <c>Open</c> for another cooldown period.
    /// </summary>
    procedure RecordFailure;

    /// <summary>
    ///   Returns the current operational state. Useful for metrics and tests; the value is a snapshot and
    ///   may change immediately after the call returns.
    /// </summary>
    /// <returns>
    ///   The current <c>TCircuitBreakerState</c>.
    /// </returns>
    function CurrentState: TCircuitBreakerState;

    /// <summary>
    ///   Identifier used in log messages, e.g. the upstream service name.
    /// </summary>
    property Name: RawUtf8 read FName;
  end;

implementation

function TCircuitBreaker.AllowRequest: Boolean;
var
  NowTick: Int64;
begin
  Result := False;
  FLock.Lock;
  try
    case FState of
      TCircuitBreakerState.Closed:
      begin
        Exit(True);
      end;
      TCircuitBreakerState.Open:
      begin
        NowTick := GetTickCount64;
        if (NowTick - FOpenedAtTick) < FOpenTimeoutMs then
          Exit(False);
        TransitionTo(TCircuitBreakerState.HalfOpen);
        FProbeInFlight := True;
        Exit(True);
      end;
      TCircuitBreakerState.HalfOpen:
      begin
        if FProbeInFlight then
          Exit(False);
        FProbeInFlight := True;
        Exit(True);
      end;
    end;
  finally
    FLock.UnLock;
  end;
end;

constructor TCircuitBreaker.Create(
  const aName: RawUtf8;
  const aFailureThreshold: Integer;
  const aOpenTimeoutMs: Int64
  );
begin
  inherited Create;
  FName := aName;
  FFailureThreshold := aFailureThreshold;
  FOpenTimeoutMs := aOpenTimeoutMs;
  FState := TCircuitBreakerState.Closed;
  FConsecutiveFailures := 0;
  FOpenedAtTick := 0;
  FProbeInFlight := False;
end;

function TCircuitBreaker.CurrentState: TCircuitBreakerState;
begin
  FLock.Lock;
  try
    Result := FState;
  finally
    FLock.UnLock;
  end;
end;

procedure TCircuitBreaker.RecordFailure;
begin
  FLock.Lock;
  try
    case FState of
      TCircuitBreakerState.Closed:
      begin
        Inc(FConsecutiveFailures);
        if FConsecutiveFailures >= FFailureThreshold then
        begin
          FOpenedAtTick := GetTickCount64;
          TransitionTo(TCircuitBreakerState.Open);
        end;
      end;
      TCircuitBreakerState.HalfOpen:
      begin
        FOpenedAtTick := GetTickCount64;
        FProbeInFlight := False;
        TransitionTo(TCircuitBreakerState.Open);
      end;
      TCircuitBreakerState.Open:
      begin
        // Already Open: AllowRequest returns False, so callers should not normally end up here. Ignore.
      end;
    end;
  finally
    FLock.UnLock;
  end;
end;

procedure TCircuitBreaker.RecordSuccess;
begin
  FLock.Lock;
  try
    case FState of
      TCircuitBreakerState.Closed:
      begin
        FConsecutiveFailures := 0;
      end;
      TCircuitBreakerState.HalfOpen:
      begin
        FProbeInFlight := False;
        TransitionTo(TCircuitBreakerState.Closed);
      end;
      TCircuitBreakerState.Open:
      begin
        // Defensive: AllowRequest never lets a caller proceed in Open state, so this is unreachable.
      end;
    end;
  finally
    FLock.UnLock;
  end;
end;

procedure TCircuitBreaker.TransitionTo(
  const aNew: TCircuitBreakerState
  );
const
  STATE_NAMES: array[TCircuitBreakerState] of string = (
    'Closed',
    'Open',
    'HalfOpen'
    );
begin
  if FState = aNew then
    Exit;
  TSynLog.Add.Log(sllInfo, 'CircuitBreaker[%]: state % -> %', [FName, STATE_NAMES[FState], STATE_NAMES[aNew]], self);
  FState := aNew;
  if aNew = TCircuitBreakerState.Closed then
    FConsecutiveFailures := 0;
end;

end.
