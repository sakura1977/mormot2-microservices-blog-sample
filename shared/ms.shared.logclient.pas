/// <summary>
///   Background log shipper used by every microservice to forward its log lines to <c>ms.logs</c>.
///
///   The shipper has three parts:
///   <list>
///   <item>
///     <c>EchoCustom</c> callback (registered on <c>TSynLog.Family</c>): runs synchronously inside the log lock,
///     so it must do the absolute minimum -- it just enqueues a copy of the entry into a thread-safe ring buffer.
///   </item>
///   <item>
///     <c>TLogShipperThread</c>: a background TThread that periodically drains the queue, batches up to
///     <c>MAX_BATCH</c> entries, and ships them via <c>ILogIngestion.AppendBatch</c>.
///   </item>
///   <item>
///     A best-effort error policy: if <c>ms.logs</c> is unreachable, the batch is dropped and the queue keeps
///     growing up to <c>MAX_QUEUE</c> entries. Older entries are evicted to make room. Local file logging in
///     each service stays unchanged so nothing is permanently lost.
///   </item>
///   </list>
///
///   Usage from <c>TMicroService</c>:
///   <code>
///   FLogShipper := TLogShipper.Create(FServiceName, LogsHost, LogsPort);
///   FLogShipper.Attach;  // installs the EchoCustom callback
///   ...
///   FLogShipper.Detach;  // before process exit
///   FreeAndNil(FLogShipper);
///   </code>
/// </summary>
unit ms.shared.logclient;

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
  mormot.core.datetime,
  mormot.core.log,
  mormot.core.os,
  mormot.core.rtti,
  mormot.core.text,
  mormot.orm.base,
  mormot.orm.core,
  mormot.rest.core,
  mormot.rest.http.client,
  mormot.soa.client,
  mormot.soa.core,
  ms.shared.api;

const
  /// <summary>
  ///   Maximum number of pending entries kept in the in-memory queue. When this is exceeded, the oldest entries
  ///   are dropped to make room for newer ones. Sizing it at 10 000 covers a few seconds of even very chatty
  ///   services and keeps the memory cost trivial.
  /// </summary>
  MAX_QUEUE_SIZE = 10000;

  /// <summary>
  ///   Maximum number of entries shipped per <c>ILogIngestion.AppendBatch</c> call. Higher batches reduce HTTP
  ///   overhead but make each call slower; 100 is a reasonable middle ground.
  /// </summary>
  MAX_BATCH_SIZE = 100;

  /// <summary>
  ///   How often the background thread checks for queued entries when no new ones arrive (milliseconds).
  /// </summary>
  FLUSH_INTERVAL_MS = 250;

