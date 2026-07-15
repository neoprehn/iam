# Ruleset-Schema (Kontrakt für den Phase-3-Loader)

Alle Rulesets unter `rules/<ruleset>/` liefern dieselbe **Kern-Datenstruktur**, damit **ein**
Loader/Evaluator (parametrisiert über `$ruleset`) alle verarbeitet — unabhängig von der Quelle
(KPMG-Excel, CSI-XML). Quellen + Konverter liegen unter `rules/_archive/`.

Aktuelle Rulesets: `kpmg_r3` (R/3), `csi` (ECC/R3), `csi_bi` (BI/BW).

## Dateien je Ruleset

| Datei | Pflicht | Inhalt |
| --- | --- | --- |
| `queries.json` | ja | Liste Queries (Funktionsbausteine) |
| `queries.custom.json` | optional | Overlay: eigene Metadaten-Edits/abgeleitete Queries (Query Management) |
| `sod_rules.json` | ja | Liste SoD-Regeln (boolescher Ausdruck über Query-Variablen) |
| `sod_rules.custom.json` | optional | Overlay: eigene Metadaten-Edits an SoD-Regeln (Query Management, Modus „SoD") |
| `ruleset.json` | ja | Metadaten + `combinationSemantics` |
| `legends.json` | ja | Wertelegenden (queryTypes, Klassifizierung, Reason-Codes …) |
| `risks.json` | optional | bei allen drei Rulesets vorhanden: Risiko-Objekte, **eine gemeinsame Datei für SoD- UND Query-Risiken** (Nutzerentscheid 2026-07-15 — keine getrennten Dateien). Jeder Eintrag trägt entweder `alias` (verknüpft mit `sodRule`) **oder** `query` (verknüpft mit `query`-ID), nie beides. Felder: `riskType`/`riskLevel`/`riskStatus` sowie `risk` (Kurztitel) sowie optional `description` (Langtext) — bei der Erstbefüllung werden `risk`+`description` zu **einem** Freitext-Wert kombiniert (`"<risk>: <description>"`, Nutzerentscheid: nichts verwerfen) und füllen das gleichnamige `risk`-Feld der Query/SoD-Regel; `riskType`/`riskLevel`/`riskStatus` je 1:1. Overlay-Edit (`queries.custom.json`/`sod_rules.custom.json`) gewinnt danach immer, kein erzwungener Reset bei Re-Import. Bei CSI/CSI_BI historisch 440 SoD-Einträge mit echtem, differenziertem `risk`/`description`-Inhalt (CSI-nativ); alle Query-Einträge sowie KPMG_R3s SoD-Einträge aktuell nur als leeres Template (`riskType`/`riskStatus`/`risk`/`description` = `null`) angelegt — inhaltliche Befüllung steht noch aus (s. ROADMAP 9.4). KPMG_R3s Query-Einträge tragen bereits einen `riskLevel`-Startwert aus der vorhandenen `criticality` |

## Kern-Felder (über ALLE Rulesets identisch — der Loader baut hierauf)

**Query** (`queries.json[]`):
- `query` (str, ID) · `description` (Langbezeichnung) · `shortDescription` (Kurzbezeichnung,
  **optional** — bisher in keiner Quelle gepflegt, daher meist leer; UI faellt auf `description`
  zurueck, solange das so ist) · `queryType` (Scope-Filter, **nicht** Operator)
- `soxClassification` (roh) · `criticality` (**normalisiert**) · `criticalityRank` (int 5..1)
- `module` (Prozessbereich, CSI-Vokabular; bei KPMG via CSI-TCode abgeleitet, teils leer)
- `gdprClassification` (roh, L/M/H/C/V) · `datenschutz` (**normalisiert wie `criticality`**, aus
  `gdprClassification` abgeleitet sofern nicht per Overlay gesetzt; bisher nur bei CSI/CSI_BI
  gepflegt, bei KPMG_R3 durchgehend leer) · `disregardTcode` (bool) · `multipleRun` (bool)
- `authorizations[]`: `{ object, field, andLogic (bool), values (str[]), audit (bool) }`
- `transactions[]`: `{ tcode, audit (bool), stad (bool) }`
- `risk` (str, **optional**) · `controls` (str, **optional**) — Freitext: potenzielles Risiko bzw.
  mitigierende Ma&szlig;nahmen, gepflegt &uuml;ber das Query Management (eigene Tabs). `risk`
  zusätzlich aus `risks.json` initial befüllt (s. Dateitabelle oben), sofern noch nicht per Overlay
  gesetzt; `controls` weiterhin ohne Vendor-/Seed-Quelle, nur über das Overlay befüllt.
- `riskType`/`riskLevel`/`riskStatus` (str, **optional**, feste Wertelisten; `riskLevel` seit
  2026-07-15 auf dieselbe Konvention wie `criticality` umgestellt: `very-critical/critical/high/
  medium/low`) — eigene Dimension neben `risk`/`controls`: deckt ein Control das inhärente Risiko
  ausreichend ab? Zusätzlich aus `risks.json` initial befüllt (s. Dateitabelle oben), Overlay-Edit
  gewinnt danach immer. Dropdown im „Risiko"-Tab.

**SoD-Regel** (`sod_rules.json[]`):
- `sodRule` (str, ID) · `description` (Langbezeichnung, bei KPMG oft ein ganzer Satz inkl.
  Query-Aufzaehlung) · `shortDescription` (Kurzbezeichnung, **optional**, s.o.) ·
  `expression` (z. B. `"(QA OR QB) AND QC"`)
- `reasonCode` · `variables` (`{ "QA": "<queryId>", … }`, Wert = **str**)
- `criticality` (**normalisiert**) · `criticalityRank` — bei KPMG aus `reasonCode`-Suffix;
  **CSI fuehrt keine native SoD-Schwere** (reasonCode = Template) → `null`.
- `risk` (str, **optional**) · `controls` (str, **optional**) — analog zu Query, gepflegt &uuml;ber
  das Query Management (Modus „SoD", eigene Tabs). `risk` analog zu Query zusätzlich initial aus
  `risks.json` befüllt (bei CSI/CSI_BI 440 Einträge mit echtem, historisch gewachsenem Inhalt).
- `riskType`/`riskLevel`/`riskStatus` (str, **optional**, feste Wertelisten) — analog zu Query,
  ebenfalls initial aus `risks.json` befüllt (s. Dateitabelle oben), Overlay-Edit gewinnt danach
  immer.

**Overlay (`sod_rules.custom.json`, optional, analog zu `queries.custom.json`):** Metadaten-Edits
an bestehenden Vendor-Regeln (Kurzbezeichnung/Kritikalit&auml;t/Risiko/Controls) &uuml;ber das Query
Management — Vendor-Datei (`sod_rules.json`) bleibt unber&uuml;hrt. **Keine** Struktur-Edits
(`clauses`/`variables`) in v1 — neue/abgeleitete SoD-Regeln sind (anders als bei Queries) noch
nicht &uuml;ber die UI anlegbar.

**Kurz- vs. Langbezeichnung:** In Filtern/Dropdowns wird die **Kurzbezeichnung** angezeigt (kurz
genug, um neben der ID in Klammern lesbar zu bleiben); die Langbezeichnung bleibt das fachliche
Volltext-Feld (z. B. fuer Tooltips/Export). Bis Kurzbezeichnungen gepflegt sind, zeigt die UI
ersatzweise die Langbezeichnung.

**Normalisierte Kritikalitaet (einheitlich, ruleset-uebergreifend):**
`very-critical`(5) › `critical`(4) › `high`(3) › `medium`(2) › `low`(1). Damit „Very Critical" o. ae.
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
