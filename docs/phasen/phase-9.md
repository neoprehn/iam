# Phase 9 — Anwendung (transportable Docker-App)

Eine **nutzerfreundliche, transportable App**, die den gesamten Ablauf einer Auswertung ohne
JSON-Pflege bedienbar macht — **Import, Auswertung, Ergebnisse, Sichern, Bereinigen**. Sie **baut
auf allem Bestehenden auf** (Runner, Cypher, Profile, `dataset`-Dimension, Findings im Graph);
nichts wird weggeworfen. Bedienbar im Browser unter `http://localhost:8000/`.

:::{admonition} Vertrauensgrenze
:class: important
Nur die Bedienoberfläche ist „außen". **Keine Mandantendaten verlassen** die Umgebung: SAP-Extrakte
(`data/import/`), das DB-Volume und die Backups (`backups/`) bleiben lokal und sind gitignored.
:::

## Laufzeit-Architektur

```
 Browser (http://localhost:8000/)
   │   statische Ribbon-UI (frontend/index.html), vom Backend ausgeliefert
   ▼
 iam-backend  (FastAPI, Port 8000)            ← Runner-as-API, asynchrone Jobs
   │   Import (Ordner/ZIP) · Auswertung · Findings/Export · Backup/Restore · Clear/Reset
   │   orchestriert die cypher-/load-/migrations-Dateien über den Neo4j-Treiber
   ▼
 iam-neo4j  (Neo4j 5 Community + APOC, Bolt 7687 / Browser 7474)
   ├─ Rohschicht je `dataset`  (User/Role/Profile/Authorization/…)
   ├─ konstante Ruleset-Schicht (Query/SoDRule/AuthReq/Clause)
   └─ regenerierbare Findings (:SoDConflict) + (:Run)-Scope/Provenienz
```

Alles **lokal**, alles in **einem Compose**. Das Backend ist als Container **plattformunabhängig**
(portabler als die PowerShell-Runner, die als Host-Variante erhalten bleiben). Es nutzt apoc-**core**;
weil `apoc.cypher.runFile` (apoc-extended) fehlt, werden die `.cypher`-Dateien im Backend in
Einzel-Statements zerlegt und über den Treiber gefahren — `apoc.load.json` darin läuft weiter
server-seitig.

## Oberfläche — Ribbon nach Lebenszyklus

Die Befehle stehen oben in einer **Ribbon-Bar**, gegliedert wie der Ablauf einer Auswertung; jeder
Befehl öffnet einen **Dialog**, der **Hauptbereich** zeigt durchgehend die **Ergebnisse**
(KPIs · Läufe · Findings).

