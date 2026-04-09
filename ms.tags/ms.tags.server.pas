/// <summary>
///   Interface-based service implementation for the Tags microservice. Implements <c>ITag</c> for tag CRUD and
///   many-to-many post-tag associations.
///
///   Demonstrates the junction table pattern in mORMot2:
///   - <c>TOrmPostTag</c> links posts to tags (m:n relationship).
///   - <c>SetPostTags</c> replaces all associations atomically by deleting existing entries and inserting new ones.
///   - <c>GetByPost</c> queries the junction table, then retrieves each tag individually (N+1 pattern, acceptable
///     for small tag counts per post).
///   - <c>TDocVariantData</c> with <c>Kind = dvArray</c> is used to parse the JSON array of tag IDs passed to
///     SetPostTags.
///
///   See <c>ms.users.server.pas</c> for detailed explanations of the basic CRUD and JSON parsing patterns used here.
/// </summary>
unit ms.tags.server;

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
  ms.tags.model;

type

  /// <summary>
  ///   Implements the ITag interface for tag CRUD and many-to-many post-tag associations.
  /// </summary>
  TTagService = class(TInterfacedObject, ITag)
  strict private
    /// <summary>
    ///   ORM interface used for all database operations on tags and post-tag associations.
    /// </summary>
    FOrm: IRestOrm;
  public

    /// <summary>
    ///   Creates a new TTagService instance with the given ORM interface.
    /// </summary>
    /// <param name="aOrm">
    ///   The ORM interface used for database access.
    /// </param>
    constructor Create(
      const aOrm: IRestOrm
      );

    /// <summary>
    ///   Retrieves a single tag by its ID.
    /// </summary>
    /// <param name="aId">
    ///   The unique identifier of the tag to retrieve.
    /// </param>
    /// <returns>
    ///   Tag data. <c>ID = 0</c> if not found.
    /// </returns>
    function Get(
      aId: TID
      ): TTagDto;

    /// <summary>
    ///   Retrieves all tags.
    /// </summary>
    /// <returns>
    ///   Array of all tags.
    /// </returns>
    function GetAll: TTagDtoArray;

    /// <summary>
    ///   Retrieves all tags associated with a given post.
    /// </summary>
    /// <param name="aPostId">
    ///   The post ID whose tags should be retrieved.
    /// </param>
    /// <returns>
    ///   Array of tags associated with the post.
    /// </returns>
    function GetByPost(
      aPostId: TID
      ): TTagDtoArray;

    /// <summary>
    ///   Retrieves all post IDs that have a specific tag assigned.
    /// </summary>
    /// <param name="aTagId">
    ///   The tag ID to look up.
    /// </param>
    /// <returns>
    ///   Array of post IDs that carry the given tag.
    /// </returns>
    function GetPostIds(
      aTagId: TID
      ): TIDDynArray;

    /// <summary>
    ///   Replaces all tag associations for a post with the given tag IDs.
    /// </summary>
    /// <param name="aPostId">
    ///   The post whose tag associations should be replaced.
    /// </param>
    /// <param name="aTagIds">
    ///   JSON array of tag IDs to assign to the post.
    /// </param>
    /// <returns>
    ///   True if the replacement succeeded.
    /// </returns>
    function SetPostTags(
      aPostId: TID;
      const aTagIds: RawJson
      ): boolean;

    /// <summary>
    ///   Creates a new tag.
    /// </summary>
    /// <param name="aData">
    ///   Tag data with at least <c>Name</c> (required).
    /// </param>
    /// <returns>
    ///   The ID of the newly created tag, or 0 if the name was empty.
    /// </returns>
    function Add(
      const aData: TTagCreateDto
      ): TID;

    /// <summary>
    ///   Updates an existing tag, merging only provided fields.
    /// </summary>
    /// <param name="aId">
    ///   The ID of the tag to update.
    /// </param>
    /// <param name="aData">
    ///   JSON object with fields to merge into the existing tag.
    /// </param>
    /// <returns>
    ///   True if the tag was found and updated successfully.
    /// </returns>
    function Update(
      aId: TID;
      const aData: RawJson
      ): boolean;

    /// <summary>
    ///   Removes a tag and all its post associations.
    /// </summary>
    /// <param name="aId">
    ///   The ID of the tag to remove.
    /// </param>
    /// <returns>
    ///   True if the tag was deleted successfully.
    /// </returns>
    function Remove(
      aId: TID
      ): boolean;
  end;

  /// <summary>
  ///   Microservice server for Tags. Registers TTagService as an interface-based SOA service.
  /// </summary>
  TTagsServer = class(TMicroService)
  strict private
    /// <summary>
    ///   Holds the TTagService instance registered as ITag on the REST server.
    /// </summary>
    FTagImpl: TTagService;
  protected

    /// <summary>
    ///   Creates the ORM model with TOrmBlogTag and TOrmPostTag.
    /// </summary>
    /// <returns>
    ///   A new TOrmModel configured for the tag tables.
    /// </returns>
    function CreateModel: TOrmModel; override;

    /// <summary>
    ///   Registers the ITag service implementation on the REST server.
    /// </summary>
    procedure SetupServices; override;
  end;

implementation

function TagToDto(
  aRec: TOrmBlogTag
  ): TTagDto;
begin
  Result.ID := aRec.IDValue;
  Result.Name := aRec.Name;
  Result.Slug := aRec.Slug;
  Result.Description := aRec.Description;
  Result.CreatedAt := aRec.CreatedAt;
end;

function TTagService.Add(
  const aData: TTagCreateDto
  ): TID;
var
  Tag: TOrmBlogTag;
