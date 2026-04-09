/// <summary>
///   Shared base class and helpers for all blog microservices.
///
///   This unit implements the core microservice skeleton using mORMot2:
///   - <c>TMicroService</c>: template-method base class that wires up
///     ORM model, REST server, HTTP transport, logging, health check, and graceful shutdown -- subclasses only override
///     <c>CreateModel</c> and <c>SetupServices</c>.
///   - <c>OrmGetById</c> / <c>OrmGetAll</c>: reusable helpers for the most common ORM read patterns.
///
///   mORMot2 components used:
///   - <c>TRestServerDB</c>: combines a REST server with an embedded SQLite database via the mORMot2 ORM.
///   - <c>TRestHttpServer</c>: exposes the REST server over HTTP
///     using the high-performance async I/O engine (IOCP on Windows).
///   - <c>TSynLog</c>: structured logging with automatic rotation.
///   - <c>ServiceMethodRegister</c>: registers custom method-based
///     endpoints (health, shutdown) outside the SOA interface system.
/// </summary>
unit ms.shared.service;

{$SCOPEDENUMS ON}
{$I mormot.defines.inc}
{$WARN SYMBOL_PLATFORM OFF}
{$WARN UNIT_PLATFORM OFF}

interface

uses
  System.SysUtils,
  mormot.core.base,
  mormot.core.datetime,
  mormot.core.json,
  mormot.core.log,
  mormot.core.os,
  mormot.core.rtti,
  mormot.core.text,
  mormot.core.unicode,
  mormot.db.raw.sqlite3,
  mormot.net.http,
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
  ms.shared.correlation;

