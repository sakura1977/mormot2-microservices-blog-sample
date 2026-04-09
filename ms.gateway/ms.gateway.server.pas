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
  ms.shared.service;

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
  // Aggregation service -- actual business logic, not a proxy
  RegisterService(TBlogService.Create(FPosts, FUsers, FTags, FComments), TypeInfo(IBlog));
end;

procedure TGatewayServer.DoInitialize;
begin
  // Intercept the HTTP handler to add static file serving
  // for non-API requests (SPA frontend from www/ directory).
  // The original handler processes /api/* routes via TRestServer.
  FOriginalHandler := FHttpServer.HttpServer.OnRequest;
  FHttpServer.HttpServer.OnRequest := HandleRequest;
end;

procedure TGatewayServer.DoFinalize;
begin
  // Release interfaces before clients
  FAuth := nil;
  FUsers := nil;
  FPosts := nil;
  FTags := nil;
  FComments := nil;
  FMedia := nil;
  FAnalytics := nil;
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
