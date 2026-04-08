/// <summary>
///   Interface-based service implementation for the Auth microservice.
///   Implements IAuth using SCRAM-MCF for password verification,
///   registered as a mORMot2 SOA service on TRestServerDB.
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
  mormot.orm.base,
  mormot.orm.core,
  mormot.rest.core,
  mormot.rest.server,
  mormot.rest.sqlite3,
  mormot.soa.core,
  mormot.soa.server,
  ms.auth.model,
  ms.shared,
  ms.shared.api,
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
  ///   Implements the IAuth interface using SCRAM-MCF password
  ///   verification. Registered as a sicShared SOA service.
  /// </summary>
  TAuthService = class(TInterfacedObject, IAuth)
  private
    FOrm: IRestOrm;
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
  public
    constructor Create(
      const aOrm: IRestOrm;
      aJwt: TBlogJwt
    );

    // IAuth
    procedure Challenge(const aEmail: RawUtf8;
      out aMcfInfo, aServerNonce: RawUtf8);
    function Authenticate(const aEmail, aServerNonce, aClientProof: RawUtf8;
      out aToken: RawUtf8; out aUserId: TID;
      out aServerProof: RawUtf8): boolean;
    function Register(const aEmail, aPassword: RawUtf8;
      aUserId: TID): TID;
    function Validate(const aToken: RawUtf8;
      out aUserId: TID): boolean;
    function ChangePassword(aUserId: TID;
      const aOldPassword, aNewPassword: RawUtf8): boolean;
  end;

  /// <summary>
  ///   Auth microservice server. Creates a TRestServerDB with
  ///   the TOrmAuthUser model and registers TAuthService as a
  ///   SOA interface-based service for IAuth.
  /// </summary>
  TAuthServer = class(TMicroService)
  private
    FJwt: TBlogJwt;
    FAuthImpl: TAuthService;
  protected
    function CreateModel: TOrmModel; override;
    procedure SetupServices; override;
    procedure DoFinalize; override;
  end;

implementation

{ TAuthService }

constructor TAuthService.Create(
  const aOrm: IRestOrm;
  aJwt: TBlogJwt
);
begin
  inherited Create;
  FOrm := aOrm;
  FJwt := aJwt;
end;

function TAuthService.FindUserByEmail(
  const aEmail: RawUtf8
): TOrmAuthUser;
begin
  Result := TOrmAuthUser.Create;
  if not FOrm.Retrieve('Email=?', [], [aEmail], Result) then
    FreeAndNil(Result);
end;