type

  /// <summary>
  ///   Abstract base class for all blog microservices.
  ///   Implements the Template Method pattern: subclasses override
  ///   <c>CreateModel</c> (define ORM tables) and <c>SetupServices</c>
  ///   (register SOA interfaces), while the base class handles the full server lifecycle in <c>Run</c>.
  ///
  ///   Each microservice instance owns:
  ///   - A <c>TOrmModel</c> defining which TOrm classes (tables) this service manages.
  ///   - A <c>TRestServerDB</c> providing ORM persistence via SQLite and hosting the SOA interface implementations.
  ///   - A <c>TRestHttpServer</c> exposing everything over HTTP.
  ///
  ///   Management endpoints registered automatically:
  ///   - GET /api/health -- returns service status as JSON.
  ///   - POST /api/shutdown -- triggers graceful shutdown.
  /// </summary>
  TMicroService = class
  strict private
    FConfig: TMicroServiceConfig;
    FLogFamily: TSynLogFamily;
    FPort: RawUtf8;
    FServiceName: RawUtf8;
    FShutdownRequested: boolean;
    FStartTime: TDateTime;

    /// <summary>
    ///   The original mORMot2 HTTP request handler captured before correlation-ID wrapping.
    ///   <c>HandleRequestWithCorrelation</c> delegates to this after extracting/setting the request's correlation ID.
    /// </summary>
    FInnerHttpHandler: TOnHttpServerRequest;

    /// <summary>
    ///   Configures <c>TSynLog</c> with file rotation, per-service log files, and console echo. Log level is read from
    ///   the JSON config file (trace/debug/info/error).
    /// </summary>
    procedure InitLogging;

    /// <summary>
    ///   HTTP request handler wrapper that extracts (or generates) the correlation ID from the incoming request,
    ///   stores it in a thread-local variable for the duration of the request, mirrors it to the response headers,
    ///   and delegates to the inner mORMot2 handler. Cleans the threadvar after the request to prevent leakage
    ///   between pooled requests.
    /// </summary>
    /// <param name="aCtxt">
    ///   The HTTP request context provided by the async HTTP server.
    /// </param>
    /// <returns>
    ///   The HTTP status code returned by the inner handler.
    /// </returns>
    function HandleRequestWithCorrelation(
      aCtxt: THttpServerRequestAbstract
      ): cardinal;

    /// <summary>
    ///   Method-based service handler for GET /api/health. Returns a JSON object with service name, port, version,
    ///   and uptime. Registered via <c>ServiceMethodRegister</c>, which is mORMot2's mechanism for custom REST
    ///   endpoints outside the SOA interface system.
    /// </summary>
    /// <param name="Ctxt">
    ///   The REST request context provided by mORMot2.
    /// </param>
    procedure HandleHealth(
      Ctxt: TRestServerUriContext
      );

    /// <summary>
    ///   Method-based service handler for POST /api/shutdown. Sets the shutdown flag to break the main loop in <c>Run</c>.
    /// </summary>
    /// <param name="Ctxt">
    ///   The REST request context provided by mORMot2.
    /// </param>
    procedure HandleShutdown(
      Ctxt: TRestServerUriContext
      );
  protected
    /// <summary>
    ///   The ORM model defining which TOrm classes this service uses.
    ///   Created by <c>CreateModel</c> and owned by this instance.
    /// </summary>
    FModel: TOrmModel;

    /// <summary>
    ///   The REST server combining ORM persistence (SQLite) with SOA interface hosting. This is the central mORMot2
    ///   component that every microservice builds upon.
    /// </summary>
    FRestServer: TRestServerDB;

    /// <summary>
    ///   The HTTP server exposing <c>FRestServer</c> over the network.
    ///   Uses <c>useHttpAsync</c> for high-performance async I/O with IOCP (Windows) or epoll (Linux).
    /// </summary>
    FHttpServer: TRestHttpServer;

    /// <summary>
    ///   Creates the ORM model with the service's table classes. Subclasses must pass <c>MODEL_ROOT</c> as the model
    ///   root to ensure consistent URL routing: /api/{Service}/{Method}.
    /// </summary>
    /// <returns>
    ///   A new <c>TOrmModel</c> instance (ownership transfers to this <c>TMicroService</c>).
    /// </returns>
    function CreateModel: TOrmModel; virtual; abstract;

    /// <summary>
    ///   Registers interface-based (SOA) services on the REST server. Use <c>RegisterService</c> to register each
    ///   implementation with standard settings.
    /// </summary>
    procedure SetupServices; virtual; abstract;

    /// <summary>
    ///   Hook called after all services are registered and the HTTP server is running. Override for post-startup
    ///   initialization (e.g., the gateway intercepts the HTTP handler here).
    /// </summary>
    procedure DoInitialize; virtual;

    /// <summary>
    ///   Hook called before the server shuts down. Override for cleanup (e.g., releasing client connections).
    /// </summary>
    procedure DoFinalize; virtual;

    /// <summary>
    ///   Registers a SOA service implementation on the REST server with the standard settings used by all blog services:
    ///   - <c>ByPassAuthentication</c>: disables mORMot2's built-in REST authentication (we use our own SCRAM-MCF/JWT).
    ///   - <c>ResultAsJsonObjectWithoutResult</c>: returns output parameters as named JSON keys instead of a positional
    ///     array, which is easier to consume from JavaScript.
    /// </summary>
    /// <param name="aImpl">
    ///   The service implementation object (must implement the interface specified by <c>aInterface</c>).
    /// </param>
    /// <param name="aInterface">
    ///   RTTI pointer to the service interface, obtained via <c>TypeInfo(IMyService)</c>.
    /// </param>
    /// <returns>
    ///   The service factory, for further configuration if needed.
    /// </returns>
    function RegisterService(
      aImpl: TInterfacedObject;
      aInterface: PRttiInfo
      ): TServiceFactoryServerAbstract;
  public
    /// <summary>
    ///   Creates the microservice instance. Loads configuration from a JSON file ({serviceName}.config.json) and sets
    ///   up logging. Does NOT start the server yet -- call <c>Run</c>.
    /// </summary>
    /// <param name="aServiceName">
    ///   Identifier used for logging, config file name, and database file name (e.g., 'ms.posts').
    /// </param>
    /// <param name="aDefaultPort">
    ///   HTTP port to use if not specified in the config file.
    /// </param>
    constructor Create(
      const aServiceName, aDefaultPort: RawUtf8
      );

    /// <summary>
    ///   Frees the HTTP server, REST server, and ORM model.
    /// </summary>
    destructor Destroy; override;

    /// <summary>
    ///   Signals the service to shut down. Can be called from any thread (e.g., from the shutdown HTTP handler).
    /// </summary>
    procedure RequestShutdown;

    /// <summary>
    ///   Main entry point. Creates the database, registers services, starts the HTTP server, and enters the main loop.
    ///   Blocks until Enter is pressed or <c>RequestShutdown</c> is called (e.g., via POST /api/shutdown).
    /// </summary>
    procedure Run;

    /// <summary>
    ///   The loaded service configuration (port, log level, URLs).
    /// </summary>
    property Config: TMicroServiceConfig read FConfig;

    /// <summary>
    ///   The HTTP port this service listens on.
    /// </summary>
    property Port: RawUtf8 read FPort;

    /// <summary>
    ///   The underlying mORMot2 REST server. Exposed for testing and advanced configuration.
    /// </summary>
    property RestServer: TRestServerDB read FRestServer;

    /// <summary>
    ///   The service's identifier (e.g., 'ms.posts').
    /// </summary>
    property ServiceName: RawUtf8 read FServiceName;
  end;

