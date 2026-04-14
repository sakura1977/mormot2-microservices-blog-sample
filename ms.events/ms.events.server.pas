/// <summary>
///   Event-bus microservice. Stage 2 (persistent outbox + ring-buffer fast path) of
///   SPEC #22 / PLAN #23.
///
///   Hosts two SOA services on a single port:
///   <list>
///     <item><c>TEventPublisherService</c> -- write path. Stamps the event with the current
///       correlation ID and hands it to the stream service.</item>
///     <item><c>TEventStreamService</c> -- fan-out path. Persists every event to
///       <c>TOrmEventOutbox</c> (the assigned <c>RowID</c> becomes the bus event ID), keeps the
///       last <c>EVENT_BUFFER_SIZE</c> events in a ring buffer for fast replay, broadcasts every
///       new event over WebSocket callbacks, and evicts subscribers after
///       <c>DEFAULT_SUBSCRIBER_FAILURE_THRESHOLD</c> consecutive failures.</item>
///   </list>
///
///   Catch-up sources, in priority order: <c>aFromEventId = -1</c> resolves to
///   <c>TOrmConsumerCursor.LastEventId + 1</c>; <c>aFromEventId &gt; 0</c> not covered by the ring
///   buffer is served from <c>TOrmEventOutbox</c> (T16 — replaces the stage-1
///   <c>EEventBufferOverrun</c> raise). <c>Acknowledge</c> upserts the consumer cursor.
///
///   When constructed without an <c>IRestOrm</c> (tests / stage-1 unit fixtures) the service
///   degrades to in-memory-only behaviour: no persistence, no cursors, ring-buffer-only catch-up
///   (raises <c>EEventBufferOverrun</c> on overrun, as in stage 1).
/// </summary>
unit ms.events.server;

{$SCOPEDENUMS ON}
{$I mormot.defines.inc}
{$WARN SYMBOL_PLATFORM OFF}
{$WARN UNIT_PLATFORM OFF}

interface

uses
  System.SysUtils,
  mormot.core.base,
  mormot.core.datetime,
  mormot.core.interfaces,
  mormot.core.os,
  mormot.core.text,
  mormot.orm.base,
  mormot.orm.core,
  mormot.rest.core,
  mormot.rest.server,
  mormot.rest.sqlite3,
  mormot.soa.core,
  mormot.soa.server,
  ms.shared,
  ms.shared.api,
  ms.shared.correlation,
  ms.shared.service,
  ms.events.model;

const

  /// <summary>
  ///   Number of most recent events retained for catch-up subscribers. Older events trigger an
  ///   <c>EEventBufferOverrun</c> on <c>Subscribe</c>. Persistent catch-up arrives in stage 2.
  /// </summary>
  EVENT_BUFFER_SIZE = 1000;

  /// <summary>
  ///   Consecutive <c>OnEvent</c> failures that must accumulate before a subscriber is evicted.
  ///   A single transient error (e.g. a slow TCP peer) must not drop an otherwise healthy viewer.
  /// </summary>
  DEFAULT_SUBSCRIBER_FAILURE_THRESHOLD = 3;

