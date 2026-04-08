/// <summary>
///   JWT token management for the blog microservices.
///
///   Wraps mORMot2's <c>TJwtHS256</c> (HMAC-SHA256 based JSON Web
///   Tokens) into a simple create/validate API. The JWT contains
///   a custom 'uid' claim with the user's database ID, plus
///   standard claims (issuer, expiration, issued-at).
///
///   mORMot2 JWT features used:
///   - <c>TJwtHS256</c>: HMAC-SHA256 JWT implementation. Handles
///     signing, verification, and expiration checks automatically.
///   - <c>TJwtContent</c>: parsed JWT payload with typed access
///     to standard and custom claims via <c>TDocVariantData</c>.
///   - <c>jrcIssuer, jrcExpirationTime, jrcIssuedAt</c>: standard
///     JWT claim identifiers that TJwtHS256 validates automatically.
/// </summary>
unit ms.shared.jwt;

{$SCOPEDENUMS ON}
{$I mormot.defines.inc}
{$WARN SYMBOL_PLATFORM OFF}
{$WARN UNIT_PLATFORM OFF}

interface

uses
  mormot.core.base,
  mormot.core.datetime,
  mormot.core.json,
  mormot.core.text,
  mormot.crypt.jwt;

type

  /// <summary>
  ///   Manages JWT token creation and validation for the blog
  ///   authentication system. Encapsulates mORMot2's <c>TJwtHS256</c>
  ///   with a simple two-method API.
  /// </summary>
  TBlogJwt = class
  private
    /// <summary>
    ///   The mORMot2 JWT engine. Handles HMAC-SHA256 signing,
    ///   signature verification, and expiration validation.
    /// </summary>
    FJwt: TJwtHS256;

    /// <summary>
    ///   The HMAC secret key (kept for the lifetime of this instance).
    /// </summary>
    FSecret: RawUtf8;
  public

    /// <summary>
    ///   Creates a new JWT manager with the given secret and expiration.
    /// </summary>
    /// <param name="aSecret">
    ///   HMAC-SHA256 secret key for signing and verification.
    /// </param>
    /// <param name="aExpirationMinutes">
    ///   Token validity duration in minutes (default: 1440 = 24 hours).
    /// </param>
    constructor Create(
      const aSecret: RawUtf8;
      aExpirationMinutes: integer = 1440
      );

    /// <summary>
    ///   Releases the internal <c>TJwtHS256</c> engine.
    /// </summary>
    destructor Destroy; override;

    /// <summary>
    ///   Creates a signed JWT token embedding the given user ID
    ///   as a custom 'uid' claim.
    /// </summary>
    /// <param name="aUserId">
    ///   The user ID to embed in the token payload.
    /// </param>
    /// <returns>
    ///   The signed JWT string (header.payload.signature).
    /// </returns>
    function CreateToken(
      aUserId: TID
      ): RawUtf8;

    /// <summary>
    ///   Validates a JWT token's signature and expiration, then
    ///   extracts the user ID from the 'uid' claim.
    /// </summary>
    /// <param name="aToken">
    ///   The JWT token string to validate.
    /// </param>
    /// <param name="aUserId">
    ///   Output: the user ID from the token, or 0 if invalid.
    /// </param>
    /// <returns>
    ///   True if the token is valid and not expired.
    /// </returns>
    function ValidateToken(
      const aToken: RawUtf8;
      out aUserId: TID
      ): boolean;
  end;

implementation

constructor TBlogJwt.Create(
  const aSecret: RawUtf8;
  aExpirationMinutes: integer
  );
begin
  inherited Create;
  FSecret := aSecret;
  // TJwtHS256.Create parameters:
  //   aSecret: the HMAC-SHA256 signing key
  //   aPBKDF2Round: 0 = use the key directly (no key derivation)
  //   aClaims: which standard claims to include and validate
  //   aAudience: empty = no audience restriction
  //   aExpirationMinutes: token lifetime
  FJwt := TJwtHS256.Create(
    FSecret,
    0,
    [jrcIssuer, jrcExpirationTime, jrcIssuedAt],
    [],
    aExpirationMinutes
    );
end;

function TBlogJwt.CreateToken(
  aUserId: TID
  ): RawUtf8;
begin
  // TJwtHS256.Compute creates a signed JWT with:
  //   - Custom claims as name/value pairs: ['uid', aUserId]
  //   - Standard claims (iss, exp, iat) added automatically
  // The 'uid' claim stores the user's database ID, which we
  // extract in ValidateToken via Content.data.I['uid'].
  Result := FJwt.Compute(
    ['uid', aUserId],
    'ms.auth'
    );
end;

destructor TBlogJwt.Destroy;
begin
  FJwt.Free;
  inherited Destroy;
end;

function TBlogJwt.ValidateToken(
  const aToken: RawUtf8;
  out aUserId: TID
  ): boolean;
var
  Content: TJwtContent;
begin
  // TJwtHS256.Verify checks the HMAC signature, expiration (exp),
  // and issuer (iss). Results go into Content.result (jwtValid,
  // jwtInvalidSignature, jwtExpired, etc.).
  FJwt.Verify(aToken, Content);
  Result := (Content.result = jwtValid);
  if Result then
    // Content.data is a TDocVariantData holding all JWT claims.
    // .I['uid'] extracts the 'uid' claim as a 64-bit integer.
    aUserId := Content.data.I['uid']
  else
    aUserId := 0;
end;

end.
