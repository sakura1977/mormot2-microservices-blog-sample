# Delphi/Object Pascal – Coding Style Guide

Diese Anleitung beschreibt den verbindlichen Coding-Stil für alle Delphi/Object-Pascal-Dateien
in diesem Repository. Alle Regeln wurden aus dem bestehenden, manuell formatierten Quellcode
abgeleitet und sind bei jeder Code-Generierung einzuhalten.

---

## 1  Dateistruktur

### 1.1  Encoding
- Jede `.pas`-Datei beginnt mit einem **UTF-8 BOM** (`﻿`).
- Zeilenenden: CRLF (Windows).

### 1.2  Dateiaufbau (Reihenfolge)
```pascal
﻿/// <summary>
///   Einzeilige oder mehrzeilige Zusammenfassung des Units.
/// </summary>
unit Namespace.UnitName;

{$SCOPEDENUMS ON}

{$WARN SYMBOL_PLATFORM OFF}
{$WARN UNIT_PLATFORM   OFF}
// ggf. weitere {$WARN …} Suppressions

interface

uses
  …;

type
  …;

implementation

…

end.
```

### 1.3  Zeilenlänge

- Maximal **120 Zeichen** pro Zeile. Ein paar wenige mehr (bis ~125) sind kein Problem.
- **Nicht zu früh umbrechen!** Zeilen sollen die verfügbaren 120 Zeichen **ausnutzen**. Code,
  der auf eine Zeile unter 120 Zeichen passt, gehört auf **eine** Zeile. Umbrüche bei 60, 70
  oder 80 Zeichen sind **genauso falsch** wie Zeilen mit 150 Zeichen.
- Diese Regel gilt für Code **und** Kommentare gleichermaßen.
- **Ausnahme**: Methodensignaturen mit Parametern folgen §5.2 (ein Parameter pro Zeile) — dort
  werden kurze Zeilen akzeptiert, weil die Struktur wichtiger ist als die Zeilenausnutzung.

### 1.4  Compiler-Direktiven
Direkt nach dem `unit`-Statement, vor `interface`:

| Direktive | Pflicht | Anmerkung |
|-----------|---------|-----------|
| `{$SCOPEDENUMS ON}` | ja | immer erste Direktive |
| `{$WARN SYMBOL_PLATFORM OFF}` | ja |  |
| `{$WARN UNIT_PLATFORM OFF}` | ja |  |
| `{$WARN IMPLICIT_STRING_CAST OFF}` | bei Bedarf |  |
| `{$WARN IMPLICIT_STRING_CAST_LOSS OFF}` | bei Bedarf |  |

---

## 2  Uses-Klausel

- Pro Zeile **ein** Unit-Name.
- Reihenfolge: `System.*` → `Winapi.*` → `Vcl.*` → Projekt-eigene Units.
- Innerhalb jeder Gruppe alphabetisch sortiert.
- Werden, wenn möglich, immer im interface-Teil der Datei genannt, in implementation ausschließlich, wenn ansonsten zirkuläre Aufrufe ausgelöst werden.

```pascal
uses
  System.Character,
  System.Generics.Collections,
  System.SysUtils,
  lw.lexer.types;
```

---

## 3  Benennung (Naming Conventions)

| Kategorie | Präfix | Stil | Beispiel | Sonstiges |
|-----------|--------|------|----------|-----------|
| Typen (class, record, enum, interface) | `T` | PascalCase | `TToken`, `TTriviaKind` | |
| Interfaces | `I` | PascalCase | `ICstNode` | |
| Instanzfelder | `F` | PascalCase | `FSource`, `FCurrent` | |
| Class-Variablen | `F` | PascalCase | `FMap`, `FRootDirectory` | |
| Parameter | `a` | camelCase | `aKind`, `aText`, `aOffset` | |
| Lokale Variablen | – | PascalCase | `Offset`, `TriviaList`, `StartIdx` | Immer aussagekräftige Namen verwenden |
| Konstanten | – | UPPER\_SNAKE\_CASE | `MAX_TOKEN_LENGTH`, `DEFAULT_BUFFER_SIZE` | |
| Enum-Werte | – | PascalCase | `TokenLeaf`, `EndOfLine` | |
| Reservierte Wörter als Bezeichner | `&` | PascalCase | `&At`, `&Type`, `&Array` | |

