/// <summary>
///   HTTP client wrapper for service-to-service calls.
///   Provides simple Get/Post/Put/Delete methods with JSON.
/// </summary>
unit ms.shared.client;

{$SCOPEDENUMS ON}
{$I mormot.defines.inc}
{$WARN SYMBOL_PLATFORM OFF}
{$WARN UNIT_PLATFORM OFF}

interface

uses
  System.SysUtils,
  mormot.core.base,
  mormot.core.json,
  mormot.core.log,
  mormot.core.text,
  mormot.core.unicode,
  mormot.net.client,
  mormot.net.sock;

type

  /// <summary>
  ///   HTTP client for calling a specific microservice.
  /// </summary>
  TMicroClient = class
  private
    FBaseUrl: RawUtf8;
    FServiceName: RawUtf8;
    FHost: RawUtf8;
    FPort: RawUtf8;

    /// <summary>
    ///   Sends an HTTP request and returns the response body.
    /// </summary>
    /// <param name="aPath">
    ///   The request path (e.g. '/api/users').
    /// </param>
    /// <param name="aMethod">
    ///   The HTTP method (GET, POST, PUT, DELETE).
    /// </param>
    /// <param name="aBody">
    ///   The request body content.
    /// </param>
    /// <param name="aContentType">
    ///   The content type of the request body.
    /// </param>
    /// <param name="aStatus">
    ///   Receives the HTTP status code.
    /// </param>
    /// <returns>
    ///   The response body as a string.
    /// </returns>
    function DoRequest(
      const aPath, aMethod: RawUtf8;
      const aBody: RawByteString;
      const aContentType: RawUtf8;
      out aStatus: integer
    ): RawUtf8;

    /// <summary>
    ///   Parses the base URL into host and port components.
    /// </summary>
    procedure ParseBaseUrl;
  public

    /// <summary>
    ///   Creates a client for the specified service.
    /// </summary>
    /// <param name="aBaseUrl">
    ///   The service base URL, e.g. 'http://localhost:8082'.
    /// </param>
    /// <param name="aServiceName">
    ///   The service name, e.g. 'ms.users' (used for logging).
    /// </param>
    constructor Create(
      const aBaseUrl, aServiceName: RawUtf8
    );

    /// <summary>
    ///   Sends an HTTP DELETE request and returns the response body.
    /// </summary>
    /// <param name="aPath">
    ///   The request path.
    /// </param>
    /// <param name="aStatus">
    ///   Receives the HTTP status code.
    /// </param>
    /// <returns>
    ///   The response body.
    /// </returns>
    function Delete(
      const aPath: RawUtf8;
      out aStatus: integer
    ): RawUtf8;

    /// <summary>
    ///   Sends an HTTP GET request and returns the response body.
    /// </summary>
    /// <param name="aPath">
    ///   The request path.
    /// </param>
    /// <param name="aStatus">
    ///   Receives the HTTP status code.
    /// </param>
    /// <returns>
    ///   The response body.
    /// </returns>
    function Get(
      const aPath: RawUtf8;
      out aStatus: integer
    ): RawUtf8;

    /// <summary>
    ///   Sends an HTTP POST request with a JSON body and returns the response body.
    /// </summary>
    /// <param name="aPath">
    ///   The request path.
    /// </param>
    /// <param name="aJsonBody">
    ///   The JSON request body.
    /// </param>
    /// <param name="aStatus">
    ///   Receives the HTTP status code.
    /// </param>
    /// <returns>
    ///   The response body.
    /// </returns>
    function Post(
      const aPath, aJsonBody: RawUtf8;
      out aStatus: integer
    ): RawUtf8;

    /// <summary>
    ///   Sends an HTTP PUT request with a JSON body and returns the response body.
    /// </summary>
    /// <param name="aPath">
    ///   The request path.
    /// </param>
    /// <param name="aJsonBody">
    ///   The JSON request body.
    /// </param>
    /// <param name="aStatus">
    ///   Receives the HTTP status code.
    /// </param>
    /// <returns>
    ///   The response body.
    /// </returns>
    function Put(
      const aPath, aJsonBody: RawUtf8;
      out aStatus: integer
    ): RawUtf8;

    /// <summary>
    ///   The base URL of the target service.
    /// </summary>
    property BaseUrl: RawUtf8 read FBaseUrl;

    /// <summary>
    ///   The name of the target service.
    /// </summary>
    property ServiceName: RawUtf8 read FServiceName;
  end;

implementation

constructor TMicroClient.Create(
  const aBaseUrl, aServiceName: RawUtf8
);
begin
  inherited Create;
  FBaseUrl := aBaseUrl;
  FServiceName := aServiceName;
  ParseBaseUrl;
end;

function TMicroClient.Delete(
  const aPath: RawUtf8;
  out aStatus: integer
): RawUtf8;
begin
  Result := DoRequest(aPath, 'DELETE', '', '', aStatus);
end;

function TMicroClient.DoRequest(
  const aPath, aMethod: RawUtf8;
  const aBody: RawByteString;
  const aContentType: RawUtf8;
  out aStatus: integer
): RawUtf8;
var
  Client: THttpClientSocket;
begin
  Result := '';
  aStatus := 0;
  Client := THttpClientSocket.Create(5000);
  try
    try
      Client.OpenBind(FHost, FPort, False);
      aStatus := Client.Request(aPath, aMethod, 0, '',
        aBody, aContentType);
      Result := Client.Http.Content;
    except
      on E: Exception do
        aStatus := 503; // Service Unavailable
    end;
  finally
    Client.Free;
  end;
end;

function TMicroClient.Get(
  const aPath: RawUtf8;
  out aStatus: integer
): RawUtf8;
begin
  Result := DoRequest(aPath, 'GET', '', '', aStatus);
end;

procedure TMicroClient.ParseBaseUrl;
var
  Uri: TUri;
begin
  if Uri.From(FBaseUrl) then
  begin
    FHost := Uri.Server;
    FPort := Uri.Port;
  end
  else
  begin
    FHost := 'localhost';
    FPort := '80';
  end;
end;

function TMicroClient.Post(
  const aPath, aJsonBody: RawUtf8;
  out aStatus: integer
): RawUtf8;
begin
  Result := DoRequest(aPath, 'POST', aJsonBody,
    'application/json', aStatus);
end;

function TMicroClient.Put(
  const aPath, aJsonBody: RawUtf8;
  out aStatus: integer
): RawUtf8;
begin
  Result := DoRequest(aPath, 'PUT', aJsonBody,
    'application/json', aStatus);
end;

end.
