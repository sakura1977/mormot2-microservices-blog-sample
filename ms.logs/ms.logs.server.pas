/// <summary>
///   Central logging microservice. Receives log entries from every other service via the <c>ILogIngestion</c>
///   interface and exposes a typed query API via <c>ILogQuery</c>.
///
///   Two SOA implementations live in this unit:
///   <list>
///   <item><c>TLogIngestionService</c> -- write path. Stores incoming batches in <c>TOrmLogEntry</c> and mirrors
///     the message text to the FTS5 virtual table for full-text search.</item>
///   <item><c>TLogQueryService</c> -- read path. Provides ByCorrelationId, Recent, Search and Stats queries.</item>
///   </list>
///
///   The service is intentionally tolerant: ingestion never fails the producing service even if the database is
///   busy, and queries return empty arrays rather than exceptions when no rows match.
///
///   See <c>.claude/central-logging.md</c> for the architectural overview.
/// </summary>
unit ms.logs.server;

{$SCOPEDENUMS ON}
{$I mormot.defines.inc}
{$WARN SYMBOL_PLATFORM OFF}
{$WARN UNIT_PLATFORM OFF}

interface

uses
  System.SysUtils,
  mormot.core.base,
  mormot.core.datetime,
  mormot.core.log,
  mormot.core.os,
  mormot.core.text,
  mormot.core.unicode,
  mormot.orm.base,
  mormot.orm.core,
  mormot.rest.core,
  mormot.rest.server,
  mormot.rest.sqlite3,
  mormot.soa.core,
  mormot.soa.server,
  ms.logs.model,
  ms.shared,
  ms.shared.api,
  ms.shared.correlation,
  ms.shared.service;

type

  /// <summary>
  ///   Implements <c>ILogIngestion</c>. Stores each batch in a single SQLite transaction. The correlation ID
  ///   (if present) is parsed out of the message text by <c>ExtractCorrelationIdFromMessage</c>.
  /// </summary>
  TLogIngestionService = class(TInterfacedObject, ILogIngestion)
  strict private
    /// <summary>
    ///   Injected ORM interface used for batched inserts.
    /// </summary>
    FOrm: IRestOrm;
  public

    /// <summary>
    ///   Creates the ingestion service with the given ORM interface.
    /// </summary>
    /// <param name="aOrm">
    ///   The ORM interface (typically <c>FRestServer.Orm</c>).
    /// </param>
    constructor Create(
      const aOrm: IRestOrm
      );

    /// <summary>
    ///   Persists a batch of log entries. Inserts both the regular row and the FTS5 row in the same transaction.
    /// </summary>
    /// <param name="aEntries">
    ///   The entries to persist. Each carries its own service name, timestamp, level and message text.
    /// </param>
    procedure AppendBatch(
      const aEntries: TLogEntryIngestDtoArray
      );
  end;

  /// <summary>
  ///   Implements <c>ILogQuery</c>. Reads from <c>TOrmLogEntry</c> and the parallel FTS5 table for full-text
  ///   searches. All methods return empty arrays/zero records on miss rather than raising exceptions.
  /// </summary>
  TLogQueryService = class(TInterfacedObject, ILogQuery)
  strict private
    /// <summary>
    ///   Injected ORM interface used for read queries.
    /// </summary>
    FOrm: IRestOrm;
  public

    /// <summary>
    ///   Creates the query service with the given ORM interface.
    /// </summary>
    /// <param name="aOrm">
    ///   The ORM interface.
    /// </param>
    constructor Create(
      const aOrm: IRestOrm
      );

    /// <summary>
    ///   Returns every log entry that belongs to one user request, sorted by timestamp ascending.
    /// </summary>
    /// <param name="aId">
    ///   The correlation ID to look up.
    /// </param>
    /// <returns>
    ///   Matching entries, or empty array if none found.
    /// </returns>
    function ByCorrelationId(
      const aId: RawUtf8
      ): TLogEntryDtoArray;

    /// <summary>
    ///   Returns recent log entries matching the supplied filter, sorted by timestamp descending.
    /// </summary>
    /// <param name="aFilter">
    ///   Filter parameters. Empty/zero fields disable the corresponding filter.
    /// </param>
    /// <returns>
    ///   Matching entries.
    /// </returns>
    function Recent(
      const aFilter: TLogQueryFilter
      ): TLogEntryDtoArray;

    /// <summary>
    ///   Full-text search across the message column using SQLite FTS5.
    /// </summary>
    /// <param name="aText">
    ///   The FTS5 match expression.
    /// </param>
    /// <param name="aLimit">
    ///   Maximum rows to return (clamped to 1..1000).
    /// </param>
    /// <returns>
    ///   Matching entries sorted by timestamp descending.
    /// </returns>
    function Search(
      const aText: RawUtf8;
      aLimit: integer
      ): TLogEntryDtoArray;

    /// <summary>
    ///   Returns aggregate counts: total entries, time range, per-service breakdown.
    /// </summary>
    /// <returns>
    ///   The current statistics snapshot.
    /// </returns>
    function Stats: TLogStatsDto;
  end;

  /// <summary>
  ///   Microservice server hosting the central logging service. Wires the ORM model
  ///   (<c>TOrmLogEntry</c> + <c>TOrmLogEntryFts</c>) and registers both SOA implementations.
  /// </summary>
  TLogsServer = class(TMicroService)
  strict private
    /// <summary>
    ///   The ingestion service implementation instance.
    /// </summary>
    FIngestionImpl: TLogIngestionService;

    /// <summary>
    ///   The query service implementation instance.
    /// </summary>
    FQueryImpl: TLogQueryService;
  protected

    /// <summary>
    ///   Creates the ORM model with both the regular and FTS5 log tables.
    /// </summary>
    /// <returns>
    ///   A new <c>TOrmModel</c> for the logging service.
    /// </returns>
    function CreateModel: TOrmModel; override;

    /// <summary>
    ///   Registers <c>ILogIngestion</c> and <c>ILogQuery</c> on the REST server.
    /// </summary>
    procedure SetupServices; override;
  end;

