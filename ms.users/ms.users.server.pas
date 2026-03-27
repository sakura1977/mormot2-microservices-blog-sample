/// <summary>
///   HTTP server for the Users service.
///   CRUD endpoints for author profiles.
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
  mormot.db.raw.sqlite3,
  mormot.net.http,
  mormot.net.server,
  mormot.orm.base,
  mormot.orm.core,
  mormot.rest.sqlite3,
  ms.shared,
  ms.shared.service,
  ms.users.model;

type

  /// <summary>
  ///   Microservice server handling user/author profile endpoints.
  /// </summary>
  TUsersServer = class(TMicroService)
  private
    FModel: TOrmModel;
    FRest: TRestServerDB;

    /// <summary>
    ///   Extracts a numeric ID from a URL path after the given prefix.
    /// </summary>
    /// <param name="aPath">
    ///   The full request URL path.
    /// </param>
    /// <param name="aPrefix">
    ///   The URL prefix before the ID segment.
    /// </param>
    /// <returns>
    ///   The extracted ID value, or 0 if parsing fails.
    /// </returns>
    function ExtractId(
      const aPath, aPrefix: RawUtf8
    ): TID;
  protected

    /// <summary>
    ///   Initializes the database and ORM model.
    /// </summary>
    procedure DoInitialize; override;

    /// <summary>
    ///   Releases the REST server and ORM model.
    /// </summary>
    procedure DoFinalize; override;

    /// <summary>
    ///   Dispatches incoming HTTP requests to user endpoints.
    /// </summary>
    /// <param name="aCtxt">
    ///   The HTTP request context.
    /// </param>
    /// <returns>
    ///   The HTTP status code for the response.
    /// </returns>
    function OnRequest(
      aCtxt: THttpServerRequestAbstract
    ): cardinal; override;
  end;

implementation

{ TUsersServer }

procedure TUsersServer.DoFinalize;
begin
  FreeAndNil(FRest);
  FreeAndNil(FModel);
end;

procedure TUsersServer.DoInitialize;
var
  DatabasePath: TFileName;
begin
  DatabasePath := Executable.ProgramFilePath + 'users.db';
  FModel := CreateUsersModel;
  FRest := TRestServerDB.Create(FModel, DatabasePath);
  FRest.DB.Synchronous := smNormal;
  FRest.DB.LockingMode := lmExclusive;
  FRest.CreateMissingTables;
end;

function TUsersServer.ExtractId(
  const aPath, aPrefix: RawUtf8
): TID;
begin
  Result := GetInt64(pointer(Copy(aPath, Length(aPrefix) + 1, 20)));
end;

function TUsersServer.OnRequest(
  aCtxt: THttpServerRequestAbstract
): cardinal;
var
  Path: RawUtf8;
  RecordId, NewId: TID;
  Rec: TOrmAuthor;
  Doc: TDocVariantData;
  Table: TOrmTable;
