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
| ms.auth | 8081 | Authentication (JWT) |
| ms.users | 8082 | Author Profiles |
| ms.posts | 8083 | Blog Posts CRUD |
| ms.tags | 8084 | Tags + Post-Tag Associations |
| ms.comments | 8085 | Comments + Moderation |
| ms.media | 8086 | File Uploads |
| ms.controller | 8090 | Service Orchestrator |

---

## Request Flow

### Public Page Request

```mermaid
sequenceDiagram
    participant B as Browser
    participant GW as Gateway :8080
    participant P as Posts :8083

    B->>GW: GET /api/posts?page=1&status=1
    GW->>P: GET /api/posts?page=1&status=1
    P-->>GW: {"items":[...], "total":N, "page":1}
    GW-->>B: {"items":[...], "total":N, "page":1}
```

### Single Post (Aggregated)

```mermaid
sequenceDiagram
    participant B as Browser
    participant GW as Gateway :8080
    participant P as Posts :8083
    participant U as Users :8082
    participant T as Tags :8084
    participant C as Comments :8085

    B->>GW: GET /api/posts/1
    GW->>P: GET /api/posts/1
    P-->>GW: {RowID:1, Title:..., AuthorId:1}

    par Parallel Enrichment
        GW->>U: GET /api/users/1
        U-->>GW: {DisplayName: "Max Mustermann"}
    and
        GW->>T: GET /api/posts/1/tags
        T-->>GW: [{Name:"Delphi"}, {Name:"mORMot2"}]
    and
        GW->>C: GET /api/posts/1/comments
        C-->>GW: [{AuthorName:"...", Body:"..."}]
    end

    GW-->>B: {Title:..., Author:{...}, Tags:[...], Comments:[...]}
```

### Authentication Flow

```mermaid
sequenceDiagram
    participant B as Browser
    participant GW as Gateway :8080
    participant A as Auth :8081

    Note over B,A: Login
    B->>GW: POST /api/auth/login {Email, Password}
    GW->>A: POST /api/auth/login {Email, Password}
    A->>A: Verify SHA-256(Salt + Password)
    A->>A: Create JWT (HMAC-SHA256, 24h)
    A-->>GW: {token: "eyJ...", userId: 1}
    GW-->>B: {token: "eyJ...", userId: 1}
    B->>B: Store token in localStorage

    Note over B,A: Authenticated Request
    B->>GW: POST /api/posts {Title:...} + Bearer token
    GW->>A: POST /api/auth/validate {Token: "eyJ..."}
    A-->>GW: {valid: true, userId: 1}
    GW->>GW: Extract userId, proceed
```

### Post Creation with Tags

```mermaid
sequenceDiagram
    participant B as Browser
    participant GW as Gateway :8080
    participant A as Auth :8081
    participant P as Posts :8083
    participant T as Tags :8084

    B->>GW: POST /api/posts + Bearer token
    GW->>A: Validate token
    A-->>GW: {valid: true, userId: 1}
    GW->>P: POST /api/posts {Title, Body, AuthorId:1, Status:1}
    P-->>GW: {id: 5}
    GW-->>B: {id: 5}

    B->>GW: PUT /api/posts/5/tags + Bearer token
    GW->>A: Validate token
    A-->>GW: {valid: true}
    GW->>T: PUT /api/posts/5/tags {TagIds:[1,3]}
    T->>T: Delete existing associations
    T->>T: Create new PostTag records
    T-->>GW: {success: true}
    GW-->>B: {success: true}
```

### Comment Moderation

```mermaid
sequenceDiagram
    participant V as Visitor
    participant A as Author
    participant GW as Gateway :8080
    participant C as Comments :8085

    Note over V,C: Public Comment Submission
    V->>GW: POST /api/posts/1/comments {AuthorName, Body}
    GW->>C: POST /api/posts/1/comments
    C->>C: Status = PENDING (0)
    C-->>GW: {id: 1, status: 0}
    GW-->>V: Comment submitted for review

    Note over A,C: Moderation by Author
    A->>GW: GET /api/comments/pending + Bearer
    GW->>C: GET /api/comments/pending
    C-->>GW: [{id:1, AuthorName:"...", Body:"..."}]
    GW-->>A: Pending comments list

    A->>GW: PUT /api/comments/1/approve + Bearer
    GW->>C: PUT /api/comments/1/approve {ModeratedBy:1}
    C->>C: Status = APPROVED (1)
    C-->>GW: {success: true}
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

## Gateway Routing Map

```mermaid
graph TD
    REQ[Incoming Request]
    REQ --> PATH{URL Path}

    PATH -->|/api/auth/*| AUTH_ROUTE[Auth Service :8081]
    PATH -->|/api/users*| USERS_ROUTE[Users Service :8082]
    PATH -->|/api/posts*| POSTS_CHECK{Sub-route?}
    PATH -->|/api/tags*| TAGS_ROUTE[Tags Service :8084]
    PATH -->|/api/comments*| COMMENTS_ROUTE[Comments Service :8085]
    PATH -->|/api/media*| MEDIA_ROUTE[Media Service :8086]
    PATH -->|/*| STATIC[Static Files / SPA]

    POSTS_CHECK -->|/comments| COMMENTS_ROUTE
    POSTS_CHECK -->|/tags| TAGS_ROUTE
    POSTS_CHECK -->|single post| AGGREGATE[Aggregated Response<br/>Post + Author + Tags + Comments]
    POSTS_CHECK -->|list / by-slug / by-author| POSTS_ROUTE[Posts Service :8083]

    style AGGREGATE fill:#e0e7ff,stroke:#2563eb
    style AUTH_ROUTE fill:#fef3c7,stroke:#d97706
```

### Authentication Requirements

| Endpoint | GET | POST | PUT | DELETE |
|----------|-----|------|-----|--------|
| `/api/auth/*` | -- | Public | Auth | -- |
| `/api/users*` | Public | Auth | Auth | Auth |
| `/api/posts` | Public | Auth | Auth | Auth |
| `/api/posts/{id}/comments` | Public | **Public** | -- | -- |
| `/api/posts/{id}/tags` | Public | Auth | Auth | -- |
| `/api/tags*` | Public | Auth | Auth | Auth |
| `/api/comments/pending` | Auth | -- | -- | -- |
| `/api/comments/{id}/*` | Public | Auth | Auth | Auth |
| `/api/media*` | Public | Auth | -- | Auth |

---

## Data Model

```mermaid
erDiagram
    AuthUser {
        int ID PK
        string Email UK
        string PasswordHash
        string Salt
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
| Auth | JWT (HMAC-SHA256, 24h expiry) |
| Frontend | Vanilla JavaScript SPA |
| IPC | REST/JSON over HTTP |
