<#
.SYNOPSIS
  Wandelt SE16-"unkonvertiert"-Listenexporte (.txt) in saubere CSV (Tab-getrennt, UTF-8) um.

.DESCRIPTION
  SE16/SE16N "Lokale Datei -> unkonvertiert" liefert ein fixbreites, Pipe-getrenntes
  Listenformat mit Titel-/Info-/Trennzeilen und einer leeren Markierungsspalte. Das ist
  nicht direkt LOAD-CSV-tauglich. Dieses Skript extrahiert Kopfzeile (= SAP-Feldnamen) und
  Datenzeilen, trimmt das Fixbreiten-Padding und schreibt UTF-8-CSV mit Tab als Trennzeichen.

  Standard: ALLE *.txt des Ordners werden konvertiert (kein -Tables noetig).

  DATENHYGIENE: Sensible Credential-Spalten (Passwort-Hashes/-Codes, z. B. PWDSALTEDHASH,
  BCODE, PASSCODE, OCOD*/BCDA*/CODV*) werden bereits HIER verworfen (-DropColumnsLike) und
  landen so in keiner abgeleiteten CSV. Selbst wenn SE16 sie faelschlich mitexportiert hat,
  verlassen sie diesen Schritt nicht. Die Load-Skripte lesen ohnehin nur die benoetigten
  Spalten (Defense in Depth) -> Passwoerter erreichen den Graphen nie.

  Encoding der Quelle: Windows-1252 (Umlaute in Texten/Namen bleiben erhalten).
  Ausgabe: <tabellenname-kleingeschrieben>.csv im selben Ordner.

.PARAMETER Folder
  Ordner mit den .txt-Exporten (= dataset-Ordner unter data/import/).

.PARAMETER Tables
  Optionale Liste der Tabellen (ohne .txt). Ohne Angabe werden alle *.txt konvertiert.

.PARAMETER DropColumnsLike
  Wildcard-Muster (case-insensitiv) fuer Spalten, die NICHT in die CSV uebernommen werden.
  Default: bekannte Passwort-/Hash-/Code-Felder. Leeres Array = nichts verwerfen.

.PARAMETER RequiredTables
  Minimalset an Tabellen (ohne .txt), das fuer die Weiterverarbeitung (Load) vorhanden sein
  MUSS. Fehlt eine davon, bricht das Skript VOR der Konvertierung ab. Ohne Angabe wird die
  Liste aus -RequiredTablesConfig gelesen (zentrale Quelle).

.PARAMETER RequiredTablesConfig
  Pfad zur zentralen Tabellenliste (JSON mit 'required'/'optional'). Default:
  config/required_tables.json relativ zu diesem Skript.

.PARAMETER SkipRequiredCheck
  Ueberspringt die Minimalset-Pruefung (fuer ad-hoc Teilkonvertierung einzelner Tabellen).

.EXAMPLE
  # Ganzen Ordner konvertieren (empfohlen), sensible Spalten werden automatisch verworfen:
  .\load\Convert-Se16Export.ps1 -Folder data\import\acme
#>
param(
    [Parameter(Mandatory = $true)] [string] $Folder,
    [string[]] $Tables,
    [string] $OutDelimiter = "`t",
    [string[]] $DropColumnsLike = @('BCODE*', 'BCDA*', 'OCOD*', 'CODV*', 'PASSCODE', 'PWDSALTEDHASH', 'PWDHISTORY'),
    [string[]] $RequiredTables,
    [string] $RequiredTablesConfig = (Join-Path $PSScriptRoot '..\config\required_tables.json'),
    [switch] $SkipRequiredCheck
)

$src = [System.Text.Encoding]::GetEncoding(1252)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

if (-not (Test-Path -LiteralPath $Folder)) { throw "Ordner nicht gefunden: $Folder" }

# Tabellenliste aus zentraler Config laden (falls nicht explizit per -RequiredTables uebergeben).
$optionalTables = @()
if (-not $RequiredTables -or $RequiredTables.Count -eq 0) {
    if (Test-Path -LiteralPath $RequiredTablesConfig) {
        $cfg = Get-Content -LiteralPath $RequiredTablesConfig -Raw -Encoding UTF8 | ConvertFrom-Json
        $RequiredTables = @($cfg.required)
        $optionalTables = @($cfg.optional)
    }
    else {
        Write-Warning "Config nicht gefunden: $RequiredTablesConfig - verwende eingebauten Fallback."
        $RequiredTables = @('USR02', 'AGR_DEFINE', 'AGR_AGRS', 'AGR_USERS', 'AGR_PROF', 'UST04', 'AGR_1251', 'TSTCT', 'USOBT_C', 'UST10S', 'UST12')
    }
}