| Gruppe | Befehl | Wirkung |
| --- | --- | --- |
| **1 Daten** | Import | ZIP hochladen **oder** vorhandenen Ordner wählen → Import-Job |
| **2 Auswertung** | Neuer Lauf | Parameter-Formular (statt JSON) → Materialisierung + Auswertung |
| **3 Ergebnisse** | Aktualisieren · Export CSV | Läufe/Findings neu laden · Findings des aktiven Laufs als CSV |
| **4 Sichern** | Backup / Restore | Quelldaten-ZIP erstellen (opt. „Backup & Clear"), wiederherstellen, herunterladen |
| **5 Verwalten** | Bereinigen | Dataset löschen · alles zurücksetzen (Ruleset & Schema bleiben) |

## API-Oberfläche (Runner als Endpunkte)

Lange Schritte laufen als **asynchrone Jobs**; der Fortschritt wird über `GET /jobs/{id}`
(Status/Schritt/Ergebniszähler) angezeigt.

| Endpunkt | Zweck |
| --- | --- |
| `GET /health`, `GET /profiles` | Bereitschaft; Formular-Stammdaten (Rulesets, Profile, Sleeping) |
| `GET /datasets`, `GET /import-folders` | vorhandene Stände; Import-Ordner (txt/csv-Zählung) |
| `POST /imports` `{dataset,…}` | Import eines vorhandenen Ordners (konvertieren→Schema→laden→validieren) |
| `POST /imports/upload` (ZIP) | Import per Datei-Upload (entpacken→ggf. konvertieren→Import) |
| `POST /runs` `{ruleset,dataset,asOf,profile…}` | Materialisierung + Auswertung |
| `GET /runs` | Liste `(:Run)` inkl. Findings-/Regel-/Sleeping-Zahlen |
| `GET /findings?runId=…&minRank=…` | Findings eines Laufs (Tabelle) |
| `GET /findings/export?runId=…` | Findings als **CSV** (Semikolon, UTF-8-BOM → Excel-tauglich) |
| `POST /datasets/{d}/backup` (`?clear=true`) | Quelldaten-Backup (opt. anschließend leeren) |
| `GET /backups`, `GET /backups/{file}/download` | Backups listen / herunterladen |
| `POST /backups/{file}/restore` | Restore = entpacken + Re-Import |
| `POST /datasets/{d}/clear`, `POST /reset` | Dataset leeren / alles zurücksetzen (Ruleset & Schema bleiben) |

## Entwurfsentscheidungen

**Import im Container statt PowerShell.** Der SE16-Konverter (`load/Convert-Se16Export.ps1`) ist nach
Python portiert (`backend/convert.py`) — zeilengleich inkl. Credential-Denylist (Passwort-/Hash-Spalten
werden verworfen), gegen die PS-Version byte-identisch verifiziert. Damit ist der Importpfad
container-transportabel; PowerShell ist nicht mehr nötig.

**Backup/Restore auf Quelldaten-Ebene.** Neo4j Community kann `neo4j-admin dump` nur **offline**
(DBMS-Stopp) — ungeeignet für einen App-Knopf. Stattdessen: Backup = ZIP der konvertierten,
**bereinigten** `.csv` (+ Manifest), Restore = entpacken + **deterministischer Re-Import**. Das ist
**online**, **transportabel** (eine Datei für Kolleg:innen) und trust-aware (nie die rohen `.txt`).
Findings sind regenerierbar (AE-10) und werden nach Restore neu ausgewertet.

**Ergebnisse getrennt von der Quelle.** Das Backup sichert die Quelle (reproduziert den Graphen);
Findings werden als **CSV-Report** exportiert — nicht als Graph-Rückspielung.

**Clear/Reset erhalten Ruleset & Schema.** Beide Operationen löschen nur die dataset-skopierten
Knoten (Dataset-Clear) bzw. alle Daten außer der Ruleset-Schicht und dem Migrations-Tracking
(Reset). So ist direkt danach neu importier- und auswertbar, ohne das Ruleset neu zu laden.
Gebatcht über `apoc.periodic.iterate` (`cypher/admin/`).

## Starten

```bash
docker compose up -d --build          # neo4j + neodash + backend
# Browser: http://localhost:8000/
```

Schema einmalig anlegen (oder über den ersten Import, der es idempotent sicherstellt):

```bash
docker compose run --rm migrations
```

## Status & Offenes

**Umgesetzt (Bau-Schritte 1–4):** Backend-API über die Runner, voller Import im Container inkl.
ZIP-Upload, Ribbon-Oberfläche nach Lebenszyklus, Ergebnisse + CSV-Export, Backup/Restore (inkl.
Backup & Clear, Download), Clear/Reset.

**Offen:** Mandanten-**Vergleich** (zwei `dataset`, Delta), natives **`.xlsx`**, gebrandetes
**NVL/React**-Frontend mit Konfliktpfad-Graph (die NeoDash-Karten-Cypher aus Phase 6 sind die
Vorlage), **Ruleset-Editor** (Vendor-Basis vs. Custom, Round-Trip auf die JSON).

**DoD (Phase 9):** Eine transportable App, in der Import, parametrierte Auswertung, Vergleich,
Anzeige, Export und Backup/Restore ohne JSON-Pflege bedienbar sind — lokal, ohne dass Mandantendaten
die Umgebung verlassen.
