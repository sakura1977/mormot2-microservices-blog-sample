/// <summary>
///   Interface-based service implementation for the Comments microservice.
///   Implements the <c>IComment</c> contract with moderation workflow.
///
///   Demonstrates the selective-field update pattern in mORMot2:
///   - <c>IRestOrm.Update(Rec, 'Field1,Field2')</c>: the second parameter is a CSV list of field names to update.
///     Only those columns are written to SQLite, which is more efficient than updating all fields and avoids
///     accidentally overwriting fields that weren't intended to change.
///   - Moderation workflow: comments start as pending (status 0), and are approved (1) or rejected (2) by an author.
///     Only approved comments are returned by <c>GetByPost</c>.
///
///   See <c>ms.users.server.pas</c> for detailed explanations of the basic CRUD and JSON parsing patterns used here.
/// </summary>
unit ms.comments.server;

{$SCOPEDENUMS ON}
{$I mormot.defines.inc}
{$WARN SYMBOL_PLATFORM OFF}
{$WARN UNIT_PLATFORM OFF}

interface

uses
  System.Classes,
  System.SyncObjs,
  System.SysUtils,
  mormot.core.base,
  mormot.core.datetime,
  mormot.core.json,
  mormot.core.os,
  mormot.core.text,
  mormot.core.unicode,
  mormot.core.variants,
  mormot.orm.base,
  mormot.orm.core,
  mormot.rest.core,
  mormot.rest.http.client,
  mormot.rest.server,
  mormot.rest.sqlite3,
  mormot.soa.client,
  mormot.soa.core,
  mormot.soa.server,
  ms.comments.model,
  ms.shared,
  ms.shared.api,
  ms.shared.service;

const
  /// <summary>
  ///   Stable consumer identifier used as cursor key in <c>ms.events</c>. Must not change --
  ///   ACKed cursor positions are stored under this name in <c>TOrmConsumerCursor</c>.
  /// </summary>
  CONSUMER_COMMENTS_CASCADE = 'comments.cascade';

  /// <summary>
  ///   Period between reconnect attempts when the WebSocket subscription to <c>ms.events</c>
  ///   is not currently established (milliseconds). Five seconds keeps the log noise modest
  ///   during a long bus outage while still picking up the bus quickly after it returns.
  /// </summary>
  CASCADE_RECONNECT_INTERVAL_MS = 5000;

