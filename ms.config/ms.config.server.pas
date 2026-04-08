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
  ms.shared.service;

type

  /// <summary>
  ///   Implements <c>IConfig</c> by serving configuration from an in-memory <c>TDocVariantData</c> loaded from the master
  ///   JSON file. No database is needed.
  /// </summary>
  TConfigService = class(TInterfacedObject, IConfig)
  strict private
    /// <summary>
    ///   Parsed master configuration holding all service blocks.
    /// </summary>
    FMasterDoc: TDocVariantData;
  public

    /// <summary>
    ///   Creates the config service and parses the master JSON.
    /// </summary>
    /// <param name="aMasterJson">
    ///   Complete master configuration as a JSON object keyed by service name.
    /// </param>
    constructor Create(
      const aMasterJson: RawUtf8
      );

    /// <summary>
    ///   Returns the configuration for a specific service.
    /// </summary>
    /// <param name="aServiceName">
    ///   Service identifier (e.g. 'ms.auth').
    /// </param>
    /// <returns>
    ///   JSON object with all config fields, or '{}' if the service name is unknown.
    /// </returns>
    function GetServiceConfig(
      const aServiceName: RawUtf8
      ): RawJson;

    /// <summary>
    ///   Returns the complete configuration for all services.
    /// </summary>
    /// <returns>
    ///   JSON object keyed by service name.
    /// </returns>
    function GetAllConfigs: RawJson;

    /// <summary>
    ///   Returns the service registry containing only Host and Port per service. Secrets and database paths are excluded.
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

constructor TConfigService.Create(
  const aMasterJson: RawUtf8
  );
begin
  inherited Create;
  FMasterDoc.InitJson(aMasterJson, JSON_FAST_FLOAT);
  if FMasterDoc.Kind <> dvObject then
    FMasterDoc.InitObject([], JSON_FAST);
end;

function TConfigService.GetAllConfigs: RawJson;
begin
  Result := FMasterDoc.ToJson;
end;

function TConfigService.GetServiceConfig(
  const aServiceName: RawUtf8
  ): RawJson;
var
  ValueIdx: PtrInt;
begin
  ValueIdx := FMasterDoc.GetValueIndex(aServiceName);
  if ValueIdx < 0 then
    Exit('{}');
  Result := VariantToUtf8(FMasterDoc.Values[ValueIdx]);
end;

function TConfigService.GetServiceRegistry: RawJson;
var
  Registry, Entry: TDocVariantData;
  ServiceIdx: PtrInt;
  ServiceDoc: PDocVariantData;
begin
  Registry.InitObject([], JSON_FAST);
  for ServiceIdx := 0 to FMasterDoc.Count - 1 do
  begin
    ServiceDoc := _Safe(FMasterDoc.Values[ServiceIdx]);
    if ServiceDoc^.Kind = dvObject then
    begin
      Entry.InitObject([
        'Host', ServiceDoc^.U['Host'],
        'Port', ServiceDoc^.U['Port']
      ], JSON_FAST);
      Registry.AddValue(FMasterDoc.Names[ServiceIdx], variant(Entry));
    end;
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
    TSynLog.Add.Log(sllWarning, 'ms.config.master.json not found, serving empty config', self);
    MasterJson := '{}';
  end;
  FConfigImpl := TConfigService.Create(MasterJson);
  RegisterService(FConfigImpl, TypeInfo(IConfig));
end;

end.
