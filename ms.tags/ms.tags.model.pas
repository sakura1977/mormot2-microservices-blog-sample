/// <summary>
///   ORM models for the Tags service: tags and post-tag assignments.
///
///   Demonstrates the many-to-many (m:n) relationship pattern in
///   mORMot2's ORM: <c>TOrmBlogTag</c> stores the tags, and
///   <c>TOrmPostTag</c> is the junction table linking posts to tags.
///   Both are registered in the same <c>TOrmModel</c> so they share
///   one SQLite database.
///
///   Named <c>TOrmBlogTag</c> (not TOrmTag) to avoid a routing
///   conflict with the <c>ITag</c> SOA interface.
/// </summary>
unit ms.tags.model;

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
  ///   Stores a tag with its unique name and slug.
  /// </summary>
  TOrmBlogTag = class(TOrm)
  private
    FName: RawUtf8;
    FSlug: RawUtf8;
    FDescription: RawUtf8;
    FCreatedAt: TDateTime;
  published

    /// <summary>
    ///   Unique display name of the tag.
    /// </summary>
    property Name: RawUtf8 index 100
      read FName write FName stored AS_UNIQUE;

    /// <summary>
    ///   URL-friendly unique slug for the tag.
    /// </summary>
    property Slug: RawUtf8 index 100
      read FSlug write FSlug stored AS_UNIQUE;

    /// <summary>
    ///   Optional description of the tag.
    /// </summary>
    property Description: RawUtf8
      read FDescription write FDescription;

    /// <summary>
    ///   Timestamp when the tag was created.
    /// </summary>
    property CreatedAt: TDateTime
      read FCreatedAt write FCreatedAt;
  end;

  /// <summary>
  ///   Junction table implementing the many-to-many relationship
  ///   between posts and tags. Each record links one PostId to one
  ///   TagId. mORMot2's ORM creates the SQLite table automatically
  ///   from these published properties.
  /// </summary>
  TOrmPostTag = class(TOrm)
  private
    FPostId: TID;
    FTagId: TID;
  published

    /// <summary>
    ///   Foreign key referencing the associated post.
    /// </summary>
    property PostId: TID
      read FPostId write FPostId;

    /// <summary>
    ///   Foreign key referencing the associated tag.
    /// </summary>
    property TagId: TID
      read FTagId write FTagId;
  end;

implementation

end.
