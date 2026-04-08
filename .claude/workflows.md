# Blog-Microservices -- Ablaeufe und Workflows

Alle Aufrufe verwenden mORMot2 SOA-Format:
`POST /api/{Interface}/{Method}` mit JSON-Array als Body.

## 1. Oeffentlichen Beitrag lesen (aggregiert ueber IBlog)

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
  |<-- Aggregiertes JSON  |                    |            |           |            |
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
  |<-- MCF-Info + Nonce ------|               |
  |                           |               |
  |   [Browser berechnet PBKDF2 + ClientProof]|
  |                           |               |
  |-- POST /api/Auth/        |               |
  |   Authenticate           |               |
  |   [email,nonce,proof] -->|               |
  |                           |-- IAuth.Authenticate(...) --->|
  |                           |<-- {Result, aToken, aUserId,  |
  |                           |     aServerProof} ------------|
  |<-- JWT-Token + UserId ----|               |
  |                           |               |
  |   [Browser verifiziert ServerProof]       |
  |   [Browser speichert JWT in localStorage] |
```

## 3. Neuen Beitrag erstellen (angemeldet)

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

## 4. Kommentar abgeben (ohne Anmeldung)

```
Browser                Gateway         ms.comments
  |                       |               |
  |-- POST /api/Comment/  |               |
  |   Add [42, {Author-   |               |
  |   Name, Body}] ------>|               |
  |                       |-- IComment.Add(42, {...}) -->|
  |                       |<-- {Result: 7} -------------|
  |<-- {Result: 7} -------|  (Status: ausstehend)
```

## 5. Kommentar moderieren (angemeldet)

```
Browser                Gateway         ms.comments
  |                       |               |
  |-- POST /api/Comment/  |               |
  |   GetPending [] ----->|               |
  |                       |-- IComment.GetPending -->|
  |                       |<-- [{id:7, body:"..."}] -|
  |<-- Ausstehende -------|               |
  |    Kommentare         |               |
  |                       |               |
  |-- POST /api/Comment/  |               |
  |   Approve [7, 1] ---->|               |
  |                       |-- IComment.Approve(7, 1) -->|
  |                       |<-- {Result: true} ----------|
  |<-- {Result: true} ----|               |
```

## 6. Tags einem Beitrag zuordnen

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

## 7. Beitrags-Liste laden (Startseite)

```
Browser                Gateway         ms.posts
  |                       |               |
  |-- POST /api/Post/     |               |
  |   GetList             |               |
  |   [1, 10, 1, 0] ---->|               |
  |   (page,limit,        |               |
  |    status,authorId)   |               |
  |                       |-- IPost.GetList(1, 10, 1, 0) -->|
  |                       |<-- {Result: {items:[...],       |
  |                       |     total:3, page:1}} ----------|
  |<-- Paginierte --------|               |
  |    Beitragsliste      |               |
```
