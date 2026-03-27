/// <summary>
///   HTTP server for the Tags service.
///   CRUD for tags and m:n association with posts.
/// </summary>
unit ms.tags.server;

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
  ms.tags.model;

type

  /// <summary>
  ///   Microservice server handling CRUD for tags
  ///   and the many-to-many relationship between posts and tags.
  /// </summary>
  TTagsServer = class(TMicroService)
  private
    FModel: TOrmModel;
    FRest: TRestServerDB;

    /// <summary>
    ///   Extracts a numeric ID from a URL path after a given prefix.
    /// </summary>
    /// <param name="aPath">
    ///   The full request path.
    /// </param>
    /// <param name="aPrefix">
    ///   The prefix to strip before parsing the ID.
    /// </param>
    /// <returns>
    ///   The parsed TID value.
    /// </returns>
    function ExtractId(
      const aPath: RawUtf8;
      const aPrefix: RawUtf8
    ): TID;
  protected

    /// <summary>
    ///   Initializes the ORM model and SQLite database.
    /// </summary>
    procedure DoInitialize; override;

    /// <summary>
    ///   Releases the REST server and ORM model.
    /// </summary>
    procedure DoFinalize; override;

    /// <summary>
    ///   Routes incoming HTTP requests to the appropriate handler.
    /// </summary>
    /// <param name="aCtxt">
    ///   The HTTP server request context.
    /// </param>
    /// <returns>
    ///   The HTTP status code for the response.
    /// </returns>
    function OnRequest(
      aCtxt: THttpServerRequestAbstract
    ): cardinal; override;
  end;

implementation

{ TTagsServer }

procedure TTagsServer.DoFinalize;
begin
  FreeAndNil(FRest);
  FreeAndNil(FModel);
end;

procedure TTagsServer.DoInitialize;
var
  DatabasePath: TFileName;
begin
  DatabasePath := Executable.ProgramFilePath + 'tags.db';
  FModel := CreateTagsModel;
  FRest := TRestServerDB.Create(FModel, DatabasePath);
  FRest.DB.Synchronous := smNormal;
  FRest.DB.LockingMode := lmExclusive;
  FRest.CreateMissingTables;
end;

function TTagsServer.ExtractId(
  const aPath: RawUtf8;
  const aPrefix: RawUtf8
): TID;
begin
  Result := GetInt64(pointer(Copy(aPath, Length(aPrefix) + 1, 20)));
end;

function TTagsServer.OnRequest(
  aCtxt: THttpServerRequestAbstract
): cardinal;
var
  Path: RawUtf8;
  TagId, PostId, CurrentTagId, NewId: TID;
  TagRecord: TOrmTag;
  PostTagRecord: TOrmPostTag;
  JsonDoc: TDocVariantData;
  ResultTable: TOrmTable;
  CurrentIdx: PtrInt;
  TagIdsDoc: TDocVariantData;
  CountValue: Int64;
