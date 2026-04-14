/// <summary>
///   Background event-bus publisher used by every microservice that produces domain events.
///   Stage 2 of SPEC #22 / PLAN #23 (task T17). Mirrors <c>TLogShipper</c> in shape: a thread-safe
///   ring buffer fed synchronously from the producing thread, plus a single worker thread that
///   drains the queue and calls <c>IEventPublisher.Publish</c> on the central <c>ms.events</c>
///   service over a persistent WebSocket connection.
///
///   <para>
///     The producer thread never blocks on the network -- <c>Enqueue</c> only takes a critical
///     section, copies the input record into the ring buffer and signals the worker. If the
///     worker cannot reach <c>ms.events</c> the failed event is requeued at the head with an
///     incremented attempt counter. After <c>MAX_PUBLISH_ATTEMPTS</c> the event is dropped to
///     prevent a poisoned message from blocking the whole pipeline; <c>ms.events</c> still has
///     <c>TOrmEventOutbox</c> for everything that did make it through, and consumers reconnect
///     via cursor on the next subscribe.
///   </para>
///
///   Usage from a producing service:
///   <code>
///   FEventPublisher := TEventPublisher.Create(SERVICE_POSTS, EventsHost, EventsPort);
///   FEventPublisher.Start;
///   ...
///   FEventPublisher.Enqueue('PostPublished', PayloadJson, 1);
///   ...
///   FEventPublisher.Stop;  // before process exit
///   FreeAndNil(FEventPublisher);
///   </code>
/// </summary>
unit ms.shared.events;

{$SCOPEDENUMS ON}
{$I mormot.defines.inc}
{$WARN SYMBOL_PLATFORM OFF}
{$WARN UNIT_PLATFORM OFF}

interface

uses
  System.Classes,
  System.SysUtils,
  System.SyncObjs,
  mormot.core.base,
  mormot.core.os,
  mormot.orm.core,
  mormot.rest.http.client,
  mormot.soa.client,
  mormot.soa.core,
  ms.shared.api;

const
  /// <summary>
  ///   Maximum number of pending events kept in the in-memory queue. When exceeded, the oldest
  ///   event is dropped to make room. Same sizing rationale as <c>ms.shared.logclient</c>.
  /// </summary>
  MAX_EVENT_QUEUE_SIZE = 10000;

  /// <summary>
  ///   How often the worker checks for pending events when none arrive (milliseconds).
  /// </summary>
  EVENT_FLUSH_INTERVAL_MS = 100;

  /// <summary>
  ///   Backoff applied after a failed publish round before retrying (milliseconds). Keeps the
  ///   worker from busy-looping when <c>ms.events</c> is down.
  /// </summary>
  EVENT_RETRY_BACKOFF_MS = 1000;

  /// <summary>
  ///   Maximum number of publish attempts per event before the worker gives up and drops the
  ///   item. Five tries with a one-second backoff covers most transient outages without letting
  ///   one bad event stall the whole queue.
  /// </summary>
  MAX_PUBLISH_ATTEMPTS = 5;

