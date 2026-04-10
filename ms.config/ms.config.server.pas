/// <summary>
///   Configuration microservice implementation. Loads a master configuration file (<c>ms.config.master.json</c>) at
///   startup and serves it to other services via the <c>IConfig</c> SOA interface. Each service queries its own
///   configuration block during bootstrap.
/// </summary>
unit ms.config.server;

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
  mormot.core.os,
  mormot.core.rtti,
  mormot.core.text,
  mormot.core.variants,
  mormot.orm.core,
  mormot.rest.core,
  mormot.rest.server,
  mormot.rest.sqlite3,
  mormot.soa.core,
  mormot.soa.server,
  ms.shared,
  ms.shared.api,
  ms.shared.correlation,
  ms.shared.service;

type

  /// <summary>
  ///   Implements <c>IConfig</c> by serving configuration from an in-memory <c>TDocVariantData</c> loaded from the master
  ///   JSON file. The master file may contain a special <c>defaults</c> block whose fields are merged into every
  ///   service's effective configuration. Per-service blocks override matching keys from <c>defaults</c>. No database
  ///   is needed.
  /// </summary>
  TConfigService = class(TInterfacedObject, IConfig)
  strict private
    /// <summary>
    ///   Parsed master configuration holding all service blocks (and the optional <c>defaults</c> block).
    /// </summary>
    FMasterDoc: TDocVariantData;

    /// <summary>
    ///   Builds the effective configuration for one service by starting from the <c>defaults</c> block (if present)
    ///   and overlaying the per-service block on top. Per-service keys win over default keys.
    /// </summary>
    /// <param name="aServiceName">
    ///   Service identifier to merge.
    /// </param>
    /// <param name="aMerged">
    ///   Output: the merged configuration document, ready to serialize.
    /// </param>
    /// <returns>
    ///   <c>True</c> if the service exists in the master document, <c>False</c> otherwise.
    /// </returns>
    function BuildMergedConfig(
      const aServiceName: RawUtf8;
      out aMerged: TDocVariantData
      ): boolean;
  public

    /// <summary>
    ///   Creates the config service and parses the master JSON.
    /// </summary>
    /// <param name="aMasterJson">
    ///   Complete master configuration as a JSON object keyed by service name. May contain an additional
    ///   <c>defaults</c> object with shared baseline values.
    /// </param>
    constructor Create(
      const aMasterJson: RawUtf8
      );

    /// <summary>
    ///   Returns the effective configuration for a specific service: the <c>defaults</c> block merged with the
    ///   per-service overrides.
    /// </summary>
    /// <param name="aServiceName">
    ///   Service identifier (e.g. 'ms.auth'). Asking for <c>defaults</c> returns '{}' since it is not a service.
    /// </param>
    /// <returns>
    ///   JSON object with all merged config fields, or '{}' if the service name is unknown.
    /// </returns>
    function GetServiceConfig(
      const aServiceName: RawUtf8
      ): RawJson;

    /// <summary>
    ///   Returns the complete merged configuration for all services. The <c>defaults</c> block itself is not included
    ///   in the result -- only the effective per-service configurations are.
    /// </summary>
    /// <returns>
    ///   JSON object keyed by service name.
    /// </returns>
    function GetAllConfigs: RawJson;

    /// <summary>
    ///   Returns the service registry containing only Host and Port per service. The <c>defaults</c> block is
    ///   excluded; Host falls back to the defaults block when a service does not override it. Secrets and database
    ///   paths are excluded.
    /// </summary>
    /// <returns>
    ///   JSON object keyed by service name, each entry containing only <c>Host</c> and <c>Port</c>.
    /// </returns>
    function GetServiceRegistry: RawJson;
  end;

  /// <summary>
  ///   Microservice server hosting the <c>IConfig</c> service. Loads the master config file during <c>SetupServices</c>.
  /// </summary>
  TConfigServer = class(TMicroService)
  strict private
    /// <summary>
    ///   The config service implementation instance.
    /// </summary>
    FConfigImpl: TConfigService;
  protected

    /// <summary>
    ///   Creates an empty ORM model (no tables needed).
    /// </summary>
    /// <returns>
    ///   A new <c>TOrmModel</c> with no TOrm classes.
    /// </returns>
    function CreateModel: TOrmModel; override;

    /// <summary>
    ///   Loads <c>ms.config.master.json</c> and registers the <c>IConfig</c> service implementation.
    /// </summary>
    procedure SetupServices; override;
  end;

implementation

