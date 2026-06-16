# Phase 5 — Runner & Orchestrierung

Zwei PowerShell-Runner bündeln die manuellen `cypher-shell`-Aufrufe zu wenigen Befehlen —
einer für den **Import**, einer für die **Auswertung**. Container-only über den laufenden
`iam-neo4j`; das Passwort kommt aus `.env`, nie als Klartext ins Skript.

## `run/run_import.ps1` — SE16-Export → Graph

```powershell
.\run\run_import.ps1 -Dataset <name> [-Lang DE,DEU,D] [-SkipConvert]
```

Schritte: **konvertieren** (`Convert-Se16Export.ps1` inkl. Minimalset-Prüfung +
Credential-Denylist) → **migrieren** (`docker compose run --rm migrations`) → alle
`load/*.cypher` in Reihenfolge mit `-P dataset` / `-P lang` → `99_validate`. Erwartet den
Export unter `data/import/<Dataset>/`. Jeder Schritt wird über `$LASTEXITCODE` geprüft.

## `run/run_evaluate.ps1` — Ruleset → Findings

```powershell
.\run\run_evaluate.ps1 -Ruleset kpmg_r3 -Dataset <name> -AsOf 2023-12-31 `
    [-UserTypeProfile dialog-service] [-OrgProfile standard] `
    [-SleepDays 180] [-MinCriticalityRank 5] [-SodRules @('BCX_0001')] `
    [-SkipRulesetLoad] [-SkipMaterialize]
```

Schritte: **Ruleset laden** (`cypher/ruleset/load_ruleset.cypher`) → **materialisieren**
(`cypher/sod/materialize_matches.cypher`) → **SoD auswerten** (`cypher/sod/evaluate_sod.cypher`).
Die **Profile** (`-UserTypeProfile`, `-OrgProfile`, Sleeping, Scope) werden aus
`config/analysis_profiles.json` **aufgelöst** und als `-P`-Cypher-Literale übergeben — der
Nutzer pflegt **kein** JSON von Hand. Am Ende: Zusammenfassung (Findings / Regeln / sleeping).

:::{important} Stichtag (`-AsOf`)
Muss zum **Datenstand** passen (Snapshot-Datum, nicht „heute") — er steuert Rollen-Gültigkeit
**und** die Sleeping-Bewertung. Siehe [Phase 3](phase-3.md).
:::

## Verhältnis zur App (Phase 9)

Die Runner sind zugleich die **Backend-Operationen** der späteren transportablen App: dort
werden sie als API/Jobs aufgerufen, das Frontend liefert die Parameter (statt der `-P`-Flags).

## PowerShell-Hinweise

- `$ErrorActionPreference = 'Continue'` + explizite `$LASTEXITCODE`-Prüfung (native Tools wie
  `docker compose` schreiben Fortschritt auf stderr — unter `'Stop'` würde PS 5.1 das fälschlich
  fatal werten).
- Zusammenfassungs-Query als **Argument** an `cypher-shell` (nicht per stdin-Pipe — sonst BOM).

**DoD:** Frischer Lauf auf einem zweiten Rechner liefert identische Ergebnisse (gleiche Daten
vorausgesetzt).