begin
  if aData.Name = '' then
    Exit(0);
  Tag := TOrmBlogTag.Create;
  try
    Tag.Name := aData.Name;
    Tag.Slug := TextToSlug(Tag.Name);
    Tag.Description := aData.Description;
    Tag.CreatedAt := NowUtc;
    Result := FOrm.Add(Tag, True);
  finally
    Tag.Free;
  end;
end;

constructor TTagService.Create(
  const aOrm: IRestOrm
  );
begin
  inherited Create;
  FOrm := aOrm;
end;

function TTagService.Get(
  aId: TID
  ): TTagDto;
var
  Rec: TOrmBlogTag;
begin
  Finalize(Result);
  FillCharFast(Result, SizeOf(Result), 0);
  Rec := TOrmBlogTag.Create;
  try
    if FOrm.Retrieve(aId, Rec) then
      Result := TagToDto(Rec);
  finally
    Rec.Free;
  end;
end;

function TTagService.GetAll: TTagDtoArray;
var
  Rec: TOrmBlogTag;
  Count: PtrInt;
begin
  Result := nil;
  Count := 0;
  Rec := TOrmBlogTag.CreateAndFillPrepare(FOrm, '', []);
  try
    SetLength(Result, Rec.FillTable.RowCount);
    while Rec.FillOne do
    begin
      Result[Count] := TagToDto(Rec);
      Inc(Count);
    end;
    SetLength(Result, Count);
  finally
    Rec.Free;
  end;
end;

function TTagService.GetByPost(
  aPostId: TID
  ): TTagDtoArray;
var
  Table: TOrmTable;
  Tag: TOrmBlogTag;
  TagId: TID;
  RowIdx: PtrInt;
  Count: PtrInt;
begin
  Result := nil;
  Count := 0;
  Table := FOrm.MultiFieldValues(TOrmPostTag, 'TagId', FormatUtf8('PostId=%', [aPostId]));
  try
    if (Table = nil) or (Table.RowCount = 0) then
      Exit;
    SetLength(Result, Table.RowCount);
    for RowIdx := 1 to Table.RowCount do
    begin
      TagId := Table.GetAsInt64(RowIdx, 0);
      Tag := TOrmBlogTag.Create;
      try
        if FOrm.Retrieve(TagId, Tag) then
        begin
          Result[Count] := TagToDto(Tag);
          Inc(Count);
        end;
      finally
        Tag.Free;
      end;
    end;
    SetLength(Result, Count);
  finally
    Table.Free;
  end;
end;

function TTagService.GetPostIds(
  aTagId: TID
  ): TIDDynArray;
var
  Table: TOrmTable;
  RowIdx: PtrInt;
begin
  Result := nil;
  Table := FOrm.MultiFieldValues(TOrmPostTag, 'PostId', FormatUtf8('TagId=%', [aTagId]));
  try
    if (Table = nil) or (Table.RowCount = 0) then
      Exit;
    SetLength(Result, Table.RowCount);
    for RowIdx := 1 to Table.RowCount do
      Result[RowIdx - 1] := Table.GetAsInt64(RowIdx, 0);
  finally
    Table.Free;
  end;
end;

function TTagService.Remove(
  aId: TID
  ): boolean;
begin
  // Delete post-tag associations for this tag first
  FOrm.Delete(TOrmPostTag, FormatUtf8('TagId=%', [aId]));
  Result := FOrm.Delete(TOrmBlogTag, aId);
end;

function TTagService.SetPostTags(
  aPostId: TID;
  const aTagIds: RawJson
  ): boolean;
var
  Arr: TDocVariantData;
  TagId: TID;
  CountValue: Int64;
  PostTag: TOrmPostTag;
  TagIdx: PtrInt;
begin
  Result := False;
  Arr.InitJson(aTagIds, JSON_FAST_FLOAT);
  if Arr.Kind <> dvArray then
    Exit;
  // Delete existing associations for this post
  FOrm.Delete(TOrmPostTag, FormatUtf8('PostId=%', [aPostId]));
  // Create new associations
  for TagIdx := 0 to Arr.Count - 1 do
  begin
    TagId := Arr.Values[TagIdx];
    // Avoid duplicates
    CountValue := 0;
    FOrm.OneFieldValue(TOrmPostTag, 'count(*)', FormatUtf8('PostId=% AND TagId=%', [aPostId, TagId]), [], [], CountValue);
    if CountValue = 0 then
    begin
      PostTag := TOrmPostTag.Create;
      try
        PostTag.PostId := aPostId;
        PostTag.TagId := TagId;
        FOrm.Add(PostTag, True);
      finally
        PostTag.Free;
      end;
    end;
  end;
  Result := True;
end;

function TTagService.Update(
  aId: TID;
  const aData: RawJson
  ): boolean;
var
  Doc: TDocVariantData;
  Tag: TOrmBlogTag;
begin
  Result := False;
  Tag := TOrmBlogTag.Create;
  try
    if not FOrm.Retrieve(aId, Tag) then
      Exit;
    Doc.InitJson(aData, JSON_FAST_FLOAT);
    if Doc.GetValueIndex('Name') >= 0 then
    begin
      Tag.Name := Doc.U['Name'];
      Tag.Slug := TextToSlug(Tag.Name);
    end;
    if Doc.GetValueIndex('Description') >= 0 then
      Tag.Description := Doc.U['Description'];
    Result := FOrm.Update(Tag);
  finally
    Tag.Free;
  end;
end;

function TTagsServer.CreateModel: TOrmModel;
begin
  Result := TOrmModel.Create([TOrmBlogTag, TOrmPostTag], MODEL_ROOT);
end;

procedure TTagsServer.SetupServices;
begin
  FTagImpl := TTagService.Create(FRestServer.Orm);
  RegisterService(FTagImpl, TypeInfo(ITag));
end;

end.
