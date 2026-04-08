# Blog-Microservices -- Dokumentation

Microservice-basiertes Blog-System mit **Delphi 13** und **mORMot2**.

## Schnellstart

```
1. BlogMicroservices.groupproj in Delphi oeffnen
2. "Build All" ausfuehren
3. start-all.cmd starten
4. seed-data.cmd ausfuehren (Demo-Daten)
5. http://localhost:8080 im Browser oeffnen
6. Login: max@example.com / demo1234
```

## Dokumentation

| Datei | Inhalt |
|-------|--------|
| [architecture.md](architecture.md) | Architektur-Uebersicht, Service-Tabelle, Kommunikationsprinzipien |
| [services.md](services.md) | Detaillierte Service-Definitionen mit SOA-Interfaces und Datenmodellen |
| [technology.md](technology.md) | mORMot2-Module, Projektstruktur, Code-Muster, Konfiguration |
| [workflows.md](workflows.md) | Sequenzdiagramme fuer alle wichtigen Ablaeufe |

## Architektur

- **API-Stil**: mORMot2 SOA (Interface-basierte Services)
- **URL-Format**: `POST /api/{ServiceName}/{MethodName}` mit JSON-Array als Body
- **Authentifizierung**: SCRAM-MCF (PBKDF2-SHA256, Client-seitiges Hashing)

## Services

| Service | Port | SOA-Interface | Beschreibung |
|---------|------|---------------|--------------|
| ms.gateway | 8080 | IBlog + Proxies | API-Gateway + Web-Frontend |
| ms.auth | 8081 | IAuth | SCRAM-MCF Authentifizierung, JWT-Tokens |
| ms.users | 8082 | IUser | Autorenprofile und Biografien |
| ms.posts | 8083 | IPost | Blog-Beitraege mit Paginierung |
| ms.tags | 8084 | ITag | Tag-Verwaltung (m:n mit Beitraegen) |
| ms.comments | 8085 | IComment | Kommentare mit Moderations-Workflow |
| ms.media | 8086 | IMedia | Bild-Upload und -Auslieferung |

## Technologie

- **Sprache**: Object Pascal (Delphi 13)
- **Framework**: mORMot2
- **Datenbank**: SQLite (eine DB pro Service)
- **Kommunikation**: mORMot2 SOA ueber REST/HTTP mit JSON
- **Authentifizierung**: SCRAM-MCF + JWT (HMAC-SHA256)
- **Frontend**: Vanilla JS SPA (keine Abhaengigkeiten)
- **Logging**: TSynLog mit Rotation (5 x 5 MB pro Service)

## Betriebsskripte

| Skript | Funktion |
|--------|----------|
| `start-all.cmd` | Alle 7 Services in korrekter Reihenfolge starten |
| `stop-all.cmd` | Alle Services sauber herunterfahren (via POST /api/shutdown) |
| `status.cmd` | Health-Check aller Services (via GET /api/health) |
| `seed-data.cmd` | Demo-Daten anlegen (1 Autor, 3 Beitraege, 4 Tags) |

## Projektstruktur

```
BlogMicroservices.groupproj    IDE-Projektgruppe
start-all.cmd / stop-all.cmd   Betriebsskripte
seed-data.cmd / status.cmd     Demo-Daten / Health-Checks
shared/                        4 gemeinsame Units
  ms.shared.pas                  Konstanten, Config, Slug-Generierung
  ms.shared.api.pas              SOA-Interface-Definitionen (IAuth, IUser, ...)
  ms.shared.jwt.pas              JWT-Token-Erstellung und -Validierung
  ms.shared.service.pas          Basisklasse TMicroService, RegisterService,
                                   OrmGetById, OrmGetAll
ms.gateway/                    Gateway + www/ Frontend
ms.auth/                       Auth-Service (model + server)
ms.users/                      Users-Service (model + server)
ms.posts/                      Posts-Service (model + server)
ms.tags/                       Tags-Service (model + server)
ms.comments/                   Comments-Service (model + server)
ms.media/                      Media-Service (model + server)
test/                          In-Process Integration Tests
  ms.testCases.pas               130+ Assertions (positiv + negativ)
  ms.tests.dpr                   Konsolen-Testrunner
```
