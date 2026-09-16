<#
.SYNOPSIS
  Startet den iam-Backend-Prozess (uvicorn) nativ gegen die Windows-Installation.

.DESCRIPTION
  Setzt dieselben Umgebungsvariablen, die im Docker-Setup ueber die Volume-Mounts in
  docker-compose.yml entstehen (s. backend/app.py, CONFIG_DIR/RULES_DIR/... Defaults dort sind
  Container-Pfade wie /app/config -- hier auf die realen Repo-Unterordner umgebogen), und startet
  uvicorn im Vordergrund. Wird vom Scheduled Task 'IAM-Backend' bei jedem Systemstart aufgerufen
  (s. install.ps1) -- laeuft deshalb OHNE --reload (anders als im Docker-Dev-Setup): Codeaenderungen
  wirken erst nach dem naechsten Update-Lauf (update.ps1) bzw. Neustart des Tasks.

.PARAMETER RepoDir  Pfad zum geklonten Repo (s. install.ps1 -InstallDir).
#>
param(
    [Parameter(Mandatory = $true)] [string] $RepoDir
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path $RepoDir).Path

function Get-EnvVal([string] $name, [string] $path) {
    $line = Get-Content $path | Where-Object { $_ -match "^$name=" } | Select-Object -First 1
    if ($line) { ($line -replace "^$name=", '').Trim() } else { $null }
}
$envPath = Join-Path $repo '.env'
$pw = Get-EnvVal 'NEO4J_PASSWORD' $envPath
if (-not $pw) { throw "NEO4J_PASSWORD fehlt in $envPath" }
$lang = Get-EnvVal 'IMPORT_LANG' $envPath
if (-not $lang) { $lang = 'DE,DEU,D' }

$env:NEO4J_URI = 'bolt://localhost:7687'
$env:NEO4J_USER = 'neo4j'
$env:NEO4J_PASSWORD = $pw
$env:IMPORT_LANG = $lang
$env:CONFIG_DIR = Join-Path $repo 'config'
$env:RULES_DIR = Join-Path $repo 'rules'
$env:CHECKS_DIR = Join-Path $repo 'checks'
$env:CYPHER_DIR = Join-Path $repo 'cypher'
$env:LOAD_DIR = Join-Path $repo 'load'
$env:MIGRATIONS_DIR = Join-Path $repo 'migrations'
$env:DATA_DIR = Join-Path $repo 'data\import'
$env:BACKUP_DIR = Join-Path $repo 'backups'
$env:LOG_DIR = Join-Path $repo 'data\logs'
$env:FRONTEND_DIR = Join-Path $repo 'frontend'

Set-Location (Join-Path $repo 'backend')
& "$repo\.venv-win\Scripts\python.exe" -m uvicorn app:app --host 0.0.0.0 --port 8000
