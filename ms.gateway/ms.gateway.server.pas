/// <summary>
///   API Gateway: routes browser requests to backend microservices and serves the SPA web frontend as static files.
///
///   This is the most architecturally interesting service in the project. It demonstrates several advanced mORMot2
///   patterns:
///
///   1. <em>Transparent SOA proxying</em>: The gateway resolves backend service interfaces via
///      <c>TRestHttpClient</c> + <c>Services.Resolve</c>, which returns a <c>TInterfacedObjectFake</c> that
///      transparently forwards method calls as HTTP requests. These fake client objects are then re-registered as
///      server-side services on the gateway's own <c>TRestServerDB</c> via <c>RegisterService</c> -- no manual
///      proxy classes needed. The gateway acts as a pure pass-through for 6 interfaces.
///
///   2. <em>Response aggregation</em> (<c>TBlogService</c>): The <c>IBlog.GetPostFull</c> method queries 4 backend
///      services (posts, users, tags, comments) and merges their responses into one enriched <c>TPostFullDto</c>
///      record.
///
///   3. <em>HTTP request interception</em>: The gateway intercepts the <c>THttpAsyncServer.OnRequest</c> handler to
///      split traffic between API calls (/api/...) and static file serving (SPA frontend from www/ directory).
///
///   4. <em>Client-side service format matching</em>: Backend services use <c>ResultAsJsonObjectWithoutResult</c>,
///      so the gateway's client factories must also set this flag via <c>TServiceFactoryClient</c> to parse
///      responses correctly.
/// </summary>
unit ms.gateway.server;

{$SCOPEDENUMS ON}
{$I mormot.defines.inc}
{$WARN SYMBOL_PLATFORM OFF}
{$WARN UNIT_PLATFORM OFF}

interface

uses
  System.SysUtils,
  mormot.core.base,
  mormot.core.buffers,
  mormot.core.data,
  mormot.core.datetime,
  mormot.core.json,
  mormot.core.log,
  mormot.core.os,
  mormot.core.rtti,
  mormot.core.text,
  mormot.core.unicode,
  mormot.core.variants,
  mormot.net.async,
  mormot.net.http,
  mormot.net.server,
  mormot.net.ws.core,
  mormot.net.ws.async,
  mormot.orm.base,
  mormot.orm.core,
  mormot.rest.client,
  mormot.rest.core,
  mormot.rest.server,
  mormot.rest.sqlite3,
  mormot.rest.http.client,
  mormot.rest.http.server,
  mormot.soa.client,
  mormot.soa.core,
  mormot.soa.server,
  ms.shared,
  ms.shared.api,
  ms.shared.correlation,
  ms.shared.jwt,
  ms.shared.service,
  mormot.core.interfaces;

