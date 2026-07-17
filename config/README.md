# Konfiguration

Dieser Ordner bündelt zentrale, versionierte Steuerdateien:

- **`required_tables.json`** — Minimalset (`required`) + Anreicherung (`optional`) der erwarteten
  SE16-Tabellen. Zentrale Quelle für den Konverter (`load/Convert-Se16Export.ps1` prüft das
  Minimalset vor der Umwandlung) und den künftigen Runner. Tabellennamen = `.txt`-Basisnamen.
- **`analysis_profiles.json`** — Auswertungs-Profile (Org-Modi/Filter), siehe unten.

---

# Auswertungs-Profile (`analysis_profiles.json`)

Die **dritte Achse** der SoD-Auswertung neben dem konstanten **Ruleset** und dem variablen
**Dataset**: ein benanntes **Profil** steuert, wie die Auswertung läuft — vor allem die
**Org-Dimension**.

```
SoD-Lauf  =  Ruleset (konstant)  ×  Dataset (variabel)  ×  Profil (diese Datei)  ×  Stichtag
```

`ruleset`/Profil sind konstant und versioniert; `dataset`, `asOf` (Stichtag) und `runId`
werden **zur Laufzeit** gebunden (das System wechselt, das Ruleset bleibt).

## Org-Modi

| `org.mode` | Bedeutung |
| --- | --- |
| `ignoreOrg` | **Standard** — Org-Felder unbeschränkt. „Kann der User die Funktion überhaupt?" |
| `wildcardOnly` | nur **übergreifende** Berechtigungen — Org-Feld trägt echtes `*`/Vollbereich (AE-06). |
| `filtered` | je Org-Feld ein 2-Ebenen-Kriterienbaum (`filters`), siehe unten. Nicht gelistete Org-Felder bleiben unbeschränkt. |

## Filter-Kriterienbaum (`filtered`, ROADMAP 9.3)

Je Org-Feld ein Baum mit **maximal 2 Ebenen**: `{op:'AND'|'OR', children:[...]}` auf Top-Level —
ein Kind ist entweder ein **Leaf** oder eine **Gruppe** (die selbst wieder nur Leafs enthält, keine
Gruppe-in-Gruppe). Damit sind Ausdrücke wie **„(1000 UND 2000) ODER 3000"** je Feld möglich.

| Knotentyp | Form | Bedeutung |
| --- | --- | --- |
| Leaf „Wert" | `{type:'value', value}` | Auth deckt genau diesen Wert ab. |
| Leaf „Bereich" | `{type:'range', from, to}` | Auth deckt einen Wert im Intervall `[from,to]` ab (ODER über den Bereich). |
| Gruppe | `{type:'group', op:'AND'\|'OR', children:[Leaf,...]}` | Kombinator über ihre eigenen Leafs. |

Top-Level-`op` kombiniert seine `children` (Leafs und/oder Gruppen gemischt) mit `AND` (alle
müssen erfüllt sein) oder `OR` (mindestens eines). Beispiel „(1000 UND 2000) ODER 3000":

```json
{ "op": "OR", "children": [
  { "type": "group", "op": "AND", "children": [
    { "type": "value", "value": "1000" }, { "type": "value", "value": "2000" }
  ] },
  { "type": "value", "value": "3000" }
] }
```

Ältere Profile im flachen Format (`{op:'AND'|'OR', values:[...]}` bzw. `{op:'RANGE', from, to}`)
werden beim Lesen automatisch in diese Baumform übersetzt (`backend/app.py:_normalize_org_filter()`),
nie auf Platte zurückgeschrieben — bestehende Profile brechen dadurch nicht.

## Wichtig

- **Org-Felder** kommen aus **USORG** (54 Felder, z. B. `BUKRS`, `WERKS`, `EKORG`) — kein
  Hardcoding. Ein Feld gilt als org-relevant, wenn sein Name in USORG steht.
- **AE-06-Normalisierung** greift in allen Modi: `*`, Vollbereich (`LOW=' '`/`HIGH='ZZZ…'`) und
  nicht gepflegtes Org-Level werden gleichbehandelt. Ein `*` im Auth-Feld erfüllt damit **jeden**
  Filter (es deckt alles ab) — übergreifende Berechtigungen verbreitern den Treffer.
- Werte im Graphen liegen als `f_<FELD>`-Listen vor (Einzelwerte, `*`, oder `LOW..HIGH`-Bereiche);
  der Phase-3-Evaluator interpretiert sie gegen den Profil-Filter.

## Weitere Auswertungs-Parameter

Neben Org (`profiles`) und Scope (`scopeProfiles`) steuern zwei weitere Achsen die Auswertung —
ebenfalls Parameter, nicht im Cypher verdrahtet:

- **`userTypeProfiles`** → `$userTypes` (Subtyp-Labels): `[]` = alle · `['Dialog','Service']` (A/S)
  · `['Dialog']`. Damit z. B. „SoD nur für anmeldefähige Personen" vs. „alle".
- **`sleeping.sleepDays`** → `$sleepDays`: Tage ohne Anmeldung (bezogen auf `asOf`) → `userSleeping`.
  Default 180, frei wählbar. **Stichtag muss zum Datenstand passen** (Snapshot, nicht „heute").

Der vollständige Parametersatz (`ruleset`, `dataset`, `asOf`, `userTypes`, `sleepDays`,
`orgFilters`) steht in `_runParameters`; Details siehe `docs/phasen/phase-3.md`.

> **Org-Filter-Hinweis:** `orgFilters` deckt literale Org-Werte ab. Org-pflichtige (abgeleitete)
> Rollen tragen Platzhalter (`$BUKRS`); deren Auflösung über AGR_1252 (`Role.org_$<Feld>`) ist
> noch offen — bis dahin ist `filtered` nur für literale Werte vollständig.

## Erweiterung

Neue Profile = weiterer Eintrag in `profiles[]`/`scopeProfiles[]`/`userTypeProfiles[]`. Der
Evaluator wird gegen diese Struktur **einmal** gebaut und über den Profilnamen angesteuert.
