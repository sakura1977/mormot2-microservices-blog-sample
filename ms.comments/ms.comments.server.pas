/// <summary>
///   HTTP server for the Comments service.
///   Create, moderate and list comments.
/// </summary>
unit ms.comments.server;

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
  ms.comments.model,
  ms.shared,
  ms.shared.service;

type

  /// <summary>
  ///   Microservice server handling comment endpoints.
  /// </summary>
  TCommentsServer = class(TMicroService)
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
    ///   Dispatches incoming HTTP requests to comment endpoints.
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

{ TCommentsServer }

procedure TCommentsServer.DoFinalize;
begin
  FreeAndNil(FRest);
  FreeAndNil(FModel);
end;

procedure TCommentsServer.DoInitialize;
var
  DatabasePath: TFileName;
begin
  DatabasePath := Executable.ProgramFilePath + 'comments.db';
  FModel := CreateCommentsModel;
  FRest := TRestServerDB.Create(FModel, DatabasePath);
  FRest.DB.Synchronous := smNormal;
  FRest.DB.LockingMode := lmExclusive;
  FRest.CreateMissingTables;
end;

function TCommentsServer.ExtractId(
  const aPath, aPrefix: RawUtf8
): TID;
begin
  Result := GetInt64(pointer(Copy(aPath, Length(aPrefix) + 1, 20)));
end;

function TCommentsServer.OnRequest(
  aCtxt: THttpServerRequestAbstract
): cardinal;
var
  Path: RawUtf8;
  RecordId, PostId, NewId: TID;
  Rec: TOrmComment;
  Doc: TDocVariantData;
  Table: TOrmTable;
  ApprovedCount, PendingCount, TotalCount: Int64;
