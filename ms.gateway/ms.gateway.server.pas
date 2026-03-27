/// <summary>
///   API gateway for the blog microservices.
///   Routes API calls to backend services,
///   validates JWT tokens and serves the web frontend.
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
  mormot.core.os,
  mormot.core.text,
  mormot.core.unicode,
  mormot.core.variants,
  mormot.net.client,
  mormot.net.http,
  mormot.net.server,
  ms.shared,
  ms.shared.client,
  ms.shared.service;

type

  /// <summary>
  ///   Gateway microservice that proxies requests to backend services,
  ///   handles JWT authentication, serves static files, and provides
  ///   aggregated post endpoints with author/tags/comments.
  /// </summary>
  TGatewayServer = class(TMicroService)
  private
    FAuthClient: TMicroClient;
    FUsersClient: TMicroClient;
    FPostsClient: TMicroClient;
    FTagsClient: TMicroClient;
    FCommentsClient: TMicroClient;
    FMediaClient: TMicroClient;
    FWwwPath: TFileName;

    /// <summary>
    ///   Validates a JWT token by calling the auth service.
    /// </summary>
    /// <param name="aToken">
    ///   The JWT token string to validate.
    /// </param>
    /// <param name="aUserId">
    ///   Receives the authenticated user ID on success.
    /// </param>
    /// <returns>
    ///   True if the token is valid.
    /// </returns>
    function ValidateToken(
      const aToken: RawUtf8;
      out aUserId: TID
    ): boolean;

    /// <summary>
    ///   Extracts the bearer token from the Authorization header.
    /// </summary>
    /// <param name="aCtxt">
    ///   The HTTP request context.
    /// </param>
    /// <returns>
    ///   The extracted token string, or empty if not found.
    /// </returns>
    function ExtractBearerToken(
      aCtxt: THttpServerRequestAbstract
    ): RawUtf8;

    /// <summary>
    ///   Serves a static file from the filesystem.
    /// </summary>
    /// <param name="aFilePath">
    ///   The full path to the file to serve.
    /// </param>
    /// <param name="aCtxt">
    ///   The HTTP request context.
    /// </param>
    /// <returns>
    ///   HTTP_SUCCESS if found, HTTP_NOTFOUND otherwise.
    /// </returns>
    function ServeStaticFile(
      const aFilePath: TFileName;
      aCtxt: THttpServerRequestAbstract
    ): cardinal;

    /// <summary>
    ///   Determines the MIME type for a given file name by extension.
    /// </summary>
    /// <param name="aFileName">
    ///   The file name to check.
    /// </param>
    /// <returns>
    ///   The MIME type string.
    /// </returns>
    function GuessMimeType(
      const aFileName: TFileName
    ): RawUtf8;

    /// <summary>
    ///   Proxies a GET request to a backend service.
    /// </summary>
    /// <param name="aClient">
    ///   The backend service client.
    /// </param>
    /// <param name="aPath">
    ///   The request path to forward.
    /// </param>
    /// <param name="aCtxt">
    ///   The HTTP request context.
    /// </param>
    /// <returns>
    ///   The HTTP status code from the backend.
    /// </returns>
    function ProxyGet(
      aClient: TMicroClient;
      const aPath: RawUtf8;
      aCtxt: THttpServerRequestAbstract
    ): cardinal;

    /// <summary>
    ///   Proxies a POST request to a backend service.
    /// </summary>
    /// <param name="aClient">
    ///   The backend service client.
    /// </param>
    /// <param name="aPath">
    ///   The request path to forward.
    /// </param>
    /// <param name="aCtxt">
    ///   The HTTP request context.
    /// </param>
    /// <returns>
    ///   The HTTP status code from the backend.
    /// </returns>
    function ProxyPost(
      aClient: TMicroClient;
      const aPath: RawUtf8;
      aCtxt: THttpServerRequestAbstract
    ): cardinal;

    /// <summary>
    ///   Proxies a PUT request to a backend service.
    /// </summary>
    /// <param name="aClient">
    ///   The backend service client.
    /// </param>
    /// <param name="aPath">
    ///   The request path to forward.
    /// </param>
    /// <param name="aCtxt">
    ///   The HTTP request context.
    /// </param>
    /// <returns>
    ///   The HTTP status code from the backend.
    /// </returns>
    function ProxyPut(
      aClient: TMicroClient;
      const aPath: RawUtf8;
      aCtxt: THttpServerRequestAbstract
    ): cardinal;

    /// <summary>
    ///   Proxies a DELETE request to a backend service.
    /// </summary>
    /// <param name="aClient">
    ///   The backend service client.
    /// </param>
    /// <param name="aPath">
    ///   The request path to forward.
    /// </param>
    /// <param name="aCtxt">
    ///   The HTTP request context.
    /// </param>
    /// <returns>
    ///   The HTTP status code from the backend.
    /// </returns>
    function ProxyDelete(
      aClient: TMicroClient;
      const aPath: RawUtf8;
      aCtxt: THttpServerRequestAbstract
    ): cardinal;

    /// <summary>
    ///   Handles a GET request for a single post, aggregating
    ///   author, tags, and comments from their respective services.
    /// </summary>
    /// <param name="aPostPath">
    ///   The post endpoint path to forward to the posts service.
    /// </param>
    /// <param name="aCtxt">
    ///   The HTTP request context.
    /// </param>
    /// <returns>
    ///   The HTTP status code for the aggregated response.
    /// </returns>
    function HandleGetPost(
      const aPostPath: RawUtf8;
      aCtxt: THttpServerRequestAbstract
    ): cardinal;

    /// <summary>
    ///   Validates the bearer token and returns the user ID.
    ///   Sets an error response if authentication fails.
    /// </summary>
    /// <param name="aCtxt">
    ///   The HTTP request context.
    /// </param>
    /// <param name="aUserId">
    ///   Receives the authenticated user ID on success.
    /// </param>
    /// <returns>
    ///   True if the user is authenticated.
    /// </returns>
    function RequireAuth(
      aCtxt: THttpServerRequestAbstract;
      out aUserId: TID
    ): boolean;

    /// <summary>
    ///   Sets CORS headers on the response.
    /// </summary>
    /// <param name="aCtxt">
    ///   The HTTP request context.
    /// </param>
    procedure SetCorsHeaders(
      aCtxt: THttpServerRequestAbstract
    );
  protected

    /// <summary>
    ///   Initializes backend service clients and the static file path.
    /// </summary>
    procedure DoInitialize; override;

    /// <summary>
    ///   Releases all backend service clients.
    /// </summary>
    procedure DoFinalize; override;

    /// <summary>
    ///   Main request router for the gateway.
    /// </summary>
    /// <param name="aCtxt">
    ///   The HTTP server request context.
    /// </param>
    /// <returns>
    ///   The HTTP status code for the response.
    /// </returns>
    function OnRequest(
      aCtxt: THttpServerRequestAbstract
    ): cardinal; override;
  end;