type

  /// <summary>
  ///   Forwards declared so the thread class can hold a reference to its owner.
  /// </summary>
  TLogShipper = class;

  /// <summary>
  ///   Background worker thread that drains the queue and ships batches to <c>ms.logs</c>. Owned by
  ///   <c>TLogShipper</c>; do not create directly.
  /// </summary>
  TLogShipperThread = class(TThread)
  strict private
    /// <summary>
    ///   The owning shipper instance.
    /// </summary>
    FOwner: TLogShipper;

    /// <summary>
    ///   Event used to wake the thread when new entries are enqueued.
    /// </summary>
    FWakeUp: TEvent;
  protected

    /// <summary>
    ///   Drains the queue in a loop until the thread is terminated. Sleeps on <c>FWakeUp</c> between batches.
    /// </summary>
    procedure Execute; override;
  public

    /// <summary>
    ///   Creates the worker thread for the given owner. The thread starts running immediately.
    /// </summary>
    /// <param name="aOwner">
    ///   The owning <c>TLogShipper</c>.
    /// </param>
    constructor Create(
      aOwner: TLogShipper
      );

    /// <summary>
    ///   Frees the wake-up event after the thread has stopped.
    /// </summary>
    destructor Destroy; override;

    /// <summary>
    ///   Signals the worker that new entries are available so it wakes from <c>WaitFor</c> immediately.
    /// </summary>
    procedure WakeUp;
  end;

  /// <summary>
  ///   Per-service log shipper. Wires the <c>EchoCustom</c> hook on <c>TSynLog.Family</c> to a thread-safe
  ///   queue and a background flush thread that ships batches to <c>ms.logs</c> via <c>ILogIngestion</c>.
  /// </summary>
  TLogShipper = class
  strict private
    /// <summary>
    ///   The producing service name -- written into every queued entry.
    /// </summary>
    FServiceName: RawUtf8;

    /// <summary>
    ///   Hostname of the central <c>ms.logs</c> service.
    /// </summary>
    FHost: RawUtf8;

    /// <summary>
    ///   TCP port of the central <c>ms.logs</c> service.
    /// </summary>
    FPort: RawUtf8;

    /// <summary>
    ///   The HTTP REST client connected to <c>ms.logs</c>. Created lazily on first successful flush.
    /// </summary>
    FClient: TRestHttpClient;

    /// <summary>
    ///   The resolved <c>ILogIngestion</c> interface from <c>FClient</c>.
    /// </summary>
    FIngestion: ILogIngestion;

    /// <summary>
    ///   In-memory ring buffer of pending entries. Size is bounded by <c>MAX_QUEUE_SIZE</c>.
    /// </summary>
    FQueue: TLogEntryIngestDtoArray;

    /// <summary>
    ///   Index of the next entry to dequeue.
    /// </summary>
    FQueueHead: PtrInt;

    /// <summary>
    ///   Number of entries currently in the queue.
    /// </summary>
    FQueueCount: PtrInt;

    /// <summary>
    ///   Critical section guarding the queue.
    /// </summary>
    FQueueLock: TRTLCriticalSection;

    /// <summary>
    ///   Background flush thread.
    /// </summary>
    FThread: TLogShipperThread;

    /// <summary>
    ///   Set to true once <c>Attach</c> has installed the EchoCustom hook.
    /// </summary>
    FAttached: boolean;

    /// <summary>
    ///   The previous EchoCustom value, restored on <c>Detach</c>.
    /// </summary>
    FPreviousEcho: TOnTextWriterEcho;

    /// <summary>
    ///   The <c>EchoCustom</c> callback. Runs on the calling thread inside the log lock; must not block.
    /// </summary>
    /// <param name="aSender">
    ///   The text writer (provided by mORMot2, unused here).
    /// </param>
    /// <param name="aLevel">
    ///   The log level of the entry being written.
    /// </param>
    /// <param name="aText">
    ///   The fully formatted log line.
    /// </param>
    /// <returns>
    ///   Always <c>True</c> to continue logging.
    /// </returns>
    function OnLogEcho(
      aSender: TEchoWriter;
      aLevel: TSynLogLevel;
      const aText: RawUtf8
      ): boolean;
  public

    /// <summary>
    ///   Resolves <c>ILogIngestion</c> from <c>FClient</c>, creating the client on demand. Returns false if the
    ///   server is unreachable; callers must drop the batch in that case.
    /// </summary>
    /// <returns>
    ///   <c>True</c> if the interface is now resolved and ready to use.
    /// </returns>
    function EnsureIngestion: boolean;

    /// <summary>
    ///   Creates the shipper. Does not start shipping until <c>Attach</c> is called.
    /// </summary>
    /// <param name="aServiceName">
    ///   The producing service identifier (e.g. <c>ms.posts</c>).
    /// </param>
    /// <param name="aHost">
    ///   Hostname of <c>ms.logs</c>.
    /// </param>
    /// <param name="aPort">
    ///   TCP port of <c>ms.logs</c>.
    /// </param>
    constructor Create(
      const aServiceName, aHost, aPort: RawUtf8
      );

    /// <summary>
    ///   Detaches the EchoCustom hook (if attached), stops the worker thread, and frees the HTTP client.
    /// </summary>
    destructor Destroy; override;

    /// <summary>
    ///   Installs the EchoCustom callback on <c>TSynLog.Family</c> and starts the background flush thread.
    ///   Safe to call multiple times -- subsequent calls are no-ops.
    /// </summary>
    procedure Attach;

    /// <summary>
    ///   Restores the previous EchoCustom callback, signals the worker to stop, and waits for it to finish.
    /// </summary>
    procedure Detach;

    /// <summary>
    ///   Pulls up to <c>MAX_BATCH_SIZE</c> entries from the queue. Used by the worker thread.
    /// </summary>
    /// <param name="aBatch">
    ///   Output: the dequeued entries (empty if the queue was empty).
    /// </param>
    procedure DequeueBatch(
      out aBatch: TLogEntryIngestDtoArray
      );

    /// <summary>
    ///   The producing service name passed to <c>Create</c>.
    /// </summary>
    property ServiceName: RawUtf8
      read FServiceName;

    property Ingestion: ILogIngestion
      read FIngestion;
  end;

implementation

constructor TLogShipperThread.Create(
  aOwner: TLogShipper
  );
begin
  FOwner := aOwner;
  FWakeUp := TEvent.Create(nil, False, False, '');
  FreeOnTerminate := False;
  inherited Create(False);
end;

destructor TLogShipperThread.Destroy;
begin
  FWakeUp.Free;
  inherited Destroy;
end;

procedure TLogShipperThread.WakeUp;
begin
  FWakeUp.SetEvent;
end;

procedure TLogShipperThread.Execute;
var
  Batch: TLogEntryIngestDtoArray;