/// <summary>
///   Extracts a correlation ID (UUID) from a log message text. Looks for the first sequence matching the
///   <c>[xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx]</c> pattern that <c>LogWithCorrelation</c> emits.
/// </summary>
/// <param name="aMessage">
///   The log line text.
/// </param>
/// <returns>
///   The 36-character UUID without surrounding brackets, or an empty string if no UUID was found.
/// </returns>
function ExtractCorrelationIdFromMessage(
  const aMessage: RawUtf8
  ): RawUtf8;

implementation

function ExtractCorrelationIdFromMessage(
  const aMessage: RawUtf8
  ): RawUtf8;
const
  UUID_LEN = 36;
var
  StartIdx, ScanIdx, EndIdx: PtrInt;
  CharValue: AnsiChar;
  Hyphens: integer;
begin
  // The LogWithCorrelation helper produces lines beginning with '[<uuid>] ' so we look for an opening bracket
  // followed by exactly 36 characters of UUID syntax. This avoids a regex dependency and is fast enough for
  // the ingestion path.
  Result := '';
  StartIdx := PosEx('[', aMessage, 1);
  while StartIdx > 0 do
  begin
    EndIdx := StartIdx + 1 + UUID_LEN;
    if (EndIdx <= Length(aMessage)) and (aMessage[EndIdx] = ']') then
    begin
      Hyphens := 0;
      for ScanIdx := StartIdx + 1 to EndIdx - 1 do
      begin
        CharValue := aMessage[ScanIdx];
        if CharValue = '-' then
        begin
          Inc(Hyphens);
          continue;
        end;
        if not (CharValue in ['0'..'9', 'a'..'f', 'A'..'F']) then
        begin
          Hyphens := -1;
          break;
        end;
      end;
      if Hyphens = 4 then
      begin
        Result := LowerCase(Copy(aMessage, StartIdx + 1, UUID_LEN));
        Exit;
      end;
    end;
    StartIdx := PosEx('[', aMessage, StartIdx + 1);
  end;
end;

function LogEntryToDto(
  aRec: TOrmLogEntry
  ): TLogEntryDto;