begin
  Path := aCtxt.Url;

  // --- GET /api/tags ---
  if (aCtxt.Method = 'GET') and (Path = '/api/tags') then
  begin
    ResultTable := FRest.Orm.MultiFieldValues(TOrmTag, '*', '');
    try
      if ResultTable = nil then
      begin
        aCtxt.OutContent := '[]';
      end
      else
      begin
        aCtxt.OutContent := ResultTable.GetJsonValues(True);
      end;
    finally
      ResultTable.Free;
    end;
    aCtxt.OutContentType := JSON_CONTENT_TYPE;
    Result := HTTP_SUCCESS;
  end

  // --- GET /api/tags/{id}/posts ---
  else if (aCtxt.Method = 'GET') and
    IdemPChar(pointer(Path), '/API/TAGS/') and
    (PosEx('/posts', Path) > 0) then
  begin
    // Extract tag ID from /api/tags/{id}/posts
    TagId := GetInt64(pointer(Copy(Path, 11, PosEx('/posts', Path) - 11)));
    ResultTable := FRest.Orm.MultiFieldValues(TOrmPostTag, 'PostId',
      FormatUtf8('TagId=%', [TagId]));
    try
      if ResultTable = nil then
      begin
        aCtxt.OutContent := '[]';
      end
      else
      begin
        aCtxt.OutContent := ResultTable.GetJsonValues(True);
      end;
    finally
      ResultTable.Free;
    end;
    aCtxt.OutContentType := JSON_CONTENT_TYPE;
    Result := HTTP_SUCCESS;
  end

  // --- GET /api/posts/{postId}/tags ---
  else if (aCtxt.Method = 'GET') and
    IdemPChar(pointer(Path), '/API/POSTS/') and
    (PosEx('/tags', Path) > 0) then
  begin
    PostId := GetInt64(pointer(Copy(Path, 12, PosEx('/tags', Path) - 12)));
    // Retrieve PostTag entries for this post
    ResultTable := FRest.Orm.MultiFieldValues(TOrmPostTag, 'TagId',
      FormatUtf8('PostId=%', [PostId]));
    try
      if (ResultTable = nil) or (ResultTable.RowCount = 0) then
      begin
        aCtxt.OutContent := '[]';
      end
      else
      begin
        // Load tag details
        JsonDoc.InitArray([], JSON_FAST);
        for CurrentIdx := 1 to ResultTable.RowCount do
        begin
          CurrentTagId := ResultTable.GetAsInt64(CurrentIdx, 0);
          TagRecord := TOrmTag.Create;
          try
            if FRest.Orm.Retrieve(CurrentTagId, TagRecord) then
              JsonDoc.AddItem(
                _JsonFast(TagRecord.GetJsonValues(True, True, ooSelect)));
          finally
            TagRecord.Free;
          end;
        end;
        aCtxt.OutContent := JsonDoc.ToJson;
      end;
    finally
      ResultTable.Free;
    end;
    aCtxt.OutContentType := JSON_CONTENT_TYPE;
    Result := HTTP_SUCCESS;
  end

  // --- POST /api/posts/{postId}/tags ---
  // --- PUT  /api/posts/{postId}/tags ---
  else if ((aCtxt.Method = 'POST') or (aCtxt.Method = 'PUT')) and
    IdemPChar(pointer(Path), '/API/POSTS/') and
    (PosEx('/tags', Path) > 0) then
  begin
    PostId := GetInt64(pointer(Copy(Path, 12, PosEx('/tags', Path) - 12)));
    JsonDoc.InitJson(aCtxt.InContent, JSON_FAST_FLOAT);

    // On PUT: delete existing associations
    if aCtxt.Method = 'PUT' then
      FRest.Orm.Delete(TOrmPostTag,
        FormatUtf8('PostId=%', [PostId]));

    // Create new associations
    if JsonDoc.GetValueIndex('TagIds') >= 0 then
    begin
      TagIdsDoc := JsonDoc.A['TagIds']^;
      for CurrentIdx := 0 to TagIdsDoc.Count - 1 do
      begin
        CurrentTagId := TagIdsDoc.Values[CurrentIdx];
        // Avoid duplicates
        CountValue := 0;
        FRest.Orm.OneFieldValue(TOrmPostTag, 'count(*)',
          FormatUtf8('PostId=% AND TagId=%', [PostId, CurrentTagId]),
          [], [], CountValue);
        if CountValue = 0 then
        begin
          PostTagRecord := TOrmPostTag.Create;
          try
            PostTagRecord.PostId := PostId;
            PostTagRecord.TagId := CurrentTagId;
            FRest.Orm.Add(PostTagRecord, True);
          finally
            PostTagRecord.Free;
          end;
        end;
      end;
    end;
    aCtxt.OutContent := '{"success":true}';
    aCtxt.OutContentType := JSON_CONTENT_TYPE;
    Result := HTTP_SUCCESS;
  end

  // --- GET /api/tags/{id} ---
  else if (aCtxt.Method = 'GET') and
    IdemPChar(pointer(Path), '/API/TAGS/') then
  begin
    TagId := ExtractId(Path, '/api/tags/');
    TagRecord := TOrmTag.Create;
    try
      if FRest.Orm.Retrieve(TagId, TagRecord) then
      begin
        aCtxt.OutContent := TagRecord.GetJsonValues(True, True, ooSelect);
        Result := HTTP_SUCCESS;
      end
      else
      begin
        aCtxt.OutContent := '{"error":"not found"}';
        Result := HTTP_NOTFOUND;
      end;
    finally
      TagRecord.Free;
    end;
    aCtxt.OutContentType := JSON_CONTENT_TYPE;
  end

  // --- POST /api/tags ---
  else if (aCtxt.Method = 'POST') and (Path = '/api/tags') then
  begin
    JsonDoc.InitJson(aCtxt.InContent, JSON_FAST_FLOAT);
    TagRecord := TOrmTag.Create;
    try
      TagRecord.Name := JsonDoc.U['Name'];
      TagRecord.Slug := TextToSlug(TagRecord.Name);
      TagRecord.Description := JsonDoc.U['Description'];
      TagRecord.CreatedAt := NowUtc;
      NewId := FRest.Orm.Add(TagRecord, True);
      if NewId > 0 then
      begin
        aCtxt.OutContent := FormatUtf8('{"id":%}', [NewId]);
        Result := HTTP_CREATED;
      end
      else
      begin
        aCtxt.OutContent := '{"error":"creation failed"}';
        Result := HTTP_SERVERERROR;
      end;
    finally
      TagRecord.Free;
    end;
    aCtxt.OutContentType := JSON_CONTENT_TYPE;
  end

  // --- PUT /api/tags/{id} ---
  else if (aCtxt.Method = 'PUT') and
    IdemPChar(pointer(Path), '/API/TAGS/') then
  begin
    TagId := ExtractId(Path, '/api/tags/');
    JsonDoc.InitJson(aCtxt.InContent, JSON_FAST_FLOAT);
    TagRecord := TOrmTag.Create;
    try
      if not FRest.Orm.Retrieve(TagId, TagRecord) then
      begin
        aCtxt.OutContent := '{"error":"not found"}';
        aCtxt.OutContentType := JSON_CONTENT_TYPE;
        Result := HTTP_NOTFOUND;
        Exit;
      end;
      if JsonDoc.GetValueIndex('Name') >= 0 then
      begin
        TagRecord.Name := JsonDoc.U['Name'];
        TagRecord.Slug := TextToSlug(TagRecord.Name);
      end;
      if JsonDoc.GetValueIndex('Description') >= 0 then
        TagRecord.Description := JsonDoc.U['Description'];
      if FRest.Orm.Update(TagRecord) then
      begin
        aCtxt.OutContent := '{"success":true}';
        Result := HTTP_SUCCESS;
      end
      else
      begin
        aCtxt.OutContent := '{"error":"update failed"}';
        Result := HTTP_SERVERERROR;
      end;
    finally
      TagRecord.Free;
    end;
    aCtxt.OutContentType := JSON_CONTENT_TYPE;
  end

  // --- DELETE /api/tags/{id} ---
  else if (aCtxt.Method = 'DELETE') and
    IdemPChar(pointer(Path), '/API/TAGS/') then
  begin
    TagId := ExtractId(Path, '/api/tags/');
    // Also delete PostTag associations
    FRest.Orm.Delete(TOrmPostTag, FormatUtf8('TagId=%', [TagId]));
    if FRest.Orm.Delete(TOrmTag, TagId) then
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

  else
    Result := inherited OnRequest(aCtxt);
end;

end.