type

  /// <summary>
  ///   Raised when a subscriber asks for an <c>aFromEventId</c> that has already been overwritten
  ///   in the ring buffer. In stage 2 the consumer cursor is consulted instead, so this exception
  ///   disappears for the common case.
  /// </summary>
  EEventBufferOverrun = class(ESynException);

  TEventStreamService = class;

  /// <summary>
  ///   Producer-side implementation of <c>IEventPublisher</c>. Synchronous: on return the event
  ///   has been added to the ring buffer and broadcast to all currently-subscribed consumers.
  /// </summary>
  TEventPublisherService = class(TInterfacedObject, IEventPublisher)
  strict private
    /// <summary>
    ///   The fan-out/ring-buffer service. Never <c>nil</c> -- construction order is enforced by
    ///   <c>TEventsServer.SetupServices</c>.
    /// </summary>
    FStream: TEventStreamService;
  public

    /// <summary>
    ///   Wires the publisher to the stream service used for ID assignment, retention and fan-out.
    /// </summary>
    constructor Create(
      aStream: TEventStreamService
      );

    /// <summary>
    ///   Builds a <c>TEventDto</c>, stamps it with the current correlation ID and passes it to the
    ///   stream service. Returns the bus-assigned monotonic ID.
    /// </summary>
    function Publish(
      const aEventType: RawUtf8;
      const aPayloadJson: RawJson;
      const aProducerService: RawUtf8;
      aSchemaVersion: Integer
      ): TID;
  end;

  /// <summary>
  ///   Per-subscriber bookkeeping. Kept as a record so the failure counter survives transient
  ///   exceptions without re-allocating the callback reference.
  /// </summary>
  TEventSubscriberEntry = record
    ConsumerName: RawUtf8;
    Callback: IEventStreamCallback;
    FailureCount: Integer;
  end;

  /// <summary>
  ///   Fan-out service implementing <c>IEventStream</c>. Owns the ring buffer and the subscriber
  ///   list, serializes access via a single critical section, and routes broadcasts synchronously
  ///   (mORMot2 serializes calls per subscriber via <c>optExecLockedPerInterface</c>).
  /// </summary>
  TEventStreamService = class(TInterfacedObject, IEventStream)
  strict private
    FLock: TRTLCriticalSection;
    FBuffer: TEventDtoArray;
    /// <summary>
    ///   Index where the next event will be written. Wraps modulo <c>EVENT_BUFFER_SIZE</c>.
    /// </summary>
    FBufferHead: Integer;
    /// <summary>
    ///   Number of events currently in the buffer (0..<c>EVENT_BUFFER_SIZE</c>).
    /// </summary>
    FBufferCount: Integer;
    /// <summary>
    ///   ID that will be assigned to the next published event when no ORM is wired (in-memory
    ///   fallback only). Starts at 1, never decreases. Ignored when <c>FOrm</c> is set -- SQLite
    ///   then assigns the ID via <c>TOrmEventOutbox.RowID</c>.
    /// </summary>
    FNextId: TID;
    FSubscribers: array of TEventSubscriberEntry;
    FFailureThreshold: Integer;
    /// <summary>
    ///   ORM facade for the per-service SQLite DB. <c>nil</c> in tests / stage-1 fixtures, in
    ///   which case the service runs in-memory-only (no outbox, no cursors).
    /// </summary>
    FOrm: IRestOrm;

    /// <summary>
    ///   Streams events with <c>ID &gt;= aFromEventId AND ID &lt; aUpperExclusiveId</c> from
    ///   <c>TOrmEventOutbox</c> directly to <c>aCallback</c>. Caller holds <c>FLock</c> so no new
    ///   events are broadcast meanwhile -- catch-up and live tail join without gap or duplicate.
    /// </summary>
    procedure CatchUpFromOutboxLocked(
      aFromEventId, aUpperExclusiveId: TID;
      const aCallback: IEventStreamCallback
      );

    /// <summary>
    ///   Walks the ring buffer in publication order and invokes <c>OnEvent</c> for every stored
    ///   entry with <c>ID &gt;= aFromEventId</c>. The caller holds <c>FLock</c>.
    /// </summary>
    /// <exception cref="EEventBufferOverrun">
    ///   Raised when <c>aFromEventId</c> is older than the oldest buffered event.
    /// </exception>
    procedure ReplayLocked(
      aFromEventId: TID;
      const aCallback: IEventStreamCallback
      );
  public
    /// <summary>
    ///   Wires the service to the per-service ORM. Pass <c>nil</c> for in-memory-only operation
    ///   (tests). When set, the constructor seeds <c>FNextId</c> from
    ///   <c>MAX(TOrmEventOutbox.ID)</c> so monotonicity survives restarts.
    /// </summary>
    constructor Create(
      const aOrm: IRestOrm = nil
      ); reintroduce;
    destructor Destroy; override;

    /// <summary>
    ///   Assigns an ID, stores the event in the ring buffer and fans it out to all current
    ///   subscribers. Called from <c>TEventPublisherService.Publish</c>.
    /// </summary>
    function AppendAndBroadcast(
      var aEvent: TEventDto
      ): TID;

    // IEventStream
    procedure Subscribe(
      const aConsumerName: RawUtf8;
      aFromEventId: TID;
      const aCallback: IEventStreamCallback
      );
    procedure Acknowledge(
      const aConsumerName: RawUtf8;
      aLastAckedId: TID
      );
    procedure Unsubscribe(
      const aCallback: IEventStreamCallback
      );

    // IServiceWithCallbackReleased
    procedure CallbackReleased(
      const Callback: IInvokable;
      const InterfaceName: RawUtf8
      );

    /// <summary>
    ///   Eviction threshold exposed for tests; defaults to
    ///   <c>DEFAULT_SUBSCRIBER_FAILURE_THRESHOLD</c>.
    /// </summary>
    property FailureThreshold: Integer
      read FFailureThreshold write FFailureThreshold;
  end;

  /// <summary>
  ///   Microservice host. Registers <c>IEventPublisher</c> and <c>IEventStream</c>, enables
  ///   WebSockets on the REST server via the <c>TMicroService</c> base class.
  /// </summary>
  TEventsServer = class(TMicroService)
  strict private
    FPublisherImpl: TEventPublisherService;
    FStreamImpl: TEventStreamService;
  protected

    /// <summary>
    ///   Registers <c>TOrmEventOutbox</c> (the persistent event log) and
    ///   <c>TOrmConsumerCursor</c> (per-consumer ACK position). Persist-on-Publish, catch-up
    ///   queries and cursor advancement land in T16; the tables are already created here so
    ///   the schema exists from the first server start.
    /// </summary>
    function CreateModel: TOrmModel; override;

    /// <summary>
    ///   Creates the stream service first, then the publisher that references it, and registers
    ///   both on the REST server. Uses <c>optExecLockedPerInterface</c> for the stream so
    ///   <c>OnEvent</c> calls are serialized per subscriber.
    /// </summary>
    procedure SetupServices; override;
  end;

