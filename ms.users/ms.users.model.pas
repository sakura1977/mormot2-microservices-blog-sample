/// <summary>
///   ORM model for the Users service: author profiles.
/// </summary>
unit ms.users.model;

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
  ///   Stores author profile information for the blog platform.
  /// </summary>
  TOrmAuthor = class(TOrm)
  private
    FDisplayName: RawUtf8;
    FSlug: RawUtf8;
    FBio: RawUtf8;
    FWebsiteUrl: RawUtf8;
    FAvatarMediaId: TID;
    FCreatedAt: TDateTime;
    FUpdatedAt: TDateTime;
  published

    /// <summary>
    ///   Display name shown publicly for the author.
    /// </summary>
    property DisplayName: RawUtf8 index 200
      read FDisplayName write FDisplayName;

    /// <summary>
    ///   URL-friendly unique slug for the author.
    /// </summary>
    property Slug: RawUtf8 index 200
      read FSlug write FSlug stored AS_UNIQUE;

    /// <summary>
    ///   Biographical text describing the author.
    /// </summary>
    property Bio: RawUtf8
      read FBio write FBio;

    /// <summary>
    ///   URL of the author's personal website.
    /// </summary>
    property WebsiteUrl: RawUtf8 index 500
      read FWebsiteUrl write FWebsiteUrl;

    /// <summary>
    ///   Foreign key referencing the author's avatar media entry.
    /// </summary>
    property AvatarMediaId: TID
      read FAvatarMediaId write FAvatarMediaId;

    /// <summary>
    ///   Timestamp when the author profile was created.
    /// </summary>
    property CreatedAt: TDateTime
      read FCreatedAt write FCreatedAt;

    /// <summary>
    ///   Timestamp when the author profile was last updated.
    /// </summary>
    property UpdatedAt: TDateTime
      read FUpdatedAt write FUpdatedAt;
  end;

implementation

end.
