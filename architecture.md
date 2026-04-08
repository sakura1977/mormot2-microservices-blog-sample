# Blog Microservices Architecture

A microservice-based blog platform built with Delphi 13 and mORMot2.

---

## System Overview

```mermaid
graph TB
    Browser[Browser / Client]
    Controller[ms.controller :8090]

    subgraph Gateway
        GW[ms.gateway :8080]
        SPA[SPA Frontend]
    end

    subgraph Backend Services
        AUTH[ms.auth :8081]
        USERS[ms.users :8082]
        POSTS[ms.posts :8083]
        TAGS[ms.tags :8084]
        COMMENTS[ms.comments :8085]
        MEDIA[ms.media :8086]
    end

    subgraph Databases
        DB_AUTH[(auth.db)]
        DB_USERS[(users.db)]
        DB_POSTS[(posts.db)]
        DB_TAGS[(tags.db)]
        DB_COMMENTS[(comments.db)]
        DB_MEDIA[(media.db)]
    end

    Browser -->|HTTP :8080| GW
    GW --> SPA
    GW -->|REST/JSON| AUTH
    GW -->|REST/JSON| USERS
    GW -->|REST/JSON| POSTS
    GW -->|REST/JSON| TAGS
    GW -->|REST/JSON| COMMENTS
    GW -->|REST/JSON| MEDIA

    AUTH --- DB_AUTH
    USERS --- DB_USERS
    POSTS --- DB_POSTS
    TAGS --- DB_TAGS
    COMMENTS --- DB_COMMENTS
    MEDIA --- DB_MEDIA

    Controller -.->|start/stop/monitor| AUTH
    Controller -.->|start/stop/monitor| USERS
    Controller -.->|start/stop/monitor| POSTS
    Controller -.->|start/stop/monitor| TAGS
    Controller -.->|start/stop/monitor| COMMENTS
    Controller -.->|start/stop/monitor| MEDIA
    Controller -.->|start/stop/monitor| GW
```

---

## Service Ports

| Service | Port | Purpose |
|---------|------|---------|
| ms.gateway | 8080 | API Gateway + SPA Frontend |
| ms.auth | 8081 | Authentication (SCRAM-MCF + JWT) |
| ms.users | 8082 | Author Profiles |
| ms.posts | 8083 | Blog Posts CRUD |
| ms.tags | 8084 | Tags + Post-Tag Associations |
| ms.comments | 8085 | Comments + Moderation |
| ms.media | 8086 | File Uploads |
| ms.controller | 8090 | Service Orchestrator |

---

## SOA URL Format

All services use mORMot2 interface-based services (SOA). The URL format is:

```
POST /api/{InterfaceName}/{MethodName}
```

Request body: JSON array of positional input parameters.
Response body: JSON object with named output parameters.

Example:

```
POST /api/Post/GetList
Body: [1, 10, 1, 0]
Response: {"Result": "{\"items\":[...],\"total\":5,\"page\":1}"}
```

---

## Request Flow

### Post List (Public)

```mermaid
sequenceDiagram
    participant B as Browser
    participant GW as Gateway :8080
    participant P as Posts :8083

    B->>GW: POST /api/Post/GetList [1, 10, 1, 0]
    GW->>P: POST /api/Post/GetList [1, 10, 1, 0]
    P-->>GW: {"Result": "{\"items\":[...],\"total\":N}"}
    GW-->>B: {"Result": "{\"items\":[...],\"total\":N}"}
```

### Single Post (Aggregated via IBlog)

```mermaid
sequenceDiagram
    participant B as Browser
    participant GW as Gateway :8080
    participant P as Posts :8083
    participant U as Users :8082
    participant T as Tags :8084
    participant C as Comments :8085

    B->>GW: POST /api/Blog/GetPostFull [1]
    Note over GW: TBlogService (local)
    GW->>P: IPost.Get(1)
    P-->>GW: {RowID:1, Title:..., AuthorId:1}
    GW->>U: IUser.Get(1)
    U-->>GW: {DisplayName: "Max Mustermann"}
    GW->>T: ITag.GetByPost(1)
    T-->>GW: [{Name:"Delphi"}, {Name:"mORMot2"}]
    GW->>C: IComment.GetByPost(1)
    C-->>GW: [{AuthorName:"...", Body:"..."}]
    GW-->>B: {Title:..., Author:{...}, Tags:[...], Comments:[...]}
```

### Posts by Tag (Aggregated via IBlog)

```mermaid
sequenceDiagram
    participant B as Browser
    participant GW as Gateway :8080
    participant T as Tags :8084
    participant P as Posts :8083
    participant U as Users :8082

    B->>GW: POST /api/Blog/GetPostsByTag [3]
    Note over GW: TBlogService (local)
    GW->>T: ITag.Get(3)
    T-->>GW: {Name:"mORMot2", ...}
    GW->>T: ITag.GetPostIds(3)
    T-->>GW: [1, 5, 7]
    loop For each PostId
        GW->>P: IPost.Get(id)
        P-->>GW: {Title:..., AuthorId:..., Status:1}
        GW->>U: IUser.Get(authorId)
        U-->>GW: {DisplayName:...}
    end
    Note over GW: Filter: Status = PUBLISHED only
    GW-->>B: {Tag:{Name:"mORMot2"}, Posts:[...]}
```

