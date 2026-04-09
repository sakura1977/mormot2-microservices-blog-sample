/// <summary>
///   Interface-based service implementation for the Users microservice.
///
///   This unit demonstrates the standard mORMot2 microservice pattern:
///   1. A <c>TInterfacedObject</c> descendant implements the SOA interface (<c>IUser</c>), receiving
///      <c>IRestOrm</c> via constructor injection for testability.
///   2. A <c>TMicroService</c> subclass (<c>TUsersServer</c>) wires the ORM model and service together
///      via <c>CreateModel</c> and <c>SetupServices</c>.
///
///   Key mORMot2 patterns demonstrated:
///   - <c>TDocVariantData</c>: flexible JSON parsing without fixed record types. <c>Doc.U['key']</c>
///     reads a UTF-8 string, <c>Doc.I['key']</c> reads an integer.
///   - <c>Doc.GetValueIndex('key') >= 0</c>: checks if a JSON field is present, enabling partial
///     updates (PATCH semantics).
///   - <c>IRestOrm.Add/Retrieve/Update/Delete</c>: the four CRUD operations of mORMot2's ORM,
///     working on TOrm instances.
///   - <c>JSON_FAST_FLOAT</c>: parsing option that enables fast floating-point conversion and returns
///     null for missing keys instead of raising exceptions.
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
  ///   Implements the <c>IUser</c> SOA interface for author profile CRUD. Receives <c>IRestOrm</c> via constructor
  ///   injection, making it testable without HTTP or a running server (see ms.testCases.pas).
  /// </summary>
  TUserService = class(TInterfacedObject, IUser)
  strict private
    /// <summary>
    ///   Injected ORM interface for database operations. <c>IRestOrm</c> is mORMot2's abstraction over the ORM
    ///   engine, providing Add/Retrieve/Update/Delete and query methods.
    /// </summary>
    FOrm: IRestOrm;
  public
    /// <summary>
    ///   Creates the service with an injected ORM interface.
    /// </summary>
    /// <param name="aOrm">
    ///   The ORM interface, typically <c>FRestServer.Orm</c>.
    /// </param>
    constructor Create(
      const aOrm: IRestOrm
      );

    /// <summary>
    ///   Retrieves a single author profile by ID.
    /// </summary>
    /// <param name="aId">
    ///   The author's record ID.
    /// </param>
    /// <returns>
    ///   Author profile data. <c>ID = 0</c> if not found.
    /// </returns>
    function Get(
      aId: TID
      ): TAuthorDto;

    /// <summary>
    ///   Retrieves all author profiles.
    /// </summary>
    /// <returns>
    ///   Array of all author profiles.
    /// </returns>
    function GetAll: TAuthorDtoArray;

    /// <summary>
    ///   Creates a new author profile. Requires <c>DisplayName</c>. Auto-generates the URL slug.
    /// </summary>
    /// <param name="aData">
    ///   Author data with at least <c>DisplayName</c>.
    /// </param>
    /// <returns>
    ///   The new record ID, or 0 if validation failed.
    /// </returns>
    function Add(
      const aData: TAuthorCreateDto
      ): TID;

    /// <summary>
    ///   Partially updates an existing author profile. Only JSON fields present in <c>aData</c> are modified (PATCH
    ///   semantics via <c>GetValueIndex</c> checks).
    /// </summary>
    /// <param name="aId">
    ///   The author's record ID.
    /// </param>
    /// <param name="aData">
    ///   JSON object with fields to update.
    /// </param>
    /// <returns>
    ///   True if the record was found and updated.
    /// </returns>
    function Update(
      aId: TID;
      const aData: RawJson
      ): boolean;

    /// <summary>
    ///   Deletes an author profile by ID.
    /// </summary>
    /// <param name="aId">
    ///   The author's record ID.
    /// </param>
    /// <returns>
    ///   True if the SQL DELETE executed successfully.
    /// </returns>
    function Remove(
      aId: TID
      ): boolean;
  end;

  /// <summary>
  ///   Microservice server hosting the <c>IUser</c> service. Subclasses <c>TMicroService</c> and overrides only two
  ///   methods: <c>CreateModel</c> (defines ORM tables) and <c>SetupServices</c> (registers the SOA implementation).
  /// </summary>
  TUsersServer = class(TMicroService)
  strict private

    /// <summary>
    ///   The user service implementation instance.
    /// </summary>
    FUserImpl: TUserService;
  protected
    /// <summary>
    ///   Creates the ORM model with <c>TOrmAuthor</c>. The <c>MODEL_ROOT</c> parameter ('api') ensures URLs follow
    ///   the /api/User/{Method} pattern.
    /// </summary>
    /// <returns>
    ///   A new <c>TOrmModel</c> instance.
    /// </returns>
    function CreateModel: TOrmModel; override;

    /// <summary>
    ///   Creates <c>TUserService</c> with the ORM interface and registers it as an <c>IUser</c> SOA service.
    /// </summary>
    procedure SetupServices; override;
  end;

