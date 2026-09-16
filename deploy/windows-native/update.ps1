<#
.SYNOPSIS
  Update-Runner fuer die native Windows-Installation: zieht den neuesten Stand aus dem Git-Repo,
  synchronisiert die Python-Abhaengigkeiten und startet das Backend neu.

.DESCRIPTION
  Entspricht fachlich einem "docker compose pull && docker compose up -d --build" fuer den
  Backend-Dienst -- Neo4j selbst (Version, Speicher-/APOC-Konfiguration) bleibt unberuehrt, da sich
  das auch im Docker-Setup nicht automatisch per Pull aktualisiert (docker-compose.yml-Aenderungen
  brauchen dort ebenfalls ein manuelles Neuanlegen). Schema-Migrationen (migrations/*.cypher) muessen
  hier NICHT separat angestossen werden -- der Import-Job im Backend wendet sie bei jedem Lauf
  ohnehin idempotent selbst an (s. app.py, MIGRATIONS_DIR.glob("*.cypher") vor jedem Import).

  Bricht bei nicht-fast-forward-faehigem Git-Stand ab (z. B. manuelle lokale Aenderungen im
  Installationsordner) statt Aenderungen zu ueberschreiben. Wird vom Scheduled Task 'IAM-Update'
  taeglich ausgefuehrt (s. install.ps1), kann aber jederzeit manuell gestartet werden:

    Start-ScheduledTask -TaskName IAM-Update
    # oder direkt:
    .\deploy\windows-native\update.ps1 -RepoDir C:\iam

.PARAMETER RepoDir  Pfad zum geklonten Repo.
#>
param(
    [Parameter(Mandatory = $true)] [string] $RepoDir
)
# 'Continue': git schreibt Fortschritt auf stderr, das soll keinen Abbruch ausloesen -- echte
# Fehler werden ueber $LASTEXITCODE geprueft (gleiches Muster wie run/run_import.ps1).
$ErrorActionPreference = 'Continue'
$repo = (Resolve-Path $RepoDir).Path

$logDir = Join-Path $repo 'data\logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$logFile = Join-Path $logDir 'windows-update.log'
function Log([string] $msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format 's'), $msg
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

Log "== Update-Lauf gestartet =="
Set-Location $repo
$before = git rev-parse HEAD
git fetch origin 2>&1 | ForEach-Object { Log "  $_" }
if ($LASTEXITCODE -ne 0) {
    Log "FEHLER: git fetch fehlgeschlagen. Update abgebrochen."
    exit 1
}
git merge --ff-only origin/main 2>&1 | ForEach-Object { Log "  $_" }
if ($LASTEXITCODE -ne 0) {
    Log "FEHLER: git merge --ff-only fehlgeschlagen (lokale Aenderungen im Repo?). Update abgebrochen -- manuell pruefen: git -C `"$repo`" status"
    exit 1
}
$after = git rev-parse HEAD
if ($before -eq $after) {
    Log "Bereits aktuell ($after), kein Neustart noetig."
    exit 0
}
Log "Aktualisiert: $before -> $after"

& "$repo\.venv-win\Scripts\pip.exe" install -r (Join-Path $repo 'backend\requirements.txt') -q
Log "Python-Abhaengigkeiten synchronisiert."

Log "Starte Backend-Task neu ..."
Stop-ScheduledTask -TaskName 'IAM-Backend' -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-ScheduledTask -TaskName 'IAM-Backend'
Log "== Update-Lauf abgeschlossen =="
