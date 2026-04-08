/// <summary>
///   ORM model for the Users service: author profiles.
///
///   mORMot2 ORM basics demonstrated here:
///   - Classes descending from <c>TOrm</c> map to SQLite tables.
///     The table name is derived from the class name by stripping
///     the 'TOrm' prefix: <c>TOrmAuthor</c> becomes table 'Author'.
///   - Published properties become table columns. The ORM uses RTTI
///     to auto-create the table schema, read/write records, and
///     serialize to/from JSON.
///   - <c>RawUtf8</c> maps to SQLite TEXT. The optional <c>index N</c>
///     specifier sets the maximum length (VARCHAR(N) equivalent)
///     and creates a size hint for the column.
///   - <c>TID</c> (Int64) maps to SQLite INTEGER. Used for foreign
///     keys referencing records in other services' databases.
///   - <c>TDateTime</c> maps to SQLite TEXT (ISO 8601 format).
///   - <c>stored AS_UNIQUE</c> creates a UNIQUE index on the column,
///     enforced at the SQLite level.
///
///   IMPORTANT naming rule: the class name (minus 'TOrm' prefix)
///   must NOT collide with any SOA interface name (minus 'I' prefix).
///   Example: <c>IUser</c> routes as 'User', so the ORM class is
///   <c>TOrmAuthor</c> (not TOrmUser) to avoid routing conflicts.
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
  ///   ORM record for blog author profiles. Inherits <c>TOrm</c>
  ///   which provides the <c>ID</c> property (SQLite RowID) and
  ///   all ORM infrastructure (CRUD, JSON serialization, etc.).
  ///   Published properties define the SQLite table columns.
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
    ///   <c>index 200</c> sets the maximum text length (VARCHAR(200)
    ///   equivalent in mORMot2's ORM).
    /// </summary>
    property DisplayName: RawUtf8 index 200
      read FDisplayName write FDisplayName;

    /// <summary>
    ///   URL-friendly unique slug, auto-generated from DisplayName
    ///   via <c>TextToSlug</c>. <c>stored AS_UNIQUE</c> creates a
    ///   UNIQUE index in SQLite, preventing duplicate slugs.
    /// </summary>
    property Slug: RawUtf8 index 200
      read FSlug write FSlug stored AS_UNIQUE;

    /// <summary>
    ///   Biographical text describing the author.
    ///   No <c>index</c> specifier = unlimited TEXT length.
    /// </summary>
    property Bio: RawUtf8
      read FBio write FBio;

    /// <summary>
    ///   URL of the author's personal website.
    /// </summary>
    property WebsiteUrl: RawUtf8 index 500
      read FWebsiteUrl write FWebsiteUrl;

    /// <summary>
    ///   Foreign key referencing the author's avatar in ms.media.
    ///   <c>TID</c> is mORMot2's 64-bit integer type for record IDs.
    ///   Cross-service references are stored as plain IDs -- the
    ///   resolution happens in the gateway's aggregation service.
    /// </summary>
    property AvatarMediaId: TID
      read FAvatarMediaId write FAvatarMediaId;

    /// <summary>
    ///   UTC timestamp when the profile was created.
    ///   Stored as ISO 8601 TEXT in SQLite.
    /// </summary>
    property CreatedAt: TDateTime
      read FCreatedAt write FCreatedAt;

    /// <summary>
    ///   UTC timestamp of the last profile update.
    /// </summary>
    property UpdatedAt: TDateTime
      read FUpdatedAt write FUpdatedAt;
  end;

implementation

end.
