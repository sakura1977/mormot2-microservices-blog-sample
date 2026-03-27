/// <summary>
///   Shared base class for all blog microservices.
///   Provides health-check endpoint, logging, configuration,
///   and graceful shutdown.
/// </summary>
unit ms.shared.service;

{$SCOPEDENUMS ON}
{$I mormot.defines.inc}
{$WARN SYMBOL_PLATFORM OFF}
{$WARN UNIT_PLATFORM OFF}

interface

uses
  SysUtils,
  mormot.core.base,
  mormot.core.datetime,
  mormot.core.json,
  mormot.core.log,
  mormot.core.os,
  mormot.core.rtti,
  mormot.core.text,
  mormot.core.unicode,
  mormot.net.async,
  mormot.net.http,
  mormot.net.server,
  ms.shared;

type

  /// <summary>
  ///   Status of a microservice.
  /// </summary>
  TServiceHealthStatus = (
    Starting,
    Running,
    Stopping,
    Stopped,
    Error
  );

  /// <summary>
  ///   Health-check response (returned as JSON).
  /// </summary>
  THealthResponse = packed record
    Service: RawUtf8;
    Status: RawUtf8;
    Port: RawUtf8;
    Uptime: RawUtf8;
    Version: RawUtf8;
    Timestamp: TDateTime;
  end;

  /// <summary>
  ///   Base class for a microservice.
  ///   Provides HTTP server, logging, health-check, and shutdown.
  /// </summary>
  TMicroService = class
  private
    FConfig: TMicroServiceConfig;
    FHttpServer: THttpAsyncServer;
    FLogFamily: TSynLogFamily;
    FPort: RawUtf8;
    FServiceName: RawUtf8;
    FShutdownRequested: boolean;
    FStartTime: TDateTime;
    FStatus: TServiceHealthStatus;

    /// <summary>
    ///   Returns the health-check information as a JSON string.
    /// </summary>
    /// <returns>
    ///   JSON representation of the current health status.
    /// </returns>
    function GetHealthJson: RawUtf8;

    /// <summary>
    ///   Initializes the logging subsystem based on configuration.
    /// </summary>
    procedure InitLogging;

    /// <summary>
    ///   Converts a service health status enum to its text representation.
    /// </summary>
    /// <param name="aStatus">
    ///   The health status to convert.
    /// </param>
    /// <returns>
    ///   A human-readable status string.
    /// </returns>
    function StatusToText(aStatus: TServiceHealthStatus): RawUtf8;
  protected

    /// <summary>
    ///   Called after the HTTP server has started.
    ///   Override in derived classes for custom initialization.
    /// </summary>
    procedure DoFinalize; virtual;

    /// <summary>
    ///   Called before the service shuts down.
    ///   Override in derived classes for custom cleanup.
    /// </summary>
    procedure DoInitialize; virtual;

    /// <summary>
    ///   Called when an HTTP request arrives.
    ///   The base implementation handles /api/health and /api/shutdown.
    ///   Derived classes override this for custom endpoints.
    /// </summary>
    /// <param name="Ctxt">
    ///   The HTTP request context.
    /// </param>
    /// <returns>
    ///   The HTTP status code for the response.
    /// </returns>
    function OnRequest(Ctxt: THttpServerRequestAbstract): cardinal; virtual;
  public

    /// <summary>
    ///   Creates a new microservice instance.
    /// </summary>
    /// <param name="aServiceName">
    ///   The name of the service (e.g. 'ms.users').
    /// </param>
    /// <param name="aDefaultPort">
    ///   The default port to listen on.
    /// </param>
    constructor Create(
      const aServiceName, aDefaultPort: RawUtf8
    );

    /// <summary>
    ///   Destroys the microservice and releases the HTTP server.
    /// </summary>
    destructor Destroy; override;

    /// <summary>
    ///   Writes a log message at the specified level.
    /// </summary>
    /// <param name="aLevel">
    ///   The log level.
    /// </param>
    /// <param name="aFormat">
    ///   The format string.
    /// </param>
    /// <param name="aArgs">
    ///   The format arguments.
    /// </param>
    procedure Log(
      aLevel: TSynLogLevel;
      const aFormat: RawUtf8;
      const aArgs: array of const
    ); overload;

    /// <summary>
    ///   Writes a log message at info level.
    /// </summary>
    /// <param name="aFormat">
    ///   The format string.
    /// </param>
    /// <param name="aArgs">
    ///   The format arguments.
    /// </param>
    procedure Log(
      const aFormat: RawUtf8;
      const aArgs: array of const
    ); overload;

    /// <summary>
    ///   Requests a graceful shutdown of the service.
    /// </summary>
    procedure RequestShutdown;

    /// <summary>
    ///   Starts the HTTP server and waits until shutdown is requested.
    /// </summary>
    procedure Run;

    /// <summary>
    ///   The loaded service configuration.
    /// </summary>
    property Config: TMicroServiceConfig read FConfig;

    /// <summary>
    ///   The port the service is listening on.
    /// </summary>
    property Port: RawUtf8 read FPort;

    /// <summary>
    ///   The name of this service.
    /// </summary>
    property ServiceName: RawUtf8 read FServiceName;

    /// <summary>
    ///   Whether a shutdown has been requested.
    /// </summary>
    property ShutdownRequested: boolean read FShutdownRequested;

    /// <summary>
    ///   The current health status of the service.
    /// </summary>
    property Status: TServiceHealthStatus read FStatus;
  end;