implementation

{ TGatewayServer }

// ===== Initialization =====

procedure TGatewayServer.DoFinalize;
begin
  FreeAndNil(FMediaClient);
  FreeAndNil(FCommentsClient);
  FreeAndNil(FTagsClient);
  FreeAndNil(FPostsClient);
  FreeAndNil(FUsersClient);
  FreeAndNil(FAuthClient);
end;

procedure TGatewayServer.DoInitialize;
begin
  FWwwPath := Executable.ProgramFilePath + 'www' + PathDelim;
  if not DirectoryExists(FWwwPath) then
    CreateDir(FWwwPath);
  FAuthClient := TMicroClient.Create(Config.AuthUrl, SERVICE_AUTH);
  FUsersClient := TMicroClient.Create(Config.UsersUrl, SERVICE_USERS);
  FPostsClient := TMicroClient.Create(Config.PostsUrl, SERVICE_POSTS);
  FTagsClient := TMicroClient.Create(Config.TagsUrl, SERVICE_TAGS);
  FCommentsClient := TMicroClient.Create(Config.CommentsUrl, SERVICE_COMMENTS);
  FMediaClient := TMicroClient.Create(Config.MediaUrl, SERVICE_MEDIA);
end;

// ===== Helper methods =====

function TGatewayServer.ExtractBearerToken(
  aCtxt: THttpServerRequestAbstract
): RawUtf8;
var
  AuthHeader: RawUtf8;