const
  /// <summary>
  ///   Semantic version of all blog microservices.
  /// </summary>
  SERVICE_VERSION = '0.2.0';

  /// <summary>
  ///   Model root for all services. Determines the URL prefix: all SOA endpoints become /api/{InterfaceName}/{MethodName}.
  ///   Every <c>CreateModel</c> override must pass this value to <c>TOrmModel.Create</c>.
  /// </summary>
  MODEL_ROOT = 'api';

/// <summary>
///   Retrieves a single ORM record by its ID and returns it as JSON.
///   This is the standard "get by ID" pattern used across all services.
///   Uses <c>IRestOrm.Retrieve</c> for the lookup and <c>TOrm.GetJsonValues</c> for serialization.
/// </summary>
/// <param name="aOrm">
///   The ORM interface (typically <c>FRestServer.Orm</c> or injected via constructor for testability).
/// </param>
/// <param name="aClass">
///   The TOrm descendant class to instantiate and retrieve.
/// </param>
/// <param name="aId">
///   The record ID (SQLite RowID) to look up.
/// </param>
/// <returns>
///   JSON object with all published fields, or '{}' if not found.
/// </returns>
function OrmGetById(
  const aOrm: IRestOrm;
  aClass: TOrmClass;
  aId: TID
  ): RawJson;

/// <summary>
///   Retrieves all ORM records of a given class, optionally filtered by a WHERE clause, and returns them as a JSON array.
///   Uses <c>IRestOrm.MultiFieldValues</c> which returns a <c>TOrmTable</c> (an in-memory result set).
/// </summary>
/// <param name="aOrm">
///   The ORM interface.
/// </param>
/// <param name="aClass">
///   The TOrm descendant class to query.
/// </param>
/// <param name="aWhere">
///   Optional SQL WHERE clause (without the WHERE keyword). Pass empty string to retrieve all records.
/// </param>
/// <returns>
///   JSON array of objects, or '[]' if no records match.
/// </returns>
function OrmGetAll(
  const aOrm: IRestOrm;
  aClass: TOrmClass;
  const aWhere: RawUtf8 = ''
  ): RawJson;

/// <summary>
///   Fetches the configuration for a service from the central <c>ms.config</c> service via a temporary HTTP connection.
/// </summary>
/// <param name="aConfigUrl">
///   URL of the config service (e.g. 'http://localhost:8087').
/// </param>
/// <param name="aServiceName">
///   Service identifier to query (e.g. 'ms.auth').
/// </param>
/// <param name="aConfig">
///   Output: the parsed configuration record.
/// </param>
/// <returns>
///   True if the config was fetched and parsed successfully, False on any network or parsing error.
/// </returns>
function FetchRemoteConfig(
  const aConfigUrl: RawUtf8;
  const aServiceName: RawUtf8;
  out aConfig: TMicroServiceConfig
  ): boolean;

