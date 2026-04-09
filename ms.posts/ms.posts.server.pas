/// <summary>
///   Interface-based service implementation for the Posts microservice. Implements <c>IPost</c> with CRUD,
///   pagination, and filtering.
///
///   Demonstrates additional mORMot2 patterns beyond basic CRUD:
///   - <c>IRestOrm.MultiFieldValues</c>: returns a <c>TOrmTable</c> (in-memory result set) for paginated queries
///     with custom WHERE clauses, ORDER BY, LIMIT, and OFFSET.
///   - <c>IRestOrm.OneFieldValueInt64</c>: efficient single-value query for aggregate functions like COUNT(*).
///   - <c>FormatUtf8</c>: mORMot2's fast string formatting function, similar to Format but optimized for
///     <c>RawUtf8</c> and safe against SQL injection when used with integer parameters.
///   - Publication state machine: Status field transitions (draft -> published -> archived) with automatic
///     PublishedAt timestamp on first publication.
///
///   See <c>ms.users.server.pas</c> for detailed explanations of the basic CRUD and JSON parsing patterns
///   used here.
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
  strict private
    /// <summary>
    ///   ORM interface used for all database operations on blog posts.
    /// </summary>
    FOrm: IRestOrm;
  public

    /// <summary>
    ///   Creates a new TPostService instance with the given ORM interface.
    /// </summary>
    /// <param name="aOrm">
    ///   The ORM interface to use for persistence operations.
    /// </param>
    constructor Create(
      const aOrm: IRestOrm
      );

    /// <summary>
    ///   Retrieves a single post by its ID.
    /// </summary>
    /// <param name="aId">
    ///   The unique identifier of the post to retrieve.
    /// </param>
    /// <returns>
    ///   JSON representation of the post, or empty JSON object if not found.
    /// </returns>
    function Get(
      aId: TID
      ): RawJson;

    /// <summary>
    ///   Retrieves a single post by its URL slug.
    /// </summary>
    /// <param name="aSlug">
    ///   The URL-friendly slug identifying the post.
    /// </param>
    /// <returns>
    ///   JSON representation of the post, or empty JSON object if not found.
    /// </returns>
    function GetBySlug(
      const aSlug: RawUtf8
      ): RawJson;

    /// <summary>
    ///   Retrieves a paginated, filtered list of posts.
    /// </summary>
    /// <param name="aPage">
    ///   The page number (1-based). Values <= 0 default to 1.
    /// </param>
    /// <param name="aLimit">
    ///   The number of posts per page. Clamped to 1..100, defaults to 10.
    /// </param>
    /// <param name="aStatus">
    ///   Filter by publication status. Values <= 0 mean no filter.
    /// </param>
    /// <param name="aAuthorId">
    ///   Filter by author ID. Values <= 0 mean no filter.
    /// </param>
    /// <returns>
    ///   JSON object with items array, total count, and current page number.
    /// </returns>
    function GetList(
      aPage: integer;
      aLimit: integer;
      aStatus: integer;
      aAuthorId: TID
      ): RawJson;

    /// <summary>
    ///   Creates a new post from JSON data. Returns the new ID.
    /// </summary>
    /// <param name="aData">
    ///   JSON object containing the post fields (Title, Body, Excerpt, AuthorId, etc.).
    /// </param>
    /// <returns>
    ///   The ID of the newly created post, or 0 if the Title was empty.
    /// </returns>
    function Add(
      const aData: RawJson
      ): TID;

    /// <summary>
    ///   Updates an existing post with partial JSON data.
    /// </summary>
    /// <param name="aId">
    ///   The unique identifier of the post to update.
    /// </param>
    /// <param name="aData">
    ///   JSON object containing only the fields to update.
    /// </param>
    /// <returns>
    ///   True if the post was found and updated successfully.
    /// </returns>
    function Update(
      aId: TID;
      const aData: RawJson
      ): boolean;

    /// <summary>
    ///   Deletes a post by its ID.
    /// </summary>
    /// <param name="aId">
    ///   The unique identifier of the post to delete.
    /// </param>
    /// <returns>
    ///   True if the post was deleted successfully.
    /// </returns>
    function Remove(
      aId: TID
      ): boolean;
  end;

  /// <summary>
  ///   Microservice server for blog posts. Registers TPostService as an IPost SOA service.
  /// </summary>
  TPostsServer = class(TMicroService)
  strict private
    /// <summary>
    ///   The TPostService instance registered as IPost service implementation.
    /// </summary>
    FPostImpl: TPostService;
  protected

    /// <summary>
    ///   Creates the ORM model containing TOrmBlogPost.
    /// </summary>
    /// <returns>
    ///   A new TOrmModel configured with the TOrmBlogPost class.
    /// </returns>
    function CreateModel: TOrmModel; override;

    /// <summary>
    ///   Registers the IPost service on the REST server.
    /// </summary>
    procedure SetupServices; override;
  end;

implementation

constructor TPostService.Create(
  const aOrm: IRestOrm
  );
begin
  inherited Create;
  FOrm := aOrm;
end;

function TPostService.Get(
  aId: TID
  ): RawJson;
begin
  Result := OrmGetById(FOrm, TOrmBlogPost, aId);
end;

function TPostService.GetBySlug(
  const aSlug: RawUtf8
  ): RawJson;
var
  PostRecord: TOrmBlogPost;
begin
  PostRecord := TOrmBlogPost.Create;
  try
    if FOrm.Retrieve('Slug=?', [], [aSlug], PostRecord) then
      Result := PostRecord.GetJsonValues(True, True, ooSelect)
    else
      Result := '{}';
  finally
    PostRecord.Free;
  end;
end;

function TPostService.GetList(
  aPage: integer;
  aLimit: integer;
  aStatus: integer;
  aAuthorId: TID
  ): RawJson;
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
    Total := FOrm.OneFieldValueInt64(TOrmBlogPost, 'Count(*)', WhereClause)
  else
    Total := FOrm.TableRowCount(TOrmBlogPost);

  // Retrieve paginated results
  if WhereClause = '' then
    WhereClause := 'RowID>0';
  ResultTable := FOrm.MultiFieldValues(TOrmBlogPost, '*',
    WhereClause + FormatUtf8(' ORDER BY RowID DESC LIMIT % OFFSET %', [aLimit, (aPage - 1) * aLimit]));
  try
    if ResultTable = nil then
      Result := FormatUtf8('{"items":[],"total":%,"page":%}', [Total, aPage])
    else
      Result := FormatUtf8('{"items":%,"total":%,"page":%}', [ResultTable.GetJsonValues(True), Total, aPage]);
  finally
    ResultTable.Free;
  end;
end;

function TPostService.Add(
  const aData: RawJson
  ): TID;
var
  JsonDoc: TDocVariantData;
  PostRecord: TOrmBlogPost;
begin
  JsonDoc.InitJson(aData, JSON_FAST_FLOAT);
  if JsonDoc.U['Title'] = '' then
    Exit(0);
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

function TPostService.Update(
  aId: TID;
  const aData: RawJson
  ): boolean;
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

function TPostService.Remove(
  aId: TID
  ): boolean;
begin
  Result := FOrm.Delete(TOrmBlogPost, aId);
end;

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