> **Hinweis:** Da `{$SCOPEDENUMS ON}` aktiv ist, werden Enum-Werte immer voll qualifiziert
> verwendet: `TTokenKind.EOF`, nicht `EOF`. In Fällen, wo die Quelle SCOPEDENUMS nicht definiert oder gar auf OFF setzt, trotzdem immer voll qualifizieren.

### 3.1  Lokale Variablen

- Namen sind **vollständig beschreibend**, niemals nur 1 Buchstabe
- kein generisches `L`-Präfix, keine Abkürzungen, die den Zweck verschleiern
- PascalCase, kein Präfix
- Listen, Arrays und ähnliche werden **nie** mit dem Suffix "s" gebildet, sondern erhalten als Suffix `List`, `Array`, `Dictionary`, usw.
- Der Name benennt **was** die Variable enthält, nicht ihren Typ:

```pascal
// Gut
var
  StartIdx:     Integer;
  TriviaList:   TList<TTrivia>;
  FileContent:  string;
  PassCount:    Integer;

// Schlecht
var
  LStartIdx:  Integer;   // L-Präfix unnötig
  List:       TList<TTrivia>;  // zu generisch
  S:          string;    // einbuchstabig
  Cnt:        Integer;   // kryptische Abkürzung
```

### 3.2  Schleifen-Indexvariablen

Schleifen-Indexvariablen sind **niemals einbuchstabig** (`i`, `j`, `k`).
Der Name beschreibt, was iteriert wird:

```pascal
// Gut
for var CurrentFilename in FilenameArray do …
for var CurrentTokenIdx := 0 to High(TokenArray) do …
for var CurrentToken in TokenArray do …

// Schlecht
for var i := 0 to High(TokenArray) do …
for I := 0 to Count - 1 do …
```

---

## 4  XML-Dokumentationskommentare

### 4.1  Grundregel
**Alle** Typen, Methoden, Eigenschaften und Felder erhalten `/// <summary>…</summary>` XML-Kommentare, auch private. XML-Block-Tags werden **immer** auf eine eigene Zeile gesetzt. Für alle Methoden werden auch die Parameter und auftretende Exceptions in die XML-Kommentare aufgenommen. Für Funktionen werden mittels <return> die Rückgabewerte erklärt.

### 4.2  Format

**Grundregel: jedes öffnende Block-Tag steht allein auf seiner Zeile, der Inhalt
folgt eingerückt, das schließende Tag steht ebenfalls allein auf seiner Zeile.**
Diese Regel gilt ohne Ausnahme für `<summary>`, `<param>`, `<returns>`,
`<exception>` und alle weiteren Block-Tags.

```pascal
/// <summary>
///   Beschreibungstext hier.
/// </summary>
/// <param name="aKind">
///   Der Trivia-Typ des Elements.
/// </param>
/// <param name="aText">
///   Quelltextinhalt exakt wie in der Originaldatei.
/// </param>
/// <returns>
///   Ein neues TTrivia mit den übergebenen Werten.
/// </returns>
```

Jede Zeile beginnt mit `/// ` (mit Leerzeichen), Inhalt 2 Zeichen eingerückt
relativ zur `///`-Ebene.

Vor XML-Kommentaren ist **immer** eine Leerzeile!

### 4.3  Elemente

| Element | Verwendung |
|---------|------------|
| `<summary>` | Jede Deklaration (auch private) |
| `<param name="aXxx">` | Jeder Parameter von Methoden |
| `<returns>` | Rückgabewert von Funktionen |
| `<exception cref="TXxx">` | Jede `raise`-Anweisung |
| `<c>…</c>` | Inline-Code in Fließtext (kein Block-Tag, bleibt inline) |
| `<em>…</em>` | Hervorhebungen (kein Block-Tag, bleibt inline) |

> **Merksatz:** `<c>` und `<em>` sind **Inline**-Tags und dürfen im Fließtext
> stehen. Alle anderen Tags (`<summary>`, `<param>`, `<returns>`, `<exception>`)
> sind **Block**-Tags — öffnendes Tag, Inhalt und schließendes Tag stehen
> immer auf getrennten Zeilen.

