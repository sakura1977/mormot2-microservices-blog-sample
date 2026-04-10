/// <summary>
///   ORM model for the Posts service: blog posts.
///
///   Demonstrates several mORMot2 ORM features:
///   - <c>stored AS_UNIQUE</c> on Slug for unique URL-friendly identifiers.
///   - <c>TID</c> foreign keys (AuthorId, FeaturedImageId) referencing
///     records in other services' databases. Cross-service joins are
///     resolved at the gateway level, not in the ORM.
///   - Integer status codes (draft/published/archived) as a simple
///     state machine alternative to enums.
///   - Parallel <c>TOrmBlogPostFts</c> SQLite FTS5 virtual table over
///     Title, Excerpt and Body for full-text search. Kept in sync with
///     <c>TOrmBlogPost</c> by the service layer inside a single
///     transaction per write.
///
///   Named <c>TOrmBlogPost</c> (not TOrmPost) to avoid a routing
///   conflict with the <c>IPost</c> SOA interface.
/// </summary>
unit ms.posts.model;

{$SCOPEDENUMS ON}
{$I mormot.defines.inc}
{$WARN SYMBOL_PLATFORM OFF}
{$WARN UNIT_PLATFORM OFF}

interface

uses
  mormot.core.base,
  mormot.orm.base,
  mormot.orm.core;

type

  /// <summary>
  ///   Stores blog post content, metadata, and publication state.
  /// </summary>
  TOrmBlogPost = class(TOrm)
  private
    FTitle: RawUtf8;
    FSlug: RawUtf8;
    FBody: RawUtf8;
    FExcerpt: RawUtf8;
    FAuthorId: TID;
    FFeaturedImageId: TID;
    FMetaTitle: RawUtf8;
    FMetaDescription: RawUtf8;
    FMetaKeywords: RawUtf8;
    FStatus: integer;
    FPublishedAt: TDateTime;
    FCreatedAt: TDateTime;
    FUpdatedAt: TDateTime;
  published

    /// <summary>
    ///   Title of the blog post.
    /// </summary>
    property Title: RawUtf8 index 300
      read FTitle write FTitle;

    /// <summary>
    ///   URL-friendly unique slug for the post.
    /// </summary>
    property Slug: RawUtf8 index 300
      read FSlug write FSlug stored AS_UNIQUE;

    /// <summary>
    ///   Full body content of the post.
    /// </summary>
    property Body: RawUtf8
      read FBody write FBody;

    /// <summary>
    ///   Short excerpt or teaser text for the post.
    /// </summary>
    property Excerpt: RawUtf8
      read FExcerpt write FExcerpt;

    /// <summary>
    ///   Foreign key referencing the post author.
    /// </summary>
    property AuthorId: TID
      read FAuthorId write FAuthorId;

    /// <summary>
    ///   Foreign key referencing the featured image media entry.
    /// </summary>
    property FeaturedImageId: TID
      read FFeaturedImageId write FFeaturedImageId;

    /// <summary>
    ///   SEO meta title for the post.
    /// </summary>
    property MetaTitle: RawUtf8 index 200
      read FMetaTitle write FMetaTitle;

    /// <summary>
    ///   SEO meta description for the post.
    /// </summary>
    property MetaDescription: RawUtf8 index 500
      read FMetaDescription write FMetaDescription;

    /// <summary>
    ///   SEO meta keywords for the post.
    /// </summary>
    property MetaKeywords: RawUtf8 index 500
      read FMetaKeywords write FMetaKeywords;

    /// <summary>
    ///   Publication status code (e.g. draft, published).
    /// </summary>
    property Status: integer
      read FStatus write FStatus;

    /// <summary>
    ///   Timestamp when the post was published.
    /// </summary>
    property PublishedAt: TDateTime
      read FPublishedAt write FPublishedAt;

    /// <summary>
    ///   Timestamp when the post was created.
    /// </summary>
    property CreatedAt: TDateTime
      read FCreatedAt write FCreatedAt;

    /// <summary>
    ///   Timestamp when the post was last updated.
    /// </summary>
    property UpdatedAt: TDateTime
      read FUpdatedAt write FUpdatedAt;
  end;

  /// <summary>
  ///   Parallel FTS5 virtual table indexing <c>Title</c>, <c>Excerpt</c> and <c>Body</c> of every
  ///   <c>TOrmBlogPost</c>. Rows share the same <c>RowID</c> as the backing post record, so a join
  ///   is a straight <c>RowID IN (...)</c> subquery.
  ///
  ///   mORMot2 maps this class to <c>CREATE VIRTUAL TABLE BlogPostFts USING fts5(Title, Excerpt, Body)</c>
  ///   automatically because the class derives from <c>TOrmFts5</c>. A MATCH without a column prefix
  ///   searches all three columns; <c>Title: word</c> restricts the match to the title.
  /// </summary>
  TOrmBlogPostFts = class(TOrmFts5)
  private
    FTitle: RawUtf8;
    FExcerpt: RawUtf8;
    FBody: RawUtf8;
  published

    /// <summary>
    ///   Indexed title text. Mirrors <c>TOrmBlogPost.Title</c>.
    /// </summary>
    property Title: RawUtf8
      read FTitle write FTitle;

    /// <summary>
    ///   Indexed excerpt text. Mirrors <c>TOrmBlogPost.Excerpt</c>.
    /// </summary>
    property Excerpt: RawUtf8
      read FExcerpt write FExcerpt;

    /// <summary>
    ///   Indexed body text. Mirrors <c>TOrmBlogPost.Body</c>.
    /// </summary>
    property Body: RawUtf8
      read FBody write FBody;
  end;

implementation

end.
