/// <summary>
///   HTTP server for the Media service.
///   Upload, delivery and management of images.
/// </summary>
unit ms.media.server;

{$SCOPEDENUMS ON}
{$I mormot.defines.inc}
{$WARN SYMBOL_PLATFORM OFF}
{$WARN UNIT_PLATFORM OFF}

interface

uses
  System.Classes,
  System.SysUtils,
  mormot.core.base,
  mormot.core.buffers,
  mormot.core.datetime,
  mormot.core.json,
  mormot.core.os,
  mormot.core.text,
  mormot.core.unicode,
  mormot.core.variants,
  mormot.db.raw.sqlite3,
  mormot.net.http,
  mormot.net.server,
  mormot.orm.base,
  mormot.orm.core,
  mormot.rest.sqlite3,
  ms.media.model,
  ms.shared,
  ms.shared.service;

type

  /// <summary>
  ///   Microservice server handling media upload and retrieval endpoints.
  /// </summary>
  TMediaServer = class(TMicroService)
  private
    FModel: TOrmModel;
    FRest: TRestServerDB;
    FMediaPath: TFileName;

    /// <summary>
    ///   Extracts a numeric ID from a URL path after the given prefix.
    /// </summary>
    /// <param name="aPath">
    ///   The full request URL path.
    /// </param>
    /// <param name="aPrefix">
    ///   The URL prefix before the ID segment.
    /// </param>
    /// <returns>
    ///   The extracted ID value, or 0 if parsing fails.
    /// </returns>
    function ExtractId(
      const aPath, aPrefix: RawUtf8
    ): TID;

    /// <summary>
    ///   Guesses the MIME type based on a file name extension.
    /// </summary>
    /// <param name="aFileName">
    ///   The file name to inspect.
    /// </param>
    /// <returns>
    ///   The guessed MIME type string, or 'application/octet-stream' as fallback.
    /// </returns>
    function GuessMimeType(
      const aFileName: RawUtf8
    ): RawUtf8;
  protected

    /// <summary>
    ///   Initializes the database, ORM model and media storage directory.
    /// </summary>
    procedure DoInitialize; override;

    /// <summary>
    ///   Releases the REST server and ORM model.
    /// </summary>
    procedure DoFinalize; override;

    /// <summary>
    ///   Dispatches incoming HTTP requests to media endpoints.
    /// </summary>
    /// <param name="aCtxt">
    ///   The HTTP request context.
    /// </param>
    /// <returns>
    ///   The HTTP status code for the response.
    /// </returns>
    function OnRequest(
      aCtxt: THttpServerRequestAbstract
    ): cardinal; override;
  end;

implementation

{ TMediaServer }

procedure TMediaServer.DoFinalize;
begin
  FreeAndNil(FRest);
  FreeAndNil(FModel);
end;

procedure TMediaServer.DoInitialize;
var
  DatabasePath: TFileName;
begin
  DatabasePath := Executable.ProgramFilePath + 'media.db';
  FMediaPath := Executable.ProgramFilePath + 'media' + PathDelim;
  if not DirectoryExists(FMediaPath) then
    CreateDir(FMediaPath);
  FModel := CreateMediaModel;
  FRest := TRestServerDB.Create(FModel, DatabasePath);
  FRest.DB.Synchronous := smNormal;
  FRest.DB.LockingMode := lmExclusive;
  FRest.CreateMissingTables;
end;

function TMediaServer.ExtractId(
  const aPath, aPrefix: RawUtf8
): TID;
begin
  Result := GetInt64(pointer(Copy(aPath, Length(aPrefix) + 1, 20)));
end;

function TMediaServer.GuessMimeType(
  const aFileName: RawUtf8
): RawUtf8;
var
  FileExtension: string;
begin
  FileExtension := System.SysUtils.LowerCase(ExtractFileExt(Utf8ToString(aFileName)));
  if FileExtension = '.jpg' then
  begin
    Result := 'image/jpeg';
  end
  else if FileExtension = '.jpeg' then
  begin
    Result := 'image/jpeg';
  end
  else if FileExtension = '.png' then
  begin
    Result := 'image/png';
  end
  else if FileExtension = '.gif' then
  begin
    Result := 'image/gif';
  end
  else if FileExtension = '.webp' then
  begin
    Result := 'image/webp';
  end
  else if FileExtension = '.svg' then
  begin
    Result := 'image/svg+xml';
  end
  else if FileExtension = '.bmp' then
  begin
    Result := 'image/bmp';
  end
  else
  begin
    Result := 'application/octet-stream';
  end;
end;

function TMediaServer.OnRequest(
  aCtxt: THttpServerRequestAbstract
): cardinal;
var
  Path: RawUtf8;
  RecordId, NewId: TID;
  Rec: TOrmMedia;
  Doc: TDocVariantData;
  FilePath: TFileName;
  Content: RawByteString;