begin
  Path := aCtxt.Url;

  // GET /api/users
  if (aCtxt.Method = 'GET') and (Path = '/api/users') then
  begin
    Table := FRest.Orm.MultiFieldValues(TOrmAuthor, '*', '');
    try
      if Table = nil then
      begin
        aCtxt.OutContent := '[]';
      end
      else
      begin
        aCtxt.OutContent := Table.GetJsonValues(True);
      end;
    finally
      Table.Free;
    end;
    aCtxt.OutContentType := JSON_CONTENT_TYPE;
    Result := HTTP_SUCCESS;
  end

  // GET /api/users/{id}
  else if (aCtxt.Method = 'GET') and
    IdemPChar(pointer(Path), '/API/USERS/') then
  begin
    RecordId := ExtractId(Path, '/api/users/');
    if RecordId <= 0 then
    begin
      aCtxt.OutContent := '{"error":"invalid id"}';
      aCtxt.OutContentType := JSON_CONTENT_TYPE;
      Result := HTTP_BADREQUEST;
      Exit;
    end;
    Rec := TOrmAuthor.Create;
    try
      if FRest.Orm.Retrieve(RecordId, Rec) then
      begin
        aCtxt.OutContent := Rec.GetJsonValues(True, True, ooSelect);
        aCtxt.OutContentType := JSON_CONTENT_TYPE;
        Result := HTTP_SUCCESS;
      end
      else
      begin
        aCtxt.OutContent := '{"error":"not found"}';
        aCtxt.OutContentType := JSON_CONTENT_TYPE;
        Result := HTTP_NOTFOUND;
      end;
    finally
      Rec.Free;
    end;
  end

  // POST /api/users
  else if (aCtxt.Method = 'POST') and (Path = '/api/users') then
  begin
    Doc.InitJson(aCtxt.InContent, JSON_FAST_FLOAT);
    Rec := TOrmAuthor.Create;
    try
      Rec.DisplayName := Doc.U['DisplayName'];
      Rec.Bio := Doc.U['Bio'];
      Rec.WebsiteUrl := Doc.U['WebsiteUrl'];
      Rec.Slug := TextToSlug(Rec.DisplayName);
      Rec.CreatedAt := NowUtc;
      Rec.UpdatedAt := NowUtc;
      NewId := FRest.Orm.Add(Rec, True);
      if NewId > 0 then
      begin
        aCtxt.OutContent := FormatUtf8('{"id":%}', [NewId]);
        aCtxt.OutContentType := JSON_CONTENT_TYPE;
        Result := HTTP_CREATED;
      end
      else
      begin
        aCtxt.OutContent := '{"error":"creation failed"}';
        aCtxt.OutContentType := JSON_CONTENT_TYPE;
        Result := HTTP_SERVERERROR;
      end;
    finally
      Rec.Free;
    end;
  end

  // PUT /api/users/{id}
  else if (aCtxt.Method = 'PUT') and
    IdemPChar(pointer(Path), '/API/USERS/') then
  begin
    RecordId := ExtractId(Path, '/api/users/');
    Doc.InitJson(aCtxt.InContent, JSON_FAST_FLOAT);
    Rec := TOrmAuthor.Create;
    try
      if not FRest.Orm.Retrieve(RecordId, Rec) then
      begin
        aCtxt.OutContent := '{"error":"not found"}';
        aCtxt.OutContentType := JSON_CONTENT_TYPE;
        Result := HTTP_NOTFOUND;
        Exit;
      end;
      if Doc.GetValueIndex('DisplayName') >= 0 then
      begin
        Rec.DisplayName := Doc.U['DisplayName'];
        Rec.Slug := TextToSlug(Rec.DisplayName);
      end;
      if Doc.GetValueIndex('Bio') >= 0 then
      begin
        Rec.Bio := Doc.U['Bio'];
      end;
      if Doc.GetValueIndex('WebsiteUrl') >= 0 then
      begin
        Rec.WebsiteUrl := Doc.U['WebsiteUrl'];
      end;
      if Doc.GetValueIndex('AvatarMediaId') >= 0 then
      begin
        Rec.AvatarMediaId := Doc.I['AvatarMediaId'];
      end;
      Rec.UpdatedAt := NowUtc;
      if FRest.Orm.Update(Rec) then
      begin
        aCtxt.OutContent := '{"success":true}';
        Result := HTTP_SUCCESS;
      end
      else
      begin
        aCtxt.OutContent := '{"error":"update failed"}';
        Result := HTTP_SERVERERROR;
      end;
      aCtxt.OutContentType := JSON_CONTENT_TYPE;
    finally
      Rec.Free;
    end;
  end

  // DELETE /api/users/{id}
  else if (aCtxt.Method = 'DELETE') and
    IdemPChar(pointer(Path), '/API/USERS/') then
  begin
    RecordId := ExtractId(Path, '/api/users/');
    if FRest.Orm.Delete(TOrmAuthor, RecordId) then
    begin
      aCtxt.OutContent := '{"success":true}';
      Result := HTTP_SUCCESS;
    end
    else
    begin
      aCtxt.OutContent := '{"error":"not found"}';
      Result := HTTP_NOTFOUND;
    end;
    aCtxt.OutContentType := JSON_CONTENT_TYPE;
  end

  // Fallback: health / shutdown
  else
    Result := inherited OnRequest(aCtxt);
end;

end.
