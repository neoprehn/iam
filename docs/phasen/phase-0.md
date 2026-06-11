# Phase 0 — Fundament & Umgebung

**Ziel:** Eine lauffähige lokale Neo4j-Umgebung und das Repo-Gerüst. **DoD:** Ein frisch
geklontes Repo bringt mit wenigen Befehlen eine leere, lauffähige Umgebung hoch.

Die Umgebung ist **container-only** (AE-15): Neo4j, NeoDash und APOC laufen als Container über
Docker Desktop mit WSL2-Backend. Auf dem Windows-Host wird **keine** Neo4j- oder
Java-Installation benötigt; `cypher-shell` wird über den laufenden Container aufgerufen.

## Voraussetzungen (Host)

Einmalig auf dem Windows-Rechner. Beide Schritte brauchen Administratorrechte und einen
Neustart.

### 1. WSL2 installieren

In einer **als Administrator** gestarteten PowerShell:

```powershell
wsl --install
```

Danach **Rechner neu starten**.

### 2. Docker Desktop installieren

[Docker Desktop](https://www.docker.com/products/docker-desktop) herunterladen und
installieren, dabei die Option *„Use WSL 2 instead of Hyper-V"* aktiviert lassen. Anschließend
Docker Desktop starten und warten, bis die Engine läuft.

### 3. Verifizieren

```powershell
wsl -l -v
docker --version
docker compose version
```

Erwartet: WSL listet eine Distro mit `VERSION 2`, `docker` und `docker compose` antworten mit
einer Versionsnummer. Referenz beim Aufbau dieser Phase: Docker `29.5.3`, Compose `v5.1.4`.

## Repo-Gerüst

Die Zielstruktur trennt Logik (im Repo) strikt von Daten (lokal, gitignored — AE-01):

```text
iam/
├─ docker-compose.yml   # Neo4j + NeoDash, Versionen gepinnt, APOC
├─ migrations/          # neo4j-migrations: Constraints, Indizes (Phase 1)
├─ load/               # LOAD CSV-Skripte (Phase 2)
├─ rules/              # Regelkatalog sod_matrix.csv (Phase 3)
├─ cypher/
│  ├─ checks/          # Einzelberechtigungs-Checks
│  └─ sod/             # SoD-Abfragen
├─ dashboards/         # NeoDash-Export (JSON, Phase 6)
├─ run/                # Runner (Phase 5)
├─ docs/               # diese Doku (Sphinx/MyST) + docs/legacy
└─ data/              # GITIGNORED: SAP-CSV + DB-Volume + Import
```

### `docker-compose.yml`

Gepinnte Versionen sichern Reproduzierbarkeit (AE-14). APOC wird passend zur Neo4j-Version
automatisch über `NEO4J_PLUGINS` geladen — kein separates Image.

```yaml
services:
  neo4j:
    image: neo4j:5.26.27-community
    container_name: iam-neo4j
    ports:
      - "7474:7474"   # Neo4j Browser (HTTP)
      - "7687:7687"   # Bolt
    environment:
      NEO4J_AUTH: neo4j/${NEO4J_PASSWORD}
      NEO4J_PLUGINS: '["apoc"]'
      NEO4J_apoc_import_file_enabled: "true"
      NEO4J_apoc_import_file_use__neo4j__config: "true"
      NEO4J_dbms_security_procedures_unrestricted: "apoc.*"
    volumes:
      - ./data/db:/data
      - ./data/import:/var/lib/neo4j/import   # file:///<name>.csv (AE-15)
      - ./data/logs:/logs
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:7474 || exit 1"]
      interval: 15s
      timeout: 10s
      retries: 10
      start_period: 40s
    restart: unless-stopped

  neodash:
    image: neo4jlabs/neodash:2.4.11
    container_name: iam-neodash
    ports:
      - "5005:5005"
    depends_on:
      neo4j:
        condition: service_healthy
    restart: unless-stopped
```

Wichtig für Windows: relative Pfade mit Vorwärts-Slashes (`./data/db:/data`), fester
Container-Name `iam-neo4j` (damit `docker exec` im späteren Runner stabil bleibt).

### Schutz-Dateien

`.gitignore` hält Daten, Secrets und Dumps aus dem Repo (AE-01):

```text
/data/
.env
*.dump
```

`.gitattributes` erzwingt LF-Zeilenenden für Skripte, die im Linux-Container laufen —
sonst scheitert die Ausführung an CRLF (AE-15):

```text
*.cypher text eol=lf
*.sh     text eol=lf
*.ps1    text eol=crlf
```

`.env.example` ist die Vorlage; die echte `.env` (mit dem Neo4j-Passwort, min. 8 Zeichen)
bleibt lokal und gitignored.

## Start & Verifikation

```powershell
# Zugangsdaten anlegen (lokal, gitignored)
Copy-Item .env.example .env
notepad .env            # NEO4J_PASSWORD setzen (min. 8 Zeichen)

# Umgebung starten (erster Start zieht Images + APOC, dauert etwas)
docker compose up -d

# Status
docker compose ps
```

:::{note}
Neo4j übernimmt das Passwort aus `NEO4J_AUTH` nur beim **ersten** Start, solange
`data/db` leer ist. Ein späterer Passwortwechsel greift erst nach Löschen des
DB-Volumes.
:::

Erreichbarkeit der Web-Oberflächen:

- Neo4j Browser: <http://localhost:7474>
- NeoDash: <http://localhost:5005>

Cypher über den Container ausführen (kein lokaler `cypher-shell` nötig — AE-15):

```powershell
docker exec -i iam-neo4j cypher-shell -u neo4j -p "$env:NEO4J_PASSWORD" "RETURN 1 AS ok;"
docker exec -i iam-neo4j cypher-shell -u neo4j -p "$env:NEO4J_PASSWORD" "RETURN apoc.version();"
```

### Ergebnis beim Aufbau dieser Phase

| Prüfung | Ergebnis |
| --- | --- |
| `iam-neo4j` | Up, **healthy** (Ports 7474/7687) |
| `iam-neodash` | Up (Port 5005) |
| Neo4j Browser `:7474` | HTTP 200 |
| NeoDash `:5005` | HTTP 200 |
| `cypher-shell … RETURN 1` | `ok = 1` |
| APOC | `5.26.27` geladen |

Damit ist die DoD von Phase 0 erfüllt.

## Nützliche Befehle

```powershell
docker compose ps                 # Status
docker logs iam-neo4j             # Neo4j-Logs
docker compose down               # Stoppen (Daten bleiben im Volume)
docker compose down -v            # Stoppen + Volumes löschen (Reset, NUR Dev)
docker compose up -d              # (Neu-)Starten
```
