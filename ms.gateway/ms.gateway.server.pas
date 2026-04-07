/// <summary>
///   API Gateway: routes requests to backend microservices
///   using interface-based service proxies and serves the web frontend.
/// </summary>
unit ms.gateway.server;

{$I mormot.defines.inc}

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
  mormot.core.text,
  mormot.core.unicode,
  mormot.core.variants,
  mormot.net.async,
  mormot.net.http,
  mormot.net.server,
  mormot.orm.base,
  mormot.orm.core,
  mormot.core.rtti,
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
  ///   Proxy implementation of IAuth that delegates to the auth backend.
  /// </summary>
  TAuthProxy = class(TInterfacedObject, IAuth)
  private
    FRemote: IAuth;
  public
    constructor Create(const aRemote: IAuth);
    procedure Challenge(const aEmail: RawUtf8;
      out aMcfInfo, aServerNonce: RawUtf8);
    function Authenticate(const aEmail, aServerNonce, aClientProof: RawUtf8;
      out aToken: RawUtf8; out aUserId: TID;
      out aServerProof: RawUtf8): boolean;
    function Register(const aEmail, aPassword: RawUtf8;
      aUserId: TID): TID;
    function Validate(const aToken: RawUtf8;
      out aUserId: TID): boolean;
    function ChangePassword(aUserId: TID;
      const aOldPassword, aNewPassword: RawUtf8): boolean;
  end;

  /// <summary>
  ///   Proxy implementation of IUser.
  /// </summary>
  TUserProxy = class(TInterfacedObject, IUser)
  private
    FRemote: IUser;
  public
    constructor Create(const aRemote: IUser);
    function Get(aId: TID): RawJson;
    function GetAll: RawJson;
    function Add(const aData: RawJson): TID;
    function Update(aId: TID; const aData: RawJson): boolean;
    function Remove(aId: TID): boolean;
  end;

  /// <summary>
  ///   Proxy implementation of IPost.
  /// </summary>
  TPostProxy = class(TInterfacedObject, IPost)
  private
    FRemote: IPost;
  public
    constructor Create(const aRemote: IPost);
    function Get(aId: TID): RawJson;
    function GetBySlug(const aSlug: RawUtf8): RawJson;
    function GetList(aPage, aLimit, aStatus: integer;
      aAuthorId: TID): RawJson;
    function Add(const aData: RawJson): TID;
    function Update(aId: TID; const aData: RawJson): boolean;
    function Remove(aId: TID): boolean;
  end;

  /// <summary>
  ///   Proxy implementation of ITag.
  /// </summary>
  TTagProxy = class(TInterfacedObject, ITag)
  private
    FRemote: ITag;
  public
    constructor Create(const aRemote: ITag);
    function Get(aId: TID): RawJson;
    function GetAll: RawJson;
    function GetByPost(aPostId: TID): RawJson;
    function SetPostTags(aPostId: TID;
      const aTagIds: RawJson): boolean;
    function Add(const aData: RawJson): TID;
    function Update(aId: TID; const aData: RawJson): boolean;
    function Remove(aId: TID): boolean;
  end;

  /// <summary>
  ///   Proxy implementation of IComment.
  /// </summary>
  TCommentProxy = class(TInterfacedObject, IComment)
  private
    FRemote: IComment;
  public
    constructor Create(const aRemote: IComment);
    function GetByPost(aPostId: TID): RawJson;
    function GetPending: RawJson;
    function Add(aPostId: TID; const aData: RawJson): TID;
    function Approve(aId, aModeratedBy: TID): boolean;
    function Reject(aId, aModeratedBy: TID): boolean;
    function Remove(aId: TID): boolean;
  end;

  /// <summary>
  ///   Proxy implementation of IMedia.
  /// </summary>
  TMediaProxy = class(TInterfacedObject, IMedia)
  private
    FRemote: IMedia;
  public
    constructor Create(const aRemote: IMedia);
    function Upload(const aFileName, aFileData, aAltText: RawUtf8;
      aUploadedBy: TID): TID;
    function GetInfo(aId: TID): RawJson;
    function GetFile(aId: TID;
      out aContentType: RawUtf8): RawByteString;
    function Remove(aId: TID): boolean;
  end;

  /// <summary>
  ///   Aggregation service: enriches a post with author, tags, comments.
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
    function ServeStaticFile(const aFilePath: TFileName;
      aCtxt: THttpServerRequestAbstract): cardinal;
    function GuessMimeType(const aFileName: TFileName): RawUtf8;
    function HandleRequest(aCtxt: THttpServerRequestAbstract): cardinal;
    function HandleStaticFile(aCtxt: THttpServerRequestAbstract): cardinal;
  protected
    function CreateModel: TOrmModel; override;
    procedure SetupServices; override;
    procedure DoInitialize; override;
    procedure DoFinalize; override;
  end;

