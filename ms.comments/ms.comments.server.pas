/// <summary>
///   Interface-based service implementation for the Comments microservice.
///   Implements the IComment contract via TCommentService and hosts it
///   inside TCommentsServer (a TMicroService subclass).
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
  ///   Implements the IComment interface for comment CRUD and moderation.
  /// </summary>
  TCommentService = class(TInterfacedObject, IComment)
  private
    FOrm: IRestOrm;
  public
    constructor Create(const aOrm: IRestOrm);
    function GetByPost(aPostId: TID): RawJson;
    function GetPending: RawJson;
    function Add(aPostId: TID; const aData: RawJson): TID;
    function Approve(aId, aModeratedBy: TID): boolean;
    function Reject(aId, aModeratedBy: TID): boolean;
    function Remove(aId: TID): boolean;
  end;

  /// <summary>
  ///   Microservice server hosting the IComment service implementation.
  /// </summary>
  TCommentsServer = class(TMicroService)
  private
    FCommentImpl: TCommentService;
  protected
    function CreateModel: TOrmModel; override;
    procedure SetupServices; override;
  end;

implementation

{ TCommentService }

constructor TCommentService.Create(const aOrm: IRestOrm);
begin
  inherited Create;
  FOrm := aOrm;
end;

function TCommentService.GetByPost(aPostId: TID): RawJson;
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

function TCommentService.Add(aPostId: TID; const aData: RawJson): TID;
var
  Doc: TDocVariantData;
  Rec: TOrmBlogComment;
begin
  Doc.InitJson(aData, JSON_FAST_FLOAT);
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

function TCommentService.Approve(aId, aModeratedBy: TID): boolean;
var
  Rec: TOrmBlogComment;
begin
  Rec := TOrmBlogComment.Create;
  try
    if not FOrm.Retrieve(aId, Rec) then
    begin
      Result := False;
      Exit;
    end;
    Rec.Status := COMMENT_STATUS_APPROVED;
    Rec.ModeratedBy := aModeratedBy;
    Rec.ModeratedAt := NowUtc;
    Result := FOrm.Update(Rec, 'Status,ModeratedBy,ModeratedAt');
  finally
    Rec.Free;
  end;
end;

function TCommentService.Reject(aId, aModeratedBy: TID): boolean;
var
  Rec: TOrmBlogComment;
begin
  Rec := TOrmBlogComment.Create;
  try
    if not FOrm.Retrieve(aId, Rec) then
    begin
      Result := False;
      Exit;
    end;
    Rec.Status := COMMENT_STATUS_REJECTED;
    Rec.ModeratedBy := aModeratedBy;
    Rec.ModeratedAt := NowUtc;
    Result := FOrm.Update(Rec, 'Status,ModeratedBy,ModeratedAt');
  finally
    Rec.Free;
  end;
end;

function TCommentService.Remove(aId: TID): boolean;
begin
  Result := FOrm.Delete(TOrmBlogComment, aId);
end;

{ TCommentsServer }

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