type

  /// <summary>
  ///   Aggregation service: enriches a post with author, tags, comments.
  ///   The only gateway-specific service with actual business logic.
  /// </summary>
  TBlogService = class(TInterfacedObject, IBlog)
  strict private
    /// <summary>
    ///   Client interface for the Posts backend service.
    /// </summary>
    FPosts: IPost;

    /// <summary>
    ///   Client interface for the Users backend service.
    /// </summary>
    FUsers: IUser;

    /// <summary>
    ///   Client interface for the Tags backend service.
    /// </summary>
    FTags: ITag;

    /// <summary>
    ///   Client interface for the Comments backend service.
    /// </summary>
    FComments: IComment;
  public
    /// <summary>
    ///   Creates a new blog aggregation service with the given backend interfaces.
    /// </summary>
    /// <param name="aPosts">
    ///   The Posts service client interface.
    /// </param>
    /// <param name="aUsers">
    ///   The Users service client interface.
    /// </param>
    /// <param name="aTags">
    ///   The Tags service client interface.
    /// </param>
    /// <param name="aComments">
    ///   The Comments service client interface.
    /// </param>
    constructor Create(
      const aPosts: IPost;
      const aUsers: IUser;
      const aTags: ITag;
      const aComments: IComment
      );

    /// <summary>
    ///   Returns a fully enriched post with author, tags, and comments as a typed record.
    /// </summary>
    /// <param name="aId">
    ///   The post identifier.
    /// </param>
    /// <returns>
    ///   A <c>TPostFullDto</c> record. <c>ID = 0</c> if the post was not found.
    /// </returns>
    function GetPostFull(
      aId: TID
      ): TPostFullDto;

    /// <summary>
    ///   Returns all published posts for a given tag, each enriched with author information.
    /// </summary>
    /// <param name="aTagId">
    ///   The tag identifier.
    /// </param>
    /// <returns>
    ///   A <c>TPostsByTagDto</c> record. <c>Tag.ID = 0</c> if the tag was not found.
    /// </returns>
    function GetPostsByTag(
      aTagId: TID
      ): TPostsByTagDto;
  end;

  /// <summary>
  ///   Forward declaration so the gateway broker callback can hold a reference back to the broker service.
  /// </summary>
  TLogStreamBrokerService = class;

  /// <summary>
  ///   Server-to-client callback that the gateway registers with <c>ms.logs.ILogStream.Subscribe</c>. When
  ///   <c>ms.logs</c> invokes <c>NotifyEntry</c> over the persistent WebSocket, this class fans the entry out
  ///   to every browser-side subscriber via the gateway's own <c>TLogStreamBrokerService</c>.
  ///
  ///   <c>TInterfacedCallback</c> is mORMot2's base class for SOA callbacks: it manages the WebSocket-bound
  ///   reference count and notifies the server's <c>CallbackReleased</c> hook when this instance goes away.
  /// </summary>
  TGatewayLogBrokerCallback = class(TInterfacedCallback, ILogStreamCallback)
  strict private
    /// <summary>
    ///   The gateway-side broker service that holds the browser subscriber list.
    /// </summary>
    FBroker: TLogStreamBrokerService;
  public

    /// <summary>
    ///   Creates the callback bound to a REST client and the gateway broker.
    /// </summary>
    /// <param name="aRest">
    ///   The <c>TRestHttpClientWebsockets</c> instance used to talk to <c>ms.logs</c>; required by the
    ///   <c>TInterfacedCallback</c> base class for refcount tracking.
    /// </param>
    /// <param name="aBroker">
    ///   The broker service whose <c>Broadcast</c> method receives every notification.
    /// </param>
    constructor Create(
      aRest: TRest;
      aBroker: TLogStreamBrokerService
      ); reintroduce;

    /// <summary>
    ///   Invoked by <c>ms.logs</c> for every newly persisted log entry. Forwards the entry to the broker.
    /// </summary>
    /// <param name="aEntry">
    ///   The log entry exactly as sent by ms.logs.
    /// </param>
    procedure NotifyEntry(
      const aEntry: TLogEntryDto
      );
  end;

  /// <summary>
  ///   Implements <c>ILogStream</c> on the gateway side and additionally fans out entries to browser-side
  ///   WebSocket clients that connect via the custom <c>blog-logs</c> chat sub-protocol.
  ///
  ///   <em>Why a custom chat protocol for the browser hop?</em> mORMot2's built-in <c>synopsejson</c> protocol
  ///   is REST-over-WebSocket with mORMot2-specific framing (call IDs, callback registration sequence). It is
  ///   designed for <c>TRestHttpClientWebsockets</c>, not for raw <c>new WebSocket(...)</c> in a browser.
  ///   Trying to talk to it from JavaScript leaves the server waiting for a handshake frame the browser cannot
  ///   produce, so the connection sits idle. The pragmatic fix is a tiny custom protocol on the last hop:
  ///   <c>TWebSocketProtocolChat</c> exchanges arbitrary text frames, the gateway pushes <c>{"entry": ...}</c>
  ///   JSON when new entries arrive, the browser parses them. The Pascal-side stack
  ///   (Producer -> ms.logs -> Gateway) keeps using the proper mORMot2 binary callbacks -- only the very last
  ///   hop is the custom protocol.
  /// </summary>
  TLogStreamBrokerService = class(TInterfacedObject, ILogStream)
  strict private
    /// <summary>
    ///   Critical section guarding both the Pascal subscriber list and the browser connection list against
    ///   concurrent Subscribe/Broadcast/Released and chat-frame events.
    /// </summary>
    FLock: TRTLCriticalSection;

    /// <summary>
    ///   Pascal-side subscribers (used by tests and any other in-process consumers). In production browser
    ///   traffic this list is empty -- browsers go through <c>FChatConnections</c> instead.
    /// </summary>
    FSubscribers: array of ILogStreamCallback;

    /// <summary>
    ///   Active browser-side WebSocket connections registered via the custom <c>blog-logs</c> chat protocol.
    ///   Each entry is a <c>TWebSocketProcess</c> pointer; we never own these objects, we just hold references
    ///   for as long as the underlying connection is alive.
    /// </summary>
    FChatConnections: array of TWebSocketProcess;

    /// <summary>
    ///   The chat protocol instance owned by the gateway HTTP server. Cached so <c>Broadcast</c> can call
    ///   <c>SendFrameJson</c> on it without going back through the protocols list.
    /// </summary>
    FChatProtocol: TWebSocketProtocolChat;
  public

    /// <summary>
    ///   Initializes the lock guarding the subscriber list.
    /// </summary>
    constructor Create;

    /// <summary>
    ///   Releases the lock and the subscriber list.
    /// </summary>
    destructor Destroy; override;

    /// <summary>
    ///   Adds a browser callback to the subscriber list.
    /// </summary>
    /// <param name="aCallback">
    ///   The browser-side callback (transported via the JSON WebSocket protocol).
    /// </param>
    procedure Subscribe(
      const aCallback: ILogStreamCallback
      );

    /// <summary>
    ///   Removes a browser callback from the subscriber list.
    /// </summary>
    /// <param name="aCallback">
    ///   The callback to remove.
    /// </param>
    procedure Unsubscribe(
      const aCallback: ILogStreamCallback
      );

    /// <summary>
    ///   Cleanup hook invoked by mORMot2 when a browser callback's reference count reaches zero (the WebSocket
    ///   was closed). Removes the callback from the subscriber list automatically.
    /// </summary>
    /// <param name="aCallback">
    ///   The released callback.
    /// </param>
    /// <param name="aInterfaceName">
    ///   The released interface name; we only act on <c>ILogStreamCallback</c>.
    /// </param>
    procedure CallbackReleased(
      const aCallback: IInvokable;
      const aInterfaceName: RawUtf8
      );

    /// <summary>
    ///   Pushes one entry to every active subscriber and every active chat connection. Called from
    ///   <c>TGatewayLogBrokerCallback.NotifyEntry</c> after the gateway received the entry from ms.logs.
    /// </summary>
    /// <param name="aEntry">
    ///   The log entry to broadcast.
    /// </param>
    procedure Broadcast(
      const aEntry: TLogEntryDto
      );

    /// <summary>
    ///   Tells the broker which <c>TWebSocketProtocolChat</c> instance to use when fanning out to browser
    ///   connections. Called once during gateway setup, after the protocol is registered with the HTTP server.
    /// </summary>
    /// <param name="aProtocol">
    ///   The chat protocol instance owned by the HTTP server.
    /// </param>
    procedure AttachChatProtocol(
      aProtocol: TWebSocketProtocolChat
      );

    /// <summary>
    ///   Adds a browser WebSocket connection to the active list. Called by the chat-protocol frame handler
    ///   when a client first contacts the server (typically via a "hello" frame).
    /// </summary>
    /// <param name="aSender">
    ///   The <c>TWebSocketProcess</c> representing the client connection.
    /// </param>
    procedure AddChatConnection(
      aSender: TWebSocketProcess
      );

    /// <summary>
    ///   Removes a browser WebSocket connection from the active list. Called when the chat protocol receives
    ///   a close frame, when a send fails, or during gateway shutdown.
    /// </summary>
    /// <param name="aSender">
    ///   The <c>TWebSocketProcess</c> to remove.
    /// </param>
    procedure RemoveChatConnection(
      aSender: TWebSocketProcess
      );
  end;

  /// <summary>
  ///   Gateway microservice: hosts proxy services on a <c>TRestServer</c> and serves the static web frontend via
  ///   <c>THttpAsyncServer</c>. API calls (/api/...) are delegated to a <c>TRestServerDB</c> hosting proxy services.
  ///   Non-API calls serve static files from www/.
  /// </summary>
  TGatewayServer = class(TMicroService)
  strict private
    /// <summary>
    ///   REST HTTP client connected to the Auth backend service.
    /// </summary>
    FAuthClient: TRestHttpClient;

    /// <summary>
    ///   REST HTTP client connected to the Users backend service.
    /// </summary>
    FUsersClient: TRestHttpClient;

    /// <summary>
    ///   REST HTTP client connected to the Posts backend service.
    /// </summary>
    FPostsClient: TRestHttpClient;

    /// <summary>
    ///   REST HTTP client connected to the Tags backend service.
    /// </summary>
    FTagsClient: TRestHttpClient;

    /// <summary>
    ///   REST HTTP client connected to the Comments backend service.
    /// </summary>
    FCommentsClient: TRestHttpClient;

    /// <summary>
    ///   REST HTTP client connected to the Media backend service.
    /// </summary>
    FMediaClient: TRestHttpClient;

    /// <summary>
    ///   REST HTTP client connected to the Analytics backend service.
    /// </summary>
    FAnalyticsClient: TRestHttpClient;

    /// <summary>
    ///   Persistent WebSocket REST client connected to the central logging backend service. Carries both the
    ///   regular <c>ILogQuery</c> SOA traffic and the <c>ILogStream</c> callbacks that drive the live tail.
    /// </summary>
    FLogsClient: TRestHttpClientWebsockets;

    /// <summary>
    ///   Resolved <c>ILogStream</c> interface from <c>FLogsClient</c>; used by the gateway to subscribe its
    ///   own callback for live entries.
    /// </summary>
    FLogStreamRemote: ILogStream;

    /// <summary>
    ///   The gateway's own browser-facing log stream broker. Browsers <c>Subscribe</c> here; entries arrive
    ///   from <c>ms.logs</c> via the broker callback below and get fanned out by this service.
    /// </summary>
    FLogBroker: TLogStreamBrokerService;

    /// <summary>
    ///   Pascal-side callback registered with <c>ms.logs</c>. When ms.logs invokes <c>NotifyEntry</c>, the
    ///   callback forwards the entry into <c>FLogBroker.Broadcast</c>.
    /// </summary>
    FLogBrokerCallback: ILogStreamCallback;

    /// <summary>
    ///   The custom chat protocol instance hosted by the HTTP server, used for browser WebSocket connections
    ///   on the <c>blog-logs</c> sub-protocol. Owned by the underlying HTTP server's protocol list.
    /// </summary>
    FLogChatProtocol: TWebSocketProtocolChat;

    /// <summary>
    ///   Service registry loaded from the configuration service, mapping service names to host/port.
    /// </summary>
    FServiceRegistry: TDocVariantData;

    /// <summary>
    ///   Filesystem path to the static web frontend directory.
    /// </summary>
    FWwwPath: TFileName;

    /// <summary>
    ///   Original HTTP request handler from <c>TRestHttpServer</c>, used for API route delegation.
    /// </summary>
    FOriginalHandler: TOnHttpServerRequest;

    /// <summary>
    ///   Resolved remote interface for the Auth backend service.
    /// </summary>
    FAuth: IAuth;

    /// <summary>
    ///   Resolved remote interface for the Users backend service.
    /// </summary>
    FUsers: IUser;

    /// <summary>
    ///   Resolved remote interface for the Posts backend service.
    /// </summary>
    FPosts: IPost;

    /// <summary>
    ///   Resolved remote interface for the Tags backend service.
    /// </summary>
    FTags: ITag;

    /// <summary>
    ///   Resolved remote interface for the Comments backend service.
    /// </summary>
    FComments: IComment;

    /// <summary>
    ///   Resolved remote interface for the Media backend service.
    /// </summary>
    FMedia: IMedia;

    /// <summary>
    ///   Resolved remote interface for the Analytics backend service.
    /// </summary>
    FAnalytics: IAnalytics;

    /// <summary>
    ///   Resolved remote interface for the central log query backend service.
    /// </summary>
    FLogQuery: ILogQuery;

    /// <summary>
    ///   Frame handler for the <c>blog-logs</c> chat protocol. Called by mORMot2 every time a browser sends a
    ///   text/binary frame or closes the connection. Tracks connections in <c>FLogBroker</c>.
    /// </summary>
    /// <param name="aSender">
    ///   The <c>TWebSocketProcess</c> representing the browser connection.
    /// </param>
    /// <param name="aFrame">
    ///   The incoming WebSocket frame (read-only -- we never modify it).
    /// </param>
    /// <param name="aInfo">
    ///   Optional info string (unused for this protocol).
    /// </param>
    procedure OnLogChatFrame(
      aSender: TWebSocketProcess;
      const aFrame: TWebSocketFrame
      );

    /// <summary>
    ///   Creates a REST HTTP client connected to a backend service and registers the given interfaces.
    /// </summary>
    /// <param name="aHost">
    ///   The backend service hostname.
    /// </param>
    /// <param name="aPort">
    ///   The backend service port.
    /// </param>
    /// <param name="aInterfaces">
    ///   Array of interface RTTI pointers to register on the client.
    /// </param>
    /// <returns>
    ///   A configured <c>TRestHttpClient</c> with interfaces registered and response format matched.
    /// </returns>
    function ConnectToBackend(
      const aHost: RawUtf8;
      const aPort: RawUtf8;
      const aInterfaces: array of PRttiInfo
      ): TRestHttpClient;

    /// <summary>
    ///   Per-call hook installed on every backend <c>TRestHttpClient</c>. Reads the current request's correlation ID
    ///   from the threadvar and appends it to the outgoing HTTP headers, ensuring backend services receive the same
    ///   ID and can include it in their own logs.
    /// </summary>
    /// <param name="aSender">
    ///   The REST client making the call (provided by mORMot2, unused here).
    /// </param>
    /// <param name="aCall">
    ///   The REST call parameters; <c>InHead</c> is mutated to include the correlation header.
    /// </param>
    /// <returns>
    ///   Always <c>True</c> to allow the call to proceed.
    /// </returns>
    function ForwardCorrelationId(
      aSender: TRestClientUri;
      var aCall: TRestUriParams
      ): boolean;

    /// <summary>
    ///   Looks up a field value for a service in the registry, falling back to a default.
    /// </summary>
    /// <param name="aServiceName">
    ///   The service name key in the registry.
    /// </param>
    /// <param name="aField">
    ///   The field name to retrieve (e.g. Host or Port).
    /// </param>
    /// <param name="aDefault">
    ///   The default value if the field is not found.
    /// </param>
    /// <returns>
    ///   The registry value or <c>aDefault</c>.
    /// </returns>
    function RegistryLookup(
      const aServiceName: RawUtf8;
      const aField: RawUtf8;
      const aDefault: RawUtf8
      ): RawUtf8;

    /// <summary>
    ///   Serves a static file from disk, setting the content type from the file extension.
    /// </summary>
    /// <param name="aFilePath">
    ///   The absolute filesystem path to the file.
    /// </param>
    /// <param name="aCtxt">
    ///   The HTTP request context to populate with the response.
    /// </param>
    /// <returns>
    ///   <c>HTTP_SUCCESS</c> if the file exists, <c>HTTP_NOTFOUND</c> otherwise.
    /// </returns>
    function ServeStaticFile(
      const aFilePath: TFileName;
      aCtxt: THttpServerRequestAbstract
      ): cardinal;

    /// <summary>
    ///   Main HTTP request handler: adds CORS headers, routes API calls to the REST server,
    ///   and delegates non-API calls to static file serving.
    /// </summary>
    /// <param name="aCtxt">
    ///   The HTTP request context.
    /// </param>
    /// <returns>
    ///   The HTTP status code for the response.
    /// </returns>
    function HandleRequest(
      aCtxt: THttpServerRequestAbstract
      ): cardinal;

    /// <summary>
    ///   Handles non-API requests by serving static files from the www directory with SPA fallback.
    /// </summary>
    /// <param name="aCtxt">
    ///   The HTTP request context.
    /// </param>
    /// <returns>
    ///   The HTTP status code for the response.
    /// </returns>
    function HandleStaticFile(
      aCtxt: THttpServerRequestAbstract
      ): cardinal;
  protected
    /// <summary>
    ///   Creates the ORM model for the gateway REST server.
    /// </summary>
    /// <returns>
    ///   An empty <c>TOrmModel</c> since the gateway has no ORM tables.
    /// </returns>
    function CreateModel: TOrmModel; override;

    /// <summary>
    ///   Connects to all backend services and registers proxy interfaces on the gateway REST server.
    /// </summary>
    procedure SetupServices; override;

    /// <summary>
    ///   Intercepts the HTTP handler to add static file serving for the SPA frontend.
    /// </summary>
    procedure DoInitialize; override;

    /// <summary>
    ///   Releases all remote interfaces and frees backend HTTP clients.
    /// </summary>
    procedure DoFinalize; override;
  end;

