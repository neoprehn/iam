# Phase 9 — Anwendung (transportable Docker-App) · Konzept

Eine **nutzerfreundliche, transportable App** (Docker), die Import, parametrierte Auswertung,
Anzeige, Vergleich, Export und Backup ohne JSON-Pflege bedienbar macht. **Baut auf allem
Bestehenden auf** — nichts wird weggeworfen. Dieses Dokument ist der Plan; gebaut wird danach.

## Architektur

```
[Front-end (Web, React + NVL)]  →  [Backend-Service (Container)]  →  [Neo4j]
   Formulare statt JSON,             Runner-as-API + Jobs:            Daten + Ruleset
   KPIs / Graph / Export,            import, evaluate, findings,      + Findings (+ (:Run))
   System/Vergleich-Wahl             datasets, backup/restore, export
```

Alles **lokal** beim Anwender, alles in **einem Compose**. Vertrauensgrenze bleibt: nur die
Bedienoberfläche ist „außen", **keine Mandantendaten verlassen** die Umgebung. Der Backend-Service
ist als Container **plattformunabhängig** (portabler als die heutigen PowerShell-Runner).

## Was es auf Bestehendem aufsetzt (nichts neu erfinden)

| App-Baustein | Existiert bereits als |
| --- | --- |
| Import-Operation | `run/run_import.ps1` (Schritte konvertieren→migrieren→laden→validieren) |
| Auswerte-Operation | `run/run_evaluate.ps1` + `cypher/sod/*` |
| Parameter „ohne JSON" | `config/analysis_profiles.json` → App-Formulare füllen es |
| „neuer Mandant vs. Vergleich" | `dataset`-Dimension (in jedem Key) |
| Ergebnis-Store | Findings im Graph mit Provenienz; `(:Run)` trägt den Scope |
| Backup/Restore | `neo4j-admin database dump`/`load` (Phase 7) |
| Anzeige-Inhalte | NeoDash-Karten-Cypher (Phase 6) → 1:1 in NVL/React |

## MVP-Schnitt

**Im MVP:**
- Import starten (Dataset wählen/anlegen, Fortschritt sehen).
- Auswertung starten mit **Profil-Formularen** (Ruleset, Stichtag, Nutzertyp inkl. „nicht
  gesperrt", Org-Modus, Sleeping, Scope) — füllt intern die Parameter.
- Findings + KPIs ansehen (Liste, Top-Regeln, Konfliktpfad-Graph), umschaltbar über `(:Run)`.

**Bewusst später:** Excel-Export, Mandanten-**Vergleich**, **Backup/Restore/Clear**, Ruleset-Editor.

## API-Oberfläche (Runner als Endpunkte)

- `POST /imports` `{dataset}` → Job; `GET /imports/{id}` Status.
- `POST /runs` `{ruleset, dataset, asOf, profile…}` → Job (materialize+evaluate); `GET /runs/{id}`.
- `GET /runs` → Liste `(:Run)` (Scope/Provenienz); `GET /findings?runId=…&minRank=…`.
- `GET /datasets` → vorhandene Stände; *(später)* `POST /backups`, `POST /datasets/{d}/clear`,
  `GET /export.xlsx?runId=…`.

Lange Schritte (Materialisierung ~Minuten) laufen als **asynchrone Jobs** mit Status/Fortschritt
(wie der Import). Findings bleiben im Graph — kein separater Ergebnis-Store.

## Technikwahl (Vorschlag)

- **Backend:** Python + FastAPI (passt zu den vorhandenen Konvertern; offizieller Neo4j-Treiber).
  Orchestriert die `cypher/`-Dateien (statt `-P`-Flags → Treiber-Parameter), Jobs via Task-Queue
  oder einfachem Hintergrund-Worker.
- **Frontend:** React; Graph-Visualisierung mit **NVL** (Neo4j Visualization Library).
- **Container:** zwei zusätzliche Compose-Services (`backend`, `frontend`) neben `neo4j`.

## Bau-Reihenfolge

1. **Backend-API über die Runner** (import/evaluate/findings/runs) — die Logik existiert, nur die
   HTTP-Klammer + Jobs fehlen. *(Hier wird aus den PS-Runnern die plattformunabhängige Variante.)*
2. **Minimale UI** (Auswertung starten via Formular → Findings/KPIs sehen).
3. **Schrittweise Features:** Vergleich (zwei `dataset`), Excel-Export, Backup/Restore/Clear,
   Ruleset-Editor (Vendor-Basis vs. Custom, Round-Trip).

## Voraussetzungen aus Phase 7 (fließen direkt ein)

Versionen in `docker-compose.yml` pinnen, `neo4j-admin dump`/`load` als Backup/Restore-Mechanik,
Trust-Boundary-Doku — alles von der App **wiederverwendet**.

**DoD (Phase 9):** Eine transportable App, in der Import, parametrierte Auswertung, Vergleich,
Anzeige, Export und Backup/Restore ohne JSON-Pflege bedienbar sind — lokal, ohne dass
Mandantendaten die Umgebung verlassen.
