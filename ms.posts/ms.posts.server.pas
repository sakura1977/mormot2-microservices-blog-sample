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
  mormot.core.log,
  mormot.core.os,
  mormot.core.rtti,
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

    /// <summary>
    ///   Inserts or updates the FTS5 row that shadows a <c>TOrmBlogPost</c>. The FTS row uses
    ///   the same <c>RowID</c> as the backing post, so retrieve tells us whether to insert or
    ///   update. Must be called inside a transaction together with the post write.
    /// </summary>
    /// <param name="aId">
    ///   The post's record ID. The FTS row will carry the same ID.
    /// </param>
    /// <param name="aTitle">
    ///   Title text to index.
    /// </param>
    /// <param name="aExcerpt">
    ///   Excerpt text to index.
    /// </param>
    /// <param name="aBody">
    ///   Body text to index.
    /// </param>
    procedure UpsertFts(
      aId: TID;
      const aTitle, aExcerpt, aBody: RawUtf8
      );
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
    ///   Post data. <c>ID = 0</c> if not found.
    /// </returns>
    function Get(
      aId: TID
      ): TPostDto;

    /// <summary>
    ///   Retrieves a single post by its URL slug.
    /// </summary>
    /// <param name="aSlug">
    ///   The URL-friendly slug identifying the post.
    /// </param>
    /// <returns>
    ///   Post data. <c>ID = 0</c> if not found.
    /// </returns>
    function GetBySlug(
      const aSlug: RawUtf8
      ): TPostDto;

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
    ///   Paginated result with items array, total count, and current page.
    /// </returns>
    function GetList(
      aPage: integer;
      aLimit: integer;
      aStatus: integer;
      aAuthorId: TID
      ): TPostListDto;

    /// <summary>
    ///   Creates a new post. Returns the new ID.
    /// </summary>
    /// <param name="aData">
    ///   Post data with at least <c>Title</c> (required).
    /// </param>
    /// <returns>
    ///   The ID of the newly created post, or 0 if the Title was empty.
    /// </returns>
    function Add(
      const aData: TPostCreateDto
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
    ///   Deletes a post by its ID. Also deletes the matching row in the FTS5 virtual table.
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

    /// <summary>
    ///   Full-text search across Title, Excerpt and Body via the parallel FTS5 virtual table.
    ///   Only published posts are returned, ordered by <c>PublishedAt</c> descending.
    /// </summary>
    /// <param name="aText">
    ///   Free-text search expression. The input is tokenised into word-only tokens and each
    ///   token is emitted as an FTS5 phrase literal (<c>"word"</c>), so punctuation, quotes and
    ///   boolean-operator words like <c>OR</c> are treated as plain text. Multiple tokens are
    ///   joined with space, which FTS5 interprets as implicit AND.
    /// </param>
    /// <param name="aLimit">
    ///   Maximum rows to return. Clamped to 1..100 (default 20 on out-of-range input).
    /// </param>
    /// <returns>
    ///   Matching posts. Empty array if the expression is empty or nothing matches.
    /// </returns>
    function Search(
      const aText: RawUtf8;
      aLimit: integer
      ): TPostDtoArray;
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

    /// <summary>
    ///   Iterates every <c>TOrmBlogPost</c> row once and inserts a matching <c>TOrmBlogPostFts</c>
    ///   row, sharing the post's <c>RowID</c>. Called on startup when the FTS table is empty but
    ///   the post table is not -- for example after pulling this change on an existing dev DB.
    ///   The whole pass runs inside one transaction so a crash mid-backfill leaves the database
    ///   in a well-defined state.
    /// </summary>
    procedure BackfillFtsIndex;
  protected

    /// <summary>
    ///   Creates the ORM model containing <c>TOrmBlogPost</c> and the parallel <c>TOrmBlogPostFts</c>
    ///   virtual table used for full-text search.
    /// </summary>
    /// <returns>
    ///   A new TOrmModel configured with both classes.
    /// </returns>
    function CreateModel: TOrmModel; override;

    /// <summary>
    ///   Registers the IPost service on the REST server and backfills the FTS5 index if needed.
    /// </summary>
    procedure SetupServices; override;
  end;

implementation

// Turns a free-text search expression into a whitespace-separated list of quoted FTS5 phrase
// tokens. Example: the user types   foo' OR 1=1 --   and this returns   "foo" "OR" "1" "1"  .
//
// Why this is necessary: the SQL literal is already protected by QuotedStr, but the *contents*
// of the MATCH expression must still be valid FTS5 query syntax. FTS5 treats ' ( ) * : ^ and the
// bare words AND / OR / NOT as operators, so passing raw user text through unfiltered crashes
// the query parser on anything fancier than plain ASCII words. Wrapping every token in double
// quotes makes FTS5 treat it as a literal phrase, which is exactly the search UX we want.
//
// The tokeniser recognises ASCII letters, digits, underscore and any non-ASCII byte as "word"
// characters. Everything else is a separator. Non-ASCII bytes are kept intact so German umlauts
// and other Unicode letters continue to match. Empty tokens are dropped.
function SanitizeFtsQuery(
  const aText: RawUtf8
  ): RawUtf8;
var
  ReadIdx: PtrInt;
  StartIdx: PtrInt;
  CurrentChar: AnsiChar;
  TokenText: RawUtf8;

  function IsWordChar(
    aChar: AnsiChar
    ): boolean; inline;
  begin
    Result :=
      (aChar in ['a'..'z', 'A'..'Z', '0'..'9', '_'])
      or (byte(aChar) >= 128);
  end;

begin
  Result := '';
  ReadIdx := 1;
  while ReadIdx <= Length(aText) do
  begin
    // Skip separators.
    while ReadIdx <= Length(aText) do
    begin
      CurrentChar := aText[ReadIdx];
      if IsWordChar(CurrentChar) then
        break;
      Inc(ReadIdx);
    end;
    if ReadIdx > Length(aText) then
      break;
    // Scan one token.
    StartIdx := ReadIdx;
    while ReadIdx <= Length(aText) do
    begin
      CurrentChar := aText[ReadIdx];
      if not IsWordChar(CurrentChar) then
        break;
      Inc(ReadIdx);
    end;
    TokenText := Copy(aText, StartIdx, ReadIdx - StartIdx);
    if TokenText = '' then
      continue;
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + '"' + TokenText + '"';
  end;
end;

function PostToDto(
  aRec: TOrmBlogPost
  ): TPostDto;
begin
  Result.ID := aRec.IDValue;
  Result.Title := aRec.Title;
  Result.Slug := aRec.Slug;
  Result.Body := aRec.Body;
  Result.Excerpt := aRec.Excerpt;
  Result.AuthorId := aRec.AuthorId;
  Result.FeaturedImageId := aRec.FeaturedImageId;
  Result.MetaTitle := aRec.MetaTitle;
  Result.MetaDescription := aRec.MetaDescription;
  Result.MetaKeywords := aRec.MetaKeywords;
  Result.Status := aRec.Status;
  Result.PublishedAt := aRec.PublishedAt;
  Result.CreatedAt := aRec.CreatedAt;
  Result.UpdatedAt := aRec.UpdatedAt;
end;

constructor TPostService.Create(
  const aOrm: IRestOrm
  );
begin
  inherited Create;
  FOrm := aOrm;
end;

function TPostService.Get(
  aId: TID
  ): TPostDto;
var
  Rec: TOrmBlogPost;
begin
  Finalize(Result);
  FillCharFast(Result, SizeOf(Result), 0);
  Rec := TOrmBlogPost.Create;
  try
    if FOrm.Retrieve(aId, Rec) then
      Result := PostToDto(Rec);
  finally
    Rec.Free;
  end;
end;

function TPostService.GetBySlug(
  const aSlug: RawUtf8
  ): TPostDto;
var
  Rec: TOrmBlogPost;
begin
  Finalize(Result);
  FillCharFast(Result, SizeOf(Result), 0);
  Rec := TOrmBlogPost.Create;
  try
    if FOrm.Retrieve('Slug=?', [], [aSlug], Rec) then
      Result := PostToDto(Rec);
  finally
    Rec.Free;
  end;
end;

function TPostService.GetList(
  aPage: integer;
  aLimit: integer;
  aStatus: integer;
  aAuthorId: TID
  ): TPostListDto;
var
  WhereClause: RawUtf8;
  Rec: TOrmBlogPost;
  Count: PtrInt;
begin
  Finalize(Result);
  FillCharFast(Result, SizeOf(Result), 0);
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
    Result.Total := FOrm.OneFieldValueInt64(TOrmBlogPost, 'Count(*)', WhereClause)
  else
    Result.Total := FOrm.TableRowCount(TOrmBlogPost);
  Result.Page := aPage;
  // Retrieve paginated results
  if WhereClause = '' then
    WhereClause := 'RowID>0';
  Count := 0;
  Rec := TOrmBlogPost.CreateAndFillPrepare(FOrm,
    WhereClause + FormatUtf8(' ORDER BY RowID DESC LIMIT % OFFSET %', [aLimit, (aPage - 1) * aLimit]));
  try
    SetLength(Result.Items, Rec.FillTable.RowCount);
    while Rec.FillOne do
    begin
      Result.Items[Count] := PostToDto(Rec);
      Inc(Count);
    end;
    SetLength(Result.Items, Count);
  finally
    Rec.Free;
  end;
end;

function TPostService.Add(
  const aData: TPostCreateDto
  ): TID;
var
  PostRecord: TOrmBlogPost;
begin
  if aData.Title = '' then
    Exit(0);
  // One transaction keeps the post row and its FTS5 shadow in sync: if either write fails the
  // search index and the canonical table cannot drift apart.
  FOrm.TransactionBegin(TOrmBlogPost);
  try
    PostRecord := TOrmBlogPost.Create;
    try
      PostRecord.Title := aData.Title;
      PostRecord.Slug := TextToSlug(PostRecord.Title);
      PostRecord.Body := aData.Body;
      PostRecord.Excerpt := aData.Excerpt;
      PostRecord.AuthorId := aData.AuthorId;
      PostRecord.FeaturedImageId := aData.FeaturedImageId;
      PostRecord.MetaTitle := aData.MetaTitle;
      PostRecord.MetaDescription := aData.MetaDescription;
      PostRecord.MetaKeywords := aData.MetaKeywords;
      PostRecord.Status := aData.Status;
      if PostRecord.Status = POST_STATUS_PUBLISHED then
        PostRecord.PublishedAt := NowUtc;
      PostRecord.CreatedAt := NowUtc;
      PostRecord.UpdatedAt := NowUtc;
      Result := FOrm.Add(PostRecord, True);
    finally
      PostRecord.Free;
    end;
    if Result > 0 then
      UpsertFts(Result, aData.Title, aData.Excerpt, aData.Body);
    FOrm.Commit;
  except
    FOrm.RollBack;
    raise;
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
  // Same transactional rationale as Add: the post row and its FTS5 shadow must move together.
  FOrm.TransactionBegin(TOrmBlogPost);
  try
    PostRecord := TOrmBlogPost.Create;
    try
      if not FOrm.Retrieve(aId, PostRecord) then
      begin
        FOrm.RollBack;
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
      Result := FOrm.Update(PostRecord);
      if Result then
        UpsertFts(aId, PostRecord.Title, PostRecord.Excerpt, PostRecord.Body);
    finally
      PostRecord.Free;
    end;
    FOrm.Commit;
  except
    FOrm.RollBack;
    raise;
  end;
end;

function TPostService.Remove(
  aId: TID
  ): boolean;
begin
  // Drop both the post row and its FTS5 shadow in the same transaction. If the post does not
  // exist, the post delete returns False and we still roll back -- leaving nothing behind.
  FOrm.TransactionBegin(TOrmBlogPost);
  try
    Result := FOrm.Delete(TOrmBlogPost, aId);
    if Result then
      FOrm.Delete(TOrmBlogPostFts, aId);
    FOrm.Commit;
  except
    FOrm.RollBack;
    raise;
  end;
end;

function TPostService.Search(
  const aText: RawUtf8;
  aLimit: integer
  ): TPostDtoArray;
var
  SanitisedQuery: RawUtf8;
  WhereClause: RawUtf8;
  Rec: TOrmBlogPost;
  Count: PtrInt;
begin
  Result := nil;
  if aText = '' then
    Exit;
  // Reduce the free-text input to a safe FTS5 expression. If nothing survives the tokenisation
  // (e.g. the caller typed only punctuation) we short-circuit with an empty result instead of
  // handing FTS5 an empty MATCH, which would raise.
  SanitisedQuery := SanitizeFtsQuery(aText);
  if SanitisedQuery = '' then
    Exit;
  if aLimit <= 0 then
    aLimit := 20;
  if aLimit > 100 then
    aLimit := 100;
  // Join the canonical table to the FTS5 virtual table by RowID. The SanitisedQuery contains only
  // word characters inside quoted phrases, so passing it through QuotedStr protects the outer SQL
  // literal while the FTS5 parser sees a well-formed expression. Only published posts are returned
  // so drafts never leak via search.
  WhereClause := FormatUtf8(
    'RowID IN (SELECT RowID FROM BlogPostFts WHERE BlogPostFts MATCH % LIMIT %) ' +
    'AND Status=% ORDER BY PublishedAt DESC',
    [QuotedStr(SanitisedQuery), aLimit, POST_STATUS_PUBLISHED]);
  Count := 0;
  Rec := TOrmBlogPost.CreateAndFillPrepare(FOrm, WhereClause);
  try
    SetLength(Result, Rec.FillTable.RowCount);
    while Rec.FillOne do
    begin
      Result[Count] := PostToDto(Rec);
      Inc(Count);
    end;
    SetLength(Result, Count);
  finally
    Rec.Free;
  end;
end;

procedure TPostService.UpsertFts(
  aId: TID;
  const aTitle, aExcerpt, aBody: RawUtf8
  );
var
  Fts: TOrmBlogPostFts;
  AlreadyExists: boolean;
begin
  Fts := TOrmBlogPostFts.Create;
  try
    // Retrieve overwrites our fields with whatever the DB has; we reset them immediately below
    // so the Add/Update path sees the freshly supplied text regardless of the previous row.
    AlreadyExists := FOrm.Retrieve(aId, Fts);
    Fts.IDValue := aId;
    Fts.Title := aTitle;
    Fts.Excerpt := aExcerpt;
    Fts.Body := aBody;
    if AlreadyExists then
      FOrm.Update(Fts)
    else
      FOrm.Add(Fts, True, True);
  finally
    Fts.Free;
  end;
end;

procedure TPostsServer.BackfillFtsIndex;
var
  PostRec: TOrmBlogPost;
  FtsRec: TOrmBlogPostFts;
  Indexed: PtrInt;
begin
  Indexed := 0;
  FRestServer.Orm.TransactionBegin(TOrmBlogPost);
  try
    PostRec := TOrmBlogPost.CreateAndFillPrepare(FRestServer.Orm, '');
    try
      while PostRec.FillOne do
      begin
        FtsRec := TOrmBlogPostFts.Create;
        try
          FtsRec.IDValue := PostRec.IDValue;
          FtsRec.Title := PostRec.Title;
          FtsRec.Excerpt := PostRec.Excerpt;
          FtsRec.Body := PostRec.Body;
          FRestServer.Orm.Add(FtsRec, True, True);
          Inc(Indexed);
        finally
          FtsRec.Free;
        end;
      end;
    finally
      PostRec.Free;
    end;
    FRestServer.Orm.Commit;
    TSynLog.Add.Log(sllInfo, '% FTS backfill indexed % post(s)', [ServiceName, Indexed], self);
  except
    FRestServer.Orm.RollBack;
    raise;
  end;
end;

function TPostsServer.CreateModel: TOrmModel;
begin
  Result := TOrmModel.Create([TOrmBlogPost, TOrmBlogPostFts], MODEL_ROOT);
end;

procedure TPostsServer.SetupServices;
var
  PostCount: Int64;
  FtsCount: Int64;
begin
  FPostImpl := TPostService.Create(FRestServer.Orm);
  RegisterService(FPostImpl, TypeInfo(IPost));
  // One-time backfill: if an older database has posts but no FTS5 rows, index the existing
  // records so /search works immediately after pulling this change. Subsequent writes keep
  // the two tables in lockstep via the transactional upsert in TPostService.
  PostCount := FRestServer.Orm.TableRowCount(TOrmBlogPost);
  FtsCount := FRestServer.Orm.TableRowCount(TOrmBlogPostFts);
  if (PostCount > 0) and (FtsCount < PostCount) then
    BackfillFtsIndex;
end;

end.