implementation

constructor TBlogService.Create(
  const aPosts: IPost;
  const aUsers: IUser;
  const aTags: ITag;
  const aComments: IComment
  );
begin
  inherited Create;
  FPosts := aPosts;
  FUsers := aUsers;
  FTags := aTags;
  FComments := aComments;
end;

function PostDtoToFull(
  const aPost: TPostDto
  ): TPostFullDto;
begin
  Finalize(Result);
  FillCharFast(Result, SizeOf(Result), 0);
  Result.ID := aPost.ID;
  Result.Title := aPost.Title;
  Result.Slug := aPost.Slug;
  Result.Body := aPost.Body;
  Result.Excerpt := aPost.Excerpt;
  Result.AuthorId := aPost.AuthorId;
  Result.FeaturedImageId := aPost.FeaturedImageId;
  Result.MetaTitle := aPost.MetaTitle;
  Result.MetaDescription := aPost.MetaDescription;
  Result.MetaKeywords := aPost.MetaKeywords;
  Result.Status := aPost.Status;
  Result.PublishedAt := aPost.PublishedAt;
  Result.CreatedAt := aPost.CreatedAt;
  Result.UpdatedAt := aPost.UpdatedAt;
end;

function PostDtoToWithAuthor(
  const aPost: TPostDto
  ): TPostWithAuthorDto;
