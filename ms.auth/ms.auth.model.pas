/// <summary>
///   ORM model for the Auth service: login credentials.
/// </summary>
unit ms.auth.model;

{$SCOPEDENUMS ON}
{$I mormot.defines.inc}
{$WARN SYMBOL_PLATFORM OFF}
{$WARN UNIT_PLATFORM OFF}

interface

uses
  mormot.core.base,
  mormot.orm.base,
  mormot.orm.core;

type

  /// <summary>
  ///   Stores authentication credentials for a user account.
  /// </summary>
  TOrmAuthUser = class(TOrm)
  private
    FEmail: RawUtf8;
    FPasswordHash: RawUtf8;
    FSalt: RawUtf8;
    FUserId: TID;
    FIsActive: boolean;
    FCreatedAt: TDateTime;
    FLastLogin: TDateTime;
  published

    /// <summary>
    ///   Unique email address used for authentication.
    /// </summary>
    property Email: RawUtf8 index 200
      read FEmail write FEmail stored AS_UNIQUE;

    /// <summary>
    ///   Hashed password for secure credential storage.
    /// </summary>
    property PasswordHash: RawUtf8 index 200
      read FPasswordHash write FPasswordHash;

    /// <summary>
    ///   Cryptographic salt used for password hashing.
    /// </summary>
    property Salt: RawUtf8 index 100
      read FSalt write FSalt;

    /// <summary>
    ///   Foreign key referencing the associated user profile.
    /// </summary>
    property UserId: TID
      read FUserId write FUserId;

    /// <summary>
    ///   Indicates whether the account is currently active.
    /// </summary>
    property IsActive: boolean
      read FIsActive write FIsActive;

    /// <summary>
    ///   Timestamp when the account was created.
    /// </summary>
    property CreatedAt: TDateTime
      read FCreatedAt write FCreatedAt;

    /// <summary>
    ///   Timestamp of the most recent successful login.
    /// </summary>
    property LastLogin: TDateTime
      read FLastLogin write FLastLogin;
  end;

/// <summary>
///   Creates the ORM model for the Auth service.
/// </summary>
/// <returns>
///   A TOrmModel instance containing TOrmAuthUser.
/// </returns>
function CreateAuthModel: TOrmModel;

implementation

function CreateAuthModel: TOrmModel;
begin
  Result := TOrmModel.Create([TOrmAuthUser]);
end;

end.
