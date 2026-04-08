/// <summary>
///   Service orchestrator for the blog microservices. Starts, monitors, and stops all backend services. Provides a
///   REST API and a console interface.
/// </summary>
unit ms.controller.orchestrator;

{$SCOPEDENUMS ON}
{$I mormot.defines.inc}
{$WARN SYMBOL_PLATFORM OFF}
{$WARN UNIT_PLATFORM OFF}

interface

uses
  System.Classes,
  System.SysUtils,
  Winapi.Windows,
  mormot.core.base,
  mormot.core.datetime,
  mormot.core.json,
  mormot.core.log,
  mormot.core.os,
  mormot.core.rtti,
  mormot.core.text,
  mormot.core.threads,
  mormot.net.async,
  mormot.net.client,
  mormot.net.http,
  mormot.net.server,
  mormot.net.sock,
  ms.shared;

type

  /// <summary>
  ///   Status of a managed service process.
  /// </summary>
  TServiceProcessStatus = (
    /// <summary>
    ///   The service has not been started yet.
    /// </summary>
    NotStarted,

    /// <summary>
    ///   The service process is currently being launched.
    /// </summary>
    Starting,

    /// <summary>
    ///   The service is running and operational.
    /// </summary>
    Running,

    /// <summary>
    ///   The service is in the process of being stopped.
    /// </summary>
    Stopping,

    /// <summary>
    ///   The service has been stopped.
    /// </summary>
    Stopped,

    /// <summary>
    ///   The service encountered an error or crashed.
    /// </summary>
    Error
  );

  /// <summary>
  ///   Record holding runtime information about a managed service.
  /// </summary>
  TServiceEntry = record
  public
    /// <summary>
    ///   The unique name identifying this service.
    /// </summary>
    Name: RawUtf8;

    /// <summary>
    ///   The HTTP port this service listens on.
    /// </summary>
    Port: RawUtf8;

    /// <summary>
    ///   The full path to the service executable.
    /// </summary>
    ExePath: TFileName;

    /// <summary>
    ///   The Windows process handle of the running service.
    /// </summary>
    ProcessHandle: THandle;

    /// <summary>
    ///   The Windows process ID of the running service.
    /// </summary>
    ProcessId: Cardinal;

    /// <summary>
    ///   The current process status of this service.
    /// </summary>
    Status: TServiceProcessStatus;

    /// <summary>
    ///   The UTC timestamp of the last health check performed.
    /// </summary>
    LastHealthCheck: TDateTime;

    /// <summary>
    ///   Whether the last health check was successful.
    /// </summary>
    HealthOk: boolean;

    /// <summary>
    ///   The number of automatic restarts performed so far.
    /// </summary>
    RestartCount: integer;

    /// <summary>
    ///   The maximum number of automatic restarts allowed before giving up.
    /// </summary>
    MaxRestarts: integer;
  end;

  /// <summary>
  ///   DTO for the status API response of a single service.
  /// </summary>
  TServiceStatusDto = packed record
  public
    /// <summary>
    ///   The service name.
    /// </summary>
    Name: RawUtf8;

    /// <summary>
    ///   The port the service listens on.
    /// </summary>
    Port: RawUtf8;

    /// <summary>
    ///   The current status as a human-readable text string.
    /// </summary>
    Status: RawUtf8;

    /// <summary>
    ///   Whether the service passed the last health check.
    /// </summary>
    HealthOk: boolean;

    /// <summary>
    ///   The number of automatic restarts performed.
    /// </summary>
    RestartCount: integer;

    /// <summary>
    ///   The Windows process ID.
    /// </summary>
    Pid: Cardinal;
  end;

  /// <summary>
  ///   DTO for the overall controller status API response.
  /// </summary>
  TControllerStatusDto = packed record
  public
    /// <summary>
    ///   The name of the controller service.
    /// </summary>
    Controller: RawUtf8;

    /// <summary>
    ///   The port the controller API listens on.
    /// </summary>
    Port: RawUtf8;

    /// <summary>
    ///   The status information for each managed service.
    /// </summary>
    Services: array of TServiceStatusDto;

    /// <summary>
    ///   The UTC timestamp when the status was generated.
    /// </summary>
    Timestamp: TDateTime;
  end;

  /// <summary>
  ///   Orchestrator that manages all blog microservices, including starting, stopping, health monitoring, and
  ///   automatic restart on crash.
  /// </summary>
  TServiceOrchestrator = class
  strict private
    /// <summary>
    ///   The HTTP port for the controller API.
    /// </summary>
    FPort: RawUtf8;

    /// <summary>
    ///   The array of all registered service entries.
    /// </summary>
    FServices: array of TServiceEntry;

    /// <summary>
    ///   The HTTP server instance for the controller API.
    /// </summary>
    FHttpServer: THttpAsyncServer;

    /// <summary>
    ///   The background timer thread for periodic service monitoring.
    /// </summary>
    FMonitorThread: TSynBackgroundTimer;

    /// <summary>
    ///   Flag indicating whether a shutdown has been requested.
    /// </summary>
    FShutdownRequested: boolean;

    /// <summary>
    ///   The base path used to locate service executables.
    /// </summary>
    FBasePath: TFileName;

    /// <summary>
    ///   Checks the health of a service via its /api/health endpoint.
    /// </summary>
    /// <param name="aEntry">
    ///   The service entry to check.
    /// </param>
    /// <returns>
    ///   True if the service responds with HTTP 200.
    /// </returns>
    function CheckHealth(
      var aEntry: TServiceEntry
      ): boolean;

    /// <summary>
    ///   Locates the executable for a given service name.
    /// </summary>
    /// <param name="aServiceName">
    ///   The service name to look up.
    /// </param>
    /// <returns>
    ///   The full path to the executable.
    /// </returns>
    function FindExe(
      const aServiceName: RawUtf8
      ): TFileName;

    /// <summary>
    ///   Returns a JSON representation of the current status of all services.
    /// </summary>
    /// <returns>
    ///   The JSON status string.
    /// </returns>
    function GetStatusJson: RawUtf8;

    /// <summary>
    ///   Checks whether a process is still running.
    /// </summary>
    /// <param name="aHandle">
    ///   The process handle to check.
    /// </param>
    /// <returns>
    ///   True if the process is still active.
    /// </returns>
    function IsProcessRunning(
      aHandle: THandle
      ): boolean;

    /// <summary>
    ///   Background timer callback that monitors all services, detects crashes, and triggers automatic restarts.
    /// </summary>
    /// <param name="aSender">
    ///   The background timer that triggered this callback.
    /// </param>
    /// <param name="aMsg">
    ///   The timer message (unused).
    /// </param>
    procedure MonitorServices(
      aSender: TSynBackgroundTimer;
      const aMsg: RawUtf8
      );

    /// <summary>
    ///   Handles incoming HTTP requests to the controller API.
    /// </summary>
    /// <param name="aCtxt">
    ///   The HTTP server request context.
    /// </param>
    /// <returns>
    ///   The HTTP status code for the response.
    /// </returns>
    function OnRequest(
      aCtxt: THttpServerRequestAbstract
      ): cardinal;

    /// <summary>
    ///   Registers a service for management by the orchestrator.
    /// </summary>
    /// <param name="aName">
    ///   The service name identifier.
    /// </param>
    /// <param name="aPort">
    ///   The port the service listens on.
    /// </param>
    procedure RegisterService(
      const aName: RawUtf8;
      const aPort: RawUtf8
      );

    /// <summary>
    ///   Starts a service process.
    /// </summary>
    /// <param name="aEntry">
    ///   The service entry to start.
    /// </param>
    /// <returns>
    ///   True if the process was started successfully.
    /// </returns>
    function StartProcess(
      var aEntry: TServiceEntry
      ): boolean;

    /// <summary>
    ///   Converts a service process status enum to its text representation.
    /// </summary>
    /// <param name="aStatus">
    ///   The status enum value.
    /// </param>
    /// <returns>
    ///   The status as a text string.
    /// </returns>
    function StatusToText(
      aStatus: TServiceProcessStatus
      ): RawUtf8;

    /// <summary>
    ///   Stops a service process, first gracefully via /api/shutdown, then forcefully if needed.
    /// </summary>
    /// <param name="aEntry">
    ///   The service entry to stop.
    /// </param>
    /// <returns>
    ///   True if the process was stopped successfully.
    /// </returns>
    function StopProcess(
      var aEntry: TServiceEntry
      ): boolean;

    /// <summary>
    ///   Waits for a service to become healthy within the given timeout.
    /// </summary>
    /// <param name="aEntry">
    ///   The service entry to wait for.
    /// </param>
    /// <param name="aTimeoutMs">
    ///   The maximum time in milliseconds to wait for a healthy response.
    /// </param>
    procedure WaitForHealth(
      var aEntry: TServiceEntry;
      aTimeoutMs: integer
      );
  public

    /// <summary>
    ///   Creates the orchestrator listening on the given port.
    /// </summary>
    /// <param name="aPort">
    ///   The HTTP port for the controller API.
    /// </param>
    constructor Create(
      const aPort: RawUtf8
      );

    /// <summary>
    ///   Destroys the orchestrator and releases resources.
    /// </summary>
    destructor Destroy; override;

    /// <summary>
    ///   Registers all known services and runs the controller loop.
    /// </summary>
    procedure Run;

    /// <summary>
    ///   Starts all registered services.
    /// </summary>
    procedure StartAll;

    /// <summary>
    ///   Shuts down all running services.
    /// </summary>
    procedure StopAll;
  end;

