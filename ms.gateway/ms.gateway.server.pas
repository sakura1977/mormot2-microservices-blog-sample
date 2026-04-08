/// <summary>
///   API Gateway: routes browser requests to backend microservices
///   and serves the SPA web frontend as static files.
///
///   This is the most architecturally interesting service in the
///   project. It demonstrates several advanced mORMot2 patterns:
///
///   1. <em>Transparent SOA proxying</em>: The gateway resolves
///      backend service interfaces via <c>TRestHttpClient</c> +
///      <c>Services.Resolve</c>, which returns a
///      <c>TInterfacedObjectFake</c> that transparently forwards
///      method calls as HTTP requests. These fake client objects
///      are then re-registered as server-side services on the
///      gateway's own <c>TRestServerDB</c> via
///      <c>RegisterService</c> -- no manual proxy classes needed.
///      The gateway acts as a pure pass-through for 6 interfaces.
///
///   2. <em>Response aggregation</em> (<c>TBlogService</c>):
///      The <c>IBlog.GetPostFull</c> method queries 4 backend
///      services (posts, users, tags, comments) and merges their
///      responses into one enriched JSON document using
///      <c>TDocVariantData</c>.
///
///   3. <em>HTTP request interception</em>: The gateway intercepts
///      the <c>THttpAsyncServer.OnRequest</c> handler to split
///      traffic between API calls (/api/...) and static file
///      serving (SPA frontend from www/ directory).
///
///   4. <em>Client-side service format matching</em>: Backend
///      services use <c>ResultAsJsonObjectWithoutResult</c>, so
///      the gateway's client factories must also set this flag
///      via <c>TServiceFactoryClient</c> to parse responses
///      correctly.
/// </summary>
unit ms.gateway.server;

{$SCOPEDENUMS ON}
{$I mormot.defines.inc}
{$WARN SYMBOL_PLATFORM OFF}
{$WARN UNIT_PLATFORM OFF}

interface

uses
  SysUtils,
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
  ms.shared.jwt,
  ms.shared.service;

type

  /// <summary>
  ///   Aggregation service: enriches a post with author, tags, comments.
  ///   The only gateway-specific service with actual business logic.
  /// </summary>
  TBlogService = class(TInterfacedObject, IBlog)
  private
    FPosts: IPost;
    FUsers: IUser;
    FTags: ITag;
    FComments: IComment;
  public
    constructor Create(const aPosts: IPost; const aUsers: IUser;
      const aTags: ITag; const aComments: IComment);
    function GetPostFull(aId: TID): RawJson;
    function GetPostsByTag(aTagId: TID): RawJson;
  end;

  /// <summary>
  ///   Gateway microservice: hosts proxy services on a TRestServer
  ///   and serves the static web frontend via THttpAsyncServer.
  ///   API calls (/api/...) are delegated to a TRestServerDB hosting
  ///   proxy services. Non-API calls serve static files from www/.
  /// </summary>
  TGatewayServer = class(TMicroService)
  private
    FAuthClient: TRestHttpClient;
    FUsersClient: TRestHttpClient;
    FPostsClient: TRestHttpClient;
    FTagsClient: TRestHttpClient;
    FCommentsClient: TRestHttpClient;
    FMediaClient: TRestHttpClient;
    FServiceRegistry: TDocVariantData;
    FWwwPath: TFileName;
    FOriginalHandler: TOnHttpServerRequest;
    // Resolved remote interfaces
    FAuth: IAuth;
    FUsers: IUser;
    FPosts: IPost;
    FTags: ITag;
    FComments: IComment;
    FMedia: IMedia;
    function ConnectToBackend(const aHost, aPort: RawUtf8;
      const aInterfaces: array of PRttiInfo): TRestHttpClient;
    function RegistryLookup(const aServiceName, aField,
      aDefault: RawUtf8): RawUtf8;
    function ServeStaticFile(const aFilePath: TFileName;
      aCtxt: THttpServerRequestAbstract): cardinal;
    function HandleRequest(aCtxt: THttpServerRequestAbstract): cardinal;
    function HandleStaticFile(aCtxt: THttpServerRequestAbstract): cardinal;
  protected
    function CreateModel: TOrmModel; override;
    procedure SetupServices; override;
    procedure DoInitialize; override;
    procedure DoFinalize; override;
  end;