const
  /// <summary>
  ///   Reserved key in the master JSON whose contents are merged into every service's effective configuration.
  ///   Per-service blocks override matching keys from this block.
  /// </summary>
  DEFAULTS_KEY = 'defaults';

constructor TConfigService.Create(
  const aMasterJson: RawUtf8
  );
begin
  inherited Create;
  FMasterDoc.InitJson(aMasterJson, JSON_FAST_FLOAT);
  if FMasterDoc.Kind <> dvObject then
    FMasterDoc.InitObject([], JSON_FAST);
end;

function TConfigService.BuildMergedConfig(
  const aServiceName: RawUtf8;
  out aMerged: TDocVariantData
  ): boolean;
var
  ServiceIdx, DefaultsIdx: PtrInt;
  ServiceDoc: PDocVariantData;
begin
  // The defaults key itself is not a service -- callers must not see it as one.
  if aServiceName = DEFAULTS_KEY then
    Exit(False);
  ServiceIdx := FMasterDoc.GetValueIndex(aServiceName);
  if ServiceIdx < 0 then
    Exit(False);
  // Start from a copy of the defaults block (if present), then overlay the per-service block on top.
  // AddOrUpdateFrom replaces existing keys with the values from the source document, so per-service keys win.
  DefaultsIdx := FMasterDoc.GetValueIndex(DEFAULTS_KEY);
  if DefaultsIdx >= 0 then
    aMerged.InitCopy(FMasterDoc.Values[DefaultsIdx], JSON_FAST)
  else
    aMerged.InitObject([], JSON_FAST);
  ServiceDoc := _Safe(FMasterDoc.Values[ServiceIdx]);
  if ServiceDoc^.Kind = dvObject then
    aMerged.AddOrUpdateFrom(variant(ServiceDoc^));
  Result := True;
end;

function TConfigService.GetAllConfigs: RawJson;
var
  Result_, Merged: TDocVariantData;
  ServiceIdx: PtrInt;
  ServiceName: RawUtf8;
begin
  // Walk every key in the master document, skip the defaults block, and emit the merged effective config
  // for each real service. Consumers see exactly what they would get from GetServiceConfig.
  Result_.InitObject([], JSON_FAST);
  for ServiceIdx := 0 to FMasterDoc.Count - 1 do
  begin
    ServiceName := FMasterDoc.Names[ServiceIdx];
    if ServiceName = DEFAULTS_KEY then
      Continue;
    if BuildMergedConfig(ServiceName, Merged) then
      Result_.AddValue(ServiceName, variant(Merged));
  end;
  Result := Result_.ToJson;
end;

function TConfigService.GetServiceConfig(
  const aServiceName: RawUtf8
  ): RawJson;
var
  Merged: TDocVariantData;
begin
  if not BuildMergedConfig(aServiceName, Merged) then
    Exit('{}');
  Result := Merged.ToJson;
end;

function TConfigService.GetServiceRegistry: RawJson;
var
  Registry, Entry, Merged: TDocVariantData;
  ServiceIdx: PtrInt;
  ServiceName: RawUtf8;
begin
  Registry.InitObject([], JSON_FAST);
  for ServiceIdx := 0 to FMasterDoc.Count - 1 do
  begin
    ServiceName := FMasterDoc.Names[ServiceIdx];
    if ServiceName = DEFAULTS_KEY then
      Continue;
    // Use the merged view so Host can come from the defaults block when the service does not override it.
    if not BuildMergedConfig(ServiceName, Merged) then
      Continue;
    Entry.InitObject([
      'Host', Merged.U['Host'],
      'Port', Merged.U['Port']
    ], JSON_FAST);
    Registry.AddValue(ServiceName, variant(Entry));
  end;
  Result := Registry.ToJson;
end;

function TConfigServer.CreateModel: TOrmModel;
begin
  Result := TOrmModel.Create([], MODEL_ROOT);
end;

procedure TConfigServer.SetupServices;
var
  MasterPath: TFileName;
  MasterJson: RawUtf8;
begin
  MasterPath := Executable.ProgramFilePath + 'ms.config.master.json';
  if FileExists(MasterPath) then
    MasterJson := StringFromFile(MasterPath)
  else
  begin
    LogWithCorrelation(sllWarning, 'ms.config.master.json not found, serving empty config', [], self);
    MasterJson := '{}';
  end;
  FConfigImpl := TConfigService.Create(MasterJson);
  RegisterService(FConfigImpl, TypeInfo(IConfig));
end;

end.