/// <summary>
///   Merges two configuration records. For each field, the remote value wins if it is non-empty/non-zero; otherwise
///   the local value is kept.
/// </summary>
/// <param name="aLocal">
///   The local baseline configuration (from .config.json).
/// </param>
/// <param name="aRemote">
///   The remotely fetched configuration (from ms.config).
/// </param>
/// <returns>
///   The merged configuration record.
/// </returns>
function MergeServiceConfig(
  const aLocal, aRemote: TMicroServiceConfig
  ): TMicroServiceConfig;

/// <summary>
///   Maps a string value to a <c>TRestHttpServerSecurity</c> enum.
/// </summary>
/// <param name="aValue">
///   String representation: 'secNone' or 'secTLS'.
/// </param>
/// <returns>
///   The corresponding enum value. Defaults to <c>secNone</c>.
/// </returns>
function SecurityFromString(
  const aValue: RawUtf8
  ): TRestHttpServerSecurity;

implementation

constructor TMicroService.Create(
  const aServiceName, aDefaultPort: RawUtf8
  );
var
  Bootstrap: TBootstrapConfig;
  RemoteConfig: TMicroServiceConfig;
  CachePath: TFileName;
  CacheJson: RawUtf8;
begin
  inherited Create;
  FServiceName := aServiceName;
  FShutdownRequested := False;
  // Step 1: Load local config (fallback baseline)
  FConfig := LoadServiceConfig(Executable.ProgramFilePath + Utf8ToString(aServiceName) + '.config.json', aDefaultPort);
  // Step 2: Try remote config from ms.config (skip for ms.config itself)
  if aServiceName <> SERVICE_CONFIG then
  begin
    Bootstrap := LoadBootstrapConfig(aServiceName);
    if Bootstrap.ConfigUrl <> '' then
    begin
      if FetchRemoteConfig(Bootstrap.ConfigUrl, aServiceName, RemoteConfig) then
      begin
        FConfig := MergeServiceConfig(FConfig, RemoteConfig);
        // Cache for offline fallback
        CachePath := Executable.ProgramFilePath + Utf8ToString(aServiceName) + '.config.cached.json';
        FileFromString(RecordSaveJson(RemoteConfig, TypeInfo(TMicroServiceConfig)), CachePath);
      end
      else
      begin
        // Try cached config from previous successful fetch
        CachePath := Executable.ProgramFilePath + Utf8ToString(aServiceName) + '.config.cached.json';
        if FileExists(CachePath) then
        begin
          CacheJson := StringFromFile(CachePath);
          Finalize(RemoteConfig);
          FillCharFast(RemoteConfig, SizeOf(RemoteConfig), 0);
          RecordLoadJson(RemoteConfig, CacheJson, TypeInfo(TMicroServiceConfig));
          FConfig := MergeServiceConfig(FConfig, RemoteConfig);
        end;
      end;
    end;
  end;
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
  // Override in subclasses for pre-shutdown cleanup
end;

procedure TMicroService.DoInitialize;
begin
  // Override in subclasses for post-startup initialization
end;

function TMicroService.HandleRequestWithCorrelation(
  aCtxt: THttpServerRequestAbstract
  ): cardinal;
var
  CorrId: RawUtf8;
begin
  // Extract correlation ID from incoming headers, or generate a new one if absent.
  // The result is stored in the threadvar so that any code on this request thread can read it
  // (logging, outgoing HTTP forwards, etc.).
  CorrId := EnsureCorrelationIdFromHeaders(aCtxt.InHeaders);
  // Mirror the correlation ID to the response so the caller can correlate request and response.
  aCtxt.OutCustomHeaders := aCtxt.OutCustomHeaders + #13#10 + CORRELATION_HEADER + ': ' + CorrId;
  try
    Result := FInnerHttpHandler(aCtxt);
  finally
    // The HTTP server reuses threads from a pool. Clear the threadvar so the next request
    // on this thread does not inherit the previous correlation ID.
    ClearCurrentCorrelationId;
  end;
end;

procedure TMicroService.HandleHealth(
  Ctxt: TRestServerUriContext
  );