type

  /// <summary>
  ///   Implements the <c>IComment</c> interface for comment CRUD and moderation.
  /// </summary>
  TCommentService = class(TInterfacedObject, IComment)
  strict private

    /// <summary>
    ///   ORM interface for database access.
    /// </summary>
    FOrm: IRestOrm;
  public

    /// <summary>
    ///   Creates the comment service with an injected ORM interface.
    /// </summary>
    /// <param name="aOrm">
    ///   The ORM interface for database operations.
    /// </param>
    constructor Create(
      const aOrm: IRestOrm
      );

    /// <summary>
    ///   Adds a new comment to a post with status pending.
    /// </summary>
    /// <param name="aPostId">
    ///   The post to comment on (must be greater than 0).
    /// </param>
    /// <param name="aData">
    ///   Comment data with at least <c>Body</c> (required).
    /// </param>
    /// <returns>
    ///   The new comment ID, or 0 if validation failed.
    /// </returns>
    function Add(
      aPostId: TID;
      const aData: TCommentCreateDto
      ): TID;

    /// <summary>
    ///   Approves a pending comment, making it publicly visible.
    /// </summary>
    /// <param name="aId">
    ///   The comment's record ID.
    /// </param>
    /// <param name="aModeratedBy">
    ///   The author ID who approved the comment.
    /// </param>
    /// <returns>
    ///   True if the comment was found and approved.
    /// </returns>
    function Approve(
      aId, aModeratedBy: TID
      ): boolean;

    /// <summary>
    ///   Retrieves all approved comments for a post.
    /// </summary>
    /// <param name="aPostId">
    ///   The post's record ID.
    /// </param>
    /// <returns>
    ///   Array of approved comments.
    /// </returns>
    function GetByPost(
      aPostId: TID
      ): TCommentDtoArray;

    /// <summary>
    ///   Retrieves all comments awaiting moderation.
    /// </summary>
    /// <returns>
    ///   Array of pending comments.
    /// </returns>
    function GetPending: TCommentDtoArray;

    /// <summary>
    ///   Rejects a pending comment, hiding it from public view.
    /// </summary>
    /// <param name="aId">
    ///   The comment's record ID.
    /// </param>
    /// <param name="aModeratedBy">
    ///   The author ID who rejected the comment.
    /// </param>
    /// <returns>
    ///   True if the comment was found and rejected.
    /// </returns>
    function Reject(
      aId, aModeratedBy: TID
      ): boolean;

    /// <summary>
    ///   Deletes a comment permanently.
    /// </summary>
    /// <param name="aId">
    ///   The comment's record ID.
    /// </param>
    /// <returns>
    ///   True if the DELETE statement executed successfully.
    /// </returns>
    function Remove(
      aId: TID
      ): boolean;
  end;

  /// <summary>
  ///   Subscriber callback for the <c>comments.cascade</c> consumer (ADR-0001). Receives
  ///   every event from <c>ms.events</c> and is responsible for the local cleanup that keeps
  ///   the comments DB consistent with deleted posts. On <c>EVENT_POST_DELETED</c> it parses
  ///   the <c>postId</c> from the payload and runs <c>DELETE FROM TOrmBlogComment WHERE
  ///   PostId=?</c> -- which is naturally idempotent so replays after a reconnect cause no
  ///   harm. Every event is acknowledged so the persisted cursor advances and we don't keep
  ///   re-receiving handled events.
  /// </summary>
  TCommentCascadeConsumer = class(TInterfacedObject, IEventStreamCallback)
  strict private
    FOrm: IRestOrm;
    FStream: IEventStream;
    FShutdown: boolean;
  public

    /// <summary>
    ///   Wires the consumer to its local ORM (for cascade DELETEs) and to the upstream
    ///   <c>IEventStream</c> proxy (for <c>Acknowledge</c> calls). Both are required.
    /// </summary>
    constructor Create(
      const aOrm: IRestOrm;
      const aStream: IEventStream
      );

    /// <summary>
    ///   Invoked by <c>ms.events</c> for every event in the consumer's stream. Filters on
    ///   <c>EVENT_POST_DELETED</c>, parses <c>postId</c> from the JSON payload, deletes the
    ///   matching comments rows and finally <c>Acknowledge</c>s so the cursor advances.
    ///   Other event types are ACKed without further action. Returns immediately if
    ///   <c>Shutdown</c> has been called -- avoids the 5..30 s hang we used to see on the WS
    ///   reader thread when ms.events died first and a stale OnEvent still tried to call back.
    /// </summary>
    procedure OnEvent(
      const aEvent: TEventDto
      );

    /// <summary>
    ///   Called by <c>TCommentsServer.DoFinalize</c> at the very start of teardown. Sets a
    ///   one-way flag that <c>OnEvent</c> checks before doing any work, so in-flight callbacks
    ///   on the WebSocket reader thread don't try to talk back to a dying bus.
    /// </summary>
    procedure Shutdown;
  end;

  /// <summary>
  ///   Forward declaration: the reconnect thread holds a back-reference to the server.
  /// </summary>
  TCommentsServer = class;

  /// <summary>
  ///   Background worker that periodically retries the cascade subscription to
  ///   <c>ms.events</c> while it is not currently connected. Owned by <c>TCommentsServer</c>;
  ///   started in <c>SetupServices</c>, stopped in <c>DoFinalize</c>.
  /// </summary>
  TCommentsReconnectThread = class(TThread)
  strict private
    FOwner: TCommentsServer;
    FWakeUp: TEvent;
  protected

    /// <summary>
    ///   Sleeps on <c>FWakeUp</c> for <c>CASCADE_RECONNECT_INTERVAL_MS</c> between checks and
    ///   asks the owner to retry whenever no subscription is active. Exits on
    ///   <c>Terminate</c>.
    /// </summary>
    procedure Execute; override;
  public
    constructor Create(
      aOwner: TCommentsServer
      );
    destructor Destroy; override;

    /// <summary>
    ///   Signals the worker so it returns from <c>WaitFor</c> immediately (used during
    ///   shutdown).
    /// </summary>
    procedure WakeUp;
  end;

  /// <summary>
  ///   Microservice server hosting the <c>IComment</c> service implementation.
  /// </summary>
  TCommentsServer = class(TMicroService)
  strict private

    /// <summary>
    ///   The comment service implementation instance.
    /// </summary>
    FCommentImpl: TCommentService;

    /// <summary>
    ///   Long-lived WebSocket client to <c>ms.events</c>. Nil when the bus is disabled or the
    ///   handshake fails -- in that case <c>FEventStream</c>/<c>FEventCallback</c> stay nil and
    ///   the reconnect thread keeps retrying.
    /// </summary>
    FEventsClient: TRestHttpClientWebsockets;

    /// <summary>
    ///   Resolved <c>IEventStream</c> proxy used for <c>Subscribe</c>/<c>Acknowledge</c>/
    ///   <c>Unsubscribe</c>.
    /// </summary>
    FEventStream: IEventStream;

    /// <summary>
    ///   Strong reference to the cascade callback while the subscription is active. Released
    ///   in <c>DoFinalize</c> so mORMot2 can drop the fake-callback pair cleanly.
    /// </summary>
    FEventCallback: IEventStreamCallback;

    /// <summary>
    ///   Typed back-pointer to the same instance as <c>FEventCallback</c>. Held alongside the
    ///   interface so <c>DoFinalize</c> can call <c>Shutdown</c> without round-tripping through
    ///   <c>ObjectFromInterface</c>. Owned via <c>FEventCallback</c>; do not Free directly.
    /// </summary>
    FEventConsumer: TCommentCascadeConsumer;

    /// <summary>
    ///   Guards <c>FEventsClient</c>, <c>FEventStream</c>, <c>FEventCallback</c> against
    ///   concurrent access from the reconnect thread and the shutdown thread.
    /// </summary>
    FConnectionLock: TRTLCriticalSection;

    /// <summary>
    ///   Background worker that retries <c>EnsureEventSubscription</c> every
    ///   <c>CASCADE_RECONNECT_INTERVAL_MS</c> while the subscription is down.
    /// </summary>
    FReconnectThread: TCommentsReconnectThread;

    /// <summary>
    ///   Best-effort: opens a WebSocket connection to <c>ms.events</c>, resolves
    ///   <c>IEventStream</c> and subscribes the cascade consumer with
    ///   <c>aFromEventId = -1</c> (resume from the persisted cursor). On any failure all three
    ///   fields are reset to nil so the next reconnect tick starts from a clean slate.
    ///   Holds <c>FConnectionLock</c>.
    /// </summary>
    procedure TrySubscribeToEvents;
  public

    /// <summary>
    ///   Idempotent: if the cascade subscription is currently down, run another
    ///   <c>TrySubscribeToEvents</c>. Called by the reconnect thread.
    /// </summary>
    procedure EnsureEventSubscription;
  protected

    /// <summary>
    ///   Creates the ORM model with <c>TOrmBlogComment</c>.
    /// </summary>
    /// <returns>
    ///   A new <c>TOrmModel</c> for the comments table.
    /// </returns>
    function CreateModel: TOrmModel; override;

    /// <summary>
    ///   Registers the <c>IComment</c> service implementation and subscribes to the event bus
    ///   for cascade-delete propagation (ADR-0001).
    /// </summary>
    procedure SetupServices; override;

    /// <summary>
    ///   Unsubscribes the cascade consumer and tears down the WebSocket client before the
    ///   inherited shutdown frees the REST server.
    /// </summary>
    procedure DoFinalize; override;
  end;

