# Blog Microservices -- Documentation

Microservice-based blog system with **Delphi 13** and **mORMot2**.

## Quick Start

```
1. Open BlogMicroservices.groupproj in Delphi
2. Run "Build All"
3. Run start-all.cmd
4. Run seed-data.cmd (demo data)
5. Open http://localhost:8080 in browser
6. Login: max@example.com / demo1234
```

## Documentation

| File | Content |
|------|---------|
| [architecture.md](architecture.md) | Architecture overview, service table, communication principles |
| [services.md](services.md) | Detailed service definitions with SOA interfaces and data models |
| [technology.md](technology.md) | mORMot2 modules, project structure, code patterns, configuration |
| [workflows.md](workflows.md) | Sequence diagrams for all key workflows |

## Architecture

- **API style**: mORMot2 SOA (interface-based services)
- **URL format**: `POST /api/{ServiceName}/{MethodName}` with JSON array body
- **Authentication**: SCRAM-MCF (PBKDF2-SHA256, client-side hashing)

## Services

| Service | Port | SOA Interface | Description |
|---------|------|---------------|-------------|
| ms.gateway | 8080 | IBlog + Proxies | API gateway + web frontend |
| ms.auth | 8081 | IAuth | SCRAM-MCF authentication, JWT tokens |
| ms.users | 8082 | IUser | Author profiles and bios |
| ms.posts | 8083 | IPost | Blog posts with pagination |
| ms.tags | 8084 | ITag | Tag management (m:n with posts) |
| ms.comments | 8085 | IComment | Comments with moderation workflow |
| ms.media | 8086 | IMedia | Image upload and serving |

## Technology

- **Language**: Object Pascal (Delphi 13)
- **Framework**: mORMot2
- **Database**: SQLite (one DB per service)
- **Communication**: mORMot2 SOA over REST/HTTP with JSON
- **Authentication**: SCRAM-MCF + JWT (HMAC-SHA256)
- **Frontend**: Vanilla JS SPA (no dependencies)
- **Logging**: TSynLog with rotation (5 x 5 MB per service)

## Operations Scripts

| Script | Purpose |
|--------|---------|
| `start-all.cmd` | Start all 7 services in correct order |
| `stop-all.cmd` | Graceful shutdown of all services (via POST /api/shutdown) |
| `status.cmd` | Health check all services (via GET /api/health) |
| `seed-data.cmd` | Create demo data (1 author, 3 posts, 4 tags) |

## Project Structure

```
BlogMicroservices.groupproj    IDE project group
start-all.cmd / stop-all.cmd   Operations scripts
seed-data.cmd / status.cmd     Demo data / health checks
shared/                        4 shared units
  ms.shared.pas                  Constants, config, slug generation
  ms.shared.api.pas              SOA interface definitions (IAuth, IUser, ...)
  ms.shared.jwt.pas              JWT token creation and validation
  ms.shared.service.pas          TMicroService base class, RegisterService,
                                   OrmGetById, OrmGetAll
ms.gateway/                    Gateway + www/ frontend
ms.auth/                       Auth service (model + server)
ms.users/                      Users service (model + server)
ms.posts/                      Posts service (model + server)
ms.tags/                       Tags service (model + server)
ms.comments/                   Comments service (model + server)
ms.media/                      Media service (model + server)
test/                          In-process integration tests
  ms.testCases.pas               130+ assertions (positive + negative)
  ms.tests.dpr                   Console test runner
```