const
  SERVICE_VERSION = '0.1.0';

  HEALTH_STATUS_TEXT: array[TServiceHealthStatus] of RawUtf8 = (
    'starting', 'running', 'stopping', 'stopped', 'error'
  );

implementation

constructor TMicroService.Create(
  const aServiceName, aDefaultPort: RawUtf8
);
begin
  inherited Create;
  FServiceName := aServiceName;
  FStatus := TServiceHealthStatus.Starting;
  FShutdownRequested := False;
  FConfig := LoadServiceConfig(
    Executable.ProgramFilePath + Utf8ToString(aServiceName) + '.config.json',
    aDefaultPort);
  FPort := FConfig.Port;
  InitLogging;
end;

destructor TMicroService.Destroy;
begin
  FreeAndNil(FHttpServer);
  inherited Destroy;
end;

procedure TMicroService.DoFinalize;
begin
  // Can be overridden in derived classes
end;

procedure TMicroService.DoInitialize;
begin
  // Can be overridden in derived classes
end;

function TMicroService.GetHealthJson: RawUtf8;
var
  Health: THealthResponse;
begin
  Health.Service := FServiceName;
  Health.Status := StatusToText(FStatus);
  Health.Port := FPort;
  Health.Uptime := FormatUtf8('% seconds',
    [Round((NowUtc - FStartTime) * SecsPerDay)]);
  Health.Version := SERVICE_VERSION;
  Health.Timestamp := NowUtc;
  Result := RecordSaveJson(Health, TypeInfo(THealthResponse));
end;

procedure TMicroService.InitLogging;
var
  LogPath: TFileName;
begin
  LogPath := Executable.ProgramFilePath + 'logs';
  if not DirectoryExists(LogPath) then
    CreateDir(LogPath);

  FLogFamily := TSynLog.Family;
  FLogFamily.DestinationPath := LogPath + PathDelim;
  FLogFamily.CustomFileName := Utf8ToString(FServiceName);
  FLogFamily.RotateFileCount := 5;
  FLogFamily.RotateFileSizeKB := 5 * 1024; // 5 MB per file
  FLogFamily.PerThreadLog := ptIdentifiedInOneFile;

  // Set log level from configuration
  if FConfig.LogLevel = 'trace' then
  begin
    FLogFamily.Level := LOG_VERBOSE;
  end
  else if FConfig.LogLevel = 'debug' then
  begin
    FLogFamily.Level := LOG_VERBOSE - [sllTrace];
  end
  else if FConfig.LogLevel = 'info' then
  begin
    FLogFamily.Level := [sllInfo, sllWarning, sllError,
      sllLastError, sllException, sllExceptionOS];
  end
  else if FConfig.LogLevel = 'warn' then
  begin
    FLogFamily.Level := [sllWarning, sllError,
      sllLastError, sllException, sllExceptionOS];
  end
  else if FConfig.LogLevel = 'error' then
  begin
    FLogFamily.Level := [sllError, sllLastError,
      sllException, sllExceptionOS];
  end
  else
  begin
    FLogFamily.Level := LOG_VERBOSE - [sllTrace];
  end;

  // Also output to console
  FLogFamily.EchoToConsole := FLogFamily.Level;
