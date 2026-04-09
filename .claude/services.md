# Blog Microservices -- Service Definitions and SOA Interfaces

All services use mORMot2 interface-based services (SOA).
URL format: `POST /api/{InterfaceName}/{MethodName}` with JSON array body.
Response format: JSON object with named parameters (`ResultAsJsonObjectWithoutResult`).

---

## Cross-Service: Management Endpoints

Every microservice automatically provides two method-based endpoints (via `TMicroService` base class in `ms.shared.service.pas`):

```
GET    /api/health      Health check
         Response: { "service": "ms.auth", "status": "ok",
                     "port": "8081", "version": "0.2.0",
                     "uptime": "..." }

POST   /api/shutdown    Graceful shutdown
         Response: HTTP 200
```

---

## Cross-Service: Correlation IDs

Every HTTP request carries an `X-Correlation-Id` header that
propagates through every service involved in handling it. This is
implemented entirely in shared infrastructure, so no service
implementation has to be modified:

- `ms.shared.correlation.pas` -- threadvar, helper functions,
  `LogWithCorrelation`
- `TMicroService.HandleRequestWithCorrelation` -- wraps the HTTP
  handler for **all backend services** (auth, users, posts, tags,
  comments, media, analytics, config, logs). Every incoming request
  is automatically logged as `{Service} REQ {Method} {URL}` and
  `{Service} RSP {Method} {URL} -> {Status}`
- `ms.gateway.server.pas` -- extracts the header (or generates a
  UUID) in `HandleRequest`; installs `OnBeforeCall` on every
  `TRestHttpClient` to forward the ID to outgoing backend calls
- `ms.gateway/www/js/api.js` -- browser generates the UUID and
  reads it back from the response header

See [correlation-ids.md](correlation-ids.md) for the full design.

---

## SOA Interface Definitions (ms.shared.api.pas)

All interfaces are defined in `ms.shared.api.pas` and used by both
backend services (implementation) and the gateway (client proxies).

---

## 1. ms.gateway (Port 8080)

### Responsibility
API gateway and web frontend. Proxies SOA calls to backend services
and aggregates data via the IBlog service.

### SOA Interface: IBlog (gateway only)

```pascal
IBlog = interface(IInvokable)
  function GetPostFull(aId: TID): TPostFullDto;
    // Aggregates: Post + Author + Tags + Comments
  function GetPostsByTag(aTagId: TID): TPostsByTagDto;
    // Returns Tag + Posts with author enrichment
end;
```

### Transparent SOA Proxying (no manual proxy classes)
- Backend interfaces are resolved via `TRestHttpClient.Services.Resolve`
- The resulting `TInterfacedObjectFake` instances are registered directly
  as server services on the gateway (`RegisterService`)
- Client factories use `ResultAsJsonObjectWithoutResult := True`

### Static Files
- SPA frontend from `www/` (index.html, css/, js/)
- Non-API URLs served as static files with SPA fallback

### No own database

---

## 2. ms.auth (Port 8081)

### Responsibility
SCRAM-MCF authentication with PBKDF2-SHA256 and JWT tokens.

### Data Model

```pascal
TOrmAuthUser = class(TOrm)
  property Email: RawUtf8        // unique login identifier
  property McfInfo: RawUtf8      // MCF format password hash (PBKDF2-SHA256)
  property PersistedKey: RawUtf8 // SCRAM persisted key
  property UserId: TID           // foreign key to ms.users (author ID)
  property IsActive: boolean     // account active?
  property CreatedAt: TDateTime
  property LastLogin: TDateTime
end;
```

### SOA Interface: IAuth

```pascal
IAuth = interface(IInvokable)
  procedure Challenge(const aEmail: RawUtf8;
    out aMcfInfo, aServerNonce: RawUtf8);
  function Authenticate(const aEmail, aServerNonce, aClientProof: RawUtf8;
    out aToken: RawUtf8; out aUserId: TID;
    out aServerProof: RawUtf8): boolean;
  function Register(const aEmail, aPassword: RawUtf8;
    aUserId: TID): TID;
  function Validate(const aToken: RawUtf8;
    out aUserId: TID): boolean;
  function ChangePassword(aUserId: TID;
    const aOldPassword, aNewPassword: RawUtf8): boolean;
end;
```

### SCRAM-MCF Flow
1. Client calls `Challenge` -> receives MCF info (salt, rounds) + ServerNonce
2. Client computes PBKDF2 locally, derives ClientProof
3. Client calls `Authenticate` -> server verifies, returns JWT + ServerProof
4. Client verifies ServerProof (mutual authentication)

---

## 3. ms.users (Port 8082)

### Responsibility
Author profile management.

### Data Model

```pascal
TOrmAuthor = class(TOrm)
  property DisplayName: RawUtf8
  property Bio: RawUtf8
  property WebsiteUrl: RawUtf8
  property AvatarMediaId: TID
  property CreatedAt: TDateTime
  property UpdatedAt: TDateTime
end;
```

### SOA Interface: IUser

