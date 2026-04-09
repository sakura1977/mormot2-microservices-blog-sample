/// <summary>
///   SOA interface definitions and DTO record types for all blog microservices. These interfaces define the service
///   contracts used by both server implementations and client proxies (gateway).
///
///   In mORMot2, interface-based services (SOA) are declared as <c>IInvokable</c> descendants with a unique GUID.
///   The framework automatically generates JSON serialization for all method parameters, enabling transparent
///   HTTP-based remote calls.
///
///   Key mORMot2 SOA concepts used here:
///   - <c>IInvokable</c>: base interface enabling RTTI-based method invocation and JSON marshalling.
///   - <c>TID</c>: mORMot2's standard 64-bit integer type for ORM record identifiers (maps to SQLite RowID).
///   - <c>RawUtf8</c>: mORMot2's preferred string type for all UTF-8 text. More efficient than Delphi's UnicodeString
///     for JSON and HTTP operations.
///   - <c>RawJson</c>: a type alias for raw JSON content that mORMot2 passes through without re-encoding. Used only
///     where schema-less data exchange is required (Update methods with PATCH semantics, IConfig).
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
  mormot.core.interfaces,
  mormot.core.rtti,
  mormot.core.text,
  mormot.soa.core;

const
  /// <summary>
  ///   Symmetric encryption key used during the WebSocket upgrade handshake. Both server and client sides must
  ///   use the same value, otherwise <c>WebSocketsUpgrade</c> fails. Override in <c>ms.config.master.json</c>
  ///   for any real deployment -- this default is suitable for the development demo only.
  /// </summary>
  WEBSOCKETS_KEY = 'blog-microservices-ws-change-me';

  /// <summary>
  ///   The friendly URI segment used for WebSocket upgrades. Empty means "any URI is accepted", which keeps the
  ///   handshake compatible with the existing <c>/api</c> root used by REST traffic.
  /// </summary>
  WEBSOCKETS_URI = '';