begin
  Result := '';
  AuthHeader := FindIniNameValue(pointer(aCtxt.InHeaders),
    'AUTHORIZATION: ');
  if IdemPChar(pointer(AuthHeader), 'BEARER ') then
    Result := TrimU(Copy(AuthHeader, 8, MaxInt));
end;

function TGatewayServer.RequireAuth(
  aCtxt: THttpServerRequestAbstract;
  out aUserId: TID
): boolean;
var
  Token: RawUtf8;
begin
  Token := ExtractBearerToken(aCtxt);
  Result := ValidateToken(Token, aUserId);
  if not Result then
  begin
    aCtxt.OutContent := '{"error":"unauthorized"}';
    aCtxt.OutContentType := JSON_CONTENT_TYPE;
  end;
end;

procedure TGatewayServer.SetCorsHeaders(
  aCtxt: THttpServerRequestAbstract
);
begin
  aCtxt.OutCustomHeaders :=
    'Access-Control-Allow-Origin: *'#13#10 +
    'Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS'#13#10 +
    'Access-Control-Allow-Headers: Content-Type, Authorization';
end;

function TGatewayServer.ValidateToken(
  const aToken: RawUtf8;
  out aUserId: TID
): boolean;
var
  StatusCode: integer;
  ResponseBody: RawUtf8;
  JsonDoc: TDocVariantData;
begin
  Result := False;
  aUserId := 0;
  if aToken = '' then
    Exit;
  ResponseBody := FAuthClient.Post('/api/auth/validate',
    FormatUtf8('{"Token":"%"}', [aToken]), StatusCode);
  if StatusCode = 200 then
  begin
    JsonDoc.InitJson(ResponseBody, JSON_FAST_FLOAT);
    Result := JsonDoc.B['valid'];
    if Result then
      aUserId := JsonDoc.I['userId'];
  end;
end;

// ===== Proxy methods =====

function TGatewayServer.ProxyDelete(
  aClient: TMicroClient;
  const aPath: RawUtf8;
  aCtxt: THttpServerRequestAbstract
): cardinal;
var
  StatusCode: integer;
begin
  aCtxt.OutContent := aClient.Delete(aPath, StatusCode);
  aCtxt.OutContentType := JSON_CONTENT_TYPE;
  Result := StatusCode;
end;

function TGatewayServer.ProxyGet(
  aClient: TMicroClient;
  const aPath: RawUtf8;
  aCtxt: THttpServerRequestAbstract
): cardinal;
var
  StatusCode: integer;
begin
  aCtxt.OutContent := aClient.Get(aPath, StatusCode);
  aCtxt.OutContentType := JSON_CONTENT_TYPE;
  Result := StatusCode;
end;

function TGatewayServer.ProxyPost(
  aClient: TMicroClient;
  const aPath: RawUtf8;
  aCtxt: THttpServerRequestAbstract
): cardinal;
var
  StatusCode: integer;
begin
  aCtxt.OutContent := aClient.Post(aPath,
    aCtxt.InContent, StatusCode);
  aCtxt.OutContentType := JSON_CONTENT_TYPE;
  Result := StatusCode;
end;

function TGatewayServer.ProxyPut(
  aClient: TMicroClient;
  const aPath: RawUtf8;
  aCtxt: THttpServerRequestAbstract
): cardinal;
var
  StatusCode: integer;
begin
  aCtxt.OutContent := aClient.Put(aPath,
    aCtxt.InContent, StatusCode);
  aCtxt.OutContentType := JSON_CONTENT_TYPE;
  Result := StatusCode;
end;

// ===== Aggregated post endpoint =====

function TGatewayServer.HandleGetPost(
  const aPostPath: RawUtf8;
  aCtxt: THttpServerRequestAbstract
): cardinal;
var
  StatusCode: integer;
  PostJson, AuthorJson, TagsJson, CommentsJson: RawUtf8;
  PostDoc: TDocVariantData;
  AuthorId, PostId: TID;
