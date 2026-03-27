/// <summary>
///   HTTP server for the Auth service.
///   Login, registration, token validation, password change.
/// </summary>
unit ms.auth.server;

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
  mormot.crypt.core,
  mormot.db.raw.sqlite3,
  mormot.net.http,
  mormot.net.server,
  mormot.orm.base,
  mormot.orm.core,
  mormot.rest.sqlite3,
  ms.auth.model,
  ms.shared,
  ms.shared.jwt,
  ms.shared.service;

type

  /// <summary>
  ///   Microservice server handling authentication endpoints.
  /// </summary>
  TAuthServer = class(TMicroService)
  private
    FModel: TOrmModel;
    FRest: TRestServerDB;
    FJwt: TBlogJwt;

    /// <summary>
    ///   Finds a user record by email address.
    /// </summary>
    /// <param name="aEmail">
    ///   The email address to search for.
    /// </param>
    /// <returns>
    ///   The matching TOrmAuthUser instance, or nil if not found.
    ///   Caller must free the returned object.
    /// </returns>
    function FindUserByEmail(
      const aEmail: RawUtf8
    ): TOrmAuthUser;

    /// <summary>
    ///   Generates a cryptographically random salt value.
    /// </summary>
    /// <returns>
    ///   A hex-encoded random salt string.
    /// </returns>
    function GenerateSalt: RawUtf8;

    /// <summary>
    ///   Hashes a password with the given salt using SHA-256.
    /// </summary>
    /// <param name="aPassword">
    ///   The plaintext password to hash.
    /// </param>
    /// <param name="aSalt">
    ///   The salt to prepend before hashing.
    /// </param>
    /// <returns>
    ///   The hex-encoded SHA-256 hash of the salted password.
    /// </returns>
    function HashPassword(
      const aPassword, aSalt: RawUtf8
    ): RawUtf8;
  protected

    /// <summary>
    ///   Initializes the database, ORM and JWT handler.
    /// </summary>
    procedure DoInitialize; override;

    /// <summary>
    ///   Releases the JWT handler, REST server and ORM model.
    /// </summary>
    procedure DoFinalize; override;

    /// <summary>
    ///   Dispatches incoming HTTP requests to authentication endpoints.
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

{ TAuthServer }

procedure TAuthServer.DoFinalize;
begin
  FreeAndNil(FJwt);
  FreeAndNil(FRest);
  FreeAndNil(FModel);
end;

procedure TAuthServer.DoInitialize;
var
  DatabasePath: TFileName;
begin
  DatabasePath := Executable.ProgramFilePath + 'auth.db';
  FModel := CreateAuthModel;
  FRest := TRestServerDB.Create(FModel, DatabasePath);
  FRest.DB.Synchronous := smNormal;
  FRest.DB.LockingMode := lmExclusive;
  FRest.CreateMissingTables;
  FJwt := TBlogJwt.Create(Config.JwtSecret, JWT_EXPIRATION_MINUTES);
end;

function TAuthServer.FindUserByEmail(
  const aEmail: RawUtf8
): TOrmAuthUser;
begin
  Result := TOrmAuthUser.Create;
  if not FRest.Orm.Retrieve('Email=?', [], [aEmail], Result) then
    FreeAndNil(Result);
end;

function TAuthServer.GenerateSalt: RawUtf8;
var
  RandomData: THash128;
begin
  RandomBytes(@RandomData, SizeOf(RandomData));
  Result := BinToHex(@RandomData, SizeOf(RandomData));
end;

function TAuthServer.HashPassword(
  const aPassword, aSalt: RawUtf8
): RawUtf8;
var
  Combined: RawUtf8;
  Digest: THash256;
begin
  Combined := aSalt + aPassword;
  Digest := Sha256Digest(pointer(Combined), Length(Combined));
  Result := Sha256DigestToString(Digest);
end;

function TAuthServer.OnRequest(
  aCtxt: THttpServerRequestAbstract
): cardinal;
var
  Path: RawUtf8;
  Doc: TDocVariantData;
  User: TOrmAuthUser;
  Token: RawUtf8;
  UserId: TID;
  NewId: TID;
  Salt, Hash: RawUtf8;