implementation

function CommentToDto(
  aRec: TOrmBlogComment
  ): TCommentDto;
begin
  Result.ID := aRec.IDValue;
  Result.PostId := aRec.PostId;
  Result.AuthorName := aRec.AuthorName;
  Result.AuthorEmail := aRec.AuthorEmail;
  Result.Body := aRec.Body;
  Result.Status := aRec.Status;
  Result.ModeratedBy := aRec.ModeratedBy;
  Result.ModeratedAt := aRec.ModeratedAt;
  Result.CreatedAt := aRec.CreatedAt;
end;

function CommentsFromQuery(
  const aOrm: IRestOrm;
  const aWhere: RawUtf8
  ): TCommentDtoArray;
var
  Rec: TOrmBlogComment;
  Count: PtrInt;
begin
  Result := nil;
  Count := 0;
  Rec := TOrmBlogComment.CreateAndFillPrepare(aOrm, aWhere);
  try
    SetLength(Result, Rec.FillTable.RowCount);
    while Rec.FillOne do
    begin
      Result[Count] := CommentToDto(Rec);
      Inc(Count);
    end;
    SetLength(Result, Count);
  finally
    Rec.Free;
  end;
end;

function TCommentService.Add(
  aPostId: TID;
  const aData: TCommentCreateDto
  ): TID;
