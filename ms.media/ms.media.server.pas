/// <summary>
///   Interface-based service implementation for the Media microservice.
///   Implements the IMedia contract via TMediaService and hosts it
///   inside TMediaServer (a TMicroService subclass).
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
  ///   Implements the IMedia interface for file upload, retrieval
  ///   and management of media assets.
  /// </summary>
  TMediaService = class(TInterfacedObject, IMedia)
  private
    FOrm: IRestOrm;
    FMediaPath: TFileName;
    /// <summary>
    ///   Guesses the MIME type based on a file name extension.
    /// </summary>
    /// <param name="aFileName">
    ///   The file name to inspect.
    /// </param>
    /// <returns>
    ///   The guessed MIME type string, or 'application/octet-stream'
    ///   as fallback.
    /// </returns>
    function GuessMimeType(const aFileName: RawUtf8): RawUtf8;
  public
    constructor Create(const aOrm: IRestOrm; const aMediaPath: TFileName);
    function Upload(const aFileName, aFileData, aAltText: RawUtf8;
      aUploadedBy: TID): TID;
    function GetInfo(aId: TID): RawJson;
    function GetFile(aId: TID;
      out aContentType: RawUtf8): RawByteString;
    function Remove(aId: TID): boolean;
  end;

  /// <summary>
  ///   Microservice server hosting the IMedia service implementation.
  /// </summary>
  TMediaServer = class(TMicroService)
  private
    FMediaImpl: TMediaService;
    FMediaPath: TFileName;
  protected
    function CreateModel: TOrmModel; override;
    procedure SetupServices; override;
    procedure DoInitialize; override;
  end;

implementation

{ TMediaService }

constructor TMediaService.Create(
  const aOrm: IRestOrm; const aMediaPath: TFileName);
begin
  inherited Create;
  FOrm := aOrm;
  FMediaPath := aMediaPath;
end;

function TMediaService.GuessMimeType(
  const aFileName: RawUtf8): RawUtf8;
var
  Ext: string;
begin
  Ext := System.SysUtils.LowerCase(
    ExtractFileExt(Utf8ToString(aFileName)));
  if (Ext = '.jpg') or (Ext = '.jpeg') then
    Result := 'image/jpeg'
  else if Ext = '.png' then
    Result := 'image/png'
  else if Ext = '.gif' then
    Result := 'image/gif'
  else if Ext = '.webp' then
    Result := 'image/webp'
  else if Ext = '.svg' then
    Result := 'image/svg+xml'
  else
    Result := 'application/octet-stream';
end;

function TMediaService.Upload(
  const aFileName, aFileData, aAltText: RawUtf8;
  aUploadedBy: TID): TID;
var
  Rec: TOrmMediaFile;
  Content: RawByteString;
  FilePath: TFileName;
begin
  Content := Base64ToBin(aFileData);
  Rec := TOrmMediaFile.Create;
  try
    Rec.FileName := aFileName;
    Rec.MimeType := GuessMimeType(aFileName);
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

function TMediaService.GetInfo(aId: TID): RawJson;
var
  Rec: TOrmMediaFile;
begin
  Rec := TOrmMediaFile.Create;
  try
    if FOrm.Retrieve(aId, Rec) then
      Result := Rec.GetJsonValues(True, True, ooSelect)
    else
      Result := '{}';
  finally
    Rec.Free;
  end;
end;

function TMediaService.GetFile(aId: TID;
  out aContentType: RawUtf8): RawByteString;
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

function TMediaService.Remove(aId: TID): boolean;
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

{ TMediaServer }

function TMediaServer.CreateModel: TOrmModel;
begin
  Result := TOrmModel.Create([TOrmMediaFile], 'api');
end;

procedure TMediaServer.DoInitialize;
begin
  // media/ directory is already created in SetupServices
end;

procedure TMediaServer.SetupServices;
var
  Factory: TServiceFactoryServerAbstract;
begin
  FMediaPath := Executable.ProgramFilePath + 'media' + PathDelim;
  if not DirectoryExists(FMediaPath) then
    CreateDir(FMediaPath);
  FMediaImpl := TMediaService.Create(FRestServer.Orm, FMediaPath);
  Factory := FRestServer.ServiceRegister(
    FMediaImpl, [TypeInfo(IMedia)]) ;
  Factory.ByPassAuthentication := True;
  Factory.ResultAsJsonObjectWithoutResult := True;
end;

end.