begin
  // Ctxt.Returns sends a JSON response with HTTP 200.
  // JsonEncode creates a JSON object from name/value pairs.
  Ctxt.Returns(JsonEncode([
    'service', FServiceName,
    'status', 'ok',
    'port', FPort,
    'version', SERVICE_VERSION,
    'uptime', FormatUtf8('%', [DateTimeMSToString(NowUtc - FStartTime)])
  ]));
end;

procedure TMicroService.HandleShutdown(
  Ctxt: TRestServerUriContext
  );
begin
  // Ctxt.Success sends HTTP 200 with no content.
  // Setting FShutdownRequested breaks the main loop in Run.
  Ctxt.Success;
  FShutdownRequested := True;
end;

procedure TMicroService.InitLogging;
var
  LogPath: TFileName;
begin
  LogPath := Executable.ProgramFilePath + 'logs';
  if not DirectoryExists(LogPath) then
    CreateDir(LogPath);
  // TSynLog.Family is a singleton that configures logging for the
  // entire process. Each service gets its own log file via CustomFileName.
  FLogFamily := TSynLog.Family;
  FLogFamily.DestinationPath := LogPath + PathDelim;
  FLogFamily.CustomFileName := Utf8ToString(FServiceName);
  // Rotate after 5 MB, keep 5 old files
  FLogFamily.RotateFileCount := 5;
  FLogFamily.RotateFileSizeKB := 5 * 1024;
  // All threads log to one file (identified by thread name)
  FLogFamily.PerThreadLog := ptIdentifiedInOneFile;
  // Map config string to mORMot2 log level sets
  if FConfig.LogLevel = 'trace' then
    FLogFamily.Level := LOG_VERBOSE
  else if FConfig.LogLevel = 'debug' then
    FLogFamily.Level := LOG_VERBOSE - [sllTrace]
  else if FConfig.LogLevel = 'info' then
    FLogFamily.Level := [sllInfo, sllWarning, sllError, sllLastError, sllException, sllExceptionOS]
  else if FConfig.LogLevel = 'error' then
    FLogFamily.Level := [sllError, sllLastError, sllException, sllExceptionOS]
  else
    FLogFamily.Level := LOG_VERBOSE - [sllTrace];
  // Echo log entries to the console (useful for development)
  FLogFamily.EchoToConsole := FLogFamily.Level;
end;

function TMicroService.RegisterService(
  aImpl: TInterfacedObject;
  aInterface: PRttiInfo
  ): TServiceFactoryServerAbstract;