type

  // -----------------------------------------------------------------------
  //  Base DTO Records -- output types for entity retrieval
  // -----------------------------------------------------------------------

  /// <summary>
  ///   Data transfer object for author/user profiles. Mirrors the <c>TOrmAuthor</c> fields exposed via the public API.
  ///   An <c>ID</c> of 0 indicates that no record was found.
  /// </summary>
  TAuthorDto = packed record
  public
    /// <summary>
    ///   Unique author identifier (SQLite RowID).
    /// </summary>
    ID: TID;

    /// <summary>
    ///   Author's display name shown on posts and profiles.
    /// </summary>
    DisplayName: RawUtf8;

    /// <summary>
    ///   URL-friendly identifier, auto-generated from <c>DisplayName</c>.
    /// </summary>
    Slug: RawUtf8;

    /// <summary>
    ///   Biographical text for the author profile.
    /// </summary>
    Bio: RawUtf8;

    /// <summary>
    ///   Author's personal or professional website URL.
    /// </summary>
    WebsiteUrl: RawUtf8;

    /// <summary>
    ///   Foreign key to the author's avatar media file.
    /// </summary>
    AvatarMediaId: TID;

    /// <summary>
    ///   Timestamp when the profile was created (UTC, ISO 8601).
    /// </summary>
    CreatedAt: TDateTime;

    /// <summary>
    ///   Timestamp of the last profile update (UTC, ISO 8601).
    /// </summary>
    UpdatedAt: TDateTime;
  end;

  /// <summary>
  ///   Dynamic array of <c>TAuthorDto</c> records.
  /// </summary>
  TAuthorDtoArray = array of TAuthorDto;

  /// <summary>
  ///   Data transfer object for blog posts. Mirrors the <c>TOrmBlogPost</c> fields exposed via the public API.
  ///   An <c>ID</c> of 0 indicates that no record was found.
  /// </summary>
  TPostDto = packed record
  public
    /// <summary>
    ///   Unique post identifier (SQLite RowID).
    /// </summary>
    ID: TID;

    /// <summary>
    ///   Post title.
    /// </summary>
    Title: RawUtf8;

    /// <summary>
    ///   URL-friendly identifier, auto-generated from <c>Title</c>.
    /// </summary>
    Slug: RawUtf8;

    /// <summary>
    ///   Full post content (HTML or plain text).
    /// </summary>
    Body: RawUtf8;

    /// <summary>
    ///   Short teaser text for post listings.
    /// </summary>
    Excerpt: RawUtf8;

    /// <summary>
    ///   Foreign key to the author who wrote this post.
    /// </summary>
    AuthorId: TID;

    /// <summary>
    ///   Foreign key to the featured image media file.
    /// </summary>
    FeaturedImageId: TID;

    /// <summary>
    ///   SEO meta title override.
    /// </summary>
    MetaTitle: RawUtf8;

    /// <summary>
    ///   SEO meta description.
    /// </summary>
    MetaDescription: RawUtf8;

    /// <summary>
    ///   SEO meta keywords (comma-separated).
    /// </summary>
    MetaKeywords: RawUtf8;

    /// <summary>
    ///   Publication status: 0 = draft, 1 = published, 2 = archived.
    /// </summary>
    Status: integer;

    /// <summary>
    ///   Timestamp when the post was first published (UTC, ISO 8601).
    /// </summary>
    PublishedAt: TDateTime;

    /// <summary>
    ///   Timestamp when the post was created (UTC, ISO 8601).
    /// </summary>
    CreatedAt: TDateTime;

    /// <summary>
    ///   Timestamp of the last post update (UTC, ISO 8601).
    /// </summary>
    UpdatedAt: TDateTime;
  end;

  /// <summary>
  ///   Dynamic array of <c>TPostDto</c> records.
  /// </summary>
  TPostDtoArray = array of TPostDto;

  /// <summary>
  ///   Paginated list of blog posts with total count for pagination.
  /// </summary>
  TPostListDto = packed record
  public
    /// <summary>
    ///   Array of posts for the current page.
    /// </summary>
    Items: TPostDtoArray;

    /// <summary>
    ///   Total number of posts matching the filter (across all pages).
    /// </summary>
    Total: integer;

    /// <summary>
    ///   Current page number (1-based).
    /// </summary>
    Page: integer;
  end;

  /// <summary>
  ///   Data transfer object for blog tags. Mirrors the <c>TOrmBlogTag</c> fields exposed via the public API.
  ///   An <c>ID</c> of 0 indicates that no record was found.
  /// </summary>
  TTagDto = packed record
  public
    /// <summary>
    ///   Unique tag identifier (SQLite RowID).
    /// </summary>
    ID: TID;

    /// <summary>
    ///   Tag display name (unique).
    /// </summary>
    Name: RawUtf8;

    /// <summary>
    ///   URL-friendly identifier, auto-generated from <c>Name</c>.
    /// </summary>
    Slug: RawUtf8;

    /// <summary>
    ///   Optional tag description.
    /// </summary>
    Description: RawUtf8;

    /// <summary>
    ///   Timestamp when the tag was created (UTC, ISO 8601).
    /// </summary>
    CreatedAt: TDateTime;
  end;

  /// <summary>
  ///   Dynamic array of <c>TTagDto</c> records.
  /// </summary>
  TTagDtoArray = array of TTagDto;

  /// <summary>
  ///   Data transfer object for blog comments. Mirrors the <c>TOrmBlogComment</c> fields exposed via the public API.
  ///   An <c>ID</c> of 0 indicates that no record was found.
  /// </summary>
  TCommentDto = packed record
  public
    /// <summary>
    ///   Unique comment identifier (SQLite RowID).
    /// </summary>
    ID: TID;

    /// <summary>
    ///   Foreign key to the post this comment belongs to.
    /// </summary>
    PostId: TID;

    /// <summary>
    ///   Display name of the comment author (visitor-supplied).
    /// </summary>
    AuthorName: RawUtf8;

    /// <summary>
    ///   Email address of the comment author (visitor-supplied, optional).
    /// </summary>
    AuthorEmail: RawUtf8;

    /// <summary>
    ///   Comment text content.
    /// </summary>
    Body: RawUtf8;

    /// <summary>
    ///   Moderation status: 0 = pending, 1 = approved, 2 = rejected.
    /// </summary>
    Status: integer;

    /// <summary>
    ///   Foreign key to the author who moderated this comment.
    /// </summary>
    ModeratedBy: TID;

    /// <summary>
    ///   Timestamp when the moderation action occurred (UTC, ISO 8601).
    /// </summary>
    ModeratedAt: TDateTime;

    /// <summary>
    ///   Timestamp when the comment was submitted (UTC, ISO 8601).
    /// </summary>
    CreatedAt: TDateTime;
  end;

  /// <summary>
  ///   Dynamic array of <c>TCommentDto</c> records.
  /// </summary>
  TCommentDtoArray = array of TCommentDto;

  /// <summary>
  ///   Data transfer object for media file metadata. Excludes <c>StoragePath</c> which is an internal implementation
  ///   detail. An <c>ID</c> of 0 indicates that no record was found.
  /// </summary>
  TMediaInfoDto = packed record
  public
    /// <summary>
    ///   Unique media record identifier (SQLite RowID).
    /// </summary>
    ID: TID;

    /// <summary>
    ///   Original file name as uploaded.
    /// </summary>
    FileName: RawUtf8;

    /// <summary>
    ///   MIME type detected from the file extension (e.g. 'image/png').
    /// </summary>
    MimeType: RawUtf8;

    /// <summary>
    ///   File size in bytes.
    /// </summary>
    FileSize: Int64;

    /// <summary>
    ///   Alternative text for accessibility and SEO.
    /// </summary>
    AltText: RawUtf8;

    /// <summary>
    ///   Foreign key to the author who uploaded this file.
    /// </summary>
    UploadedBy: TID;

    /// <summary>
    ///   Timestamp when the file was uploaded (UTC, ISO 8601).
    /// </summary>
    CreatedAt: TDateTime;
  end;

  // -----------------------------------------------------------------------
  //  Input DTO Records -- for Add/Create methods
  // -----------------------------------------------------------------------

  /// <summary>
  ///   Input record for creating a new author profile. <c>DisplayName</c> is required.
  /// </summary>
  TAuthorCreateDto = packed record
  public
    /// <summary>
    ///   Author's display name (required, must not be empty).
    /// </summary>
    DisplayName: RawUtf8;

    /// <summary>
    ///   Biographical text (optional).
    /// </summary>
    Bio: RawUtf8;

    /// <summary>
    ///   Website URL (optional).
    /// </summary>
    WebsiteUrl: RawUtf8;
  end;

  /// <summary>
  ///   Input record for creating a new blog post. <c>Title</c> is required.
  /// </summary>
  TPostCreateDto = packed record
  public
    /// <summary>
    ///   Post title (required, must not be empty).
    /// </summary>
    Title: RawUtf8;

    /// <summary>
    ///   Full post content (optional).
    /// </summary>
    Body: RawUtf8;

    /// <summary>
    ///   Short teaser text (optional).
    /// </summary>
    Excerpt: RawUtf8;

    /// <summary>
    ///   Foreign key to the author.
    /// </summary>
    AuthorId: TID;

    /// <summary>
    ///   Foreign key to the featured image.
    /// </summary>
    FeaturedImageId: TID;

    /// <summary>
    ///   SEO meta title (optional).
    /// </summary>
    MetaTitle: RawUtf8;

    /// <summary>
    ///   SEO meta description (optional).
    /// </summary>
    MetaDescription: RawUtf8;

    /// <summary>
    ///   SEO meta keywords (optional, comma-separated).
    /// </summary>
    MetaKeywords: RawUtf8;

    /// <summary>
    ///   Publication status: 0 = draft, 1 = published.
    /// </summary>
    Status: integer;
  end;

  /// <summary>
  ///   Input record for creating a new tag. <c>Name</c> is required and must be unique.
  /// </summary>
  TTagCreateDto = packed record
  public
    /// <summary>
    ///   Tag display name (required, unique).
    /// </summary>
    Name: RawUtf8;

    /// <summary>
    ///   Optional tag description.
    /// </summary>
    Description: RawUtf8;
  end;

  /// <summary>
  ///   Input record for adding a new comment. <c>Body</c> is required.
  /// </summary>
  TCommentCreateDto = packed record
  public
    /// <summary>
    ///   Display name of the comment author (optional).
    /// </summary>
    AuthorName: RawUtf8;

    /// <summary>
    ///   Email address of the comment author (optional).
    /// </summary>
    AuthorEmail: RawUtf8;

    /// <summary>
    ///   Comment text content (required, must not be empty).
    /// </summary>
    Body: RawUtf8;
  end;

  // -----------------------------------------------------------------------
  //  Composite DTO Records -- enriched/aggregated types
  // -----------------------------------------------------------------------

  /// <summary>
  ///   Fully enriched blog post with nested author, tags, and comments. Used by the gateway aggregation service and
  ///   the analytics service for cross-service JOINs.
  /// </summary>
  TPostFullDto = packed record
  public
    /// <summary>
    ///   Unique post identifier.
    /// </summary>
    ID: TID;

    /// <summary>
    ///   Post title.
    /// </summary>
    Title: RawUtf8;

    /// <summary>
    ///   URL-friendly identifier.
    /// </summary>
    Slug: RawUtf8;

    /// <summary>
    ///   Full post content.
    /// </summary>
    Body: RawUtf8;

    /// <summary>
    ///   Short teaser text.
    /// </summary>
    Excerpt: RawUtf8;

    /// <summary>
    ///   Foreign key to the author.
    /// </summary>
    AuthorId: TID;

    /// <summary>
    ///   Foreign key to the featured image.
    /// </summary>
    FeaturedImageId: TID;

    /// <summary>
    ///   SEO meta title.
    /// </summary>
    MetaTitle: RawUtf8;

    /// <summary>
    ///   SEO meta description.
    /// </summary>
    MetaDescription: RawUtf8;

    /// <summary>
    ///   SEO meta keywords.
    /// </summary>
    MetaKeywords: RawUtf8;

    /// <summary>
    ///   Publication status.
    /// </summary>
    Status: integer;

    /// <summary>
    ///   Timestamp when the post was first published.
    /// </summary>
    PublishedAt: TDateTime;

    /// <summary>
    ///   Timestamp when the post was created.
    /// </summary>
    CreatedAt: TDateTime;

    /// <summary>
    ///   Timestamp of the last post update.
    /// </summary>
    UpdatedAt: TDateTime;

    /// <summary>
    ///   Nested author profile. <c>ID = 0</c> if the author was not found.
    /// </summary>
    Author: TAuthorDto;

    /// <summary>
    ///   Tags assigned to this post. Empty array if none.
    /// </summary>
    Tags: TTagDtoArray;

    /// <summary>
    ///   Approved comments on this post (limited to 10 in analytics). Empty array if none.
    /// </summary>
    Comments: TCommentDtoArray;

    /// <summary>
    ///   True if the users service was unreachable when enriching this post.
    /// </summary>
    AuthorUnavailable: boolean;

    /// <summary>
    ///   True if the tags service was unreachable when enriching this post.
    /// </summary>
    TagsUnavailable: boolean;

    /// <summary>
    ///   True if the comments service was unreachable when enriching this post.
    /// </summary>
    CommentsUnavailable: boolean;
  end;

  /// <summary>
  ///   Dynamic array of <c>TPostFullDto</c> records.
  /// </summary>
  TPostFullDtoArray = array of TPostFullDto;

  /// <summary>
  ///   Blog post enriched with author information only (no tags or comments). Used by
  ///   <c>IBlog.GetPostsByTag</c> where tags are implicit and comments are not needed.
  /// </summary>
  TPostWithAuthorDto = packed record
  public
    /// <summary>
    ///   Unique post identifier.
    /// </summary>
    ID: TID;

    /// <summary>
    ///   Post title.
    /// </summary>
    Title: RawUtf8;

    /// <summary>
    ///   URL-friendly identifier.
    /// </summary>
    Slug: RawUtf8;

    /// <summary>
    ///   Full post content.
    /// </summary>
    Body: RawUtf8;

    /// <summary>
    ///   Short teaser text.
    /// </summary>
    Excerpt: RawUtf8;

    /// <summary>
    ///   Foreign key to the author.
    /// </summary>
    AuthorId: TID;

    /// <summary>
    ///   Foreign key to the featured image.
    /// </summary>
    FeaturedImageId: TID;

    /// <summary>
    ///   SEO meta title.
    /// </summary>
    MetaTitle: RawUtf8;

    /// <summary>
    ///   SEO meta description.
    /// </summary>
    MetaDescription: RawUtf8;

    /// <summary>
    ///   SEO meta keywords.
    /// </summary>
    MetaKeywords: RawUtf8;

    /// <summary>
    ///   Publication status.
    /// </summary>
    Status: integer;

    /// <summary>
    ///   Timestamp when the post was first published.
    /// </summary>
    PublishedAt: TDateTime;

    /// <summary>
    ///   Timestamp when the post was created.
    /// </summary>
    CreatedAt: TDateTime;

    /// <summary>
    ///   Timestamp of the last post update.
    /// </summary>
    UpdatedAt: TDateTime;

    /// <summary>
    ///   Nested author profile. <c>ID = 0</c> if the author was not found.
    /// </summary>
    Author: TAuthorDto;

    /// <summary>
    ///   True if the users service was unreachable when enriching this post.
    /// </summary>
    AuthorUnavailable: boolean;
  end;

  /// <summary>
  ///   Dynamic array of <c>TPostWithAuthorDto</c> records.
  /// </summary>
  TPostWithAuthorDtoArray = array of TPostWithAuthorDto;

  /// <summary>
  ///   Result of <c>IBlog.GetPostsByTag</c>: a tag with its associated posts enriched with author data.
  ///   <c>Tag.ID = 0</c> indicates that the tag was not found.
  /// </summary>
  TPostsByTagDto = packed record
  public
    /// <summary>
    ///   The tag that was looked up.
    /// </summary>
    Tag: TTagDto;

    /// <summary>
    ///   Published posts with this tag, each enriched with author data.
    /// </summary>
    Posts: TPostWithAuthorDtoArray;
  end;

  // -----------------------------------------------------------------------
  //  Analytics DTO Records
  // -----------------------------------------------------------------------

  /// <summary>
  ///   Aggregate counts from all services. Fields set to -1 indicate that the corresponding service was unavailable.
  /// </summary>
  TOverviewDto = packed record
  public
    /// <summary>
    ///   Total number of blog posts (all statuses).
    /// </summary>
    Posts: integer;

    /// <summary>
    ///   Total number of registered authors.
    /// </summary>
    Authors: integer;

    /// <summary>
    ///   Total number of tags.
    /// </summary>
    Tags: integer;

    /// <summary>
    ///   Number of comments awaiting moderation.
    /// </summary>
    PendingComments: integer;

    /// <summary>
    ///   True if the posts service was unreachable.
    /// </summary>
    PostsUnavailable: boolean;

    /// <summary>
    ///   True if the users service was unreachable.
    /// </summary>
    AuthorsUnavailable: boolean;

    /// <summary>
    ///   True if the tags service was unreachable.
    /// </summary>
    TagsUnavailable: boolean;

    /// <summary>
    ///   True if the comments service was unreachable.
    /// </summary>
    CommentsUnavailable: boolean;
  end;

  /// <summary>
  ///   Per-author statistics with post count and total comment count across all their posts.
  /// </summary>
  TAuthorStatDto = packed record
  public
    /// <summary>
    ///   Author identifier.
    /// </summary>
    AuthorId: TID;

    /// <summary>
    ///   Author's display name.
    /// </summary>
    DisplayName: RawUtf8;

    /// <summary>
    ///   Number of posts by this author.
    /// </summary>
    PostCount: integer;

    /// <summary>
    ///   Total number of approved comments on this author's posts.
    /// </summary>
    CommentCount: integer;
  end;

  /// <summary>
  ///   Dynamic array of <c>TAuthorStatDto</c> records.
  /// </summary>
  TAuthorStatDtoArray = array of TAuthorStatDto;

  /// <summary>
  ///   Tag with usage count for the tag cloud visualization.
  /// </summary>
  TTagCloudItemDto = packed record
  public
    /// <summary>
    ///   Tag identifier.
    /// </summary>
    TagId: TID;

    /// <summary>
    ///   Tag display name.
    /// </summary>
    Name: RawUtf8;

    /// <summary>
    ///   URL-friendly tag identifier.
    /// </summary>
    Slug: RawUtf8;

    /// <summary>
    ///   Number of posts using this tag.
    /// </summary>
    PostCount: integer;
  end;

  /// <summary>
  ///   Dynamic array of <c>TTagCloudItemDto</c> records.
  /// </summary>
  TTagCloudItemDtoArray = array of TTagCloudItemDto;

  /// <summary>
  ///   Post ranked by comment count for the "top commented" list.
  /// </summary>
  TTopCommentedPostDto = packed record
  public
    /// <summary>
    ///   Post identifier.
    /// </summary>
    PostId: TID;

    /// <summary>
    ///   Post title.
    /// </summary>
    Title: RawUtf8;

    /// <summary>
    ///   Number of approved comments on this post.
    /// </summary>
    CommentCount: integer;
  end;

  /// <summary>
  ///   Dynamic array of <c>TTopCommentedPostDto</c> records.
  /// </summary>
  TTopCommentedPostDtoArray = array of TTopCommentedPostDto;

  /// <summary>
  ///   Comment activity overview: pending comment count and top commented posts.
  /// </summary>
  TCommentActivityDto = packed record
  public
    /// <summary>
    ///   Number of comments awaiting moderation.
    /// </summary>
    PendingCount: integer;

    /// <summary>
    ///   Top 10 posts ranked by number of approved comments (descending).
    /// </summary>
    TopCommentedPosts: TTopCommentedPostDtoArray;
  end;

  // -----------------------------------------------------------------------
  //  Central Logging DTOs (ms.logs)
  // -----------------------------------------------------------------------

  /// <summary>
  ///   Single log entry as shipped from a producing service to <c>ms.logs</c>. The correlation ID is intentionally
  ///   not a separate field -- it is parsed out of <c>Message</c> on the server side, since the existing
  ///   <c>LogWithCorrelation</c> helper already prepends it.
  /// </summary>
  TLogEntryIngestDto = packed record
  public
    /// <summary>
    ///   The producing service identifier (e.g. <c>ms.posts</c>).
    /// </summary>
    ServiceName: RawUtf8;

    /// <summary>
    ///   When the log line was emitted (UTC).
    /// </summary>
    Timestamp: TDateTime;

    /// <summary>
    ///   <c>TSynLogLevel</c> ordinal -- 0=none, 1=info, ..., see mormot.core.log.
    /// </summary>
    Level: integer;

    /// <summary>
    ///   The full log line text. May contain a leading <c>[correlation-id]</c> prefix added by
    ///   <c>LogWithCorrelation</c>.
    /// </summary>
    Message: RawUtf8;
  end;

  /// <summary>
  ///   Dynamic array of <c>TLogEntryIngestDto</c> records used for batched ingestion.
  /// </summary>
  TLogEntryIngestDtoArray = array of TLogEntryIngestDto;

  /// <summary>
  ///   Single log entry as returned to query clients (browser, gateway). Carries the parsed correlation ID
  ///   and the persistent record ID.
  /// </summary>
  TLogEntryDto = packed record
  public
    /// <summary>
    ///   Persistent record identifier.
    /// </summary>
    ID: TID;

    /// <summary>
    ///   Producing service name.
    /// </summary>
    ServiceName: RawUtf8;

    /// <summary>
    ///   Timestamp when the entry was logged (UTC).
    /// </summary>
    Timestamp: TDateTime;

    /// <summary>
    ///   <c>TSynLogLevel</c> ordinal.
    /// </summary>
    Level: integer;

    /// <summary>
    ///   Correlation ID extracted from the message text, or empty if none was present.
    /// </summary>
    CorrelationId: RawUtf8;

    /// <summary>
    ///   The full log line text.
    /// </summary>
    Message: RawUtf8;
  end;

  /// <summary>
  ///   Dynamic array of <c>TLogEntryDto</c> records returned by query methods.
  /// </summary>
  TLogEntryDtoArray = array of TLogEntryDto;

  /// <summary>
  ///   Filter parameters for the <c>Recent</c> query. Empty/zero fields disable the corresponding filter.
  /// </summary>
  TLogQueryFilter = packed record
  public
    /// <summary>
    ///   Optional service name filter (exact match). Empty = all services.
    /// </summary>
    ServiceName: RawUtf8;

    /// <summary>
    ///   Optional minimum level (inclusive). 0 = no level filter.
    /// </summary>
    MinLevel: integer;

    /// <summary>
    ///   Optional lower bound on timestamp (UTC). 0 = no lower bound.
    /// </summary>
    Since: TDateTime;

    /// <summary>
    ///   Optional upper bound on timestamp (UTC). 0 = no upper bound.
    /// </summary>
    UntilTime: TDateTime;

    /// <summary>
    ///   Maximum rows to return. Clamped to 1..1000 server-side. 0 falls back to the default of 100.
    /// </summary>
    Limit: integer;
  end;

  /// <summary>
  ///   Aggregate counts grouped by service and severity, used by the dashboard tile.
  /// </summary>
  TLogServiceStatDto = packed record
  public
    /// <summary>
    ///   The producing service.
    /// </summary>
    ServiceName: RawUtf8;

    /// <summary>
    ///   Total entries from this service.
    /// </summary>
    TotalCount: integer;

    /// <summary>
    ///   Number of warning entries.
    /// </summary>
    WarningCount: integer;

    /// <summary>
    ///   Number of error entries.
    /// </summary>
    ErrorCount: integer;
  end;

  /// <summary>
  ///   Dynamic array of <c>TLogServiceStatDto</c>.
  /// </summary>
  TLogServiceStatDtoArray = array of TLogServiceStatDto;

  /// <summary>
  ///   Snapshot of the central log store: total entries, oldest/newest timestamps, per-service breakdown.
  /// </summary>
  TLogStatsDto = packed record
  public
    /// <summary>
    ///   Total number of stored log entries.
    /// </summary>
    TotalEntries: integer;

    /// <summary>
    ///   Timestamp of the oldest entry in the store, or 0 if empty.
    /// </summary>
    OldestEntry: TDateTime;

    /// <summary>
    ///   Timestamp of the most recent entry, or 0 if empty.
    /// </summary>
    NewestEntry: TDateTime;

    /// <summary>
    ///   Per-service breakdown.
    /// </summary>
    Services: TLogServiceStatDtoArray;
  end;

  // -----------------------------------------------------------------------
  //  Service Interfaces
  // -----------------------------------------------------------------------

  /// <summary>
  ///   Authentication service contract using SCRAM-MCF protocol. Implements a two-phase challenge/authenticate flow
  ///   where the client computes PBKDF2 locally -- the plaintext password is never transmitted over the wire.
  /// </summary>
  IAuth = interface(IInvokable)
    ['{F1D2E3C4-5A6B-7C8D-9E0F-1A2B3C4D5E6F}']

    /// <summary>
    ///   Phase 1 of SCRAM-MCF login. Returns the MCF format info (algorithm, rounds, salt) and a one-time server nonce.
    ///   For unknown emails, returns fake MCF info to prevent user enumeration attacks.
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
    ///   Phase 2 of SCRAM-MCF login. Verifies the client's cryptographic proof and returns a JWT token on success, plus
    ///   a server proof for mutual authentication.
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
    ///   Creates a new authentication account. Stores the email together with the PBKDF2-derived credentials (MCF hash
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
    ///   The UserId on success, 0 if the email is already taken or input is invalid.
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
  ///   User/author profile service. Provides CRUD operations for author profiles (display name, bio, website).
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
    ///   Author profile data. <c>ID = 0</c> if not found.
    /// </returns>
    function Get(
      aId: TID
      ): TAuthorDto;

    /// <summary>
    ///   Retrieves all author profiles.
    /// </summary>
    /// <returns>
    ///   Array of all author profiles, or empty array if none exist.
    /// </returns>
    function GetAll: TAuthorDtoArray;

    /// <summary>
    ///   Creates a new author profile.
    /// </summary>
    /// <param name="aData">
    ///   Author data with at least <c>DisplayName</c> (required).
    /// </param>
    /// <returns>
    ///   The new record ID, or 0 if validation failed.
    /// </returns>
    function Add(
      const aData: TAuthorCreateDto
      ): TID;

    /// <summary>
    ///   Partially updates an existing author profile. Only fields present in the JSON are modified.
    /// </summary>
    /// <param name="aId">
    ///   The author's record ID.
    /// </param>
    /// <param name="aData">
    ///   JSON object with fields to update (PATCH semantics).
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
  ///   Blog post service. Provides CRUD with pagination, filtering by status and author, and URL slug-based lookup.
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
    ///   Post data. <c>ID = 0</c> if not found.
    /// </returns>
    function Get(
      aId: TID
      ): TPostDto;

    /// <summary>
    ///   Retrieves a single post by its URL-friendly slug.
    /// </summary>
    /// <param name="aSlug">
    ///   The slug to look up (e.g. 'my-first-post').
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
    ///   Page number (1-based). Clamped to >= 1.
    /// </param>
    /// <param name="aLimit">
    ///   Items per page (clamped to 1..100).
    /// </param>
    /// <param name="aStatus">
    ///   Filter by status (0=all, 1=published, 2=archived).
    /// </param>
    /// <param name="aAuthorId">
    ///   Filter by author. Pass 0 to include all authors.
    /// </param>
    /// <returns>
    ///   Paginated result with items array, total count, and current page.
    /// </returns>
    function GetList(
      aPage, aLimit, aStatus: integer;
      aAuthorId: TID
      ): TPostListDto;

    /// <summary>
    ///   Creates a new blog post. The slug is auto-generated from the title via <c>TextToSlug</c>.
    /// </summary>
    /// <param name="aData">
    ///   Post data with at least <c>Title</c> (required).
    /// </param>
    /// <returns>
    ///   The new record ID, or 0 if validation failed.
    /// </returns>
    function Add(
      const aData: TPostCreateDto
      ): TID;

    /// <summary>
    ///   Partially updates an existing post. If the title changes, the slug is regenerated automatically.
    /// </summary>
    /// <param name="aId">
    ///   The post's record ID.
    /// </param>
    /// <param name="aData">
    ///   JSON object with fields to update (PATCH semantics).
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
  ///   Tag service. Manages tags and many-to-many post-tag associations via a junction table (TOrmPostTag).
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
    ///   Tag data. <c>ID = 0</c> if not found.
    /// </returns>
    function Get(
      aId: TID
      ): TTagDto;

    /// <summary>
    ///   Retrieves all tags.
    /// </summary>
    /// <returns>
    ///   Array of all tags, or empty array if none exist.
    /// </returns>
    function GetAll: TTagDtoArray;

    /// <summary>
    ///   Retrieves all tags assigned to a specific post.
    /// </summary>
    /// <param name="aPostId">
    ///   The post's record ID.
    /// </param>
    /// <returns>
    ///   Array of tags assigned to the post, or empty array if none.
    /// </returns>
    function GetByPost(
      aPostId: TID
      ): TTagDtoArray;

    /// <summary>
    ///   Retrieves all post IDs that have a specific tag assigned.
    /// </summary>
    /// <param name="aTagId">
    ///   The tag's record ID.
    /// </param>
    /// <returns>
    ///   Array of post IDs, or empty array if none.
    /// </returns>
    function GetPostIds(
      aTagId: TID
      ): TIDDynArray;

    /// <summary>
    ///   Replaces all tag assignments for a post. Deletes existing associations and creates new ones from the provided
    ///   tag IDs.
    /// </summary>
    /// <param name="aPostId">
    ///   The post to assign tags to.
    /// </param>
    /// <param name="aTagIds">
    ///   JSON array of tag IDs, e.g. '[1,3,5]'.
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
    ///   Tag data with at least <c>Name</c> (required, unique).
    /// </param>
    /// <returns>
    ///   The new record ID, or 0 if validation or UNIQUE constraint failed.
    /// </returns>
    function Add(
      const aData: TTagCreateDto
      ): TID;

    /// <summary>
    ///   Partially updates an existing tag. If the name changes, the slug is regenerated automatically.
    /// </summary>
    /// <param name="aId">
    ///   The tag's record ID.
    /// </param>
    /// <param name="aData">
    ///   JSON object with fields to update (PATCH semantics).
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
  ///   Comment service with moderation workflow. Comments start as pending, and must be approved or rejected by an
  ///   author before they appear publicly.
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
    ///   Array of approved comments, or empty array if none.
    /// </returns>
    function GetByPost(
      aPostId: TID
      ): TCommentDtoArray;

    /// <summary>
    ///   Retrieves all comments awaiting moderation.
    /// </summary>
    /// <returns>
    ///   Array of pending comments, or empty array if none.
    /// </returns>
    function GetPending: TCommentDtoArray;

    /// <summary>
    ///   Adds a new comment to a post (status: pending). Visitors can comment without authentication.
    /// </summary>
    /// <param name="aPostId">
    ///   The post to comment on (must be > 0).
    /// </param>
    /// <param name="aData">
    ///   Comment data with at least <c>Body</c> (required).
    /// </param>
    /// <returns>
    ///   The new comment ID, or 0 if validation failed.
    /// </returns>
    function Add(
      aPostId: TID;
      const aData: TCommentCreateDto
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
  ///   Media service for file uploads. Files are uploaded as Base64-encoded strings, stored on the file system, with
  ///   metadata tracked in the database.
  /// </summary>
  IMedia = interface(IInvokable)
    ['{E6F7A8B9-0C1D-2E3F-4A5B-6C7D8E9FA0B1}']

    /// <summary>
    ///   Uploads a media file. The file data is Base64-encoded and decoded server-side. Maximum size: 3 MB after
    ///   decoding.
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
    ///   The new media record ID, or 0 if validation failed or the file exceeds the size limit.
    /// </returns>
    function Upload(
      const aFileName, aFileData, aAltText: RawUtf8;
      aUploadedBy: TID
      ): TID;

    /// <summary>
    ///   Retrieves metadata for a media file (name, MIME type, size, alt text) without the file content.
    /// </summary>
    /// <param name="aId">
    ///   The media record ID.
    /// </param>
    /// <returns>
    ///   Media metadata. <c>ID = 0</c> if not found.
    /// </returns>
    function GetInfo(
      aId: TID
      ): TMediaInfoDto;

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
    ///   Deletes a media file from both the database and the file system.
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
  ///   Gateway aggregation service. Enriches a single post with data from multiple backend services (author profile,
  ///   tags, approved comments) into one combined response. This is the only service with actual business logic
  ///   in the gateway -- all other interfaces are proxied directly.
  /// </summary>
  IBlog = interface(IInvokable)
    ['{F7A8B9C0-1D2E-3F4A-5B6C-7D8E9FA0B1C2}']

    /// <summary>
    ///   Returns a fully enriched blog post: post data plus nested Author object, Tags array, and Comments array.
    /// </summary>
    /// <param name="aId">
    ///   The post's record ID.
    /// </param>
    /// <returns>
    ///   Aggregated post data. <c>ID = 0</c> if the post was not found.
    /// </returns>
    function GetPostFull(
      aId: TID
      ): TPostFullDto;

    /// <summary>
    ///   Returns a list of posts that have a specific tag assigned, enriched with author information.
    /// </summary>
    /// <param name="aTagId">
    ///   The tag's record ID to filter by.
    /// </param>
    /// <returns>
    ///   Tag info and posts array. <c>Tag.ID = 0</c> if the tag was not found.
    /// </returns>
    function GetPostsByTag(
      aTagId: TID
      ): TPostsByTagDto;
  end;

  /// <summary>
  ///   Configuration service providing centralized setup options for all other microservices. Returns schema-less JSON
  ///   because the configuration structure varies per service and evolves independently.
  /// </summary>
  IConfig = interface(IInvokable)
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}']

    /// <summary>
    ///   Returns the configuration for a specific service.
    /// </summary>
    /// <param name="aServiceName">
    ///   Service identifier (e.g. 'ms.auth').
    /// </param>
    /// <returns>
    ///   JSON object with all config fields, or '{}' if unknown.
    /// </returns>
    function GetServiceConfig(
      const aServiceName: RawUtf8
      ): RawJson;

    /// <summary>
    ///   Returns the complete configuration for all services.
    /// </summary>
    /// <returns>
    ///   JSON object keyed by service name.
    /// </returns>
    function GetAllConfigs: RawJson;

    /// <summary>
    ///   Returns the service registry (Host + Port only). Does not include secrets or database paths.
    /// </summary>
    /// <returns>
    ///   JSON object keyed by service name, each with Host and Port.
    /// </returns>
    function GetServiceRegistry: RawJson;
  end;

  /// <summary>
  ///   Analytics service for cross-service data aggregation. Demonstrates how to combine data from multiple
  ///   microservices -- the equivalent of SQL JOINs across service boundaries.
  /// </summary>
  IAnalytics = interface(IInvokable)
    ['{B1C2D3E4-F5A6-7B8C-9D0E-1F2A3B4C5D6E}']

    /// <summary>
    ///   Returns aggregate counts from all services: total posts, authors, tags, and pending comments.
    /// </summary>
    /// <returns>
    ///   Overview with count fields and <c>*Unavailable</c> flags for unreachable services.
    /// </returns>
    function GetOverview: TOverviewDto;

    /// <summary>
    ///   Returns per-author statistics: post count and total comment count on their posts.
    /// </summary>
    /// <returns>
    ///   Array of author stat records, or empty array if the users service is unavailable.
    /// </returns>
    function GetAuthorStats: TAuthorStatDtoArray;

    /// <summary>
    ///   Returns all tags ranked by the number of posts that use them. Demonstrates grouped counting across services.
    /// </summary>
    /// <returns>
    ///   Array of tag cloud items sorted descending by usage.
    /// </returns>
    function GetTagCloud: TTagCloudItemDtoArray;

    /// <summary>
    ///   Returns comment activity: pending count and the top commented posts.
    /// </summary>
    /// <returns>
    ///   Comment activity overview with pending count and top 10 most-commented posts.
    /// </returns>
    function GetCommentActivity: TCommentActivityDto;

    /// <summary>
    ///   Returns the most recent published posts, each enriched with author, tags, and up to 10 comments. This is the
    ///   cross-service JOIN equivalent -- the key teaching method.
    /// </summary>
    /// <param name="aLimit">
    ///   Maximum number of posts to return (clamped to 1..50). Pass 0 for empty result.
    /// </param>
    /// <returns>
    ///   Array of enriched post records, or empty array if unavailable or limit is 0.
    /// </returns>
    function GetRecentPostsFull(
      aLimit: integer
      ): TPostFullDtoArray;
  end;

  /// <summary>
  ///   Write-side of the central logging service. Producing services ship batches of log entries here from a
  ///   background thread to keep the calling thread non-blocking.
  /// </summary>
  ILogIngestion = interface(IInvokable)
    ['{C2D3E4F5-A6B7-8C9D-0E1F-2A3B4C5D6E7F}']

    /// <summary>
    ///   Appends a batch of log entries from a single producing service.
    /// </summary>
    /// <param name="aEntries">
    ///   The entries to persist. Each one carries its own service name, timestamp, level and message text.
    /// </param>
    procedure AppendBatch(
      const aEntries: TLogEntryIngestDtoArray
      );
  end;

  /// <summary>
  ///   Read-side of the central logging service. Used by the gateway/browser to retrieve and search log entries
  ///   across all microservices.
  /// </summary>
  ILogQuery = interface(IInvokable)
    ['{D3E4F5A6-B7C8-9D0E-1F2A-3B4C5D6E7F8A}']

    /// <summary>
    ///   Returns every log entry that belongs to one user request, identified by its correlation ID.
    /// </summary>
    /// <param name="aId">
    ///   The correlation ID to look up.
    /// </param>
    /// <returns>
    ///   Matching entries sorted by timestamp ascending. Empty array if none found.
    /// </returns>
    function ByCorrelationId(
      const aId: RawUtf8
      ): TLogEntryDtoArray;

    /// <summary>
    ///   Returns recent log entries matching the supplied filter.
    /// </summary>
    /// <param name="aFilter">
    ///   Filter parameters. Empty/zero fields disable the corresponding filter.
    /// </param>
    /// <returns>
    ///   Matching entries sorted by timestamp descending.
    /// </returns>
    function Recent(
      const aFilter: TLogQueryFilter
      ): TLogEntryDtoArray;

    /// <summary>
    ///   Full-text search across the message column using SQLite FTS5.
    /// </summary>
    /// <param name="aText">
    ///   The FTS5 match expression (typically just words).
    /// </param>
    /// <param name="aLimit">
    ///   Maximum rows to return (clamped to 1..1000).
    /// </param>
    /// <returns>
    ///   Matching entries sorted by timestamp descending.
    /// </returns>
    function Search(
      const aText: RawUtf8;
      aLimit: integer
      ): TLogEntryDtoArray;

    /// <summary>
    ///   Returns aggregate counts for the dashboard tile: total entries, time range, per-service breakdown.
    /// </summary>
    /// <returns>
    ///   The current statistics snapshot.
    /// </returns>
    function Stats: TLogStatsDto;
  end;

  /// <summary>
  ///   Server-to-client callback interface used by <c>ILogStream</c> to push new log entries to subscribers in
  ///   real time. The framework transports each call over the persistent WebSocket connection between client and
  ///   server (binary protocol for service-to-service, JSON protocol for browsers).
  /// </summary>
  ILogStreamCallback = interface(IInvokable)
    ['{1A2B3C4D-5E6F-7A8B-9C0D-1E2F3A4B5C6D}']

    /// <summary>
    ///   Invoked by the server every time a new log entry is persisted by the central logging service. The
    ///   subscriber receives the entry on its own thread; mORMot2 serializes calls per subscriber when the
    ///   service is registered with <c>optExecLockedPerInterface</c>.
    /// </summary>
    /// <param name="aEntry">
    ///   The log entry exactly as it was persisted to the central store.
    /// </param>
    procedure NotifyEntry(
      const aEntry: TLogEntryDto
      );
  end;

  /// <summary>
  ///   Publish/subscribe interface for the central logging service. Clients call <c>Subscribe</c> with their own
  ///   <c>ILogStreamCallback</c> implementation; the server invokes <c>NotifyEntry</c> on every subscriber for
  ///   each new log entry. The inherited <c>CallbackReleased</c> hook from <c>IServiceWithCallbackReleased</c>
  ///   fires automatically when a subscriber's WebSocket connection drops, so no explicit unregistration is
  ///   required when a client disconnects ungracefully.
  /// </summary>
  ILogStream = interface(IServiceWithCallbackReleased)
    ['{2B3C4D5E-6F7A-8B9C-0D1E-2F3A4B5C6D7E}']

    /// <summary>
    ///   Registers a callback to receive every subsequent log entry. The callback's lifetime is managed by the
    ///   framework via reference counting -- when the calling client releases its reference (or its WebSocket
    ///   connection closes), the server-side <c>CallbackReleased</c> notification fires.
    /// </summary>
    /// <param name="aCallback">
    ///   The subscriber's callback implementation.
    /// </param>
    procedure Subscribe(
      const aCallback: ILogStreamCallback
      );

    /// <summary>
    ///   Removes a previously registered callback. Most clients do not need to call this explicitly because the
    ///   framework cleans up automatically on disconnect; explicit unsubscription is provided for tests and for
    ///   long-running clients that wish to pause notifications without dropping their REST connection.
    /// </summary>
    /// <param name="aCallback">
    ///   The subscriber's callback implementation, identical to the one passed to <c>Subscribe</c>.
    /// </param>
    procedure Unsubscribe(
      const aCallback: ILogStreamCallback
      );
  end;

