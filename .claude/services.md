# Blog-Microservices -- Service-Definitionen und SOA-Interfaces

Alle Services nutzen mORMot2 interface-basierte Services (SOA).
URL-Format: `POST /api/{InterfaceName}/{MethodName}` mit JSON-Array als Body.
Antwortformat: JSON-Objekt mit benannten Parametern (`ResultAsJsonObjectWithoutResult`).

---

## Service-uebergreifend: Management-Endpunkte

Jeder Microservice stellt automatisch zwei method-based Endpunkte bereit (via `TMicroService`-Basisklasse aus `ms.shared.service.pas`):

```
GET    /api/health      Health-Check
         Response: { "service": "ms.auth", "status": "ok",
                     "port": "8081", "version": "0.2.0",
                     "uptime": "..." }

POST   /api/shutdown    Sauberes Herunterfahren
         Response: HTTP 200
```

---

## SOA-Interface-Definitionen (ms.shared.api.pas)

Alle Interfaces sind in `ms.shared.api.pas` definiert und werden sowohl
von den Backend-Services (Implementierung) als auch vom Gateway (Client-Proxies) genutzt.

---

## 1. ms.gateway (Port 8080)

### Aufgabe
API-Gateway und Web-Frontend. Leitet SOA-Aufrufe als Proxy an Backend-Services weiter
und aggregiert Daten ueber den IBlog-Service.

### SOA-Interface: IBlog (nur im Gateway)

```pascal
IBlog = interface(IInvokable)
  function GetPostFull(aId: TID): RawJson;
    // Aggregiert: Post + Author + Tags + Comments
end;
```

### Transparentes SOA-Proxying (keine manuellen Proxy-Klassen)
- Backend-Interfaces werden via `TRestHttpClient.Services.Resolve` aufgeloest
- Die resultierenden `TInterfacedObjectFake`-Instanzen werden direkt als
  Server-Services auf dem Gateway registriert (`RegisterService`)
- Client-Factories verwenden `ResultAsJsonObjectWithoutResult := True`

### Statische Dateien
- SPA-Frontend aus `www/` (index.html, css/, js/)
- Nicht-API-URLs werden als statische Dateien oder SPA-Fallback bedient

### Keine eigene Datenbank

---

## 2. ms.auth (Port 8081)

### Aufgabe
SCRAM-MCF Authentifizierung mit PBKDF2-SHA256 und JWT-Tokens.

### Datenmodell

```pascal
TOrmAuthUser = class(TOrm)
  property Email: RawUtf8        // E-Mail (eindeutig, Login-Name)
  property McfHash: RawUtf8      // MCF-Format Passwort-Hash (PBKDF2-SHA256)
  property UserId: TID           // Referenz auf ms.users (Autoren-ID)
  property IsActive: boolean     // Konto aktiv?
  property CreatedAt: TDateTime
  property LastLogin: TDateTime
end;
```

### SOA-Interface: IAuth

```pascal
IAuth = interface(IInvokable)
  procedure Challenge(const aEmail: RawUtf8;
    out aMcfInfo, aServerNonce: RawUtf8);
  function Authenticate(const aEmail, aServerNonce, aClientProof: RawUtf8;
    out aToken: RawUtf8; out aUserId: TID;
    out aServerProof: RawUtf8): boolean;
  function Register(const aEmail, aPassword: RawUtf8;
    aUserId: TID): TID;
  function Validate(const aToken: RawUtf8;
    out aUserId: TID): boolean;
  function ChangePassword(aUserId: TID;
    const aOldPassword, aNewPassword: RawUtf8): boolean;
end;
```

### SCRAM-MCF Ablauf
1. Client ruft `Challenge` auf -> erhaelt MCF-Info (Salt, Rounds) + ServerNonce
2. Client berechnet PBKDF2 lokal, erzeugt ClientProof
3. Client ruft `Authenticate` auf -> Server verifiziert, liefert JWT + ServerProof
4. Client verifiziert ServerProof (gegenseitige Authentifizierung)

---

## 3. ms.users (Port 8082)

### Aufgabe
Verwaltung der Autorenprofile.

### Datenmodell

```pascal
TOrmAuthor = class(TOrm)
  property DisplayName: RawUtf8
  property Bio: RawUtf8
  property WebsiteUrl: RawUtf8
  property AvatarMediaId: TID
  property CreatedAt: TDateTime
  property UpdatedAt: TDateTime
end;
```

### SOA-Interface: IUser

```pascal
IUser = interface(IInvokable)
  function Get(aId: TID): RawJson;
  function GetAll: RawJson;
  function Add(const aData: RawJson): TID;
  function Update(aId: TID; const aData: RawJson): boolean;
  function Remove(aId: TID): boolean;
end;
```

---

## 4. ms.posts (Port 8083)

### Aufgabe
Blog-Beitraege mit Paginierung, Filterung und SEO-Metadaten.

### Datenmodell

