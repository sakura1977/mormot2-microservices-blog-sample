/// <summary>
///   HTTP server for the Auth service.
///   SCRAM-MCF authentication (challenge/authenticate),
///   registration, token validation, password change.
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
  mormot.crypt.secure,
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

const
  /// Maximum age of a SCRAM challenge in seconds.
  CHALLENGE_TTL_SEC = 60;

type

  /// <summary>
  ///   Pending SCRAM challenge awaiting client proof.
  /// </summary>
  TScramChallenge = record
    Email: RawUtf8;
    ServerNonce: RawUtf8;
    McfInfo: RawUtf8;
    PersistedKey: RawUtf8;
    UserId: TID;
    IsReal: boolean;
    CreatedAt: TDateTime;
  end;

  TScramChallenges = array of TScramChallenge;

  /// <summary>
  ///   Microservice server handling authentication endpoints
  ///   using SCRAM-MCF for password verification.
  /// </summary>
  TAuthServer = class(TMicroService)
  private
    FModel: TOrmModel;
    FRest: TRestServerDB;
    FJwt: TBlogJwt;
    FChallenges: TScramChallenges;
    FChallengeSafe: TLightLock;

    /// <summary>
    ///   Finds a user record by email address.
    /// </summary>
    function FindUserByEmail(
      const aEmail: RawUtf8
    ): TOrmAuthUser;

    /// <summary>
    ///   Computes a new MCF hash and SCRAM persisted key for a password.
    /// </summary>
    procedure ComputeScramCredentials(
      const aEmail, aPassword: RawUtf8;
      out aMcfInfo, aPersistedKey: RawUtf8
    );

    /// <summary>
    ///   Adds a challenge entry and removes expired ones.
    /// </summary>
    procedure StoreChallenge(
      const aChallenge: TScramChallenge
    );

    /// <summary>
    ///   Finds and removes a challenge by server nonce.
    ///   Returns True if found and not expired.
    /// </summary>
    function ConsumeChallenge(
      const aServerNonce: RawUtf8;
      out aChallenge: TScramChallenge
    ): boolean;
  protected
    procedure DoInitialize; override;
    procedure DoFinalize; override;
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

procedure TAuthServer.ComputeScramCredentials(
  const aEmail, aPassword: RawUtf8;
  out aMcfInfo, aPersistedKey: RawUtf8
);
var
  McfHash: RawUtf8;
begin
  McfHash := ModularCryptHash(mcfPbkdf2Sha256, aPassword);
  ModularCryptIdentify(McfHash, @aMcfInfo);
  aPersistedKey := ScramPersistedKey(McfHash, aEmail);
  FillZero(RawByteString(McfHash));
end;

procedure TAuthServer.StoreChallenge(
  const aChallenge: TScramChallenge
);
var
  Idx, Count: PtrInt;
  Now: TDateTime;
begin
  Now := NowUtc;
  FChallengeSafe.Lock;
  try
    // Remove expired entries
    Count := Length(FChallenges);
    Idx := 0;
    while Idx < Count do
    begin
      if (Now - FChallenges[Idx].CreatedAt) * SecsPerDay > CHALLENGE_TTL_SEC then
      begin
        Dec(Count);
        if Idx < Count then
          FChallenges[Idx] := FChallenges[Count];
        SetLength(FChallenges, Count);
      end
      else
        Inc(Idx);
    end;
    // Add new challenge
    SetLength(FChallenges, Count + 1);
    FChallenges[Count] := aChallenge;
  finally
    FChallengeSafe.UnLock;
  end;
end;

function TAuthServer.ConsumeChallenge(
  const aServerNonce: RawUtf8;
  out aChallenge: TScramChallenge
): boolean;
var
  Idx, Count: PtrInt;
begin
  Result := False;
  FChallengeSafe.Lock;
  try
    Count := Length(FChallenges);
    for Idx := 0 to Count - 1 do
    begin
      if FChallenges[Idx].ServerNonce = aServerNonce then
      begin
        if (NowUtc - FChallenges[Idx].CreatedAt) * SecsPerDay <=
          CHALLENGE_TTL_SEC then
        begin
          aChallenge := FChallenges[Idx];
          Result := True;
        end;
        // Remove consumed or expired entry
        Dec(Count);
        if Idx < Count then
          FChallenges[Idx] := FChallenges[Count];
        SetLength(FChallenges, Count);
        Exit;
      end;
    end;
  finally
    FChallengeSafe.UnLock;
  end;
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
  McfInfo, PersistedKey: RawUtf8;
  Challenge: TScramChallenge;
  ServerProof: RawUtf8;
  RandomData: THash128;