implementation

{ TEventPublisherService }

constructor TEventPublisherService.Create(
  aStream: TEventStreamService
  );
begin
  inherited Create;
  FStream := aStream;
end;

function TEventPublisherService.Publish(
  const aEventType: RawUtf8;
  const aPayloadJson: RawJson;
  const aProducerService: RawUtf8;
  aSchemaVersion: Integer
  ): TID;
var
  Event: TEventDto;
begin
  FillCharFast(Event, SizeOf(Event), 0);
  Event.EventType := aEventType;
  Event.PayloadJson := aPayloadJson;
  Event.ProducerService := aProducerService;
  Event.CreatedAt := NowUtc;
  Event.CorrelationId := GetCurrentCorrelationId;
  Event.SchemaVersion := aSchemaVersion;
  Result := FStream.AppendAndBroadcast(Event);
end;

{ TEventStreamService }

constructor TEventStreamService.Create(
  const aOrm: IRestOrm
  );
var
  HighWatermark: TID;
begin
  inherited Create;
  InitializeCriticalSection(FLock);
  SetLength(FBuffer, EVENT_BUFFER_SIZE);
  FBufferHead := 0;
  FBufferCount := 0;
  FFailureThreshold := DEFAULT_SUBSCRIBER_FAILURE_THRESHOLD;
  FOrm := aOrm;
  // FNextId is only consulted in the in-memory fallback. When ORM is wired SQLite assigns the
  // ID, but we still need a monotonicity baseline for catch-up upper-bound math, so seed it
  // from the highest persisted ID + 1.
  if FOrm <> nil then
  begin
    HighWatermark := GetInt64(pointer(
      FOrm.OneFieldValue(TOrmEventOutbox, 'max(RowID)', '')));
    FNextId := HighWatermark + 1;
  end
  else
    FNextId := 1;
end;

destructor TEventStreamService.Destroy;
begin
  EnterCriticalSection(FLock);
  try
    FSubscribers := nil;
    FBuffer := nil;
  finally
    LeaveCriticalSection(FLock);
  end;
  DeleteCriticalSection(FLock);
  inherited Destroy;
end;

function TEventStreamService.AppendAndBroadcast(
  var aEvent: TEventDto
  ): TID;
var
  SubscriberIdx: PtrInt;
  Outbox: TOrmEventOutbox;