### Authentication Flow (SCRAM-MCF)

Authentication uses the SCRAM protocol (RFC 5802) adapted for mORMot2
with MCF (Modular Crypt Format) credential storage. The plaintext
password is **never** transmitted over the wire.

```mermaid
sequenceDiagram
    participant B as Browser
    participant GW as Gateway :8080
    participant A as Auth :8081

    Note over B,A: Phase 1: Challenge
    B->>GW: POST /api/Auth/Challenge [email]
    GW->>A: IAuth.Challenge(email)
    A->>A: Lookup MCF info for email<br/>(or generate fake MCF to prevent enumeration)
    A->>A: Generate one-time server nonce
    A-->>GW: {aMcfInfo: "$pbkdf2-sha256$...", aServerNonce: "..."}
    GW-->>B: {aMcfInfo, aServerNonce}

    Note over B: Phase 2: Client-side PBKDF2
    B->>B: Compute PBKDF2-SHA256 from password + salt
    B->>B: Derive ClientKey, StoredKey via HMAC-SHA256
    B->>B: Compute ClientProof = ClientKey XOR ClientSignature

    Note over B,A: Phase 3: Authenticate
    B->>GW: POST /api/Auth/Authenticate [email, nonce, proof]
    GW->>A: IAuth.Authenticate(email, nonce, proof)
    A->>A: Verify SCRAM client proof against persisted key
    A->>A: Create JWT (HMAC-SHA256, 24h expiry)
    A->>A: Compute server proof for mutual auth
    A-->>GW: {Result:true, aToken:"eyJ...", aUserId:1, aServerProof:"..."}
    GW-->>B: {Result, aToken, aUserId, aServerProof}

    Note over B: Phase 4: Mutual Authentication
    B->>B: Verify server proof (confirms server knows the key)
    B->>B: Store JWT + userId in localStorage
```

### Post Creation with Tags

```mermaid
sequenceDiagram
    participant B as Browser
    participant GW as Gateway :8080
    participant P as Posts :8083
    participant T as Tags :8084

    B->>GW: POST /api/Post/Add [{Title, Body, AuthorId, Status}]
    Note over GW: Bearer token in header
    GW->>P: IPost.Add(data)
    P-->>GW: {Result: 5}
    GW-->>B: {Result: 5}

    B->>GW: POST /api/Tag/SetPostTags [5, [1, 3]]
    GW->>T: ITag.SetPostTags(5, [1,3])
    T->>T: Delete existing PostTag for PostId=5
    T->>T: Create new PostTag records
    T-->>GW: {Result: true}
    GW-->>B: {Result: true}
```

### Comment Moderation

```mermaid
sequenceDiagram
    participant V as Visitor
    participant A as Author
    participant GW as Gateway :8080
    participant C as Comments :8085

    Note over V,C: Public Comment Submission
    V->>GW: POST /api/Comment/Add [postId, {AuthorName, Body}]
    GW->>C: IComment.Add(postId, data)
    C->>C: Status = PENDING (0)
    C-->>GW: {Result: 1}
    GW-->>V: Comment submitted for review

    Note over A,C: Moderation by Author
    A->>GW: POST /api/Comment/GetPending []
    GW->>C: IComment.GetPending
    C-->>GW: [{RowID:1, AuthorName:"...", Body:"..."}]
    GW-->>A: Pending comments list

    A->>GW: POST /api/Comment/Approve [1, authorId]
    GW->>C: IComment.Approve(1, authorId)
    C->>C: Status = APPROVED (1), set ModeratedBy/ModeratedAt
    C-->>GW: {Result: true}
    GW-->>A: Comment approved
```

---

## Controller Orchestrator

```mermaid
graph LR
    subgraph ms.controller :8090
        Start[StartAll]
        Monitor[Health Monitor<br/>every 10s]
        Stop[StopAll]
    end

    Start -->|1| MEDIA[ms.media]
    Start -->|2| USERS[ms.users]
    Start -->|3| AUTH[ms.auth]
    Start -->|4| POSTS[ms.posts]
    Start -->|5| TAGS[ms.tags]
    Start -->|6| COMMENTS[ms.comments]
    Start -->|7| GW[ms.gateway]

    Monitor -->|GET /api/health| MEDIA
    Monitor -->|GET /api/health| USERS
    Monitor -->|GET /api/health| AUTH
    Monitor -->|GET /api/health| POSTS
    Monitor -->|GET /api/health| TAGS
    Monitor -->|GET /api/health| COMMENTS
    Monitor -->|GET /api/health| GW

    Monitor -->|crash detected| Restart[Auto-Restart<br/>max 3x]
```