implementation

{ TAuthProxy }

constructor TAuthProxy.Create(const aRemote: IAuth);
begin
  inherited Create;
  FRemote := aRemote;
end;

procedure TAuthProxy.Challenge(const aEmail: RawUtf8;
  out aMcfInfo, aServerNonce: RawUtf8);
begin
  FRemote.Challenge(aEmail, aMcfInfo, aServerNonce);
end;

function TAuthProxy.Authenticate(const aEmail, aServerNonce,
  aClientProof: RawUtf8; out aToken: RawUtf8; out aUserId: TID;
  out aServerProof: RawUtf8): boolean;
begin
  Result := FRemote.Authenticate(aEmail, aServerNonce, aClientProof,
    aToken, aUserId, aServerProof);
end;

function TAuthProxy.Register(const aEmail, aPassword: RawUtf8;
  aUserId: TID): TID;
begin
  Result := FRemote.Register(aEmail, aPassword, aUserId);
end;

function TAuthProxy.Validate(const aToken: RawUtf8;
  out aUserId: TID): boolean;
begin
  Result := FRemote.Validate(aToken, aUserId);
end;

function TAuthProxy.ChangePassword(aUserId: TID;
  const aOldPassword, aNewPassword: RawUtf8): boolean;
begin
  Result := FRemote.ChangePassword(aUserId, aOldPassword, aNewPassword);
end;

{ TUserProxy }

constructor TUserProxy.Create(const aRemote: IUser);
begin
  inherited Create;
  FRemote := aRemote;
end;

function TUserProxy.Get(aId: TID): RawJson;
begin
  Result := FRemote.Get(aId);
end;

function TUserProxy.GetAll: RawJson;
begin
  Result := FRemote.GetAll;
end;

function TUserProxy.Add(const aData: RawJson): TID;
begin
  Result := FRemote.Add(aData);
end;

function TUserProxy.Update(aId: TID; const aData: RawJson): boolean;
begin
  Result := FRemote.Update(aId, aData);
end;

function TUserProxy.Remove(aId: TID): boolean;
begin
  Result := FRemote.Remove(aId);
end;

{ TPostProxy }

constructor TPostProxy.Create(const aRemote: IPost);
begin
  inherited Create;
  FRemote := aRemote;
end;

function TPostProxy.Get(aId: TID): RawJson;
begin
  Result := FRemote.Get(aId);
end;

function TPostProxy.GetBySlug(const aSlug: RawUtf8): RawJson;
begin
  Result := FRemote.GetBySlug(aSlug);
end;

function TPostProxy.GetList(aPage, aLimit, aStatus: integer;
  aAuthorId: TID): RawJson;
begin
  Result := FRemote.GetList(aPage, aLimit, aStatus, aAuthorId);
end;

function TPostProxy.Add(const aData: RawJson): TID;
begin
  Result := FRemote.Add(aData);
end;

function TPostProxy.Update(aId: TID; const aData: RawJson): boolean;
begin
  Result := FRemote.Update(aId, aData);
end;

function TPostProxy.Remove(aId: TID): boolean;
begin
  Result := FRemote.Remove(aId);
end;

{ TTagProxy }

constructor TTagProxy.Create(const aRemote: ITag);
begin
  inherited Create;
  FRemote := aRemote;
end;

function TTagProxy.Get(aId: TID): RawJson;
begin
  Result := FRemote.Get(aId);
end;

function TTagProxy.GetAll: RawJson;
begin
  Result := FRemote.GetAll;
end;

function TTagProxy.GetByPost(aPostId: TID): RawJson;
begin
  Result := FRemote.GetByPost(aPostId);
end;

function TTagProxy.SetPostTags(aPostId: TID;
  const aTagIds: RawJson): boolean;
begin
  Result := FRemote.SetPostTags(aPostId, aTagIds);