```pascal
IUser = interface(IInvokable)
  function Get(aId: TID): TAuthorDto;
  function GetAll: TAuthorDtoArray;
  function Add(const aData: TAuthorCreateDto): TID;
  function Update(aId: TID; const aData: RawJson): boolean;
    // RawJson: PATCH semantics (only present fields updated)
  function Remove(aId: TID): boolean;
end;
```

---

## 4. ms.posts (Port 8083)

### Responsibility
Blog posts with pagination, filtering, and SEO metadata.

### Data Model

```pascal
TOrmBlogPost = class(TOrm)
  property Title: RawUtf8
  property Slug: RawUtf8          // stored AS_UNIQUE
  property Body: RawUtf8
  property Excerpt: RawUtf8
  property AuthorId: TID
  property FeaturedImageId: TID
  property MetaTitle: RawUtf8
  property MetaDescription: RawUtf8
  property MetaKeywords: RawUtf8
  property Status: integer        // 0=draft, 1=published, 2=archived
  property PublishedAt: TDateTime
  property CreatedAt: TDateTime
  property UpdatedAt: TDateTime
end;
```

### SOA Interface: IPost

```pascal
IPost = interface(IInvokable)
  function Get(aId: TID): TPostDto;
  function GetBySlug(const aSlug: RawUtf8): TPostDto;
  function GetList(aPage, aLimit, aStatus: integer;
    aAuthorId: TID): TPostListDto;
  function Add(const aData: TPostCreateDto): TID;
  function Update(aId: TID; const aData: RawJson): boolean;
    // RawJson: PATCH semantics (only present fields updated)
  function Remove(aId: TID): boolean;
end;
```

---

## 5. ms.tags (Port 8084)

### Responsibility
Tag management and many-to-many post-tag associations.

### Data Model

```pascal
TOrmBlogTag = class(TOrm)
  property Name: RawUtf8          // stored AS_UNIQUE
  property Slug: RawUtf8          // stored AS_UNIQUE
  property Description: RawUtf8
  property CreatedAt: TDateTime
end;

TOrmPostTag = class(TOrm)
  property PostId: TID
  property TagId: TID
end;
```

### SOA Interface: ITag

```pascal
ITag = interface(IInvokable)
  function Get(aId: TID): TTagDto;
  function GetAll: TTagDtoArray;
  function GetByPost(aPostId: TID): TTagDtoArray;
  function GetPostIds(aTagId: TID): TIDDynArray;
    // Returns array of post IDs for a tag
  function SetPostTags(aPostId: TID;
    const aTagIds: RawJson): boolean;
  function Add(const aData: TTagCreateDto): TID;
  function Update(aId: TID; const aData: RawJson): boolean;
    // RawJson: PATCH semantics (only present fields updated)
  function Remove(aId: TID): boolean;
end;
```

---

## 6. ms.comments (Port 8085)

### Responsibility
Comment system with moderation workflow.

### Data Model

```pascal
TOrmBlogComment = class(TOrm)
  property PostId: TID
  property AuthorName: RawUtf8
  property AuthorEmail: RawUtf8
  property Body: RawUtf8
  property Status: integer       // 0=pending, 1=approved, 2=rejected
  property ModeratedBy: TID
  property ModeratedAt: TDateTime
  property CreatedAt: TDateTime
end;
```

### SOA Interface: IComment

```pascal
IComment = interface(IInvokable)
  function GetByPost(aPostId: TID): TCommentDtoArray;
  function GetPending: TCommentDtoArray;
  function Add(aPostId: TID; const aData: TCommentCreateDto): TID;
  function Approve(aId, aModeratedBy: TID): boolean;
  function Reject(aId, aModeratedBy: TID): boolean;
  function Remove(aId: TID): boolean;
end;
```

---

## 7. ms.media (Port 8086)

### Responsibility
Media file management (images). Upload via Base64, stored on file system.

### Data Model

```pascal
TOrmMediaFile = class(TOrm)
  property FileName: RawUtf8
  property StoragePath: RawUtf8
  property MimeType: RawUtf8
  property FileSize: Int64
  property AltText: RawUtf8
  property UploadedBy: TID
  property CreatedAt: TDateTime
end;
```

### Storage
- Files stored on local file system: `./media/{id}_{filename}`
- Metadata tracked in SQLite database

### SOA Interface: IMedia

```pascal
IMedia = interface(IInvokable)
  function Upload(const aFileName, aFileData, aAltText: RawUtf8;
    aUploadedBy: TID): TID;
  function GetInfo(aId: TID): TMediaInfoDto;
  function GetFile(aId: TID;
    out aContentType: RawUtf8): RawByteString;
  function Remove(aId: TID): boolean;
end;
```

---

## 8. ms.config (Port 8087)

### Responsibility
Central configuration registry. Loads master config and serves it to all services at startup.

### No Data Model (no ORM tables)

### SOA Interface: IConfig

```pascal
IConfig = interface(IInvokable)
  function GetServiceConfig(const aServiceName: RawUtf8): RawJson;
  function GetAllConfigs: RawJson;
  function GetServiceRegistry: RawJson;
    // Returns only Host + Port per service (no secrets)
end;
```