implementation

initialization
  // Register all DTO record types and their dynamic arrays for mORMot2 RTTI-based JSON serialization.
  // This is required for SOA interface methods to automatically serialize/deserialize these types.
  Rtti.RegisterType(TypeInfo(TAuthorDto));
  Rtti.RegisterType(TypeInfo(TAuthorDtoArray));
  Rtti.RegisterType(TypeInfo(TPostDto));
  Rtti.RegisterType(TypeInfo(TPostDtoArray));
  Rtti.RegisterType(TypeInfo(TPostListDto));
  Rtti.RegisterType(TypeInfo(TTagDto));
  Rtti.RegisterType(TypeInfo(TTagDtoArray));
  Rtti.RegisterType(TypeInfo(TCommentDto));
  Rtti.RegisterType(TypeInfo(TCommentDtoArray));
  Rtti.RegisterType(TypeInfo(TMediaInfoDto));
  Rtti.RegisterType(TypeInfo(TAuthorCreateDto));
  Rtti.RegisterType(TypeInfo(TPostCreateDto));
  Rtti.RegisterType(TypeInfo(TTagCreateDto));
  Rtti.RegisterType(TypeInfo(TCommentCreateDto));
  Rtti.RegisterType(TypeInfo(TPostFullDto));
  Rtti.RegisterType(TypeInfo(TPostFullDtoArray));
  Rtti.RegisterType(TypeInfo(TPostWithAuthorDto));
  Rtti.RegisterType(TypeInfo(TPostWithAuthorDtoArray));
  Rtti.RegisterType(TypeInfo(TPostsByTagDto));
  Rtti.RegisterType(TypeInfo(TOverviewDto));
  Rtti.RegisterType(TypeInfo(TAuthorStatDto));
  Rtti.RegisterType(TypeInfo(TAuthorStatDtoArray));
  Rtti.RegisterType(TypeInfo(TTagCloudItemDto));
  Rtti.RegisterType(TypeInfo(TTagCloudItemDtoArray));
  Rtti.RegisterType(TypeInfo(TTopCommentedPostDto));
  Rtti.RegisterType(TypeInfo(TTopCommentedPostDtoArray));
  Rtti.RegisterType(TypeInfo(TCommentActivityDto));
  Rtti.RegisterType(TypeInfo(TLogEntryIngestDto));
  Rtti.RegisterType(TypeInfo(TLogEntryIngestDtoArray));
  Rtti.RegisterType(TypeInfo(TLogEntryDto));
  Rtti.RegisterType(TypeInfo(TLogEntryDtoArray));
  Rtti.RegisterType(TypeInfo(TLogQueryFilter));
  Rtti.RegisterType(TypeInfo(TLogServiceStatDto));
  Rtti.RegisterType(TypeInfo(TLogServiceStatDtoArray));
  Rtti.RegisterType(TypeInfo(TLogStatsDto));
  // Pre-register the SOA interfaces involved in the WebSocket-callback flow. mORMot2 needs both the
  // service interface (ILogStream) and its callback parameter type (ILogStreamCallback) to be in the
  // global TInterfaceFactory registry BEFORE a Subscribe call arrives, otherwise the server-side
  // TServiceContainerServer.GetFakeCallback raises 'Unexpected ILogStreamCallback' when it tries to
  // materialize the fake instance for the incoming call. Auto-discovery via ServiceRegister covers
  // the parent interface but not callback parameter types, so we register them explicitly here.
  TInterfaceFactory.RegisterInterfaces([
    TypeInfo(ILogStream),
    TypeInfo(ILogStreamCallback)]);

end.