end;

function TTagProxy.Add(const aData: RawJson): TID;
begin
  Result := FRemote.Add(aData);
end;

function TTagProxy.Update(aId: TID; const aData: RawJson): boolean;
begin
  Result := FRemote.Update(aId, aData);
end;

function TTagProxy.Remove(aId: TID): boolean;
begin
  Result := FRemote.Remove(aId);
end;

{ TCommentProxy }

constructor TCommentProxy.Create(const aRemote: IComment);
begin
  inherited Create;
  FRemote := aRemote;
end;

function TCommentProxy.GetByPost(aPostId: TID): RawJson;
begin
  Result := FRemote.GetByPost(aPostId);
end;

function TCommentProxy.GetPending: RawJson;
begin
  Result := FRemote.GetPending;
end;

function TCommentProxy.Add(aPostId: TID;
  const aData: RawJson): TID;
begin
  Result := FRemote.Add(aPostId, aData);
end;

function TCommentProxy.Approve(aId, aModeratedBy: TID): boolean;
begin
  Result := FRemote.Approve(aId, aModeratedBy);
end;

function TCommentProxy.Reject(aId, aModeratedBy: TID): boolean;
begin
  Result := FRemote.Reject(aId, aModeratedBy);
end;

function TCommentProxy.Remove(aId: TID): boolean;
begin
  Result := FRemote.Remove(aId);
end;

{ TMediaProxy }

constructor TMediaProxy.Create(const aRemote: IMedia);
begin
  inherited Create;
  FRemote := aRemote;
end;

function TMediaProxy.Upload(const aFileName, aFileData,
  aAltText: RawUtf8; aUploadedBy: TID): TID;
begin
  Result := FRemote.Upload(aFileName, aFileData, aAltText, aUploadedBy);
end;

function TMediaProxy.GetInfo(aId: TID): RawJson;
begin
  Result := FRemote.GetInfo(aId);
end;

function TMediaProxy.GetFile(aId: TID;
  out aContentType: RawUtf8): RawByteString;
begin
  Result := FRemote.GetFile(aId, aContentType);
end;

function TMediaProxy.Remove(aId: TID): boolean;
begin
  Result := FRemote.Remove(aId);
end;

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
  if (PostJson = '') or (PostJson = '{}') then
  begin
    Result := '{}';
    Exit;
  end;
  PostDoc.InitJson(PostJson, JSON_FAST_FLOAT);
  AuthorId := PostDoc.I['AuthorId'];
  PostId := PostDoc.I['RowID'];
  if PostId = 0 then
    PostId := PostDoc.I['ID'];
  // Enrich with author
  AuthorJson := FUsers.Get(AuthorId);
  if (AuthorJson <> '') and (AuthorJson <> '{}') then
    PostDoc.AddValue('Author', _JsonFast(AuthorJson))
  else
    PostDoc.AddValue('Author', null);
  // Enrich with tags
  if PostId > 0 then
  begin
    TagsJson := FTags.GetByPost(PostId);
    if (TagsJson <> '') and (TagsJson <> '[]') then
      PostDoc.AddValue('Tags', _JsonFast(TagsJson))
    else
      PostDoc.AddValue('Tags', _ArrFast([]));
    // Enrich with comments
    CommentsJson := FComments.GetByPost(PostId);
    if (CommentsJson <> '') and (CommentsJson <> '[]') then
      PostDoc.AddValue('Comments', _JsonFast(CommentsJson))
    else
      PostDoc.AddValue('Comments', _ArrFast([]));
  end;
  Result := RawJson(PostDoc.ToJson);
end;

{ TGatewayServer }

function TGatewayServer.ConnectToBackend(const aHost, aPort: RawUtf8;
  const aInterfaces: array of PRttiInfo): TRestHttpClient;
var
  ClientModel: TOrmModel;
  i: PtrInt;
begin
  ClientModel := TOrmModel.Create([], MODEL_ROOT);
  Result := TRestHttpClient.Create(aHost, aPort, ClientModel);
  Result.Model.Owner := Result; // model freed with client
  Result.ServiceRegister(aInterfaces, sicShared);
  // Backend services use ResultAsJsonObjectWithoutResult format --
  // the client factories must match to parse responses correctly
  for i := 0 to High(aInterfaces) do
    TServiceFactoryClient(Result.Services.Info(aInterfaces[i]))
      .ResultAsJsonObjectWithoutResult := True;
