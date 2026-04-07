/// <summary>
///   Interface-based service implementation for the Users microservice.
///   Implements the IUser contract via TUserService and hosts it
///   inside TUsersServer (a TMicroService subclass).
/// </summary>
unit ms.users.server;

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
  mormot.core.os,
  mormot.core.text,
  mormot.core.unicode,
  mormot.core.variants,
  mormot.orm.base,
  mormot.orm.core,
  mormot.rest.core,
  mormot.rest.server,
  mormot.rest.sqlite3,
  mormot.soa.core,
  mormot.soa.server,
  ms.shared,
  ms.shared.api,
  ms.shared.service,
  ms.users.model;

type

  /// <summary>
  ///   Implements the IUser interface for author profile CRUD.
  /// </summary>
  TUserService = class(TInterfacedObject, IUser)
  private
    FOrm: IRestOrm;
  public
    constructor Create(const aOrm: IRestOrm);
    function Get(aId: TID): RawJson;
    function GetAll: RawJson;
    function Add(const aData: RawJson): TID;
    function Update(aId: TID; const aData: RawJson): boolean;
    function Remove(aId: TID): boolean;
  end;

  /// <summary>
  ///   Microservice server hosting the IUser service implementation.
  /// </summary>
  TUsersServer = class(TMicroService)
  private
    FUserImpl: TUserService;
  protected
    function CreateModel: TOrmModel; override;
    procedure SetupServices; override;
  end;

implementation

{ TUserService }

constructor TUserService.Create(const aOrm: IRestOrm);
begin
  inherited Create;
  FOrm := aOrm;
end;

function TUserService.Get(aId: TID): RawJson;
var
  Rec: TOrmAuthor;
begin
  Rec := TOrmAuthor.Create;
  try
    if FOrm.Retrieve(aId, Rec) then
      Result := Rec.GetJsonValues(True, True, ooSelect)
    else
      Result := '{}';
  finally
    Rec.Free;
  end;
end;

function TUserService.GetAll: RawJson;
var
  Table: TOrmTable;
begin
  Table := FOrm.MultiFieldValues(TOrmAuthor, '*', '');
  try
    if Table = nil then
      Result := '[]'
    else
      Result := Table.GetJsonValues(True);
  finally
    Table.Free;
  end;
end;

function TUserService.Add(const aData: RawJson): TID;
var
  Doc: TDocVariantData;
  Rec: TOrmAuthor;
begin
  Doc.InitJson(aData, JSON_FAST_FLOAT);
  Rec := TOrmAuthor.Create;
  try
    Rec.DisplayName := Doc.U['DisplayName'];
    Rec.Bio := Doc.U['Bio'];
    Rec.WebsiteUrl := Doc.U['WebsiteUrl'];
    Rec.Slug := TextToSlug(Rec.DisplayName);
    Rec.CreatedAt := NowUtc;
    Rec.UpdatedAt := NowUtc;
    Result := FOrm.Add(Rec, True);
  finally
    Rec.Free;
  end;
end;

function TUserService.Update(aId: TID; const aData: RawJson): boolean;
var
  Doc: TDocVariantData;
  Rec: TOrmAuthor;
begin
  Rec := TOrmAuthor.Create;
  try
    if not FOrm.Retrieve(aId, Rec) then
    begin
      Result := False;
      Exit;
    end;
    Doc.InitJson(aData, JSON_FAST_FLOAT);
    if Doc.GetValueIndex('DisplayName') >= 0 then
    begin
      Rec.DisplayName := Doc.U['DisplayName'];
      Rec.Slug := TextToSlug(Rec.DisplayName);
    end;
    if Doc.GetValueIndex('Bio') >= 0 then
      Rec.Bio := Doc.U['Bio'];
    if Doc.GetValueIndex('WebsiteUrl') >= 0 then
      Rec.WebsiteUrl := Doc.U['WebsiteUrl'];
    if Doc.GetValueIndex('AvatarMediaId') >= 0 then
      Rec.AvatarMediaId := Doc.I['AvatarMediaId'];
    Rec.UpdatedAt := NowUtc;
    Result := FOrm.Update(Rec);
  finally
    Rec.Free;
  end;
end;

function TUserService.Remove(aId: TID): boolean;
begin
  Result := FOrm.Delete(TOrmAuthor, aId);
end;

{ TUsersServer }

function TUsersServer.CreateModel: TOrmModel;
begin
  Result := TOrmModel.Create([TOrmAuthor], 'api');
end;

procedure TUsersServer.SetupServices;
var
  Factory: TServiceFactoryServerAbstract;
begin
  FUserImpl := TUserService.Create(FRestServer.Orm);
  Factory := FRestServer.ServiceRegister(
    FUserImpl, [TypeInfo(IUser)]) ;
  Factory.ByPassAuthentication := True;
  Factory.ResultAsJsonObjectWithoutResult := True;
end;

end.