implementation

const
  HEALTH_CHECK_INTERVAL_SEC = 10;
  PROCESS_START_WAIT_MS     = 2000;
  MAX_RESTARTS_DEFAULT      = 3;

  STATUS_TEXT: array[TServiceProcessStatus] of RawUtf8 = (
    'not_started', 'starting', 'running', 'stopping', 'stopped', 'error'
  );

function TServiceOrchestrator.CheckHealth(
  var aEntry: TServiceEntry
  ): boolean;
var
  Client: THttpClientSocket;
  StatusCode: integer;
begin
  Result := False;
  if aEntry.Status <> TServiceProcessStatus.Running then
    Exit;

  try
    Client := THttpClientSocket.Create(3000);
    try
      Client.OpenBind('localhost', aEntry.Port, False);
      StatusCode := Client.Request('/api/health', 'GET', 0, '');
      Result := (StatusCode = 200);
    finally
      Client.Free;
    end;
  except
    Result := False;
  end;

  aEntry.HealthOk := Result;
  aEntry.LastHealthCheck := NowUtc;
end;

constructor TServiceOrchestrator.Create(
  const aPort: RawUtf8
  );
begin
  inherited Create;
  FPort := aPort;
  FShutdownRequested := False;
  FBasePath := Executable.ProgramFilePath;