implementation

{ TBlogService }

constructor TBlogService.Create(const aPosts: IPost;
  const aUsers: IUser; const aTags: ITag;
  const aComments: IComment);
begin
  inherited Create;
  FPosts := aPosts;
  FUsers := aUsers;
  FTags := aTags;
  FComments := aComments;
end;

function TBlogService.GetPostFull(aId: TID): RawJson;
var
  PostJson, AuthorJson, TagsJson, CommentsJson: RawJson;
  PostDoc: TDocVariantData;
  AuthorId, PostId: TID;
begin
  PostJson := FPosts.Get(aId);
  if PostJson = '{}' then
    Exit('{}');
  PostDoc.InitJson(PostJson, JSON_FAST_FLOAT);
  AuthorId := PostDoc.I['AuthorId'];
  PostId := PostDoc.I['RowID'];
  if PostId = 0 then
    PostId := PostDoc.I['ID'];
  // Enrich with author (graceful degradation)
  try
    AuthorJson := FUsers.Get(AuthorId);
    if AuthorJson <> '{}' then
      PostDoc.AddValue('Author', _JsonFast(AuthorJson))
    else
      PostDoc.AddValue('Author', null);
  except
    PostDoc.AddValue('Author', null);
    PostDoc.B['AuthorUnavailable'] := True;
  end;
  // Enrich with tags (graceful degradation)
  if PostId > 0 then
  begin
    try
      TagsJson := FTags.GetByPost(PostId);
      if TagsJson <> '[]' then
        PostDoc.AddValue('Tags', _JsonFast(TagsJson))
      else
        PostDoc.AddValue('Tags', _ArrFast([]));
    except
      PostDoc.AddValue('Tags', _ArrFast([]));
      PostDoc.B['TagsUnavailable'] := True;
    end;
    // Enrich with comments (graceful degradation)
    try
      CommentsJson := FComments.GetByPost(PostId);
      if CommentsJson <> '[]' then
        PostDoc.AddValue('Comments', _JsonFast(CommentsJson))
      else
        PostDoc.AddValue('Comments', _ArrFast([]));
    except
      PostDoc.AddValue('Comments', _ArrFast([]));
      PostDoc.B['CommentsUnavailable'] := True;
    end;
  end;
  Result := RawJson(PostDoc.ToJson);
end;

function TBlogService.GetPostsByTag(aTagId: TID): RawJson;
var
  TagJson, PostIdsJson, PostJson, AuthorJson: RawJson;
  ResultDoc, PostDoc: TDocVariantData;
  PostIds, Posts: TDocVariantData;
  PostIdx: PtrInt;
  PostId, AuthorId: TID;
begin
  TagJson := FTags.Get(aTagId);
  if TagJson = '{}' then
    Exit('{}');
  PostIdsJson := FTags.GetPostIds(aTagId);
  if PostIdsJson = '[]' then
  begin
    ResultDoc.InitObject([
      'Tag', _JsonFast(TagJson),
      'Posts', _ArrFast([])
    ], JSON_FAST);
    Exit(RawJson(ResultDoc.ToJson));
  end;
  PostIds.InitJson(PostIdsJson, JSON_FAST_FLOAT);
  Posts.InitArray([], JSON_FAST);
  for PostIdx := 0 to PostIds.Count - 1 do
  begin
    PostId := PostIds.Values[PostIdx];
    // Post service unavailable -> skip this post
    try
      PostJson := FPosts.Get(PostId);
    except
      continue;
    end;
    if PostJson = '{}' then
      continue;
    PostDoc.InitJson(PostJson, JSON_FAST_FLOAT);
    if PostDoc.I['Status'] <> POST_STATUS_PUBLISHED then
      continue;
    // Author service unavailable -> post without author
    AuthorId := PostDoc.I['AuthorId'];
    try
      AuthorJson := FUsers.Get(AuthorId);
      if AuthorJson <> '{}' then
        PostDoc.AddValue('Author', _JsonFast(AuthorJson))
      else
        PostDoc.AddValue('Author', null);
    except
      PostDoc.AddValue('Author', null);
    end;
    Posts.AddItem(_JsonFast(RawUtf8(PostDoc.ToJson)));
  end;
  ResultDoc.InitObject([
    'Tag', _JsonFast(TagJson),
    'Posts', variant(Posts)
  ], JSON_FAST);
  Result := RawJson(ResultDoc.ToJson);
