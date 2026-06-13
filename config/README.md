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
| `filtered` | je Org-Feld eine Bedingung (`filters`), siehe Operatoren. Nicht gelistete Org-Felder bleiben unbeschränkt. |

## Filter-Operatoren (`filtered`)

| `op` | Bedeutung | Beispiel |
| --- | --- | --- |
| `AND` | Auth muss **alle** `values` abdecken | `BUKRS` = 1000 **und** 2000 |
| `OR` | Auth deckt **mindestens einen** `values` ab | `BUKRS` = 1000 **oder** 4000 |
| `RANGE` | Auth deckt einen Wert im Intervall `[from,to]` ab (ODER über den Bereich) | `BUKRS` 1000–5000 |

## Wichtig

- **Org-Felder** kommen aus **USORG** (54 Felder, z. B. `BUKRS`, `WERKS`, `EKORG`) — kein
  Hardcoding. Ein Feld gilt als org-relevant, wenn sein Name in USORG steht.
- **AE-06-Normalisierung** greift in allen Modi: `*`, Vollbereich (`LOW=' '`/`HIGH='ZZZ…'`) und
  nicht gepflegtes Org-Level werden gleichbehandelt. Ein `*` im Auth-Feld erfüllt damit **jeden**
  Filter (es deckt alles ab) — übergreifende Berechtigungen verbreitern den Treffer.
- Werte im Graphen liegen als `f_<FELD>`-Listen vor (Einzelwerte, `*`, oder `LOW..HIGH`-Bereiche);
  der Phase-3-Evaluator interpretiert sie gegen den Profil-Filter.

## Erweiterung

Neue Profile = weiterer Eintrag in `profiles[]`. Der Evaluator wird gegen diese Struktur
**einmal** gebaut und über den Profilnamen angesteuert (analog `$ruleset`/`$dataset`).