# Pflicht-Tabellen pruefen, BEVOR konvertiert wird (sonst scheitert spaeter der Load).
if (-not $SkipRequiredCheck) {
    $missing = @($RequiredTables | Where-Object { -not (Test-Path (Join-Path $Folder "$_.txt")) })
    if ($missing.Count -gt 0) {
        throw ("Minimalset unvollstaendig - fehlende Pflicht-Tabellen (.txt) in '" + $Folder + "': " +
            ($missing -join ', ') + ". Export vervollstaendigen oder -SkipRequiredCheck fuer Teilkonvertierung.")
    }
    Write-Output ("Minimalset vollstaendig: {0}/{0} Pflicht-Tabellen vorhanden." -f $RequiredTables.Count)
    if ($optionalTables.Count -gt 0) {
        $missOpt = @($optionalTables | Where-Object { -not (Test-Path (Join-Path $Folder "$_.txt")) })
        if ($missOpt.Count -gt 0) {
            Write-Output ("Hinweis: optionale Tabellen fehlen (Anreicherung entfaellt): " + ($missOpt -join ', '))
        }
    }
}

if (-not $Tables -or $Tables.Count -eq 0) {
    $Tables = Get-ChildItem -Path $Folder -Filter *.txt | ForEach-Object { $_.BaseName }
}

function Test-Sensitive([string] $name, [string[]] $patterns) {
    foreach ($p in $patterns) { if ($name -like $p) { return $true } }
    return $false
}

foreach ($t in $Tables) {
    $in = Join-Path $Folder "$t.txt"
    if (-not (Test-Path $in)) { Write-Warning "fehlt: $in"; continue }
    $out = Join-Path $Folder ($t.ToLower() + ".csv")

    $reader = New-Object System.IO.StreamReader($in, $src)
    $writer = New-Object System.IO.StreamWriter($out, $false, $utf8NoBom)
    $headerNames = @(); $dropped = @(); $keepIdx = $null; $rows = 0
    try {
        while ($null -ne ($line = $reader.ReadLine())) {
            if (-not $line.StartsWith("|")) { continue }   # Titel/Info/Trennlinien/Footer überspringen
            $parts = $line.Split([char]124)                # nach | trennen
            $parts = $parts[1..($parts.Length - 2)]        # führendes/abschließendes Leerfeld weg
            if ($parts.Length -gt 0 -and $parts[0].Trim() -eq "") {
                $parts = $parts[1..($parts.Length - 1)]    # leere Markierungsspalte weg
            }
            # Trim Fixbreiten-Padding; "-Zeichen entfernen (Tab-getrennt/unquotiert ->
            # LOAD CSV deutet " sonst als Quote und bricht ab).
            $fields = foreach ($p in $parts) { ($p.Trim() -replace '"', '') }

            if ($null -eq $keepIdx) {
                # erste |-Zeile = Kopfzeile: sensible Spalten ermitteln und ausschliessen
                $keepIdx = New-Object System.Collections.Generic.List[int]
                for ($i = 0; $i -lt $fields.Count; $i++) {
                    if (Test-Sensitive $fields[$i] $DropColumnsLike) { $dropped += $fields[$i] }
                    else { $keepIdx.Add($i) }
                }
                $headerNames = @($keepIdx | ForEach-Object { $fields[$_] })
                $writer.WriteLine([string]::Join($OutDelimiter, $headerNames))
            }
            else {
                $kept = foreach ($i in $keepIdx) { if ($i -lt $fields.Count) { $fields[$i] } else { "" } }
                $writer.WriteLine([string]::Join($OutDelimiter, $kept))
                $rows++
            }
        }
    }
    finally {
        $reader.Close(); $writer.Close()
    }
    Write-Output ("{0,-12} -> {1,-16} Spalten: {2,-3} Datenzeilen: {3}" -f `
            $t, (Split-Path $out -Leaf), $headerNames.Count, $rows)
    Write-Output ("              [{0}]" -f ([string]::Join(", ", $headerNames)))
    if ($dropped.Count -gt 0) {
        Write-Output ("              verworfen (sensibel): [{0}]" -f ([string]::Join(", ", $dropped)))
    }
}
