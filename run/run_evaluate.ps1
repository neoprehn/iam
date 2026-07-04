<#
.SYNOPSIS
  Auswerte-Runner: Ruleset laden -> Matches materialisieren -> SoD auswerten (Findings).

.DESCRIPTION
  Drei Schritte ueber den laufenden iam-neo4j: cypher/ruleset/load_ruleset, cypher/sod/
  materialize_matches_*, cypher/sod/evaluate_sod_*. Materialisieren und Auswerten laufen als
  Reset (einmalig) -> Kandidaten ermitteln -> pro Einheit (Query bzw. Regel) -- dieselben
  .cypher-Dateien wie die App (backend/app.py:_run_phase()), nur ohne deren Fortschrittsanzeige/
  Checkpoint (Host-Runner ist ein einmaliger interaktiver Lauf, alle Schritte idempotent).
  Evidenz (VIA_ROLE/VIA_PROFILE + intra/inter) wird hier NICHT berechnet -- ueber die App per
  POST /runs/{id}/explain nachrechenbar. Profile (Nutzertyp/Org/Scope/Sleeping) werden aus
  config/analysis_profiles.json aufgeloest und als -P Parameter uebergeben.

.PARAMETER Ruleset   Ruleset-Id (kpmg_r3/csi/csi_bi); Ordner wird aus rules/*/ruleset.json ermittelt.
.PARAMETER Dataset   Dataset-Id (System).
.PARAMETER AsOf      Stichtag 'YYYY-MM-DD' — MUSS zum Datenstand (Snapshot) passen.
.PARAMETER UserTypeProfile  Name aus config userTypeProfiles (Default 'all').
.PARAMETER OrgProfile       Name aus config profiles (Default 'standard' = egal).
.PARAMETER SleepDays        Sleeping-Schwelle; Default aus config sleeping.sleepDays.
.PARAMETER MinCriticalityRank  nur Regeln >= Rang (5=very-high); Default 0.
.PARAMETER SodRules         explizite Regel-IDs (leer = alle).
.PARAMETER RunId            Lauf-Id (Default: ruleset-Zeitstempel).
.PARAMETER SkipRulesetLoad  Ruleset bereits geladen.
.PARAMETER SkipMaterialize  Zwischenergebnis bereits materialisiert (gleicher Stichtag!).

.EXAMPLE
  .\run\run_evaluate.ps1 -Ruleset kpmg_r3 -Dataset acme -AsOf 2023-12-31 -UserTypeProfile dialog-service
#>
param(
    [string] $Ruleset = 'kpmg_r3',
    [Parameter(Mandatory = $true)] [string] $Dataset,
    [Parameter(Mandatory = $true)] [string] $AsOf,
    [string] $UserTypeProfile = 'all',
    [string] $OrgProfile = 'standard',
    [int] $SleepDays = -1,
    [int] $MinCriticalityRank = 0,
    [string[]] $SodRules = @(),
    [string] $RunId,
    [switch] $SkipRulesetLoad,
    [switch] $SkipMaterialize
)
# 'Continue' (statt 'Stop'): native Tools koennen auf stderr schreiben — echte Fehler via
# $LASTEXITCODE (Invoke-Cypher) bzw. explizite throws.
$ErrorActionPreference = 'Continue'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

function Get-EnvVal([string] $name) {
    $line = Get-Content (Join-Path $root '.env') | Where-Object { $_ -match "^$name=" } | Select-Object -First 1
    if ($line) { ($line -replace "^$name=", '').Trim() } else { $null }
}
$pw = Get-EnvVal 'NEO4J_PASSWORD'
if (-not $pw) { throw 'NEO4J_PASSWORD fehlt in .env' }

# PS-Wert -> Cypher-Literal (String/Bool/Zahl/Liste/Map)
function ConvertTo-Cypher($v) {
    if ($null -eq $v) { return 'null' }
    if ($v -is [bool]) { return $v.ToString().ToLower() }
    if ($v -is [int] -or $v -is [long] -or $v -is [double]) { return "$v" }
    if ($v -is [string]) { return "'" + ($v -replace "'", "\'") + "'" }
    if ($v -is [System.Collections.IDictionary]) {
        $p = $v.GetEnumerator() | ForEach-Object { "$($_.Key):$(ConvertTo-Cypher $_.Value)" }
        return '{' + ($p -join ',') + '}'
    }
    if ($v -is [System.Management.Automation.PSCustomObject]) {
        $p = $v.PSObject.Properties | Where-Object { -not $_.Name.StartsWith('_') } | ForEach-Object { "$($_.Name):$(ConvertTo-Cypher $_.Value)" }
        return '{' + ($p -join ',') + '}'
    }
    if ($v -is [System.Collections.IEnumerable]) {
        return '[' + (($v | ForEach-Object { ConvertTo-Cypher $_ }) -join ',') + ']'
    }
    return "'$v'"
}

# Config + Ruleset-Ordner
$cfg = Get-Content (Join-Path $root 'config\analysis_profiles.json') -Raw | ConvertFrom-Json
$rsDir = (Get-ChildItem (Join-Path $root 'rules') -Directory | Where-Object {
        $rj = Join-Path $_.FullName 'ruleset.json'
        (Test-Path $rj) -and ((Get-Content $rj -Raw | ConvertFrom-Json).ruleset -eq $Ruleset)
    } | Select-Object -First 1).Name
if (-not $rsDir) { throw "Kein Ruleset-Ordner fuer '$Ruleset' (rules/*/ruleset.json)." }

