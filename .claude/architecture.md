# Blog-Microservices -- Architektur

## Zielsetzung

Ein einfaches Blog-System, aufgebaut als Microservice-Architektur mit **Delphi 13** und **mORMot2**. Jede fachliche Funktion laeuft in einer eigenen Konsolen-EXE mit eigener SQLite-Datenbank.

## Uebersicht der Services

```
                    +--------+---------+
                    |   ms.gateway     |
                    |  (HTTP Gateway + |
                    |   Web-Frontend)  |
                    +--------+---------+
                             |
         +-------------------+-------------------+
         |         |         |         |         |
   +-----+--+ +---+----+ +--+-----+ +-+------+ +--+-----+ +--+-----+
   |ms.auth | |ms.users| |ms.posts| |ms.tags | |ms.comm.| |ms.media|
   |  IAuth | | IUser  | | IPost  | | ITag   | |IComment| | IMedia |
   +:8081   | +:8082   | +:8083   | +:8084   | +:8085   | +:8086   |
   +--------+ +--------+ +--------+ +--------+ +--------+ +--------+
       |          |          |          |          |          |
    auth.db    users.db   posts.db   tags.db  comments.db media.db
```

## Services im Ueberblick

| # | Service           | Port  | Interface | Aufgabe                               |
|---|-------------------|-------|-----------|---------------------------------------|
| 1 | **ms.gateway**    | 8080  | IBlog     | API-Gateway, Proxies, Web-Frontend    |
| 2 | **ms.auth**       | 8081  | IAuth     | SCRAM-MCF Login, JWT-Tokens           |
| 3 | **ms.users**      | 8082  | IUser     | Autorenprofile, Biografien            |
| 4 | **ms.posts**      | 8083  | IPost     | Blog-Beitraege, SEO-Metadaten         |
| 5 | **ms.tags**       | 8084  | ITag      | Tags, Zuordnung zu Beitraegen (m:n)   |
| 6 | **ms.comments**   | 8085  | IComment  | Kommentare, Moderations-Workflow      |
| 7 | **ms.media**      | 8086  | IMedia    | Bild-Upload, Speicherung              |

## API-Stil: mORMot2 SOA

Alle Services verwenden Interface-basierte Services (SOA), nicht klassische REST-Endpunkte.

- **URL-Format**: `POST /api/{InterfaceName}/{MethodName}`
- **Request-Body**: JSON-Array mit positionalen Parametern `[param1, param2, ...]`
- **Response**: JSON-Objekt mit benannten Ausgabeparametern (ResultAsJsonObjectWithoutResult)
- **Interfaces**: Definiert in `ms.shared.api.pas`, von allen Services geteilt

### Beispiel: Tag erstellen

```
POST /api/Tag/Add
Body: [{"Name":"Delphi","Description":"Everything about Delphi"}]
Response: {"Result":1}
```

## Kommunikation

- **Browser -> Gateway**: HTTP/JSON (SOA-Format via api.js)
- **Gateway -> Backend**: mORMot2 SOA via `TRestHttpClient` + `TServiceFactoryClient`
- **Authentifizierung**: SCRAM-MCF (Challenge/Authenticate), dann JWT-Token im Authorization-Header
- **Datenbank**: Jeder Service hat eine eigene SQLite-Datei (via mORMot2 ORM)

## Management-Endpunkte

Jeder Service stellt automatisch bereit (via TMicroService-Basisklasse):

```
GET  /api/health       Health-Check (JSON mit Service-Name, Port, Version, Uptime)
POST /api/shutdown     Sauberes Herunterfahren
```

## Prinzipien

1. **Single Responsibility** -- Jeder Service hat genau eine fachliche Zustaendigkeit
2. **Eigene Datenhaltung** -- Kein Service greift auf die Datenbank eines anderen zu
3. **Lose Kopplung** -- Services kommunizieren ausschliesslich ueber SOA-Interfaces
4. **Gateway-Pattern** -- Alle Browser-Anfragen laufen ueber den Gateway
5. **Eigene Auth** -- SCRAM-MCF statt integrierter mORMot2-Authentifizierung

## Service-Abhaengigkeiten

```
ms.gateway  -->  ms.auth       (Token-Validierung)
ms.gateway  -->  ms.users      (Autorenprofile)
ms.gateway  -->  ms.posts      (Beitraege)
ms.gateway  -->  ms.tags       (Tags)
ms.gateway  -->  ms.comments   (Kommentare)
ms.gateway  -->  ms.media      (Bilder)

Alle anderen Services: keine Abhaengigkeiten untereinander
(Referenzen nur als IDs, Aufloesung im Gateway via IBlog.GetPostFull)
```
