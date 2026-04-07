/// <summary>
///   Shared base class for all blog microservices.
///   Uses TRestServerDB for ORM + interface-based services
///   and TRestHttpServer for HTTP transport.
/// </summary>
unit ms.shared.service;

{$I mormot.defines.inc}

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
  mormot.db.raw.sqlite3,
  mormot.orm.base,
  mormot.orm.core,
  mormot.rest.core,
  mormot.rest.server,
  mormot.rest.sqlite3,
  mormot.rest.http.server,
  mormot.soa.core,
  mormot.soa.server,
  ms.shared;

type

  /// <summary>
  ///   Base class for a microservice backed by TRestServerDB.
  ///   Subclasses override CreateModel and SetupServices.
  /// </summary>
  TMicroService = class
  private
    FConfig: TMicroServiceConfig;
    FLogFamily: TSynLogFamily;
    FPort: RawUtf8;
    FServiceName: RawUtf8;
    FShutdownRequested: boolean;
    FStartTime: TDateTime;
    procedure InitLogging;
  protected
    FModel: TOrmModel;
    FRestServer: TRestServerDB;
    FHttpServer: TRestHttpServer;
    /// Creates the ORM model with the service's table classes.
    /// The model root MUST be 'api'.
    function CreateModel: TOrmModel; virtual; abstract;
    /// Registers interface-based services on the REST server.
    procedure SetupServices; virtual; abstract;
    /// Called after services are registered for extra initialization.
    procedure DoInitialize; virtual;
    /// Called before shutdown for cleanup.
    procedure DoFinalize; virtual;
  public
    constructor Create(const aServiceName, aDefaultPort: RawUtf8);
    destructor Destroy; override;
    procedure RequestShutdown;
    procedure Run;
    property Config: TMicroServiceConfig read FConfig;
    property Port: RawUtf8 read FPort;
    property RestServer: TRestServerDB read FRestServer;
    property ServiceName: RawUtf8 read FServiceName;
  end;

const
  SERVICE_VERSION = '0.2.0';
  /// Model root for all services -- keeps URLs as /api/ServiceName/Method
  MODEL_ROOT = 'api';

implementation

constructor TMicroService.Create(
  const aServiceName, aDefaultPort: RawUtf8);
begin
  inherited Create;
  FServiceName := aServiceName;
  FShutdownRequested := False;
  FConfig := LoadServiceConfig(
    Executable.ProgramFilePath +
      Utf8ToString(aServiceName) + '.config.json',
    aDefaultPort);
  FPort := FConfig.Port;
  InitLogging;
end;

destructor TMicroService.Destroy;
begin
  FreeAndNil(FHttpServer);
  FreeAndNil(FRestServer);
  FreeAndNil(FModel);
  inherited Destroy;
end;

procedure TMicroService.DoFinalize;
begin
  // Override in subclasses
end;

procedure TMicroService.DoInitialize;
begin
  // Override in subclasses
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
  FLogFamily.RotateFileSizeKB := 5 * 1024;
  FLogFamily.PerThreadLog := ptIdentifiedInOneFile;
  if FConfig.LogLevel = 'trace' then
    FLogFamily.Level := LOG_VERBOSE
  else if FConfig.LogLevel = 'debug' then
    FLogFamily.Level := LOG_VERBOSE - [sllTrace]
  else if FConfig.LogLevel = 'info' then
    FLogFamily.Level := [sllInfo, sllWarning, sllError,
      sllLastError, sllException, sllExceptionOS]
  else if FConfig.LogLevel = 'error' then
    FLogFamily.Level := [sllError, sllLastError,
      sllException, sllExceptionOS]
  else
    FLogFamily.Level := LOG_VERBOSE - [sllTrace];
  FLogFamily.EchoToConsole := FLogFamily.Level;
end;

procedure TMicroService.RequestShutdown;
begin
  FShutdownRequested := True;
end;

procedure TMicroService.Run;
var
  DatabasePath: TFileName;
begin
  FStartTime := NowUtc;
  TSynLog.Add.Log(sllInfo, '% starting on port %...',
    [FServiceName, FPort], self);
  try
    // Create ORM model and REST server
    DatabasePath := Executable.ProgramFilePath +
      Utf8ToString(FServiceName) + '.db';
    FModel := CreateModel;
    FRestServer := TRestServerDB.Create(FModel, DatabasePath);
    FRestServer.DB.Synchronous := smNormal;
    FRestServer.DB.LockingMode := lmExclusive;
    FRestServer.Server.CreateMissingTables;
    // Register interface-based services
    SetupServices;
    // Create HTTP server
    FHttpServer := TRestHttpServer.Create(
      FPort, FRestServer, '+', useHttpAsync, nil, 4, secNone);
    FHttpServer.AccessControlAllowOrigin := '*';
    DoInitialize;
    TSynLog.Add.Log(sllInfo, '% running on port %.',
      [FServiceName, FPort], self);
    WriteLn(FServiceName, ' running on port ', FPort, '.');
    WriteLn('Press Enter to stop.');
    // Wait for shutdown signal
    while not FShutdownRequested do
    begin
      if ConsoleKeyPressed($0D) then
        Break;
      SleepHiRes(200);
    end;
    TSynLog.Add.Log(sllInfo, '% shutting down...',
      [FServiceName], self);
    DoFinalize;
    FreeAndNil(FHttpServer);
    FreeAndNil(FRestServer);
    FreeAndNil(FModel);
    TSynLog.Add.Log(sllInfo, '% stopped.', [FServiceName], self);
  except
    on E: Exception do
    begin
      TSynLog.Add.Log(sllError, 'ERROR in %: %',
        [FServiceName, E.Message], self);
      WriteLn('ERROR: ', E.Message);
    end;
  end;
end;

end.
