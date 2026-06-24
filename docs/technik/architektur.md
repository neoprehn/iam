# Architektur (aktueller Stand)

Diese Seite beschreibt das System **wie es heute gebaut ist**. Wie es dahin kam, steht im
[Entwicklungsverlauf](../index.md) (die Phasen-Seiten).

## Komponenten

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

 iam-neodash (PoC-Anzeige, Port 5005)   ·   iam-migrations (Schema, Profil „tools")
```

Alles **lokal**, alles in **einem Docker-Compose**. Das **Backend** ist als Container
plattformunabhängig und ersetzt die früheren PowerShell-Runner (die als Host-Variante erhalten
bleiben). Es nutzt apoc-**core**; da `apoc.cypher.runFile` (apoc-extended) fehlt, zerlegt das
Backend die `.cypher`-Dateien in Einzel-Statements und fährt sie über den Treiber — `apoc.load.json`
darin läuft weiter server-seitig auf Neo4j.

## Datenschichten im Graphen

| Schicht | Inhalt | Schlüssel/Dimension |
| --- | --- | --- |
| **Rohschicht** | Benutzer, Rollen, Profile, Berechtigungen, Transaktionen, Org-Felder | je **`dataset`** (Systemstand) |
| **Ruleset-Schicht** | Queries (Funktionsbausteine), SoD-Regeln, Berechtigungsbedingungen, CNF-Klauseln | konstant, je **`ruleset`** |
| **Ergebnisschicht** | `(:SoDConflict)`-Findings, `(:Run)` mit Scope/Provenienz | je **`runId`**, regenerierbar |

Die Trennung ist bewusst: die Ergebnisschicht ist **regenerierbar** (wird vor jedem Lauf neu
gerechnet) und nie Eingang der nächsten Ableitung (siehe Architektur-Entscheidung AE-10 in der
ROADMAP). Findings entstehen in zwei Schritten: **Materialisierung** (`(:User)-[:MATCHES]->(:Query)`)
und **Auswertung** (reine Mengenlogik über die CNF-Klauseln der Regeln).

## Endpunkte (Backend)

Lange Schritte laufen als **asynchrone Jobs**; Fortschritt über `GET /jobs/{id}`.

| Endpunkt | Zweck |
| --- | --- |
| `GET /health`, `GET /profiles` | Bereitschaft; Formular-Stammdaten (Rulesets, Profile, Sleeping) |
| `GET /datasets`, `GET /import-folders` | vorhandene Stände; Import-Ordner |
| `POST /imports`, `POST /imports/upload` | Import (vorhandener Ordner / ZIP-Upload) |
| `POST /runs`, `GET /runs` | Auswertung starten; Läufe inkl. Findings-Zahlen |
| `GET /findings`, `GET /findings/export` | Findings (Tabelle / CSV) |
| `POST /datasets/{d}/backup`, `GET /backups`, `…/download`, `…/restore` | Backup/Restore |
| `POST /datasets/{d}/clear`, `POST /reset` | Bereinigen (Ruleset & Schema bleiben) |

## Vertrauensgrenze

Nur die Bedienoberfläche ist „außen". **Keine Mandantendaten** verlassen die Umgebung:
SAP-Extrakte (`data/import/`), das DB-Volume und Backups (`backups/`) bleiben lokal und sind
gitignored; das Repo enthält ausschließlich Logik/Vorgehen. Das Backend bindet diese Verzeichnisse
nur lokal ein.

## Deployment

Verteilungseinheit ist **Docker Compose**. Der Stack ist **Kubernetes-fähig** (interner,
abgesicherter Cluster): Neo4j als `StatefulSet` mit `PVC`, Backend als `Deployment` (vorerst eine
Replica — Jobs liegen in-memory), Passwort als `Secret`, `data/import` + `backups` als `PVC`,
Zugang nur clusterintern bzw. hinter Unternehmens-Auth. Details: Phase 10 in der ROADMAP.