begin
  // Load post
  PostJson := FPostsClient.Get(aPostPath, StatusCode);
  if StatusCode <> 200 then
  begin
    aCtxt.OutContent := PostJson;
    aCtxt.OutContentType := JSON_CONTENT_TYPE;
    Result := StatusCode;
    Exit;
  end;

  PostDoc.InitJson(PostJson, JSON_FAST_FLOAT);
  AuthorId := PostDoc.I['AuthorId'];
  PostId := PostDoc.I['RowID'];
  if PostId = 0 then
    PostId := PostDoc.I['ID'];

  // Load author
  AuthorJson := FUsersClient.Get(
    FormatUtf8('/api/users/%', [AuthorId]), StatusCode);
  if StatusCode = 200 then
  begin
    PostDoc.AddValue('Author', _JsonFast(AuthorJson));
  end
  else
  begin
    PostDoc.AddValue('Author', null);
  end;

  // Load tags
  if PostId > 0 then
  begin
    TagsJson := FTagsClient.Get(
      FormatUtf8('/api/posts/%/tags', [PostId]), StatusCode);
    if StatusCode = 200 then
    begin
      PostDoc.AddValue('Tags', _JsonFast(TagsJson));
    end
    else
    begin
      PostDoc.AddValue('Tags', _ArrFast([]));
    end;

    // Load comments (approved only)
    CommentsJson := FCommentsClient.Get(
      FormatUtf8('/api/posts/%/comments', [PostId]), StatusCode);
    if StatusCode = 200 then
    begin
      PostDoc.AddValue('Comments', _JsonFast(CommentsJson));
    end
    else
    begin
      PostDoc.AddValue('Comments', _ArrFast([]));
    end;
  end;

  aCtxt.OutContent := PostDoc.ToJson;
  aCtxt.OutContentType := JSON_CONTENT_TYPE;
  Result := HTTP_SUCCESS;
end;

// ===== Static files =====

function TGatewayServer.GuessMimeType(
  const aFileName: TFileName
): RawUtf8;
var
  FileExt: string;
begin
  FileExt := System.SysUtils.LowerCase(ExtractFileExt(aFileName));
  if FileExt = '.html' then
  begin
    Result := 'text/html; charset=utf-8';
  end
  else if FileExt = '.css' then
  begin
    Result := 'text/css; charset=utf-8';
  end
  else if FileExt = '.js' then
  begin
    Result := 'application/javascript; charset=utf-8';
  end
  else if FileExt = '.json' then
  begin
    Result := JSON_CONTENT_TYPE;
  end
  else if FileExt = '.png' then
  begin
    Result := 'image/png';
  end
  else if FileExt = '.jpg' then
  begin
    Result := 'image/jpeg';
  end
  else if FileExt = '.jpeg' then
  begin
    Result := 'image/jpeg';
  end
  else if FileExt = '.gif' then
  begin
    Result := 'image/gif';
  end
  else if FileExt = '.svg' then
  begin
    Result := 'image/svg+xml';
  end
  else if FileExt = '.ico' then
  begin
    Result := 'image/x-icon';
  end
  else if FileExt = '.woff2' then
  begin
    Result := 'font/woff2';
  end
  else if FileExt = '.woff' then
  begin
    Result := 'font/woff';
  end
  else
  begin
    Result := 'application/octet-stream';
  end;
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
  begin
    Result := HTTP_NOTFOUND;
  end;
end;

// ===== Main routing =====

function TGatewayServer.OnRequest(
  aCtxt: THttpServerRequestAbstract
): cardinal;
var
  Path: RawUtf8;
  UserId: TID;
  FilePath: TFileName;
  QueryPos: PtrInt;
