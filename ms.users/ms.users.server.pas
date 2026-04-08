/// <summary>
///   Interface-based service implementation for the Users microservice.
///
///   This unit demonstrates the standard mORMot2 microservice pattern:
///   1. A <c>TInterfacedObject</c> descendant implements the SOA
///      interface (<c>IUser</c>), receiving <c>IRestOrm</c> via
///      constructor injection for testability.
///   2. A <c>TMicroService</c> subclass (<c>TUsersServer</c>) wires
///      the ORM model and service together via <c>CreateModel</c>
///      and <c>SetupServices</c>.
///
///   Key mORMot2 patterns demonstrated:
///   - <c>TDocVariantData</c>: flexible JSON parsing without fixed
///     record types. <c>Doc.U['key']</c> reads a UTF-8 string,
///     <c>Doc.I['key']</c> reads an integer.
///   - <c>Doc.GetValueIndex('key') >= 0</c>: checks if a JSON
///     field is present, enabling partial updates (PATCH semantics).
///   - <c>IRestOrm.Add/Retrieve/Update/Delete</c>: the four CRUD
///     operations of mORMot2's ORM, working on TOrm instances.
///   - <c>JSON_FAST_FLOAT</c>: parsing option that enables fast
///     floating-point conversion and returns null for missing keys
///     instead of raising exceptions.
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
  ///   Implements the <c>IUser</c> SOA interface for author profile CRUD.
  ///   Receives <c>IRestOrm</c> via constructor injection, making it
  ///   testable without HTTP or a running server (see ms.testCases.pas).
  /// </summary>
  TUserService = class(TInterfacedObject, IUser)
  private
    /// <summary>
    ///   Injected ORM interface for database operations.
    ///   <c>IRestOrm</c> is mORMot2's abstraction over the ORM engine,
    ///   providing Add/Retrieve/Update/Delete and query methods.
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
    ///   JSON object with author data, or '{}' if not found.
    /// </returns>
    function Get(
      aId: TID
      ): RawJson;

    /// <summary>
    ///   Retrieves all author profiles.
    /// </summary>
    /// <returns>
    ///   JSON array of author objects.
    /// </returns>
    function GetAll: RawJson;

    /// <summary>
    ///   Creates a new author profile from JSON data.
    ///   Requires <c>DisplayName</c>. Auto-generates the URL slug.
    /// </summary>
    /// <param name="aData">
    ///   JSON object with author fields.
    /// </param>
    /// <returns>
    ///   The new record ID, or 0 if validation failed.
    /// </returns>
    function Add(
      const aData: RawJson
      ): TID;

    /// <summary>
    ///   Partially updates an existing author profile.
    ///   Only JSON fields present in <c>aData</c> are modified
    ///   (PATCH semantics via <c>GetValueIndex</c> checks).
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
  ///   Microservice server hosting the <c>IUser</c> service.
  ///   Subclasses <c>TMicroService</c> and overrides only two
  ///   methods: <c>CreateModel</c> (defines ORM tables) and
  ///   <c>SetupServices</c> (registers the SOA implementation).
  /// </summary>
  TUsersServer = class(TMicroService)
  private
    FUserImpl: TUserService;
  protected
    /// <summary>
    ///   Creates the ORM model with <c>TOrmAuthor</c>.
    ///   The <c>MODEL_ROOT</c> parameter ('api') ensures URLs
    ///   follow the /api/User/{Method} pattern.
    /// </summary>
    /// <returns>
    ///   A new <c>TOrmModel</c> instance.
    /// </returns>
    function CreateModel: TOrmModel; override;

    /// <summary>
    ///   Creates <c>TUserService</c> with the ORM interface
    ///   and registers it as an <c>IUser</c> SOA service.
    /// </summary>
    procedure SetupServices; override;
  end;

implementation

{ TUserService }

constructor TUserService.Create(
  const aOrm: IRestOrm
  );
begin
  inherited Create;
  FOrm := aOrm;
end;

function TUserService.Get(
  aId: TID
  ): RawJson;
begin
  // OrmGetById is a shared helper (ms.shared.service.pas) that
  // encapsulates the Retrieve + GetJsonValues pattern.
  Result := OrmGetById(FOrm, TOrmAuthor, aId);
end;

function TUserService.GetAll: RawJson;
begin
  // OrmGetAll wraps MultiFieldValues + GetJsonValues.
  // Pass an empty WHERE clause to retrieve all records.
  Result := OrmGetAll(FOrm, TOrmAuthor);
end;

function TUserService.Add(
  const aData: RawJson
  ): TID;
var
  Doc: TDocVariantData;
  Rec: TOrmAuthor;
begin
  // TDocVariantData is mORMot2's Swiss-army-knife for JSON.
  // InitJson parses the JSON string into a variant object.
  // JSON_FAST_FLOAT enables fast number parsing and returns
  // empty/zero for missing keys instead of raising exceptions.
  Doc.InitJson(aData, JSON_FAST_FLOAT);
  // Validate required fields before touching the database
  if Doc.U['DisplayName'] = '' then
    Exit(0);
  Rec := TOrmAuthor.Create;
  try
    // Doc.U['key'] reads a RawUtf8 value from the parsed JSON.
    // Doc.I['key'] reads an Int64 value.
    Rec.DisplayName := Doc.U['DisplayName'];
    Rec.Bio := Doc.U['Bio'];
    Rec.WebsiteUrl := Doc.U['WebsiteUrl'];
    Rec.Slug := TextToSlug(Rec.DisplayName);
    Rec.CreatedAt := NowUtc;
    Rec.UpdatedAt := NowUtc;
    // IRestOrm.Add inserts the record into SQLite.
    // The True parameter means "send all fields including ID=0"
    // which lets SQLite auto-assign the RowID.
    // Returns the new RowID on success, 0 on failure.
    Result := FOrm.Add(Rec, True);
  finally
    Rec.Free;
  end;
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
    // First retrieve the existing record so we can apply
    // partial updates (only modify fields present in the JSON).
    if not FOrm.Retrieve(aId, Rec) then
      Exit(False);
    Doc.InitJson(aData, JSON_FAST_FLOAT);
    // GetValueIndex returns -1 if the key doesn't exist in the JSON.
    // This implements PATCH semantics: only update fields that the
    // client explicitly included in the request.
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
    // IRestOrm.Update writes all fields back to SQLite.
    Result := FOrm.Update(Rec);
  finally
    Rec.Free;
  end;
end;

function TUserService.Remove(
  aId: TID
  ): boolean;
begin
  // IRestOrm.Delete executes DELETE FROM Author WHERE RowID=aId.
  // Returns True even if no row matched (SQLite behavior).
  Result := FOrm.Delete(TOrmAuthor, aId);
end;

{ TUsersServer }

function TUsersServer.CreateModel: TOrmModel;
begin
  // TOrmModel.Create takes an array of TOrm classes that define
  // the SQLite tables for this service. MODEL_ROOT ('api') sets
  // the URL prefix for all endpoints.
  Result := TOrmModel.Create([TOrmAuthor], MODEL_ROOT);
end;

procedure TUsersServer.SetupServices;
begin
  // Inject the ORM interface into the service implementation.
  // FRestServer.Orm returns the IRestOrm interface of the REST server.
  FUserImpl := TUserService.Create(FRestServer.Orm);
  // RegisterService (from TMicroService base class) registers the
  // implementation as an IUser SOA service with standard settings.
  RegisterService(FUserImpl, TypeInfo(IUser));
end;

end.
