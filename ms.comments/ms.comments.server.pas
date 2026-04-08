/// <summary>
///   Interface-based service implementation for the Comments microservice.
///   Implements the <c>IComment</c> contract with moderation workflow.
///
///   Demonstrates the selective-field update pattern in mORMot2:
///   - <c>IRestOrm.Update(Rec, 'Field1,Field2')</c>: the second
///     parameter is a CSV list of field names to update. Only those
///     columns are written to SQLite, which is more efficient than
///     updating all fields and avoids accidentally overwriting
///     fields that weren't intended to change.
///   - Moderation workflow: comments start as pending (status 0),
///     and are approved (1) or rejected (2) by an author. Only
///     approved comments are returned by <c>GetByPost</c>.
///
///   See <c>ms.users.server.pas</c> for detailed explanations of
///   the basic CRUD and JSON parsing patterns used here.
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
  mormot.core.variants,
  mormot.orm.base,
  mormot.orm.core,
  mormot.rest.core,
  mormot.rest.server,
  mormot.rest.sqlite3,
  mormot.soa.core,
  mormot.soa.server,
  ms.comments.model,
  ms.shared,
  ms.shared.api,
  ms.shared.service;

type

  /// <summary>
  ///   Implements the <c>IComment</c> interface for comment CRUD
  ///   and moderation.
  /// </summary>
  TCommentService = class(TInterfacedObject, IComment)
  private

    /// <summary>
    ///   ORM interface for database access.
    /// </summary>
    FOrm: IRestOrm;
  public

    /// <summary>
    ///   Creates the comment service with an injected ORM interface.
    /// </summary>
    /// <param name="aOrm">
    ///   The ORM interface for database operations.
    /// </param>
    constructor Create(
      const aOrm: IRestOrm
      );

    /// <summary>
    ///   Adds a new comment to a post with status pending.
    /// </summary>
    /// <param name="aPostId">
    ///   The post to comment on (must be greater than 0).
    /// </param>
    /// <param name="aData">
    ///   JSON object with at least <c>Body</c> (required).
    /// </param>
    /// <returns>
    ///   The new comment ID, or 0 if validation failed.
    /// </returns>
    function Add(
      aPostId: TID;
      const aData: RawJson
      ): TID;

    /// <summary>
    ///   Approves a pending comment, making it publicly visible.
    /// </summary>
    /// <param name="aId">
    ///   The comment's record ID.
    /// </param>
    /// <param name="aModeratedBy">
    ///   The author ID who approved the comment.
    /// </param>
    /// <returns>
    ///   True if the comment was found and approved.
    /// </returns>
    function Approve(
      aId, aModeratedBy: TID
      ): boolean;

    /// <summary>
    ///   Retrieves all approved comments for a post.
    /// </summary>
    /// <param name="aPostId">
    ///   The post's record ID.
    /// </param>
    /// <returns>
    ///   JSON array of approved comment objects, or '[]'.
    /// </returns>
    function GetByPost(
      aPostId: TID
      ): RawJson;

    /// <summary>
    ///   Retrieves all comments awaiting moderation.
    /// </summary>
    /// <returns>
    ///   JSON array of pending comment objects, or '[]'.
    /// </returns>
    function GetPending: RawJson;

    /// <summary>
    ///   Rejects a pending comment, hiding it from public view.
    /// </summary>
    /// <param name="aId">
    ///   The comment's record ID.
    /// </param>
    /// <param name="aModeratedBy">
    ///   The author ID who rejected the comment.
    /// </param>
    /// <returns>
    ///   True if the comment was found and rejected.
    /// </returns>
    function Reject(
      aId, aModeratedBy: TID
      ): boolean;

    /// <summary>
    ///   Deletes a comment permanently.
    /// </summary>
    /// <param name="aId">
    ///   The comment's record ID.
    /// </param>
    /// <returns>
    ///   True if the DELETE statement executed successfully.
    /// </returns>
    function Remove(
      aId: TID
      ): boolean;
  end;

  /// <summary>
  ///   Microservice server hosting the <c>IComment</c> service
  ///   implementation.
  /// </summary>
  TCommentsServer = class(TMicroService)
  private

    /// <summary>
    ///   The comment service implementation instance.
    /// </summary>
    FCommentImpl: TCommentService;
  protected

    /// <summary>
    ///   Creates the ORM model with <c>TOrmBlogComment</c>.
    /// </summary>
    /// <returns>
    ///   A new <c>TOrmModel</c> for the comments table.
    /// </returns>
    function CreateModel: TOrmModel; override;

    /// <summary>
    ///   Registers the <c>IComment</c> service implementation.
    /// </summary>
    procedure SetupServices; override;
  end;