begin
  Path := aCtxt.Url;

  // POST /api/media/upload
  if (aCtxt.Method = 'POST') and (Path = '/api/media/upload') then
  begin
    // Simple upload: body is the image file,
    // metadata comes as query parameters or headers
    Doc.InitJson(aCtxt.InContent, JSON_FAST_FLOAT);
    Rec := TOrmMedia.Create;
    try
      Rec.FileName := Doc.U['FileName'];
      if Rec.FileName = '' then
      begin
        Rec.FileName := 'upload.bin';
      end;
      Rec.MimeType := Doc.U['MimeType'];
      if Rec.MimeType = '' then
      begin
        Rec.MimeType := GuessMimeType(Rec.FileName);
      end;
      Rec.AltText := Doc.U['AltText'];
      Rec.UploadedBy := Doc.I['UploadedBy'];
      Rec.CreatedAt := NowUtc;

      // File content (Base64-encoded in the JSON body)
      Content := Base64ToBin(Doc.U['FileData']);
      Rec.FileSize := Length(Content);

      NewId := FRest.Orm.Add(Rec, True);
      if NewId > 0 then
      begin
        // Save file to disk
        Rec.StoragePath := FormatUtf8('%_%',
          [NewId, Rec.FileName]);
        FilePath := FMediaPath + Utf8ToString(Rec.StoragePath);
        FileFromString(Content, FilePath);

        // Update StoragePath in the database record
        Rec.IDValue := NewId;
        FRest.Orm.Update(Rec, 'StoragePath');

        aCtxt.OutContent := FormatUtf8(
          '{"id":%,"url":"/api/media/%"}', [NewId, NewId]);
        aCtxt.OutContentType := JSON_CONTENT_TYPE;
        Result := HTTP_CREATED;
      end
      else
      begin
        aCtxt.OutContent := '{"error":"upload failed"}';
        aCtxt.OutContentType := JSON_CONTENT_TYPE;
        Result := HTTP_SERVERERROR;
      end;
    finally
      Rec.Free;
    end;
  end

  // GET /api/media/{id}/info
  else if (aCtxt.Method = 'GET') and
    IdemPChar(pointer(Path), '/API/MEDIA/') and
    (PosEx('/info', Path) > 0) then
  begin
    RecordId := ExtractId(Path, '/api/media/');
    Rec := TOrmMedia.Create;
    try
      if FRest.Orm.Retrieve(RecordId, Rec) then
      begin
        aCtxt.OutContent := Rec.GetJsonValues(True, True, ooSelect);
        aCtxt.OutContentType := JSON_CONTENT_TYPE;
        Result := HTTP_SUCCESS;
      end
      else
      begin
        aCtxt.OutContent := '{"error":"not found"}';
        aCtxt.OutContentType := JSON_CONTENT_TYPE;
        Result := HTTP_NOTFOUND;
      end;
    finally
      Rec.Free;
    end;
  end

  // GET /api/media/{id} (serve the image)
  else if (aCtxt.Method = 'GET') and
    IdemPChar(pointer(Path), '/API/MEDIA/') then
  begin
    RecordId := ExtractId(Path, '/api/media/');
    Rec := TOrmMedia.Create;
    try
      if FRest.Orm.Retrieve(RecordId, Rec) then
      begin
        FilePath := FMediaPath + Utf8ToString(Rec.StoragePath);
        if FileExists(FilePath) then
        begin
          aCtxt.OutContent := StringFromFile(FilePath);
          aCtxt.OutContentType := Rec.MimeType;
          Result := HTTP_SUCCESS;
        end
        else
        begin
          aCtxt.OutContent := '{"error":"file not found on disk"}';
          aCtxt.OutContentType := JSON_CONTENT_TYPE;
          Result := HTTP_NOTFOUND;
        end;
      end
      else
      begin
        aCtxt.OutContent := '{"error":"not found"}';
        aCtxt.OutContentType := JSON_CONTENT_TYPE;
        Result := HTTP_NOTFOUND;
      end;
    finally
      Rec.Free;
    end;
  end

  // DELETE /api/media/{id}
  else if (aCtxt.Method = 'DELETE') and
    IdemPChar(pointer(Path), '/API/MEDIA/') then
  begin
    RecordId := ExtractId(Path, '/api/media/');
    Rec := TOrmMedia.Create;
    try
      if FRest.Orm.Retrieve(RecordId, Rec) then
      begin
        // Delete file from disk
        FilePath := FMediaPath + Utf8ToString(Rec.StoragePath);
        if FileExists(FilePath) then
          DeleteFile(FilePath);
        FRest.Orm.Delete(TOrmMedia, RecordId);
        aCtxt.OutContent := '{"success":true}';
        Result := HTTP_SUCCESS;
      end
      else
      begin
        aCtxt.OutContent := '{"error":"not found"}';
        Result := HTTP_NOTFOUND;
      end;
    finally
      Rec.Free;
    end;
    aCtxt.OutContentType := JSON_CONTENT_TYPE;
  end

  else
    Result := inherited OnRequest(aCtxt);
end;

end.
