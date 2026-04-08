# test -- Integration Test Suite

All 7 microservices run **in a single process** with an in-memory SQLite database. No HTTP servers, no ports, no separate processes needed.

## Running

Open `ms.tests.dpr` in the Delphi IDE and run (F9). Results are printed to the console.

## How It Works

`TBlogTestContext` creates one `TRestServerDB` with `SQLITE_MEMORY_DATABASE_NAME` (`:memory:`) containing all ORM tables from all services. All service implementations share the same `IRestOrm` and are registered on the same REST server. Tests call SOA interfaces directly -- in-process, no HTTP overhead.

## Test Classes

| Class | Service | Tests |
|-------|---------|-------|
| TTestUserService | ms.users | AddAndGet, AddEmptyName, GetNotFound, Update, GetAll, Remove |
| TTestAuthService | ms.auth | Register, Challenge, Authenticate, Validate, ChangePassword |
| TTestPostService | ms.posts | AddAndGet, GetBySlug, GetList, Update, Remove |
| TTestTagService | ms.tags | AddAndGet, SetPostTags, GetByPost, GetPostIds, Remove, RemoveCascade |
| TTestCommentService | ms.comments | AddPending, AddEmptyBody, Approve, Reject, GetByPost |
| TTestMediaService | ms.media | Upload, GetInfo, GetFile, Remove, UploadTooLarge |
| TTestBlogAggregation | ms.gateway | GetPostFull, GetPostsByTag |
| TTestFullWorkflow | end-to-end | Complete user registration through comment moderation |

## Framework

Uses mORMot2's `TSynTests` / `TSynTestCase` with `Check()` and `CheckEqual()` assertions.
