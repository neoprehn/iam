# Phase 10 — Verteilung & Reproduzierbarkeit

**Ziel:** Das Projekt auf einem anderen Rechner identisch zum Laufen bringen — als Kollegen-Demo
oder als eigenes Zweitgerät (z. B. ein Laptop für Entwicklung unterwegs) — **ohne dass
Mandantendaten über GitHub/Cloud wandern**.

:::{admonition} Vertrauensgrenze
:class: important
Zwei strikt getrennte Dinge wandern auf unterschiedlichen Wegen: **Code/Logik** über Git/GitHub
(unkritisch, öffentlich einsehbar), **Mandantendaten** (SAP-Extrakte, DB-Inhalt, Backups) nur
manuell und verschlüsselt (USB-Stick, verschlüsselter Container) — nie per E-Mail, Cloud-Freigabe
oder Commit.
:::

## Voraussetzung auf dem Zielrechner

Docker Desktop mit WSL2-Backend — eine allgemeine Windows-Voraussetzung, kein IAM-spezifischer
Schritt (Details: [Docker-Doku](https://docs.docker.com/desktop/setup/install/windows-install/)).

Typischer Fehler beim ersten Start: *„WSL fehlt"*. Fix in den meisten Fällen (PowerShell als
Administrator, danach Neustart):

```powershell
wsl --install
```

Bricht das ab, meist zwei Ursachen: Virtualisierung im BIOS/UEFI deaktiviert (Task-Manager →
Leistung → CPU → „Virtualisierung") oder Windows-Version zu alt (`winver`, mind. Version 2004 /
Build 19041). RAM-Bedarf: Neo4j fordert per `docker-compose.yml` **8 GB Heap + 4 GB Pagecache** an
(s. Phase 9) — WSL2 reserviert sich standardmäßig ~50 % des Host-RAM; ab **16 GB** Host-RAM
komfortabel ausreichend, darunter ggf. `%UserProfile%\.wslconfig` anpassen (`memory=`-Wert) oder die
Heap/Pagecache-Werte in `docker-compose.yml` für den Zielrechner reduzieren.

## Code übertragen — zwei Wege

**Weg A — `git clone` (sauber, empfohlen bei Internetzugang zu GitHub):**
```powershell
git clone https://github.com/neoprehn/iam.git
```

**Weg B — kompletten Ordner kopieren (z. B. per USB, kein GitHub-Zugriff nötig):**
Alle Pfade in `docker-compose.yml` sind relativ — der Ordner ist 1:1 portierbar, unabhängig vom
Laufwerksbuchstaben (`D:\` vs. `C:\` spielt keine Rolle). `.env` kann unverändert mitkopiert werden
(Passwort bleibt gültig). Nachträglich an Git anbinden (z. B. für spätere `git pull`-Updates), ohne
lokale Inhalte zu verlieren:
```powershell
cd <kopierter-Ordner>
git init
git remote add origin https://github.com/neoprehn/iam.git
git fetch origin
git checkout -f -B main origin/main
```
`git checkout -f` überschreibt nur **getrackte** Dateien mit dem GitHub-Stand (unkritisch bei
identischem Ausgangsstand); `.env`, `data/`, `backups/` sind gitignored und bleiben unangetastet.

## Umgebung starten

```powershell
docker compose up -d --build
docker compose run --rm migrations      # Schema anlegen, idempotent
```
Warten, bis `docker compose ps` bei `iam-neo4j` **„healthy"** zeigt. App: `http://localhost:8000/`.

## Auswertung übertragen — zwei Verfahren

Der eigentliche Neo4j-Graph liegt **nicht** im Projektordner, sondern in einem von Docker verwalteten
**Named Volume** (`iam_neo4j_db`) — ein reiner Ordner-Transfer nimmt ihn nicht mit. Zwei Wege, je nach
Bedarf:

**a) App-eigenes Backup/Restore** (Ribbon „Sichern") — Dataset-Backup (Quell-CSV) + Run-Backup
(Findings). Leichtgewichtig, über die UI bedienbar, **aber bewusst ohne Evidenz**
(`VIA_ROLE`/`VIA_PROFILE`) — Root-Cause-Graphen müssen nach Restore neu berechnet werden
(„Evidenz"-Button). Geeignet, wenn nur ein einzelnes Dataset/Run gebraucht wird.

**b) `neo4j-admin database dump`/`load`** — kompletter Graph in einer Datei: alle Datasets, alle
Rulesets, alle Runs/Findings **inklusive Evidenz**, kein Nachrechnen nötig. **Am 2026-07-12 live
end-to-end verifiziert** (5,66 GiB Rohdaten, Dump in 41 s, Load in 17 s, Knotenzahl vor/nach
identisch: 3.932.567).

Neo4j **Community Edition kann keine einzelne Datenbank pausieren** (`STOP DATABASE` ist
Enterprise-only, meldet „Unsupported administration command") — der Dump braucht daher den
**ganzen `neo4j`-Container gestoppt**, nicht nur die Datenbank. Auf Windows/Git-Bash unbedingt
**PowerShell** verwenden (Git-Bash übersetzt `/tmp`-Pfade fälschlich in Windows-Pfade).

Dump (Quellrechner):
```powershell
cd D:\Entwicklung\iam\iam
docker compose stop backend neo4j
docker compose run --rm -v "${PWD}\backups:/hostout" neo4j neo4j-admin database dump neo4j --to-path=/hostout --overwrite-destination=true
docker compose up -d
```
→ Datei liegt danach unter `backups\neo4j.dump`; wandert wie jede Mandantendaten-Datei nur manuell
(USB/verschlüsselt).

Load (Zielrechner, nach `docker compose up -d --build` + `migrations`, `neo4j.dump` vorher in
`backups\` kopiert):
```powershell
docker compose stop backend neo4j
docker compose run --rm -v "${PWD}\backups:/hostout" neo4j neo4j-admin database load neo4j --from-path=/hostout --overwrite-destination=true
docker compose up -d
```

## Code-Änderungen nach `git pull` — was der laufende Container automatisch übernimmt

Fast der gesamte App-Code ist **bind-gemountet**, nicht ins Image gebacken
(`backend/app.py`, `backend/convert.py`, `frontend/`, `cypher/`, `rules/`, `config/`); der
Backend-Container läuft mit `uvicorn --reload`. Ein `git pull` auf einem Zweitgerät wird daher in
den allermeisten Fällen **automatisch übernommen** — kein Rebuild, kein Neustart:

| Änderung | Aktion nötig? |
| --- | --- |
| `backend/app.py`, `backend/convert.py`, `frontend/*`, `cypher/*`, `rules/*`, `config/*` | **Nein** — Hot-Reload |
| `backend/requirements.txt` (neue Abhängigkeit), `Dockerfile` | `docker compose up -d --build` |
| `migrations/*.cypher` (Schema-Änderung) | `docker compose run --rm migrations` |

Zur Einordnung, wie oft die beiden Ausnahmefälle tatsächlich vorkommen (Stand 2026-07-12, 146
Commits Projekthistorie): `requirements.txt` 3×, `migrations/` 4× geändert — der Normalfall ist
also der automatische Hot-Reload-Pfad.

## Mehrere eigene Arbeitsgeräte (Heim + mobil)

Bewusst **zurückgestellt, aktuell nicht benötigt**: eine feste Synchronisationsroutine für
Mandantendaten zwischen zwei eigenen Geräten. Bei Bedarf greift derselbe `dump`/`load`-Mechanismus
wie oben, nur wiederkehrend statt einmalig. Für den Code reicht einfache Disziplin (Solo-Projekt,
ein Branch): vor dem Rechnerwechsel committen + pushen, beim Ankommen zuerst `git pull`.

Ein mobiles Gerät, das Mandantendaten mitführt, macht die Vertrauensgrenze praxisrelevanter als am
stationären Heim-Rechner: Volltext-Verschlüsselung (BitLocker) empfohlen; beim Arbeiten mit echten
Datasets unterwegs die üblichen Berufsgeheimnis-Vorsichten (kein öffentliches WLAN für Datenzugriff,
Bildschirmsperre, Blickschutz).

## Status & Offenes

**Verifiziert (2026-07-12):** kompletter Ordner-Transfer (relative Pfade, laufwerksunabhängig),
nachträgliche Git-Anbindung ohne Datenverlust, `neo4j-admin dump`/`load` end-to-end inkl.
Restore-Probe in einem Wegwerf-Volume, Hot-Reload-Verhalten.

**Offen:** `docker-compose.yml`-Versionen abschließend gegenprüfen; ein eigenständiges
Onboarding-Dokument im Top-Level-README (dieser Phasen-Text deckt den Inhalt bereits ab, aber noch
nicht in der knappen Kurzform fürs README); Synchronisationsroutine für mehrere eigene Geräte (s. o.,
bewusst zurückgestellt).

**DoD (Phase 10):** Ein Kollege — oder das eigene Zweitgerät — bringt das Projekt identisch zum
Laufen, ohne dass Mandantendaten das Repo berühren.
