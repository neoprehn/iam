# IAM — SAP-Berechtigungsanalyse mit Neo4j

[![Documentation Status](https://readthedocs.org/projects/iam-iam/badge/?version=latest)](https://iam-iam.readthedocs.io/de/latest/)

📖 **Doku:** <https://iam-iam.readthedocs.io/de/latest/>

Graphbasierte Auswertung von SAP-Berechtigungen (R/3 und S/4HANA): Can-Do (Berechtigung)
und Did-Do (Nutzung), inklusive SoD-Konfliktanalyse. Die Auswertung läuft **container-only**
über Docker Desktop/WSL2 — keine lokale Neo4j- oder Java-Installation nötig.

Der vollständige Fahrplan steht in [ROADMAP.md](ROADMAP.md). Leitprinzip: **Logik und Daten
sind getrennt.** Das Repo enthält nur Logik, Umgebung und Darstellung — niemals Mandantendaten.
SAP-Extrakte und das DB-Volume liegen lokal unter `data/` und sind gitignored.

## Quickstart

Voraussetzung: Docker Desktop mit WSL2-Backend (siehe „Windows-Spezifika" in der ROADMAP).

```powershell
# 1. Repo klonen
git clone https://github.com/neoprehn/iam.git
cd iam

# 2. Zugangsdaten anlegen (lokal, gitignored) und Passwort setzen (min. 8 Zeichen)
Copy-Item .env.example .env
notepad .env

# 3. Umgebung starten (erster Start zieht Images + APOC, baut das Backend)
docker compose up -d --build

# 4. Schema einmalig anlegen (idempotent; der erste Import stellt es auch sicher)
docker compose run --rm migrations

# 5. App öffnen
#    Web-App (Import/Auswertung/Ergebnisse/Sichern/Verwalten) : http://localhost:8000/
#    Neo4j Browser : http://localhost:7474   ·   NeoDash : http://localhost:5005
```

## Bedienung über die App (empfohlen)

Die **Web-App** unter <http://localhost:8000/> deckt den ganzen Lebenszyklus ohne JSON-Pflege ab
— gegliedert in einer Ribbon-Bar: **Daten** (Import per ZIP-Upload oder Ordner) → **Auswertung**
(SoD-Lauf mit Parameter-Formular) → **Ergebnisse** (KPIs, Findings, CSV-Export) → **Sichern**
(Backup/Restore der Quelldaten) → **Verwalten** (Clear/Reset). Das Backend (`iam-backend`)
orchestriert die vorhandenen Cypher-/Load-Skripte als asynchrone Jobs — plattformunabhängig im
Container, ohne lokales PowerShell. Details: [docs/phasen/phase-9](docs/phasen/phase-9.md).

SAP-Extrakte gehören lokal nach `data/import/<dataset>/` (oder per ZIP-Upload in der App) und
verlassen die Umgebung nie. Die alternativen Host-Runner `run/run_import.ps1` /
`run/run_evaluate.ps1` bleiben für PowerShell-Nutzung erhalten.

## Repo-Struktur

```
iam/
├─ docker-compose.yml   # neo4j + neodash + backend (+ migrations als tools-Profil), gepinnt, APOC
├─ docker/              # Dockerfile(s), z. B. neo4j-migrations-CLI (gepinnt)
├─ backend/            # FastAPI-App (app.py) + SE16-Konverter (convert.py), Dockerfile
├─ frontend/           # statische Ribbon-UI (index.html), vom Backend ausgeliefert
├─ config/             # analysis_profiles.json, required_tables.json
├─ migrations/          # neo4j-migrations: Constraints, Indizes (idempotent)
├─ load/               # LOAD-CSV-Skripte + Convert-Se16Export.ps1 (Host-Variante)
├─ rules/              # normalisierte Rulesets (KPMG_R3/CSI/CSI_BI) + _archive/
├─ cypher/
│  ├─ checks/          # Einzelberechtigungs-Checks
│  ├─ sod/             # SoD-Materialisierung + Auswertung
│  ├─ ruleset/        # Ruleset-Loader (JSON → Graph)
│  └─ admin/           # clear_dataset / reset_data
├─ dashboards/         # NeoDash-Export (JSON, PoC)
├─ run/                # run_import.ps1 / run_evaluate.ps1 (Host-Runner)
├─ docs/               # Sphinx/MyST: Phasen, Datenmodell, Extraktionsleitfaden
│  └─ legacy/          # Alte Importskripte (Referenz)
├─ data/              # GITIGNORED: SAP-CSV + DB-Volume + Import
└─ backups/           # GITIGNORED: Dataset-Backups (.zip)
```

## Anforderungen

- Docker Desktop mit WSL2-Backend (Windows)
- Neo4j Community + NeoDash + APOC laufen als Container (gepinnte Versionen, siehe
  `docker-compose.yml`)

## Legacy

`docs/legacy/sap_abap_importer.cypher` enthält den früheren JSON/APOC-Importansatz
(`apoc.load.json`, deutsche Labels). Er ist als Referenz erhalten; der aktuelle Ansatz
folgt der ROADMAP (LOAD CSV, versionierte Migrationen, englische Labels).

---

Kontakt: Mirko Prehn
