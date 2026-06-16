<#
.SYNOPSIS
  Import-Runner: SE16-Export eines Datasets in den Graphen (konvertieren -> migrieren -> laden -> validieren).

.DESCRIPTION
  Erwartet den SE16-"unkonvertiert"-Export unter data/import/<Dataset>/ (.txt). Konvertiert ihn
  (Minimalset-Pruefung + Credential-Denylist), stellt das Schema sicher und laedt alle load/*.cypher
  in Reihenfolge mit -P dataset / -P lang. Container-only ueber den laufenden iam-neo4j.

.PARAMETER Dataset   Ordnername unter data/import/ (= dataset-Id).
.PARAMETER Lang      Sprach-Schalter (komma-separiert); Default aus .env IMPORT_LANG bzw. DE,DEU,D.
.PARAMETER SkipConvert  .txt sind bereits konvertiert -> Konvertierung ueberspringen.

.EXAMPLE
  .\run\run_import.ps1 -Dataset sachsenenergie
#>
param(
    [Parameter(Mandatory = $true)] [string] $Dataset,
    [string] $Lang,
    [switch] $SkipConvert
)
# 'Continue': native Tools (docker compose) schreiben Fortschritt auf stderr — unter 'Stop'
# wuerde PS 5.1 das faelschlich als fatalen Fehler werten. Echte Fehler via $LASTEXITCODE.
$ErrorActionPreference = 'Continue'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

function Get-EnvVal([string] $name) {
    $line = Get-Content (Join-Path $root '.env') | Where-Object { $_ -match "^$name=" } | Select-Object -First 1
    if ($line) { ($line -replace "^$name=", '').Trim() } else { $null }
}

$pw = Get-EnvVal 'NEO4J_PASSWORD'
if (-not $pw) { throw 'NEO4J_PASSWORD fehlt in .env' }
if (-not $Lang) { $Lang = Get-EnvVal 'IMPORT_LANG'; if (-not $Lang) { $Lang = 'DE,DEU,D' } }
$folder = Join-Path $root "data\import\$Dataset"
if (-not (Test-Path $folder)) { throw "Import-Ordner fehlt: $folder" }

Write-Host "== Import-Runner | dataset=$Dataset | lang=$Lang ==" -ForegroundColor Cyan

# 1. Konvertieren (Minimalset-Pruefung + Credential-Denylist stecken im Konverter)
if (-not $SkipConvert) {
    Write-Host "[1/4] Konvertiere SE16-Export ..." -ForegroundColor Cyan
    & (Join-Path $root 'load\Convert-Se16Export.ps1') -Folder $folder
}
else { Write-Host "[1/4] Konvertierung uebersprungen (-SkipConvert)." }

# 2. Schema sicherstellen
Write-Host "[2/4] Migrationen ..." -ForegroundColor Cyan
docker compose run --rm migrations
if ($LASTEXITCODE -ne 0) { throw 'Migrationen fehlgeschlagen' }

# 3. Laden (Reihenfolge = Dateiname)
Write-Host "[3/4] Lade load/*.cypher ..." -ForegroundColor Cyan
$ds = "dataset => '$Dataset'"
$codes = ($Lang.Split(',') | ForEach-Object { "'$($_.Trim())'" }) -join ','
$langP = "lang => [$codes]"
foreach ($f in (Get-ChildItem (Join-Path $root 'load\*.cypher') | Sort-Object Name)) {
    Write-Host "    >>> $($f.Name)"
    docker exec iam-neo4j cypher-shell -u neo4j -p $pw -P $ds -P $langP -f "/load/$($f.Name)"
    if ($LASTEXITCODE -ne 0) { throw "Fehler in $($f.Name)" }
}

Write-Host "[4/4] Import abgeschlossen (99_validate-Zaehler siehe oben)." -ForegroundColor Green
