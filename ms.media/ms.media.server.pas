/// <summary>
///   Interface-based service implementation for the Media microservice. Implements <c>IMedia</c> for file upload,
///   retrieval, and deletion.
///
///   Demonstrates file handling alongside ORM persistence:
///   - Upload flow: Base64-decode the file data, store the binary on the file system, and track metadata (name,
///     MIME type, size, storage path) in SQLite via the ORM.
///   - <c>Base64ToBin</c> / <c>BinToBase64</c>: mORMot2 utilities for binary-to-text encoding (used because SOA
///     parameters are JSON strings, not binary streams).
///   - <c>FileFromString</c> / <c>StringFromFile</c>: mORMot2 one-liner utilities for file I/O without TFileStream.
///   - Upload size limit (<c>MAX_UPLOAD_SIZE</c>) enforced after Base64 decoding to prevent denial-of-service.
///   - <c>GuessMimeType</c>: shared helper (ms.shared.pas) that maps file extensions to MIME types.
///
///   See <c>ms.users.server.pas</c> for detailed explanations of the basic CRUD and JSON parsing patterns used here.
/// </summary>
unit ms.media.server;

{$SCOPEDENUMS ON}
{$I mormot.defines.inc}
{$WARN SYMBOL_PLATFORM OFF}
{$WARN UNIT_PLATFORM OFF}

interface

uses
  System.SysUtils,
  mormot.core.base,
  mormot.core.buffers,
  mormot.core.datetime,
  mormot.core.json,
  mormot.core.os,
  mormot.core.text,
  mormot.core.variants,
  mormot.orm.base,
  mormot.orm.core,
  mormot.rest.core,
  mormot.rest.server,
  mormot.rest.sqlite3,
  mormot.soa.core,
  mormot.soa.server,
  ms.media.model,
  ms.shared,
  ms.shared.api,
  ms.shared.service;

type

  /// <summary>
  ///   Implements the <c>IMedia</c> interface for file upload, retrieval and management of media assets.
  /// </summary>
  TMediaService = class(TInterfacedObject, IMedia)
  strict private
    /// <summary>
    ///   ORM interface used for all database operations on media file records.
    /// </summary>
    FOrm: IRestOrm;

    /// <summary>
    ///   File system path where uploaded media files are stored.
    /// </summary>
    FMediaPath: TFileName;
  public
    /// <summary>
    ///   Creates a new <c>TMediaService</c> instance with the given ORM and media storage path.
    /// </summary>
    /// <param name="aOrm">
    ///   The ORM interface for database access.
    /// </param>
    /// <param name="aMediaPath">
    ///   The file system path where uploaded media files will be stored.
    /// </param>
    constructor Create(
      const aOrm: IRestOrm;
      const aMediaPath: TFileName
      );

    /// <summary>
    ///   Uploads a file by Base64-decoding the data, storing the binary on disk, and tracking metadata in the ORM.
    /// </summary>
    /// <param name="aFileName">
    ///   The original file name of the uploaded file.
    /// </param>
    /// <param name="aFileData">
    ///   The Base64-encoded file content.
    /// </param>
    /// <param name="aAltText">
    ///   An alternative text description for the media file.
    /// </param>
    /// <param name="aUploadedBy">
    ///   The ID of the user who uploaded the file.
    /// </param>
    /// <returns>
    ///   The ID of the newly created media record, or 0 on failure.
    /// </returns>
    function Upload(
      const aFileName, aFileData, aAltText: RawUtf8;
      aUploadedBy: TID
      ): TID;

    /// <summary>
    ///   Retrieves the JSON metadata for a media file identified by its ID.
    /// </summary>
    /// <param name="aId">
    ///   The ID of the media record to retrieve.
    /// </param>
    /// <returns>
    ///   The JSON representation of the media file record.
    /// </returns>
    function GetInfo(
      aId: TID
      ): RawJson;

    /// <summary>
    ///   Retrieves the binary content and MIME type of a media file identified by its ID.
    /// </summary>
    /// <param name="aId">
    ///   The ID of the media record whose file content is requested.
    /// </param>
    /// <param name="aContentType">
    ///   Receives the MIME type of the file on output.
    /// </param>
    /// <returns>
    ///   The raw binary content of the file, or empty string if not found.
    /// </returns>
    function GetFile(
      aId: TID;
      out aContentType: RawUtf8
      ): RawByteString;

    /// <summary>
    ///   Removes a media file record from the database and deletes the corresponding file from disk.
    /// </summary>
    /// <param name="aId">
    ///   The ID of the media record to remove.
    /// </param>
    /// <returns>
    ///   <c>True</c> if the record was found and successfully deleted.
    /// </returns>
    function Remove(
      aId: TID
      ): boolean;
  end;

  /// <summary>
  ///   Microservice server hosting the <c>IMedia</c> service implementation.
  /// </summary>
  TMediaServer = class(TMicroService)
  strict private
    /// <summary>
    ///   The <c>TMediaService</c> instance that implements the <c>IMedia</c> interface.
    /// </summary>
    FMediaImpl: TMediaService;

    /// <summary>
    ///   File system path where uploaded media files are stored on the server.
    /// </summary>
    FMediaPath: TFileName;
  protected
    /// <summary>
    ///   Creates the ORM model containing the <c>TOrmMediaFile</c> table definition.
    /// </summary>
    /// <returns>
    ///   A new <c>TOrmModel</c> instance for the media service.
    /// </returns>
    function CreateModel: TOrmModel; override;

    /// <summary>
    ///   Initializes the media storage directory and registers the <c>IMedia</c> service implementation.
    /// </summary>
    procedure SetupServices; override;
  end;

