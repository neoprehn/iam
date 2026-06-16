<#
.SYNOPSIS
  Auswerte-Runner: Ruleset laden -> Matches materialisieren -> SoD auswerten (Findings).

.DESCRIPTION
  Drei Schritte ueber den laufenden iam-neo4j: cypher/ruleset/load_ruleset, cypher/sod/
  materialize_matches, cypher/sod/evaluate_sod. Profile (Nutzertyp/Org/Scope/Sleeping) werden
  aus config/analysis_profiles.json aufgeloest und als -P Parameter uebergeben.

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
  .\run\run_evaluate.ps1 -Ruleset kpmg_r3 -Dataset sachsenenergie -AsOf 2023-12-31 -UserTypeProfile dialog-service
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

function Invoke-Cypher([string] $file, [string[]] $params) {
    $dargs = @('exec', 'iam-neo4j', 'cypher-shell', '-u', 'neo4j', '-p', $pw)
    foreach ($p in $params) { $dargs += @('-P', $p) }
    $dargs += @('-f', $file)
    & docker @dargs
    if ($LASTEXITCODE -ne 0) { throw "Fehler in $file" }
}

if (-not $SkipRulesetLoad) {
    Write-Host "[1/3] Ruleset laden ($rsDir) ..." -ForegroundColor Cyan
    Invoke-Cypher '/cypher/ruleset/load_ruleset.cypher' @("dir => '$rsDir'", "ruleset => '$Ruleset'")
}
if (-not $SkipMaterialize) {
    Write-Host "[2/3] Matches materialisieren (Stichtag $AsOf) ..." -ForegroundColor Cyan
    Invoke-Cypher '/cypher/sod/materialize_matches.cypher' @("ruleset => '$Ruleset'", "dataset => '$Dataset'", "asOf => date('$AsOf')", "runId => '$RunId'")
}
Write-Host "[3/3] SoD auswerten ..." -ForegroundColor Cyan
Invoke-Cypher '/cypher/sod/evaluate_sod.cypher' @(
    "ruleset => '$Ruleset'", "dataset => '$Dataset'", "asOf => date('$AsOf')", "runId => '$RunId'",
    "userTypes => $(ConvertTo-Cypher $userTypes)", "excludeLocked => $(ConvertTo-Cypher $excludeLocked)",
    "sleepDays => $SleepDays", "minCriticalityRank => $MinCriticalityRank",
    "sodRules => $(ConvertTo-Cypher $SodRules)", "orgFilters => $(ConvertTo-Cypher $orgFilters)"
)

# Zusammenfassung (Query als Argument -> kein stdin-BOM)
Write-Host "== Zusammenfassung runId=$RunId ==" -ForegroundColor Green
$q = "MATCH (f:SoDConflict {runId:'$RunId'}) RETURN count(f) AS findings, count(DISTINCT f.ruleId) AS regeln, sum(CASE WHEN f.userSleeping THEN 1 ELSE 0 END) AS sleeping;"
docker exec iam-neo4j cypher-shell -u neo4j -p $pw --format plain $q