type

  /// <summary>
  ///   Internal queue slot. Mirrors the <c>IEventPublisher.Publish</c> arguments plus a per-item
  ///   attempt counter for the retry policy.
  /// </summary>
  TEventQueueItem = record
    EventType: RawUtf8;
    PayloadJson: RawJson;
    SchemaVersion: Integer;
    Attempts: Integer;
  end;

  /// <summary>
  ///   Forward declaration so the worker thread can hold a reference to its owner.
  /// </summary>
  TEventPublisher = class;

  /// <summary>
  ///   Background worker thread that drains the event queue and forwards each item to the
  ///   central <c>ms.events</c> service. Owned by <c>TEventPublisher</c>; do not create directly.
  /// </summary>
  TEventPublisherThread = class(TThread)
  strict private
    FOwner: TEventPublisher;
    FWakeUp: TEvent;
  protected
    /// <summary>
    ///   Drains the queue in a loop until the thread is terminated. Sleeps on <c>FWakeUp</c>
    ///   between idle iterations and after publish failures.
    /// </summary>
    procedure Execute; override;
  public
    constructor Create(
      aOwner: TEventPublisher
      );
    destructor Destroy; override;

    /// <summary>
    ///   Signals the worker that new entries are available so it returns from <c>WaitFor</c>
    ///   without waiting for the next periodic tick.
    /// </summary>
    procedure WakeUp;
  end;

  /// <summary>
  ///   Per-service event publisher client. Wraps a persistent WebSocket connection to
  ///   <c>ms.events</c> and a background queue so the producing thread never blocks on the
  ///   network.
  /// </summary>
  TEventPublisher = class
  strict private
    FProducerService: RawUtf8;
    FHost: RawUtf8;
    FPort: RawUtf8;
    FClient: TRestHttpClientWebsockets;
    FPublisher: IEventPublisher;
    FQueue: array of TEventQueueItem;
    FQueueHead: PtrInt;
    FQueueCount: PtrInt;
    FQueueLock: TRTLCriticalSection;
    FThread: TEventPublisherThread;
    FStarted: boolean;
  public

    /// <summary>
    ///   Creates the publisher. Does not start shipping until <c>Start</c> is called.
    /// </summary>
    /// <param name="aProducerService">
    ///   Producing service identifier (e.g. <c>SERVICE_POSTS</c>) -- written into every event.
    /// </param>
    /// <param name="aHost">
    ///   Hostname of <c>ms.events</c>.
    /// </param>
    /// <param name="aPort">
    ///   TCP port of <c>ms.events</c>.
    /// </param>
    constructor Create(
      const aProducerService, aHost, aPort: RawUtf8
      );

    /// <summary>
    ///   Stops the worker thread (if running) and frees the WebSocket client.
    /// </summary>
    destructor Destroy; override;

    /// <summary>
    ///   Starts the background worker thread. Safe to call multiple times -- subsequent calls
    ///   are no-ops.
    /// </summary>
    procedure Start;

    /// <summary>
    ///   Signals the worker to stop and waits for it to drain in-flight work. Items still in the
    ///   queue at this point are abandoned (consumers can recover them via cursor on reconnect
    ///   only if they were already published; truly-in-queue items are lost on shutdown).
    /// </summary>
    procedure Stop;

    /// <summary>
    ///   Synchronously enqueues an event for asynchronous publication. Returns immediately;
    ///   network failures are handled by the worker. When the queue is full the oldest pending
    ///   event is dropped to make room.
    /// </summary>
    procedure Enqueue(
      const aEventType: RawUtf8;
      const aPayloadJson: RawJson;
      aSchemaVersion: Integer
      );

    /// <summary>
    ///   Worker callback: dequeues exactly one item. Returns <c>False</c> if the queue is empty.
    ///   One-at-a-time draining is deliberate -- on publish failure the item is requeued at the
    ///   head and the rest of the queue stays untouched for the next attempt.
    /// </summary>
    function DequeueOne(
      out aItem: TEventQueueItem
      ): boolean;

    /// <summary>
    ///   Worker callback: re-inserts a failed item at the head of the queue with its
    ///   <c>Attempts</c> counter already incremented. Drops the item silently when the counter
    ///   reaches <c>MAX_PUBLISH_ATTEMPTS</c>.
    /// </summary>
    procedure RequeueFailed(
      const aItem: TEventQueueItem
      );

    /// <summary>
    ///   Worker callback: lazily resolves <c>IEventPublisher</c> from <c>FClient</c>, creating
    ///   the WebSocket client on demand. Returns <c>False</c> when <c>ms.events</c> is
    ///   unreachable so the worker can back off and retry.
    /// </summary>
    function EnsurePublisher: boolean;

    /// <summary>
    ///   Drops the cached client + interface so the next <c>EnsurePublisher</c> rebuilds the
    ///   WebSocket connection. Called after a publish failure that suggests the socket has gone
    ///   stale.
    /// </summary>
    procedure ResetClient;

    property ProducerService: RawUtf8
      read FProducerService;
    property Publisher: IEventPublisher
      read FPublisher;
  end;

implementation

{ TEventPublisherThread }

constructor TEventPublisherThread.Create(
  aOwner: TEventPublisher
  );
begin
  FOwner := aOwner;
  FWakeUp := TEvent.Create(nil, False, False, '');
  FreeOnTerminate := False;
  inherited Create(False);
end;

destructor TEventPublisherThread.Destroy;
begin
  FWakeUp.Free;
  inherited Destroy;
end;

procedure TEventPublisherThread.WakeUp;
begin
  FWakeUp.SetEvent;
end;

procedure TEventPublisherThread.Execute;
var
  Item: TEventQueueItem;
  PublishOk: boolean;
begin
  while not Terminated do
  begin
    if FOwner.DequeueOne(Item) then
    begin
      PublishOk := False;
      try
        if FOwner.EnsurePublisher then
        begin
          FOwner.Publisher.Publish(
            Item.EventType,
            Item.PayloadJson,
            FOwner.ProducerService,
            Item.SchemaVersion);
          PublishOk := True;
        end;
      except
        // Network glitch, server restart, dropped socket -- treat as transient and retry.
        // Reset the client so the next attempt rebuilds the WebSocket from scratch.
        FOwner.ResetClient;
      end;
      if not PublishOk then
      begin
        FOwner.RequeueFailed(Item);
        // Back off so we don't burn CPU when ms.events is down. WaitFor returns early if the
        // producer enqueues new work or Stop is called.
        FWakeUp.WaitFor(EVENT_RETRY_BACKOFF_MS);
      end;
    end
    else
      // Idle -- sleep until woken up by Enqueue or until the periodic timer ticks.
      FWakeUp.WaitFor(EVENT_FLUSH_INTERVAL_MS);
  end;
end;

{ TEventPublisher }

