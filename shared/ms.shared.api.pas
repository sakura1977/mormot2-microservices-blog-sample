/// <summary>
///   SOA interface definitions for all blog microservices.
///   These interfaces define the service contracts used by both
///   server implementations and client proxies (gateway).
///
///   In mORMot2, interface-based services (SOA) are declared as
///   <c>IInvokable</c> descendants with a unique GUID. The framework
///   automatically generates JSON serialization for all method
///   parameters, enabling transparent HTTP-based remote calls.
///
///   Key mORMot2 SOA concepts used here:
///   - <c>IInvokable</c>: base interface enabling RTTI-based
///     method invocation and JSON marshalling.
///   - <c>RawJson</c>: a type alias for raw JSON content that
///     mORMot2 passes through without re-encoding. Ideal for
///     flexible, schema-less data exchange between services.
///   - <c>TID</c>: mORMot2's standard 64-bit integer type for
///     ORM record identifiers (maps to SQLite RowID).
///   - <c>RawUtf8</c>: mORMot2's preferred string type for all
///     UTF-8 text. More efficient than Delphi's UnicodeString
///     for JSON and HTTP operations.
///
///   URL format: POST /api/{InterfaceName}/{MethodName}
///   Request body: JSON array of positional parameters
///   Response: JSON object with named output parameters
/// </summary>
unit ms.shared.api;

{$SCOPEDENUMS ON}
{$I mormot.defines.inc}
{$WARN SYMBOL_PLATFORM OFF}
{$WARN UNIT_PLATFORM OFF}

interface

uses
  mormot.core.base,
  mormot.core.text;

