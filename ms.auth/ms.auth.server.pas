/// <summary>
///   Interface-based service implementation for the Auth microservice.
///   Implements <c>IAuth</c> using SCRAM-MCF for password verification.
///
///   Demonstrates mORMot2's built-in cryptographic primitives:
///   - <c>ModularCryptHash</c> (<c>mormot.crypt.secure</c>): computes a PBKDF2-SHA256 password hash in MCF
///     (Modular Crypt Format), e.g. '$pbkdf2-sha256$310000$salt$checksum'. This is the industry-standard
///     format used by passlib (Python), PHC, etc.
///   - <c>ScramPersistedKey</c>: derives the SCRAM persisted key from the MCF hash and the user's email
///     (used as salt).
///   - <c>ScramServerProof</c>: verifies the client's SCRAM proof and computes the server proof for mutual
///     authentication.
///   - <c>ModularCryptFakeInfo</c>: returns a fake MCF info string for non-existent users, preventing email
///     enumeration attacks (the response looks identical to a real challenge).
///
///   The SCRAM flow (RFC 5802 adapted for mORMot2):
///   1. Client calls <c>Challenge(email)</c> -> gets MCF info + nonce.
///   2. Client computes PBKDF2 locally, derives client proof.
///   3. Client calls <c>Authenticate(email, nonce, proof)</c>.
///   4. Server verifies proof, returns JWT + server proof.
///   5. Client verifies server proof (mutual authentication).
///
///   The plaintext password is NEVER transmitted or stored. PBKDF2 key derivation runs on both client
///   (browser) and server (registration only).
///
///   See <c>ms.shared.jwt.pas</c> for JWT token creation/validation.
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

  /// <summary>
  ///   Maximum age of a SCRAM challenge in seconds.
  /// </summary>
  CHALLENGE_TTL_SEC = 60;