### 4.4  Unit-Header
Vor dem `unit`-Schlüsselwort (aber nach dem BOM-bedingten Zeilenstart):
```pascal
﻿/// <summary>
///   Kurzbeschreibung: wichtigste Typen und Zweck dieses Units.
/// </summary>
unit lw.lexer.example;
```

---

## 5  Methodensignaturen (Deklarationen und Implementierungsköpfe)

Diese Regeln gelten für **Deklarationen** (`interface`-Teil) und **Implementierungsköpfe**
(`implementation`-Teil). Sie gelten **NICHT** für Funktions-/Methodenaufrufe im Code-Body —
diese folgen nur der Zeilenlängenregel (§1.3).

### 5.1  Keine Parameter → einzeilig
```pascal
function AtEnd: Boolean; inline;
```

### 5.2  Ein oder mehr Parameter → IMMER mehrzeilig

**Diese Regel ist absolut.** Auch wenn die gesamte Signatur auf eine Zeile passen würde,
wird sie mehrzeilig formatiert. Die Struktur hat Vorrang vor der Zeilenlänge.

```pascal
// RICHTIG — immer mehrzeilig, auch bei kurzen Signaturen:
constructor Create(
  const aOrm: IRestOrm
  );

function Get(
  aId: TID
  ): TPostDto;

procedure Advance(
  const aCount: Integer = 1
  ); inline;

class function Create(
  const aKind: TTriviaKind;
  const aText: string;
  const aOffset: Integer
  ): TTrivia; static; inline;

// FALSCH — Parameter NIEMALS auf eine Zeile zusammenfassen:
constructor Create(const aOrm: IRestOrm);
function Get(aId: TID): TPostDto;
constructor Create(const aPosts: IPost; const aUsers: IUser;
  const aTags: ITag; const aComments: IComment);
```

Regeln:
- **Jeder** Parameter auf einer **eigenen** Zeile, mit **2 Leerzeichen** eingerückt.
- Die schließende `)` auf einer eigenen Zeile, mit **2 Leerzeichen** eingerückt.
- Rückgabetyp und Direktiven (`static`, `inline`, `override` …) auf der
  `):`-Zeile.
- Auch bei nur **einem** Parameter wird mehrzeilig formatiert.

Gleiche Regel gilt für Implementierungsköpfe:
```pascal
class function TTrivia.Create(
  const aKind: TTriviaKind;
  const aText: string;
  const aOffset: Integer
  ): TTrivia;
begin
  …
end;
```

### 5.3  Funktionsaufrufe im Code-Body

Funktionsaufrufe (nicht Deklarationen) folgen **nur** der Zeilenlängenregel (§1.3).
Parameter werden **nicht** einzeln auf eigene Zeilen verteilt, sondern auf eine Zeile
geschrieben, solange sie unter ~120 Zeichen bleibt:

```pascal
// RICHTIG — Aufruf auf einer Zeile, solange unter ~120 Zeichen:
Table := FOrm.MultiFieldValues(TOrmPostTag, 'TagId', FormatUtf8('PostId=%', [aPostId]));
RegisterService(ObjectFromInterface(FAuth) as TInterfacedObject, TypeInfo(IAuth));
TSynLog.Add.Log(sllInfo, '% starting on port %...', [FServiceName, FPort], self);

// RICHTIG — Aufruf umbrechen, wenn über ~120 Zeichen:
FHttpServer := TRestHttpServer.Create(FPort, FRestServer, FConfig.HttpBind, useHttpAsync, nil,
  FConfig.HttpThreads, SecurityFromString(FConfig.HttpSecurity));

// FALSCH — Aufruf zu früh umbrechen:
Table := FOrm.MultiFieldValues(TOrmPostTag, 'TagId',
  FormatUtf8('PostId=%', [aPostId]));
RegisterService(
  ObjectFromInterface(FAuth) as TInterfacedObject, TypeInfo(IAuth));
```

---

## 6  Einrückung und Formatierung

- **2 Leerzeichen** pro Einrückungsebene (keine Tabs in der Quelle).
- `begin` und `end` stehen immer auf eigenen Zeilen.
- Öffnendes `begin` nach `if`, `for`, `while`, `try` usw. **niemals** auf derselben Zeile
  wie die Bedingung.