begin
  while not Terminated do
  begin
    FOwner.DequeueBatch(Batch);
    if Length(Batch) > 0 then
    begin
      try
        if FOwner.EnsureIngestion then
          FOwner.Ingestion.AppendBatch(Batch);
      except
        // Best-effort: drop the batch on any failure (server down, network glitch, etc.).
        // Local file logging on the producing service is unaffected.
      end;
    end
    else
      // Nothing to flush -- sleep until woken up by Enqueue or until the periodic timer ticks.
      FWakeUp.WaitFor(FLUSH_INTERVAL_MS);
  end;
end;

constructor TLogShipper.Create(
  const aServiceName, aHost, aPort: RawUtf8
  );
begin
  inherited Create;
  FServiceName := aServiceName;
  FHost := aHost;
  FPort := aPort;
  SetLength(FQueue, MAX_QUEUE_SIZE);
  InitializeCriticalSection(FQueueLock);
end;

destructor TLogShipper.Destroy;
begin
  Detach;
  DeleteCriticalSection(FQueueLock);
  FIngestion := nil;
  FreeAndNil(FClient);
  inherited Destroy;
end;

procedure TLogShipper.Attach;
begin
  if FAttached then
    Exit;
  FPreviousEcho := TSynLog.Family.EchoCustom;
  TSynLog.Family.EchoCustom := OnLogEcho;
  FThread := TLogShipperThread.Create(self);
  FAttached := True;
end;

procedure TLogShipper.Detach;
begin
  if not FAttached then
    Exit;
  FAttached := False;
  // Restore the previous echo before tearing down the thread so no new entries get queued.
  TSynLog.Family.EchoCustom := FPreviousEcho;
  if FThread <> nil then
  begin
    FThread.Terminate;
    FThread.WakeUp;
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
end;

function TLogShipper.OnLogEcho(
  aSender: TEchoWriter;
  aLevel: TSynLogLevel;
  const aText: RawUtf8
  ): boolean;
var
  Slot: PtrInt;
begin
  Result := True;
  // Skip our own thread to avoid infinite recursion: when the worker thread later calls AppendBatch,
  // mORMot2 may itself emit log entries about the HTTP request, which would re-enter OnLogEcho on the
  // worker thread and re-queue forever.
  if (FThread <> nil) and (TThread.CurrentThread.ThreadID = FThread.ThreadID) then
    Exit;
  EnterCriticalSection(FQueueLock);
  try
    if FQueueCount >= MAX_QUEUE_SIZE then
    begin
      // Drop the oldest entry to make room. The dropped entry is the one currently at FQueueHead.
      FQueueHead := (FQueueHead + 1) mod MAX_QUEUE_SIZE;
      Dec(FQueueCount);
    end;
    Slot := (FQueueHead + FQueueCount) mod MAX_QUEUE_SIZE;
    FQueue[Slot].ServiceName := FServiceName;
    FQueue[Slot].Timestamp := NowUtc;
    FQueue[Slot].Level := ord(aLevel);
    FQueue[Slot].Message := aText;
    Inc(FQueueCount);
  finally
    LeaveCriticalSection(FQueueLock);
  end;
  if FThread <> nil then
    FThread.WakeUp;
end;

procedure TLogShipper.DequeueBatch(
  out aBatch: TLogEntryIngestDtoArray
  );
var
  TakeCount, BatchIdx: PtrInt;
begin
  aBatch := nil;
  EnterCriticalSection(FQueueLock);
  try
    TakeCount := FQueueCount;
    if TakeCount > MAX_BATCH_SIZE then
      TakeCount := MAX_BATCH_SIZE;
    if TakeCount = 0 then
      Exit;
    SetLength(aBatch, TakeCount);
    for BatchIdx := 0 to TakeCount - 1 do
    begin
      aBatch[BatchIdx] := FQueue[FQueueHead];
      FQueueHead := (FQueueHead + 1) mod MAX_QUEUE_SIZE;
    end;
    Dec(FQueueCount, TakeCount);
  finally
    LeaveCriticalSection(FQueueLock);
  end;
end;

function TLogShipper.EnsureIngestion: boolean;
var
  ClientModel: TOrmModel;
begin
  if FIngestion <> nil then
    Exit(True);
  if FClient = nil then
  begin
    try
      ClientModel := TOrmModel.Create([], 'api');
      FClient := TRestHttpClient.Create(FHost, FPort, ClientModel);
      FClient.Model.Owner := FClient;
      FClient.ServiceRegister([TypeInfo(ILogIngestion)], sicShared);
      TServiceFactoryClient(FClient.Services.Info(TypeInfo(ILogIngestion))).
        ResultAsJsonObjectWithoutResult := True;
    except
      FreeAndNil(FClient);
      Exit(False);
    end;
  end;
  Result := FClient.Services.Resolve(ILogIngestion, FIngestion);
  if not Result then
    FIngestion := nil;
end;

end.