begin
  Finalize(Result);
  FillCharFast(Result, SizeOf(Result), 0);
  Result.ID := aPost.ID;
  Result.Title := aPost.Title;
  Result.Slug := aPost.Slug;
  Result.Body := aPost.Body;
  Result.Excerpt := aPost.Excerpt;
  Result.AuthorId := aPost.AuthorId;
  Result.FeaturedImageId := aPost.FeaturedImageId;
  Result.MetaTitle := aPost.MetaTitle;
  Result.MetaDescription := aPost.MetaDescription;
  Result.MetaKeywords := aPost.MetaKeywords;
  Result.Status := aPost.Status;
  Result.PublishedAt := aPost.PublishedAt;
  Result.CreatedAt := aPost.CreatedAt;
  Result.UpdatedAt := aPost.UpdatedAt;
end;

function TBlogService.GetPostFull(
  aId: TID
  ): TPostFullDto;
var
  Post: TPostDto;
  Author: TAuthorDto;
begin
  Finalize(Result);
  FillCharFast(Result, SizeOf(Result), 0);
  Post := FPosts.Get(aId);
  if Post.ID = 0 then
    Exit;
  Result := PostDtoToFull(Post);
  // Enrich with author (graceful degradation)
  try
    Author := FUsers.Get(Post.AuthorId);
    Result.Author := Author;
  except
    Result.AuthorUnavailable := True;
  end;
  // Enrich with tags (graceful degradation)
  try
    Result.Tags := FTags.GetByPost(Post.ID);
  except
    Result.TagsUnavailable := True;
  end;
  // Enrich with comments (graceful degradation)
  try
    Result.Comments := FComments.GetByPost(Post.ID);
  except
    Result.CommentsUnavailable := True;
  end;
end;

function TBlogService.GetPostsByTag(
  aTagId: TID
  ): TPostsByTagDto;
var
  Tag: TTagDto;
  PostIds: TIDDynArray;
  Post: TPostDto;
  Author: TAuthorDto;
  PostWithAuthor: TPostWithAuthorDto;
  PostIdx: PtrInt;
