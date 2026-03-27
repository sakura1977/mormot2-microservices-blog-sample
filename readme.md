# Blog Microservices with Delphi and mORMot2

A fully functional blog platform built as a microservice architecture using **Delphi 13** and the **mORMot2** framework. Each feature -- authentication, posts, tags, comments, media -- runs as an independent console application with its own SQLite database, communicating exclusively via REST/JSON.

This project serves as both a working application and a learning resource for developers interested in building microservices with native Delphi.

---

## The Idea

Most microservice tutorials use Node.js, Go, or Java. But what about Delphi? With its native compilation, minimal runtime dependencies, and the powerful mORMot2 framework, Delphi is an excellent -- and underappreciated -- choice for microservices:

- **Multi-EXE deployment** -- no runtime, no container, no VM needed
- **Tiny footprint** -- each service uses ~5 MB RAM
- **Fast startup** -- services are ready in milliseconds
- **SQLite embedded** -- no external database server required
- **mORMot2 ORM** -- type-safe database access with automatic table creation

The blog platform demonstrates how to decompose a monolithic application into independent services that can be developed, deployed, and scaled separately.

---

## Architecture at a Glance

```
                    Browser
                       |
                  [Gateway :8080]
                  /   |   |   \
           Auth  Users Posts  Tags  Comments  Media
           :8081 :8082 :8083  :8084  :8085    :8086
            |      |     |     |       |        |
          auth.db users posts tags  comments  media
                   .db   .db  .db    .db      .db
```

Eight independent services, each a standalone console application:

| Service | Port | Responsibility |
|---------|------|----------------|
| **ms.gateway** | 8080 | API routing, JWT validation, response aggregation, SPA frontend |
| **ms.auth** | 8081 | Login, registration, JWT token management |
| **ms.users** | 8082 | Author profiles |
| **ms.posts** | 8083 | Blog post CRUD with pagination and filtering |
| **ms.tags** | 8084 | Tag management and post-tag associations (m:n) |
| **ms.comments** | 8085 | Comments with moderation workflow |
| **ms.media** | 8086 | File uploads with Base64 encoding |
| **ms.controller** | 8090 | Service orchestrator with health monitoring |

For detailed diagrams (request flows, data model, routing map), see [ARCHITECTURE.md](ARCHITECTURE.md).

---

## Prerequisites

