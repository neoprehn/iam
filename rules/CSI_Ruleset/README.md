# Ruleset `csi` — CSI SoD-Ruleset (ECC/R3)

Normalisierte JSON-Fassung des nativen CSI-tools-Rulesets (Quelle:
`rules/_archive/CSI_Ruleset/CSI_400_Ruleset20191201.xml`, Konverter
`rules/_archive/_convert_csi.py`).

**Gleiches Modell wie [`KPMG_R3`](../KPMG_R3/README.md)** (query-/ausdrucksbasiert) — die
Verknüpfungssemantik (Werte AND/OR per `andLogic`, Felder/Objekte UND, TCodes ODER,
Auth↔TCode UND, `type` = Scope-Filter) gilt identisch und steht in `ruleset.json` →
`combinationSemantics`.

## Dateien

| Datei | Inhalt |
| --- | --- |
| `queries.json` | Queries (Master + Berechtigungen + TCodes); zusätzlich `module`/`subModule`/`disregardTcode` |
| `sod_rules.json` | SoD-Regeln (`expression`, Variablen→Query, **`risks`**-Verweise) |
| `risks.json` | **CSI-nativ:** Risiko-Objekte (`riskLevel`/`riskType`/`riskStatus`) |
| `legends.json` | `queryTypes` (vollständig: AO=Audit-Optional, AR=Audit-Required, …), Sox/GDPR, `sodReasonCodes`, `sodDefinitions` (Ausdrucksvorlagen) |
| `ruleset.json` | Metadaten + `combinationSemantics` + Zähler |

## Unterschiede zu KPMG_R3

- **Echte Risk-Objekte** (`risks.json`) mit Level/Typ/Status, je SoD-Regel verknüpft — seit
  2026-07-15 als Erstbefüllung von `riskType`/`riskLevel`/`riskStatus` im SoD-Editor geladen
  (s. `rules/SCHEMA.md`, ROADMAP 9.4); vorher unbenutzt in der Datei liegend.
- **`disregardTcode`** explizit je Query: ist es `true`, zählt nur der Auth-Teil (TCode-Teil ignoriert).
- **`queryType`** mit vollständiger Legende (CSI nativ; KPMGs Export hatte hier „Undefined").