end;

function TGatewayServer.CreateModel: TOrmModel;
begin
  Result := TOrmModel.Create([], MODEL_ROOT);
end;

procedure TGatewayServer.SetupServices;
var
  Factory: TServiceFactoryServerAbstract;

  procedure RegisterProxy(aImpl: TInterfacedObject;
    aInterface: PRttiInfo);
  begin
    Factory := FRestServer.ServiceRegister(
      aImpl, [aInterface]) ;
    Factory.ByPassAuthentication := True;
    Factory.ResultAsJsonObjectWithoutResult := True;
  end;

begin
  FWwwPath := Executable.ProgramFilePath + 'www' + PathDelim;
  if not DirectoryExists(FWwwPath) then
    CreateDir(FWwwPath);
  // Connect to backend services and resolve interfaces
  FAuthClient := ConnectToBackend('localhost', PORT_AUTH,
    [TypeInfo(IAuth)]);
  FAuthClient.Services.Resolve(IAuth, FAuth);
  FUsersClient := ConnectToBackend('localhost', PORT_USERS,
    [TypeInfo(IUser)]);
  FUsersClient.Services.Resolve(IUser, FUsers);
  FPostsClient := ConnectToBackend('localhost', PORT_POSTS,
    [TypeInfo(IPost)]);
  FPostsClient.Services.Resolve(IPost, FPosts);
  FTagsClient := ConnectToBackend('localhost', PORT_TAGS,
    [TypeInfo(ITag)]);
  FTagsClient.Services.Resolve(ITag, FTags);
  FCommentsClient := ConnectToBackend('localhost', PORT_COMMENTS,
    [TypeInfo(IComment)]);
  FCommentsClient.Services.Resolve(IComment, FComments);
  FMediaClient := ConnectToBackend('localhost', PORT_MEDIA,
    [TypeInfo(IMedia)]);
  FMediaClient.Services.Resolve(IMedia, FMedia);
  // Register proxy services on our REST server
  RegisterProxy(TAuthProxy.Create(FAuth), TypeInfo(IAuth));
  RegisterProxy(TUserProxy.Create(FUsers), TypeInfo(IUser));
  RegisterProxy(TPostProxy.Create(FPosts), TypeInfo(IPost));
  RegisterProxy(TTagProxy.Create(FTags), TypeInfo(ITag));
  RegisterProxy(TCommentProxy.Create(FComments), TypeInfo(IComment));
  RegisterProxy(TMediaProxy.Create(FMedia), TypeInfo(IMedia));
  // Register aggregation service
  RegisterProxy(
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
    Result := HTTP_NOCONTENT;
    Exit;
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
    begin
      Result := HTTP_FORBIDDEN;
      Exit;
    end;
    FilePath := FWwwPath + StringReplace(
      Utf8ToString(Copy(Path, 2, MaxInt)), '/', PathDelim, [rfReplaceAll]);
  end;
  Result := ServeStaticFile(FilePath, aCtxt);
  // SPA fallback: unmatched routes serve index.html
  if Result = HTTP_NOTFOUND then
    Result := ServeStaticFile(FWwwPath + 'index.html', aCtxt);
end;

function TGatewayServer.GuessMimeType(
  const aFileName: TFileName): RawUtf8;
var
  Ext: string;
begin
  Ext := SysUtils.LowerCase(ExtractFileExt(aFileName));
  if Ext = '.html' then Result := 'text/html; charset=utf-8'
  else if Ext = '.css' then Result := 'text/css; charset=utf-8'
  else if Ext = '.js' then Result := 'application/javascript; charset=utf-8'
  else if Ext = '.json' then Result := JSON_CONTENT_TYPE
  else if Ext = '.png' then Result := 'image/png'
  else if Ext = '.jpg' then Result := 'image/jpeg'
  else if Ext = '.jpeg' then Result := 'image/jpeg'
  else if Ext = '.gif' then Result := 'image/gif'
  else if Ext = '.svg' then Result := 'image/svg+xml'
  else if Ext = '.ico' then Result := 'image/x-icon'
  else if Ext = '.woff2' then Result := 'font/woff2'
  else if Ext = '.woff' then Result := 'font/woff'
  else Result := 'application/octet-stream';
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