begin
  Path := aCtxt.Url;

  // POST /api/auth/login
  if (aCtxt.Method = 'POST') and (Path = '/api/auth/login') then
  begin
    Doc.InitJson(aCtxt.InContent, JSON_FAST_FLOAT);
    User := FindUserByEmail(Doc.U['Email']);
    try
      if User = nil then
      begin
        aCtxt.OutContent := '{"error":"invalid credentials"}';
        aCtxt.OutContentType := JSON_CONTENT_TYPE;
        Result := HTTP_FORBIDDEN;
        Exit;
      end;
      if not User.IsActive then
      begin
        aCtxt.OutContent := '{"error":"account disabled"}';
        aCtxt.OutContentType := JSON_CONTENT_TYPE;
        Result := HTTP_FORBIDDEN;
        Exit;
      end;
      Hash := HashPassword(Doc.U['Password'], User.Salt);
      if Hash <> User.PasswordHash then
      begin
        aCtxt.OutContent := '{"error":"invalid credentials"}';
        aCtxt.OutContentType := JSON_CONTENT_TYPE;
        Result := HTTP_FORBIDDEN;
        Exit;
      end;
      // Login successful
      Token := FJwt.CreateToken(User.UserId);
      User.LastLogin := NowUtc;
      FRest.Orm.Update(User, 'LastLogin');
      aCtxt.OutContent := FormatUtf8(
        '{"token":"%","userId":%}', [Token, User.UserId]);
      aCtxt.OutContentType := JSON_CONTENT_TYPE;
      Result := HTTP_SUCCESS;
    finally
      User.Free;
    end;
  end

  // POST /api/auth/register
  else if (aCtxt.Method = 'POST') and (Path = '/api/auth/register') then
  begin
    Doc.InitJson(aCtxt.InContent, JSON_FAST_FLOAT);
    // Check whether the email is already taken
    User := FindUserByEmail(Doc.U['Email']);
    if User <> nil then
    begin
      User.Free;
      aCtxt.OutContent := '{"error":"email already registered"}';
      aCtxt.OutContentType := JSON_CONTENT_TYPE;
      Result := HTTP_BADREQUEST;
      Exit;
    end;
    User := TOrmAuthUser.Create;
    try
      User.Email := Doc.U['Email'];
      Salt := GenerateSalt;
      User.Salt := Salt;
      User.PasswordHash := HashPassword(Doc.U['Password'], Salt);
      User.UserId := Doc.I['UserId'];
      User.IsActive := True;
      User.CreatedAt := NowUtc;
      NewId := FRest.Orm.Add(User, True);
      if NewId > 0 then
      begin
        aCtxt.OutContent := FormatUtf8(
          '{"userId":%}', [User.UserId]);
        Result := HTTP_CREATED;
      end
      else
      begin
        aCtxt.OutContent := '{"error":"registration failed"}';
        Result := HTTP_SERVERERROR;
      end;
      aCtxt.OutContentType := JSON_CONTENT_TYPE;
    finally
      User.Free;
    end;
  end

  // POST /api/auth/validate
  else if (aCtxt.Method = 'POST') and (Path = '/api/auth/validate') then
  begin
    Doc.InitJson(aCtxt.InContent, JSON_FAST_FLOAT);
    Token := Doc.U['Token'];
    if FJwt.ValidateToken(Token, UserId) then
    begin
      aCtxt.OutContent := FormatUtf8(
        '{"valid":true,"userId":%}', [UserId]);
      Result := HTTP_SUCCESS;
    end
    else
    begin
      aCtxt.OutContent := '{"valid":false,"userId":0}';
      Result := HTTP_SUCCESS;
    end;
    aCtxt.OutContentType := JSON_CONTENT_TYPE;
  end

  // PUT /api/auth/change-password
  else if (aCtxt.Method = 'PUT') and
    (Path = '/api/auth/change-password') then
  begin
    Doc.InitJson(aCtxt.InContent, JSON_FAST_FLOAT);
    UserId := Doc.I['UserId'];
    User := TOrmAuthUser.Create;
    try
      if not FRest.Orm.Retrieve('UserId=?', [], [UserId], User) then
      begin
        aCtxt.OutContent := '{"error":"user not found"}';
        aCtxt.OutContentType := JSON_CONTENT_TYPE;
        Result := HTTP_NOTFOUND;
        Exit;
      end;
      // Verify old password
      Hash := HashPassword(Doc.U['OldPassword'], User.Salt);
      if Hash <> User.PasswordHash then
      begin
        aCtxt.OutContent := '{"error":"wrong password"}';
        aCtxt.OutContentType := JSON_CONTENT_TYPE;
        Result := HTTP_FORBIDDEN;
        Exit;
      end;
      // Set new password
      Salt := GenerateSalt;
      User.Salt := Salt;
      User.PasswordHash := HashPassword(Doc.U['NewPassword'], Salt);
      FRest.Orm.Update(User, 'Salt,PasswordHash');
      aCtxt.OutContent := '{"success":true}';
      aCtxt.OutContentType := JSON_CONTENT_TYPE;
      Result := HTTP_SUCCESS;
    finally
      User.Free;
    end;
  end

  // POST /api/auth/logout
  else if (aCtxt.Method = 'POST') and (Path = '/api/auth/logout') then
  begin
    // Stateless JWT: nothing to do on the server side
    aCtxt.OutContent := '{"success":true}';
    aCtxt.OutContentType := JSON_CONTENT_TYPE;
    Result := HTTP_SUCCESS;
  end

  else
    Result := inherited OnRequest(aCtxt);
end;

end.
