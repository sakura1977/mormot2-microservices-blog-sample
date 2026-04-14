/// <summary>
///   ORM model for the Events service (stage 2 of SPEC #22 / PLAN #23, task T15).
///
///   Two tables back the persistent event bus:
///   <list>
///     <item><c>TOrmEventOutbox</c> -- one row per published event. The <c>RowID</c> assigned by
///       SQLite becomes the bus-wide monotonic event ID transported in <c>TEventDto.ID</c>. All
///       fields mirror <c>TEventDto</c> 1:1 so <c>Persist-on-Publish</c> (T16) is a straight
///       copy. <c>EventType</c>, <c>ProducerService</c> and <c>CorrelationId</c> are indexed to
///       keep catch-up filters and trace lookups cheap.</item>
///     <item><c>TOrmConsumerCursor</c> -- one row per logical consumer
///       (<c>ConsumerName</c> is unique). <c>LastEventId</c> is advanced by
///       <c>IEventStream.Acknowledge</c> (T16) so reconnecting consumers can resume with
///       <c>aFromEventId = -1</c> without losing or replaying events.</item>
///   </list>
///
///   Both tables live in the per-service SQLite DB <c>ms.events.db</c>; cross-service joins are
///   never performed in-process (matches the project-wide separate-DB-per-service decision).
/// </summary>
unit ms.events.model;

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
  ///   Persistent outbox row. Mirrors <c>TEventDto</c> field-for-field; the inherited
  ///   <c>TOrm.ID</c> carries the bus-assigned monotonic event ID.
  /// </summary>
  TOrmEventOutbox = class(TOrm)
  private
    FEventType: RawUtf8;
    FPayloadJson: RawUtf8;
    FProducerService: RawUtf8;
    FCreatedAt: TDateTime;
    FCorrelationId: RawUtf8;
    FSchemaVersion: integer;
  published

    /// <summary>
    ///   Logical event type, e.g. <c>'PostPublished'</c>. Indexed for catch-up filters.
    /// </summary>
    property EventType: RawUtf8 index 100
      read FEventType write FEventType;

    /// <summary>
    ///   Opaque JSON payload as published. Length is unbounded (no <c>index</c> hint).
    /// </summary>
    property PayloadJson: RawUtf8
      read FPayloadJson write FPayloadJson;

    /// <summary>
    ///   Name of the producing service (<c>SERVICE_POSTS</c>, ...). Indexed for per-producer
    ///   replay and audit queries.
    /// </summary>
    property ProducerService: RawUtf8 index 64
      read FProducerService write FProducerService;

    /// <summary>
    ///   UTC timestamp at which the bus accepted the event.
    /// </summary>
    property CreatedAt: TDateTime
      read FCreatedAt write FCreatedAt;

    /// <summary>
    ///   Correlation ID of the originating request, propagated from <c>TEventDto.CorrelationId</c>.
    ///   Indexed so trace joins across services stay cheap.
    /// </summary>
    property CorrelationId: RawUtf8 index 64
      read FCorrelationId write FCorrelationId;

    /// <summary>
    ///   Payload schema revision. Starts at 1, incremented on breaking payload changes.
    /// </summary>
    property SchemaVersion: integer
      read FSchemaVersion write FSchemaVersion;
  end;

  /// <summary>
  ///   Persistent per-consumer cursor. <c>ConsumerName</c> is unique; <c>LastEventId</c> stores
  ///   the highest <c>TOrmEventOutbox.ID</c> the consumer has acknowledged via
  ///   <c>IEventStream.Acknowledge</c>.
  /// </summary>
  TOrmConsumerCursor = class(TOrm)
  private
    FConsumerName: RawUtf8;
    FLastEventId: TID;
    FUpdatedAt: TDateTime;
  published

    /// <summary>
    ///   Stable consumer identifier as passed to <c>IEventStream.Subscribe</c>. Unique because
    ///   each logical consumer owns exactly one cursor row.
    /// </summary>
    property ConsumerName: RawUtf8 index 100
      read FConsumerName write FConsumerName stored AS_UNIQUE;

    /// <summary>
    ///   Highest event <c>ID</c> the consumer has durably processed. Resume-from-cursor reads
    ///   <c>WHERE ID &gt; LastEventId</c>.
    /// </summary>
    property LastEventId: TID
      read FLastEventId write FLastEventId;

    /// <summary>
    ///   UTC timestamp of the last <c>Acknowledge</c> call. Useful for stale-consumer detection.
    /// </summary>
    property UpdatedAt: TDateTime
      read FUpdatedAt write FUpdatedAt;
  end;

implementation

end.
