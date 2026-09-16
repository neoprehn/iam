# Native Windows-Installation (ohne Docker)

Das Haupt-README beschreibt den **container-only**-Standardpfad (Docker Desktop/WSL2) — das
bleibt die empfohlene Umgebung. Dieser Ordner ist eine bewusste, zusätzliche Abweichung davon,
für genau einen Fall: einen Drittrechner, auf dem Docker nicht installiert werden darf/kann, die
einzelnen Komponenten (Python, Java, Neo4j) aber schon. Er ersetzt nichts am Haupt-Setup.

Was hier entsteht:

- **Neo4j Community Server** als native Windows-Dienst (kein Container) — Speicher-/APOC-/
  Import-Einstellungen sind 1:1 aus `docker-compose.yml` übernommen.
- **Backend** (`uvicorn`) als Scheduled Task, der bei jedem Systemstart automatisch läuft (auch
  ohne Login) — funktional das Windows-Äquivalent zum `iam-backend`-Container.
- Ein **täglicher Update-Task**, der `git pull` macht, Python-Abhängigkeiten synchronisiert und
  das Backend neu startet — der "einfache Pull statt echtes CI/CD"-Ansatz (bewusst gewählt: kein
  Build-Server nötig, Code kommt unverändert aus dem Git-Repo).

## Installation

1. PowerShell **als Administrator** öffnen.
2. Repo an einen beliebigen Ort klonen (oder direkt per Skript klonen lassen, s. u.).
3. Ausführen:

   ```powershell
   .\deploy\windows-native\install.ps1
   ```

   Optional mit Parametern (z. B. anderes Laufwerk, mehr Speicher auf leistungsfähigerer
   Hardware):

   ```powershell
   .\deploy\windows-native\install.ps1 -InstallDir D:\iam -HeapSizeGb 4 -PageCacheGb 4
   ```

   Das Skript ist **idempotent** — mehrfaches Ausführen (z. B. nach einem Fehler) überspringt
   bereits erledigte Schritte, statt sie zu wiederholen.

4. Nach Abschluss: <http://localhost:8000/> (Web-App) und <http://localhost:7474/> (Neo4j
   Browser) sollten erreichbar sein.

## Verifizieren (wichtig — bitte nicht überspringen)

Die Ruleset-Dateien unter `rules/` liest Neo4j selbst über `apoc.load.json('file:///rules/...')`
(derselbe feste Pfad wie im Docker-Bind-Mount `./rules:/rules:ro`, s.
`cypher/ruleset/load_ruleset.cypher`). Ohne Docker hängt die Auflösung dieses Pfads davon ab, wie
die JVM eine führerlose absolute Pfadangabe (`/rules/...`, ohne Laufwerksbuchstaben) aus dem
Arbeitsverzeichnis des Neo4j-Dienstes ableitet — `install.ps1` legt dafür eine NTFS-Junction
`<Laufwerk>:\rules` an und installiert Neo4j bewusst auf demselben Laufwerk wie das Repo. Das
sollte funktionieren, ist aber die einzige nicht-triviale Annahme in diesem Setup — deshalb hier
direkt gegentesten, bevor irgendetwas Fachliches (Ruleset laden, Lauf starten) versucht wird:

```powershell
# <NeoHome> = z. B. C:\neo4j\neo4j-community-5.26.27 (Pfad, den install.ps1 ausgegeben hat)
& "<NeoHome>\bin\cypher-shell.bat" -u neo4j -p <NEO4J_PASSWORD aus .env> `
    "CALL apoc.load.json('file:///rules/KPMG_R3/legends.json') YIELD value RETURN count(value);"