constructor TEventPublisher.Create(
  const aProducerService, aHost, aPort: RawUtf8
  );
begin
  inherited Create;
  FProducerService := aProducerService;
  FHost := aHost;
  FPort := aPort;
  SetLength(FQueue, MAX_EVENT_QUEUE_SIZE);
  InitializeCriticalSection(FQueueLock);
end;

destructor TEventPublisher.Destroy;
begin
  Stop;
  DeleteCriticalSection(FQueueLock);
  FPublisher := nil;
  FreeAndNil(FClient);
  inherited Destroy;
end;

procedure TEventPublisher.Start;
begin
  if FStarted then
    Exit;
  FThread := TEventPublisherThread.Create(self);
  FStarted := True;
end;

procedure TEventPublisher.Stop;
begin
  if not FStarted then
    Exit;
  FStarted := False;
  if FThread <> nil then
  begin
    FThread.Terminate;
    FThread.WakeUp;
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
end;

procedure TEventPublisher.Enqueue(
  const aEventType: RawUtf8;
  const aPayloadJson: RawJson;
  aSchemaVersion: Integer
  );
var
  Slot: PtrInt;
begin
  EnterCriticalSection(FQueueLock);
  try
    if FQueueCount >= MAX_EVENT_QUEUE_SIZE then
    begin
      // Drop the oldest entry to make room. Matches the TLogShipper backpressure policy.
      FQueueHead := (FQueueHead + 1) mod MAX_EVENT_QUEUE_SIZE;
      Dec(FQueueCount);
    end;
    Slot := (FQueueHead + FQueueCount) mod MAX_EVENT_QUEUE_SIZE;
    FQueue[Slot].EventType := aEventType;
    FQueue[Slot].PayloadJson := aPayloadJson;
    FQueue[Slot].SchemaVersion := aSchemaVersion;
    FQueue[Slot].Attempts := 0;
    Inc(FQueueCount);
  finally
    LeaveCriticalSection(FQueueLock);
  end;
  if FThread <> nil then
    FThread.WakeUp;
end;

function TEventPublisher.DequeueOne(
  out aItem: TEventQueueItem
  ): boolean;
begin
  EnterCriticalSection(FQueueLock);
  try
    if FQueueCount = 0 then
      Exit(False);
    aItem := FQueue[FQueueHead];
    FQueueHead := (FQueueHead + 1) mod MAX_EVENT_QUEUE_SIZE;
    Dec(FQueueCount);
    Result := True;
  finally
    LeaveCriticalSection(FQueueLock);
  end;
end;

procedure TEventPublisher.RequeueFailed(
  const aItem: TEventQueueItem
  );
var
  NewHead: PtrInt;
  Retry: TEventQueueItem;
begin
  Retry := aItem;
  Inc(Retry.Attempts);
  if Retry.Attempts >= MAX_PUBLISH_ATTEMPTS then
    // Poison-pill guard: drop after enough tries so one bad event cannot stall the queue.
    Exit;
  EnterCriticalSection(FQueueLock);
  try
    if FQueueCount >= MAX_EVENT_QUEUE_SIZE then
    begin
      // Queue is full -- drop the newest entry instead of the retry, since the retry is older
      // and has already paid its serialization cost.
      Dec(FQueueCount);
    end;
    NewHead := (FQueueHead - 1 + MAX_EVENT_QUEUE_SIZE) mod MAX_EVENT_QUEUE_SIZE;
    FQueueHead := NewHead;
    FQueue[NewHead] := Retry;
    Inc(FQueueCount);
  finally
    LeaveCriticalSection(FQueueLock);
  end;
end;

function TEventPublisher.EnsurePublisher: boolean;
var
  ClientModel: TOrmModel;
  UpgradeError: RawUtf8;
begin
  if FPublisher <> nil then
    Exit(True);
  if FClient = nil then
  begin
    try
      ClientModel := TOrmModel.Create([], 'api');
      FClient := TRestHttpClientWebsockets.Create(FHost, FPort, ClientModel);
      FClient.Model.Owner := FClient;
      UpgradeError := FClient.WebSocketsUpgrade(WEBSOCKETS_KEY);
      if UpgradeError <> '' then
      begin
        // Server unreachable / handshake rejected -- drop the half-built client so the next
        // attempt starts clean.
        FreeAndNil(FClient);
        Exit(False);
      end;
      FClient.ServiceRegister([TypeInfo(IEventPublisher)], sicShared);
      TServiceFactoryClient(FClient.Services.Info(TypeInfo(IEventPublisher))).
        ResultAsJsonObjectWithoutResult := True;
    except
      FreeAndNil(FClient);
      Exit(False);
    end;
  end;
  Result := FClient.Services.Resolve(IEventPublisher, FPublisher);
  if not Result then
    FPublisher := nil;
end;

procedure TEventPublisher.ResetClient;
begin
  FPublisher := nil;
  FreeAndNil(FClient);
end;

end.
