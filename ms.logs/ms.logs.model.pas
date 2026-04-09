/// <summary>
///   ORM model for the central logging service.
///
///   Stores one row per log entry from any other microservice. The schema is intentionally narrow:
///   timestamp + level + service name for filtering, correlation ID for distributed tracing, and the full
///   message text for display and full-text search.
///
///   Two TOrm classes are defined:
///   <list>
///   <item>
///     <c>TOrmLogEntry</c> -- the regular table containing every column. Indexes on <c>Timestamp</c>,
///     <c>ServiceName</c>, <c>Level</c> and <c>CorrelationId</c> make the typed query methods fast.
///   </item>
///   <item>
///     <c>TOrmLogEntryFts</c> -- a parallel SQLite FTS5 virtual table over the <c>Message</c> column. Used by
///     <c>ILogQuery.Search</c> to support phrase queries like "connection AND timeout" without scanning the
///     whole table.
///   </item>
///   </list>
///
///   The two tables are kept in sync at insert time -- both Adds happen in the same SQLite transaction.
/// </summary>
unit ms.logs.model;

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
  ///   One log entry persisted by the central logging service. The <c>CorrelationId</c> is parsed from the message
  ///   text by the ingestion service before storage, so queries can filter on it efficiently via the index.
  /// </summary>
  TOrmLogEntry = class(TOrm)
  private
    FTimestamp: TDateTime;
    FServiceName: RawUtf8;
    FLevel: integer;
    FCorrelationId: RawUtf8;
    FMessage: RawUtf8;
  published

    /// <summary>
    ///   When the log line was emitted (UTC). Indexed for time-range queries.
    /// </summary>
    property Timestamp: TDateTime
      read FTimestamp write FTimestamp;

    /// <summary>
    ///   The producing service identifier (e.g. <c>ms.posts</c>).
    /// </summary>
    property ServiceName: RawUtf8 index 32
      read FServiceName write FServiceName;

    /// <summary>
    ///   <c>TSynLogLevel</c> ordinal (0 = none, ..., 12 = exception).
    /// </summary>
    property Level: integer
      read FLevel write FLevel;

    /// <summary>
    ///   Correlation ID extracted from the message text, or empty if none was present.
    /// </summary>
    property CorrelationId: RawUtf8 index 64
      read FCorrelationId write FCorrelationId;

    /// <summary>
    ///   The full log line text (potentially truncated to a sane upper bound by the ingestion service).
    /// </summary>
    property Message: RawUtf8
      read FMessage write FMessage;
  end;

  /// <summary>
  ///   Parallel FTS5 virtual table over the <c>Message</c> column of <c>TOrmLogEntry</c>. Each row is identified by
  ///   the same <c>RowID</c> as the underlying entry, so a join is straightforward.
  ///
  ///   mORMot2 maps this class to <c>CREATE VIRTUAL TABLE LogEntryFts USING fts5(Message)</c> automatically because
  ///   the class derives from <c>TOrmFts5</c>.
  /// </summary>
  TOrmLogEntryFts = class(TOrmFts5)
  private
    FMessage: RawUtf8;
  published

    /// <summary>
    ///   Indexed message text. Same value as the corresponding <c>TOrmLogEntry.Message</c>.
    /// </summary>
    property Message: RawUtf8
      read FMessage write FMessage;
  end;

implementation

end.
