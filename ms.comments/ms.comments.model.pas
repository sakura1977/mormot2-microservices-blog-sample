/// <summary>
///   ORM model for the Comments service: comments with moderation.
/// </summary>
unit ms.comments.model;

{$SCOPEDENUMS ON}
{$I mormot.defines.inc}
{$WARN SYMBOL_PLATFORM OFF}
{$WARN UNIT_PLATFORM OFF}

interface

uses
  mormot.core.base,
  mormot.orm.core;

type

  /// <summary>
  ///   Stores a comment on a blog post, including moderation state.
  /// </summary>
  TOrmComment = class(TOrm)
  private
    FPostId: TID;
    FAuthorName: RawUtf8;
    FAuthorEmail: RawUtf8;
    FBody: RawUtf8;
    FStatus: integer;
    FModeratedBy: TID;
    FModeratedAt: TDateTime;
    FCreatedAt: TDateTime;
  published

    /// <summary>
    ///   Foreign key referencing the post this comment belongs to.
    /// </summary>
    property PostId: TID
      read FPostId write FPostId;

    /// <summary>
    ///   Display name of the comment author.
    /// </summary>
    property AuthorName: RawUtf8 index 200
      read FAuthorName write FAuthorName;

    /// <summary>
    ///   Email address of the comment author.
    /// </summary>
    property AuthorEmail: RawUtf8 index 200
      read FAuthorEmail write FAuthorEmail;

    /// <summary>
    ///   Full text body of the comment.
    /// </summary>
    property Body: RawUtf8
      read FBody write FBody;

    /// <summary>
    ///   Moderation status code (e.g. pending, approved, rejected).
    /// </summary>
    property Status: integer
      read FStatus write FStatus;

    /// <summary>
    ///   Foreign key referencing the moderator who reviewed the comment.
    /// </summary>
    property ModeratedBy: TID
      read FModeratedBy write FModeratedBy;

    /// <summary>
    ///   Timestamp when the comment was moderated.
    /// </summary>
    property ModeratedAt: TDateTime
      read FModeratedAt write FModeratedAt;

    /// <summary>
    ///   Timestamp when the comment was created.
    /// </summary>
    property CreatedAt: TDateTime
      read FCreatedAt write FCreatedAt;
  end;

/// <summary>
///   Creates the ORM model for the Comments service.
/// </summary>
/// <returns>
///   A TOrmModel instance containing TOrmComment.
/// </returns>
function CreateCommentsModel: TOrmModel;

implementation

function CreateCommentsModel: TOrmModel;
begin
  Result := TOrmModel.Create([TOrmComment]);
end;

end.