- **Delphi 13** (or Delphi 12.x with minor adjustments)
- **mORMot2** -- clone from [github.com/synopse/mORMot2](https://github.com/synopse/mORMot2)
- **curl** -- for the seed data and status scripts (included with Windows 10+)

### Setting Up mORMot2

1. Clone the mORMot2 repository
2. Ensure the mORMot2 `src` and `static` directories are accessible
3. Adjust the search paths in the `.dproj` files (or the `gitroot` environment variable) to point to your mORMot2 installation

---

## Getting Started

### 1. Compile

Open `BlogMicroservices.groupproj` in the Delphi IDE and build all projects (Ctrl+Shift+F9). This compiles all 8 services into the configured output directory.

Alternatively, compile each `.dproj` individually.

### 2. Start the Services

**Option A -- Using the Controller (recommended):**

```
ms.controller.exe
```

The controller starts all 7 services in the correct dependency order, monitors their health every 10 seconds, and auto-restarts crashed services (up to 3 times). Press Enter or POST to `/api/shutdown` to stop everything gracefully.

**Option B -- Using the script:**

```
start-all.cmd
```

This starts each service in a minimized console window. Use `stop-all.cmd` to shut them down.

### 3. Populate Demo Data

```
seed-data.cmd
```

Creates a demo author (Max Mustermann), 4 tags, and 3 sample blog posts with tag assignments. Login credentials: `max@example.com` / `demo1234`.

### 4. Open the Blog

Navigate to [http://localhost:8080](http://localhost:8080) in your browser.

### 5. Check Service Health

```
status.cmd
```

Or query the controller API:

```
curl http://localhost:8090/api/status
```

---

## Project Structure

```
mormot2-microservices/
|
|-- shared/                      Shared units (used by all services)
|   |-- ms.shared.pas              Constants, config loading, slug generation
|   |-- ms.shared.service.pas      Base service class (HTTP server, health, shutdown)
|   |-- ms.shared.jwt.pas          JWT token creation and validation
|   |-- ms.shared.client.pas       HTTP client for inter-service communication
|   +-- ms.shared.dto.pas          Data transfer objects
|
|-- ms.auth/                     Authentication service
|   |-- ms.auth.dpr                Entry point
|   |-- ms.auth.model.pas          TOrmAuthUser (email, password hash, salt)
|   +-- ms.auth.server.pas         Login, register, validate, change-password
|
|-- ms.users/                    User/author profiles
|-- ms.posts/                    Blog posts with pagination
|-- ms.tags/                     Tags and post-tag associations
|-- ms.comments/                 Comments with moderation
|-- ms.media/                    File upload and storage
|
|-- ms.gateway/                  API Gateway
|   |-- ms.gateway.dpr
|   |-- ms.gateway.server.pas      Routing, proxying, JWT validation, aggregation
|   +-- www/                       Frontend SPA
|       |-- index.html               Single-page application shell
|       |-- css/style.css            Styling
|       +-- js/
|           |-- api.js               API client library
|           +-- app.js               UI logic and routing
|
|-- ms.controller/               Service orchestrator
|   +-- ms.controller.orchestrator.pas  Process management, health checks
|
|-- BlogMicroservices.groupproj  Delphi project group (all 8 projects)
|-- start-all.cmd                Start all services via script
|-- stop-all.cmd                 Stop all services via script
|-- seed-data.cmd                Create demo data
|-- status.cmd                   Check service health
+-- ARCHITECTURE.md              Detailed architecture diagrams
```

---

## Key Features

### API Gateway with Response Aggregation

The gateway doesn't just proxy requests. When you fetch a single blog post, it **aggregates** data from multiple services into one response:

```
GET /api/posts/1  -->  Gateway queries:
                         1. Posts service   -> post data
                         2. Users service   -> author profile
                         3. Tags service    -> assigned tags
                         4. Comments service -> approved comments
                       Returns unified JSON with all data
```

### JWT Authentication

- Passwords hashed with SHA-256 + random salt
- JWT tokens (HMAC-SHA256) with 24-hour expiration
- Gateway validates tokens by calling the auth service
- Public endpoints (reading posts, submitting comments) require no authentication

### Comment Moderation Workflow

1. Visitors submit comments without login (status: **pending**)
2. Authors see pending comments in their dashboard
3. Authors approve or reject each comment
4. Only approved comments appear on the blog

### Tag System

- Tags are managed as a separate service
- Many-to-many relationships via a PostTag junction table
- Tags can be assigned via checkboxes in the post editor
- New tags can be created inline

### Service Orchestrator

The controller (`ms.controller`) manages the complete service lifecycle:

- Starts services in dependency order
- Health checks every 10 seconds via `/api/health`
- Automatic restart on crash (max 3 attempts)
- Graceful shutdown via `/api/shutdown` POST, then force-kill if needed
- REST API for remote management

---

## Configuration

Each service reads its configuration from `{service-name}.config.json` in the executable directory. If the file doesn't exist, sensible defaults are used.

Example (`ms.gateway.config.json`):

```json
{
  "Port": "8080",
  "LogLevel": "debug",
  "AuthUrl": "http://localhost:8081",
  "UsersUrl": "http://localhost:8082",
  "PostsUrl": "http://localhost:8083",
  "TagsUrl": "http://localhost:8084",
  "CommentsUrl": "http://localhost:8085",
  "MediaUrl": "http://localhost:8086"
}
```

Configurable options:

| Field | Description | Default |
|-------|-------------|---------|
| `Port` | HTTP listening port | Service-specific |
| `Database` | SQLite database filename | `data.db` |
| `LogLevel` | `trace`, `debug`, `info`, `warn`, `error` | `debug` |
| `JwtSecret` | HMAC key for JWT signing | Built-in default |
| `{Service}Url` | Backend service URLs (gateway only) | `http://localhost:{port}` |

---

## API Quick Reference

### Public Endpoints

```
GET  /api/posts?page=1&limit=10&status=1   List published posts
GET  /api/posts/{id}                        Single post (aggregated)
GET  /api/posts/by-slug/{slug}              Post by URL slug
GET  /api/posts/by-author/{id}              Posts by author
GET  /api/tags                              All tags
GET  /api/tags/{id}/posts                   Posts for a tag
GET  /api/posts/{id}/comments               Approved comments
POST /api/posts/{id}/comments               Submit a comment (no login)
POST /api/auth/login                        Get JWT token
POST /api/auth/register                     Create account
```

### Authenticated Endpoints (Bearer token required)

```
POST   /api/posts                           Create post
PUT    /api/posts/{id}                      Update post
DELETE /api/posts/{id}                      Delete post
PUT    /api/posts/{id}/tags                 Set post tags
POST   /api/tags                            Create tag
GET    /api/comments/pending                Pending comments
PUT    /api/comments/{id}/approve           Approve comment
PUT    /api/comments/{id}/reject            Reject comment
POST   /api/media/upload                    Upload file
PUT    /api/auth/change-password            Change password
```

---

## What You Can Learn

This project covers a wide range of topics relevant to modern software architecture, all implemented in Delphi:

### Microservice Patterns

- **Service decomposition** -- splitting a monolith into focused services
- **API Gateway** -- central entry point with routing, authentication, and response aggregation
- **Database per service** -- each service owns its data, no shared databases
- **Inter-service communication** -- synchronous REST/JSON calls between services
- **Service orchestration** -- automated startup, health monitoring, and restart

### mORMot2 Framework

- **THttpAsyncServer** -- high-performance async HTTP server with IOCP
- **TRestServerDB + SQLite** -- ORM with automatic table creation and CRUD
- **TDocVariantData** -- flexible JSON parsing and manipulation
- **JWT authentication** -- token creation and validation with TJwtHS256
- **FormatUtf8, IdemPChar, PosExChar** -- efficient string handling utilities
- **TSynBackgroundTimer** -- background thread for periodic tasks

### Web Development

- **REST API design** -- resource-oriented endpoints with proper HTTP methods and status codes
- **JWT auth flow** -- token issuance, validation, and bearer header handling
- **CORS handling** -- cross-origin headers for API access
- **SPA architecture** -- single-page application with vanilla JavaScript
- **Response aggregation** -- combining data from multiple services into one response

### Delphi Techniques

- **Console applications** as lightweight services
- **Process management** with `CreateProcessW`, `TerminateProcess`, `WaitForSingleObject`
- **Configuration via JSON** with `RecordLoadJson`
- **URL routing** with `IdemPChar` and path parsing
- **Slug generation** with umlaut replacement and normalization
- **Graceful shutdown** via HTTP endpoint and console key detection

### DevOps Concepts

- **Health check endpoints** (`/api/health`) for monitoring
- **Graceful shutdown** (`/api/shutdown`) for zero-downtime deployments
- **Configuration externalization** via JSON config files
- **Logging** with configurable levels and file rotation
- **Seed scripts** for reproducible demo environments

---

## License

This project is provided as an educational resource. 
GNU GENERAL PUBLIC LICENSE, Version 3, 29 June 2007

---

## Acknowledgments

- [mORMot2](https://github.com/synopse/mORMot2) by Arnaud Bouchez -- the backbone of this project
- Built with [Delphi](https://www.embarcadero.com/products/delphi) by Embarcadero