implementation

constructor TMediaService.Create(
  const aOrm: IRestOrm;
  const aMediaPath: TFileName
  );
begin
  inherited Create;
  FOrm := aOrm;
  FMediaPath := aMediaPath;
end;

function TMediaService.GetFile(
  aId: TID;
  out aContentType: RawUtf8
  ): RawByteString;
var
  Rec: TOrmMediaFile;
  FilePath: TFileName;
begin
  Result := '';
  aContentType := '';
  Rec := TOrmMediaFile.Create;
  try
    if FOrm.Retrieve(aId, Rec) then
    begin
      FilePath := FMediaPath + Utf8ToString(Rec.StoragePath);
      Result := StringFromFile(FilePath);
      aContentType := Rec.MimeType;
    end;
  finally
    Rec.Free;
  end;
end;

function TMediaService.GetInfo(
  aId: TID
  ): RawJson;
begin
  Result := OrmGetById(FOrm, TOrmMediaFile, aId);
end;

function TMediaService.Remove(
  aId: TID
  ): boolean;
var
  Rec: TOrmMediaFile;
  FilePath: TFileName;
begin
  Result := False;
  Rec := TOrmMediaFile.Create;
  try
    if FOrm.Retrieve(aId, Rec) then
    begin
      // Delete file from disk
      FilePath := FMediaPath + Utf8ToString(Rec.StoragePath);
      if FileExists(FilePath) then
        DeleteFile(FilePath);
      Result := FOrm.Delete(TOrmMediaFile, aId);
    end;
  finally
    Rec.Free;
  end;
end;

function TMediaService.Upload(
  const aFileName, aFileData, aAltText: RawUtf8;
  aUploadedBy: TID
  ): TID;
var
  Rec: TOrmMediaFile;
  Content: RawByteString;
  FilePath: TFileName;
begin
  if (aFileName = '') or (aFileData = '') then
    Exit(0);
  Content := Base64ToBin(aFileData);
  if Length(Content) > MAX_UPLOAD_SIZE then
    Exit(0);
  Rec := TOrmMediaFile.Create;
  try
    Rec.FileName := aFileName;
    Rec.MimeType := GuessMimeType(Utf8ToString(aFileName));
    Rec.FileSize := Length(Content);
    Rec.AltText := aAltText;
    Rec.UploadedBy := aUploadedBy;
    Rec.CreatedAt := NowUtc;
    Result := FOrm.Add(Rec, True);
    if Result > 0 then
    begin
      // Save file to disk as {id}_{filename}
      Rec.StoragePath := FormatUtf8('%_%', [Result, aFileName]);
      FilePath := FMediaPath + Utf8ToString(Rec.StoragePath);
      FileFromString(Content, FilePath);
      // Update StoragePath in the database record
      Rec.IDValue := Result;
      FOrm.Update(Rec, 'StoragePath');
    end;
  finally
    Rec.Free;
  end;
end;

function TMediaServer.CreateModel: TOrmModel;
begin
  Result := TOrmModel.Create([TOrmMediaFile], MODEL_ROOT);
end;

procedure TMediaServer.SetupServices;
begin
  FMediaPath := Executable.ProgramFilePath + 'media' + PathDelim;
  if not DirectoryExists(FMediaPath) then
    CreateDir(FMediaPath);
  FMediaImpl := TMediaService.Create(FRestServer.Orm, FMediaPath);
  RegisterService(FMediaImpl, TypeInfo(IMedia));
end;

end.
