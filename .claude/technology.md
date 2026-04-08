# Blog Microservices -- Technology and mORMot2 Usage

## mORMot2 Modules by Purpose

### All Services (shared)

| Purpose              | mORMot2 Unit                        | Usage                              |
|----------------------|-------------------------------------|------------------------------------|
| ORM / data model     | `mormot.orm.core`                   | Define `TOrm` classes              |
| SQLite database      | `mormot.orm.sqlite3`                | `TRestServerDB` as DB backend      |
| REST HTTP server     | `mormot.rest.http.server`           | `TRestHttpServer` per service      |
| SOA interfaces       | `mormot.soa.core`, `mormot.soa.server` | Interface-based services        |
| JSON processing      | `mormot.core.json`                  | `TDocVariantData` for JSON parsing |
| Logging              | `mormot.core.log`                   | `TSynLog` for all services         |
| Base types           | `mormot.core.base`, `mormot.core.text`, `mormot.core.unicode` | RawUtf8, helper functions |

### ms.auth (additional)

| Purpose              | mORMot2 Unit                        | Usage                              |
|----------------------|-------------------------------------|------------------------------------|
| SCRAM/PBKDF2         | `mormot.crypt.core`                 | Password hashing (MCF format)      |
| JWT tokens           | `mormot.crypt.jwt`                  | `TJwtHS256` for token creation     |

### ms.gateway (additional)

| Purpose              | mORMot2 Unit                        | Usage                              |
|----------------------|-------------------------------------|------------------------------------|
| HTTP client          | `mormot.rest.http.client`           | `TRestHttpClient` to backend services |
| SOA client           | `mormot.soa.client`                 | `TServiceFactoryClient` for proxies |
| Async HTTP           | `mormot.net.async`                  | `THttpAsyncServer` for requests    |

## Project Structure

```
mormot2-microservices/
|
+-- shared/                   Shared code
|   +-- ms.shared.pas           Constants, config loading, TextToSlug, GuessMimeType
|   +-- ms.shared.api.pas       SOA interface definitions (IAuth, IUser, ...)
|   +-- ms.shared.jwt.pas       JWT token creation and validation
|   +-- ms.shared.service.pas   TMicroService base class (Run, Health, Shutdown),
|                                 RegisterService, OrmGetById, OrmGetAll
|
+-- ms.gateway/
|   +-- ms.gateway.dpr          Entry point
|   +-- ms.gateway.server.pas   Transparent SOA proxying, IBlog aggregation, static file serving
|   +-- www/                    Frontend SPA
|       +-- index.html
|       +-- css/style.css
|       +-- js/api.js             SOA client + SCRAM-MCF crypto
|       +-- js/app.js             UI logic and routing
|
+-- ms.auth/
|   +-- ms.auth.dpr
|   +-- ms.auth.model.pas       ORM model (TOrmAuthUser)
|   +-- ms.auth.server.pas      TAuthService (IAuth), TAuthServer
|
+-- ms.users/
|   +-- ms.users.dpr
|   +-- ms.users.model.pas      ORM model (TOrmAuthor)
|   +-- ms.users.server.pas     TUserService (IUser), TUsersServer
|
+-- ms.posts/
|   +-- ms.posts.dpr
|   +-- ms.posts.model.pas      ORM model (TOrmBlogPost)
|   +-- ms.posts.server.pas     TPostService (IPost), TPostsServer
|
+-- ms.tags/
|   +-- ms.tags.dpr
|   +-- ms.tags.model.pas       ORM model (TOrmBlogTag, TOrmPostTag)
|   +-- ms.tags.server.pas      TTagService (ITag), TTagsServer
|
+-- ms.comments/
|   +-- ms.comments.dpr
|   +-- ms.comments.model.pas   ORM model (TOrmBlogComment)
|   +-- ms.comments.server.pas  TCommentService (IComment), TCommentsServer
|
+-- ms.media/
|   +-- ms.media.dpr
|   +-- ms.media.model.pas      ORM model (TOrmMediaFile)
|   +-- ms.media.server.pas     TMediaService (IMedia), TMediaServer
|
+-- ms.controller/              Service orchestrator (optional)
|
+-- test/                       Integration tests
|   +-- ms.tests.dpr              Console test runner
|   +-- ms.testCases.pas          130+ assertions, all services in-process
|
+-- BlogMicroservices.groupproj  Delphi project group
+-- start-all.cmd / stop-all.cmd Operations scripts
+-- seed-data.cmd                Demo data
+-- status.cmd                   Health checks
```

## Service Architecture Pattern

Every microservice follows the same structure:

### 1. ORM Model (model.pas)
```pascal
TOrmBlogPost = class(TOrm)
  property Title: RawUtf8 index 300
    read FTitle write FTitle;
  property Slug: RawUtf8 index 300
    read FSlug write FSlug stored AS_UNIQUE;
  // ...
end;
```

### 2. Service Implementation (server.pas)
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

### 3. Server Class (server.pas)
```pascal
TPostsServer = class(TMicroService)
protected
  function CreateModel: TOrmModel; override;
  procedure SetupServices; override;
end;

procedure TPostsServer.SetupServices;
begin
  FPostImpl := TPostService.Create(FRestServer.Orm);
  RegisterService(FPostImpl, TypeInfo(IPost));
end;
```

### 4. Main Program (dpr)
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

## Configuration

Each service reads its configuration from `{service-name}.config.json`:

```json
{
  "Port": "8083",
  "LogLevel": "debug",
  "JwtSecret": "..."
}
```

Defaults are applied automatically if the file is missing.

## ORM Naming Convention

ORM class names must NOT match their SOA interface name (after stripping
the TOrm/I prefixes), as mORMot2 would report a routing conflict.

| Service    | Interface | ORM Class       | Table Name   |
|------------|-----------|-----------------|--------------|
| ms.auth    | IAuth     | TOrmAuthUser    | AuthUser     |
| ms.users   | IUser     | TOrmAuthor      | Author       |
| ms.posts   | IPost     | TOrmBlogPost    | BlogPost     |
| ms.tags    | ITag      | TOrmBlogTag     | BlogTag      |
| ms.tags    | --        | TOrmPostTag     | PostTag      |
| ms.comments| IComment  | TOrmBlogComment | BlogComment  |
| ms.media   | IMedia    | TOrmMediaFile   | MediaFile    |
