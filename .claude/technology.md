# Blog-Microservices -- Technologie und mORMot2-Einsatz

## mORMot2-Module pro Aufgabe

### Alle Services (gemeinsam)

| Aufgabe              | mORMot2-Unit                        | Verwendung                         |
|----------------------|-------------------------------------|------------------------------------|
| ORM / Datenmodell    | `mormot.orm.core`                   | `TOrm`-Klassen definieren         |
| SQLite-Datenbank     | `mormot.orm.sqlite3`                | `TRestServerDB` als DB-Backend     |
| REST-HTTP-Server     | `mormot.rest.http.server`           | `TRestHttpServer` pro Service      |
| SOA-Interfaces       | `mormot.soa.core`, `mormot.soa.server` | Interface-basierte Services     |
| JSON-Verarbeitung    | `mormot.core.json`                  | `TDocVariantData` fuer JSON-Parsing |
| Logging              | `mormot.core.log`                   | `TSynLog` fuer alle Services       |
| Basis-Typen          | `mormot.core.base`, `mormot.core.text`, `mormot.core.unicode` | RawUtf8, Hilfsfunktionen |

### ms.auth (zusaetzlich)

| Aufgabe              | mORMot2-Unit                        | Verwendung                         |
|----------------------|-------------------------------------|------------------------------------|
| SCRAM/PBKDF2         | `mormot.crypt.core`                 | Passwort-Hashing (MCF-Format)      |
| JWT-Tokens           | `mormot.crypt.jwt`                  | `TJwtHS256` fuer Token-Erstellung  |

### ms.gateway (zusaetzlich)

| Aufgabe              | mORMot2-Unit                        | Verwendung                         |
|----------------------|-------------------------------------|------------------------------------|
| HTTP-Client          | `mormot.rest.http.client`           | `TRestHttpClient` zu Backend-Services |
| SOA-Client           | `mormot.soa.client`                 | `TServiceFactoryClient` fuer Proxies |
| Async-HTTP           | `mormot.net.async`                  | `THttpAsyncServer` fuer Requests   |

## Projektstruktur

```
mormot2-microservices/
|
+-- shared/                   Gemeinsamer Code
|   +-- ms.shared.pas           Konstanten, Config-Loading, TextToSlug
|   +-- ms.shared.api.pas       SOA-Interface-Definitionen (IAuth, IUser, ...)
|   +-- ms.shared.jwt.pas       JWT-Token erstellen und validieren
|   +-- ms.shared.service.pas   Basisklasse TMicroService (Run, Health, Shutdown)
|
+-- ms.gateway/
|   +-- ms.gateway.dpr          Hauptprogramm
|   +-- ms.gateway.server.pas   Transparent SOA proxying, IBlog-Aggregation, Static-File-Serving
|   +-- www/                    Frontend SPA
|       +-- index.html
|       +-- css/style.css
|       +-- js/api.js             SOA-Client + SCRAM-MCF Krypto
|       +-- js/app.js             UI-Logik und Routing
|
+-- ms.auth/
|   +-- ms.auth.dpr
|   +-- ms.auth.model.pas       ORM-Modell (TOrmAuthUser)
|   +-- ms.auth.server.pas      TAuthService (IAuth), TAuthServer
|
+-- ms.users/
|   +-- ms.users.dpr
|   +-- ms.users.model.pas      ORM-Modell (TOrmAuthor)
|   +-- ms.users.server.pas     TUserService (IUser), TUsersServer
|
+-- ms.posts/
|   +-- ms.posts.dpr
|   +-- ms.posts.model.pas      ORM-Modell (TOrmBlogPost)
|   +-- ms.posts.server.pas     TPostService (IPost), TPostsServer
|
+-- ms.tags/
|   +-- ms.tags.dpr
|   +-- ms.tags.model.pas       ORM-Modell (TOrmBlogTag, TOrmPostTag)
|   +-- ms.tags.server.pas      TTagService (ITag), TTagsServer
|
+-- ms.comments/
|   +-- ms.comments.dpr
|   +-- ms.comments.model.pas   ORM-Modell (TOrmBlogComment)
|   +-- ms.comments.server.pas  TCommentService (IComment), TCommentsServer
|
+-- ms.media/
|   +-- ms.media.dpr
|   +-- ms.media.model.pas      ORM-Modell (TOrmMediaFile)
|   +-- ms.media.server.pas     TMediaService (IMedia), TMediaServer
|
+-- ms.controller/              Service-Orchestrator (optional)
|
+-- test/                       Integration Tests
|   +-- ms.tests.dpr              Konsolen-Testrunner
|   +-- ms.testCases.pas          130+ Assertions, alle Services in-process
|
+-- BlogMicroservices.groupproj  Delphi-Projektgruppe
+-- start-all.cmd / stop-all.cmd Betriebsskripte
+-- seed-data.cmd                Demo-Daten
+-- status.cmd                   Health-Checks
```

## Service-Architekturmuster

Jeder Microservice folgt dem gleichen Aufbau:

### 1. ORM-Modell (model.pas)
```pascal
TOrmBlogPost = class(TOrm)
  property Title: RawUtf8 index 300
    read FTitle write FTitle;
  property Slug: RawUtf8 index 300
    read FSlug write FSlug stored AS_UNIQUE;
  // ...
end;
```

### 2. Service-Implementierung (server.pas)
```pascal
TPostService = class(TInterfacedObject, IPost)
private
  FOrm: IRestOrm;
public
  constructor Create(const aOrm: IRestOrm);
  function Get(aId: TID): RawJson;
  function Add(const aData: RawJson): TID;
  // ...
end;
```

### 3. Server-Klasse (server.pas)
```pascal
TPostsServer = class(TMicroService)
protected
  function CreateModel: TOrmModel; override;
  procedure SetupServices; override;
end;

procedure TPostsServer.SetupServices;
var Factory: TServiceFactoryServerAbstract;
begin
  FPostImpl := TPostService.Create(FRestServer.Orm);
  Factory := FRestServer.ServiceRegister(FPostImpl, [TypeInfo(IPost)]);
  Factory.ByPassAuthentication := True;
  Factory.ResultAsJsonObjectWithoutResult := True;
end;
```

### 4. Hauptprogramm (dpr)
```pascal
begin
  with TPostsServer.Create(SERVICE_POSTS, PORT_POSTS) do
  try
    Run;
  finally
    Free;
  end;
end.
```

## Konfiguration

Jeder Service liest seine Konfiguration aus `{service-name}.config.json`:

```json
{
  "Port": "8083",
  "LogLevel": "debug",
  "JwtSecret": "..."
}
```

Standardwerte werden automatisch gesetzt, wenn die Datei fehlt.

## ORM-Namenskonvention

ORM-Klassen duerfen NICHT den gleichen Namen wie das SOA-Interface tragen
(nach Entfernung der Prefixe TOrm/I), da mORMot2 sonst einen Routing-Konflikt meldet.

| Service    | Interface | ORM-Klasse      | Tabellenname |
|------------|-----------|-----------------|--------------|
| ms.auth    | IAuth     | TOrmAuthUser    | AuthUser     |
| ms.users   | IUser     | TOrmAuthor      | Author       |
| ms.posts   | IPost     | TOrmBlogPost    | BlogPost     |
| ms.tags    | ITag      | TOrmBlogTag     | BlogTag      |
| ms.tags    | --        | TOrmPostTag     | PostTag      |
| ms.comments| IComment  | TOrmBlogComment | BlogComment  |
| ms.media   | IMedia    | TOrmMediaFile   | MediaFile    |
