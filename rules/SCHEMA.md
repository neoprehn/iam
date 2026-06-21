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
- `query` (str, ID) · `description` (Langbezeichnung) · `shortDescription` (Kurzbezeichnung,
  **optional** — bisher in keiner Quelle gepflegt, daher meist leer; UI faellt auf `description`
  zurueck, solange das so ist) · `queryType` (Scope-Filter, **nicht** Operator)
- `soxClassification` (roh) · `criticality` (**normalisiert**) · `criticalityRank` (int 5..1)
- `module` (Prozessbereich, CSI-Vokabular; bei KPMG via CSI-TCode abgeleitet, teils leer)
- `gdprClassification` · `disregardTcode` (bool) · `multipleRun` (bool)
- `authorizations[]`: `{ object, field, andLogic (bool), values (str[]), audit (bool) }`
- `transactions[]`: `{ tcode, audit (bool), stad (bool) }`
- `risk` (str, **optional**) · `controls` (str, **optional**) — Freitext: potenzielles Risiko bzw.
  mitigierende Ma&szlig;nahmen, gepflegt &uuml;ber das Query Management (eigene Tabs); bisher in
  keiner Vendor-Quelle vorhanden, daher zunaechst nur ueber das Overlay (s. u.) befuellt.

**SoD-Regel** (`sod_rules.json[]`):
- `sodRule` (str, ID) · `description` (Langbezeichnung, bei KPMG oft ein ganzer Satz inkl.
  Query-Aufzaehlung) · `shortDescription` (Kurzbezeichnung, **optional**, s.o.) ·
  `expression` (z. B. `"(QA OR QB) AND QC"`)
- `reasonCode` · `variables` (`{ "QA": "<queryId>", … }`, Wert = **str**)
- `criticality` (**normalisiert**) · `criticalityRank` — bei KPMG aus `reasonCode`-Suffix;
  **CSI fuehrt keine native SoD-Schwere** (reasonCode = Template) → `null`.

**Kurz- vs. Langbezeichnung:** In Filtern/Dropdowns wird die **Kurzbezeichnung** angezeigt (kurz
genug, um neben der ID in Klammern lesbar zu bleiben); die Langbezeichnung bleibt das fachliche
Volltext-Feld (z. B. fuer Tooltips/Export). Bis Kurzbezeichnungen gepflegt sind, zeigt die UI
ersatzweise die Langbezeichnung.

**Normalisierte Kritikalitaet (einheitlich, ruleset-uebergreifend):**
`very-high`(5) › `critical`(4) › `high`(3) › `medium`(2) › `low`(1). Damit „Very Critical" o. ae.
ohne ruleset-spezifisches Springen ansprechbar (z. B. `criticalityRank >= 4`).

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