var
  Rec: TOrmBlogComment;
begin
  if (aPostId <= 0) or (aData.Body = '') then
    Exit(0);
  Rec := TOrmBlogComment.Create;
  try
    Rec.PostId := aPostId;
    Rec.AuthorName := aData.AuthorName;
    Rec.AuthorEmail := aData.AuthorEmail;
    Rec.Body := aData.Body;
    Rec.Status := COMMENT_STATUS_PENDING;
    Rec.CreatedAt := NowUtc;
    Result := FOrm.Add(Rec, True);
  finally
    Rec.Free;
  end;
end;

function TCommentService.Approve(
  aId, aModeratedBy: TID
  ): boolean;
var
  Rec: TOrmBlogComment;
begin
  Rec := TOrmBlogComment.Create;
  try
    if not FOrm.Retrieve(aId, Rec) then
      Exit(False);
    Rec.Status := COMMENT_STATUS_APPROVED;
    Rec.ModeratedBy := aModeratedBy;
    Rec.ModeratedAt := NowUtc;
    Result := FOrm.Update(Rec, 'Status,ModeratedBy,ModeratedAt');
  finally
    Rec.Free;
  end;
end;

constructor TCommentService.Create(
  const aOrm: IRestOrm
  );
begin
  inherited Create;
  FOrm := aOrm;
end;

function TCommentService.GetByPost(
  aPostId: TID
  ): TCommentDtoArray;
begin
  Result := CommentsFromQuery(FOrm, FormatUtf8('PostId=% AND Status=% ORDER BY RowID ASC',
    [aPostId, COMMENT_STATUS_APPROVED]));
end;

function TCommentService.GetPending: TCommentDtoArray;
begin
  Result := CommentsFromQuery(FOrm, FormatUtf8('Status=%', [COMMENT_STATUS_PENDING]));
end;

function TCommentService.Reject(
  aId, aModeratedBy: TID
  ): boolean;
var
  Rec: TOrmBlogComment;
begin
  Rec := TOrmBlogComment.Create;
  try
    if not FOrm.Retrieve(aId, Rec) then
      Exit(False);
    Rec.Status := COMMENT_STATUS_REJECTED;
    Rec.ModeratedBy := aModeratedBy;
    Rec.ModeratedAt := NowUtc;
    Result := FOrm.Update(Rec, 'Status,ModeratedBy,ModeratedAt');
  finally
    Rec.Free;
  end;
end;

function TCommentService.Remove(
  aId: TID
  ): boolean;
begin
  Result := FOrm.Delete(TOrmBlogComment, aId);
end;

{ TCommentCascadeConsumer }

constructor TCommentCascadeConsumer.Create(
  const aOrm: IRestOrm;
  const aStream: IEventStream
  );
begin
  inherited Create;
  FOrm := aOrm;
  FStream := aStream;
end;

procedure TCommentCascadeConsumer.Shutdown;
begin
  FShutdown := True;
end;

procedure TCommentCascadeConsumer.OnEvent(
  const aEvent: TEventDto
  );
var
  Payload: TDocVariantData;
  PostId: TID;