begin
  Finalize(Result);
  FillCharFast(Result, SizeOf(Result), 0);
  Tag := FTags.Get(aTagId);
  if Tag.ID = 0 then
    Exit;
  Result.Tag := Tag;
  PostIds := FTags.GetPostIds(aTagId);
  if Length(PostIds) = 0 then
    Exit;
  for PostIdx := 0 to High(PostIds) do
  begin
    // Post service unavailable -> skip this post
    try
      Post := FPosts.Get(PostIds[PostIdx]);
    except
      continue;
    end;
    if Post.ID = 0 then
      continue;
    if Post.Status <> POST_STATUS_PUBLISHED then
      continue;
    PostWithAuthor := PostDtoToWithAuthor(Post);
    // Author service unavailable -> post without author
    try
      Author := FUsers.Get(Post.AuthorId);
      PostWithAuthor.Author := Author;
    except
      PostWithAuthor.AuthorUnavailable := True;
    end;
    SetLength(Result.Posts, Length(Result.Posts) + 1);
    Result.Posts[High(Result.Posts)] := PostWithAuthor;
  end;
end;

function TGatewayServer.ConnectToBackend(
  const aHost: RawUtf8;
  const aPort: RawUtf8;
  const aInterfaces: array of PRttiInfo
  ): TRestHttpClient;
var
  ClientModel: TOrmModel;
  IntfIdx: PtrInt;
begin
  ClientModel := TOrmModel.Create([], MODEL_ROOT);
  Result := TRestHttpClient.Create(aHost, aPort, ClientModel);
  Result.Model.Owner := Result; // model freed with client
  Result.ServiceRegister(aInterfaces, sicShared);
  // Backend services use ResultAsJsonObjectWithoutResult format --
  // the client factories must match to parse responses correctly
  for IntfIdx := 0 to High(aInterfaces) do
    TServiceFactoryClient(Result.Services.Info(aInterfaces[IntfIdx])).ResultAsJsonObjectWithoutResult := True;
  // Inject the current request's correlation ID into every outgoing call.
  // OnBeforeCall fires per-call, on the calling thread, so it correctly picks up the threadvar
  // set by HandleRequest at the gateway entry point.
  Result.OnBeforeCall := ForwardCorrelationId;
end;

function TGatewayServer.ForwardCorrelationId(
  aSender: TRestClientUri;
  var aCall: TRestUriParams
  ): boolean;
var
  CorrId: RawUtf8;
begin
  CorrId := GetCurrentCorrelationId;
  if CorrId <> '' then
    AppendLine(aCall.InHead, [CORRELATION_HEADER + ': ', CorrId]);
  Result := True;
end;

procedure TGatewayServer.OnLogChatFrame(
  aSender: TWebSocketProcess;
  const aFrame: TWebSocketFrame
  );
begin
  if FLogBroker = nil then
    Exit;
  // The chat protocol delivers all frame types here. We use focText/focBinary as the trigger to register
  // a sender as an active subscriber (the browser sends a tiny "hello" frame on connect), and focClose
  // to remove it on a clean disconnect. Send failures during Broadcast are the safety net for hard drops.
  case aFrame.opcode of
    focText, focBinary:
      FLogBroker.AddChatConnection(aSender);
    focConnectionClose:
      FLogBroker.RemoveChatConnection(aSender);
  end;
end;

constructor TGatewayLogBrokerCallback.Create(
  aRest: TRest;
  aBroker: TLogStreamBrokerService
  );
begin
  inherited Create(aRest, ILogStreamCallback);
  FBroker := aBroker;
end;

procedure TGatewayLogBrokerCallback.NotifyEntry(
  const aEntry: TLogEntryDto
  );
begin
  if FBroker <> nil then
    FBroker.Broadcast(aEntry);
end;

constructor TLogStreamBrokerService.Create;
begin
  inherited Create;
  InitializeCriticalSection(FLock);
end;

destructor TLogStreamBrokerService.Destroy;
begin
  EnterCriticalSection(FLock);
  try
    FSubscribers := nil;
  finally
    LeaveCriticalSection(FLock);
  end;
  DeleteCriticalSection(FLock);
  inherited Destroy;
end;

procedure TLogStreamBrokerService.Subscribe(
  const aCallback: ILogStreamCallback
  );
begin
  if aCallback = nil then
    Exit;
  EnterCriticalSection(FLock);
  try
    SetLength(FSubscribers, Length(FSubscribers) + 1);
    FSubscribers[High(FSubscribers)] := aCallback;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TLogStreamBrokerService.Unsubscribe(
  const aCallback: ILogStreamCallback
  );
var
  SubscriberIdx: PtrInt;
begin
  if aCallback = nil then
    Exit;
  EnterCriticalSection(FLock);
  try
    for SubscriberIdx := High(FSubscribers) downto 0 do
      if FSubscribers[SubscriberIdx] = aCallback then
      begin
        Delete(FSubscribers, SubscriberIdx, 1);
        Break;
      end;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TLogStreamBrokerService.CallbackReleased(
  const aCallback: IInvokable;
  const aInterfaceName: RawUtf8
  );
var
  SubscriberIdx: PtrInt;
  ReleasedAsStream: ILogStreamCallback;
begin
  if aInterfaceName <> 'ILogStreamCallback' then
    Exit;
  if not Supports(aCallback, ILogStreamCallback, ReleasedAsStream) then
    Exit;
  EnterCriticalSection(FLock);
  try
    for SubscriberIdx := High(FSubscribers) downto 0 do
      if FSubscribers[SubscriberIdx] = ReleasedAsStream then
      begin
        Delete(FSubscribers, SubscriberIdx, 1);
        Break;
      end;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TLogStreamBrokerService.Broadcast(
  const aEntry: TLogEntryDto
  );
var
  SubscriberIdx, ChatIdx: PtrInt;
  EntryJson, FrameJson: RawUtf8;