type

  /// <summary>
  ///   Pending SCRAM challenge awaiting client proof.
  /// </summary>
  TScramChallenge = record
  public

    /// <summary>
    ///   The email address of the user who initiated this challenge.
    /// </summary>
    Email: RawUtf8;

    /// <summary>
    ///   The server-generated nonce that uniquely identifies this challenge.
    /// </summary>
    ServerNonce: RawUtf8;

    /// <summary>
    ///   The MCF format information string sent to the client for PBKDF2 derivation.
    /// </summary>
    McfInfo: RawUtf8;

    /// <summary>
    ///   The SCRAM persisted key derived from the user's stored MCF hash.
    /// </summary>
    PersistedKey: RawUtf8;

    /// <summary>
    ///   The user ID associated with this challenge.
    /// </summary>
    UserId: TID;

    /// <summary>
    ///   True if this challenge belongs to an actual user, False if it is a fake anti-enumeration challenge.
    /// </summary>
    IsReal: boolean;

    /// <summary>
    ///   UTC timestamp when this challenge was created, used for TTL expiration.
    /// </summary>
    CreatedAt: TDateTime;
  end;

  /// <summary>
  ///   Dynamic array of pending SCRAM challenges.
  /// </summary>
  TScramChallenges = array of TScramChallenge;

  /// <summary>
  ///   Implements the IAuth interface using SCRAM-MCF password verification. Registered as a sicShared SOA service.
  /// </summary>
  TAuthService = class(TInterfacedObject, IAuth)
  strict private

    /// <summary>
    ///   ORM interface for database operations on the auth user table.
    /// </summary>
    FOrm: IRestOrm;

    /// <summary>
    ///   JWT helper for creating and validating authentication tokens.
    /// </summary>
    FJwt: TBlogJwt;

    /// <summary>
    ///   Array of pending SCRAM challenges awaiting client proof.
    /// </summary>
    FChallenges: TScramChallenges;

    /// <summary>
    ///   Lightweight lock protecting concurrent access to <c>FChallenges</c>.
    /// </summary>
    FChallengeSafe: TLightLock;

    /// <summary>
    ///   Finds a user record by email address.
    /// </summary>
    /// <param name="aEmail">
    ///   The email address to search for.
    /// </param>
    /// <returns>
    ///   The user record if found, or nil if no matching user exists.
    /// </returns>
    function FindUserByEmail(
      const aEmail: RawUtf8
      ): TOrmAuthUser;

    /// <summary>
    ///   Computes a new MCF hash and SCRAM persisted key for a password.
    /// </summary>
    /// <param name="aEmail">
    ///   The user's email address, used as salt for the persisted key.
    /// </param>
    /// <param name="aPassword">
    ///   The plaintext password to derive credentials from.
    /// </param>
    /// <param name="aMcfInfo">
    ///   Returns the MCF format information string.
    /// </param>
    /// <param name="aPersistedKey">
    ///   Returns the SCRAM persisted key.
    /// </param>
    procedure ComputeScramCredentials(
      const aEmail, aPassword: RawUtf8;
      out aMcfInfo, aPersistedKey: RawUtf8
      );

    /// <summary>
    ///   Adds a challenge entry and removes expired ones.
    /// </summary>
    /// <param name="aChallenge">
    ///   The SCRAM challenge to store.
    /// </param>
    procedure StoreChallenge(
      const aChallenge: TScramChallenge
      );

    /// <summary>
    ///   Finds and removes a challenge by server nonce. Returns True if found and not expired.
    /// </summary>
    /// <param name="aServerNonce">
    ///   The server nonce identifying the challenge to consume.
    /// </param>
    /// <param name="aChallenge">
    ///   Returns the challenge data if found and not expired.
    /// </param>
    /// <returns>
    ///   True if the challenge was found and is still valid, False otherwise.
    /// </returns>
    function ConsumeChallenge(
      const aServerNonce: RawUtf8;
      out aChallenge: TScramChallenge
      ): boolean;
  public

    /// <summary>
    ///   Creates a new TAuthService instance with the given ORM and JWT helper.
    /// </summary>
    /// <param name="aOrm">
    ///   The ORM interface for database access.
    /// </param>
    /// <param name="aJwt">
    ///   The JWT helper for token creation and validation.
    /// </param>
    constructor Create(
      const aOrm: IRestOrm;
      aJwt: TBlogJwt
      );

    // IAuth

    /// <summary>
    ///   Creates a SCRAM challenge for the given email address. Returns the MCF info string and a server nonce.
    /// </summary>
    /// <param name="aEmail">
    ///   The email address of the user requesting authentication.
    /// </param>
    /// <param name="aMcfInfo">
    ///   Returns the MCF format information needed by the client for PBKDF2 derivation.
    /// </param>
    /// <param name="aServerNonce">
    ///   Returns the server-generated nonce identifying this challenge.
    /// </param>
    procedure Challenge(
      const aEmail: RawUtf8;
      out aMcfInfo, aServerNonce: RawUtf8
      );

    /// <summary>
    ///   Verifies the client's SCRAM proof and returns a JWT token on success, along with the server proof for
    ///   mutual authentication.
    /// </summary>
    /// <param name="aEmail">
    ///   The email address of the authenticating user.
    /// </param>
    /// <param name="aServerNonce">
    ///   The server nonce from the preceding Challenge call.
    /// </param>
    /// <param name="aClientProof">
    ///   The SCRAM client proof derived from the user's password.
    /// </param>
    /// <param name="aToken">
    ///   Returns the JWT token on successful authentication.
    /// </param>
    /// <param name="aUserId">
    ///   Returns the user's ID on successful authentication.
    /// </param>
    /// <param name="aServerProof">
    ///   Returns the SCRAM server proof for mutual authentication verification.
    /// </param>
    /// <returns>
    ///   True if authentication succeeded, False otherwise.
    /// </returns>
    function Authenticate(
      const aEmail, aServerNonce, aClientProof: RawUtf8;
      out aToken: RawUtf8;
      out aUserId: TID;
      out aServerProof: RawUtf8
      ): boolean;

    /// <summary>
    ///   Registers a new user with the given email and password. Computes SCRAM credentials and stores them.
    /// </summary>
    /// <param name="aEmail">
    ///   The email address for the new account.
    /// </param>
    /// <param name="aPassword">
    ///   The plaintext password used to derive SCRAM credentials.
    /// </param>
    /// <param name="aUserId">
    ///   The user ID to associate with this authentication record.
    /// </param>
    /// <returns>
    ///   The user ID on success, or 0 if registration failed.
    /// </returns>
    function Register(
      const aEmail, aPassword: RawUtf8;
      aUserId: TID
      ): TID;

    /// <summary>
    ///   Validates a JWT token and extracts the user ID.
    /// </summary>
    /// <param name="aToken">
    ///   The JWT token to validate.
    /// </param>
    /// <param name="aUserId">
    ///   Returns the user ID embedded in the token.
    /// </param>
    /// <returns>
    ///   True if the token is valid and not expired, False otherwise.
    /// </returns>
    function Validate(
      const aToken: RawUtf8;
      out aUserId: TID
      ): boolean;

    /// <summary>
    ///   Changes the password for an existing user after verifying the old password.
    /// </summary>
    /// <param name="aUserId">
    ///   The ID of the user whose password should be changed.
    /// </param>
    /// <param name="aOldPassword">
    ///   The current password for verification.
    /// </param>
    /// <param name="aNewPassword">
    ///   The new password to set.
    /// </param>
    /// <returns>
    ///   True if the old password was correct and the new password was set, False otherwise.
    /// </returns>
    function ChangePassword(
      aUserId: TID;
      const aOldPassword, aNewPassword: RawUtf8
      ): boolean;
  end;

  /// <summary>
  ///   Auth microservice server. Creates a TRestServerDB with the TOrmAuthUser model and registers TAuthService
  ///   as a SOA interface-based service for IAuth.
  /// </summary>
  TAuthServer = class(TMicroService)
  strict private

    /// <summary>
    ///   JWT helper instance owned by this server, used by the auth service.
    /// </summary>
    FJwt: TBlogJwt;

    /// <summary>
    ///   The auth service implementation registered as SOA service.
    /// </summary>
    FAuthImpl: TAuthService;
  protected

    /// <summary>
    ///   Creates the ORM model containing <c>TOrmAuthUser</c>.
    /// </summary>
    /// <returns>
    ///   A new ORM model for the auth microservice database.
    /// </returns>
    function CreateModel: TOrmModel; override;

    /// <summary>
    ///   Creates the JWT helper, the auth service instance, and registers it as SOA service.
    /// </summary>
    procedure SetupServices; override;

    /// <summary>
    ///   Frees the JWT helper. The auth service is ref-counted and freed by the service factory.
    /// </summary>
    procedure DoFinalize; override;
  end;