```

- **Ergebnis ist eine Zahl > 0:** Junction funktioniert, weiter mit dem eigentlichen Setup
  (Web-App → Import).
- **Fehler wie "Cannot open file" / "file does not exist":** Junction zeigt nicht dorthin, wo
  Neo4j sie erwartet. Prüfen, auf welchem Laufwerk `<NeoHome>` tatsächlich liegt, und die Junction
  dort manuell anlegen:

  ```powershell
  cmd /c mklink /J X:\rules "<Repo-Pfad>\rules"   # X: = Laufwerk von <NeoHome>
  ```

  Neo4j-Dienst danach neu starten (`Restart-Service neo4j`) und den Test wiederholen.

## Bedienung

Identisch zur Docker-Variante — die Web-App unter `http://localhost:8000/` deckt Import, SoD-Lauf,
Ergebnisse, Backup/Restore und Verwaltung ab (s. Haupt-README, Abschnitt "Bedienung über die
App"). Es gibt **keinen separaten Migrations-Schritt**: Der Import-Job im Backend wendet
`migrations/*.cypher` bei jedem Lauf selbst idempotent an (s. `app.py`), das eigenständige
`neo4j-migrations`-CLI-Tool aus `docker/neo4j-migrations.Dockerfile` wird hier nicht benötigt.

## Updates

Automatisch täglich um 06:00 Uhr über den Scheduled Task `IAM-Update`. Manuell sofort auslösen:

```powershell
Start-ScheduledTask -TaskName IAM-Update
# Log:
Get-Content C:\iam\data\logs\windows-update.log -Tail 30
```

Der Update-Lauf bricht bewusst ab (ohne etwas zu verändern), wenn `git merge --ff-only`
fehlschlägt — z. B. weil lokal manuell etwas im Installationsordner geändert wurde. In dem Fall
Log prüfen und `git status` im Repo-Ordner ansehen.

**Unterschied zum Docker-Dev-Setup:** Das Backend läuft hier **ohne** `--reload` — Codeänderungen
wirken erst nach dem nächsten Update-Lauf (der den Task neu startet), nicht sofort bei jedem
Speichern. Das ist beabsichtigt (dieser Rechner ist kein Entwicklungs-, sondern ein
Nutzungsrechner).

## Verwaltung / Troubleshooting

| Was | Wie |
|---|---|
| Backend-Status | `Get-ScheduledTask -TaskName IAM-Backend \| Get-ScheduledTaskInfo` |
| Backend manuell neu starten | `Stop-ScheduledTask -TaskName IAM-Backend; Start-ScheduledTask -TaskName IAM-Backend` |
| Backend-Ausgabe/Fehler | Scheduled Task läuft ohne Konsolenfenster — für Live-Debugging `start-backend.ps1` einmal direkt in einer PowerShell ausführen (`-RepoDir C:\iam`) |
| Neo4j-Status | `Get-Service neo4j` |
| Neo4j neu starten | `Restart-Service neo4j` |
| Neo4j-Logs | `<NeoHome>\logs\neo4j.log` und `debug.log` |
| Update-Logs | `data\logs\windows-update.log` im Repo |
| Port 8000/7474/7687 belegt | Andere Anwendung prüfen (`Get-NetTCPConnection -LocalPort 8000`); Ports sind in `start-backend.ps1` bzw. `neo4j.conf` nicht parametrisiert, bei Bedarf dort anpassen |
| Windows Firewall blockt Zugriff von anderen Rechnern | Eingehende Regel für TCP 8000 (Web-App) freigeben — standardmäßig ist die App nur von `localhost` aus gedacht |
| Speicher anpassen | `neo4j.conf` im `<NeoHome>\conf`-Ordner (Block hinter dem Marker-Kommentar), danach `Restart-Service neo4j` |

## Deinstallation

Kein automatisches Deinstallations-Skript (bewusst — geringes Risiko, hoher Aufwand für einen
Fall, der selten vorkommt). Manuell:

```powershell
Unregister-ScheduledTask -TaskName IAM-Backend -Confirm:$false
Unregister-ScheduledTask -TaskName IAM-Update -Confirm:$false
& "<NeoHome>\bin\neo4j.bat" uninstall-service
Remove-Item -Recurse -Force <NeoHome>          # Neo4j-Installation
Remove-Item <Laufwerk>:\rules                   # Junction (NICHT -Recurse -- sonst wird rules/ im Repo mitgeloescht!)
Remove-Item -Recurse -Force <Repo-Pfad>         # Repo + venv
```