begin
  // OnEvent runs on the WebSocket reader thread of the consumer-side client. Two hazards:
  // (1) any unhandled exception escapes into mORMot's dispatcher, which during shutdown can
  //     crash the process -- the master try/except below is the last-resort guard.
  // (2) calling back into the bus (Acknowledge) over a dying WebSocket blocks for the socket
  //     timeout (we observed 5..30 s) before raising. The Shutdown flag short-circuits the
  //     whole method so a stale callback during teardown returns instantly.
  if FShutdown then
    Exit;
  try
    // Cascade only on PostDeleted. Other event types still need an ACK so the cursor advances
    // and we don't keep re-receiving them on every reconnect.
    if aEvent.EventType = EVENT_POST_DELETED then
    try
      Payload.InitJson(aEvent.PayloadJson, JSON_FAST_FLOAT);
      PostId := Payload.I['postId'];
      if PostId > 0 then
        // DELETE WHERE PostId=? is naturally idempotent: a replayed PostDeleted matches no rows
        // on the second attempt, which is exactly the contract documented for EVENT_POST_DELETED.
        FOrm.Delete(TOrmBlogComment, FormatUtf8('PostId=%', [PostId]));
    except
      // Malformed payload or DB hiccup: swallow so a single poison message cannot stall the
      // cascade. Genuine DB failures are very rare on local SQLite.
    end;
    // Re-check the shutdown flag before talking back to the bus -- the DELETE above may have
    // taken long enough that DoFinalize has flipped the flag in the meantime.
    if FShutdown then
      Exit;
    if FStream <> nil then
    try
      FStream.Acknowledge(CONSUMER_COMMENTS_CASCADE, aEvent.ID);
    except
      // Bus unreachable -- the cursor will be re-resolved on next Subscribe(name, -1, cb)
      // anyway, so dropping a single ACK on shutdown is harmless.
    end;
  except
    // Last-resort guard: any unexpected error stays inside the consumer.
  end;
end;

{ TCommentsReconnectThread }

constructor TCommentsReconnectThread.Create(
  aOwner: TCommentsServer
  );
begin
  FOwner := aOwner;
  FWakeUp := TEvent.Create(nil, False, False, '');
  FreeOnTerminate := False;
  inherited Create(False);
end;

destructor TCommentsReconnectThread.Destroy;
begin
  FWakeUp.Free;
  inherited Destroy;
end;

procedure TCommentsReconnectThread.WakeUp;
begin
  FWakeUp.SetEvent;
end;

procedure TCommentsReconnectThread.Execute;
begin
  while not Terminated do
  begin
    FWakeUp.WaitFor(CASCADE_RECONNECT_INTERVAL_MS);
    if Terminated then
      Break;
    try
      FOwner.EnsureEventSubscription;
    except
      // Connection retries must never crash the worker -- swallow and try again next tick.
    end;
  end;
end;

{ TCommentsServer }

function TCommentsServer.CreateModel: TOrmModel;
begin
  Result := TOrmModel.Create([TOrmBlogComment], MODEL_ROOT);
end;

procedure TCommentsServer.SetupServices;
begin
  FCommentImpl := TCommentService.Create(FRestServer.Orm);
  RegisterService(FCommentImpl, TypeInfo(IComment));
  // Cascade subscription is best-effort: a missing or unreachable bus must not stop the
  // comments service from coming up. ADR-0001 accepts the eventual-consistency window.
  InitializeCriticalSection(FConnectionLock);
  TrySubscribeToEvents;
  // Always start the reconnect thread, even if the initial subscribe succeeded -- it will
  // pick up the slack if the WebSocket drops later (T7).
  FReconnectThread := TCommentsReconnectThread.Create(self);
end;

procedure TCommentsServer.EnsureEventSubscription;
begin
  EnterCriticalSection(FConnectionLock);
  try
    // Quick check under the lock: if the subscription is already live there is nothing to do.
    if FEventStream <> nil then
      Exit;
  finally
    LeaveCriticalSection(FConnectionLock);
  end;
  // Run the actual reconnect outside the quick-check, but TrySubscribeToEvents takes the lock
  // again for the field updates. The outer race is benign: at worst two retries land back to
  // back, and the first one wins because the second sees FEventStream <> nil.
  TrySubscribeToEvents;
end;

procedure TCommentsServer.TrySubscribeToEvents;
var
  EventsHost, EventsPort: RawUtf8;
  ClientModel: TOrmModel;
  UpgradeError: RawUtf8;
  LocalClient: TRestHttpClientWebsockets;
  LocalStream: IEventStream;
  LocalCallback: IEventStreamCallback;
  LocalConsumer: TCommentCascadeConsumer;
