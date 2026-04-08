# Blog Microservices -- Workflows and Sequence Diagrams

All calls use mORMot2 SOA format:
`POST /api/{Interface}/{Method}` with JSON array body.

## 1. Read a Published Post (aggregated via IBlog)

```
Browser                Gateway              ms.posts     ms.users    ms.tags    ms.comments
  |                       |                    |            |           |            |
  |-- POST /api/Blog/     |                    |            |           |            |
  |   GetPostFull [42] -->|                    |            |           |            |
  |                       |-- IPost.Get(42) -->|            |           |            |
  |                       |<-- PostJson -------|            |           |            |
  |                       |-- IUser.Get(1) --->|            |           |            |
  |                       |<-- AuthorJson -----|            |           |            |
  |                       |-- ITag.GetByPost(42) --------->|           |            |
  |                       |<-- TagsJson -------|------------|           |            |
  |                       |-- IComment.GetByPost(42) ----->|---------->|            |
  |                       |<-- CommentsJson ---|------------|-----------|            |
  |                       |                    |            |           |            |
  |<-- Aggregated JSON    |                    |            |           |            |
  |    (Post+Author+      |                    |            |           |            |
  |     Tags+Comments) ---|                    |            |           |            |
```

## 2. SCRAM-MCF Login

```
Browser                    Gateway         ms.auth
  |                           |               |
  |-- POST /api/Auth/        |               |
  |   Challenge ["max@.."] ->|               |
  |                           |-- IAuth.Challenge("max@..") -->|
  |                           |<-- {aMcfInfo, aServerNonce} ---|
  |<-- MCF info + nonce ------|               |
  |                           |               |
  |   [Browser computes PBKDF2 + ClientProof] |
  |                           |               |
  |-- POST /api/Auth/        |               |
  |   Authenticate           |               |
  |   [email,nonce,proof] -->|               |
  |                           |-- IAuth.Authenticate(...) --->|
  |                           |<-- {Result, aToken, aUserId,  |
  |                           |     aServerProof} ------------|
  |<-- JWT token + UserId ----|               |
  |                           |               |
  |   [Browser verifies ServerProof]          |
  |   [Browser stores JWT in localStorage]    |
```

## 3. Create a New Post (authenticated)

```
Browser                Gateway         ms.posts
  |                       |               |
  |-- POST /api/Post/Add  |               |
  |   Header: Bearer JWT  |               |
  |   [{Title, Body, ...}]|               |
  |                       |-- IPost.Add({...}) -->|
  |                       |<-- {Result: 42} ------|
  |<-- {Result: 42} ------|               |
```

## 4. Submit a Comment (no login required)

```
Browser                Gateway         ms.comments
  |                       |               |
  |-- POST /api/Comment/  |               |
  |   Add [42, {Author-   |               |
  |   Name, Body}] ------>|               |
  |                       |-- IComment.Add(42, {...}) -->|
  |                       |<-- {Result: 7} -------------|
  |<-- {Result: 7} -------|  (status: pending)
```

## 5. Moderate a Comment (authenticated)

```
Browser                Gateway         ms.comments
  |                       |               |
  |-- POST /api/Comment/  |               |
  |   GetPending [] ----->|               |
  |                       |-- IComment.GetPending -->|
  |                       |<-- [{id:7, body:"..."}] -|
  |<-- Pending comments --|               |
  |                       |               |
  |-- POST /api/Comment/  |               |
  |   Approve [7, 1] ---->|               |
  |                       |-- IComment.Approve(7, 1) -->|
  |                       |<-- {Result: true} ----------|
  |<-- {Result: true} ----|               |
```

## 6. Assign Tags to a Post

```
Browser                Gateway         ms.tags
  |                       |               |
  |-- POST /api/Tag/      |               |
  |   SetPostTags         |               |
  |   [42, [1,3,5]] ----->|               |
  |                       |-- ITag.SetPostTags(42, [1,3,5]) -->|
  |                       |<-- {Result: true} ----------------|
  |<-- {Result: true} ----|               |
```

## 7. Load Post List (home page)

```
Browser                Gateway         ms.posts
  |                       |               |
  |-- POST /api/Post/     |               |
  |   GetList             |               |
  |   [1, 10, 1, 0] ---->|               |
  |   (page, limit,       |               |
  |    status, authorId)  |               |
  |                       |-- IPost.GetList(1, 10, 1, 0) -->|
  |                       |<-- {Result: {items:[...],       |
  |                       |     total:3, page:1}} ----------|
  |<-- Paginated post  ---|               |
  |    list               |               |
```