begin
  Path := aCtxt.Url;

  // POST /api/auth/challenge
  // Phase 1 of SCRAM-MCF: return MCF info and server nonce
  if (aCtxt.Method = 'POST') and (Path = '/api/auth/challenge') then
  begin
    Doc.InitJson(aCtxt.InContent, JSON_FAST_FLOAT);
    Finalize(Challenge);
    FillCharFast(Challenge, SizeOf(Challenge), 0);
    Challenge.Email := Doc.U['Email'];
    // Generate server nonce
    RandomBytes(@RandomData, SizeOf(RandomData));
    Challenge.ServerNonce := BinToBase64uri(@RandomData, SizeOf(RandomData));
    Challenge.CreatedAt := NowUtc;
    // Look up user
    User := FindUserByEmail(Challenge.Email);
    if (User <> nil) and User.IsActive then
    begin
      try
        Challenge.McfInfo := User.McfInfo;
        Challenge.PersistedKey := User.PersistedKey;
        Challenge.UserId := User.UserId;
        Challenge.IsReal := True;
      finally
        User.Free;
      end;
    end
    else
    begin
      User.Free;
      // Anti-enumeration: return fake MCF info
      Challenge.McfInfo := ModularCryptFakeInfo(
        Challenge.Email, mcfPbkdf2Sha256);
      Challenge.IsReal := False;
    end;
    StoreChallenge(Challenge);
    aCtxt.OutContent := JsonEncode([
      'McfInfo', Challenge.McfInfo,
      'ServerNonce', Challenge.ServerNonce]);
    aCtxt.OutContentType := JSON_CONTENT_TYPE;
    Result := HTTP_SUCCESS;
  end

  // POST /api/auth/authenticate
  // Phase 2 of SCRAM-MCF: verify client proof, return JWT + server proof
  else if (aCtxt.Method = 'POST') and
    (Path = '/api/auth/authenticate') then
  begin
    Doc.InitJson(aCtxt.InContent, JSON_FAST_FLOAT);
    if not ConsumeChallenge(Doc.U['ServerNonce'], Challenge) then
    begin
      aCtxt.OutContent := '{"error":"invalid or expired challenge"}';
      aCtxt.OutContentType := JSON_CONTENT_TYPE;
      Result := HTTP_FORBIDDEN;
      Exit;
    end;
    if Challenge.Email <> Doc.U['Email'] then
    begin
      aCtxt.OutContent := '{"error":"invalid credentials"}';
      aCtxt.OutContentType := JSON_CONTENT_TYPE;
      Result := HTTP_FORBIDDEN;
      Exit;
    end;
    if not Challenge.IsReal then
    begin
      aCtxt.OutContent := '{"error":"invalid credentials"}';
      aCtxt.OutContentType := JSON_CONTENT_TYPE;
      Result := HTTP_FORBIDDEN;
      Exit;
    end;
    // Verify client proof using SCRAM
    ServerProof := ScramServerProof(
      Challenge.PersistedKey,
      Doc.U['ClientProof'],
      [Challenge.Email, Challenge.ServerNonce]);
    if ServerProof = '' then
    begin
      aCtxt.OutContent := '{"error":"invalid credentials"}';
      aCtxt.OutContentType := JSON_CONTENT_TYPE;
      Result := HTTP_FORBIDDEN;
      Exit;
    end;
    // Authentication successful
    Token := FJwt.CreateToken(Challenge.UserId);
    // Update last login
    User := FindUserByEmail(Challenge.Email);
    if User <> nil then
    begin
      try
        User.LastLogin := NowUtc;
        FRest.Orm.Update(User, 'LastLogin');
      finally
        User.Free;
      end;
    end;
    aCtxt.OutContent := JsonEncode([
      'token', Token,
      'userId', Challenge.UserId,
      'ServerProof', ServerProof]);
    aCtxt.OutContentType := JSON_CONTENT_TYPE;
    Result := HTTP_SUCCESS;
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
      ComputeScramCredentials(
        User.Email, Doc.U['Password'], McfInfo, PersistedKey);
      User.McfInfo := McfInfo;
      User.PersistedKey := PersistedKey;
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
      // Verify old password: re-derive MCF hash from stored format
      // info and compare the resulting persisted key
      McfInfo := ModularCryptHash(User.McfInfo, Doc.U['OldPassword']);
      PersistedKey := ScramPersistedKey(McfInfo, User.Email);
      FillZero(RawByteString(McfInfo));
      if PersistedKey <> User.PersistedKey then
      begin
        aCtxt.OutContent := '{"error":"wrong password"}';
        aCtxt.OutContentType := JSON_CONTENT_TYPE;
        Result := HTTP_FORBIDDEN;
        Exit;
      end;
      // Set new password
      ComputeScramCredentials(
        User.Email, Doc.U['NewPassword'], McfInfo, PersistedKey);
      User.McfInfo := McfInfo;
      User.PersistedKey := PersistedKey;
      FRest.Orm.Update(User, 'McfInfo,PersistedKey');
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
