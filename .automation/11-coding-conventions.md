# 11 — Systemspezifische Konventionen (mORMot2)

## Zweck / Wann brauche ich das

Diese Datei hält ausschließlich die **system- bzw. mORMot2-spezifischen** Konventionen fest,
die unabhängig vom persönlichen Stil in jedem Projekt gelten — weil sie aus dem Framework
oder der Architektur folgen, nicht aus Geschmack.

> **Formatierung und persönlicher Stil gehören NICHT hierher.** Zeilenlänge, Einrückung,
> Methodensignatur-Layout, Benennungsschema, XML-Dokumentationsstil, Datei-Encoding/BOM,
> Compiler-Direktiven-Reihenfolge, Diagramm-Stil usw. variieren von Entwickler zu Entwickler
> und gehören in den jeweiligen **Delphi-Syntax-Styleguide** des Projekts (z. B. eine
> `delphiSyntax.md`). Dieser ist VOR dem Schreiben von Pascal-Code zu öffnen und anzuwenden.

## DTOs als typed records, nie RawJson

Service-Verträge transportieren **typed records**, niemals `RawJson`. Das ist eine bewusste
Architekturentscheidung: typisierte DTOs sind Teil des im `shared/` liegenden Vertrags
zwischen Anbieter und Aufrufer, werden vom mORMot2-Interface-RPC automatisch serialisiert und
sind compilerseitig geprüft.

```pascal
// RICHTIG — typisierter Record als Vertrag
TOrderDto = record
public
  Id:            TID;
  AccountId:     TID;
  CatalogItemId: TID;
  Quantity:      Integer;
  Status:        TOrderStatus;
  CreatedAt:     TDateTime;
end;

// FALSCH — kein RawJson als Service-Vertrag
function GetOrder(aId: TID): RawJson;
```

## Variant-Felder: `VarIsNull` statt `Doc.IsNull`

Für Variant-basierte Dokument-Felder (z. B. `TDocVariant`-Werte) wird auf NULL mit
`VarIsNull(Doc.Value['key'])` geprüft. Eine Methode `Doc.IsNull(...)` existiert in mORMot2
nicht.

```pascal
// RICHTIG
if VarIsNull(Doc.Value['email']) then
  Exit(Default(TAccountDto));

// FALSCH — Doc.IsNull existiert nicht
if Doc.IsNull('email') then
  ...
```

## mORMot2-spezifische Unit-Zuordnungen

Nicht-triviale Symbol-zu-Unit-Zuordnungen, die einen „undeclared identifier"-Compilerfehler
erzeugen, wenn die falsche Unit in der `uses`-Klausel steht:

| Symbol | richtige Unit |
|--------|--------------|
| `IdemPChar` | `mormot.core.unicode` (nicht `mormot.core.base` oder `mormot.core.text`) |
| `SQLITE_MEMORY_DATABASE_NAME` | `mormot.db.core` |
| `TSynTestCase`, `TSynTests` | `mormot.core.test` |
| `TRestServerDB` | `mormot.rest.sqlite3` |
| `FormatUtf8` | `mormot.core.text` |
| `StringToUtf8` | `mormot.core.unicode` |

## 0 Hints / 0 Warnings — verbindliche Projektregel

Jeder Build muss mit **null Hints und null Warnings** abschließen. Keine Warnung ist
„harmlos" — auch `W1000 Symbol X is deprecated` oder `H2164 Variable X is declared but never
used` zählen als zu behebende Befunde, weil sie reale Probleme (veraltete API, toter Code,
unvollständige Initialisierung) verbergen können.

- Ursache beheben statt verstecken: erst der korrekte Fix, dann ggf. eine **gezielte**
  Unterdrückung mit `{$WARN ...}` für nachweislich unkritische Stellen.
- Globales Abschalten (`/W-` o. ä.) ist verboten — es maskiert künftige echte Warnungen.
- Diese Regel ist projektweit verbindlich und unabhängig vom persönlichen Formatierungsstil.

## Stolperfallen / Lessons

- **`IdemPChar` liegt in `mormot.core.unicode`**, nicht in `mormot.core.base` oder
  `mormot.core.text`. Eine fehlende Unit erzeugt einen „undeclared identifier"-Compilerfehler,
  keinen Hint — die `uses`-Klausel sofort ergänzen, wenn `IdemPChar` eingeführt wird.
- **typed records statt RawJson** ziehen sich durch alle Service-Verträge; ein einzelnes
  `RawJson`-Rückgabe-Leck umgeht die Typprüfung und bricht das Vertragsmodell.

## Referenz-Skelett: neue Service-Unit

Das folgende Skelett zeigt, wie die systemspezifischen Muster zusammenspielen: typed-record-
Vertrag, ORM-Zugriff über `IRestOrm`, `VarIsNull`/Default-Rückgaben und die korrekten
mORMot2-Unit-Zuordnungen.

> **Die konkrete Formatierung in diesem Skelett ist NICHT verbindlich** — Einrückung,
> Signatur-Layout, Zeilenumbrüche, Doku-Stil und Benennung folgen dem
> Delphi-Syntax-Styleguide des jeweiligen Projekts. Verbindlich ist nur die hier gezeigte
> **Struktur und Technik** (Interface-Implementierung, typed-record-DTO, ORM-Lebenszyklus,
> Unit-Zuordnungen).

```pascal
unit ms.order.server;

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

  /// Implementiert IOrderService gegen eine IRestOrm-Instanz.
  TOrderService = class(TInterfacedObject, IOrderService)
  strict private
    FOrm: IRestOrm;
  public
    constructor Create(const aOrm: IRestOrm);

    /// Legt eine neue Bestellung an und gibt ihre Datenbankzeilen-ID zurück.
    function CreateOrder(aAccountId: TID; aCatalogItemId: TID; aQuantity: Integer): TID;

    /// Lädt eine Bestellung anhand ihrer ID; leerer Record, wenn nicht gefunden.
    function GetById(aId: TID): TOrderDto;
  end;

implementation

uses
  mormot.core.unicode;

{ TOrderService }

constructor TOrderService.Create(const aOrm: IRestOrm);
begin
  inherited Create;
  FOrm := aOrm;
end;

function TOrderService.CreateOrder(aAccountId: TID; aCatalogItemId: TID; aQuantity: Integer): TID;
var
  NewRow: TOrmOrder;
begin
  if (aAccountId <= 0) or (aCatalogItemId <= 0) or (aQuantity <= 0) then
    Exit(0);
  NewRow := TOrmOrder.Create;
  try
    NewRow.AccountId     := aAccountId;
    NewRow.CatalogItemId := aCatalogItemId;
    NewRow.Quantity      := aQuantity;
    NewRow.Status        := TOrderStatus.Pending;
    Exit(FOrm.Add(NewRow, True));
  finally
    NewRow.Free;
  end;
end;

function TOrderService.GetById(aId: TID): TOrderDto;
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

## Querverweise

- [02-service-erstellen.md](02-service-erstellen.md) — Service-Interface, DTOs und Hosting
- [03-inter-service-kommunikation.md](03-inter-service-kommunikation.md) — DTO-Verträge im `shared/`
- [10-testing.md](10-testing.md) — Exception-Guard-Pattern in Tests