begin
  // Build the JSON payload exactly once for the chat path. RecordSaveJson uses the same RTTI that the
  // SOA layer uses for backend traffic, so the field names match across all transports.
  EntryJson := '';
  EnterCriticalSection(FLock);
  try
    // 1) Pascal-side ILogStreamCallback subscribers (used by tests and any in-process consumers).
    for SubscriberIdx := High(FSubscribers) downto 0 do
      try
        FSubscribers[SubscriberIdx].NotifyEntry(aEntry);
      except
        Delete(FSubscribers, SubscriberIdx, 1);
      end;
    // 2) Browser-side chat connections.
    if (FChatProtocol <> nil) and (Length(FChatConnections) > 0) then
    begin
      EntryJson := RecordSaveJson(aEntry, TypeInfo(TLogEntryDto));
      FrameJson := '{"entry":' + EntryJson + '}';
      for ChatIdx := High(FChatConnections) downto 0 do
        try
          if not FChatProtocol.SendFrameJson(FChatConnections[ChatIdx], FrameJson) then
            // The send failed -- the underlying socket is gone. Drop it from the active list.
            Delete(FChatConnections, ChatIdx, 1);
        except
          // Defense in depth -- the OnIncomingFrame focConnectionClose path normally evicts dead
          // connections, but a hard socket drop bypasses that path so we cover it here too.
          Delete(FChatConnections, ChatIdx, 1);
        end;
    end;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TLogStreamBrokerService.AddChatConnection(
  aSender: TWebSocketProcess
  );
var
  ChatIdx: PtrInt;
begin
  if aSender = nil then
    Exit;
  EnterCriticalSection(FLock);
  try
    // Avoid duplicates if the client sends multiple frames before disconnecting.
    for ChatIdx := 0 to High(FChatConnections) do
      if FChatConnections[ChatIdx] = aSender then
        Exit;
    SetLength(FChatConnections, Length(FChatConnections) + 1);
    FChatConnections[High(FChatConnections)] := aSender;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TLogStreamBrokerService.AttachChatProtocol(
  aProtocol: TWebSocketProtocolChat
  );
begin
  EnterCriticalSection(FLock);
  try
    FChatProtocol := aProtocol;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TLogStreamBrokerService.RemoveChatConnection(
  aSender: TWebSocketProcess
  );
var
  ChatIdx: PtrInt;
begin
  if aSender = nil then
    Exit;
  EnterCriticalSection(FLock);
  try
    for ChatIdx := High(FChatConnections) downto 0 do
      if FChatConnections[ChatIdx] = aSender then
      begin
        Delete(FChatConnections, ChatIdx, 1);
        Break;
      end;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TGatewayServer.CreateModel: TOrmModel;
begin
  Result := TOrmModel.Create([], MODEL_ROOT);
end;

function TGatewayServer.RegistryLookup(
  const aServiceName: RawUtf8;
  const aField: RawUtf8;
  const aDefault: RawUtf8
  ): RawUtf8;
var
  RegistryEntry: PDocVariantData;
begin
  RegistryEntry := FServiceRegistry.O[aServiceName];
  if (RegistryEntry <> nil) and (RegistryEntry^.U[aField] <> '') then
    Exit(RegistryEntry^.U[aField]);
  Result := aDefault;
end;

procedure TGatewayServer.SetupServices;

  procedure LoadServiceRegistry;
  var
    Bootstrap: TBootstrapConfig;
    ConfigClientModel: TOrmModel;
    ConfigClient: TRestHttpClient;
    ConfigIntf: IConfig;
    ConfigHost, ConfigPort: RawUtf8;
    RegistryJson: RawUtf8;
  begin
    FServiceRegistry.InitObject([], JSON_FAST);
    Bootstrap := LoadBootstrapConfig(SERVICE_GATEWAY);
    if Bootstrap.ConfigUrl = '' then
      Exit;
    ConfigHost := Bootstrap.ConfigUrl;
    if IdemPChar(pointer(ConfigHost), 'HTTP://') then
      Delete(ConfigHost, 1, 7)
    else if IdemPChar(pointer(ConfigHost), 'HTTPS://') then
      Delete(ConfigHost, 1, 8);
    ConfigPort := Split(ConfigHost, ':', ConfigHost);
    if ConfigPort = '' then
    begin
      ConfigPort := ConfigHost;
      ConfigHost := 'localhost';
    end;
    try
      ConfigClientModel := TOrmModel.Create([], MODEL_ROOT);
      ConfigClient := TRestHttpClient.Create(ConfigHost, ConfigPort, ConfigClientModel);
      try
        ConfigClient.Model.Owner := ConfigClient;
        ConfigClient.ServiceRegister([TypeInfo(IConfig)], sicShared);
        TServiceFactoryClient(ConfigClient.Services.Info(TypeInfo(IConfig))).ResultAsJsonObjectWithoutResult := True;
        if ConfigClient.Services.Resolve(IConfig, ConfigIntf) then
        begin
          RegistryJson := ConfigIntf.GetServiceRegistry;
          if RegistryJson <> '' then
            FServiceRegistry.InitJson(RegistryJson, JSON_FAST_FLOAT);
        end;
      finally
        ConfigIntf := nil;
        ConfigClient.Free;
      end;
    except
      // Config service unavailable -- use defaults
    end;
  end;

var
  LogsClientModel: TOrmModel;
  LogsUpgradeError: RawUtf8;
  LogBrokerFactory: TServiceFactoryServerAbstract;
