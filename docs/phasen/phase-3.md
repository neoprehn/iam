# Phase 3 — Auswertungslogik (Checks & SoD)

Einzelberechtigungs-Checks und SoD-Konfliktanalyse auf dem Can-Do-Graphen. Die Rulesets sind
**query-/ausdrucksbasiert** (KPMG/CSI tools): eine **Query** ist ein Funktionsbaustein
(Berechtigungsobjekte + TCodes), eine **SoD-Regel** ein boolescher Ausdruck über Query-Variablen.

## Achsen einer Auswertung

```
SoD-Lauf  =  Ruleset (konstant)  ×  Dataset (System)  ×  Stichtag  ×  Profile (Org / Scope / Nutzertyp / Sleeping)
```

Rulesets sind konstante Referenzdaten (Repo); nur das System (`dataset`) wechselt. Alles
Übrige ist **Parameter** — nichts ist im Cypher fest verdrahtet.

## Ruleset in den Graphen laden

`cypher/ruleset/load_ruleset.cypher` (`-P dir=…`, `-P ruleset=…`) lädt die normalisierte JSON
(`rules/<ruleset>/`) via `apoc.load.json` in die konstante Ruleset-Schicht:
`(:Query)`, `(:Query)-[:REQUIRES]->(:AuthReq)`, `(:SoDRule)`, und die CNF-Klauseln
`(:SoDRule)-[:HAS_CLAUSE]->(:Clause)-[:NEEDS]->(:Query)`. `load/23_org_fields.cypher` lädt aus
USORG die Registry der organisatorischen Felder `(:OrgField)`.

## Einzelberechtigungen (Matching)

`cypher/checks/query_match.cypher` bestimmt, welche User eine Query erfüllen — nach der
`combinationSemantics`: Werte AND/OR je `andLogic`, Felder/Objekte **UND**, TCodes **ODER**
(`*` = beliebig), Auth-Teil **UND** TCode-Teil; `*`/Bereiche `LOW..HIGH` decken ab (AE-06).
Effektive Berechtigungen laufen über Rollen/Profile/Composite/Collective; `ASSIGNED_TO` ist
stichtagsgefiltert. Einfache Checks wie `cypher/checks/sap_all.cypher` sind der Degenerationsfall.

## SoD — Zwei-Schritt über das Zwischenergebnis

Das Teure (Matching gegen Auths) passiert **einmal**, SoD ist danach reine Mengenlogik:

1. **`cypher/sod/materialize_matches.cypher`** — materialisiert das Zwischenergebnis „wer kann
   was": `(:User)-[:MATCHES]->(:Query)` (nur die SoD-relevanten Queries).
2. **`cypher/sod/evaluate_sod.cypher`** — wertet darauf aus: ein User verletzt eine Regel, wenn
   **jede Klausel** (CNF) ≥1 von ihm gematchte Query enthält → `(:SoDConflict)` mit Provenienz
   (`ruleset`, `dataset`, `asOf`, `runId`). **Risiko/Kritikalität stammt aus `(:SoDRule)`** und
   wird nur angehängt — nicht neu bewertet.

## Parameter

| Parameter | Bedeutung | Default / Beispiel |
| --- | --- | --- |
| `ruleset` | konstantes Ruleset | `kpmg_r3` / `csi` / `csi_bi` |
| `dataset` | variables System | Import-Ordnername |
| `asOf` | **Stichtag** (Neo4j-`date`) — Rollen-Gültigkeit **und** Sleeping | **auf das Snapshot-Datum setzen, nicht „heute"** |
| `userTypes` | Nutzertyp-Filter (Subtyp-Labels) | `[]` = alle · `['Dialog','Service']` (A/S) · `['Dialog']` |
| `sleepDays` | Sleeping-Schwelle in Tagen | `180` (frei wählbar) |
| `orgFilters` | Org-BO-Einschränkung je Feld | `{}` = alle „egal" (wie `*`) · `{BUKRS:{op:'OR',values:['1000','4000']}}` |

Benannte Profile dazu in `config/analysis_profiles.json` (Org-Modi, Scope-Selektoren,
Nutzertyp-Profile, Sleeping) — ein Lauf bindet Profile statt einzelne Flags.

### Stichtag — wichtig

Der `asOf` muss zum **Datenstand** passen. Ein Extrakt ist eine Momentaufnahme; mit
`asOf = heute` gegen einen älteren Stand ist z. B. „sleeping" für **alle** wahr (formal korrekt,
aber sinnlos) und befristete Rollen-Zuordnungen werden falsch bewertet. Stichtag = Snapshot-Datum.

### Org-Dimension

- **Default „egal"** (`orgFilters = {}`): Org-Felder schränken nicht ein — „kann der User die
  Funktion überhaupt".
- **`filtered`** (`op` = `AND`/`OR`/`RANGE`): der Auth-Wert des Org-Felds muss den Filter
  abdecken (`*`/Bereiche zählen, AE-06).
- :::{admonition} Offen: Org-Level-Platzhalter
  :class: warning
  Org-pflichtige (abgeleitete) Rollen tragen im Auth-Feld einen **Platzhalter** (`$BUKRS`); die
  echten Werte stehen an der Rolle (`Role.org_$<Feld>` aus AGR_1252). Der Org-Filter prüft derzeit
  nur `f_<Feld>` und löst den Platzhalter **noch nicht** auf — `filtered` ist daher nur für
  literale Org-Werte vollständig. Die Platzhalter-Auflösung ist die nächste Ausbaustufe.
  :::

### Sleeping-Regel

`userSleeping` = keine Anmeldung in `sleepDays` Tagen vor `asOf` (oder nie). Als eigener Check
(`cypher/checks/sleeping_users.cypher`) **und** als Flag an jedem `(:SoDConflict)` — so lassen sich
„aktive vs. schlafende" Konflikte trennen.

## Darstellung

Findings werden materialisiert (`(:SoDConflict)`); **NeoDash** liest und zeigt sie parametrierbar
(KPI-Kacheln, Konflikt-Tabelle mit Drill-down, Graph der Konfliktpfade), Dashboard-JSON nach
`dashboards/`. Siehe Phase 6.

**DoD:** Reproduzierbarer SoD-Lauf zu frei wählbarem Ruleset, Dataset, Stichtag und Profil, mit
vollständiger Nachweiskette (Regel → Klauseln → gematchte Queries → User; Stichtag, Run, Ruleset).
