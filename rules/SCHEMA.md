# Ruleset-Schema (Kontrakt für den Phase-3-Loader)

Alle Rulesets unter `rules/<ruleset>/` liefern dieselbe **Kern-Datenstruktur**, damit **ein**
Loader/Evaluator (parametrisiert über `$ruleset`) alle verarbeitet — unabhängig von der Quelle
(KPMG-Excel, CSI-XML). Quellen + Konverter liegen unter `rules/_archive/`.

Aktuelle Rulesets: `kpmg_r3` (R/3), `csi` (ECC/R3), `csi_bi` (BI/BW).

## Dateien je Ruleset

| Datei | Pflicht | Inhalt |
| --- | --- | --- |
| `queries.json` | ja | Liste Queries (Funktionsbausteine) |
| `sod_rules.json` | ja | Liste SoD-Regeln (boolescher Ausdruck über Query-Variablen) |
| `ruleset.json` | ja | Metadaten + `combinationSemantics` |
| `legends.json` | ja | Wertelegenden (queryTypes, Klassifizierung, Reason-Codes …) |
| `risks.json` | optional | nur wo vorhanden (CSI): Risiko-Objekte |

## Kern-Felder (über ALLE Rulesets identisch — der Loader baut hierauf)

**Query** (`queries.json[]`):
- `query` (str, ID) · `description` · `queryType` (Scope-Filter, **nicht** Operator)
- `soxClassification` · `gdprClassification` · `disregardTcode` (bool) · `multipleRun` (bool)
- `authorizations[]`: `{ object, field, andLogic (bool), values (str[]), audit (bool) }`
- `transactions[]`: `{ tcode, audit (bool), stad (bool) }`

**SoD-Regel** (`sod_rules.json[]`):
- `sodRule` (str, ID) · `description` · `expression` (z. B. `"(QA OR QB) AND QC"`)
- `reasonCode` · `variables` (`{ "QA": "<queryId>", … }`, Wert = **str**)

## Optionale Extras (ruleset-spezifisch — Loader ignoriert oder übernimmt generisch)

- KPMG_R3 — Query: `sortOrder`, `useNaming`, `auditSave`; SoD: `definition`, `definitionDescription`
- CSI — Query: `module`, `subModule`, `riskText`; SoD: `comment`, `multipleRun`, `risks[]` (Risk-Namen → `risks.json`)

## Verknüpfungssemantik

Steht je Ruleset in `ruleset.json → combinationSemantics` und ist für alle identisch:
Werte **AND/OR** per `andLogic` · Felder eines Objekts **UND** · Objekte einer Query **UND** ·
TCodes **ODER** (`*` = beliebig) · Auth-Teil ↔ TCode-Teil **UND** (bzw. nur Auth bei
`disregardTcode=true`). `queryType` ist **Scope-Filter** (welche Queries laufen).

## Bewusst NICHT im Ruleset (kommt aus dem Graphen)

TCode- und Objekt-**Bezeichnungen** (Graph: `Transaction.text`/`AuthObject.text`). Die Auswertung
matcht auf IDs (`tcode`, `object`, `field`), nicht auf Texte.
