/// <summary>
///   Interface-based service implementation for the Tags microservice.
///   Implements ITag for tag CRUD and post-tag associations.
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
  ///   Implements the ITag interface for tag CRUD and
  ///   many-to-many post-tag associations.
  /// </summary>
  TTagService = class(TInterfacedObject, ITag)
  private
    FOrm: IRestOrm;
  public
    constructor Create(const aOrm: IRestOrm);

    // ITag methods

    /// <summary>
    ///   Retrieves a single tag by its ID.
    /// </summary>
    function Get(aId: TID): RawJson;

    /// <summary>
    ///   Retrieves all tags.
    /// </summary>
    function GetAll: RawJson;

    /// <summary>
    ///   Retrieves all tags associated with a given post.
    /// </summary>
    function GetByPost(aPostId: TID): RawJson;

    /// <summary>
    ///   Replaces all tag associations for a post with the given tag IDs.
    /// </summary>
    function SetPostTags(aPostId: TID;
      const aTagIds: RawJson): boolean;

    /// <summary>
    ///   Creates a new tag from the provided JSON data.
    /// </summary>
    function Add(const aData: RawJson): TID;

    /// <summary>
    ///   Updates an existing tag, merging only provided fields.
    /// </summary>
    function Update(aId: TID; const aData: RawJson): boolean;

    /// <summary>
    ///   Removes a tag and all its post associations.
    /// </summary>
    function Remove(aId: TID): boolean;
  end;

  /// <summary>
  ///   Microservice server for Tags.
  ///   Registers TTagService as an interface-based SOA service.
  /// </summary>
  TTagsServer = class(TMicroService)
  private
    FTagImpl: TTagService;
  protected
    /// <summary>
    ///   Creates the ORM model with TOrmBlogTag and TOrmPostTag.
    /// </summary>
    function CreateModel: TOrmModel; override;

    /// <summary>
    ///   Registers the ITag service implementation on the REST server.
    /// </summary>
    procedure SetupServices; override;
  end;

implementation

{ TTagService }

constructor TTagService.Create(const aOrm: IRestOrm);
begin
  inherited Create;
  FOrm := aOrm;
end;

function TTagService.Get(aId: TID): RawJson;
begin
  Result := OrmGetById(FOrm, TOrmBlogTag, aId);
end;

function TTagService.GetAll: RawJson;
begin
  Result := OrmGetAll(FOrm, TOrmBlogTag);
end;

function TTagService.GetByPost(aPostId: TID): RawJson;
var
  Table: TOrmTable;
  Doc: TDocVariantData;
  Tag: TOrmBlogTag;
  TagId: TID;
  i: PtrInt;
begin
  Table := FOrm.MultiFieldValues(TOrmPostTag, 'TagId',
    FormatUtf8('PostId=%', [aPostId]));
  try
    if (Table = nil) or (Table.RowCount = 0) then
    begin
      Result := '[]';
      Exit;
    end;
    Doc.InitArray([], JSON_FAST);
    for i := 1 to Table.RowCount do
    begin
      TagId := Table.GetAsInt64(i, 0);
      Tag := TOrmBlogTag.Create;
      try
        if FOrm.Retrieve(TagId, Tag) then
          Doc.AddItem(
            _JsonFast(Tag.GetJsonValues(True, True, ooSelect)));
      finally
        Tag.Free;
      end;
    end;
    Result := Doc.ToJson;
  finally
    Table.Free;
  end;
end;

function TTagService.SetPostTags(aPostId: TID;
  const aTagIds: RawJson): boolean;
var
  Arr: TDocVariantData;
  TagId: TID;
  CountValue: Int64;
  PostTag: TOrmPostTag;
  i: PtrInt;
begin
  Result := False;
  Arr.InitJson(aTagIds, JSON_FAST_FLOAT);
  if Arr.Kind <> dvArray then
    Exit;
  // Delete existing associations for this post
  FOrm.Delete(TOrmPostTag,
    FormatUtf8('PostId=%', [aPostId]));
  // Create new associations
  for i := 0 to Arr.Count - 1 do
  begin
    TagId := Arr.Values[i];
    // Avoid duplicates
    CountValue := 0;
    FOrm.OneFieldValue(TOrmPostTag, 'count(*)',
      FormatUtf8('PostId=% AND TagId=%', [aPostId, TagId]),
      [], [], CountValue);
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

function TTagService.Add(const aData: RawJson): TID;
var
  Doc: TDocVariantData;
  Tag: TOrmBlogTag;
begin
  Doc.InitJson(aData, JSON_FAST_FLOAT);
  Tag := TOrmBlogTag.Create;
  try
    Tag.Name := Doc.U['Name'];
    Tag.Slug := TextToSlug(Tag.Name);
    Tag.Description := Doc.U['Description'];
    Tag.CreatedAt := NowUtc;
    Result := FOrm.Add(Tag, True);
  finally
    Tag.Free;
  end;
end;

function TTagService.Update(aId: TID; const aData: RawJson): boolean;
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

function TTagService.Remove(aId: TID): boolean;
begin
  // Delete post-tag associations for this tag first
  FOrm.Delete(TOrmPostTag,
    FormatUtf8('TagId=%', [aId]));
  Result := FOrm.Delete(TOrmBlogTag, aId);
end;

{ TTagsServer }

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