begin
  Path := aCtxt.Url;

  // GET /api/comments/pending
  if (aCtxt.Method = 'GET') and (Path = '/api/comments/pending') then
  begin
    Table := FRest.Orm.MultiFieldValues(TOrmComment, '*',
      FormatUtf8('Status=%', [COMMENT_STATUS_PENDING]));
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

  // GET /api/comments/count/{postId}
  else if (aCtxt.Method = 'GET') and
    IdemPChar(pointer(Path), '/API/COMMENTS/COUNT/') then
  begin
    PostId := ExtractId(Path, '/api/comments/count/');
    TotalCount := 0;
    ApprovedCount := 0;
    PendingCount := 0;
    FRest.Orm.OneFieldValue(TOrmComment, 'count(*)',
      FormatUtf8('PostId=%', [PostId]), [], [], TotalCount);
    FRest.Orm.OneFieldValue(TOrmComment, 'count(*)',
      FormatUtf8('PostId=% AND Status=%',
        [PostId, COMMENT_STATUS_APPROVED]), [], [], ApprovedCount);
    FRest.Orm.OneFieldValue(TOrmComment, 'count(*)',
      FormatUtf8('PostId=% AND Status=%',
        [PostId, COMMENT_STATUS_PENDING]), [], [], PendingCount);
    aCtxt.OutContent := FormatUtf8(
      '{"total":%,"approved":%,"pending":%}',
      [TotalCount, ApprovedCount, PendingCount]);
    aCtxt.OutContentType := JSON_CONTENT_TYPE;
    Result := HTTP_SUCCESS;
  end

  // GET /api/posts/{postId}/comments
  else if (aCtxt.Method = 'GET') and
    IdemPChar(pointer(Path), '/API/POSTS/') and
    (PosEx('/comments', Path) > 0) then
  begin
    PostId := GetInt64(pointer(
      Copy(Path, 12, PosEx('/comments', Path) - 12)));
    // Default: only approved comments
    Table := FRest.Orm.MultiFieldValues(TOrmComment, '*',
      FormatUtf8('PostId=% AND Status=% ORDER BY RowID ASC',
        [PostId, COMMENT_STATUS_APPROVED]));
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

  // POST /api/posts/{postId}/comments
  else if (aCtxt.Method = 'POST') and
    IdemPChar(pointer(Path), '/API/POSTS/') and
    (PosEx('/comments', Path) > 0) then
  begin
    PostId := GetInt64(pointer(
      Copy(Path, 12, PosEx('/comments', Path) - 12)));
    Doc.InitJson(aCtxt.InContent, JSON_FAST_FLOAT);
    Rec := TOrmComment.Create;
    try
      Rec.PostId := PostId;
      Rec.AuthorName := Doc.U['AuthorName'];
      Rec.AuthorEmail := Doc.U['AuthorEmail'];
      Rec.Body := Doc.U['Body'];
      Rec.Status := COMMENT_STATUS_PENDING;
      Rec.CreatedAt := NowUtc;
      NewId := FRest.Orm.Add(Rec, True);
      if NewId > 0 then
      begin
        aCtxt.OutContent := FormatUtf8(
          '{"id":%,"status":%}', [NewId, COMMENT_STATUS_PENDING]);
        Result := HTTP_CREATED;
      end
      else
      begin
        aCtxt.OutContent := '{"error":"creation failed"}';
        Result := HTTP_SERVERERROR;
      end;
    finally
      Rec.Free;
    end;
    aCtxt.OutContentType := JSON_CONTENT_TYPE;
  end

  // PUT /api/comments/{id}/approve
  else if (aCtxt.Method = 'PUT') and
    IdemPChar(pointer(Path), '/API/COMMENTS/') and
    (PosEx('/approve', Path) > 0) then
  begin
    RecordId := GetInt64(pointer(
      Copy(Path, 15, PosEx('/approve', Path) - 15)));
    Doc.InitJson(aCtxt.InContent, JSON_FAST_FLOAT);
    Rec := TOrmComment.Create;
    try
      if FRest.Orm.Retrieve(RecordId, Rec) then
      begin
        Rec.Status := COMMENT_STATUS_APPROVED;
        Rec.ModeratedBy := Doc.I['ModeratedBy'];
        Rec.ModeratedAt := NowUtc;
        FRest.Orm.Update(Rec, 'Status,ModeratedBy,ModeratedAt');
        aCtxt.OutContent := '{"success":true}';
        Result := HTTP_SUCCESS;
      end
      else
      begin
        aCtxt.OutContent := '{"error":"not found"}';
        Result := HTTP_NOTFOUND;
      end;
    finally
      Rec.Free;
    end;
    aCtxt.OutContentType := JSON_CONTENT_TYPE;
  end

  // PUT /api/comments/{id}/reject
  else if (aCtxt.Method = 'PUT') and
    IdemPChar(pointer(Path), '/API/COMMENTS/') and
    (PosEx('/reject', Path) > 0) then
  begin
    RecordId := GetInt64(pointer(
      Copy(Path, 15, PosEx('/reject', Path) - 15)));
    Doc.InitJson(aCtxt.InContent, JSON_FAST_FLOAT);
    Rec := TOrmComment.Create;
    try
      if FRest.Orm.Retrieve(RecordId, Rec) then
      begin
        Rec.Status := COMMENT_STATUS_REJECTED;
        Rec.ModeratedBy := Doc.I['ModeratedBy'];
        Rec.ModeratedAt := NowUtc;
        FRest.Orm.Update(Rec, 'Status,ModeratedBy,ModeratedAt');
        aCtxt.OutContent := '{"success":true}';
        Result := HTTP_SUCCESS;
      end
      else
      begin
        aCtxt.OutContent := '{"error":"not found"}';
        Result := HTTP_NOTFOUND;
      end;
    finally
      Rec.Free;
    end;
    aCtxt.OutContentType := JSON_CONTENT_TYPE;
  end

  // GET /api/comments/{id}
  else if (aCtxt.Method = 'GET') and
    IdemPChar(pointer(Path), '/API/COMMENTS/') then
  begin
    RecordId := ExtractId(Path, '/api/comments/');
    Rec := TOrmComment.Create;
    try
      if FRest.Orm.Retrieve(RecordId, Rec) then
      begin
        aCtxt.OutContent := Rec.GetJsonValues(True, True, ooSelect);
        Result := HTTP_SUCCESS;
      end
      else
      begin
        aCtxt.OutContent := '{"error":"not found"}';
        Result := HTTP_NOTFOUND;
      end;
    finally
      Rec.Free;
    end;
    aCtxt.OutContentType := JSON_CONTENT_TYPE;
  end

  // DELETE /api/comments/{id}
  else if (aCtxt.Method = 'DELETE') and
    IdemPChar(pointer(Path), '/API/COMMENTS/') then
  begin
    RecordId := ExtractId(Path, '/api/comments/');
    if FRest.Orm.Delete(TOrmComment, RecordId) then
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