implementation

function AuthorToDto(
  aRec: TOrmAuthor
  ): TAuthorDto;
begin
  Result.ID := aRec.IDValue;
  Result.DisplayName := aRec.DisplayName;
  Result.Slug := aRec.Slug;
  Result.Bio := aRec.Bio;
  Result.WebsiteUrl := aRec.WebsiteUrl;
  Result.AvatarMediaId := aRec.AvatarMediaId;
  Result.CreatedAt := aRec.CreatedAt;
  Result.UpdatedAt := aRec.UpdatedAt;
end;

function TUserService.Add(
  const aData: TAuthorCreateDto
  ): TID;
var
  Rec: TOrmAuthor;
begin
  if aData.DisplayName = '' then
    Exit(0);
  Rec := TOrmAuthor.Create;
  try
    Rec.DisplayName := aData.DisplayName;
    Rec.Bio := aData.Bio;
    Rec.WebsiteUrl := aData.WebsiteUrl;
    Rec.Slug := TextToSlug(Rec.DisplayName);
    Rec.CreatedAt := NowUtc;
    Rec.UpdatedAt := NowUtc;
    Result := FOrm.Add(Rec, True);
  finally
    Rec.Free;
  end;
end;

constructor TUserService.Create(
  const aOrm: IRestOrm
  );
begin
  inherited Create;
  FOrm := aOrm;
end;

function TUserService.Get(
  aId: TID
  ): TAuthorDto;
var
  Rec: TOrmAuthor;
begin
  Finalize(Result);
  FillCharFast(Result, SizeOf(Result), 0);
  Rec := TOrmAuthor.Create;
  try
    if FOrm.Retrieve(aId, Rec) then
      Result := AuthorToDto(Rec);
  finally
    Rec.Free;
  end;
end;

function TUserService.GetAll: TAuthorDtoArray;
var
  Rec: TOrmAuthor;
  Count: PtrInt;
begin
  Result := nil;
  Count := 0;
  Rec := TOrmAuthor.CreateAndFillPrepare(FOrm, '', []);
  try
    SetLength(Result, Rec.FillTable.RowCount);
    while Rec.FillOne do
    begin
      Result[Count] := AuthorToDto(Rec);
      Inc(Count);
    end;
    SetLength(Result, Count);
  finally
    Rec.Free;
  end;
end;

function TUserService.Remove(
  aId: TID
  ): boolean;
begin
  Result := FOrm.Delete(TOrmAuthor, aId);
end;

function TUserService.Update(
  aId: TID;
  const aData: RawJson
  ): boolean;
var
  Doc: TDocVariantData;
  Rec: TOrmAuthor;
begin
  Rec := TOrmAuthor.Create;
  try
    if not FOrm.Retrieve(aId, Rec) then
      Exit(False);
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

function TUsersServer.CreateModel: TOrmModel;
begin
  Result := TOrmModel.Create([TOrmAuthor], MODEL_ROOT);
end;

procedure TUsersServer.SetupServices;
begin
  FUserImpl := TUserService.Create(FRestServer.Orm);
  RegisterService(FUserImpl, TypeInfo(IUser));
end;

end.
