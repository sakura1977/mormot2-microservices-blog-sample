/// <summary>
///   ORM model for the Media service: image metadata.
/// </summary>
unit ms.media.model;

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
  ///   Stores metadata for uploaded media files (images, etc.).
  /// </summary>
  TOrmMediaFile = class(TOrm)
  private
    FFileName: RawUtf8;
    FStoragePath: RawUtf8;
    FMimeType: RawUtf8;
    FFileSize: Int64;
    FAltText: RawUtf8;
    FUploadedBy: TID;
    FCreatedAt: TDateTime;
  published

    /// <summary>
    ///   Original file name of the uploaded media.
    /// </summary>
    property FileName: RawUtf8 index 300
      read FFileName write FFileName;

    /// <summary>
    ///   Path where the file is stored on disk or in object storage.
    /// </summary>
    property StoragePath: RawUtf8 index 500
      read FStoragePath write FStoragePath;

    /// <summary>
    ///   MIME type of the media file (e.g. image/png).
    /// </summary>
    property MimeType: RawUtf8 index 100
      read FMimeType write FMimeType;

    /// <summary>
    ///   Size of the file in bytes.
    /// </summary>
    property FileSize: Int64
      read FFileSize write FFileSize;

    /// <summary>
    ///   Alternative text for accessibility purposes.
    /// </summary>
    property AltText: RawUtf8 index 500
      read FAltText write FAltText;

    /// <summary>
    ///   Foreign key referencing the user who uploaded this media.
    /// </summary>
    property UploadedBy: TID
      read FUploadedBy write FUploadedBy;

    /// <summary>
    ///   Timestamp when the media was uploaded.
    /// </summary>
    property CreatedAt: TDateTime
      read FCreatedAt write FCreatedAt;
  end;

implementation

end.
