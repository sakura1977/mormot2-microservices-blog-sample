# Blog Microservices -- Workflows and Sequence Diagrams

All calls use mORMot2 SOA format:
`POST /api/{Interface}/{Method}` with JSON array body.

## 1. Read a Published Post (aggregated via IBlog)

```mermaid
sequenceDiagram
    participant B as Browser
    participant GW as Gateway
    participant P as ms.posts
    participant U as ms.users
    participant T as ms.tags
    participant C as ms.comments

    B->>GW: POST /api/Blog/GetPostFull [42]
    Note over GW: TBlogService (local)
    GW->>P: IPost.Get(42)
    P-->>GW: PostJson
    GW->>U: IUser.Get(authorId)
    U-->>GW: AuthorJson
    GW->>T: ITag.GetByPost(42)
    T-->>GW: TagsJson
    GW->>C: IComment.GetByPost(42)
    C-->>GW: CommentsJson
    GW-->>B: {Title, Author, Tags, Comments}
```

## 2. Posts by Tag (aggregated via IBlog)

```mermaid
sequenceDiagram
    participant B as Browser
    participant GW as Gateway
    participant T as ms.tags
    participant P as ms.posts
    participant U as ms.users

    B->>GW: POST /api/Blog/GetPostsByTag [3]
    Note over GW: TBlogService (local)
    GW->>T: ITag.Get(3)
    T-->>GW: TagJson
    GW->>T: ITag.GetPostIds(3)
    T-->>GW: [1, 5, 7]
    loop Each PostId (published only)
        GW->>P: IPost.Get(id)
        P-->>GW: PostJson
        GW->>U: IUser.Get(authorId)
        U-->>GW: AuthorJson
    end
    GW-->>B: {Tag:{...}, Posts:[...]}
```

## 3. SCRAM-MCF Login

```mermaid
sequenceDiagram
    participant B as Browser
    participant GW as Gateway
    participant A as ms.auth

    Note over B,A: Phase 1 -- Challenge
    B->>GW: POST /api/Auth/Challenge ["max@..."]
    GW->>A: IAuth.Challenge("max@...")
    A-->>GW: {aMcfInfo, aServerNonce}
    GW-->>B: {aMcfInfo, aServerNonce}

    Note over B: Phase 2 -- Client computes PBKDF2 + ClientProof

    Note over B,A: Phase 3 -- Authenticate
    B->>GW: POST /api/Auth/Authenticate [email, nonce, proof]
    GW->>A: IAuth.Authenticate(...)
    A->>A: Verify SCRAM proof
    A->>A: Create JWT (HMAC-SHA256, 24h)
    A-->>GW: {Result:true, aToken, aUserId, aServerProof}
    GW-->>B: {Result, aToken, aUserId, aServerProof}

    Note over B: Phase 4 -- Browser verifies ServerProof, stores JWT
```

## 4. Create a New Post (authenticated)

```mermaid
sequenceDiagram
    participant B as Browser
    participant GW as Gateway
    participant P as ms.posts

    B->>GW: POST /api/Post/Add [{Title, Body, ...}]
    Note over B: Bearer JWT in header
    GW->>P: IPost.Add({...})
    P-->>GW: {Result: 42}
    GW-->>B: {Result: 42}
```

## 5. Submit a Comment (no login required)

```mermaid
sequenceDiagram
    participant V as Visitor
    participant GW as Gateway
    participant C as ms.comments

    V->>GW: POST /api/Comment/Add [42, {AuthorName, Body}]
    GW->>C: IComment.Add(42, {...})
    C->>C: Status = PENDING (0)
    C-->>GW: {Result: 7}
    GW-->>V: {Result: 7}
```

## 6. Moderate a Comment (authenticated)

```mermaid
sequenceDiagram
    participant A as Author
    participant GW as Gateway
    participant C as ms.comments

    A->>GW: POST /api/Comment/GetPending []
    GW->>C: IComment.GetPending
    C-->>GW: [{id:7, body:"..."}]
    GW-->>A: Pending comments

    A->>GW: POST /api/Comment/Approve [7, 1]
    GW->>C: IComment.Approve(7, 1)
    C->>C: Status = APPROVED, set ModeratedBy/At
    C-->>GW: {Result: true}
    GW-->>A: {Result: true}
```

## 7. Assign Tags to a Post

```mermaid
sequenceDiagram
    participant B as Browser
    participant GW as Gateway
    participant T as ms.tags

    B->>GW: POST /api/Tag/SetPostTags [42, [1, 3, 5]]
    GW->>T: ITag.SetPostTags(42, [1,3,5])
    T->>T: Delete existing PostTag for PostId=42
    T->>T: Create new PostTag records
    T-->>GW: {Result: true}
    GW-->>B: {Result: true}
```

## 8. Load Post List (home page)

```mermaid
sequenceDiagram
    participant B as Browser
    participant GW as Gateway
    participant P as ms.posts

    B->>GW: POST /api/Post/GetList [1, 10, 1, 0]
    Note right of B: page, limit, status, authorId
    GW->>P: IPost.GetList(1, 10, 1, 0)
    P-->>GW: {Result: {items:[...], total:3, page:1}}
    GW-->>B: Paginated post list
```
