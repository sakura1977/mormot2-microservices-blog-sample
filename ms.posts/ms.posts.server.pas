/// <summary>
///   Interface-based service implementation for the Posts microservice.
///   Implements IPost with CRUD operations, pagination, and filtering.
/// </summary>
unit ms.posts.server;

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
  ms.posts.model,
  ms.shared,
  ms.shared.api,
  ms.shared.service;

type

  /// <summary>
  ///   Implements the IPost service interface using ORM persistence.
  /// </summary>
  TPostService = class(TInterfacedObject, IPost)
  private
    FOrm: IRestOrm;
  public
    constructor Create(const aOrm: IRestOrm);
    /// <summary>
    ///   Retrieves a single post by its ID.
    /// </summary>
    function Get(aId: TID): RawJson;
    /// <summary>
    ///   Retrieves a single post by its URL slug.
    /// </summary>
    function GetBySlug(const aSlug: RawUtf8): RawJson;
    /// <summary>
    ///   Retrieves a paginated, filtered list of posts.
    /// </summary>
    function GetList(aPage, aLimit, aStatus: integer;
      aAuthorId: TID): RawJson;
    /// <summary>
    ///   Creates a new post from JSON data. Returns the new ID.
    /// </summary>
    function Add(const aData: RawJson): TID;
    /// <summary>
    ///   Updates an existing post with partial JSON data.
    /// </summary>
    function Update(aId: TID; const aData: RawJson): boolean;
    /// <summary>
    ///   Deletes a post by its ID.
    /// </summary>
    function Remove(aId: TID): boolean;
  end;

  /// <summary>
  ///   Microservice server for blog posts.
  ///   Registers TPostService as an IPost SOA service.
  /// </summary>
  TPostsServer = class(TMicroService)
  private
    FPostImpl: TPostService;
  protected
    /// <summary>
    ///   Creates the ORM model containing TOrmBlogPost.
    /// </summary>
    function CreateModel: TOrmModel; override;
    /// <summary>
    ///   Registers the IPost service on the REST server.
    /// </summary>
    procedure SetupServices; override;
  end;

implementation

{ TPostService }

constructor TPostService.Create(const aOrm: IRestOrm);
begin
  inherited Create;
  FOrm := aOrm;
end;

function TPostService.Get(aId: TID): RawJson;
begin
  Result := OrmGetById(FOrm, TOrmBlogPost, aId);
end;

function TPostService.GetBySlug(const aSlug: RawUtf8): RawJson;
var
  PostRecord: TOrmBlogPost;
begin
  Result := '';
  PostRecord := TOrmBlogPost.Create;
  try
    if FOrm.Retrieve('Slug=?', [], [aSlug], PostRecord) then
      Result := PostRecord.GetJsonValues(True, True, ooSelect);
  finally
    PostRecord.Free;
  end;
end;

function TPostService.GetList(aPage, aLimit, aStatus: integer;
  aAuthorId: TID): RawJson;
var
  WhereClause: RawUtf8;
  Total: Int64;
  ResultTable: TOrmTable;
begin
  // Clamp page and limit
  if aPage <= 0 then
    aPage := 1;
  if aLimit <= 0 then
    aLimit := 10;
  if aLimit > 100 then
    aLimit := 100;

  // Build WHERE clause from filters
  WhereClause := '';
  if aStatus > 0 then
    WhereClause := FormatUtf8('Status=%', [aStatus]);
  if aAuthorId > 0 then
  begin
    if WhereClause <> '' then
      WhereClause := WhereClause + ' AND ';
    WhereClause := WhereClause + FormatUtf8('AuthorId=%', [aAuthorId]);
  end;

  // Calculate filtered total count
  if WhereClause <> '' then
    Total := FOrm.OneFieldValueInt64(
      TOrmBlogPost, 'Count(*)', WhereClause)
  else
    Total := FOrm.TableRowCount(TOrmBlogPost);

  // Retrieve paginated results
  if WhereClause = '' then
    WhereClause := 'RowID>0';
  ResultTable := FOrm.MultiFieldValues(TOrmBlogPost, '*',
    WhereClause + FormatUtf8(' ORDER BY RowID DESC LIMIT % OFFSET %',
      [aLimit, (aPage - 1) * aLimit]));
  try
    if ResultTable = nil then
      Result := FormatUtf8('{"items":[],"total":%,"page":%}',
        [Total, aPage])
    else
      Result := FormatUtf8('{"items":%,"total":%,"page":%}',
        [ResultTable.GetJsonValues(True), Total, aPage]);
  finally
    ResultTable.Free;
  end;
end;

function TPostService.Add(const aData: RawJson): TID;
var
  JsonDoc: TDocVariantData;
  PostRecord: TOrmBlogPost;
begin
  JsonDoc.InitJson(aData, JSON_FAST_FLOAT);
  PostRecord := TOrmBlogPost.Create;
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
    Result := FOrm.Add(PostRecord, True);
  finally
    PostRecord.Free;
  end;
end;

function TPostService.Update(aId: TID; const aData: RawJson): boolean;
var
  JsonDoc: TDocVariantData;
  PostRecord: TOrmBlogPost;
begin
  Result := False;
  JsonDoc.InitJson(aData, JSON_FAST_FLOAT);
  PostRecord := TOrmBlogPost.Create;
  try
    if not FOrm.Retrieve(aId, PostRecord) then
      Exit;
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
    Result := FOrm.Update(PostRecord);
  finally
    PostRecord.Free;
  end;
end;

function TPostService.Remove(aId: TID): boolean;
begin
  Result := FOrm.Delete(TOrmBlogPost, aId);
end;

{ TPostsServer }

function TPostsServer.CreateModel: TOrmModel;
begin
  Result := TOrmModel.Create([TOrmBlogPost], MODEL_ROOT);
end;

procedure TPostsServer.SetupServices;
begin
  FPostImpl := TPostService.Create(FRestServer.Orm);
  RegisterService(FPostImpl, TypeInfo(IPost));
end;

end.
