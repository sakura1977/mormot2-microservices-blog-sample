# ms.tags -- Tag Service

Port **8084** | Interface **ITag** | Database `ms.tags.db`

Tag management and many-to-many post-tag associations via a junction table.

## SOA Interface

```
POST /api/Tag/{Method}
```

| Method | Signature | Description |
|--------|-----------|-------------|
| Get | `(aId): TTagDto` | Single tag, ID=0 if not found |
| GetAll | `(): TTagDtoArray` | All tags as typed array |
| GetByPost | `(aPostId): TTagDtoArray` | Tags assigned to a post |
| GetPostIds | `(aTagId): TIDDynArray` | Post IDs that have this tag |
| SetPostTags | `(aPostId, aTagIds): boolean` | Replace all tag assignments for a post |
| Add | `(const aData: TTagCreateDto): TID` | Creates tag, auto-generates slug |
| Update | `(aId, aData): boolean` | Partial update |
| Remove | `(aId): boolean` | Deletes tag + all associations |

## Data Model

```mermaid
erDiagram
    BlogTag {
        int RowID PK
        string Name UK
        string Slug UK
        string Description
        datetime CreatedAt
    }

    PostTag {
        int RowID PK
        int PostId FK
        int TagId FK
    }

    BlogTag ||--o{ PostTag : TagId
```

## Implementation Details

- **Junction table**: `TOrmPostTag` links posts and tags (m:n relationship)
- **SetPostTags**: atomic replace -- deletes existing associations, creates new ones, with duplicate prevention
- **Cascade delete**: removing a tag also deletes all its `PostTag` entries
- **Slug generation**: auto-generated from `Name` via `TextToSlug`
- **GetPostIds**: used by the gateway's `IBlog.GetPostsByTag` aggregation
