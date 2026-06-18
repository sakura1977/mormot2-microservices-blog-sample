# 11 — Coding-Conventions

## Zweck / Wann brauche ich das

Diese Datei destilliert die verbindlichen Delphi/Object-Pascal-Codierungsregeln für
mORMot2-Projekte. Sie gilt für jede neue Zeile Pascal-Code — in Service-Units, in `shared/`
und im Testprojekt. Vollständige Regeln und Checkliste stehen in `.claude/delphiSyntax.md`;
diese Datei fasst die projektkritischen Punkte zusammen und ergänzt mORMot2-spezifische
Lektionen.

> **Vor dem Schreiben von Pascal-Code:** `.claude/delphiSyntax.md` vollständig mit dem
> Read-Tool öffnen und anwenden — jedes Mal, nicht aus dem Gedächtnis.

## Kernkonzept

Konsistenter Stil ist keine Ästhetik-Frage: Falsch formatierte Signaturen erzeugen Merge-
Konflikte, falsche Zeilenlängen verbergen Logikfehler, und nicht-null Hints/Warnings
signalisieren echte Probleme. Alle Regeln gelten ohne Ausnahme.

## Schritt für Schritt

1. Neue Unit anlegen: UTF-8 BOM, `{$SCOPEDENUMS ON}`, Standard-`{$WARN}`-Suppressions.
2. `uses`-Klausel: eine Unit pro Zeile, alphabetisch, System.* zuerst.
3. Signaturen: jeder Parameter auf eigener Zeile (§5.2 delphiSyntax.md).
4. Aufrufe: auf eine Zeile, solange unter 120 Zeichen (§5.3).
5. Rückgaben: `Exit(Value)` durchgängig — kein `Result := x; Exit`.
6. Build auf 0 Hints/0 Warnings bringen — keine einzige ausnahmslos.
7. Checkliste in §14 delphiSyntax.md vor jeder Einreichung abarbeiten.

## Verbindliche Regeln (Kurzreferenz)

### Dateistruktur und Encoding

Jede `.pas`-Datei beginnt mit einem UTF-8 BOM. Erste Compiler-Direktive ist immer
`{$SCOPEDENUMS ON}`, gefolgt von den Standard-Suppressions:

```pascal
{$SCOPEDENUMS ON}

{$WARN SYMBOL_PLATFORM OFF}
{$WARN UNIT_PLATFORM   OFF}
```

Unit-Header vor dem `unit`-Schlüsselwort:

```pascal
﻿/// <summary>
///   Kurzbeschreibung: wichtigste Typen und Zweck dieses Units.
/// </summary>
unit ms.order.server;
```

### Zeilenlänge: 120 Zeichen, weder kürzer noch länger

- Maximal 120 Zeichen — wenige mehr (bis ~125) sind tolerierbar.
- **Nicht zu früh umbrechen.** Code, der unter 120 Zeichen passt, gehört auf eine Zeile.
  Umbrüche bei 60–80 Zeichen sind genauso falsch wie Zeilen mit 150 Zeichen.
- Ausnahme: Methodensignaturen (s. u.) — dort ist Struktur wichtiger als Ausnutzung.

### Methodensignaturen: jeder Parameter auf eigener Zeile (absolut)

Diese Regel gilt ohne Ausnahme, auch wenn die Signatur auf eine Zeile passen würde.

```pascal
// RICHTIG
function CreateOrder(
  aAccountId:    TID;
  aCatalogItemId: TID;
  aQuantity:     Integer
  ): TOrderDto;

constructor Create(
  const aOrm: IRestOrm
  );

// FALSCH — niemals so:
function CreateOrder(aAccountId: TID; aCatalogItemId: TID; aQuantity: Integer): TOrderDto;
constructor Create(const aOrm: IRestOrm);
```

Regeln:
- Jeder Parameter auf einer eigenen Zeile, 2 Leerzeichen eingerückt.
- Schließende `)` auf eigener Zeile, 2 Leerzeichen eingerückt.
- Rückgabetyp und Direktiven auf der `)`-Zeile.
- Gilt für Deklaration **und** Implementierungskopf.

Funktionsaufrufe im Code-Body folgen **nur** der Zeilenlängenregel — keine erzwungenen
Einzelparameter-Zeilen bei Aufrufen.

### Exit-Pattern: `Exit(Value)` überall

```pascal
// RICHTIG
function TOrderService.GetById(
  aId: TID
  ): TOrderDto;
begin
  if aId <= 0 then
    Exit(Default(TOrderDto));
  // …
  Exit(Result);
end;

// FALSCH
Result := Default(TOrderDto);
Exit;
```

`Exit(Value)` ist die einzige erlaubte Form für frühe Rückgaben. `Result := x; Exit` ist
verboten.

### 0 Hints / 0 Warnings — keine Ausnahme