end;

{ TGatewayServer }

function TGatewayServer.ConnectToBackend(const aHost, aPort: RawUtf8;
  const aInterfaces: array of PRttiInfo): TRestHttpClient;
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
    TServiceFactoryClient(Result.Services.Info(aInterfaces[IntfIdx]))
      .ResultAsJsonObjectWithoutResult := True;
end;

function TGatewayServer.CreateModel: TOrmModel;
begin
  Result := TOrmModel.Create([], MODEL_ROOT);
end;

function TGatewayServer.RegistryLookup(
  const aServiceName, aField, aDefault: RawUtf8
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
      ConfigClient := TRestHttpClient.Create(
        ConfigHost, ConfigPort, ConfigClientModel);
      try
        ConfigClient.Model.Owner := ConfigClient;
        ConfigClient.ServiceRegister([TypeInfo(IConfig)], sicShared);
        TServiceFactoryClient(
          ConfigClient.Services.Info(TypeInfo(IConfig)))
          .ResultAsJsonObjectWithoutResult := True;
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
  // Register resolved client interfaces directly as server services.
  // The client-resolved interfaces are TInterfacedObjectFake instances
  // that already implement the interface -- no manual proxy classes needed.
  RegisterService(
    ObjectFromInterface(FAuth) as TInterfacedObject, TypeInfo(IAuth));
  RegisterService(
    ObjectFromInterface(FUsers) as TInterfacedObject, TypeInfo(IUser));
  RegisterService(
    ObjectFromInterface(FPosts) as TInterfacedObject, TypeInfo(IPost));
  RegisterService(
    ObjectFromInterface(FTags) as TInterfacedObject, TypeInfo(ITag));
  RegisterService(
    ObjectFromInterface(FComments) as TInterfacedObject, TypeInfo(IComment));
  RegisterService(
    ObjectFromInterface(FMedia) as TInterfacedObject, TypeInfo(IMedia));
  // Aggregation service -- actual business logic, not a proxy
  RegisterService(
    TBlogService.Create(FPosts, FUsers, FTags, FComments),
    TypeInfo(IBlog));
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
  FreeAndNil(FMediaClient);
  FreeAndNil(FCommentsClient);
  FreeAndNil(FTagsClient);
  FreeAndNil(FPostsClient);
  FreeAndNil(FUsersClient);
  FreeAndNil(FAuthClient);
end;

function TGatewayServer.HandleRequest(
  aCtxt: THttpServerRequestAbstract): cardinal;
begin
  // Add CORS headers for all responses
  aCtxt.OutCustomHeaders :=
    'Access-Control-Allow-Origin: *'#13#10 +
    'Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS'#13#10 +
    'Access-Control-Allow-Headers: Content-Type, Authorization';
  // Handle CORS preflight
  if aCtxt.Method = 'OPTIONS' then
  begin
    aCtxt.OutContent := '';
    Exit(HTTP_NOCONTENT);
  end;
  // API calls go to the REST server (interface-based services)
  if IdemPChar(pointer(aCtxt.Url), '/API/') or
     IdemPChar(pointer(aCtxt.Url), '/API') then
    Result := FOriginalHandler(aCtxt)
  else
    // Non-API calls serve static files (SPA frontend)
    Result := HandleStaticFile(aCtxt);
end;

function TGatewayServer.HandleStaticFile(
  aCtxt: THttpServerRequestAbstract): cardinal;
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
    FilePath := FWwwPath + StringReplace(
      Utf8ToString(Copy(Path, 2, MaxInt)), '/', PathDelim, [rfReplaceAll]);
  end;
  Result := ServeStaticFile(FilePath, aCtxt);
  // SPA fallback: unmatched routes serve index.html
  if Result = HTTP_NOTFOUND then
    Result := ServeStaticFile(FWwwPath + 'index.html', aCtxt);
end;

function TGatewayServer.ServeStaticFile(
  const aFilePath: TFileName;
  aCtxt: THttpServerRequestAbstract): cardinal;
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