### 6.1 Bedingungen

- Wenn ein Zweig einer Bedingung einen `begin ... end`-Block enthält, enthalten auch **alle anderen** einen `begin ... end`-Block.
- nach `then` kommt immer ein Zeilenumbruch
- `else` steht immer auf einer eigenen Zeile

### 6.2 Flow-Elemente

- `break`, `continue`, `Exit(...)` stehen immer auf einer eigenen Zeile

---

## 7  Ausdrücke und Zuweisungen

### 7.1  Mehrzeilige Boole'sche Ausdrücke
Operator **am Anfang** der Fortsetzungszeile, 2 Leerzeichen Einrückung:
```pascal
Result :=
  (Kind >= TTokenKind.KeywordAnd)
  and (Kind <= TTokenKind.KeywordXor);
```

```pascal
Result :=
  IsDecDigit(aChar)
  or (
    (aChar >= 'A')
    and (aChar <= 'F')
    )
  or (
    (aChar >= 'a')
    and (aChar <= 'f')
    );
```

### 7.2  Ausrichtung von Mehrfachzuweisungen
Wenn mehrere aufeinanderfolgende Zuweisungen an verwandte Felder erfolgen,
werden die `:=`-Operatoren **nicht** durch Leerzeichen ausgerichtet:
```pascal
Result.Kind := aKind;
Result.Text := aText;
Result.Offset := aOffset;
Result.LeadingTrivia := aLeading;
Result.TrailingTrivia := aTrailing;
```

---

## 8  `case`-Anweisung

- Jede Fallmarke mit eigenem `begin`/`end`-Block.
- `else`-Zweig auf gleicher Einrückungsebene wie `case` (nicht eingerückt):
```pascal
case Current of
  ' ', #9:
  begin
    TriviaList.Add(ReadWhitespaceTriviaItem);
  end;
  '/':
  begin
    if Peek = '/' then
      TriviaList.Add(ReadLineCommentTriviaItem)
    else
      Break;
  end;
else
  Break;
end;
```

---

## 9  Typdefinitionen

### 9.1  Records
- Immer mit explizitem `public`-Abschnitt.
- Factory-Methode als `class function Create(…): T; static;`.
```pascal
TTrivia = record
public
  Kind:   TTriviaKind;
  Text:   string;
  Offset: Integer;

  class function Create(
    const aKind: TTriviaKind;
    const aText: string;
    const aOffset: Integer
    ): TTrivia; static; inline;
end;
```

### 9.2  Klassen
- `strict private` für alle Implementierungsdetails.
- Standard-Reihenfolge: `strict private` → `private` → `strict protected` → `protected` → `public` → `published`. Diese darf bei Bedarf abweichen, z.B. Sub-Typen-Deklartionen, welche benötigt werden können auch in einem führenden `public` Block aufgeführt werden.
- Klassen-Variablen in `class var`-Block im `strict private`-Abschnitt.
- `class constructor Create` / `class destructor Destroy` für klassenweite
  Initialisierung.
```pascal
TKeywords = class
strict private
  class var
    FMap: TDictionary<string, TTokenKind>;

  class constructor Create;
  class destructor Destroy;
public
  class function TryFind(
    const aText: string;
    out aKind: TTokenKind
    ): Boolean; static;
end;
```

### 9.3  Enumerations
Jeder Enum-Wert auf einer eigenen Zeile mit XML-`<summary>`-Kommentar:
```pascal
TTriviaKind = (
  /// <summary>
  ///   Whitespace on a single line.
  /// </summary>
  Whitespace,

  /// <summary>
  ///   A single end-of-line sequence.
  /// </summary>
  EndOfLine,
  …
);
```

### 9.4  Interfaces
- GUID in eigener Zeile mit `['{…}']`.
- Getter-Methoden (`GetXxx`) im Interface deklariert, Properties über Getter.
```pascal
ICstNode = interface
  ['{3A7B1F2C-84E0-4D6A-9C53-0B2F7E8D1A45}']

  function GetKind: TCstNodeKind;
  …
  property Kind: TCstNodeKind read GetKind;
end;
```