type

  /// <summary>
  ///   Authentication service contract using SCRAM-MCF protocol.
  ///   Implements a two-phase challenge/authenticate flow where
  ///   the client computes PBKDF2 locally -- the plaintext password
  ///   is never transmitted over the wire.
  /// </summary>
  IAuth = interface(IInvokable)
    ['{F1D2E3C4-5A6B-7C8D-9E0F-1A2B3C4D5E6F}']

    /// <summary>
    ///   Phase 1 of SCRAM-MCF login. Returns the MCF format info
    ///   (algorithm, rounds, salt) and a one-time server nonce.
    ///   For unknown emails, returns fake MCF info to prevent
    ///   user enumeration attacks.
    /// </summary>
    /// <param name="aEmail">
    ///   The user's email address (login identifier).
    /// </param>
    /// <param name="aMcfInfo">
    ///   Output: MCF format string (e.g. $pbkdf2-sha256$310000$salt$).
    /// </param>
    /// <param name="aServerNonce">
    ///   Output: one-time nonce for this challenge (base64uri).
    /// </param>
    procedure Challenge(
      const aEmail: RawUtf8;
      out aMcfInfo, aServerNonce: RawUtf8
      );

    /// <summary>
    ///   Phase 2 of SCRAM-MCF login. Verifies the client's
    ///   cryptographic proof and returns a JWT token on success,
    ///   plus a server proof for mutual authentication.
    /// </summary>
    /// <param name="aEmail">
    ///   The user's email address (must match the Challenge call).
    /// </param>
    /// <param name="aServerNonce">
    ///   The server nonce received from Challenge.
    /// </param>
    /// <param name="aClientProof">
    ///   The SCRAM client proof computed by the client (base64uri).
    /// </param>
    /// <param name="aToken">
    ///   Output: JWT token on success, empty on failure.
    /// </param>
    /// <param name="aUserId">
    ///   Output: the authenticated user's ID.
    /// </param>
    /// <param name="aServerProof">
    ///   Output: server proof for mutual authentication (base64uri).
    /// </param>
    /// <returns>
    ///   True if the client proof was valid, False otherwise.
    /// </returns>
    function Authenticate(
      const aEmail, aServerNonce, aClientProof: RawUtf8;
      out aToken: RawUtf8;
      out aUserId: TID;
      out aServerProof: RawUtf8
      ): boolean;

    /// <summary>
    ///   Creates a new authentication account. Stores the email
    ///   together with the PBKDF2-derived credentials (MCF hash
    ///   and persisted SCRAM key).
    /// </summary>
    /// <param name="aEmail">
    ///   Login email address (must be unique).
    /// </param>
    /// <param name="aPassword">
    ///   Plaintext password (hashed server-side via PBKDF2-SHA256).
    /// </param>
    /// <param name="aUserId">
    ///   Foreign key to the author profile in ms.users.
    /// </param>
    /// <returns>
    ///   The UserId on success, 0 if the email is already taken
    ///   or input is invalid.
    /// </returns>
    function Register(
      const aEmail, aPassword: RawUtf8;
      aUserId: TID
      ): TID;

    /// <summary>
    ///   Validates a JWT token and extracts the user ID.
    /// </summary>
    /// <param name="aToken">
    ///   The JWT token to validate.
    /// </param>
    /// <param name="aUserId">
    ///   Output: the user ID encoded in the token.
    /// </param>
    /// <returns>
    ///   True if the token is valid and not expired.
    /// </returns>
    function Validate(
      const aToken: RawUtf8;
      out aUserId: TID
      ): boolean;

    /// <summary>
    ///   Changes a user's password after verifying the old one.
    /// </summary>
    /// <param name="aUserId">
    ///   The user whose password to change.
    /// </param>
    /// <param name="aOldPassword">
    ///   Current password for verification.
    /// </param>
    /// <param name="aNewPassword">
    ///   New password to set.
    /// </param>
    /// <returns>
    ///   True if the old password was correct and the change succeeded.
    /// </returns>
    function ChangePassword(
      aUserId: TID;
      const aOldPassword, aNewPassword: RawUtf8
      ): boolean;
  end;

  /// <summary>
  ///   User/author profile service. Provides CRUD operations for
  ///   author profiles (display name, bio, website).
  ///   Uses <c>RawJson</c> for flexible input/output -- the JSON
  ///   structure is parsed and validated in the implementation.
  /// </summary>
  IUser = interface(IInvokable)
    ['{A2B3C4D5-6E7F-8A9B-0C1D-2E3F4A5B6C7D}']

    /// <summary>
    ///   Retrieves a single author profile by ID.
    /// </summary>
    /// <param name="aId">
    ///   The author's record ID.
    /// </param>
    /// <returns>
    ///   JSON object with author data, or '{}' if not found.
    /// </returns>
    function Get(
      aId: TID
      ): RawJson;

    /// <summary>
    ///   Retrieves all author profiles.
    /// </summary>
    /// <returns>
    ///   JSON array of author objects, or '[]' if empty.
    /// </returns>
    function GetAll: RawJson;

    /// <summary>
    ///   Creates a new author profile.
    /// </summary>
    /// <param name="aData">
    ///   JSON object with at least <c>DisplayName</c> (required).
    /// </param>
    /// <returns>
    ///   The new record ID, or 0 if validation failed.
    /// </returns>
    function Add(
      const aData: RawJson
      ): TID;

    /// <summary>
    ///   Partially updates an existing author profile.
    ///   Only fields present in the JSON are modified.
    /// </summary>
    /// <param name="aId">
    ///   The author's record ID.
    /// </param>
    /// <param name="aData">
    ///   JSON object with fields to update.
    /// </param>
    /// <returns>
    ///   True if the record was found and updated.
    /// </returns>
    function Update(
      aId: TID;
      const aData: RawJson
      ): boolean;

    /// <summary>
    ///   Deletes an author profile.
    /// </summary>
    /// <param name="aId">
    ///   The author's record ID.
    /// </param>
    /// <returns>
    ///   True if the DELETE statement executed successfully.
    /// </returns>
    function Remove(
      aId: TID
      ): boolean;
  end;

  /// <summary>
  ///   Blog post service. Provides CRUD with pagination, filtering
  ///   by status and author, and URL slug-based lookup.
  /// </summary>
  IPost = interface(IInvokable)
    ['{B3C4D5E6-7F8A-9B0C-1D2E-3F4A5B6C7D8E}']

    /// <summary>
    ///   Retrieves a single post by ID.
    /// </summary>
    /// <param name="aId">
    ///   The post's record ID.
    /// </param>
    /// <returns>
    ///   JSON object with post data, or '{}' if not found.
    /// </returns>
    function Get(
      aId: TID
      ): RawJson;

    /// <summary>
    ///   Retrieves a single post by its URL-friendly slug.
    /// </summary>
    /// <param name="aSlug">
    ///   The slug to look up (e.g. 'my-first-post').
    /// </param>
    /// <returns>
    ///   JSON object with post data, or '{}' if not found.
    /// </returns>
    function GetBySlug(
      const aSlug: RawUtf8
      ): RawJson;

    /// <summary>
    ///   Retrieves a paginated, filtered list of posts.
    /// </summary>
    /// <param name="aPage">
    ///   Page number (1-based). Clamped to >= 1.
    /// </param>
    /// <param name="aLimit">
    ///   Items per page (clamped to 1..100).
    /// </param>
    /// <param name="aStatus">
    ///   Filter by status (0=draft, 1=published, 2=archived).
    ///   Pass 0 to include all statuses.
    /// </param>
    /// <param name="aAuthorId">
    ///   Filter by author. Pass 0 to include all authors.
    /// </param>
    /// <returns>
    ///   JSON object: {"items":[...],"total":N,"page":N}.
    /// </returns>
    function GetList(
      aPage, aLimit, aStatus: integer;
      aAuthorId: TID
      ): RawJson;

    /// <summary>
    ///   Creates a new blog post. The slug is auto-generated
    ///   from the title via <c>TextToSlug</c>.
    /// </summary>
    /// <param name="aData">
    ///   JSON object with at least <c>Title</c> (required).
    /// </param>
    /// <returns>
    ///   The new record ID, or 0 if validation failed.
    /// </returns>
    function Add(
      const aData: RawJson
      ): TID;

    /// <summary>
    ///   Partially updates an existing post. If the title changes,
    ///   the slug is regenerated automatically.
    /// </summary>
    /// <param name="aId">
    ///   The post's record ID.
    /// </param>
    /// <param name="aData">
    ///   JSON object with fields to update.
    /// </param>
    /// <returns>
    ///   True if the record was found and updated.
    /// </returns>
    function Update(
      aId: TID;
      const aData: RawJson
      ): boolean;

    /// <summary>
    ///   Deletes a blog post.
    /// </summary>
    /// <param name="aId">
    ///   The post's record ID.
    /// </param>
    /// <returns>
    ///   True if the DELETE statement executed successfully.
    /// </returns>
    function Remove(
      aId: TID
      ): boolean;
  end;

  /// <summary>
  ///   Tag service. Manages tags and many-to-many post-tag
  ///   associations via a junction table (TOrmPostTag).
  /// </summary>
  ITag = interface(IInvokable)
    ['{C4D5E6F7-8A9B-0C1D-2E3F-4A5B6C7D8E9F}']

    /// <summary>
    ///   Retrieves a single tag by ID.
    /// </summary>
    /// <param name="aId">
    ///   The tag's record ID.
    /// </param>
    /// <returns>
    ///   JSON object with tag data, or '{}' if not found.
    /// </returns>
    function Get(
      aId: TID
      ): RawJson;

    /// <summary>
    ///   Retrieves all tags.
    /// </summary>
    /// <returns>
    ///   JSON array of tag objects, or '[]' if empty.
    /// </returns>
    function GetAll: RawJson;

    /// <summary>
    ///   Retrieves all tags assigned to a specific post.
    /// </summary>
    /// <param name="aPostId">
    ///   The post's record ID.
    /// </param>
    /// <returns>
    ///   JSON array of tag objects, or '[]' if none assigned.
    /// </returns>
    function GetByPost(
      aPostId: TID
      ): RawJson;

    /// <summary>
    ///   Replaces all tag assignments for a post. Deletes existing
    ///   associations and creates new ones from the provided tag IDs.
    /// </summary>
    /// <param name="aPostId">
    ///   The post to assign tags to.
    /// </param>
    /// <param name="aTagIds">
    ///   JSON array of tag IDs, e.g. '[1,3,5]'.
    ///   Passed as <c>RawJson</c> so mORMot2 does not re-encode it.
    /// </param>
    /// <returns>
    ///   True if the input was valid and assignments were updated.
    /// </returns>
    function SetPostTags(
      aPostId: TID;
      const aTagIds: RawJson
      ): boolean;

    /// <summary>
    ///   Creates a new tag. The slug is auto-generated from the name.
    /// </summary>
    /// <param name="aData">
    ///   JSON object with at least <c>Name</c> (required, unique).
    /// </param>
    /// <returns>
    ///   The new record ID, or 0 if validation or UNIQUE
    ///   constraint failed.
    /// </returns>
    function Add(
      const aData: RawJson
      ): TID;

    /// <summary>
    ///   Partially updates an existing tag. If the name changes,
    ///   the slug is regenerated automatically.
    /// </summary>
    /// <param name="aId">
    ///   The tag's record ID.
    /// </param>
    /// <param name="aData">
    ///   JSON object with fields to update.
    /// </param>
    /// <returns>
    ///   True if the record was found and updated.
    /// </returns>
    function Update(
      aId: TID;
      const aData: RawJson
      ): boolean;

    /// <summary>
    ///   Deletes a tag and all its post-tag associations.
    /// </summary>
    /// <param name="aId">
    ///   The tag's record ID.
    /// </param>
    /// <returns>
    ///   True if the DELETE statement executed successfully.
    /// </returns>
    function Remove(
      aId: TID
      ): boolean;
  end;

  /// <summary>
  ///   Comment service with moderation workflow. Comments start
  ///   as pending, and must be approved or rejected by an author
  ///   before they appear publicly.
  /// </summary>
  IComment = interface(IInvokable)
    ['{D5E6F7A8-9B0C-1D2E-3F4A-5B6C7D8E9FA0}']

    /// <summary>
    ///   Retrieves all approved comments for a post.
    /// </summary>
    /// <param name="aPostId">
    ///   The post's record ID.
    /// </param>
    /// <returns>
    ///   JSON array of approved comment objects, or '[]' if none.
    /// </returns>
    function GetByPost(
      aPostId: TID
      ): RawJson;

    /// <summary>
    ///   Retrieves all comments awaiting moderation.
    /// </summary>
    /// <returns>
    ///   JSON array of pending comment objects, or '[]' if none.
    /// </returns>
    function GetPending: RawJson;

    /// <summary>
    ///   Adds a new comment to a post (status: pending).
    ///   Visitors can comment without authentication.
    /// </summary>
    /// <param name="aPostId">
    ///   The post to comment on (must be > 0).
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
  ///   Media service for file uploads. Files are uploaded as
  ///   Base64-encoded strings, stored on the file system, with
  ///   metadata tracked in the database.
  /// </summary>
  IMedia = interface(IInvokable)
    ['{E6F7A8B9-0C1D-2E3F-4A5B-6C7D8E9FA0B1}']

    /// <summary>
    ///   Uploads a media file. The file data is Base64-encoded
    ///   and decoded server-side. Maximum size: 3 MB after decoding.
    /// </summary>
    /// <param name="aFileName">
    ///   Original file name (required, used for MIME type detection).
    /// </param>
    /// <param name="aFileData">
    ///   Base64-encoded file content (required).
    /// </param>
    /// <param name="aAltText">
    ///   Alternative text for accessibility/SEO (optional).
    /// </param>
    /// <param name="aUploadedBy">
    ///   The author who uploaded the file.
    /// </param>
    /// <returns>
    ///   The new media record ID, or 0 if validation failed
    ///   or the file exceeds the size limit.
    /// </returns>
    function Upload(
      const aFileName, aFileData, aAltText: RawUtf8;
      aUploadedBy: TID
      ): TID;

    /// <summary>
    ///   Retrieves metadata for a media file (name, MIME type,
    ///   size, alt text) without the file content.
    /// </summary>
    /// <param name="aId">
    ///   The media record ID.
    /// </param>
    /// <returns>
    ///   JSON object with metadata, or '{}' if not found.
    /// </returns>
    function GetInfo(
      aId: TID
      ): RawJson;

    /// <summary>
    ///   Retrieves the raw file content and its MIME type.
    /// </summary>
    /// <param name="aId">
    ///   The media record ID.
    /// </param>
    /// <param name="aContentType">
    ///   Output: the MIME type (e.g. 'image/png').
    /// </param>
    /// <returns>
    ///   The raw file bytes, or empty string if not found.
    /// </returns>
    function GetFile(
      aId: TID;
      out aContentType: RawUtf8
      ): RawByteString;

    /// <summary>
    ///   Deletes a media file from both the database and the
    ///   file system.
    /// </summary>
    /// <param name="aId">
    ///   The media record ID.
    /// </param>
    /// <returns>
    ///   True if the record was found and deleted.
    /// </returns>
    function Remove(
      aId: TID
      ): boolean;
  end;

  /// <summary>
  ///   Gateway aggregation service. Enriches a single post with
  ///   data from multiple backend services (author profile, tags,
  ///   approved comments) into one combined JSON response.
  ///   This is the only service with actual business logic in
  ///   the gateway -- all other interfaces are proxied directly.
  /// </summary>
  IBlog = interface(IInvokable)
    ['{F7A8B9C0-1D2E-3F4A-5B6C-7D8E9FA0B1C2}']

    /// <summary>
    ///   Returns a fully enriched blog post: post data plus
    ///   nested Author object, Tags array, and Comments array.
    /// </summary>
    /// <param name="aId">
    ///   The post's record ID.
    /// </param>
    /// <returns>
    ///   Aggregated JSON object, or '{}' if the post was not found.
    /// </returns>
    function GetPostFull(
      aId: TID
      ): RawJson;
  end;

implementation

end.