implementation

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
        if (NowUtc - FChallenges[Idx].CreatedAt) * SecsPerDay <= CHALLENGE_TTL_SEC then
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

procedure TAuthService.Challenge(
  const aEmail: RawUtf8;
  out aMcfInfo, aServerNonce: RawUtf8
  );
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
  try
    if (User <> nil) and User.IsActive then
    begin
      Chal.McfInfo := User.McfInfo;
      Chal.PersistedKey := User.PersistedKey;
      Chal.UserId := User.UserId;
      Chal.IsReal := True;
    end
    else
    begin
      // Anti-enumeration: return fake MCF info
      Chal.McfInfo := ModularCryptFakeInfo(aEmail, mcfPbkdf2Sha256);
      Chal.IsReal := False;
    end;
  finally
    User.Free;
  end;
  StoreChallenge(Chal);
  aMcfInfo := Chal.McfInfo;
  aServerNonce := Chal.ServerNonce;
end;

function TAuthService.Authenticate(
  const aEmail, aServerNonce, aClientProof: RawUtf8;
  out aToken: RawUtf8;
  out aUserId: TID;
  out aServerProof: RawUtf8
  ): boolean;
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
  aServerProof := ScramServerProof(Chal.PersistedKey, aClientProof, [aEmail, aServerNonce]);
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

function TAuthService.Register(
  const aEmail, aPassword: RawUtf8;
  aUserId: TID
  ): TID;
var
  User: TOrmAuthUser;
  McfInfo, PersistedKey: RawUtf8;
begin
  if (aEmail = '') or (aPassword = '') then
    Exit(0);
  Result := 0;
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

function TAuthService.Validate(
  const aToken: RawUtf8;
  out aUserId: TID
  ): boolean;
begin
  Result := FJwt.ValidateToken(aToken, aUserId);
end;

function TAuthService.ChangePassword(
  aUserId: TID;
  const aOldPassword, aNewPassword: RawUtf8
  ): boolean;
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