### 9.5  Typ-Aliase
Für häufig verwendete generische Sammlungen werden benannte Aliase angelegt:
```pascal
TTriviaArray = TArray<TTrivia>;
TTokenArray  = TArray<TToken>;
```

## 10  Abschnitt Implementierung

---

### 10.1 Sortierung

Die Methoden und Klassen werden in identischer Reihenfolge implementiert, wie diese im interface-Teil deklariert wurden; **aber** die Methoden einer Klasse werden im implementation-Teil **alphabetisch** sortiert implementiert. Sub-Klassen werden am Ende der überliegenden Klasse definiert, deren Methoden wieder alphabetisch.

---

## 11  Implementierungskommentare

### 11.1  Abschnittstrennlinien
Logische Gruppen von Methoden werden NICHT durch ein Banner getrennt:

### 11.2  Einstiegsbedingungen
Wenn eine Methode eine nicht-triviale Vorbedingung hat, wird sie als erster Kommentar
im Funktionskörper (oder als Zeilenkommentar nach dem `function`-Header in der
Implementierung) notiert:
```pascal
function TLexer.ReadBlockCommentTriviaItem: TTrivia;
// Entry: Current = '{', Peek(1) <> '$'.
// Reads { … } including braces; handles unterminated comments (runs to EOF).
```

### 11.3  Inline-Kommentare
Kurze `// Mein Kommentar`-Kommentare direkt vor dem beschriebenen Aufruf gesetzt:
```pascal
// consume '{'
MethodCall;
```

---

## 12  Moderne Delphi-Features (Delphi 10.3+)

- **Inline-Variablendeklarationen** in `for`-Schleifen und lokal (in Ausnahmen):
  ```pascal
  for var CurrentFilename in aFilenameArray do …
  var ShowDiffStartingAt := Max(1, FirstFailTokenIdx - 20);
  ```
- **Implizite Array-Konstruktoren**: `FilenameArray := [ParamStr(1)];`
- **`TArray<T>`** statt `array of T` für Typdefinitionen.

---

## 13  Projekt-/Konfigurationskonventionen

- **Build-Output**: `..\_out\$(Platform)\$(Config)\DCU` und `..\_out\$(Platform)\$(Config)\APP`
- **Zielplattformen**: Win32 und Win64; Android, iOS etc. werden aus `.dproj` entfernt.
- **Warnungen**: Im `.dpr` und in allen neuen Units nahezu alle Compiler-Warnungen aktiv
  lassen; nur gezielt supprimieren (siehe Abschnitt 1.4).

---

## 14  Checkliste vor Einreichung eines neuen Units

- [ ] UTF-8 BOM vorhanden
- [ ] Unit-Level `/// <summary>` vorhanden
- [ ] `{$SCOPEDENUMS ON}` als erste Direktive
- [ ] Standard-`{$WARN …}`-Suppressions vorhanden
- [ ] Uses alphabetisch sortiert (System.* zuerst)
- [ ] Absolut alle Member mit `/// <summary>` dokumentiert
- [ ] Alle Parameter mit `/// <param name="">` dokumentiert
- [ ] Alle Rückgabewerte mit `/// <returns>` dokumentiert
- [ ] Alle `raise ...` mit `/// <exception ...>` dokumentiert
- [ ] Parameter-Präfix `a` durchgängig eingehalten
- [ ] Feldpräfix `F` für private/class-Felder eingehalten
- [ ] Konstanten in UPPER\_SNAKE\_CASE benannt
- [ ] Keine lokalen Variablen mit `L`-Präfix oder einbuchstabigen Namen
- [ ] Schleifen-Indexvariablen beschreibend (kein `i`, `j`, `k`)
- [ ] Methoden-Deklarationen: jeder Parameter auf eigener Zeile (§5.2), auch bei nur einem Parameter
- [ ] Funktionsaufrufe im Code: auf eine Zeile, solange unter ~120 Zeichen (§5.3)
- [ ] Zeilenlänge: keine Zeile unter 120 Zeichen unnötig umbrochen (§1.3)
- [ ] Zeilenlänge: keine Zeile deutlich über 120 Zeichen (§1.3)
- [ ] Ausrichtung von Mehrfachzuweisungen geprüft
- [ ] Kein Android/iOS-Ballast im `.dproj`
