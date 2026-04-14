/// <summary>
///   Shared constants, types, and helper functions used by all blog microservices.
///
///   Contains:
///   - Service port and name constants for all 7 microservices.
///   - JWT configuration constants.
///   - Status code constants for posts and comments.
///   - <c>TMicroServiceConfig</c>: configuration record loaded from JSON files via mORMot2's <c>RecordLoadJson</c>.
///   - <c>TextToSlug</c>: URL-friendly slug generator with German umlaut support.
///   - <c>GuessMimeType</c>: file extension to MIME type mapping.
/// </summary>
unit ms.shared;

{$SCOPEDENUMS ON}
{$I mormot.defines.inc}
{$WARN SYMBOL_PLATFORM OFF}
{$WARN UNIT_PLATFORM OFF}

interface

uses
  System.SysUtils,
  mormot.core.base,
  mormot.core.json,
  mormot.core.os,
  mormot.core.text,
  mormot.core.unicode;

const

  /// <summary>
  ///   HTTP port for the gateway service.
  /// </summary>
  PORT_GATEWAY  = '8080';

  /// <summary>
  ///   HTTP port for the authentication service.
  /// </summary>
  PORT_AUTH     = '8081';

  /// <summary>
  ///   HTTP port for the users service.
  /// </summary>
  PORT_USERS   = '8082';

  /// <summary>
  ///   HTTP port for the posts service.
  /// </summary>
  PORT_POSTS   = '8083';

  /// <summary>
  ///   HTTP port for the tags service.
  /// </summary>
  PORT_TAGS    = '8084';

  /// <summary>
  ///   HTTP port for the comments service.
  /// </summary>
  PORT_COMMENTS = '8085';

  /// <summary>
  ///   HTTP port for the media service.
  /// </summary>
  PORT_MEDIA   = '8086';

  /// <summary>
  ///   HTTP port for the configuration service.
  /// </summary>
  PORT_CONFIG    = '8087';

  /// <summary>
  ///   HTTP port for the analytics service.
  /// </summary>
  PORT_ANALYTICS = '8088';

  /// <summary>
  ///   HTTP port for the central logging service.
  /// </summary>
  PORT_LOGS      = '8089';

  /// <summary>
  ///   HTTP port for the event-bus service (learning experiment, see SPEC #22 / PLAN #23).
  /// </summary>
  PORT_EVENTS    = '8091';

  /// <summary>
  ///   Internal service name for the gateway.
  /// </summary>
  SERVICE_GATEWAY  = 'ms.gateway';

  /// <summary>
  ///   Internal service name for authentication.
  /// </summary>
  SERVICE_AUTH     = 'ms.auth';

  /// <summary>
  ///   Internal service name for user management.
  /// </summary>
  SERVICE_USERS    = 'ms.users';

  /// <summary>
  ///   Internal service name for blog posts.
  /// </summary>
  SERVICE_POSTS    = 'ms.posts';

  /// <summary>
  ///   Internal service name for tags.
  /// </summary>
  SERVICE_TAGS     = 'ms.tags';

  /// <summary>
  ///   Internal service name for comments.
  /// </summary>
  SERVICE_COMMENTS = 'ms.comments';

  /// <summary>
  ///   Internal service name for media uploads.
  /// </summary>
  SERVICE_MEDIA    = 'ms.media';

  /// <summary>
  ///   Internal service name for the configuration service.
  /// </summary>
  SERVICE_CONFIG    = 'ms.config';

  /// <summary>
  ///   Internal service name for the analytics service.
  /// </summary>
  SERVICE_ANALYTICS = 'ms.analytics';

  /// <summary>
  ///   Internal service name for the central logging service.
  /// </summary>
  SERVICE_LOGS      = 'ms.logs';

  /// <summary>
  ///   Internal service name for the event-bus service.
  /// </summary>
  SERVICE_EVENTS    = 'ms.events';

  /// <summary>
  ///   Default HMAC-SHA256 secret for JWT signing. IMPORTANT: override this via the JwtSecret field in the service's
  ///   .config.json file for any real deployment.
  /// </summary>
  JWT_SECRET_DEFAULT    = 'blog-microservices-change-me-in-production';

  /// <summary>
  ///   Issuer claim written into every JWT token.
  /// </summary>
  JWT_ISSUER            = 'ms.auth';

  /// <summary>
  ///   JWT token lifetime in minutes (24 hours).
  /// </summary>
  JWT_EXPIRATION_MINUTES = 1440;

  /// <summary>
  ///   Post status code indicating a draft that is not yet visible.
  /// </summary>
  POST_STATUS_DRAFT     = 0;

  /// <summary>
  ///   Post status code indicating a published, publicly visible post.
  /// </summary>
  POST_STATUS_PUBLISHED = 1;

  /// <summary>
  ///   Post status code indicating an archived post.
  /// </summary>
  POST_STATUS_ARCHIVED  = 2;

  /// <summary>
  ///   Comment moderation status: awaiting moderator review.
  /// </summary>
  COMMENT_STATUS_PENDING  = 0;

  /// <summary>
  ///   Comment moderation status: approved and visible.
  /// </summary>
  COMMENT_STATUS_APPROVED = 1;

  /// <summary>
  ///   Comment moderation status: rejected by a moderator.
  /// </summary>
  COMMENT_STATUS_REJECTED = 2;

  /// <summary>
  ///   Maximum file size after Base64 decoding (3 MB). Prevents denial-of-service via oversized uploads.
  /// </summary>
  MAX_UPLOAD_SIZE = 3 * 1024 * 1024;