begin
  Result.ID := aRec.IDValue;
  Result.ServiceName := aRec.ServiceName;
  Result.Timestamp := aRec.Timestamp;
  Result.Level := aRec.Level;
  Result.CorrelationId := aRec.CorrelationId;
  Result.Message := aRec.Message;
end;

function LogEntriesFromQuery(
  const aOrm: IRestOrm;
  const aWhere: RawUtf8
  ): TLogEntryDtoArray;
var
  Rec: TOrmLogEntry;
  Count: PtrInt;
begin
  Result := nil;
  Count := 0;
  Rec := TOrmLogEntry.CreateAndFillPrepare(aOrm, aWhere);
  try
    SetLength(Result, Rec.FillTable.RowCount);
    while Rec.FillOne do
    begin
      Result[Count] := LogEntryToDto(Rec);
      Inc(Count);
    end;
    SetLength(Result, Count);
  finally
    Rec.Free;
  end;
end;

constructor TLogIngestionService.Create(
  const aOrm: IRestOrm
  );
begin
  inherited Create;
  FOrm := aOrm;
end;

procedure TLogIngestionService.AppendBatch(
  const aEntries: TLogEntryIngestDtoArray
  );
var
  EntryIdx: PtrInt;
  Rec: TOrmLogEntry;
  Fts: TOrmLogEntryFts;
  NewId: TID;
begin
  if Length(aEntries) = 0 then
    Exit;
  // Wrap the whole batch in one SQLite transaction so the regular and FTS5 inserts stay in sync and the
  // disk write cost is amortized across the batch.
  FOrm.TransactionBegin(TOrmLogEntry);
  try
    for EntryIdx := 0 to High(aEntries) do
    begin
      Rec := TOrmLogEntry.Create;
      try
        Rec.Timestamp := aEntries[EntryIdx].Timestamp;
        Rec.ServiceName := aEntries[EntryIdx].ServiceName;
        Rec.Level := aEntries[EntryIdx].Level;
        Rec.Message := aEntries[EntryIdx].Message;
        Rec.CorrelationId := ExtractCorrelationIdFromMessage(aEntries[EntryIdx].Message);
        NewId := FOrm.Add(Rec, True);
      finally
        Rec.Free;
      end;
      if NewId > 0 then
      begin
        Fts := TOrmLogEntryFts.Create;
        try
          Fts.IDValue := NewId;
          Fts.Message := aEntries[EntryIdx].Message;
          FOrm.Add(Fts, True, True);
        finally
          Fts.Free;
        end;
      end;
    end;
    FOrm.Commit;
  except
    FOrm.RollBack;
    raise;
  end;
end;

constructor TLogQueryService.Create(
  const aOrm: IRestOrm
  );
begin
  inherited Create;
  FOrm := aOrm;
end;

function TLogQueryService.ByCorrelationId(
  const aId: RawUtf8
  ): TLogEntryDtoArray;
begin
  if aId = '' then
    Exit(nil);
  // UUIDs only contain hex chars and hyphens, so a single-quote literal is safe (no escaping needed).
  Result := LogEntriesFromQuery(FOrm,
    FormatUtf8('CorrelationId=''%'' ORDER BY Timestamp ASC', [aId]));
end;

function TLogQueryService.Recent(
  const aFilter: TLogQueryFilter
  ): TLogEntryDtoArray;
var
  WhereClause, IsoSince, IsoUntil: RawUtf8;
  Limit: integer;
begin
  WhereClause := '';
  if aFilter.ServiceName <> '' then
    WhereClause := FormatUtf8('ServiceName=''%''', [aFilter.ServiceName]);
  if aFilter.MinLevel > 0 then
  begin
    if WhereClause <> '' then
      WhereClause := WhereClause + ' AND ';
    WhereClause := WhereClause + FormatUtf8('Level>=%', [aFilter.MinLevel]);
  end;
  if aFilter.Since > 0 then
  begin
    IsoSince := DateTimeToIso8601(aFilter.Since, True);
    if WhereClause <> '' then
      WhereClause := WhereClause + ' AND ';
    WhereClause := WhereClause + FormatUtf8('Timestamp>=''%''', [IsoSince]);
  end;
  if aFilter.UntilTime > 0 then
  begin
    IsoUntil := DateTimeToIso8601(aFilter.UntilTime, True);
    if WhereClause <> '' then
      WhereClause := WhereClause + ' AND ';
    WhereClause := WhereClause + FormatUtf8('Timestamp<=''%''', [IsoUntil]);
  end;
  if WhereClause = '' then
    WhereClause := 'RowID>0';
  Limit := aFilter.Limit;
  if Limit <= 0 then
    Limit := 100;
  if Limit > 1000 then
    Limit := 1000;
  Result := LogEntriesFromQuery(FOrm,
    WhereClause + FormatUtf8(' ORDER BY Timestamp DESC LIMIT %', [Limit]));