Jeder Build muss mit null Hints und null Warnings abschließen. Keine Warnung ist „harmlos"
— auch `W1000 Symbol X is deprecated` oder `H2164 Variable X is declared but never used`
sind Fehler im Workflow-Sinne. Gezieltes Supprimieren mit `{$WARN ...}` ist erlaubt;
globales `/W-` ist verboten.

### Benennung

| Kategorie | Konvention | Beispiel |
|-----------|-----------|---------|
| Typen, Records, Klassen, Enums | `T` + PascalCase | `TOrderDto`, `TOrderStatus` |
| Interfaces | `I` + PascalCase | `IOrderService` |
| Instanzfelder | `F` + PascalCase | `FOrm`, `FPort` |
| Parameter | `a` + camelCase | `aAccountId`, `aOrm` |
| Lokale Variablen | PascalCase, kein Präfix | `OrderId`, `ResultList` |
| Konstanten | UPPER\_SNAKE\_CASE | `MAX_RETRY_COUNT` |
| Enum-Werte (mit `{$SCOPEDENUMS ON}`) | PascalCase, vollständig qualifiziert | `TOrderStatus.Pending` |

Lokale Variablen niemals einbuchstabig (`i`, `s`) oder mit `L`-Präfix. Schleifen-Index-
variablen beschreibend: `CurrentOrderIdx` statt `i`.

### XML-Dokumentation: alle Member

Alle Typen, Methoden, Properties und Felder erhalten `/// <summary>…</summary>`. Block-Tags
(`<summary>`, `<param>`, `<returns>`, `<exception>`) stehen immer auf eigenen Zeilen:

```pascal
/// <summary>
///   Legt eine neue Bestellung an und gibt ihre ID zurück.
/// </summary>
/// <param name="aAccountId">
///   ID des Accounts, der die Bestellung aufgibt.
/// </param>
/// <param name="aCatalogItemId">
///   ID des Katalogelements.
/// </param>
/// <param name="aQuantity">
///   Bestellmenge; muss größer als 0 sein.
/// </param>
/// <returns>
///   Die neu vergebene Datenbankzeilen-ID der Bestellung.
/// </returns>
/// <exception cref="EServiceError">
///   Wird geworfen, wenn aAccountId oder aCatalogItemId ungültig sind.
/// </exception>
function CreateOrder(
  aAccountId:    TID;
  aCatalogItemId: TID;
  aQuantity:     Integer
  ): TID;
```

### DTOs als typed records, nie RawJson

```pascal
// RICHTIG
TOrderDto = record
public
  Id:            TID;
  AccountId:     TID;
  CatalogItemId: TID;
  Quantity:      Integer;
  Status:        TOrderStatus;
  CreatedAt:     TDateTime;
end;

// FALSCH
function GetOrder(aId: TID): RawJson;
```

Für Variant-basierte Dokument-Felder: `VarIsNull(Doc.Value['key'])` — nicht `Doc.IsNull`.

### mORMot2-spezifische Unit-Zuordnungen

Nicht-triviale Funktion/Typ-Zuordnungen, die Fehler verursachen wenn die falsche Unit
in der `uses`-Klausel steht:

| Symbol | richtige Unit |
|--------|--------------|
| `IdemPChar` | `mormot.core.unicode` (nicht `mormot.core.base` oder `mormot.core.text`) |
| `SQLITE_MEMORY_DATABASE_NAME` | `mormot.db.core` |
| `TSynTestCase`, `TSynTests` | `mormot.core.test` |
| `TRestServerDB` | `mormot.rest.sqlite3` |
| `FormatUtf8` | `mormot.core.text` |
| `StringToUtf8` | `mormot.core.unicode` |

### Diagramme: ausschließlich mermaid

Kein ASCII-Art für Diagramme. Jedes Architektur-, Ablauf- oder Sequenzdiagramm in
Dokumentationsdateien wird als mermaid-Codeblock geschrieben:

```
```mermaid
graph TD
    A --> B
```
```

ASCII-Art-Diagramme sind verboten, auch als „schnelle Skizze".

## Code-Skelett: neue Service-Unit

Vollständiges Skelett für eine `ms.<name>.server.pas`:

```pascal
﻿/// <summary>
///   Implementierung von I<Name>Service: <kurze Beschreibung>.
/// </summary>
unit ms.order.server;

{$SCOPEDENUMS ON}

{$WARN SYMBOL_PLATFORM OFF}
{$WARN UNIT_PLATFORM   OFF}

interface

uses
  mormot.core.base,
  mormot.core.interfaces,
  mormot.core.text,
  mormot.orm.core,
  mormot.soa.core,
  ms.shared.api,
  ms.order.model;

type

  /// <summary>
  ///   Implementiert IOrderService gegen eine IRestOrm-Instanz.
  /// </summary>
  TOrderService = class(TInterfacedObject, IOrderService)
  strict private
    FOrm: IRestOrm;

  public

    /// <summary>
    ///   Erstellt den Service mit dem übergebenen ORM-Interface.
    /// </summary>
    /// <param name="aOrm">
    ///   ORM-Interface des TRestServer.
    /// </param>
    constructor Create(
      const aOrm: IRestOrm
      );

    /// <summary>
    ///   Legt eine neue Bestellung an.
    /// </summary>
    /// <param name="aAccountId">
    ///   Aufgebender Account.
    /// </param>
    /// <param name="aCatalogItemId">
    ///   Bestelltes Katalogelement.
    /// </param>
    /// <param name="aQuantity">
    ///   Bestellmenge, muss größer 0 sein.
    /// </param>
    /// <returns>
    ///   Neue Datenbankzeilen-ID.
    /// </returns>
    function CreateOrder(
      aAccountId:    TID;
      aCatalogItemId: TID;
      aQuantity:     Integer
      ): TID;

    /// <summary>
    ///   Lädt eine Bestellung anhand ihrer ID.
    /// </summary>
    /// <param name="aId">
    ///   Datenbankzeilen-ID.
    /// </param>
    /// <returns>
    ///   DTO mit den Bestelldaten; leerer Record wenn nicht gefunden.
    /// </returns>
    function GetById(
      aId: TID
      ): TOrderDto;
  end;

implementation

uses
  mormot.core.unicode;

{ TOrderService }

constructor TOrderService.Create(
  const aOrm: IRestOrm
  );
begin
  inherited Create;
  FOrm := aOrm;
end;

function TOrderService.CreateOrder(
  aAccountId:    TID;
  aCatalogItemId: TID;
  aQuantity:     Integer
  ): TID;
var
  NewRow: TOrmOrder;
begin
  if (aAccountId <= 0) or (aCatalogItemId <= 0) or (aQuantity <= 0) then
    Exit(0);
  NewRow := TOrmOrder.Create;
  try
    NewRow.AccountId    := aAccountId;
    NewRow.CatalogItemId := aCatalogItemId;
    NewRow.Quantity     := aQuantity;
    NewRow.Status       := TOrderStatus.Pending;
    Exit(FOrm.Add(NewRow, True));
  finally
    NewRow.Free;
  end;
end;

function TOrderService.GetById(
  aId: TID
  ): TOrderDto;
var
  Row: TOrmOrder;
begin
  if aId <= 0 then
    Exit(Default(TOrderDto));
  Row := TOrmOrder.Create(FOrm, aId);
  try
    if Row.IDValue = 0 then
      Exit(Default(TOrderDto));
    Result.Id            := Row.IDValue;
    Result.AccountId     := Row.AccountId;
    Result.CatalogItemId := Row.CatalogItemId;
    Result.Quantity      := Row.Quantity;
    Result.Status        := Row.Status;
    Result.CreatedAt     := Row.CreatedAt;
    Exit(Result);
  finally
    Row.Free;
  end;
end;

end.
```

## Checkliste vor Einreichung (Kurzform)

Vollständige Checkliste in `.claude/delphiSyntax.md` §14. Mindestens zu prüfen:

- [ ] UTF-8 BOM vorhanden
- [ ] `{$SCOPEDENUMS ON}` als erste Direktive
- [ ] Alle Member mit `/// <summary>` dokumentiert, alle Parameter mit `/// <param>`
- [ ] Methodensignaturen: jeder Parameter auf eigener Zeile (auch bei einem Parameter)
- [ ] Funktionsaufrufe im Body: auf eine Zeile, solange unter 120 Zeichen
- [ ] Keine Zeile unnötig unter 120 Zeichen umbrochen
- [ ] Keine Zeile deutlich über 120 Zeichen
- [ ] `Exit(Value)` durchgängig — kein `Result := x; Exit`
- [ ] Keine lokalen Variablen mit `L`-Präfix oder einbuchstabig
- [ ] Schleifen-Indexvariablen beschreibend (kein `i`, `j`, `k`)
- [ ] Build: 0 Hints, 0 Warnings

## Stolperfallen / Lessons

- **Zeilenlänge ist eine Zwei-Seiten-Regel.** Die häufigste Verletzung ist zu frühes
  Umbrechen (bei 60–80 Zeichen), nicht zu lange Zeilen. Beide Seiten sind Fehler.
- **`IdemPChar` liegt in `mormot.core.unicode`**, nicht in `mormot.core.base` oder
  `mormot.core.text`. Fehlende Unit erzeugt einen „undeclared identifier"-Compilerfehler,
  keinen Hint — sofort hinzufügen wenn `IdemPChar` eingeführt wird.
- **Enum-Werte immer vollständig qualifizieren**, auch wenn `{$SCOPEDENUMS ON}` aktiv ist:
  `TOrderStatus.Pending`, nicht `Pending`.
- **Kein Nachbarcode als Vorlage kopieren** — Nachbarcode kann selbst regelwidrig sein.
  Immer delphiSyntax.md öffnen.

## Querverweise

- [01-projektstruktur.md](01-projektstruktur.md) — wo Units hingehören
- [02-service-erstellen.md](02-service-erstellen.md) — vollständiges Service-Skelett
- [10-testing.md](10-testing.md) — Exception-Guard-Pattern in Tests