implementation

function TCommentService.Add(
  aPostId: TID;
  const aData: RawJson
  ): TID;
var
  Doc: TDocVariantData;
  Rec: TOrmBlogComment;
begin
  Doc.InitJson(aData, JSON_FAST_FLOAT);
  if (aPostId <= 0) or (Doc.U['Body'] = '') then
    Exit(0);
  Rec := TOrmBlogComment.Create;
  try
    Rec.PostId := aPostId;
    Rec.AuthorName := Doc.U['AuthorName'];
    Rec.AuthorEmail := Doc.U['AuthorEmail'];
    Rec.Body := Doc.U['Body'];
    Rec.Status := COMMENT_STATUS_PENDING;
    Rec.CreatedAt := NowUtc;
    Result := FOrm.Add(Rec, True);
  finally
    Rec.Free;
  end;
end;

function TCommentService.Approve(
  aId, aModeratedBy: TID
  ): boolean;
var
  Rec: TOrmBlogComment;
begin
  Rec := TOrmBlogComment.Create;
  try
    if not FOrm.Retrieve(aId, Rec) then
      Exit(False);
    Rec.Status := COMMENT_STATUS_APPROVED;
    Rec.ModeratedBy := aModeratedBy;
    Rec.ModeratedAt := NowUtc;
    Result := FOrm.Update(Rec, 'Status,ModeratedBy,ModeratedAt');
  finally
    Rec.Free;
  end;
end;

constructor TCommentService.Create(
  const aOrm: IRestOrm
  );
begin
  inherited Create;
  FOrm := aOrm;
end;

function TCommentService.GetByPost(
  aPostId: TID
  ): RawJson;
var
  Table: TOrmTable;
begin
  Table := FOrm.MultiFieldValues(TOrmBlogComment, '*',
    FormatUtf8('PostId=% AND Status=% ORDER BY RowID ASC',
      [aPostId, COMMENT_STATUS_APPROVED]));
  try
    if Table = nil then
      Result := '[]'
    else
      Result := Table.GetJsonValues(True);
  finally
    Table.Free;
  end;
end;

function TCommentService.GetPending: RawJson;
var
  Table: TOrmTable;
begin
  Table := FOrm.MultiFieldValues(TOrmBlogComment, '*',
    FormatUtf8('Status=%', [COMMENT_STATUS_PENDING]));
  try
    if Table = nil then
      Result := '[]'
    else
      Result := Table.GetJsonValues(True);
  finally
    Table.Free;
  end;
end;

function TCommentService.Reject(
  aId, aModeratedBy: TID
  ): boolean;
var
  Rec: TOrmBlogComment;
begin
  Rec := TOrmBlogComment.Create;
  try
    if not FOrm.Retrieve(aId, Rec) then
      Exit(False);
    Rec.Status := COMMENT_STATUS_REJECTED;
    Rec.ModeratedBy := aModeratedBy;
    Rec.ModeratedAt := NowUtc;
    Result := FOrm.Update(Rec, 'Status,ModeratedBy,ModeratedAt');
  finally
    Rec.Free;
  end;
end;

function TCommentService.Remove(
  aId: TID
  ): boolean;
begin
  Result := FOrm.Delete(TOrmBlogComment, aId);
end;

function TCommentsServer.CreateModel: TOrmModel;
begin
  Result := TOrmModel.Create([TOrmBlogComment], MODEL_ROOT);
end;

procedure TCommentsServer.SetupServices;
begin
  FCommentImpl := TCommentService.Create(FRestServer.Orm);
  RegisterService(FCommentImpl, TypeInfo(IComment));
end;

end.