type

  /// <summary>
  ///   Configuration record for a microservice, loaded from a JSON file using mORMot2's <c>RecordLoadJson</c>. This
  ///   function uses RTTI to map JSON keys to record fields automatically -- no manual parsing needed.
  ///
  ///   Example config file (ms.gateway.config.json):
  ///   <c>{"Port":"8080","LogLevel":"debug","JwtSecret":"my-secret"}</c>
  /// </summary>
  TMicroServiceConfig = packed record
  public
    /// <summary>
    ///   HTTP port to listen on.
    /// </summary>
    Port: RawUtf8;

    /// <summary>
    ///   SQLite database filename (default: 'data.db').
    /// </summary>
    Database: RawUtf8;

    /// <summary>
    ///   Log verbosity: 'trace', 'debug', 'info', or 'error'.
    /// </summary>
    LogLevel: RawUtf8;

    /// <summary>
    ///   Directory for log files. Relative paths are resolved against the executable directory. Default: 'logs'.
    /// </summary>
    LogPath: RawUtf8;

    /// <summary>
    ///   Number of rotated log files to keep. Default: 5.
    /// </summary>
    LogRotateCount: integer;

    /// <summary>
    ///   Maximum log file size in kilobytes before rotation. Default: 5120 (5 MB).
    /// </summary>
    LogRotateSizeKB: integer;

    /// <summary>
    ///   URL of the auth service (reserved for gateway use).
    /// </summary>
    AuthUrl: RawUtf8;

    /// <summary>
    ///   URL of the users service (reserved for gateway use).
    /// </summary>
    UsersUrl: RawUtf8;

    /// <summary>
    ///   URL of the posts service (reserved for gateway use).
    /// </summary>
    PostsUrl: RawUtf8;

    /// <summary>
    ///   URL of the tags service (reserved for gateway use).
    /// </summary>
    TagsUrl: RawUtf8;

    /// <summary>
    ///   URL of the comments service (reserved for gateway use).
    /// </summary>
    CommentsUrl: RawUtf8;

    /// <summary>
    ///   URL of the media service (reserved for gateway use).
    /// </summary>
    MediaUrl: RawUtf8;

    /// <summary>
    ///   URL of the event-bus service. Consumed by producers (ms.posts, ...) to publish events
    ///   and by consumers (ms.analytics, ...) to subscribe. Empty disables the event bus for
    ///   this service (useful in tests and during bring-up).
    /// </summary>
    EventsUrl: RawUtf8;

    /// <summary>
    ///   HMAC-SHA256 secret for JWT signing. Override the default in production!
    /// </summary>
    JwtSecret: RawUtf8;

    /// <summary>
    ///   Hostname the service binds to (default: 'localhost').
    /// </summary>
    Host: RawUtf8;

    /// <summary>
    ///   Number of HTTP server threads (default: 4).
    /// </summary>
    HttpThreads: integer;

    /// <summary>
    ///   HTTP security mode string, e.g. 'secNone' or 'secTLS' (default: 'secNone').
    /// </summary>
    HttpSecurity: RawUtf8;

    /// <summary>
    ///   HTTP bind address, '+' means all interfaces (default: '+').
    /// </summary>
    HttpBind: RawUtf8;

    /// <summary>
    ///   Root path for the REST model (default: 'api').
    /// </summary>
    ModelRoot: RawUtf8;

    /// <summary>
    ///   Allowed CORS origin header value (default: '*').
    /// </summary>
    CorsOrigin: RawUtf8;

    /// <summary>
    ///   Maximum upload file size in bytes (default: 3 MB).
    /// </summary>
    MaxUploadSize: Int64;

    /// <summary>
    ///   URL of the configuration service for centralized config retrieval.
    /// </summary>
    ConfigUrl: RawUtf8;
  end;

  /// <summary>
  ///   Minimal bootstrap record that only carries the URL of the central configuration service. Loaded from
  ///   <c>bootstrap.json</c> or the <c>--config=URL</c> CLI parameter.
  /// </summary>
  TBootstrapConfig = packed record
  public
    /// <summary>
    ///   URL of the configuration service to fetch the full config from.
    /// </summary>
    ConfigUrl: RawUtf8;
  end;