```pascal
TOrmBlogPost = class(TOrm)
  property Title: RawUtf8
  property Slug: RawUtf8          // stored AS_UNIQUE
  property Body: RawUtf8
  property Excerpt: RawUtf8
  property AuthorId: TID
  property FeaturedImageId: TID
  property MetaTitle: RawUtf8
  property MetaDescription: RawUtf8
  property MetaKeywords: RawUtf8
  property Status: integer        // 0=Entwurf, 1=Veroeffentlicht, 2=Archiviert
  property PublishedAt: TDateTime
  property CreatedAt: TDateTime
  property UpdatedAt: TDateTime
end;
```

### SOA-Interface: IPost

```pascal
IPost = interface(IInvokable)
  function Get(aId: TID): RawJson;
  function GetBySlug(const aSlug: RawUtf8): RawJson;
  function GetList(aPage, aLimit, aStatus: integer;
    aAuthorId: TID): RawJson;
  function Add(const aData: RawJson): TID;
  function Update(aId: TID; const aData: RawJson): boolean;
  function Remove(aId: TID): boolean;
end;
```

---

## 5. ms.tags (Port 8084)

### Aufgabe
Tag-Verwaltung und m:n-Zuordnung zu Beitraegen.

### Datenmodell

```pascal
TOrmBlogTag = class(TOrm)
  property Name: RawUtf8          // stored AS_UNIQUE
  property Slug: RawUtf8          // stored AS_UNIQUE
  property Description: RawUtf8
  property CreatedAt: TDateTime
end;

TOrmPostTag = class(TOrm)
  property PostId: TID
  property TagId: TID
end;
```

### SOA-Interface: ITag

```pascal
ITag = interface(IInvokable)
  function Get(aId: TID): RawJson;
  function GetAll: RawJson;
  function GetByPost(aPostId: TID): RawJson;
  function SetPostTags(aPostId: TID;
    const aTagIds: RawJson): boolean;
  function Add(const aData: RawJson): TID;
  function Update(aId: TID; const aData: RawJson): boolean;
  function Remove(aId: TID): boolean;
end;
```

---

## 6. ms.comments (Port 8085)

### Aufgabe
Kommentarsystem mit Moderations-Workflow.

### Datenmodell

```pascal
TOrmBlogComment = class(TOrm)
  property PostId: TID
  property AuthorName: RawUtf8
  property AuthorEmail: RawUtf8
  property Body: RawUtf8
  property Status: integer       // 0=Ausstehend, 1=Freigegeben, 2=Abgelehnt
  property ModeratedBy: TID
  property ModeratedAt: TDateTime
  property CreatedAt: TDateTime
end;
```

### SOA-Interface: IComment

```pascal
IComment = interface(IInvokable)
  function GetByPost(aPostId: TID): RawJson;
  function GetPending: RawJson;
  function Add(aPostId: TID; const aData: RawJson): TID;
  function Approve(aId, aModeratedBy: TID): boolean;
  function Reject(aId, aModeratedBy: TID): boolean;
  function Remove(aId: TID): boolean;
end;
```

---

## 7. ms.media (Port 8086)

### Aufgabe
Verwaltung von Mediendateien (Bilder). Upload via Base64, Speicherung auf Dateisystem.

### Datenmodell

```pascal
TOrmMediaFile = class(TOrm)
  property FileName: RawUtf8
  property StoragePath: RawUtf8
  property MimeType: RawUtf8
  property FileSize: Int64
  property AltText: RawUtf8
  property UploadedBy: TID
  property CreatedAt: TDateTime
end;
```

### Speicherung
- Bilder werden im lokalen Dateisystem abgelegt: `./media/{id}_{filename}`
- Metadaten in der SQLite-Datenbank

### SOA-Interface: IMedia

```pascal
IMedia = interface(IInvokable)
  function Upload(const aFileName, aFileData, aAltText: RawUtf8;
    aUploadedBy: TID): TID;
  function GetInfo(aId: TID): RawJson;
  function GetFile(aId: TID;
    out aContentType: RawUtf8): RawByteString;
  function Remove(aId: TID): boolean;
end;
```

---

## Service-Abhaengigkeiten

```
ms.gateway  -->  ms.auth       (Token-Validierung)
ms.gateway  -->  ms.users      (Autorenprofile)
ms.gateway  -->  ms.posts      (Beitraege)
ms.gateway  -->  ms.tags       (Tags)
ms.gateway  -->  ms.comments   (Kommentare)
ms.gateway  -->  ms.media      (Bilder)

ms.auth     -->  (keine -- speichert nur UserId als Referenz)
ms.posts    -->  (keine -- speichert nur IDs)
ms.tags     -->  (keine -- speichert nur IDs)
ms.comments -->  (keine -- speichert nur IDs)
ms.media    -->  (keine -- speichert nur IDs)
ms.users    -->  (keine -- speichert nur IDs)
```