end;

procedure TMicroService.Log(
  const aFormat: RawUtf8;
  const aArgs: array of const
);
begin
  TSynLog.Add.Log(sllInfo, FormatUtf8(aFormat, aArgs), self);
end;

procedure TMicroService.Log(
  aLevel: TSynLogLevel;
  const aFormat: RawUtf8;
  const aArgs: array of const
);
begin
  TSynLog.Add.Log(aLevel, FormatUtf8(aFormat, aArgs), self);
end;

function TMicroService.OnRequest(
  Ctxt: THttpServerRequestAbstract
): cardinal;
var
  Path: RawUtf8;
begin
  Path := Ctxt.Url;
  // Health check
  if (Ctxt.Method = 'GET') and (Path = '/api/health') then
  begin
    Ctxt.OutContent := GetHealthJson;
    Ctxt.OutContentType := JSON_CONTENT_TYPE;
    Result := HTTP_SUCCESS;
  end
  // Shutdown
  else if (Ctxt.Method = 'POST') and (Path = '/api/shutdown') then
  begin
    Log('Shutdown requested via API', []);
    RequestShutdown;
    Ctxt.OutContent := '{"success":true}';
    Ctxt.OutContentType := JSON_CONTENT_TYPE;
    Result := HTTP_SUCCESS;
  end
  else
  begin
    Result := HTTP_NOTFOUND;
  end;
end;

procedure TMicroService.RequestShutdown;
begin
  FShutdownRequested := True;
end;

procedure TMicroService.Run;
begin
  FStartTime := NowUtc;
  Log('% starting on port %...', [FServiceName, FPort]);
  try
    FHttpServer := THttpAsyncServer.Create(
      FPort, nil, nil, '', 4,
      30000, [hsoNoXPoweredHeader]);
    FHttpServer.OnRequest := OnRequest;
    FHttpServer.WaitStarted;

    FStatus := TServiceHealthStatus.Running;
    DoInitialize;

    Log('% running on port %.', [FServiceName, FPort]);
    WriteLn(FServiceName, ' running on port ', FPort, '.');
    WriteLn('Press Enter or POST /api/shutdown to stop.');

    // Wait for shutdown signal or Enter key
    while not FShutdownRequested do
    begin
      if ConsoleKeyPressed($0D) then
        Break;
      SleepHiRes(200);
    end;

    FStatus := TServiceHealthStatus.Stopping;
    Log('% shutting down...', [FServiceName]);
    DoFinalize;
    FreeAndNil(FHttpServer);
    FStatus := TServiceHealthStatus.Stopped;
    Log('% stopped.', [FServiceName]);
  except
    on E: Exception do
    begin
      FStatus := TServiceHealthStatus.Error;
      Log(sllError, 'ERROR in %: %', [FServiceName, E.Message]);
      WriteLn('ERROR in ', FServiceName, ': ', E.Message);
    end;
  end;
end;

function TMicroService.StatusToText(
  aStatus: TServiceHealthStatus
): RawUtf8;
begin
  Result := HEALTH_STATUS_TEXT[aStatus];
end;

initialization
  Rtti.RegisterFromText([
    TypeInfo(THealthResponse),
    'Service,Status,Port,Uptime,Version: RawUtf8; Timestamp: TDateTime'
  ]);

end.
