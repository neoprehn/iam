# Ruleset `kpmg_r3` — KPMG SoD-Ruleset (R/3)

Normalisierte JSON-Fassung des KPMG-Rulesets (Quelle: `rules/_archive/KPMG/*.xlsx`,
Konverter `_convert_kpmg.py`). **Plattform R/3** — noch nicht S/4-tauglich
(Fiori/OData-Ebene, geänderte TCodes/Objekte fehlen).

## Dateien

| Datei | Inhalt |
| --- | --- |
| `queries.json` | 604 **Queries** (Funktionsbausteine): Master + Berechtigungen (Objekt/Feld/Werte/`andLogic`) + Transaktionen |
| `sod_rules.json` | 22 **SoD-Regeln**: boolescher `expression` über Query-Variablen + Variablen→Query-Mapping |
| `legends.json` | Wertelegenden (Sox-Skala, `typeUsage`, Reason-Codes, Ausdrucksvorlagen) |
| `ruleset.json` | Metadaten + `combinationSemantics` (das Auswerte-Modell) |

## Modell

- **Query** = benannte Funktion, definiert über (a) Berechtigungsobjekte (Objekt/Feld/Werte) und/oder
  (b) Transaktionen, plus Klassifizierung (`soxClassification` C/H/M/L/V) und `type` (Scope).
- **SoD-Regel** = boolescher Ausdruck über Query-Variablen (`(QA OR QB) AND (QC OR QD)`), wobei die
  Variablen auf konkrete Queries gemappt sind. `reasonCode` kodiert Prozess+Schwere
  (`SYS_*`/`FR_*`/`OtC_*`/`PtP_*` × `_C`/`_H`/`_V`).

## Verknüpfungssemantik (verbindlich für den Phase-3-Evaluator)

Eine Query matcht einen User, wenn:

| Ebene | Operator |
| --- | --- |
| Werte innerhalb eines Feldes | **AND** wenn `andLogic=true`, sonst **OR** |
| Felder innerhalb eines Objekts | **UND** |
| Objekte innerhalb einer Query | **UND** |
| mehrere TCodes | **ODER** (`tcode = "*"` = beliebig → TCode-Teil trivial erfüllt) |
| Auth-Teil ↔ TCode-Teil | **UND** (passender TCode **und** die Objekt-Berechtigungen; fehlt ein Teil ganz, zählt nur der vorhandene) |

`type` ist **kein** Operator, sondern ein **Scope-Filter**: `JAP` = Jahresabschluss-relevant
(Pflicht), `AO` = optional, `TEST` = Test. Ein Auswertungslauf kann darüber den Umfang steuern
(z. B. nur `JAP`).

**Beispiel `1003_BC-SEC`** („Nummernstand ändern"):
`(SNRO OR SNUM) AND (S_NUMBER.ACTVT = 11 OR 13) AND (S_NUMBER.NROBJ = *)`

## Auswertung gegen den Graphen (Phase 3)

- „darf TCode starten" → User hat über Rolle/Profil eine `S_TCODE`-Berechtigung mit `TCD ⊇ TCode`
  (bzw. `HAS_MENU`/`CHECKS`).
- „Objekt-Berechtigung erfüllt" → `f_<FELD>`-Werte an den Authorizations, mit `*`/Vollbereichs-
  Normalisierung (AE-06) und Pfad-Gültigkeit (AE-08).
- SoD-Finding = `expression` über die Query-Matches eines Users wird wahr.
