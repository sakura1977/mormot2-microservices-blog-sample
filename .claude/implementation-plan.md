# Blog-Microservices -- Implementierungsplan

Status: **Implementierung abgeschlossen** (Stand: 2026-04-07)

## Phase 1: Grundlagen (Shared Code) -- ERLEDIGT

- `ms.shared.pas` -- Konstanten, Config-Loading, TextToSlug
- `ms.shared.api.pas` -- SOA-Interface-Definitionen (IAuth, IUser, IPost, ITag, IComment, IMedia, IBlog)
- `ms.shared.jwt.pas` -- JWT-Token erstellen und validieren
- `ms.shared.service.pas` -- Basisklasse TMicroService (Run-Loop, Health, Shutdown)

## Phase 2: Backend-Services -- ERLEDIGT

| Service | ORM-Klassen | SOA-Interface | Status |
|---------|-------------|---------------|--------|
| ms.users | TOrmAuthor | IUser | Fertig |
| ms.auth | TOrmAuthUser | IAuth (SCRAM-MCF) | Fertig |
| ms.posts | TOrmBlogPost | IPost | Fertig |
| ms.tags | TOrmBlogTag, TOrmPostTag | ITag | Fertig |
| ms.comments | TOrmBlogComment | IComment | Fertig |
| ms.media | TOrmMediaFile | IMedia | Fertig |

## Phase 3: Gateway -- ERLEDIGT

- Transparentes SOA-Proxying (keine manuellen Proxy-Klassen)
- IBlog-Aggregationsservice (GetPostFull)
- Statische Datei-Auslieferung (SPA aus www/)
- CORS-Handling
- Client-Factories mit ResultAsJsonObjectWithoutResult

## Phase 4: Web-Frontend -- ERLEDIGT

- SPA mit Vanilla JavaScript (keine Abhaengigkeiten)
- SCRAM-MCF Login im Browser (PBKDF2 via Web Crypto API)
- Beitragsliste, Einzelansicht, Kommentare
- Autoren-Dashboard, Beitrags-Editor
- Kommentar-Moderation

## Phase 5: Betrieb -- ERLEDIGT

- TSynLog-Konfiguration mit Rotation
- Management-Endpunkte: GET /api/health, POST /api/shutdown
- Betriebsskripte: start-all.cmd, stop-all.cmd, status.cmd, seed-data.cmd

## Hinweise fuer zukuenftige Arbeiten

### ORM-Namenskonvention
ORM-Klassennamen duerfen nach Entfernung des `TOrm`-Prefix nicht dem
Interface-Namen (nach Entfernung des `I`-Prefix) entsprechen.
Beispiel: `IPost` + `TOrmPost` -> Konflikt! Loesung: `TOrmBlogPost`.

### SOA-Parameterformat
`RawJson`-Parameter muessen als JSON-Objekte (nicht Strings) im Array uebergeben werden:
- Richtig: `[{"Name":"Delphi"}]`
- Falsch: `["{\"Name\":\"Delphi\"}"]`
