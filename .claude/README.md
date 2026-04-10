# Blog Microservices -- Documentation

Microservice-based blog system with **Delphi 13** and **mORMot2**.

## Quick Start

```
1. Open BlogMicroservices.groupproj in Delphi
2. Run "Build All"
3. Run start-all.cmd
4. Run seed-data.cmd (demo data)
5. Open http://localhost:8080 in browser
6. Login: max@example.com / demo1234
```

## Documentation

| File | Content |
|------|---------|
| [architecture.md](architecture.md) | Architecture overview, service table, communication principles |
| [services.md](services.md) | Detailed service definitions with SOA interfaces and data models |
| [technology.md](technology.md) | mORMot2 modules, project structure, code patterns, configuration |
| [workflows.md](workflows.md) | Sequence diagrams for all key workflows |
| [correlation-ids.md](correlation-ids.md) | `X-Correlation-Id` propagation, threadvar, `OnBeforeCall` hook, logging |
| [central-logging.md](central-logging.md) | `ms.logs` service, `EchoCustom` shipper, SQLite FTS5, `ILogIngestion` / `ILogQuery` |
| [event-driven.md](event-driven.md) | Interface-based callbacks over WebSockets, live log tail, `ILogStream`, broker pattern, `synopsebin` / `synopsejson` |
| [spa-routing.md](spa-routing.md) | Client-side routing via the History API, SPA fallback in the gateway, route table, link interceptor for shareable URLs |
| [media-and-markdown.md](media-and-markdown.md) | Media upload flow, `GET /media/:id` binary passthrough route, safe Markdown subset renderer (headings, bold, italic, images) |
| [posts-search.md](posts-search.md) | SQLite FTS5 full-text search on posts: parallel virtual table, transactional write sync, backfill, frontend search bar and `/search?q=...` route |
| [circuit-breaker.md](circuit-breaker.md) | `TCircuitBreaker` (Closed/Open/HalfOpen state machine), where it is used (`TBlogService`, `TAnalyticsService`), tuning, tests, and the manual reproduction steps |
| [rate-limiting.md](rate-limiting.md) | `TRateLimiter` token bucket, two-layer auth defence (per-IP at the gateway + per-email in `ms.auth`), refund-on-success, tuning, tests, and the manual reproduction steps |

## Architecture

- **API style**: mORMot2 SOA (interface-based services)
- **URL format**: `POST /api/{ServiceName}/{MethodName}` with JSON array body
- **Authentication**: SCRAM-MCF (PBKDF2-SHA256, client-side hashing)

## Services

| Service | Port | SOA Interface | Description |
|---------|------|---------------|-------------|
| ms.gateway | 8080 | IBlog + Proxies | API gateway + web frontend |
| ms.auth | 8081 | IAuth | SCRAM-MCF authentication, JWT tokens |
| ms.users | 8082 | IUser | Author profiles and bios |
| ms.posts | 8083 | IPost | Blog posts with pagination |
| ms.tags | 8084 | ITag | Tag management (m:n with posts) |
| ms.comments | 8085 | IComment | Comments with moderation workflow |
| ms.media | 8086 | IMedia | Image upload and serving |
| ms.config | 8087 | IConfig | Central configuration registry |
| ms.analytics | 8088 | IAnalytics | Cross-service data aggregation |
| ms.logs | 8089 | ILogIngestion + ILogQuery + ILogStream | Central log aggregation (SQLite FTS5) + live broadcast |

## Technology

- **Language**: Object Pascal (Delphi 13)
- **Framework**: mORMot2
- **Database**: SQLite (one DB per service)
- **Communication**: mORMot2 SOA over REST/HTTP with JSON, plus WebSocket callbacks (`synopsebin` + `synopsejson`) for real-time events (see [event-driven.md](event-driven.md))
- **Authentication**: SCRAM-MCF + JWT (HMAC-SHA256)
- **Frontend**: Vanilla JS SPA (no dependencies)
- **Logging**: TSynLog with rotation (5 x 5 MB per service) + central `ms.logs` ingestion via `EchoCustom` + SQLite FTS5

## Operations Scripts

| Script | Purpose |
|--------|---------|
| `start-all.cmd` | Start all 10 services in correct order |
| `stop-all.cmd` | Graceful shutdown of all services (via POST /api/shutdown) |
| `status.cmd` | Health check all services (via GET /api/health) |
| `seed-data.cmd` | Create demo data (1 author, 3 posts, 4 tags) |

## Project Structure

```
BlogMicroservices.groupproj    IDE project group
start-all.cmd / stop-all.cmd   Operations scripts
seed-data.cmd / status.cmd     Demo data / health checks
shared/                        8 shared units
  ms.shared.pas                  Constants, config, slug generation
  ms.shared.api.pas              SOA interface definitions (IAuth, IUser, ...,
                                   ILogIngestion, ILogQuery)
  ms.shared.jwt.pas              JWT token creation and validation
  ms.shared.correlation.pas      X-Correlation-Id threadvar, helpers,
                                   LogWithCorrelation (see correlation-ids.md)
  ms.shared.logclient.pas        TLogShipper (EchoCustom + queue + background
                                   thread) -- see central-logging.md
  ms.shared.service.pas          TMicroService base class, RegisterService,
                                   OrmGetById, OrmGetAll,
                                   HandleRequestWithCorrelation wrapper
  ms.shared.circuitbreaker.pas   TCircuitBreaker for upstream call protection
                                   (see circuit-breaker.md)
  ms.shared.ratelimiter.pas      TRateLimiter token bucket for brute-force
                                   defence (see rate-limiting.md)
ms.gateway/                    Gateway + www/ frontend (includes /logs UI)
ms.auth/                       Auth service (model + server)
ms.users/                      Users service (model + server)
ms.posts/                      Posts service (model + server)
ms.tags/                       Tags service (model + server)
ms.comments/                   Comments service (model + server)
ms.media/                      Media service (model + server)
ms.config/                     Configuration registry
ms.analytics/                  Cross-service data aggregation
ms.logs/                       Central log aggregation (SQLite FTS5)
test/                          In-process integration tests
  ms.testCases.pas               130+ assertions (positive + negative)
  ms.tests.dpr                   Console test runner
```