end;

destructor TServiceOrchestrator.Destroy;
begin
  FreeAndNil(FMonitorThread);
  FreeAndNil(FHttpServer);
  inherited Destroy;
end;

function TServiceOrchestrator.FindExe(
  const aServiceName: RawUtf8
  ): TFileName;
var
  Candidate: TFileName;
begin
  // Search in the same directory as the controller
  Candidate := FBasePath + Utf8ToString(aServiceName) + '.exe';
  if FileExists(Candidate) then
    Exit(Candidate);
  // Search in the parent directory
  Candidate := ExtractFilePath(ExcludeTrailingPathDelimiter(FBasePath)) + Utf8ToString(aServiceName) + '.exe';
  if FileExists(Candidate) then
    Exit(Candidate);
  // Fallback: relative path (will be resolved at start time)
  Result := Utf8ToString(aServiceName) + '.exe';
end;

function TServiceOrchestrator.GetStatusJson: RawUtf8;
var
  StatusDto: TControllerStatusDto;
  ServiceIdx: integer;
begin
  StatusDto.Controller := 'ms.controller';
  StatusDto.Port := FPort;
  StatusDto.Timestamp := NowUtc;
  SetLength(StatusDto.Services, Length(FServices));
  for ServiceIdx := 0 to High(FServices) do
  begin
    StatusDto.Services[ServiceIdx].Name := FServices[ServiceIdx].Name;
    StatusDto.Services[ServiceIdx].Port := FServices[ServiceIdx].Port;
    StatusDto.Services[ServiceIdx].Status := StatusToText(FServices[ServiceIdx].Status);
    StatusDto.Services[ServiceIdx].HealthOk := FServices[ServiceIdx].HealthOk;
    StatusDto.Services[ServiceIdx].RestartCount := FServices[ServiceIdx].RestartCount;
    StatusDto.Services[ServiceIdx].Pid := FServices[ServiceIdx].ProcessId;
  end;
  Result := RecordSaveJson(StatusDto, TypeInfo(TControllerStatusDto));
end;

function TServiceOrchestrator.IsProcessRunning(
  aHandle: THandle
  ): boolean;
var
  ExitCode: Cardinal;
begin
  Result := (aHandle <> 0) and
    GetExitCodeProcess(aHandle, ExitCode) and
    (ExitCode = STILL_ACTIVE);
end;