begin
  // ServiceRegister connects a TInterfacedObject to its interface.
  // mORMot2 generates the JSON marshalling code via RTTI and routes
  // HTTP requests to the matching method automatically.
  Result := FRestServer.ServiceRegister(aImpl, [aInterface]);
  // ByPassAuthentication: we handle auth ourselves (SCRAM-MCF/JWT)
  // instead of using mORMot2's built-in REST authentication.
  Result.ByPassAuthentication := True;
  // ResultAsJsonObjectWithoutResult: returns output parameters as
  // named JSON keys (e.g., {"aMcfInfo":"...","aServerNonce":"..."})
  // instead of a positional array. Easier to consume from JavaScript.
  Result.ResultAsJsonObjectWithoutResult := True;
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
  TSynLog.Add.Log(sllInfo, '% starting on port %...', [FServiceName, FPort], self);
  try
    // --- Phase 1: Create ORM model and database ---
    // Each service has its own SQLite file ({serviceName}.db).
    // TRestServerDB combines TRestServer (REST/SOA) with TSqlDataBase
    // (SQLite access) -- it's the central mORMot2 component.
    DatabasePath := Executable.ProgramFilePath + Utf8ToString(FServiceName) + '.db';
    FModel := CreateModel;
    FRestServer := TRestServerDB.Create(FModel, DatabasePath);
    // smNormal: SQLite syncs at critical moments (good balance
    // between safety and performance for a single-writer scenario)
    FRestServer.DB.Synchronous := smNormal;
    // lmExclusive: no other process can access the DB file while
    // the service is running (better performance, single-service design)
    FRestServer.DB.LockingMode := lmExclusive;
    // CreateMissingTables automatically creates SQLite tables for any
    // TOrm class in the model that doesn't have a table yet.
    FRestServer.Server.CreateMissingTables;

    // --- Phase 2: Register SOA services ---
    // Subclasses create their service implementations and call
    // RegisterService to wire them into the REST server.
    SetupServices;

    // --- Phase 3: Register management endpoints ---
    // ServiceMethodRegister adds custom method-based endpoints
    // that are NOT part of the SOA interface system. The third
    // parameter (True) bypasses authentication.
    FRestServer.ServiceMethodRegister('health', HandleHealth, True, [mGET]);
    FRestServer.ServiceMethodRegister('shutdown', HandleShutdown, True, [mPOST]);

    // --- Phase 4: Start HTTP server ---
    // TRestHttpServer wraps TRestServerDB in an HTTP layer.
    // useHttpAsync uses the high-performance async I/O engine
    // (IOCP on Windows, epoll on Linux). The '+' means bind to
    // all network interfaces. 4 is the thread pool size.
    // secNone means no HTTPS (suitable for localhost/development).
    FHttpServer := TRestHttpServer.Create(
      FPort, FRestServer, FConfig.HttpBind, useHttpAsync, nil,
      FConfig.HttpThreads, SecurityFromString(FConfig.HttpSecurity));
    FHttpServer.AccessControlAllowOrigin := FConfig.CorsOrigin;
    // Wrap the HTTP handler to extract/propagate correlation IDs for every request.
    // Subclasses (e.g. TGatewayServer) may add additional wraps in DoInitialize -- they then capture
    // this wrap as their inner handler, so the chain remains correct.
    FInnerHttpHandler := FHttpServer.HttpServer.OnRequest;
    FHttpServer.HttpServer.OnRequest := HandleRequestWithCorrelation;
    DoInitialize;
    LogWithCorrelation(sllInfo, '% running on port %.', [FServiceName, FPort], self);
    WriteLn(FServiceName, ' running on port ', FPort, '.');
    WriteLn('Press Enter to stop.');

    // --- Phase 5: Main loop ---
    // Wait for either Enter key or shutdown signal (from the
    // POST /api/shutdown endpoint or RequestShutdown call).
    // ConsoleKeyPressed checks for key presses without blocking.
    // SleepHiRes yields the CPU efficiently (uses SwitchToThread
    // on Windows for sub-millisecond precision).
    while not FShutdownRequested do
    begin
      if ConsoleKeyPressed($0D) then
        Break;
      SleepHiRes(200);
    end;

    // --- Phase 6: Graceful shutdown ---
    TSynLog.Add.Log(sllInfo, '% shutting down...', [FServiceName], self);
    DoFinalize;
    FreeAndNil(FHttpServer);
    FreeAndNil(FRestServer);
    FreeAndNil(FModel);
    TSynLog.Add.Log(sllInfo, '% stopped.', [FServiceName], self);
  except
    on E: Exception do
    begin
      TSynLog.Add.Log(sllError, 'ERROR in %: %', [FServiceName, E.Message], self);
      WriteLn('ERROR: ', E.Message);
    end;
  end;
end;

function OrmGetById(
  const aOrm: IRestOrm;
  aClass: TOrmClass;
  aId: TID
  ): RawJson;
var
  Rec: TOrm;
begin
  // aClass.Create instantiates the correct TOrm descendant.
  // IRestOrm.Retrieve loads all published properties from SQLite
  // by RowID. GetJsonValues serializes them as a JSON object.
  Rec := aClass.Create;
  try
    if aOrm.Retrieve(aId, Rec) then
      Result := Rec.GetJsonValues(True, True, ooSelect)
    else
      Result := '{}';
  finally
    Rec.Free;
  end;
end;

function OrmGetAll(
  const aOrm: IRestOrm;
  aClass: TOrmClass;
  const aWhere: RawUtf8
  ): RawJson;
var
  Table: TOrmTable;