begin
  FWwwPath := Executable.ProgramFilePath + 'www' + PathDelim;
  if not DirectoryExists(FWwwPath) then
    CreateDir(FWwwPath);
  // Load service registry from ms.config (fallback to defaults)
  LoadServiceRegistry;
  // Connect to backend services using registry or defaults
  FAuthClient := ConnectToBackend(
    RegistryLookup(SERVICE_AUTH, 'Host', 'localhost'),
    RegistryLookup(SERVICE_AUTH, 'Port', PORT_AUTH),
    [TypeInfo(IAuth)]);
  FAuthClient.Services.Resolve(IAuth, FAuth);
  FUsersClient := ConnectToBackend(
    RegistryLookup(SERVICE_USERS, 'Host', 'localhost'),
    RegistryLookup(SERVICE_USERS, 'Port', PORT_USERS),
    [TypeInfo(IUser)]);
  FUsersClient.Services.Resolve(IUser, FUsers);
  FPostsClient := ConnectToBackend(
    RegistryLookup(SERVICE_POSTS, 'Host', 'localhost'),
    RegistryLookup(SERVICE_POSTS, 'Port', PORT_POSTS),
    [TypeInfo(IPost)]);
  FPostsClient.Services.Resolve(IPost, FPosts);
  FTagsClient := ConnectToBackend(
    RegistryLookup(SERVICE_TAGS, 'Host', 'localhost'),
    RegistryLookup(SERVICE_TAGS, 'Port', PORT_TAGS),
    [TypeInfo(ITag)]);
  FTagsClient.Services.Resolve(ITag, FTags);
  FCommentsClient := ConnectToBackend(
    RegistryLookup(SERVICE_COMMENTS, 'Host', 'localhost'),
    RegistryLookup(SERVICE_COMMENTS, 'Port', PORT_COMMENTS),
    [TypeInfo(IComment)]);
  FCommentsClient.Services.Resolve(IComment, FComments);
  FMediaClient := ConnectToBackend(
    RegistryLookup(SERVICE_MEDIA, 'Host', 'localhost'),
    RegistryLookup(SERVICE_MEDIA, 'Port', PORT_MEDIA),
    [TypeInfo(IMedia)]);
  FMediaClient.Services.Resolve(IMedia, FMedia);
  FAnalyticsClient := ConnectToBackend(
    RegistryLookup(SERVICE_ANALYTICS, 'Host', 'localhost'),
    RegistryLookup(SERVICE_ANALYTICS, 'Port', PORT_ANALYTICS),
    [TypeInfo(IAnalytics)]);
  FAnalyticsClient.Services.Resolve(IAnalytics, FAnalytics);
  // ms.logs is the only backend reached over a persistent WebSocket connection. The same client carries
  // both the request/response ILogQuery traffic and the server-to-client ILogStream callbacks. The
  // WebSocketsUpgrade handshake exchanges WEBSOCKETS_KEY with the server.
  LogsClientModel := TOrmModel.Create([], MODEL_ROOT);
  FLogsClient := TRestHttpClientWebsockets.Create(
    RegistryLookup(SERVICE_LOGS, 'Host', 'localhost'),
    RegistryLookup(SERVICE_LOGS, 'Port', PORT_LOGS),
    LogsClientModel);
  FLogsClient.Model.Owner := FLogsClient;
  LogsUpgradeError := FLogsClient.WebSocketsUpgrade(WEBSOCKETS_KEY);
  if LogsUpgradeError <> '' then
    LogWithCorrelation(sllWarning,
      'gateway: ms.logs WebSocket upgrade failed: %', [LogsUpgradeError], self);
  FLogsClient.ServiceRegister([TypeInfo(ILogQuery), TypeInfo(ILogStream)], sicShared);
  TServiceFactoryClient(FLogsClient.Services.Info(TypeInfo(ILogQuery))).
    ResultAsJsonObjectWithoutResult := True;
  TServiceFactoryClient(FLogsClient.Services.Info(TypeInfo(ILogStream))).
    ResultAsJsonObjectWithoutResult := True;
  FLogsClient.OnBeforeCall := ForwardCorrelationId;
  FLogsClient.Services.Resolve(ILogQuery, FLogQuery);
  FLogsClient.Services.Resolve(ILogStream, FLogStreamRemote);
  // Create the gateway-side broker that browser viewers will subscribe to. The broker fans out entries
  // to two transports: in-process Pascal subscribers (used by tests) and browser WebSocket connections
  // via the custom blog-logs chat protocol. The chat protocol itself is registered in DoInitialize once
  // FHttpServer has been created -- here in SetupServices it is still nil.
  FLogBroker := TLogStreamBrokerService.Create;
  // Register the gateway's own ILogStreamCallback with ms.logs so it starts receiving NotifyEntry calls.
  // The TInterfacedCallback base class manages the underlying refcount; the reference is kept alive by
  // FLogBrokerCallback as long as we hold it. ms.shared.api pre-registers ILogStreamCallback in the
  // global TInterfaceFactory so the server side can materialize the fake callback for this Subscribe.
  if FLogStreamRemote <> nil then
  begin
    FLogBrokerCallback := TGatewayLogBrokerCallback.Create(FLogsClient, FLogBroker);
    try
      FLogStreamRemote.Subscribe(FLogBrokerCallback);
    except
      on E: Exception do
      begin
        TSynLog.Add.Log(sllWarning,
          'gateway: ILogStream.Subscribe to ms.logs failed: %', [E.Message], self);
        FLogBrokerCallback := nil;
      end;
    end;
  end;
  // Register resolved client interfaces directly as server services.
  // The client-resolved interfaces are TInterfacedObjectFake instances
  // that already implement the interface -- no manual proxy classes needed.
  RegisterService(ObjectFromInterface(FAuth) as TInterfacedObject, TypeInfo(IAuth));
  RegisterService(ObjectFromInterface(FUsers) as TInterfacedObject, TypeInfo(IUser));
  RegisterService(ObjectFromInterface(FPosts) as TInterfacedObject, TypeInfo(IPost));
  RegisterService(ObjectFromInterface(FTags) as TInterfacedObject, TypeInfo(ITag));
  RegisterService(ObjectFromInterface(FComments) as TInterfacedObject, TypeInfo(IComment));
  RegisterService(ObjectFromInterface(FMedia) as TInterfacedObject, TypeInfo(IMedia));
  RegisterService(ObjectFromInterface(FAnalytics) as TInterfacedObject, TypeInfo(IAnalytics));
  RegisterService(ObjectFromInterface(FLogQuery) as TInterfacedObject, TypeInfo(ILogQuery));
  // The browser-facing ILogStream is the gateway's own broker, NOT a transparent proxy of ms.logs.
  // Browsers subscribe here; the broker re-broadcasts entries arriving from ms.logs via the persistent
  // FLogBrokerCallback registered above. optExecLockedPerInterface keeps NotifyEntry calls per browser
  // subscriber serialized in arrival order.
  LogBrokerFactory := RegisterService(FLogBroker, TypeInfo(ILogStream));
  LogBrokerFactory.SetOptions([], [optExecLockedPerInterface]);
  // Aggregation service -- actual business logic, not a proxy
  RegisterService(TBlogService.Create(FPosts, FUsers, FTags, FComments), TypeInfo(IBlog));
end;

procedure TGatewayServer.DoInitialize;
var
  WsServer: TWebSocketAsyncServer;