begin
  if Config.EventsUrl = '' then
    Exit;
  EventsHost := Config.EventsUrl;
  if IdemPChar(pointer(EventsHost), 'HTTP://') then
    Delete(EventsHost, 1, 7)
  else if IdemPChar(pointer(EventsHost), 'HTTPS://') then
    Delete(EventsHost, 1, 8);
  EventsPort := Split(EventsHost, ':', EventsHost);
  if EventsPort = '' then
  begin
    EventsPort := EventsHost;
    EventsHost := 'localhost';
  end;
  // Build the new connection in local variables FIRST. Only after Subscribe succeeds do we
  // commit them into the FEvents* fields under the lock. That keeps the publishing thread
  // (OnEvent via the WebSocket) from ever observing a partially-initialized state.
  LocalClient := nil;
  LocalStream := nil;
  LocalCallback := nil;
  LocalConsumer := nil;
  try
    ClientModel := TOrmModel.Create([], MODEL_ROOT);
    LocalClient := TRestHttpClientWebsockets.Create(EventsHost, EventsPort, ClientModel);
    LocalClient.Model.Owner := LocalClient;
    UpgradeError := LocalClient.WebSocketsUpgrade(WEBSOCKETS_KEY);
    if UpgradeError <> '' then
    begin
      FreeAndNil(LocalClient);
      Exit;
    end;
    LocalClient.ServiceRegister([TypeInfo(IEventStream)], sicShared);
    TServiceFactoryClient(LocalClient.Services.Info(TypeInfo(IEventStream)))
      .ResultAsJsonObjectWithoutResult := True;
    if not LocalClient.Services.Resolve(IEventStream, LocalStream) then
    begin
      FreeAndNil(LocalClient);
      Exit;
    end;
    // Build the typed consumer first so we can stash a back-pointer; the interface assignment
    // below takes a strong reference, but we keep the typed handle for fast Shutdown access.
    LocalConsumer := TCommentCascadeConsumer.Create(FRestServer.Orm, LocalStream);
    LocalCallback := LocalConsumer;
    // -1 = resume from the persisted TOrmConsumerCursor.LastEventId + 1. On first start the
    // cursor row does not yet exist and ms.events will deliver the full outbox from ID 1.
    LocalStream.Subscribe(CONSUMER_COMMENTS_CASCADE, -1, LocalCallback);
  except
    LocalCallback := nil;
    LocalConsumer := nil;
    LocalStream := nil;
    FreeAndNil(LocalClient);
    Exit;
  end;
  // Commit. If a previous attempt left a half-built client around (shouldn't happen, since
  // EnsureEventSubscription gates on FEventStream), drop it now.
  EnterCriticalSection(FConnectionLock);
  try
    if FEventsClient <> nil then
      FreeAndNil(FEventsClient);
    FEventsClient := LocalClient;
    FEventStream := LocalStream;
    FEventCallback := LocalCallback;
    FEventConsumer := LocalConsumer;
  finally
    LeaveCriticalSection(FConnectionLock);
  end;
end;

procedure TCommentsServer.DoFinalize;
begin
  // Step 1: tell the cascade consumer to short-circuit. Any in-flight OnEvent on the WS
  // reader thread will return immediately instead of trying to call back into a bus that may
  // already be down -- avoids the 5..30 s socket-timeout hang we used to see on stop-all.
  if FEventConsumer <> nil then
    FEventConsumer.Shutdown;
  // Step 2: stop the reconnect worker so it cannot race with the teardown below.
  if FReconnectThread <> nil then
  begin
    FReconnectThread.Terminate;
    FReconnectThread.WakeUp;
    FReconnectThread.WaitFor;
    FreeAndNil(FReconnectThread);
  end;
  // Step 3: drop our references and let the WebSocket client teardown drive CallbackReleased
  // on the server side. We deliberately do NOT call FEventStream.Unsubscribe here -- that
  // POSTs synchronously over a possibly-dying WebSocket and used to block teardown by ~5 s.
  // The framework runs CallbackReleased on the server when the socket closes, which is what
  // actually cleans up the subscriber list on the bus.
  EnterCriticalSection(FConnectionLock);
  try
    FEventConsumer := nil;  // owned via FEventCallback; just drop the back-pointer
    FEventCallback := nil;
    FEventStream := nil;
    FreeAndNil(FEventsClient);
  finally
    LeaveCriticalSection(FConnectionLock);
  end;
  DeleteCriticalSection(FConnectionLock);
  inherited DoFinalize;
end;

end.
