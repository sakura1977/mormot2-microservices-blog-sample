# mORMot2 Microservices Blog Sample

> **AI Start Here** — Read these files to get started:
>
> | Document | Purpose |
> |----------|---------|
> | [CLAUDE.md](./CLAUDE.md) | Architecture, conventions, rules (this file) |
> | [docs/status.md](./docs/status.md) | Current project status, open items |
> | [.claude/README.md](./.claude/README.md) | Topic-indexed deep-dive docs (architecture, event-bus, central-logging, …) |
>
> **Documentation rules (MCP-based):**
> - Decisions ONLY via `/mxDecision` → Knowledge-DB (doc_type='decision')
> - Plans ONLY via `/mxPlan` → Knowledge-DB (doc_type='plan')
> - Specs ONLY via `/mxSpec` → Knowledge-DB (doc_type='spec')
> - `/mxSave` updates CLAUDE.md + docs/status.md (local) + session notes (DB)
> - Search documents: `mx_search(project='mormot2-microservices-blog-sample', ...)` or `mx_briefing(project='mormot2-microservices-blog-sample')`
> - CLAUDE.md stays compact: links + rules + architecture. No long backlogs.

## Project

- **Slug:** mormot2-microservices-blog-sample
- **Stack:** Delphi + mORMot2 (Microservices, REST, WebSockets, SQLite/FTS5)
- **Status:** Active (Knowledge-Base bootstrapped 2026-04-13)

## Architecture (Kurz)

Interface-basierte mORMot2-SOA. Gateway (8080) proxied via `Services.Resolve` zu 10 Backends (8081–8089 plus ms.events 8091). Pro Service eigene SQLite-DB. WebSocket-Callbacks (synopsebin intern, synopsejson für Browser). Auth = SCRAM-MCF + JWT. Observability via Correlation-ID-Threadvar + zentralem ms.logs (FTS5, Live-WebSocket-Stream). Resilience via Token-Bucket-RateLimiter und 3-State-CircuitBreaker (`shared/`). Domain-Event-Bus (ms.events: persistente Outbox, Consumer-Cursor, Replay) trägt Cross-Service-Kaskaden (ADR-0001, siehe `.claude/event-bus.md`).

Details → mxLore:
- Architektur-Zusammenfassung (doc #1)
- Microservice-Übersicht inkl. Ports/DBs/Interfaces (doc #2)
- Projektzweck & Kernfunktionen (doc #3)
- Build/Test/Deployment (doc #4)
- ADR-Kandidaten-Katalog (doc #5)
- Offene Fragen/Risiken (doc #6)

Primärquellen im Repo: `readme.md`, `architecture.md`, `openapi.yaml`, `BlogMicroservices.groupproj`.

## Rules (project-specific)

- Delphi-Style-Guide `.claude/delphiSyntax.md` ist verbindlich (siehe globale Regel).
- Max. 120 Zeichen pro Zeile.
- Separate SQLite-DB pro Service ist bewusste Entscheidung — nicht konsolidieren.
- WebSocket-Browser-Protokoll: `synopsejson` / `TWebSocketProtocolChat` mit Custom-Name (Interop-Einschränkung, siehe Memory).
- Tests nutzen `TSynTestCase` in-process + `:memory:`-SQLite; Exceptions werden still verschluckt → risky Calls explizit mit try/except + CheckEqual absichern.
- WebSocket-Callback-Handler client-seitig (z. B. `IEventStreamCallback.OnEvent`): Master-`try/except` + Shutdown-Flag verpflichtend; während Teardown KEINE synchronen Bus-Calls (Unsubscribe/Acknowledge) — Socket schließen reicht (siehe `.claude/event-bus.md` "Shutdown discipline").