# Profile aufloesen
$utp = $cfg.userTypeProfiles | Where-Object { $_.name -eq $UserTypeProfile } | Select-Object -First 1
if (-not $utp) { throw "userTypeProfile '$UserTypeProfile' unbekannt." }
$userTypes = @($utp.userTypes)
$excludeLocked = [bool]$utp.excludeLocked
$op = $cfg.profiles | Where-Object { $_.name -eq $OrgProfile } | Select-Object -First 1
if (-not $op) { throw "OrgProfile '$OrgProfile' unbekannt." }
$orgFilters = if ($op.org.mode -eq 'filtered') { $op.org.filters } else { [pscustomobject]@{} }
if ($SleepDays -lt 0) { $SleepDays = [int]$cfg.sleeping.sleepDays }
if (-not $RunId) { $RunId = "$Ruleset-$(Get-Date -Format yyyyMMddHHmmss)" }

Write-Host "== Auswerte-Runner | ruleset=$Ruleset dataset=$Dataset asOf=$AsOf runId=$RunId ==" -ForegroundColor Cyan
Write-Host "   userTypes=$(ConvertTo-Cypher $userTypes) org=$OrgProfile orgFilters=$(ConvertTo-Cypher $orgFilters) sleepDays=$SleepDays minRank=$MinCriticalityRank" -ForegroundColor DarkCyan

$orgMode = $op.org.mode

function Invoke-Cypher([string] $file, [string[]] $params) {
    $dargs = @('exec', 'iam-neo4j', 'cypher-shell', '-u', 'neo4j', '-p', $pw)
    foreach ($p in $params) { $dargs += @('-P', $p) }
    $dargs += @('-f', $file)
    & docker @dargs
    if ($LASTEXITCODE -ne 0) { throw "Fehler in $file" }
}

# Kandidaten-Datei ausfuehren (ein RETURN id-Statement, s. backend/app.py:_run_candidates) und
# die id-Spalte als Liste zurueckgeben -- treibt die Pro-Einheit-Schleife unten, exakt wie die
# App das ueber den Treiber macht (dieselben .cypher-Dateien, kein doppelt gepflegter Cypher-Text).
function Get-CypherIds([string] $file, [string[]] $params) {
    $dargs = @('exec', 'iam-neo4j', 'cypher-shell', '-u', 'neo4j', '-p', $pw, '--format', 'plain')
    foreach ($p in $params) { $dargs += @('-P', $p) }
    $dargs += @('-f', $file)
    $out = & docker @dargs
    if ($LASTEXITCODE -ne 0) { throw "Fehler in $file" }
    $out | Select-Object -Skip 1 | ForEach-Object { $_.Trim('"') } | Where-Object { $_ }
}

