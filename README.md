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

# 3. Umgebung starten (erster Start zieht Images + APOC)
docker compose up -d

# 4. Erreichbarkeit prüfen
#    Neo4j Browser : http://localhost:7474
#    NeoDash       : http://localhost:5005

# 5. Cypher über den Container ausführen (kein lokaler cypher-shell-Install nötig)
docker exec -i iam-neo4j cypher-shell -u neo4j -p "$env:NEO4J_PASSWORD" "RETURN 1 AS ok;"
```

SAP-CSV-Extrakte gehören lokal nach `data/import/` und werden in Cypher als
`file:///<dateiname>.csv` referenziert (keine Windows-Absolutpfade — der Linux-Container
versteht sie nicht).

## Repo-Struktur

```
iam/
├─ docker-compose.yml   # Neo4j + NeoDash + migrations, Versionen gepinnt, APOC
├─ docker/              # Dockerfile(s), z. B. neo4j-migrations-CLI (gepinnt)
├─ migrations/          # neo4j-migrations: Constraints, Indizes
├─ load/               # LOAD CSV-Skripte (Daten liegen lokal)
├─ rules/              # Regelkatalog (sod_matrix.csv)
├─ cypher/
│  ├─ checks/          # Einzelberechtigungs-Checks
│  └─ sod/             # SoD-Abfragen
├─ dashboards/         # NeoDash-Export (JSON)
├─ run/                # run_all.ps1 (primär) / run_all.sh
├─ docs/               # datamodel.md, Extraktionsleitfaden
│  └─ legacy/          # Alte Importskripte (Referenz)
└─ data/              # GITIGNORED: SAP-CSV + DB-Volume + Import
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
