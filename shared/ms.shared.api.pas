/// <summary>
///   Interface definitions for all blog microservices.
///   These interfaces define the service contracts used by
///   both server implementations and client proxies.
/// </summary>
unit ms.shared.api;

{$I mormot.defines.inc}

interface

uses
  mormot.core.base,
  mormot.core.text;

type

  /// <summary>
  ///   Authentication service: SCRAM-MCF challenge/authenticate,
  ///   registration, token validation, password change.
  /// </summary>
  IAuth = interface(IInvokable)
    ['{F1D2E3C4-5A6B-7C8D-9E0F-1A2B3C4D5E6F}']
    /// Phase 1 of SCRAM-MCF login: returns MCF format info and a server nonce.
    procedure Challenge(const aEmail: RawUtf8;
      out aMcfInfo, aServerNonce: RawUtf8);
    /// Phase 2 of SCRAM-MCF login: verifies client proof, returns JWT.
    function Authenticate(const aEmail, aServerNonce, aClientProof: RawUtf8;
      out aToken: RawUtf8; out aUserId: TID;
      out aServerProof: RawUtf8): boolean;
    /// Creates a new user account. Returns the UserId on success, 0 on failure.
    function Register(const aEmail, aPassword: RawUtf8;
      aUserId: TID): TID;
    /// Validates a JWT token and returns the associated user ID.
    function Validate(const aToken: RawUtf8;
      out aUserId: TID): boolean;
    /// Changes a user's password after verifying the old one.
    function ChangePassword(aUserId: TID;
      const aOldPassword, aNewPassword: RawUtf8): boolean;
  end;

  /// <summary>
  ///   User/author profile service: CRUD for author profiles.
  /// </summary>
  IUser = interface(IInvokable)
    ['{A2B3C4D5-6E7F-8A9B-0C1D-2E3F4A5B6C7D}']
    function Get(aId: TID): RawJson;
    function GetAll: RawJson;
    function Add(const aData: RawJson): TID;
    function Update(aId: TID; const aData: RawJson): boolean;
    function Remove(aId: TID): boolean;
  end;

  /// <summary>
  ///   Blog post service: CRUD with pagination and filtering.
  /// </summary>
  IPost = interface(IInvokable)
    ['{B3C4D5E6-7F8A-9B0C-1D2E-3F4A5B6C7D8E}']
    function Get(aId: TID): RawJson;
    function GetBySlug(const aSlug: RawUtf8): RawJson;
    function GetList(aPage, aLimit, aStatus: integer;
      aAuthorId: TID): RawJson;
    function Add(const aData: RawJson): TID;
    function Update(aId: TID; const aData: RawJson): boolean;
    function Remove(aId: TID): boolean;
  end;

  /// <summary>
  ///   Tag service: CRUD for tags and m:n post-tag associations.
  /// </summary>
  ITag = interface(IInvokable)
    ['{C4D5E6F7-8A9B-0C1D-2E3F-4A5B6C7D8E9F}']
    function Get(aId: TID): RawJson;
    function GetAll: RawJson;
    function GetByPost(aPostId: TID): RawJson;
    function SetPostTags(aPostId: TID;
      const aTagIds: RawJson): boolean;
    function Add(const aData: RawJson): TID;
    function Update(aId: TID; const aData: RawJson): boolean;
    function Remove(aId: TID): boolean;
  end;

  /// <summary>
  ///   Comment service: create, moderate, and list comments.
  /// </summary>
  IComment = interface(IInvokable)
    ['{D5E6F7A8-9B0C-1D2E-3F4A-5B6C7D8E9FA0}']
    function GetByPost(aPostId: TID): RawJson;
    function GetPending: RawJson;
    function Add(aPostId: TID; const aData: RawJson): TID;
    function Approve(aId, aModeratedBy: TID): boolean;
    function Reject(aId, aModeratedBy: TID): boolean;
    function Remove(aId: TID): boolean;
  end;

  /// <summary>
  ///   Media service: upload, metadata, and file serving.
  /// </summary>
  IMedia = interface(IInvokable)
    ['{E6F7A8B9-0C1D-2E3F-4A5B-6C7D8E9FA0B1}']
    function Upload(const aFileName, aFileData, aAltText: RawUtf8;
      aUploadedBy: TID): TID;
    function GetInfo(aId: TID): RawJson;
    function GetFile(aId: TID;
      out aContentType: RawUtf8): RawByteString;
    function Remove(aId: TID): boolean;
  end;

  /// <summary>
  ///   Gateway aggregation service: enriched post with author/tags/comments.
  /// </summary>
  IBlog = interface(IInvokable)
    ['{F7A8B9C0-1D2E-3F4A-5B6C-7D8E9FA0B1C2}']
    function GetPostFull(aId: TID): RawJson;
  end;

implementation

end.