begin
  EnterCriticalSection(FLock);
  try
    if FOrm <> nil then
    begin
      // Persist FIRST so the SQLite RowID becomes the bus-wide monotonic event ID. Holding
      // FLock during the INSERT serializes publishers with subscribe/catch-up; the cost is
      // acceptable for a learning-grade event bus and removes any reordering window.
      Outbox := TOrmEventOutbox.Create;
      try
        Outbox.EventType := aEvent.EventType;
        Outbox.PayloadJson := aEvent.PayloadJson;
        Outbox.ProducerService := aEvent.ProducerService;
        Outbox.CreatedAt := aEvent.CreatedAt;
        Outbox.CorrelationId := aEvent.CorrelationId;
        Outbox.SchemaVersion := aEvent.SchemaVersion;
        Result := FOrm.Add(Outbox, true);
        if Result <= 0 then
          raise ESynException.Create('TEventStreamService: failed to persist event to outbox');
        aEvent.ID := Result;
        FNextId := Result + 1;
      finally
        Outbox.Free;
      end;
    end
    else
    begin
      // In-memory fallback (tests / stage-1 fixtures): assign sequential ID locally.
      aEvent.ID := FNextId;
      Result := FNextId;
      Inc(FNextId);
    end;
    FBuffer[FBufferHead] := aEvent;
    FBufferHead := (FBufferHead + 1) mod EVENT_BUFFER_SIZE;
    if FBufferCount < EVENT_BUFFER_SIZE then
      Inc(FBufferCount);
    // Iterate from the end so eviction during dispatch does not shift later indices.
    for SubscriberIdx := High(FSubscribers) downto 0 do
      try
        FSubscribers[SubscriberIdx].Callback.OnEvent(aEvent);
        FSubscribers[SubscriberIdx].FailureCount := 0;
      except
        Inc(FSubscribers[SubscriberIdx].FailureCount);
        if FSubscribers[SubscriberIdx].FailureCount >= FFailureThreshold then
          Delete(FSubscribers, SubscriberIdx, 1);
      end;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TEventStreamService.ReplayLocked(
  aFromEventId: TID;
  const aCallback: IEventStreamCallback
  );
var
  OldestBufferedId: TID;
  Walk, Idx: Integer;
begin
  if (aFromEventId <= 0) or (FBufferCount = 0) then
    Exit;
  // Oldest ID still in the ring buffer. FNextId points past the newest entry, so the newest
  // stored ID is FNextId - 1 and there are FBufferCount entries below it.
  OldestBufferedId := FNextId - FBufferCount;
  if aFromEventId < OldestBufferedId then
    raise EEventBufferOverrun.CreateFmt(
      'Requested fromEventId=%d is older than oldest buffered event ID=%d',
      [aFromEventId, OldestBufferedId]);
  for Walk := 0 to FBufferCount - 1 do
  begin
    Idx := (FBufferHead - FBufferCount + Walk + EVENT_BUFFER_SIZE) mod EVENT_BUFFER_SIZE;
    if FBuffer[Idx].ID >= aFromEventId then
      aCallback.OnEvent(FBuffer[Idx]);
  end;
end;

procedure TEventStreamService.CatchUpFromOutboxLocked(
  aFromEventId, aUpperExclusiveId: TID;
  const aCallback: IEventStreamCallback
  );
var
  Outbox: TOrmEventOutbox;
  Event: TEventDto;
begin
  if (aFromEventId <= 0) or (aFromEventId >= aUpperExclusiveId) or (FOrm = nil) then
    Exit;
  Outbox := TOrmEventOutbox.CreateAndFillPrepare(FOrm,
    'RowID>=? and RowID<? order by RowID',
    [], [aFromEventId, aUpperExclusiveId]);
  try
    while Outbox.FillOne do
    begin
      FillCharFast(Event, SizeOf(Event), 0);
      Event.ID := Outbox.IDValue;
      Event.EventType := Outbox.EventType;
      Event.PayloadJson := RawJson(Outbox.PayloadJson);
      Event.ProducerService := Outbox.ProducerService;
      Event.CreatedAt := Outbox.CreatedAt;
      Event.CorrelationId := Outbox.CorrelationId;
      Event.SchemaVersion := Outbox.SchemaVersion;
      // Exceptions propagate so the consumer can react; matches the ring-buffer ReplayLocked
      // contract and avoids partial silent delivery.
      aCallback.OnEvent(Event);
    end;
  finally
    Outbox.Free;
  end;
end;

procedure TEventStreamService.Subscribe(
  const aConsumerName: RawUtf8;
  aFromEventId: TID;
  const aCallback: IEventStreamCallback
  );
var
  Entry: TEventSubscriberEntry;
  Cursor: TOrmConsumerCursor;
  EffectiveFromId: TID;