begin
  // Intercept the HTTP handler to add static file serving
  // for non-API requests (SPA frontend from www/ directory).
  // The original handler processes /api/* routes via TRestServer.
  FOriginalHandler := FHttpServer.HttpServer.OnRequest;
  FHttpServer.HttpServer.OnRequest := HandleRequest;
  // Register the custom 'blog-logs' chat protocol on the underlying WebSocket-aware HTTP server.
  // TMicroService.Run created the server with WEBSOCKETS_DEFAULT_MODE which selects the async
  // WebSocket implementation, so the cast to TWebSocketAsyncServer is safe. We use a soft cast
  // (with `is`) so that future changes to the server type degrade gracefully instead of crashing.
  // We follow the canonical pattern from mORMot2's restws_simpleechoserver example: create with
  // (name, uri), then set OnIncomingFrame as a property, then add to the protocols list. The
  // 3-parameter constructor would compile, but the Clone() method that mORMot2 calls per
  // connection does not reliably propagate a callback set via constructor argument.
  if (FLogBroker <> nil) and (FHttpServer.HttpServer is TWebSocketAsyncServer) then
  begin
    WsServer := TWebSocketAsyncServer(FHttpServer.HttpServer);
    FLogChatProtocol := TWebSocketProtocolChat.Create('blog-logs', '');
    FLogChatProtocol.OnIncomingFrame := OnLogChatFrame;
    WsServer.WebSocketProtocols.Add(FLogChatProtocol);
    FLogBroker.AttachChatProtocol(FLogChatProtocol);
  end;
end;

procedure TGatewayServer.DoFinalize;
begin
  // Release interfaces before clients. The gateway's own ILogStream broker subscription is released
  // first so ms.logs gets a clean CallbackReleased notification while the WebSocket is still up.
  if (FLogBrokerCallback <> nil) and (FLogStreamRemote <> nil) then
    try
      FLogStreamRemote.Unsubscribe(FLogBrokerCallback);
    except
      // ms.logs may be down already -- nothing we can do, the framework will clean up.
    end;
  FLogBrokerCallback := nil;
  FLogStreamRemote := nil;
  FreeAndNil(FLogBroker);
  FAuth := nil;
  FUsers := nil;
  FPosts := nil;
  FTags := nil;
  FComments := nil;
  FMedia := nil;
  FAnalytics := nil;
  FLogQuery := nil;
  FreeAndNil(FLogsClient);
  FreeAndNil(FAnalyticsClient);
  FreeAndNil(FMediaClient);
  FreeAndNil(FCommentsClient);
  FreeAndNil(FTagsClient);
  FreeAndNil(FPostsClient);
  FreeAndNil(FUsersClient);
  FreeAndNil(FAuthClient);
end;

function TGatewayServer.HandleRequest(
  aCtxt: THttpServerRequestAbstract
  ): cardinal;
var
  CorrId: RawUtf8;
begin
  // Establish the correlation ID for this request before any other gateway logic.
  // The base TMicroService wrapper would also do this for /api/* calls (it sits in the chain
  // captured by FOriginalHandler), but we set it here too so static-file requests and CORS
  // preflights are also tagged. EnsureCorrelationIdFromHeaders is idempotent: if the wrapper
  // is invoked again later it will read the value we just set.
  CorrId := EnsureCorrelationIdFromHeaders(aCtxt.InHeaders);
  // Add CORS headers and mirror the correlation ID back to the caller in one shot.
  aCtxt.OutCustomHeaders :=
    'Access-Control-Allow-Origin: *'#13#10 +
    'Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS'#13#10 +
    'Access-Control-Allow-Headers: Content-Type, Authorization, ' + CORRELATION_HEADER + #13#10 +
    'Access-Control-Expose-Headers: ' + CORRELATION_HEADER + #13#10 +
    CORRELATION_HEADER + ': ' + CorrId;
  try
    // Handle CORS preflight -- bypasses the inner wrapper, so log it here.
    if aCtxt.Method = 'OPTIONS' then
    begin
      LogWithCorrelation(sllInfo, '% OPTIONS %', [ServiceName, aCtxt.Url], self);
      aCtxt.OutContent := '';
      Exit(HTTP_NOCONTENT);
    end;
    // API calls go to the REST server (interface-based services). The base wrapper logs them.
    if IdemPChar(pointer(aCtxt.Url), '/API/') or IdemPChar(pointer(aCtxt.Url), '/API') then
      Result := FOriginalHandler(aCtxt)
    else
    begin
      // Non-API calls serve static files (SPA frontend) -- not logged by the inner wrapper.
      LogWithCorrelation(sllInfo, '% STATIC %', [ServiceName, aCtxt.Url], self);
      Result := HandleStaticFile(aCtxt);
      LogWithCorrelation(sllInfo, '% STATIC % -> %', [ServiceName, aCtxt.Url, Result], self);
    end;
  finally
    // Clear the correlation ID so the next request on this thread starts clean.
    ClearCurrentCorrelationId;
  end;
end;

function TGatewayServer.HandleStaticFile(
  aCtxt: THttpServerRequestAbstract
  ): cardinal;
var
  Path: RawUtf8;
  FilePath: TFileName;
begin
  Path := aCtxt.Url;
  if (Path = '/') or (Path = '') then
    FilePath := FWwwPath + 'index.html'
  else
  begin
    // Prevent path traversal
    if PosEx('..', Path) > 0 then
      Exit(HTTP_FORBIDDEN);
    FilePath := FWwwPath + StringReplace(Utf8ToString(Copy(Path, 2, MaxInt)), '/', PathDelim, [rfReplaceAll]);
  end;
  Result := ServeStaticFile(FilePath, aCtxt);
  // SPA fallback: unmatched routes serve index.html
  if Result = HTTP_NOTFOUND then
    Result := ServeStaticFile(FWwwPath + 'index.html', aCtxt);
end;

function TGatewayServer.ServeStaticFile(
  const aFilePath: TFileName;
  aCtxt: THttpServerRequestAbstract
  ): cardinal;
begin
  if FileExists(aFilePath) then
  begin
    aCtxt.OutContent := StringFromFile(aFilePath);
    aCtxt.OutContentType := GuessMimeType(aFilePath);
    Result := HTTP_SUCCESS;
  end
  else
    Result := HTTP_NOTFOUND;
end;

end.