procedure TAuthService.ComputeScramCredentials(
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

procedure TAuthService.StoreChallenge(
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

function TAuthService.ConsumeChallenge(
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

procedure TAuthService.Challenge(const aEmail: RawUtf8;
  out aMcfInfo, aServerNonce: RawUtf8);
var
  User: TOrmAuthUser;
  Chal: TScramChallenge;
  RandomData: THash128;
begin
  Finalize(Chal);
  FillCharFast(Chal, SizeOf(Chal), 0);
  Chal.Email := aEmail;
  // Generate server nonce
  RandomBytes(@RandomData, SizeOf(RandomData));
  Chal.ServerNonce := BinToBase64uri(@RandomData, SizeOf(RandomData));
  Chal.CreatedAt := NowUtc;
  // Look up user
  User := FindUserByEmail(aEmail);
  if (User <> nil) and User.IsActive then
  begin
    try
      Chal.McfInfo := User.McfInfo;
      Chal.PersistedKey := User.PersistedKey;
      Chal.UserId := User.UserId;
      Chal.IsReal := True;
    finally
      User.Free;
    end;
  end
  else
  begin
    User.Free;
    // Anti-enumeration: return fake MCF info
    Chal.McfInfo := ModularCryptFakeInfo(aEmail, mcfPbkdf2Sha256);
    Chal.IsReal := False;
  end;
  StoreChallenge(Chal);
  aMcfInfo := Chal.McfInfo;
  aServerNonce := Chal.ServerNonce;
end;

function TAuthService.Authenticate(const aEmail, aServerNonce,
  aClientProof: RawUtf8; out aToken: RawUtf8; out aUserId: TID;
  out aServerProof: RawUtf8): boolean;
var
  Chal: TScramChallenge;
  User: TOrmAuthUser;
begin
  Result := False;
  aToken := '';
  aUserId := 0;
  aServerProof := '';
  // Consume the pending challenge
  if not ConsumeChallenge(aServerNonce, Chal) then
    Exit;
  if Chal.Email <> aEmail then
    Exit;
  if not Chal.IsReal then
    Exit;
  // Verify client proof using SCRAM
  aServerProof := ScramServerProof(
    Chal.PersistedKey,
    aClientProof,
    [aEmail, aServerNonce]);
  if aServerProof = '' then
    Exit;
  // Authentication successful
  aUserId := Chal.UserId;
  aToken := FJwt.CreateToken(aUserId);
  // Update last login
  User := FindUserByEmail(aEmail);
  if User <> nil then
  begin
    try
      User.LastLogin := NowUtc;
      FOrm.Update(User, 'LastLogin');
    finally
      User.Free;
    end;
  end;
  Result := True;
end;

function TAuthService.Register(const aEmail, aPassword: RawUtf8;
  aUserId: TID): TID;
var
  User: TOrmAuthUser;
  McfInfo, PersistedKey: RawUtf8;
begin
  Result := 0;
  if (aEmail = '') or (aPassword = '') then
    Exit;
  // Check whether the email is already taken
  User := FindUserByEmail(aEmail);
  if User <> nil then
  begin
    User.Free;
    Exit;
  end;
  User := TOrmAuthUser.Create;
  try
    User.Email := aEmail;
    ComputeScramCredentials(aEmail, aPassword, McfInfo, PersistedKey);
    User.McfInfo := McfInfo;
    User.PersistedKey := PersistedKey;
    User.UserId := aUserId;
    User.IsActive := True;
    User.CreatedAt := NowUtc;
    if FOrm.Add(User, True) > 0 then
      Result := aUserId;
  finally
    User.Free;
  end;
end;

function TAuthService.Validate(const aToken: RawUtf8;
  out aUserId: TID): boolean;
begin
  Result := FJwt.ValidateToken(aToken, aUserId);
end;

function TAuthService.ChangePassword(aUserId: TID;
  const aOldPassword, aNewPassword: RawUtf8): boolean;
var
  User: TOrmAuthUser;
  McfInfo, PersistedKey: RawUtf8;
begin
  Result := False;
  User := TOrmAuthUser.Create;
  try
    if not FOrm.Retrieve('UserId=?', [], [aUserId], User) then
      Exit;
    // Verify old password: re-derive MCF hash from stored format
    // info and compare the resulting persisted key
    McfInfo := ModularCryptHash(User.McfInfo, aOldPassword);
    PersistedKey := ScramPersistedKey(McfInfo, User.Email);
    FillZero(RawByteString(McfInfo));
    if PersistedKey <> User.PersistedKey then
      Exit;
    // Set new password
    ComputeScramCredentials(User.Email, aNewPassword, McfInfo, PersistedKey);
    User.McfInfo := McfInfo;
    User.PersistedKey := PersistedKey;
    FOrm.Update(User, 'McfInfo,PersistedKey');
    Result := True;
  finally
    User.Free;
  end;
end;

{ TAuthServer }

function TAuthServer.CreateModel: TOrmModel;
begin
  Result := TOrmModel.Create([TOrmAuthUser], MODEL_ROOT);
end;

procedure TAuthServer.SetupServices;
begin
  FJwt := TBlogJwt.Create(Config.JwtSecret, JWT_EXPIRATION_MINUTES);
  FAuthImpl := TAuthService.Create(FRestServer.Orm, FJwt);
  RegisterService(FAuthImpl, TypeInfo(IAuth));
end;

procedure TAuthServer.DoFinalize;
begin
  FreeAndNil(FJwt);
  // FAuthImpl is ref-counted via IAuth, freed by the service factory
  inherited DoFinalize;
end;

end.
