# Project Status

_Last updated: 2026-04-14 (Session 6, /mxSave: ADR-0001 + PLAN-cross-service-cascades + Session Notes via /mxMigrateToDb in Knowledge-DB migriert)_

## Implemented Features

- 2026-04-13 (Session 1): Projekt in mxLore registriert (id=4), initiale Wissensbasis angelegt.
- 2026-04-13 (Session 2): Wissensbasis vertieft (7 neue Docs), 6/10 offene Punkte via Code verifiziert.
- 2026-04-13 (Session 3):
  - IConfig-Fehlbefund korrigiert; ADR #18 „SQLite pro Microservice".
  - Test-Audit: Docs #19 (Coverage-Map 150+31 Tests) + #20 (Implizite Invarianten).
  - Spec #21, Spec #22 (ms.events), Plan #23 angelegt; M0-Entscheidungen getroffen; T05+T06 implementiert.
- 2026-04-13 (Session 4): **ms.events Stufe 1 vollständig implementiert**. User bestätigt: Build grün.
  - T07+T08: Ring-Buffer (1000) + WebSocket-Broker + Failure-Threshold=3.
  - T09: `TTestEventStream` (6 Prozeduren) + `TTestEventStreamRecorder`.
  - T10: `start-all.cmd`/`stop-all.cmd`/`status.cmd` für 11 Services angepasst; `EventsUrl` in `TMicroServiceConfig`.
  - T11: Producer in `ms.posts` (best-effort Publish nach Commit, Snapshot-vor-Free).
  - T12: Consumer in `ms.analytics` (`TPostPublishedConsumer`, `PostsPublishedViaEvents`-Counter).
  - T13: `TTestEventBusRoundtrip` — echter WS-Roundtrip, 2s-Timeout.
  - T14: Doc #26 Erfahrungsbericht + **Go** für Stufe 2.
- 2026-04-14 (Session 5): **ms.events Stufe 2 vollständig** + **Cross-Service-Cascade-Pipeline live**. Build grün, alle Tests grün.
  - **Plan #23 Stufe 2 (T15–T18)**: `TOrmEventOutbox` + `TOrmConsumerCursor` Models, Persist-on-Publish + ORM-Catch-up + Acknowledge/Cursor-Upsert mit Monotonic-Guard, `TEventPublisher` Shared-Client (Ring-Buffer + Worker + Retry, `MAX_PUBLISH_ATTEMPTS=5`), `TTestEventStreamPersistence` (5 Tests).
  - **ADR-0001 (Knowledge-DB, doc_id=31)**: Cross-Service-Datenkonsistenz ausschließlich via Domain-Events; adressiert Spec #21 Kaskaden-Policy.
  - **PLAN-cross-service-cascades (Knowledge-DB, doc_id=32)**: 12/12 Tasks (T1 Event-Konstanten + Schema-v1, T2 `TEventPublisher`-Lifecycle in `TPostsServer`, T3 `PostDeleted`-Enqueue im `Remove`-Handler, T4 `ms.comments`-Subscriber, T5 `TCommentCascadeConsumer` Cascade-DELETE, T6 Idempotenz-Tests, T7 Reconnect-Thread, T8 End-to-End-Test über echten Bus, T9 Replay-Idempotenz-Test, T10 `ms.events/readme.md` aktualisiert, T11 dieser Status-Update, T12 manueller End-to-End offen).
  - **Stabilitäts-Fixes nach manuellem Test**: Master-`try/except` in `TCommentCascadeConsumer.OnEvent` (Crash bei stop-all behoben); `FShutdown`-Flag + Drop-References-statt-Unsubscribe in `TCommentsServer.DoFinalize` (44s → <1s Shutdown).
  - **Doku neu**: `.claude/event-bus.md` (~280 Zeilen, Englisch) — komplette Pipeline-Doku inkl. Mermaid-Diagramme + Shutdown-Discipline-Abschnitt; Index-Eintrag in `.claude/README.md`.
  - **Memory neu (3 Einträge)**: `feedback_idempchar_unit` (`IdemPChar` lebt in `mormot.core.unicode`), `feedback_ws_callback_exception_safety` (Master-try/except in WS-Callbacks), `feedback_ws_shutdown_no_callback` (keine synchronen Bus-Calls beim Shutdown).

## Knowledge Base (mxLore)

- Architektur/Referenz: #1, #2, #8, #9, #12, #13, #14
- Risiken/Fragen: #6, #10, #11, #20
- Tests: #19 (Coverage-Map), #20 (Invarianten)
- Entscheidungen: #5 (Katalog), #18 (ADR SQLite-pro-Service)
- Specs: #3 (Scope), #21 (Test-Coverage-Gaps — Kaskaden-Teil durch ADR-0001 adressiert; Moderation-Autorisierung weiterhin offen), #22 (ms.events)
- Plans: #23 (ms.events — T01–T18 erledigt, abgeschlossen)
- Decisions: #31 ADR-0001 (Cross-Service-Cascades via Domain-Events)
- Plans: #32 PLAN-cross-service-cascades (12/12 ✓, T12 manueller E2E-Test am 2026-04-14 bestätigt)
- Reflektion/Lessons: #26 (Stufe-1-Bericht), #15 (archiviert), #24, + neue Session-4-Lessons

## Active Workflows

- (keine — Plan #23 abgeschlossen, PLAN-cross-service-cascades 12/12 ✓)

## Next Steps

- mxLore-Docs #2 / #13 Update (Microservice-Übersicht / ADR-Katalog) — ADR-0001 (#31) einpflegen.
- Spec #21 Restpunkt: **Moderation-Autorisierung** als ADR klären (Kaskaden-Teil ist durch ADR-0001 adressiert).
- ms.events Folge-Themen (Backlog, kein aktiver Plan): aktive WebSocket-Liveness-Detection auf Consumer-Seite, Outbox-Cleanup-Job, Dead-Letter-Pfad.

## Open Bugs

- (keine)
