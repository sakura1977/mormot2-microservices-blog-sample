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
  function GetPostFull(aId: TID): RawJson;
    // Aggregates: Post + Author + Tags + Comments
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
  function Get(aId: TID): RawJson;
  function GetAll: RawJson;
  function Add(const aData: RawJson): TID;
  function Update(aId: TID; const aData: RawJson): boolean;
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
  function Get(aId: TID): RawJson;
  function GetBySlug(const aSlug: RawUtf8): RawJson;
  function GetList(aPage, aLimit, aStatus: integer;
    aAuthorId: TID): RawJson;
  function Add(const aData: RawJson): TID;
  function Update(aId: TID; const aData: RawJson): boolean;
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
  function Get(aId: TID): RawJson;
  function GetAll: RawJson;
  function GetByPost(aPostId: TID): RawJson;
  function SetPostTags(aPostId: TID;
    const aTagIds: RawJson): boolean;
  function Add(const aData: RawJson): TID;
  function Update(aId: TID; const aData: RawJson): boolean;
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
  function GetByPost(aPostId: TID): RawJson;
  function GetPending: RawJson;
  function Add(aPostId: TID; const aData: RawJson): TID;
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
  function GetInfo(aId: TID): RawJson;
  function GetFile(aId: TID;
    out aContentType: RawUtf8): RawByteString;
  function Remove(aId: TID): boolean;
end;
```

---

## Service Dependencies

```
ms.gateway  -->  ms.auth       (token validation)
ms.gateway  -->  ms.users      (author profiles)
ms.gateway  -->  ms.posts      (blog posts)
ms.gateway  -->  ms.tags       (tags)
ms.gateway  -->  ms.comments   (comments)
ms.gateway  -->  ms.media      (media files)

ms.auth     -->  (none -- stores only UserId as reference)
ms.posts    -->  (none -- stores only IDs)
ms.tags     -->  (none -- stores only IDs)
ms.comments -->  (none -- stores only IDs)
ms.media    -->  (none -- stores only IDs)
ms.users    -->  (none -- stores only IDs)
```
