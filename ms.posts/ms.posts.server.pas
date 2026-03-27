/// <summary>
///   HTTP server for the Posts service.
///   CRUD operations for blog posts with pagination and filtering.
/// </summary>
unit ms.posts.server;

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
  ms.posts.model,
  ms.shared,
  ms.shared.service;

type

  /// <summary>
  ///   Microservice server handling CRUD for blog posts,
  ///   including pagination, filtering by status and author.
  /// </summary>
  TPostsServer = class(TMicroService)
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

    /// <summary>
    ///   Extracts a slug string from a URL path after a given prefix.
    /// </summary>
    /// <param name="aPath">
    ///   The full request path.
    /// </param>
    /// <param name="aPrefix">
    ///   The prefix to strip before extracting the slug.
    /// </param>
    /// <returns>
    ///   The extracted slug as RawUtf8.
    /// </returns>
    function ExtractSlug(
      const aPath: RawUtf8;
      const aPrefix: RawUtf8
    ): RawUtf8;

    /// <summary>
    ///   Parses the URL into a path and query parameters document.
    /// </summary>
    /// <param name="aUrl">
    ///   The full URL including query string.
    /// </param>
    /// <param name="aPath">
    ///   Receives the path portion without query string.
    /// </param>
    /// <param name="aParams">
    ///   Receives the parsed query parameters as a document variant.
    /// </param>
    procedure ParseQueryParams(
      const aUrl: RawUtf8;
      out aPath: RawUtf8;
      out aParams: TDocVariantData
    );
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

{ TPostsServer }

procedure TPostsServer.DoFinalize;
begin
  FreeAndNil(FRest);
  FreeAndNil(FModel);
end;

procedure TPostsServer.DoInitialize;
var
  DatabasePath: TFileName;
begin
  DatabasePath := Executable.ProgramFilePath + 'posts.db';
  FModel := CreatePostsModel;
  FRest := TRestServerDB.Create(FModel, DatabasePath);
  FRest.DB.Synchronous := smNormal;
  FRest.DB.LockingMode := lmExclusive;
  FRest.CreateMissingTables;
end;

function TPostsServer.ExtractId(
  const aPath: RawUtf8;
  const aPrefix: RawUtf8
): TID;
begin
  Result := GetInt64(pointer(Copy(aPath, Length(aPrefix) + 1, 20)));
end;

function TPostsServer.ExtractSlug(
  const aPath: RawUtf8;
  const aPrefix: RawUtf8
): RawUtf8;
begin
  Result := Copy(aPath, Length(aPrefix) + 1, MaxInt);
end;

function TPostsServer.OnRequest(
  aCtxt: THttpServerRequestAbstract
): cardinal;
var
  Url, Path: RawUtf8;
  Params: TDocVariantData;
  PostId, NewId, AuthorId: TID;
  Page, Limit, Status: integer;
  WhereClause: RawUtf8;
  PostRecord: TOrmPost;
  JsonDoc: TDocVariantData;
  ResultTable: TOrmTable;
  Total: Int64;