/// <summary>
///   Loads the service configuration from a JSON file. Uses mORMot2's <c>RecordLoadJson</c> to map JSON keys to record
///   fields via RTTI -- no manual JSON parsing needed. Missing fields receive sensible default values.
/// </summary>
/// <param name="aConfigFile">
///   Full path to the JSON configuration file.
/// </param>
/// <param name="aDefaultPort">
///   Default port if not specified in the config file.
/// </param>
/// <returns>
///   The loaded configuration with defaults applied.
/// </returns>
function LoadServiceConfig(
  const aConfigFile: TFileName;
  const aDefaultPort: RawUtf8
  ): TMicroServiceConfig;

/// <summary>
///   Loads the bootstrap configuration that tells a service where to find the central configuration service. Checks
///   the <c>--config=URL</c> CLI parameter first, then falls back to <c>bootstrap.json</c> in the executable directory.
/// </summary>
/// <param name="aServiceName">
///   Name of the service requesting the bootstrap config (currently unused, reserved for future per-service overrides).
/// </param>
/// <returns>
///   The bootstrap configuration with the config service URL, or empty if neither source is available.
/// </returns>
function LoadBootstrapConfig(
  const aServiceName: RawUtf8
  ): TBootstrapConfig;

/// <summary>
///   Creates a URL-friendly slug from arbitrary text. Handles German umlauts (ae/oe/ue/ss), lowercases everything,
///   replaces non-alphanumeric characters with hyphens, and collapses consecutive hyphens. Example:
///   'Microservices with Delphi!' becomes 'microservices-with-delphi'.
/// </summary>
/// <param name="aText">
///   The source text to convert.
/// </param>
/// <returns>
///   A lowercase, hyphen-separated slug string.
/// </returns>
function TextToSlug(
  const aText: RawUtf8
  ): RawUtf8;

/// <summary>
///   Guesses the MIME type based on a file name extension. Covers common web formats (HTML, CSS, JS, JSON, images,
///   fonts). Falls back to 'application/octet-stream'. Used by both the media service and the gateway's static file
///   server.
/// </summary>
/// <param name="aFileName">
///   The file name (or full path) to inspect.
/// </param>
/// <returns>
///   The MIME type string.
/// </returns>
function GuessMimeType(
  const aFileName: TFileName
  ): RawUtf8;

implementation

const
  // UTF-8 byte sequences for German umlauts and eszett.
  // Used by TextToSlug for proper transliteration.
  UTF8_SMALL_A_UMLAUT: RawUtf8 = #$C3#$A4;
  UTF8_SMALL_O_UMLAUT: RawUtf8 = #$C3#$B6;
  UTF8_SMALL_U_UMLAUT: RawUtf8 = #$C3#$BC;
  UTF8_ESZETT:          RawUtf8 = #$C3#$9F;

function LoadServiceConfig(
  const aConfigFile: TFileName;
  const aDefaultPort: RawUtf8
  ): TMicroServiceConfig;
var
  JsonContent: RawUtf8;
begin
  Finalize(Result);
  FillCharFast(Result, SizeOf(Result), 0);
  if FileExists(aConfigFile) then
  begin
    // StringFromFile reads the entire file into a RawUtf8 string
    // (mORMot2 utility, more efficient than TStringList).
    JsonContent := StringFromFile(aConfigFile);
    // RecordLoadJson maps JSON keys to record fields via RTTI.
    // Unknown JSON keys are silently ignored (forward-compatible).
    RecordLoadJson(Result, JsonContent, TypeInfo(TMicroServiceConfig));
  end;
  // Apply defaults for any fields not set by the config file
  if Result.Port = '' then
    Result.Port := aDefaultPort;
  if Result.Database = '' then
    Result.Database := 'data.db';
  if Result.LogLevel = '' then
    Result.LogLevel := 'debug';
  if Result.LogPath = '' then
    Result.LogPath := 'logs';
  if Result.LogRotateCount = 0 then
    Result.LogRotateCount := 5;
  if Result.LogRotateSizeKB = 0 then
    Result.LogRotateSizeKB := 5 * 1024;
  if Result.AuthUrl = '' then
    Result.AuthUrl := 'http://localhost:' + PORT_AUTH;
  if Result.UsersUrl = '' then
    Result.UsersUrl := 'http://localhost:' + PORT_USERS;
  if Result.PostsUrl = '' then
    Result.PostsUrl := 'http://localhost:' + PORT_POSTS;
  if Result.TagsUrl = '' then
    Result.TagsUrl := 'http://localhost:' + PORT_TAGS;
  if Result.CommentsUrl = '' then
    Result.CommentsUrl := 'http://localhost:' + PORT_COMMENTS;
  if Result.MediaUrl = '' then
    Result.MediaUrl := 'http://localhost:' + PORT_MEDIA;
  if Result.EventsUrl = '' then
    Result.EventsUrl := 'http://localhost:' + PORT_EVENTS;
  if Result.JwtSecret = '' then
    Result.JwtSecret := JWT_SECRET_DEFAULT;
  if Result.Host = '' then
    Result.Host := 'localhost';
  if Result.HttpThreads = 0 then
    Result.HttpThreads := 4;
  if Result.HttpSecurity = '' then
    Result.HttpSecurity := 'secNone';
  if Result.HttpBind = '' then
    Result.HttpBind := '+';
  if Result.ModelRoot = '' then
    Result.ModelRoot := 'api';
  if Result.CorsOrigin = '' then
    Result.CorsOrigin := '*';
  if Result.MaxUploadSize = 0 then
    Result.MaxUploadSize := MAX_UPLOAD_SIZE;
