/// <summary>
///   JWT token management for the blog microservices.
///   Wrapper around mormot.crypt.jwt using HMAC-SHA256.
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
  ///   Manages JWT token creation and validation.
  /// </summary>
  TBlogJwt = class
  private
    FJwt: TJwtHS256;
    FSecret: RawUtf8;
  public

    /// <summary>
    ///   Creates a new JWT instance.
    /// </summary>
    /// <param name="aSecret">
    ///   HMAC secret key.
    /// </param>
    /// <param name="aExpirationMinutes">
    ///   Token validity duration in minutes (default: 1440 = 24h).
    /// </param>
    constructor Create(
      const aSecret: RawUtf8;
      aExpirationMinutes: integer = 1440
    );

    /// <summary>
    ///   Releases the internal JWT engine.
    /// </summary>
    destructor Destroy; override;

    /// <summary>
    ///   Creates a signed JWT token for the given user ID.
    /// </summary>
    /// <param name="aUserId">
    ///   The user ID to embed in the token.
    /// </param>
    /// <returns>
    ///   The signed JWT token string.
    /// </returns>
    function CreateToken(aUserId: TID): RawUtf8;

    /// <summary>
    ///   Validates a JWT token.
    ///   Returns True and sets aUserId if the token is valid.
    /// </summary>
    /// <param name="aToken">
    ///   The JWT token to validate.
    /// </param>
    /// <param name="aUserId">
    ///   Receives the user ID if validation succeeds.
    /// </param>
    /// <returns>
    ///   True if the token is valid, False otherwise.
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
  FJwt := TJwtHS256.Create(
    FSecret,
    0,  // aPBKDF2Round: no PBKDF2 on the key
    [jrcIssuer, jrcExpirationTime, jrcIssuedAt],
    [],  // no audience
    aExpirationMinutes
  );
end;

function TBlogJwt.CreateToken(aUserId: TID): RawUtf8;
begin
  Result := FJwt.Compute(
    ['uid', aUserId],  // custom claims
    'ms.auth'          // issuer
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
  FJwt.Verify(aToken, Content);
  Result := (Content.result = jwtValid);
  if Result then
  begin
    aUserId := Content.data.I['uid'];
  end
  else
  begin
    aUserId := 0;
  end;
end;

end.
