# ms.events — Event-Bus (Lern-Service)

Port **8091** | Interfaces **IEventPublisher** + **IEventStream** | Eigene SQLite-DB `ms.events.db` (`TOrmEventOutbox`, `TOrmConsumerCursor`) | HTTP + WebSocket auf demselben Port

Event-Bus für interne Service-zu-Service-Benachrichtigungen. Stage 2 (T15–T18) ist eingebaut: jeder publizierte Event wird in `TOrmEventOutbox` persistiert (RowID = bus-event-ID), Subscriber bekommen Catch-up entweder ab einer expliziten Event-ID oder ab `TOrmConsumerCursor.LastEventId + 1` (`aFromEventId = -1`), `Acknowledge(name, id)` upserts den Cursor mit Monotonie-Guard.

## Zweck
Lernübung zu Outbox-Pattern, WebSocket-Fanout und Cursor-basiertem Replay im bestehenden Stack (mORMot2 + SQLite, keine externen Libs). Spezifikation: mxLore Doc #22. Plan: mxLore Doc #23.

## Stufen
- **Stufe 1 (MVP, T06–T13, fertig)**: In-Memory-Ring-Buffer (1000 Einträge), `IEventPublisher.Publish`, `IEventStream.Subscribe` mit WebSocket-Fanout, Failing-Subscriber-Drop.
- **Stufe 2 (T15–T18, fertig)**:
  - **T15** Models `TOrmEventOutbox` + `TOrmConsumerCursor` (`ms.events/ms.events.model.pas`).
  - **T16** `TEventStreamService` persistiert in der Outbox, dient Catch-up aus der Outbox (löst `EEventBufferOverrun` für stage-2-Pfade ab), `Acknowledge(name, id)` upserts den Cursor.
  - **T17** Shared-Client `TEventPublisher` in `shared/ms.shared.events.pas` (Ring-Buffer + Worker-Thread + Retry mit `MAX_PUBLISH_ATTEMPTS=5`, Backoff `EVENT_RETRY_BACKOFF_MS=1000`).
  - **T18** Test-Coverage in `test/ms.testCases.pas` → `TTestEventStreamPersistence` (Persist, Catch-up beyond ring buffer, Cursor-Upsert, Monotonic-Guard, Resume-from-cursor).

## Stage-1-Fallback
`TEventStreamService.Create(nil)` (Default) lässt die ORM-Pfade weg → reines In-Memory-Verhalten incl. `EEventBufferOverrun` bei Ringbuffer-Overrun. Wird von den Stage-1-Unit-Tests genutzt.

## Cross-Service-Kaskaden
Cross-Service-Datenkonsistenz (z. B. Comments löschen wenn Post weg ist) läuft seit [ADR-0001](../docs/decisions/ADR-0001-cross-service-cascades.md) ausschließlich über Domain-Events auf diesem Bus. Owner-Service publiziert (`ms.posts` → `EVENT_POST_DELETED`), abhängige Services subscriben mit eigenem Cursor (`ms.comments` → `comments.cascade`) und löschen lokal in ihrer eigenen DB. Erstanwendung ist in [PLAN-cross-service-cascades](../docs/plans/PLAN-cross-service-cascades.md) (T1–T12) umgesetzt; Replay-Sicherheit verlangt idempotente Consumer (siehe `EVENT_POST_DELETED`-Doc in `shared/ms.shared.api.pas`).

## Non-Goals
- Kein Ersatz für ms.logs.
- Keine Produktionsreife (Dead-Letter, TTL, Outbox-Cleanup-Job, Multi-Instance-Consumer-Schutz nicht enthalten).
- Keine generische Cascade-Engine — jede Cascade-Beziehung wird konkret implementiert (Producer publiziert, Consumer subscribt + löscht).

## Offene Punkte
- mxLore-Docs #2 / #13 (Microservice-Übersicht / ADR-Katalog) sind im Repo nicht gespiegelt; Update läuft via MCP, sobald wieder erreichbar (ADR-0001 + PLAN-cross-service-cascades sind dann mit-zu-migrieren).
- Stille WebSocket-Disconnects auf Consumer-Seite werden nicht aktiv erkannt; `TCommentsReconnectThread` greift erst, wenn die Subscription sichtbar als nil markiert ist. Echte Liveness (Ping/Pong) ist Folge-Arbeit.
