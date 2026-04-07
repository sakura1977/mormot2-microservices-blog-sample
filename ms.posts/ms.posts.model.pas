/// <summary>
///   ORM model for the Posts service: blog posts.
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
///   Creates the ORM model for the Posts service.
/// </summary>
/// <returns>
///   A TOrmModel instance containing TOrmBlogPost.
/// </returns>
function CreatePostsModel: TOrmModel;

implementation

function CreatePostsModel: TOrmModel;
begin
  Result := TOrmModel.Create([TOrmBlogPost]);
end;

end.