begin
  Url := aCtxt.Url;
  ParseQueryParams(Url, Path, Params);

  // --- GET /api/posts ---
  if (aCtxt.Method = 'GET') and (Path = '/api/posts') then
  begin
    Page := GetInteger(pointer(Params.U['page']));
    if Page <= 0 then
      Page := 1;
    Limit := GetInteger(pointer(Params.U['limit']));
    if Limit <= 0 then
      Limit := 10;
    if Limit > 100 then
      Limit := 100;

    // Build WHERE clause
    WhereClause := '';
    if Params.GetValueIndex('status') >= 0 then
    begin
      Status := GetInteger(pointer(Params.U['status']));
      WhereClause := FormatUtf8('Status=%', [Status]);
    end;
    if Params.GetValueIndex('authorId') >= 0 then
    begin
      AuthorId := GetInt64(pointer(Params.U['authorId']));
      if WhereClause <> '' then
        WhereClause := WhereClause + ' AND ';
      WhereClause := WhereClause + FormatUtf8('AuthorId=%', [AuthorId]);
    end;

    // Calculate filtered total count
    if WhereClause <> '' then
    begin
      Total := FRest.Orm.OneFieldValueInt64(
        TOrmPost, 'Count(*)', WhereClause);
    end
    else
    begin
      Total := FRest.Orm.TableRowCount(TOrmPost);
    end;
    if WhereClause = '' then
      WhereClause := 'RowID>0';
    ResultTable := FRest.Orm.MultiFieldValues(TOrmPost, '*',
      WhereClause + FormatUtf8(' ORDER BY RowID DESC LIMIT % OFFSET %',
        [Limit, (Page - 1) * Limit]));
    try
      if ResultTable = nil then
      begin
        aCtxt.OutContent := FormatUtf8(
          '{"items":[],"total":%,"page":%}', [Total, Page]);
      end
      else
      begin
        aCtxt.OutContent := FormatUtf8(
          '{"items":%,"total":%,"page":%}',
          [ResultTable.GetJsonValues(True), Total, Page]);
      end;
    finally
      ResultTable.Free;
    end;
    aCtxt.OutContentType := JSON_CONTENT_TYPE;
    Result := HTTP_SUCCESS;
  end

  // --- GET /api/posts/by-slug/{slug} ---
  else if (aCtxt.Method = 'GET') and
    IdemPChar(pointer(Path), '/API/POSTS/BY-SLUG/') then
  begin
    PostRecord := TOrmPost.Create;
    try
      if FRest.Orm.Retrieve('Slug=?', [],
        [ExtractSlug(Path, '/api/posts/by-slug/')], PostRecord) then
      begin
        aCtxt.OutContent := PostRecord.GetJsonValues(True, True, ooSelect);
        Result := HTTP_SUCCESS;
      end
      else
      begin
        aCtxt.OutContent := '{"error":"not found"}';
        Result := HTTP_NOTFOUND;
      end;
    finally
      PostRecord.Free;
    end;
    aCtxt.OutContentType := JSON_CONTENT_TYPE;
  end

  // --- GET /api/posts/by-author/{authorId} ---
  else if (aCtxt.Method = 'GET') and
    IdemPChar(pointer(Path), '/API/POSTS/BY-AUTHOR/') then
  begin
    AuthorId := ExtractId(Path, '/api/posts/by-author/');
    Page := GetInteger(pointer(Params.U['page']));
    if Page <= 0 then
      Page := 1;
    Limit := GetInteger(pointer(Params.U['limit']));
    if Limit <= 0 then
      Limit := 10;
    ResultTable := FRest.Orm.MultiFieldValues(TOrmPost, '*',
      FormatUtf8('AuthorId=% ORDER BY RowID DESC LIMIT % OFFSET %',
        [AuthorId, Limit, (Page - 1) * Limit]));
    try
      if ResultTable = nil then
      begin
        aCtxt.OutContent := '{"items":[],"total":0,"page":1}';
      end
      else
      begin
        aCtxt.OutContent := FormatUtf8('{"items":%,"total":%,"page":%}',
          [ResultTable.GetJsonValues(True), ResultTable.RowCount, Page]);
      end;
    finally
      ResultTable.Free;
    end;
    aCtxt.OutContentType := JSON_CONTENT_TYPE;
    Result := HTTP_SUCCESS;
  end

  // --- GET /api/posts/{id} ---
  else if (aCtxt.Method = 'GET') and
    IdemPChar(pointer(Path), '/API/POSTS/') then
  begin
    PostId := ExtractId(Path, '/api/posts/');
    PostRecord := TOrmPost.Create;
    try
      if FRest.Orm.Retrieve(PostId, PostRecord) then
      begin
        aCtxt.OutContent := PostRecord.GetJsonValues(True, True, ooSelect);
        Result := HTTP_SUCCESS;
      end
      else
      begin
        aCtxt.OutContent := '{"error":"not found"}';
        Result := HTTP_NOTFOUND;
      end;
    finally
      PostRecord.Free;
    end;
    aCtxt.OutContentType := JSON_CONTENT_TYPE;
  end

  // --- POST /api/posts ---
  else if (aCtxt.Method = 'POST') and (Path = '/api/posts') then
  begin
    JsonDoc.InitJson(aCtxt.InContent, JSON_FAST_FLOAT);
    PostRecord := TOrmPost.Create;
    try
      PostRecord.Title := JsonDoc.U['Title'];
      PostRecord.Slug := TextToSlug(PostRecord.Title);
      PostRecord.Body := JsonDoc.U['Body'];
      PostRecord.Excerpt := JsonDoc.U['Excerpt'];
      PostRecord.AuthorId := JsonDoc.I['AuthorId'];
      PostRecord.FeaturedImageId := JsonDoc.I['FeaturedImageId'];
      PostRecord.MetaTitle := JsonDoc.U['MetaTitle'];
      PostRecord.MetaDescription := JsonDoc.U['MetaDescription'];
      PostRecord.MetaKeywords := JsonDoc.U['MetaKeywords'];
      PostRecord.Status := JsonDoc.I['Status'];
      if PostRecord.Status = POST_STATUS_PUBLISHED then
        PostRecord.PublishedAt := NowUtc;
      PostRecord.CreatedAt := NowUtc;
      PostRecord.UpdatedAt := NowUtc;
      NewId := FRest.Orm.Add(PostRecord, True);
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
      PostRecord.Free;
    end;
    aCtxt.OutContentType := JSON_CONTENT_TYPE;
  end

  // --- PUT /api/posts/{id} ---
  else if (aCtxt.Method = 'PUT') and
    IdemPChar(pointer(Path), '/API/POSTS/') then
  begin
    PostId := ExtractId(Path, '/api/posts/');
    JsonDoc.InitJson(aCtxt.InContent, JSON_FAST_FLOAT);
    PostRecord := TOrmPost.Create;
    try
      if not FRest.Orm.Retrieve(PostId, PostRecord) then
      begin
        aCtxt.OutContent := '{"error":"not found"}';
        aCtxt.OutContentType := JSON_CONTENT_TYPE;
        Result := HTTP_NOTFOUND;
        Exit;
      end;
      if JsonDoc.GetValueIndex('Title') >= 0 then
      begin
        PostRecord.Title := JsonDoc.U['Title'];
        PostRecord.Slug := TextToSlug(PostRecord.Title);
      end;
      if JsonDoc.GetValueIndex('Body') >= 0 then
        PostRecord.Body := JsonDoc.U['Body'];
      if JsonDoc.GetValueIndex('Excerpt') >= 0 then
        PostRecord.Excerpt := JsonDoc.U['Excerpt'];
      if JsonDoc.GetValueIndex('FeaturedImageId') >= 0 then
        PostRecord.FeaturedImageId := JsonDoc.I['FeaturedImageId'];
      if JsonDoc.GetValueIndex('MetaTitle') >= 0 then
        PostRecord.MetaTitle := JsonDoc.U['MetaTitle'];
      if JsonDoc.GetValueIndex('MetaDescription') >= 0 then
        PostRecord.MetaDescription := JsonDoc.U['MetaDescription'];
      if JsonDoc.GetValueIndex('MetaKeywords') >= 0 then
        PostRecord.MetaKeywords := JsonDoc.U['MetaKeywords'];
      if JsonDoc.GetValueIndex('Status') >= 0 then
      begin
        PostRecord.Status := JsonDoc.I['Status'];
        if (PostRecord.Status = POST_STATUS_PUBLISHED) and
           (PostRecord.PublishedAt = 0) then
          PostRecord.PublishedAt := NowUtc;
      end;
      PostRecord.UpdatedAt := NowUtc;
      if FRest.Orm.Update(PostRecord) then
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
      PostRecord.Free;
    end;
    aCtxt.OutContentType := JSON_CONTENT_TYPE;
  end

  // --- DELETE /api/posts/{id} ---
  else if (aCtxt.Method = 'DELETE') and
    IdemPChar(pointer(Path), '/API/POSTS/') then
  begin
    PostId := ExtractId(Path, '/api/posts/');
    if FRest.Orm.Delete(TOrmPost, PostId) then
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

procedure TPostsServer.ParseQueryParams(
  const aUrl: RawUtf8;
  out aPath: RawUtf8;
  out aParams: TDocVariantData
);
var
  QuestionMarkPos: PtrInt;
  QueryString: RawUtf8;
  CurrentPtr: PUtf8Char;
  Key, Value: RawUtf8;
begin
  QuestionMarkPos := PosExChar('?', aUrl);
  if QuestionMarkPos > 0 then
  begin
    aPath := Copy(aUrl, 1, QuestionMarkPos - 1);
    QueryString := Copy(aUrl, QuestionMarkPos + 1, MaxInt);
    aParams.InitObject([], JSON_FAST);
    CurrentPtr := pointer(QueryString);
    while CurrentPtr <> nil do
    begin
      Key := GetNextItem(CurrentPtr, '=');
      Value := GetNextItem(CurrentPtr, '&');
      if Key <> '' then
        aParams.AddValue(Key, Value);
    end;
  end
  else
  begin
    aPath := aUrl;
    aParams.InitObject([], JSON_FAST);
  end;
end;

end.