end;

function LoadBootstrapConfig(
  const aServiceName: RawUtf8
  ): TBootstrapConfig;
var
  ParamIdx: integer;
  Param: string;
  BootstrapFile: TFileName;
  JsonContent: RawUtf8;
begin
  Finalize(Result);
  FillCharFast(Result, SizeOf(Result), 0);
  // Check CLI parameter --config=URL first
  for ParamIdx := 1 to ParamCount do
  begin
    Param := ParamStr(ParamIdx);
    if Copy(Param, 1, 9) = '--config=' then
    begin
      Result.ConfigUrl := StringToUtf8(Copy(Param, 10, MaxInt));
      Exit;
    end;
  end;
  // Fall back to bootstrap.json in the executable directory
  BootstrapFile := Executable.ProgramFilePath + 'bootstrap.json';
  if FileExists(BootstrapFile) then
  begin
    JsonContent := StringFromFile(BootstrapFile);
    RecordLoadJson(Result, JsonContent, TypeInfo(TBootstrapConfig));
  end;
end;

function TextToSlug(
  const aText: RawUtf8
  ): RawUtf8;
var
  CharIdx: PtrInt;
  CurrentChar: AnsiChar;
begin
  // LowerCaseU and TrimU are mORMot2's UTF-8 string utilities,
  // operating directly on RawUtf8 without UnicodeString conversion.
  Result := LowerCaseU(TrimU(aText));
  // Transliterate German umlauts before stripping non-ASCII
  Result := StringReplaceAll(Result, UTF8_SMALL_A_UMLAUT, 'ae');
  Result := StringReplaceAll(Result, UTF8_SMALL_O_UMLAUT, 'oe');
  Result := StringReplaceAll(Result, UTF8_SMALL_U_UMLAUT, 'ue');
  Result := StringReplaceAll(Result, UTF8_ESZETT, 'ss');
  // Replace everything that's not a-z, 0-9, or hyphen
  for CharIdx := 1 to Length(Result) do
  begin
    CurrentChar := Result[CharIdx];
    if not (CurrentChar in ['a'..'z', '0'..'9', '-']) then
      Result[CharIdx] := '-';
  end;
  // Collapse consecutive hyphens (e.g., "hello---world" -> "hello-world")
  while PosEx('--', Result) > 0 do
    Result := StringReplaceAll(Result, '--', '-');
  // Strip leading and trailing hyphens
  while (Result <> '') and (Result[1] = '-') do
    Delete(Result, 1, 1);
  while (Result <> '') and (Result[Length(Result)] = '-') do
    Delete(Result, Length(Result), 1);
end;

function GuessMimeType(
  const aFileName: TFileName
  ): RawUtf8;
var
  Ext: string;
begin
  Ext := System.SysUtils.LowerCase(ExtractFileExt(aFileName));
  if Ext = '.html' then
    Result := 'text/html; charset=utf-8'
  else if Ext = '.css' then
    Result := 'text/css; charset=utf-8'
  else if Ext = '.js' then
    Result := 'application/javascript; charset=utf-8'
  else if Ext = '.json' then
    Result := JSON_CONTENT_TYPE
  else if (Ext = '.jpg') or (Ext = '.jpeg') then
    Result := 'image/jpeg'
  else if Ext = '.png' then
    Result := 'image/png'
  else if Ext = '.gif' then
    Result := 'image/gif'
  else if Ext = '.webp' then
    Result := 'image/webp'
  else if Ext = '.svg' then
    Result := 'image/svg+xml'
  else if Ext = '.ico' then
    Result := 'image/x-icon'
  else if Ext = '.woff2' then
    Result := 'font/woff2'
  else if Ext = '.woff' then
    Result := 'font/woff'
  else
    Result := 'application/octet-stream';
end;

end.