end;

function TLogQueryService.Search(
  const aText: RawUtf8;
  aLimit: integer
  ): TLogEntryDtoArray;
var
  Limit: integer;
  WhereClause: RawUtf8;
begin
  if aText = '' then
    Exit(nil);
  Limit := aLimit;
  if Limit <= 0 then
    Limit := 100;
  if Limit > 1000 then
    Limit := 1000;
  // Join the regular table to the FTS5 virtual table by RowID. SQLite FTS5 syntax: MATCH '<query>'.
  WhereClause := FormatUtf8(
    'RowID IN (SELECT RowID FROM LogEntryFts WHERE Message MATCH ''%'' LIMIT %) ORDER BY Timestamp DESC',
    [aText, Limit]);
  Result := LogEntriesFromQuery(FOrm, WhereClause);
end;

function TLogQueryService.Stats: TLogStatsDto;
var
  Rec: TOrmLogEntry;
  ServiceIdx, ResultIdx: PtrInt;
begin
  Finalize(Result);
  FillCharFast(Result, SizeOf(Result), 0);
  Result.TotalEntries := FOrm.TableRowCount(TOrmLogEntry);
  if Result.TotalEntries = 0 then
    Exit;
  // Iterate every row once, aggregating in Pascal. This avoids SQL aggregate aliases (which mORMot2's
  // typed table accessors don't expose cleanly) and works on any backing store. For very large log stores
  // this could be replaced with raw SQL via TRestServerDB.DB.Execute, but for the demo it's plenty fast.
  Rec := TOrmLogEntry.CreateAndFillPrepare(FOrm, '');
  try
    while Rec.FillOne do
    begin
      // Update overall time range
      if (Result.OldestEntry = 0) or (Rec.Timestamp < Result.OldestEntry) then
        Result.OldestEntry := Rec.Timestamp;
      if Rec.Timestamp > Result.NewestEntry then
        Result.NewestEntry := Rec.Timestamp;
      // Find or create the per-service stat row
      ResultIdx := -1;
      for ServiceIdx := 0 to High(Result.Services) do
        if Result.Services[ServiceIdx].ServiceName = Rec.ServiceName then
        begin
          ResultIdx := ServiceIdx;
          break;
        end;
      if ResultIdx < 0 then
      begin
        SetLength(Result.Services, Length(Result.Services) + 1);
        ResultIdx := High(Result.Services);
        Result.Services[ResultIdx].ServiceName := Rec.ServiceName;
      end;
      Inc(Result.Services[ResultIdx].TotalCount);
      // sllWarning ordinal is 4, sllError is 5 in mORMot2's TSynLogLevel enum.
      if Rec.Level = 4 then
        Inc(Result.Services[ResultIdx].WarningCount)
      else if Rec.Level >= 5 then
        Inc(Result.Services[ResultIdx].ErrorCount);
    end;
  finally
    Rec.Free;
  end;
end;

function TLogsServer.CreateModel: TOrmModel;
begin
  Result := TOrmModel.Create([TOrmLogEntry, TOrmLogEntryFts], MODEL_ROOT);
end;

procedure TLogsServer.SetupServices;
begin
  FIngestionImpl := TLogIngestionService.Create(FRestServer.Orm);
  FQueryImpl := TLogQueryService.Create(FRestServer.Orm);
  RegisterService(FIngestionImpl, TypeInfo(ILogIngestion));
  RegisterService(FQueryImpl, TypeInfo(ILogQuery));
end;

end.