begin
  // MultiFieldValues returns a TOrmTable -- an in-memory result set
  // similar to a DataSet but much lighter. '*' means all fields.
  // The WHERE clause is optional (empty = no filter).
  Table := aOrm.MultiFieldValues(aClass, '*', aWhere);
  try
    if Table = nil then
      Result := '[]'
    else
      // GetJsonValues(True) serializes all rows as a JSON array
      // with expanded field names (not the compact integer-indexed format)
      Result := Table.GetJsonValues(True);
  finally
    Table.Free;
  end;
end;

function FetchRemoteConfig(
  const aConfigUrl: RawUtf8;
  const aServiceName: RawUtf8;
  out aConfig: TMicroServiceConfig
  ): boolean;
var
  ConfigClientModel: TOrmModel;
  ConfigClient: TRestHttpClient;
  ConfigIntf: IConfig;
  ConfigHost, ConfigPort: RawUtf8;
  ConfigJson: RawJson;
begin
  Result := False;
  Finalize(aConfig);
  FillCharFast(aConfig, SizeOf(aConfig), 0);
  // Parse host:port from URL like "http://localhost:8087"
  ConfigHost := aConfigUrl;
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
    ConfigClient := TRestHttpClient.Create(ConfigHost, ConfigPort, ConfigClientModel);
    try
      ConfigClient.Model.Owner := ConfigClient;
      ConfigClient.ServiceRegister([TypeInfo(IConfig)], sicShared);
      TServiceFactoryClient(ConfigClient.Services.Info(TypeInfo(IConfig))).ResultAsJsonObjectWithoutResult := True;
      if not ConfigClient.Services.Resolve(IConfig, ConfigIntf) then
        Exit;
      ConfigJson := ConfigIntf.GetServiceConfig(aServiceName);
      if (ConfigJson = '') or (ConfigJson = '{}') then
        Exit;
      RecordLoadJson(aConfig, ConfigJson, TypeInfo(TMicroServiceConfig));
      Result := True;
    finally
      ConfigIntf := nil;
      ConfigClient.Free;
    end;
  except
    Result := False;
  end;
end;

function MergeServiceConfig(
  const aLocal, aRemote: TMicroServiceConfig
  ): TMicroServiceConfig;
begin
  Result := aLocal;
  if aRemote.Port <> '' then
    Result.Port := aRemote.Port;
  if aRemote.Database <> '' then
    Result.Database := aRemote.Database;
  if aRemote.LogLevel <> '' then
    Result.LogLevel := aRemote.LogLevel;
  if aRemote.AuthUrl <> '' then
    Result.AuthUrl := aRemote.AuthUrl;
  if aRemote.UsersUrl <> '' then
    Result.UsersUrl := aRemote.UsersUrl;
  if aRemote.PostsUrl <> '' then
    Result.PostsUrl := aRemote.PostsUrl;
  if aRemote.TagsUrl <> '' then
    Result.TagsUrl := aRemote.TagsUrl;
  if aRemote.CommentsUrl <> '' then
    Result.CommentsUrl := aRemote.CommentsUrl;
  if aRemote.MediaUrl <> '' then
    Result.MediaUrl := aRemote.MediaUrl;
  if aRemote.JwtSecret <> '' then
    Result.JwtSecret := aRemote.JwtSecret;
  if aRemote.Host <> '' then
    Result.Host := aRemote.Host;
  if aRemote.HttpThreads > 0 then
    Result.HttpThreads := aRemote.HttpThreads;
  if aRemote.HttpSecurity <> '' then
    Result.HttpSecurity := aRemote.HttpSecurity;
  if aRemote.HttpBind <> '' then
    Result.HttpBind := aRemote.HttpBind;
  if aRemote.ModelRoot <> '' then
    Result.ModelRoot := aRemote.ModelRoot;
  if aRemote.CorsOrigin <> '' then
    Result.CorsOrigin := aRemote.CorsOrigin;
  if aRemote.MaxUploadSize > 0 then
    Result.MaxUploadSize := aRemote.MaxUploadSize;
end;

function SecurityFromString(
  const aValue: RawUtf8
  ): TRestHttpServerSecurity;
begin
  if IdemPropNameU(aValue, 'secTLS') then
    Exit(secTLS);
  Result := secNone;
end;

end.
