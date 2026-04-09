# Blog Microservices -- Implementation Plan

Status: **Implementation complete** (as of 2026-04-08)

## Phase 1: Foundation (Shared Code) -- DONE

- `ms.shared.pas` -- Constants, config loading, TextToSlug, GuessMimeType
- `ms.shared.api.pas` -- SOA interface definitions (IAuth, IUser, IPost, ITag, IComment, IMedia, IBlog, IAnalytics, IConfig, ILogIngestion, ILogQuery)
- `ms.shared.jwt.pas` -- JWT token creation and validation
- `ms.shared.correlation.pas` -- X-Correlation-Id threadvar + helpers (`LogWithCorrelation`)
- `ms.shared.logclient.pas` -- `TLogShipper` (EchoCustom + queue + background thread)
- `ms.shared.service.pas` -- TMicroService base class (run loop, health, shutdown, correlation wrapper, log shipper), RegisterService, OrmGetById, OrmGetAll

## Phase 2: Backend Services -- DONE

| Service | ORM Classes | SOA Interface | Status |
|---------|-------------|---------------|--------|
| ms.users | TOrmAuthor | IUser | Done |
| ms.auth | TOrmAuthUser | IAuth (SCRAM-MCF) | Done |
| ms.posts | TOrmBlogPost | IPost | Done |
| ms.tags | TOrmBlogTag, TOrmPostTag | ITag | Done |
| ms.comments | TOrmBlogComment | IComment | Done |
| ms.media | TOrmMediaFile | IMedia | Done |
| ms.config | -- | IConfig | Done |
| ms.analytics | -- | IAnalytics | Done |
| ms.logs | TOrmLogEntry, TOrmLogEntryFts | ILogIngestion + ILogQuery | Done |

## Phase 3: Gateway -- DONE

- Transparent SOA proxying (no manual proxy classes)
- IBlog aggregation service (GetPostFull)
- Static file serving (SPA from www/)
- CORS handling
- Client factories with ResultAsJsonObjectWithoutResult

## Phase 4: Web Frontend -- DONE

- SPA with vanilla JavaScript (no dependencies)
- SCRAM-MCF login in browser (PBKDF2 via Web Crypto API)
- Post list, single view, comments
- Author dashboard, post editor
- Comment moderation

## Phase 5: Testing -- DONE

- In-process integration tests (all services in one executable)
- In-memory SQLite (SQLITE_MEMORY_DATABASE_NAME)
- 130+ assertions covering positive and negative cases
- TSynTestCase framework from mORMot2

## Phase 6: Operations -- DONE

- TSynLog configuration with rotation
- Management endpoints: GET /api/health, POST /api/shutdown
- Operations scripts: start-all.cmd, stop-all.cmd, status.cmd, seed-data.cmd
- Input validation on all Add methods
- Upload size limit (3 MB)

## Phase 7: Observability -- DONE

- `X-Correlation-Id` propagation (threadvar + `OnBeforeCall`) -- see [correlation-ids.md](correlation-ids.md)
- Central logging service `ms.logs` (port 8089) -- see [central-logging.md](central-logging.md)
  - `TLogShipper` in `ms.shared.logclient.pas` ships every log line via `ILogIngestion`
  - SQLite FTS5 (`TOrmFts5`) for full-text search over log messages
  - `ILogQuery` proxied through the gateway
  - Browser UI at `/logs` with service/level/correlation-ID pivots

## Notes for Future Work

### ORM Naming Convention
ORM class names must not match their SOA interface name after stripping
the TOrm/I prefixes. mORMot2 reports a routing conflict otherwise.
Example: `IPost` + `TOrmPost` -> conflict! Solution: `TOrmBlogPost`.

### SOA Parameter Format
Most service methods use typed DTO records (e.g. `TPostCreateDto`, `TAuthorDto`) for
both input and output. mORMot2 serializes these directly to/from JSON objects.

`RawJson` is still used in two cases:
- **Update methods** (PATCH semantics): `const aData: RawJson` -- allows partial updates
  where only the fields present in the JSON are modified.
- **IConfig**: schema-less configuration data that varies per service.

`RawJson` parameters must be passed as JSON objects (not strings) in the array:
- Correct: `[{"Name":"Delphi"}]`
- Wrong: `["{\"Name\":\"Delphi\"}"]`