procedure TServiceOrchestrator.MonitorServices(
  aSender: TSynBackgroundTimer;
  const aMsg: RawUtf8
  );
var
  ServiceIdx: integer;
begin
  for ServiceIdx := 0 to High(FServices) do
  begin
    if FShutdownRequested then
      Exit;

    case FServices[ServiceIdx].Status of
      TServiceProcessStatus.Running:
      begin
        // Check whether the process is still running
        if not IsProcessRunning(FServices[ServiceIdx].ProcessHandle) then
        begin
          WriteLn('[Monitor] ', FServices[ServiceIdx].Name, ' has crashed!');
          CloseHandle(FServices[ServiceIdx].ProcessHandle);
          FServices[ServiceIdx].ProcessHandle := 0;
          FServices[ServiceIdx].Status := TServiceProcessStatus.Error;
          FServices[ServiceIdx].HealthOk := False;

          // Attempt restart
          if FServices[ServiceIdx].RestartCount < FServices[ServiceIdx].MaxRestarts then
          begin
            Inc(FServices[ServiceIdx].RestartCount);
            WriteLn('[Monitor] Restart #', FServices[ServiceIdx].RestartCount, ' of ', FServices[ServiceIdx].Name);
            StartProcess(FServices[ServiceIdx]);
          end
          else
          begin
            WriteLn('[Monitor] ', FServices[ServiceIdx].Name, ' -- maximum restarts reached!');
          end;
        end
        else
        begin
          // Perform health check
          CheckHealth(FServices[ServiceIdx]);
        end;
      end;
    end;
  end;
end;

function TServiceOrchestrator.OnRequest(
  aCtxt: THttpServerRequestAbstract
  ): cardinal;
var
  Path, ServiceName: RawUtf8;
  ServiceIdx: integer;
begin
  Path := aCtxt.Url;

  // GET /api/status -- overall status of all services
  if (aCtxt.Method = 'GET') and (Path = '/api/status') then
  begin
    aCtxt.OutContent := GetStatusJson;
    aCtxt.OutContentType := JSON_CONTENT_TYPE;
    Result := HTTP_SUCCESS;
  end

  // POST /api/start-all -- start all services
  else if (aCtxt.Method = 'POST') and (Path = '/api/start-all') then
  begin
    StartAll;
    aCtxt.OutContent := GetStatusJson;
    aCtxt.OutContentType := JSON_CONTENT_TYPE;
    Result := HTTP_SUCCESS;
  end

  // POST /api/stop-all -- stop all services
  else if (aCtxt.Method = 'POST') and (Path = '/api/stop-all') then
  begin
    StopAll;
    aCtxt.OutContent := GetStatusJson;
    aCtxt.OutContentType := JSON_CONTENT_TYPE;
    Result := HTTP_SUCCESS;
  end

  // POST /api/restart/{service} -- restart a single service
  else if (aCtxt.Method = 'POST') and (Copy(Path, 1, 13) = '/api/restart/') then
  begin
    ServiceName := Copy(Path, 14, MaxInt);
    Result := HTTP_NOTFOUND;
    for ServiceIdx := 0 to High(FServices) do
    begin
      if FServices[ServiceIdx].Name = ServiceName then
      begin
        StopProcess(FServices[ServiceIdx]);
        FServices[ServiceIdx].RestartCount := 0; // manual restart -> reset counter
        StartProcess(FServices[ServiceIdx]);
        aCtxt.OutContent := GetStatusJson;
        aCtxt.OutContentType := JSON_CONTENT_TYPE;
        Result := HTTP_SUCCESS;
        Break;
      end;
    end;
  end

  // POST /api/shutdown -- shut down controller + all services
  else if (aCtxt.Method = 'POST') and (Path = '/api/shutdown') then
  begin
    FShutdownRequested := True;
    aCtxt.OutContent := '{"success":true}';
    aCtxt.OutContentType := JSON_CONTENT_TYPE;
    Result := HTTP_SUCCESS;
  end

  else
    Result := HTTP_NOTFOUND;
end;

procedure TServiceOrchestrator.RegisterService(
  const aName: RawUtf8;
  const aPort: RawUtf8
  );
var
  EntryCount: integer;
