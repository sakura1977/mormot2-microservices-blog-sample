/// <summary>
///   Shared constants, types, and helper functions
///   for all blog microservices.
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
  // Service ports
  PORT_GATEWAY  = '8080';
  PORT_AUTH     = '8081';
  PORT_USERS   = '8082';
  PORT_POSTS   = '8083';
  PORT_TAGS    = '8084';
  PORT_COMMENTS = '8085';
  PORT_MEDIA   = '8086';

  // Service names
  SERVICE_GATEWAY  = 'ms.gateway';
  SERVICE_AUTH     = 'ms.auth';
  SERVICE_USERS    = 'ms.users';
  SERVICE_POSTS    = 'ms.posts';
  SERVICE_TAGS     = 'ms.tags';
  SERVICE_COMMENTS = 'ms.comments';
  SERVICE_MEDIA    = 'ms.media';

  // JWT
  JWT_SECRET_DEFAULT    = 'blog-microservices-change-me-in-production';
  JWT_ISSUER            = 'ms.auth';
  JWT_EXPIRATION_MINUTES = 1440; // 24 hours

  // Post status
  POST_STATUS_DRAFT     = 0;
  POST_STATUS_PUBLISHED = 1;
  POST_STATUS_ARCHIVED  = 2;

  // Comment status
  COMMENT_STATUS_PENDING  = 0;
  COMMENT_STATUS_APPROVED = 1;
  COMMENT_STATUS_REJECTED = 2;

type

  /// <summary>
  ///   Configuration of a microservice, loaded from a JSON file.
  /// </summary>
  TMicroServiceConfig = packed record
    Port: RawUtf8;
    Database: RawUtf8;
    LogLevel: RawUtf8;
    AuthUrl: RawUtf8;
    UsersUrl: RawUtf8;
    PostsUrl: RawUtf8;
    TagsUrl: RawUtf8;
    CommentsUrl: RawUtf8;
    MediaUrl: RawUtf8;
    JwtSecret: RawUtf8;
  end;

/// <summary>
///   Loads the service configuration from a JSON file.
///   Returns a default configuration if the file does not exist.
/// </summary>
/// <param name="aConfigFile">
///   Path to the JSON configuration file.
/// </param>
/// <param name="aDefaultPort">
///   Default port to use if not specified in the config file.
/// </param>
/// <returns>
///   The loaded or default service configuration.
/// </returns>
function LoadServiceConfig(
  const aConfigFile: TFileName;
  const aDefaultPort: RawUtf8
): TMicroServiceConfig;

/// <summary>
///   Creates a URL-friendly slug from arbitrary text.
///   Example: 'My first post!' becomes 'my-first-post'.
/// </summary>
/// <param name="aText">
///   The source text to convert into a slug.
/// </param>
/// <returns>
///   A lowercase, hyphen-separated slug string.
/// </returns>
function TextToSlug(const aText: RawUtf8): RawUtf8;

/// Guesses the MIME type based on a file name extension.
function GuessMimeType(const aFileName: TFileName): RawUtf8;

implementation

const
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
    JsonContent := StringFromFile(aConfigFile);
    RecordLoadJson(Result, JsonContent, TypeInfo(TMicroServiceConfig));
  end;
  // Set defaults for values not loaded from the file
  if Result.Port = '' then
    Result.Port := aDefaultPort;
  if Result.Database = '' then
    Result.Database := 'data.db';
  if Result.LogLevel = '' then
    Result.LogLevel := 'debug';
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
  if Result.JwtSecret = '' then
    Result.JwtSecret := JWT_SECRET_DEFAULT;
end;

function TextToSlug(const aText: RawUtf8): RawUtf8;
var
  CharIdx: PtrInt;
  CurrentChar: AnsiChar;
begin
  Result := LowerCaseU(TrimU(aText));
  // Replace umlauts
  Result := StringReplaceAll(Result, UTF8_SMALL_A_UMLAUT, 'ae');
  Result := StringReplaceAll(Result, UTF8_SMALL_O_UMLAUT, 'oe');
  Result := StringReplaceAll(Result, UTF8_SMALL_U_UMLAUT, 'ue');
  Result := StringReplaceAll(Result, UTF8_ESZETT, 'ss');
  // Keep only a-z, 0-9, and hyphens
  for CharIdx := 1 to Length(Result) do
  begin
    CurrentChar := Result[CharIdx];
    if not (CurrentChar in ['a'..'z', '0'..'9', '-']) then
      Result[CharIdx] := '-';
  end;
  // Collapse multiple consecutive hyphens
  while PosEx('--', Result) > 0 do
    Result := StringReplaceAll(Result, '--', '-');
  // Remove leading hyphens
  while (Result <> '') and (Result[1] = '-') do
    Delete(Result, 1, 1);
  // Remove trailing hyphens
  while (Result <> '') and (Result[Length(Result)] = '-') do
    Delete(Result, Length(Result), 1);
end;

function GuessMimeType(const aFileName: TFileName): RawUtf8;
var
  Ext: string;
begin
  Ext := System.SysUtils.LowerCase(ExtractFileExt(aFileName));
  if Ext = '.html' then Result := 'text/html; charset=utf-8'
  else if Ext = '.css' then Result := 'text/css; charset=utf-8'
  else if Ext = '.js' then Result := 'application/javascript; charset=utf-8'
  else if Ext = '.json' then Result := JSON_CONTENT_TYPE
  else if (Ext = '.jpg') or (Ext = '.jpeg') then Result := 'image/jpeg'
  else if Ext = '.png' then Result := 'image/png'
  else if Ext = '.gif' then Result := 'image/gif'
  else if Ext = '.webp' then Result := 'image/webp'
  else if Ext = '.svg' then Result := 'image/svg+xml'
  else if Ext = '.ico' then Result := 'image/x-icon'
  else if Ext = '.woff2' then Result := 'font/woff2'
  else if Ext = '.woff' then Result := 'font/woff'
  else Result := 'application/octet-stream';
end;

end.
