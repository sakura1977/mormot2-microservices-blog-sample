# Blog Microservices -- Architecture

## Goal

A simple blog system built as a microservice architecture with **Delphi 13** and **mORMot2**. Each business function runs in its own console EXE with its own SQLite database.

## Service Overview

```
                    +--------+---------+
                    |   ms.gateway     |
                    |  (HTTP Gateway + |
                    |   Web Frontend)  |
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

## Services at a Glance

| # | Service           | Port  | Interface | Responsibility                        |
|---|-------------------|-------|-----------|---------------------------------------|
| 1 | **ms.gateway**    | 8080  | IBlog     | API gateway, proxies, web frontend    |
| 2 | **ms.auth**       | 8081  | IAuth     | SCRAM-MCF login, JWT tokens           |
| 3 | **ms.users**      | 8082  | IUser     | Author profiles, bios                 |
| 4 | **ms.posts**      | 8083  | IPost     | Blog posts, SEO metadata              |
| 5 | **ms.tags**       | 8084  | ITag      | Tags, post-tag associations (m:n)     |
| 6 | **ms.comments**   | 8085  | IComment  | Comments, moderation workflow         |
| 7 | **ms.media**      | 8086  | IMedia    | Image upload, storage                 |

## API Style: mORMot2 SOA

All services use interface-based services (SOA), not classical REST endpoints.

- **URL format**: `POST /api/{InterfaceName}/{MethodName}`
- **Request body**: JSON array of positional parameters `[param1, param2, ...]`
- **Response**: JSON object with named output parameters (ResultAsJsonObjectWithoutResult)
- **Interfaces**: Defined in `ms.shared.api.pas`, shared by all services

### Example: Create a tag

```
POST /api/Tag/Add
Body: [{"Name":"Delphi","Description":"Everything about Delphi"}]
Response: {"Result":1}
```

## Communication

- **Browser -> Gateway**: HTTP/JSON (SOA format via api.js)
- **Gateway -> Backend**: mORMot2 SOA via `TRestHttpClient` + `TServiceFactoryClient`
- **Authentication**: SCRAM-MCF (Challenge/Authenticate), then JWT token in Authorization header
- **Database**: Each service has its own SQLite file (via mORMot2 ORM)

## Management Endpoints

Every service automatically provides (via TMicroService base class):

```
GET  /api/health       Health check (JSON with service name, port, version, uptime)
POST /api/shutdown     Graceful shutdown
```

## Principles

1. **Single Responsibility** -- each service has exactly one business concern
2. **Own Data Store** -- no service accesses another service's database
3. **Loose Coupling** -- services communicate exclusively via SOA interfaces
4. **Gateway Pattern** -- all browser requests go through the gateway
5. **Custom Auth** -- SCRAM-MCF instead of mORMot2's built-in REST authentication

## Service Dependencies

```
ms.gateway  -->  ms.auth       (token validation)
ms.gateway  -->  ms.users      (author profiles)
ms.gateway  -->  ms.posts      (blog posts)
ms.gateway  -->  ms.tags       (tags)
ms.gateway  -->  ms.comments   (comments)
ms.gateway  -->  ms.media      (media files)

All other services: no inter-dependencies
(Cross-references stored as IDs only, resolved in gateway via IBlog.GetPostFull)
```