begin
  EntryCount := Length(FServices);
  SetLength(FServices, EntryCount + 1);
  FServices[EntryCount].Name := aName;
  FServices[EntryCount].Port := aPort;
  FServices[EntryCount].ExePath := FindExe(aName);
  FServices[EntryCount].ProcessHandle := 0;
  FServices[EntryCount].ProcessId := 0;
  FServices[EntryCount].Status := TServiceProcessStatus.NotStarted;
  FServices[EntryCount].HealthOk := False;
  FServices[EntryCount].RestartCount := 0;
  FServices[EntryCount].MaxRestarts := MAX_RESTARTS_DEFAULT;
end;

procedure TServiceOrchestrator.Run;
begin
  WriteLn('=== ms.controller ===');
  WriteLn('Registering services...');

  // Register all blog services (order matters for startup)
  RegisterService(SERVICE_CONFIG,   PORT_CONFIG);
  RegisterService(SERVICE_MEDIA,    PORT_MEDIA);
  RegisterService(SERVICE_USERS,    PORT_USERS);
  RegisterService(SERVICE_AUTH,     PORT_AUTH);
  RegisterService(SERVICE_POSTS,    PORT_POSTS);
  RegisterService(SERVICE_TAGS,     PORT_TAGS);
  RegisterService(SERVICE_COMMENTS, PORT_COMMENTS);
  RegisterService(SERVICE_ANALYTICS, PORT_ANALYTICS);
  RegisterService(SERVICE_GATEWAY,  PORT_GATEWAY);

  WriteLn(Length(FServices), ' services registered.');
  WriteLn('');

  // Start HTTP server for controller API
  FHttpServer := THttpAsyncServer.Create(FPort, nil, nil, '', 2, 30000, [hsoNoXPoweredHeader]);
  FHttpServer.OnRequest := OnRequest;
  FHttpServer.WaitStarted;
  WriteLn('Controller API running on port ', FPort);
  WriteLn('');

  // Start config service first and wait for it to be healthy
  WriteLn('Starting config service...');
  StartProcess(FServices[0]);
  WaitForHealth(FServices[0], 5000);

  // Start remaining services
  StartAll;

  // Start monitor thread
  FMonitorThread := TSynBackgroundTimer.Create('ServiceMonitor');
  FMonitorThread.Enable(MonitorServices, HEALTH_CHECK_INTERVAL_SEC);

  WriteLn('');
  WriteLn('=== Commands ===');
  WriteLn('  GET  /api/status           Overall status');
  WriteLn('  POST /api/start-all        Start all');
  WriteLn('  POST /api/stop-all         Stop all');
  WriteLn('  POST /api/restart/{name}   Restart individual');
  WriteLn('  POST /api/shutdown         Shut down everything');
  WriteLn('  Enter                      Quit');
  WriteLn('');

  // Wait for shutdown
  while not FShutdownRequested do
  begin
    if ConsoleKeyPressed(VK_RETURN) then
    begin
      ReadLn;
      Break;
    end;
    SleepHiRes(200);
  end;

  WriteLn('');
  WriteLn('Shutting down...');
  FMonitorThread.Disable(MonitorServices);
  StopAll;
  WriteLn('All services stopped. Controller is closing.');
end;

procedure TServiceOrchestrator.StartAll;
var
  ServiceIdx: integer;
begin
  WriteLn('Starting all services...');
  for ServiceIdx := 0 to High(FServices) do
  begin
    if FServices[ServiceIdx].Status in [TServiceProcessStatus.NotStarted, TServiceProcessStatus.Stopped,
      TServiceProcessStatus.Error] then
      StartProcess(FServices[ServiceIdx]);
  end;
  WriteLn('All services started.');
end;

function TServiceOrchestrator.StartProcess(
  var aEntry: TServiceEntry
  ): boolean;
var
  StartupInfo: TStartupInfoW;
  ProcessInfo: TProcessInformation;
  CommandLine: string;