begin
  EnterCriticalSection(FLock);
  try
    EffectiveFromId := aFromEventId;
    // Resume-from-cursor: -1 asks "wherever I left off". Missing cursor row means the consumer
    // has never ACKed -- start from the very first persisted event.
    if (EffectiveFromId < 0) and (FOrm <> nil) then
    begin
      Cursor := TOrmConsumerCursor.Create(FOrm, 'ConsumerName=?', [aConsumerName]);
      try
        if Cursor.IDValue <> 0 then
          EffectiveFromId := Cursor.LastEventId + 1
        else
          EffectiveFromId := 1;
      finally
        Cursor.Free;
      end;
    end
    else if EffectiveFromId < 0 then
      // No ORM available -- treat resume as live-only so tests without ORM still work.
      EffectiveFromId := 0;

    // Catch-up: ORM when wired (covers the full history), ring buffer otherwise.
    if FOrm <> nil then
      CatchUpFromOutboxLocked(EffectiveFromId, FNextId, aCallback)
    else
      ReplayLocked(EffectiveFromId, aCallback);

    Entry.ConsumerName := aConsumerName;
    Entry.Callback := aCallback;
    Entry.FailureCount := 0;
    SetLength(FSubscribers, Length(FSubscribers) + 1);
    FSubscribers[High(FSubscribers)] := Entry;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TEventStreamService.Acknowledge(
  const aConsumerName: RawUtf8;
  aLastAckedId: TID
  );
var
  Cursor: TOrmConsumerCursor;
begin
  // No ORM (tests) -- ACK is a documented no-op.
  if FOrm = nil then
    Exit;
  EnterCriticalSection(FLock);
  try
    Cursor := TOrmConsumerCursor.Create(FOrm, 'ConsumerName=?', [aConsumerName]);
    try
      if Cursor.IDValue = 0 then
      begin
        Cursor.ConsumerName := aConsumerName;
        Cursor.LastEventId := aLastAckedId;
        Cursor.UpdatedAt := NowUtc;
        FOrm.Add(Cursor, true);
      end
      else
      begin
        // Monotonic guard: late or out-of-order ACKs must not rewind the cursor.
        if aLastAckedId > Cursor.LastEventId then
        begin
          Cursor.LastEventId := aLastAckedId;
          Cursor.UpdatedAt := NowUtc;
          FOrm.Update(Cursor);
        end;
      end;
    finally
      Cursor.Free;
    end;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TEventStreamService.Unsubscribe(
  const aCallback: IEventStreamCallback
  );
var
  SubscriberIdx: PtrInt;
begin
  EnterCriticalSection(FLock);
  try
    for SubscriberIdx := High(FSubscribers) downto 0 do
      if FSubscribers[SubscriberIdx].Callback = aCallback then
      begin
        Delete(FSubscribers, SubscriberIdx, 1);
        Break;
      end;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TEventStreamService.CallbackReleased(
  const Callback: IInvokable;
  const InterfaceName: RawUtf8
  );
var
  ReleasedAsStream: IEventStreamCallback;
  SubscriberIdx: PtrInt;
begin
  if not Supports(Callback, IEventStreamCallback, ReleasedAsStream) then
    Exit;
  EnterCriticalSection(FLock);
  try
    for SubscriberIdx := High(FSubscribers) downto 0 do
      if FSubscribers[SubscriberIdx].Callback = ReleasedAsStream then
      begin
        Delete(FSubscribers, SubscriberIdx, 1);
        Break;
      end;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

{ TEventsServer }

function TEventsServer.CreateModel: TOrmModel;
begin
  Result := TOrmModel.Create([
    TOrmEventOutbox,
    TOrmConsumerCursor], MODEL_ROOT);
end;

procedure TEventsServer.SetupServices;
var
  StreamFactory: TServiceFactoryServerAbstract;
begin
  // Stream service must exist before the publisher so the latter can hand it new entries.
  // Wire the per-service ORM so events are persisted to TOrmEventOutbox and consumer cursors
  // survive restarts (stage 2, T16).
  FStreamImpl := TEventStreamService.Create(FRestServer.Orm);
  FPublisherImpl := TEventPublisherService.Create(FStreamImpl);
  RegisterService(FPublisherImpl, TypeInfo(IEventPublisher));
  StreamFactory := RegisterService(FStreamImpl, TypeInfo(IEventStream));
  // Serialize OnEvent calls per subscriber so each consumer sees events in order even when
  // several publishers call concurrently.
  StreamFactory.SetOptions([], [optExecLockedPerInterface]);
end;

end.