### Controller API

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/status` | Status of all services |
| POST | `/api/start-all` | Start all services |
| POST | `/api/stop-all` | Stop all services |
| POST | `/api/restart/{name}` | Restart single service |
| POST | `/api/shutdown` | Shutdown everything |

### Startup Order

Services start in dependency order:

1. **ms.media** (8086) -- no dependencies
2. **ms.users** (8082) -- no dependencies
3. **ms.auth** (8081) -- references users
4. **ms.posts** (8083) -- no dependencies
5. **ms.tags** (8084) -- no dependencies
6. **ms.comments** (8085) -- no dependencies
7. **ms.gateway** (8080) -- depends on all others

Shutdown happens in **reverse order** (gateway first).

---

## Gateway Architecture

The gateway combines three responsibilities:

1. **Transparent SOA proxying**: Resolves backend service interfaces
   via `TRestHttpClient` + `Services.Resolve`, which returns a
   `TInterfacedObjectFake`. These are re-registered on the gateway's
   own `TRestServerDB` -- no manual proxy classes needed.

2. **Response aggregation** (`TBlogService`): The `IBlog` interface
   provides `GetPostFull` and `GetPostsByTag`, which query multiple
   backend services and merge their responses using `TDocVariantData`.

3. **Static file serving**: Non-API requests serve the SPA frontend
   from the `www/` directory. Unmatched routes fall back to
   `index.html` for client-side routing.

### Proxied Interfaces

| Interface | Backend | Methods |
|-----------|---------|---------|
| IAuth | ms.auth :8081 | Challenge, Authenticate, Register, Validate, ChangePassword |
| IUser | ms.users :8082 | Get, GetAll, Add, Update, Remove |
| IPost | ms.posts :8083 | Get, GetBySlug, GetList, Add, Update, Remove |
| ITag | ms.tags :8084 | Get, GetAll, GetByPost, GetPostIds, SetPostTags, Add, Update, Remove |
| IComment | ms.comments :8085 | GetByPost, GetPending, Add, Approve, Reject, Remove |
| IMedia | ms.media :8086 | Upload, GetInfo, GetFile, Remove |

### Local Aggregation Interface

| Interface | Methods | Description |
|-----------|---------|-------------|
| IBlog | GetPostFull, GetPostsByTag | Enriches posts with author, tags, comments |

---

## Data Model

```mermaid
erDiagram
    AuthUser {
        int ID PK
        string Email UK
        string McfInfo
        string PersistedKey
        int UserId FK
        boolean IsActive
        datetime CreatedAt
        datetime LastLogin
    }

    Author {
        int ID PK
        string DisplayName
        string Slug UK
        string Bio
        string WebsiteUrl
        int AvatarMediaId FK
        datetime CreatedAt
        datetime UpdatedAt
    }

    Post {
        int ID PK
        string Title
        string Slug UK
        string Body
        string Excerpt
        int AuthorId FK
        int FeaturedImageId FK
        string MetaTitle
        string MetaDescription
        string MetaKeywords
        int Status
        datetime PublishedAt
        datetime CreatedAt
        datetime UpdatedAt
    }

    Tag {
        int ID PK
        string Name UK
        string Slug UK
        string Description
        datetime CreatedAt
    }

    PostTag {
        int ID PK
        int PostId FK
        int TagId FK
    }

    Comment {
        int ID PK
        int PostId FK
        string AuthorName
        string AuthorEmail
        string Body
        int Status
        int ModeratedBy FK
        datetime ModeratedAt
        datetime CreatedAt
    }

    Media {
        int ID PK
        string FileName
        string MimeType
        int FileSize
        string StoragePath
        string AltText
        int UploadedBy FK
        datetime CreatedAt
    }

    AuthUser ||--|| Author : "UserId"
    Author ||--o{ Post : "AuthorId"
    Post ||--o{ PostTag : "PostId"
    Tag ||--o{ PostTag : "TagId"
    Post ||--o{ Comment : "PostId"
    Media ||--o| Post : "FeaturedImageId"
    Media ||--o| Author : "AvatarMediaId"
```

### Status Codes

| Entity | Value | Meaning |
|--------|-------|---------|
| Post | 0 | Draft |
| Post | 1 | Published |
| Post | 2 | Archived |
| Comment | 0 | Pending |
| Comment | 1 | Approved |
| Comment | 2 | Rejected |

---

## Technology Stack

| Layer | Technology |
|-------|------------|
| Language | Delphi 13 (Object Pascal) |
| Framework | [mORMot2](https://github.com/synopse/mORMot2) |
| HTTP Server | THttpAsyncServer (IOCP) |
| ORM | mORMot2 TRestServerDB |
| Database | SQLite (one per service) |
| Auth | SCRAM-MCF (RFC 5802) + JWT (HMAC-SHA256, 24h) |
| Frontend | Vanilla JavaScript SPA |
| IPC | REST/JSON over HTTP (SOA interface-based) |