begin
  Result := False;
  if not FileExists(aEntry.ExePath) then
  begin
    WriteLn('  ERROR: ', aEntry.ExePath, ' not found');
    aEntry.Status := TServiceProcessStatus.Error;
    Exit;
  end;

  aEntry.Status := TServiceProcessStatus.Starting;
  FillChar(StartupInfo, SizeOf(StartupInfo), 0);
  StartupInfo.cb := SizeOf(StartupInfo);
  StartupInfo.dwFlags := STARTF_USESHOWWINDOW;
  StartupInfo.wShowWindow := SW_SHOWMINNOACTIVE; // start minimized

  CommandLine := string(aEntry.ExePath);
  if CreateProcessW(nil, PChar(CommandLine), nil, nil, False, CREATE_NEW_CONSOLE, nil,
    PChar(ExtractFilePath(string(aEntry.ExePath))), StartupInfo, ProcessInfo) then
  begin
    aEntry.ProcessHandle := ProcessInfo.hProcess;
    aEntry.ProcessId := ProcessInfo.dwProcessId;
    CloseHandle(ProcessInfo.hThread);
    WriteLn('  Started: ', aEntry.Name, ' (PID ', aEntry.ProcessId, ')');
    // Wait briefly, then health check
    SleepHiRes(PROCESS_START_WAIT_MS);
    if IsProcessRunning(aEntry.ProcessHandle) then
    begin
      aEntry.Status := TServiceProcessStatus.Running;
      Result := True;
    end
    else
    begin
      aEntry.Status := TServiceProcessStatus.Error;
      WriteLn('  ERROR: ', aEntry.Name, ' terminated immediately');
    end;
  end
  else
  begin
    aEntry.Status := TServiceProcessStatus.Error;
    WriteLn('  ERROR starting ', aEntry.Name, ': ', SysErrorMessage(GetLastError));
  end;
end;

function TServiceOrchestrator.StatusToText(
  aStatus: TServiceProcessStatus
  ): RawUtf8;
begin
  Result := STATUS_TEXT[aStatus];
end;

procedure TServiceOrchestrator.StopAll;
var
  ServiceIdx: integer;
begin
  WriteLn('Stopping all services...');
  // Stop in reverse order (gateway first)
  for ServiceIdx := High(FServices) downto 0 do
  begin
    if FServices[ServiceIdx].Status in [TServiceProcessStatus.Running, TServiceProcessStatus.Starting] then
      StopProcess(FServices[ServiceIdx]);
  end;
  WriteLn('All services stopped.');
end;

function TServiceOrchestrator.StopProcess(
  var aEntry: TServiceEntry
  ): boolean;
var
  Client: THttpClientSocket;
  StatusCode: integer;
begin
  if aEntry.Status in [TServiceProcessStatus.Stopped, TServiceProcessStatus.NotStarted] then
    Exit(True);

  aEntry.Status := TServiceProcessStatus.Stopping;
  WriteLn('  Stopping ', aEntry.Name, '...');

  // Attempt 1: Graceful shutdown via /api/shutdown
  try
    Client := THttpClientSocket.Create(5000);
    try
      Client.OpenBind('localhost', aEntry.Port, False);
      StatusCode := Client.Request('/api/shutdown', 'POST', 0, '');
      if StatusCode = 200 then
        // Wait for the process to exit (max 5 sec)
        WaitForSingleObject(aEntry.ProcessHandle, 5000);
    finally
      Client.Free;
    end;
  except
    // Shutdown endpoint unreachable -- proceed with TerminateProcess
  end;

  // Attempt 2: Force-terminate the process if still running
  if IsProcessRunning(aEntry.ProcessHandle) then
  begin
    WriteLn('  Force-terminating ', aEntry.Name);
    TerminateProcess(aEntry.ProcessHandle, 1);
    WaitForSingleObject(aEntry.ProcessHandle, 3000);
  end;

  CloseHandle(aEntry.ProcessHandle);
  aEntry.ProcessHandle := 0;
  aEntry.ProcessId := 0;
  aEntry.Status := TServiceProcessStatus.Stopped;
  aEntry.HealthOk := False;
  WriteLn('  Stopped: ', aEntry.Name);
  Result := True;
end;

procedure TServiceOrchestrator.WaitForHealth(
  var aEntry: TServiceEntry;
  aTimeoutMs: integer
  );
var
  Elapsed: integer;
begin
  Elapsed := 0;
  while Elapsed < aTimeoutMs do
  begin
    if CheckHealth(aEntry) then
    begin
      WriteLn('  ', aEntry.Name, ' is healthy.');
      Exit;
    end;
    SleepHiRes(500);
    Inc(Elapsed, 500);
  end;
  WriteLn('  WARNING: ', aEntry.Name, ' did not respond to health check within ', aTimeoutMs, 'ms');
end;

initialization
  Rtti.RegisterFromText([
    TypeInfo(TServiceStatusDto),
    'Name,Port,Status: RawUtf8; HealthOk: Boolean; RestartCount: integer; Pid: Cardinal',
    TypeInfo(TControllerStatusDto),
    'Controller,Port: RawUtf8; Services: array of TServiceStatusDto; Timestamp: TDateTime'
  ]);

end.