# Eine Phase (materialize/evaluate/explain) als Reset (einmalig) -> Kandidaten -> pro Einheit --
# analog zu _run_phase() in backend/app.py, nur ohne Checkpoint/Resume (Host-Runner ist ein
# einmaliger interaktiver Lauf; bei Abbruch: einfach neu starten, alle drei Schritte sind
# idempotent). cypher-shell startet je Einheit neu -- der Prozess-Overhead ist gegenueber der
# eigentlichen Cypher-Laufzeit pro Query/Regel/Akteur meist vernachlaessigbar.
function Invoke-Phase([string] $label, [string] $resetFile, [string] $candidatesFile,
                       [string] $oneFile, [string] $unitParamName, [string[]] $baseParams) {
    if ($resetFile) { Invoke-Cypher $resetFile $baseParams }
    $ids = @(Get-CypherIds $candidatesFile $baseParams)
    $n = $ids.Count
    for ($i = 0; $i -lt $n; $i++) {
        Write-Progress -Activity $label -Status "$($i + 1)/$n : $($ids[$i])" -PercentComplete (100 * ($i + 1) / [Math]::Max($n, 1))
        Invoke-Cypher $oneFile ($baseParams + @("$unitParamName => '$($ids[$i])'"))
    }
    Write-Progress -Activity $label -Completed
    Write-Host "      $n Einheiten." -ForegroundColor DarkGray
}

if (-not $SkipRulesetLoad) {
    Write-Host "[1/4] Ruleset laden ($rsDir) ..." -ForegroundColor Cyan
    Invoke-Cypher '/cypher/ruleset/load_ruleset.cypher' @("dir => '$rsDir'", "ruleset => '$Ruleset'")
}
$commonParams = @("ruleset => '$Ruleset'", "dataset => '$Dataset'", "asOf => date('$AsOf')", "runId => '$RunId'")
if (-not $SkipMaterialize) {
    Write-Host "[2/4] Matches materialisieren (Stichtag $AsOf) ..." -ForegroundColor Cyan
    Invoke-Phase 'Materialisiere' '/cypher/sod/materialize_matches_reset.cypher' '/cypher/sod/materialize_matches_candidates.cypher' `
        '/cypher/sod/materialize_matches_one.cypher' 'qid' `
        ($commonParams + @("orgMode => '$orgMode'", "orgFilters => $(ConvertTo-Cypher $orgFilters)"))
}
Write-Host "[3/4] SoD auswerten ..." -ForegroundColor Cyan
$evalParams = $commonParams + @(
    "userTypes => $(ConvertTo-Cypher $userTypes)", "excludeLocked => $(ConvertTo-Cypher $excludeLocked)",
    "sleepDays => $SleepDays", "minCriticalityRank => $MinCriticalityRank",
    "sodRules => $(ConvertTo-Cypher $SodRules)", "title => '$RunId'",
    "orgMode => '$orgMode'", "orgFilters => $(ConvertTo-Cypher $orgFilters)"
)
Invoke-Cypher '/cypher/sod/evaluate_sod_init.cypher' $evalParams
Invoke-Phase 'Werte aus' $null '/cypher/sod/evaluate_sod_candidates.cypher' '/cypher/sod/evaluate_sod_one.cypher' 'ruleId' $evalParams
Write-Host "[4/4] Evidenz (optional, hier nicht berechnet -- ueber die App/POST /runs/{id}/explain nachrechenbar) ..." -ForegroundColor DarkGray

# Zusammenfassung (Query als Argument -> kein stdin-BOM)
Write-Host "== Zusammenfassung runId=$RunId ==" -ForegroundColor Green
$q = "MATCH (f:SoDConflict {runId:'$RunId'}) RETURN count(f) AS findings, count(DISTINCT f.ruleId) AS regeln, sum(CASE WHEN f.userSleeping THEN 1 ELSE 0 END) AS sleeping;"
docker exec iam-neo4j cypher-shell -u neo4j -p $pw --format plain $q