### Storage
- Master config: `ms.config.master.json` (loaded into memory at startup)
- No database

---

## 9. ms.analytics (Port 8088)

### Responsibility
Cross-service data aggregation. Demonstrates the microservice equivalent of SQL JOINs.

### No Data Model (no ORM tables, no database)

### SOA Interface: IAnalytics

```pascal
IAnalytics = interface(IInvokable)
  function GetOverview: TOverviewDto;
  function GetAuthorStats: TAuthorStatDtoArray;
  function GetTagCloud: TTagCloudItemDtoArray;
  function GetCommentActivity: TCommentActivityDto;
  function GetRecentPostsFull(aLimit: integer): TPostFullDtoArray;
    // Cross-service JOIN: enriches posts with author, tags, comments
end;
```

### Backend Connections
Connects directly to ms.posts, ms.users, ms.tags, ms.comments (same pattern as gateway).

---

## 10. ms.logs (Port 8089)

### Responsibility
Central log aggregation. Receives log entries from every other service via `ILogIngestion`, stores them in SQLite with an FTS5 full-text search index, and exposes the typed `ILogQuery` interface for retrieval. See [central-logging.md](central-logging.md) for the full design.

### Data Model

```pascal
TOrmLogEntry = class(TOrm)
  property Timestamp: TDateTime    // stored, indexed
  property ServiceName: RawUtf8    // e.g. "ms.posts"
  property Level: integer          // TSynLogLevel ordinal
  property CorrelationId: RawUtf8  // parsed from Message text
  property Message: RawUtf8        // full log line
end;

TOrmLogEntryFts = class(TOrmFts5)
  property Message: RawUtf8        // FTS5 virtual table, parallel to TOrmLogEntry
end;
```

### SOA Interface: ILogIngestion (write path, called by every service)

```pascal
ILogIngestion = interface(IInvokable)
  ['{C2D3E4F5-A6B7-8C9D-0E1F-2A3B4C5D6E7F}']
  procedure AppendBatch(const aEntries: TLogEntryIngestDtoArray);
end;
```

Each `TLogEntryIngestDto` carries `ServiceName`, `Timestamp`, `Level`, `Message`. The server parses out the correlation ID from the message text using the `[uuid]` prefix emitted by `LogWithCorrelation`.

### SOA Interface: ILogQuery (read path, proxied through the gateway)

```pascal
ILogQuery = interface(IInvokable)
  ['{D3E4F5A6-B7C8-9D0E-1F2A-3B4C5D6E7F8A}']
  function ByCorrelationId(const aId: RawUtf8): TLogEntryDtoArray;
  function Recent(const aFilter: TLogQueryFilter): TLogEntryDtoArray;
  function Search(const aText: RawUtf8; aLimit: integer): TLogEntryDtoArray;
  function Stats: TLogStatsDto;
end;
```

`TLogQueryFilter` carries optional `ServiceName`, `MinLevel`, `Since`, `UntilTime`, `Limit` fields. `TLogStatsDto` returns `TotalEntries`, `OldestEntry`, `NewestEntry` and a per-service breakdown.

### Ingestion Flow
1. Producer services install a `TLogShipper` (`shared/ms.shared.logclient.pas`) as a `TSynLogFamily.EchoCustom` callback
2. Each log line is enqueued into a thread-safe queue (cap 10 000, drops oldest on overflow)
3. A background thread drains the queue every 250 ms (or sooner if 100 entries pending) and calls `ILogIngestion.AppendBatch`
4. `TLogIngestionService` parses the correlation ID and writes both the regular row and the FTS5 row inside one SQLite transaction

### Storage
- Own SQLite database (`logs.db`)
- FTS5 virtual table `LogEntryFts` mirrors the `Message` column for `MATCH` queries

---

## Service Dependencies

```
ms.config     -->  (none -- starts first, reads from master JSON file)
ms.analytics  -->  ms.config     (service registry)
ms.analytics  -->  ms.posts      (post data)
ms.analytics  -->  ms.users      (author data)
ms.analytics  -->  ms.tags       (tag data)
ms.analytics  -->  ms.comments   (comment data)
ms.gateway    -->  ms.config     (service registry for backend URLs)
ms.gateway    -->  ms.auth       (token validation)
ms.gateway  -->  ms.users      (author profiles)
ms.gateway  -->  ms.posts      (blog posts)
ms.gateway  -->  ms.tags       (tags)
ms.gateway  -->  ms.comments   (comments)
ms.gateway  -->  ms.media      (media files)
ms.gateway  -->  ms.logs       (ILogQuery proxy for browser UI)

all services (except ms.logs)
            -->  ms.logs       (ILogIngestion via TLogShipper / EchoCustom)

ms.auth     -->  (none -- stores only UserId as reference)
ms.posts    -->  (none -- stores only IDs)
ms.tags     -->  (none -- stores only IDs)
ms.comments -->  (none -- stores only IDs)
ms.media    -->  (none -- stores only IDs)
ms.users    -->  (none -- stores only IDs)
ms.logs     -->  (none -- write-only target of log shippers)
```
