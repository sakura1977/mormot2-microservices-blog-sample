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
    FMcfInfo: RawUtf8;
    FPersistedKey: RawUtf8;
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
    ///   MCF format string without checksum, sent to the client
    ///   during SCRAM challenge (e.g. '$pbkdf2-sha256$310000$salt$').
    /// </summary>
    property McfInfo: RawUtf8 index 200
      read FMcfInfo write FMcfInfo;

    /// <summary>
    ///   SCRAM persisted key derived from MCF hash and email.
    ///   Contains StoredKey and ServerKey for proof verification.
    /// </summary>
    property PersistedKey: RawUtf8 index 200
      read FPersistedKey write FPersistedKey;

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

implementation

end.
