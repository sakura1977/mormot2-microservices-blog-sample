/// <summary>
///   Correlation ID infrastructure for distributed request tracing across microservices.
///
///   A correlation ID is a unique identifier attached to every incoming HTTP request that propagates through
///   all backend services involved in handling that request. It enables end-to-end tracing across log files
///   from independent services -- the foundational debugging tool for any distributed system.
///
///   Lifecycle per request:
///   <list>
///   <item>The HTTP entry handler extracts the <c>X-Correlation-Id</c> header (or generates one if absent).</item>
///   <item>The ID is stored in a <c>threadvar</c> for the duration of the request.</item>
///   <item>Any code on the request thread can read it via <c>GetCurrentCorrelationId</c>.</item>
///   <item>Outgoing HTTP calls forward it via the same header.</item>
///   <item>After the request, <c>ClearCurrentCorrelationId</c> resets the threadvar.</item>
///   </list>
///
///   See <c>.claude/correlation-ids.md</c> for the full design documentation and usage examples.
/// </summary>
unit ms.shared.correlation;

{$SCOPEDENUMS ON}
{$I mormot.defines.inc}
{$WARN SYMBOL_PLATFORM OFF}
{$WARN UNIT_PLATFORM OFF}

interface

uses
  System.SysUtils,
  mormot.core.base,
  mormot.core.log,
  mormot.core.rtti,
  mormot.core.text,
  mormot.core.unicode;

const
  /// <summary>
  ///   The HTTP header name used to propagate correlation IDs across services. Lowercase form is used in the
  ///   constant because mORMot2's <c>FindNameValue</c> requires an uppercase needle for case-insensitive matching.
  /// </summary>
  CORRELATION_HEADER = 'X-Correlation-Id';

  /// <summary>
  ///   The uppercase form of the correlation header name plus colon, used as a search needle for
  ///   <c>FindNameValue</c> when parsing raw HTTP header strings.
  /// </summary>
  CORRELATION_HEADER_UPPER = 'X-CORRELATION-ID: ';

/// <summary>
///   Generates a new unique correlation ID. Uses Delphi's <c>CreateGuid</c> wrapped in a stripped string form
///   (no curly braces, lowercase) suitable for HTTP headers and log files.
/// </summary>
/// <returns>
///   A 36-character UUID string, e.g. <c>a8f3c1e9-7d24-4b5f-9e1c-2a3b4c5d6e7f</c>.
/// </returns>
function GenerateCorrelationId: RawUtf8;

/// <summary>
///   Returns the correlation ID currently associated with the calling thread, or empty string if none has been
///   set. Code on a request thread should call this to obtain the ID for logging or HTTP forwarding.
/// </summary>
/// <returns>
///   The correlation ID for the current thread, or empty string.
/// </returns>
function GetCurrentCorrelationId: RawUtf8;

/// <summary>
///   Stores a correlation ID in the calling thread's <c>threadvar</c>. Called once per request, immediately after
///   extraction from the incoming HTTP headers.
/// </summary>
/// <param name="aId">
///   The correlation ID to store.
/// </param>
procedure SetCurrentCorrelationId(
  const aId: RawUtf8
  );

/// <summary>
///   Clears the correlation ID for the calling thread. Should be called after a request completes so that the
///   thread (which is reused from the HTTP server's pool) does not leak its previous request's ID into the next.
/// </summary>
procedure ClearCurrentCorrelationId;

/// <summary>
///   Extracts the correlation ID from a raw HTTP header block. If the header is absent or empty, returns an
///   empty string -- the caller should then call <c>GenerateCorrelationId</c> to create a new one.
/// </summary>
/// <param name="aHeaders">
///   Raw HTTP header block as received by the HTTP server (CRLF-separated lines).
/// </param>
/// <returns>
///   The correlation ID value from the header, or empty string if not present.
/// </returns>
function ExtractCorrelationIdFromHeaders(
  const aHeaders: RawUtf8
  ): RawUtf8;

/// <summary>
///   Convenience function that combines extraction and generation: returns the correlation ID from the headers
///   if present, otherwise generates a new one. The returned ID is also written to the threadvar.
/// </summary>
/// <param name="aHeaders">
///   Raw HTTP header block as received by the HTTP server.
/// </param>
/// <returns>
///   The effective correlation ID for the current request.
/// </returns>
function EnsureCorrelationIdFromHeaders(
  const aHeaders: RawUtf8
  ): RawUtf8;

/// <summary>
///   Logs a message with the current correlation ID prepended in square brackets. Use this instead of
///   <c>TSynLog.Add.Log</c> when you want the correlation ID to appear in the log entry automatically.
/// </summary>
/// <param name="aLevel">
///   The log severity level.
/// </param>
/// <param name="aFormat">
///   Format string with <c>%</c> placeholders, mORMot2-style.
/// </param>
/// <param name="aArgs">
///   Format arguments to substitute into <c>aFormat</c>.
/// </param>
/// <param name="aInstance">
///   The instance generating the log entry (or <c>nil</c>), passed to TSynLog for context.
/// </param>
procedure LogWithCorrelation(
  aLevel: TSynLogLevel;
  const aFormat: RawUtf8;
  const aArgs: array of const;
  aInstance: TObject
  );

implementation

threadvar
  FCurrentCorrelationId: RawUtf8;

function GenerateCorrelationId: RawUtf8;
var
  NewId: TGuid;
  AsText: RawUtf8;
begin
  // CreateGuid is Delphi RTL; mORMot2's GuidToRawUtf8 produces '{...}' with braces.
  // We strip the braces and lowercase the hex for a clean UUID string suitable for HTTP headers.
  CreateGuid(NewId);
  AsText := GuidToRawUtf8(NewId);
  // Strip leading '{' and trailing '}'
  if (Length(AsText) >= 2) and (AsText[1] = '{') then
    Result := LowerCase(Copy(AsText, 2, Length(AsText) - 2))
  else
    Result := LowerCase(AsText);
end;

function GetCurrentCorrelationId: RawUtf8;
begin
  Result := FCurrentCorrelationId;
end;

procedure SetCurrentCorrelationId(
  const aId: RawUtf8
  );
begin
  FCurrentCorrelationId := aId;
end;

procedure ClearCurrentCorrelationId;
begin
  FCurrentCorrelationId := '';
end;

function ExtractCorrelationIdFromHeaders(
  const aHeaders: RawUtf8
  ): RawUtf8;
begin
  // FindNameValue is mORMot2's optimized HTTP-header search: case-insensitive,
  // requires the needle in uppercase form including the trailing colon+space.
  FindNameValue(aHeaders, PAnsiChar(CORRELATION_HEADER_UPPER), Result);
end;

function EnsureCorrelationIdFromHeaders(
  const aHeaders: RawUtf8
  ): RawUtf8;
begin
  Result := ExtractCorrelationIdFromHeaders(aHeaders);
  if Result = '' then
    Result := GenerateCorrelationId;
  FCurrentCorrelationId := Result;
end;

procedure LogWithCorrelation(
  aLevel: TSynLogLevel;
  const aFormat: RawUtf8;
  const aArgs: array of const;
  aInstance: TObject
  );
var
  Prefixed: RawUtf8;
begin
  if FCurrentCorrelationId <> '' then
    Prefixed := FormatUtf8('[%] %', [FCurrentCorrelationId, aFormat])
  else
    Prefixed := aFormat;
  TSynLog.Add.Log(aLevel, FormatUtf8(Prefixed, aArgs), aInstance);
end;

end.