begin
  // Extract path without query string for routing decisions.
  // For forwarding to backend services, aCtxt.Url
  // (with query string) is used.
  Path := aCtxt.Url;
  QueryPos := PosExChar('?', Path);
  if QueryPos > 0 then
    Path := Copy(Path, 1, QueryPos - 1);
  SetCorsHeaders(aCtxt);

  // CORS Preflight
  if aCtxt.Method = 'OPTIONS' then
  begin
    aCtxt.OutContent := '';
    Result := HTTP_NOCONTENT;
    Exit;
  end;

  // ===== AUTH API =====

  if IdemPChar(pointer(Path), '/API/AUTH/') then
  begin
    if aCtxt.Method = 'POST' then
    begin
      Result := ProxyPost(FAuthClient, aCtxt.Url, aCtxt);
    end
    else if aCtxt.Method = 'PUT' then
    begin
      if not RequireAuth(aCtxt, UserId) then
      begin
        Result := HTTP_UNAUTHORIZED;
      end
      else
      begin
        Result := ProxyPut(FAuthClient, aCtxt.Url, aCtxt);
      end;
    end
    else
    begin
      Result := HTTP_NOTALLOWED;
    end;
  end

  // ===== USERS API =====

  else if IdemPChar(pointer(Path), '/API/USERS') then
  begin
    case aCtxt.Method[1] of
      'G': // GET
      begin
        Result := ProxyGet(FUsersClient, aCtxt.Url, aCtxt);
      end;
      'P': // POST or PUT
      begin
        if not RequireAuth(aCtxt, UserId) then
        begin
          Result := HTTP_UNAUTHORIZED;
        end
        else if aCtxt.Method = 'POST' then
        begin
          Result := ProxyPost(FUsersClient, aCtxt.Url, aCtxt);
        end
        else
        begin
          Result := ProxyPut(FUsersClient, aCtxt.Url, aCtxt);
        end;
      end;
      'D': // DELETE
      begin
        if not RequireAuth(aCtxt, UserId) then
        begin
          Result := HTTP_UNAUTHORIZED;
        end
        else
        begin
          Result := ProxyDelete(FUsersClient, aCtxt.Url, aCtxt);
        end;
      end;
    else
      Result := HTTP_NOTALLOWED;
    end;
  end

  // ===== POSTS API =====

  else if IdemPChar(pointer(Path), '/API/POSTS') then
  begin
    // Comment sub-routes: /api/posts/{id}/comments
    if PosEx('/comments', Path) > 0 then
    begin
      if aCtxt.Method = 'POST' then
      begin
        Result := ProxyPost(FCommentsClient, aCtxt.Url, aCtxt);
      end
      else if aCtxt.Method = 'GET' then
      begin
        Result := ProxyGet(FCommentsClient, aCtxt.Url, aCtxt);
      end
      else
      begin
        Result := HTTP_NOTALLOWED;
      end;
    end
    // Tag sub-routes: /api/posts/{id}/tags
    else if PosEx('/tags', Path) > 0 then
    begin
      if aCtxt.Method = 'GET' then
      begin
        Result := ProxyGet(FTagsClient, aCtxt.Url, aCtxt);
      end
      else
      begin
        if not RequireAuth(aCtxt, UserId) then
        begin
          Result := HTTP_UNAUTHORIZED;
        end
        else if aCtxt.Method = 'PUT' then
        begin
          Result := ProxyPut(FTagsClient, aCtxt.Url, aCtxt);
        end
        else
        begin
          Result := ProxyPost(FTagsClient, aCtxt.Url, aCtxt);
        end;
      end;
    end
    // Regular post routes
    else
    begin
      case aCtxt.Method[1] of
        'G': // GET -- aggregated with author/tags/comments
        begin
          // Single post: aggregated response
          if (Path <> '/api/posts') and
             not IdemPChar(pointer(Path), '/API/POSTS/BY-') then
          begin
            Result := HandleGetPost(aCtxt.Url, aCtxt);
          end
          else
          begin
            Result := ProxyGet(FPostsClient, aCtxt.Url, aCtxt);
          end;
        end;
        'P': // POST or PUT (both start with 'P')
        begin
          if not RequireAuth(aCtxt, UserId) then
          begin
            Result := HTTP_UNAUTHORIZED;
          end
          else if aCtxt.Method = 'POST' then
          begin
            Result := ProxyPost(FPostsClient, aCtxt.Url, aCtxt);
          end
          else
          begin
            Result := ProxyPut(FPostsClient, aCtxt.Url, aCtxt);
          end;
        end;
        'D': // DELETE
        begin
          if not RequireAuth(aCtxt, UserId) then
          begin
            Result := HTTP_UNAUTHORIZED;
          end
          else
          begin
            Result := ProxyDelete(FPostsClient, aCtxt.Url, aCtxt);
          end;
        end;
      else
        Result := HTTP_NOTALLOWED;
      end;
    end;
  end

  // ===== TAGS API =====

  else if IdemPChar(pointer(Path), '/API/TAGS') then
  begin
    case aCtxt.Method[1] of
      'G':
      begin
        Result := ProxyGet(FTagsClient, aCtxt.Url, aCtxt);
      end;
      'P': // POST/PUT
      begin
        if not RequireAuth(aCtxt, UserId) then
        begin
          Result := HTTP_UNAUTHORIZED;
        end
        else if aCtxt.Method = 'POST' then
        begin
          Result := ProxyPost(FTagsClient, aCtxt.Url, aCtxt);
        end
        else
        begin
          Result := ProxyPut(FTagsClient, aCtxt.Url, aCtxt);
        end;
      end;
      'D':
      begin
        if not RequireAuth(aCtxt, UserId) then
        begin
          Result := HTTP_UNAUTHORIZED;
        end
        else
        begin
          Result := ProxyDelete(FTagsClient, aCtxt.Url, aCtxt);
        end;
      end;
    else
      Result := HTTP_NOTALLOWED;
    end;
  end

  // ===== COMMENTS API =====
  // POST /api/posts/{id}/comments is public (no auth)
  // Moderation requires auth

  else if IdemPChar(pointer(Path), '/API/COMMENTS') then
  begin
    case aCtxt.Method[1] of
      'G':
      begin
        // pending requires auth
        if Path = '/api/comments/pending' then
        begin
          if not RequireAuth(aCtxt, UserId) then
          begin
            Result := HTTP_UNAUTHORIZED;
          end
          else
          begin
            Result := ProxyGet(FCommentsClient, aCtxt.Url, aCtxt);
          end;
        end
        else
        begin
          Result := ProxyGet(FCommentsClient, aCtxt.Url, aCtxt);
        end;
      end;
      'P': // PUT (approve/reject) requires auth
      begin
        if not RequireAuth(aCtxt, UserId) then
        begin
          Result := HTTP_UNAUTHORIZED;
        end
        else if aCtxt.Method = 'PUT' then
        begin
          Result := ProxyPut(FCommentsClient, aCtxt.Url, aCtxt);
        end
        else
        begin
          Result := ProxyPost(FCommentsClient, aCtxt.Url, aCtxt);
        end;
      end;
      'D':
      begin
        if not RequireAuth(aCtxt, UserId) then
        begin
          Result := HTTP_UNAUTHORIZED;
        end
        else
        begin
          Result := ProxyDelete(FCommentsClient, aCtxt.Url, aCtxt);
        end;
      end;
    else
      Result := HTTP_NOTALLOWED;
    end;
  end

  // ===== MEDIA API =====

  else if IdemPChar(pointer(Path), '/API/MEDIA') then
  begin
    if aCtxt.Method = 'GET' then
    begin
      // Serve image: pass through directly (including binary data)
      Result := ProxyGet(FMediaClient, aCtxt.Url, aCtxt);
      // Content-Type is taken from the media service
    end
    else if aCtxt.Method = 'POST' then
    begin
      if not RequireAuth(aCtxt, UserId) then
      begin
        Result := HTTP_UNAUTHORIZED;
      end
      else
      begin
        Result := ProxyPost(FMediaClient, aCtxt.Url, aCtxt);
      end;
    end
    else if aCtxt.Method = 'DELETE' then
    begin
      if not RequireAuth(aCtxt, UserId) then
      begin
        Result := HTTP_UNAUTHORIZED;
      end
      else
      begin
        Result := ProxyDelete(FMediaClient, aCtxt.Url, aCtxt);
      end;
    end
    else
    begin
      Result := HTTP_NOTALLOWED;
    end;
  end

  // ===== STATIC FILES =====

  else if (aCtxt.Method = 'GET') then
  begin
    // /api/health and /api/shutdown go to base class
    if IdemPChar(pointer(Path), '/API/') then
    begin
      Result := inherited OnRequest(aCtxt);
      Exit;
    end;

    // Static files from www/
    if (Path = '/') or (Path = '') then
    begin
      FilePath := FWwwPath + 'index.html';
    end
    else
    begin
      // Prevent path traversal
      if PosEx('..', Path) > 0 then
      begin
        Result := HTTP_FORBIDDEN;
        Exit;
      end;
      FilePath := FWwwPath +
        StringReplace(Utf8ToString(Copy(Path, 2, MaxInt)),
          '/', PathDelim, [rfReplaceAll]);
    end;

    Result := ServeStaticFile(FilePath, aCtxt);

    // SPA fallback: routes not found -> index.html
    if Result = HTTP_NOTFOUND then
      Result := ServeStaticFile(FWwwPath + 'index.html', aCtxt);
  end

  else
    Result := inherited OnRequest(aCtxt);
end;

end.
