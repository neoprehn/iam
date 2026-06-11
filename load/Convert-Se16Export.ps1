<#
.SYNOPSIS
  Wandelt SE16-"unkonvertiert"-Listenexporte (.txt) in saubere CSV (Tab-getrennt, UTF-8) um.

.DESCRIPTION
  SE16/SE16N "Lokale Datei -> unkonvertiert" liefert ein fixbreites, Pipe-getrenntes
  Listenformat mit Titel-/Info-/Trennzeilen und einer leeren Markierungsspalte. Das ist
  nicht direkt LOAD-CSV-tauglich. Dieses Skript extrahiert Kopfzeile (= SAP-Feldnamen) und
  Datenzeilen, trimmt das Fixbreiten-Padding und schreibt UTF-8-CSV mit Tab als Trennzeichen.

  Encoding der Quelle: Windows-1252 (Umlaute in Texten/Namen bleiben erhalten).
  Ausgabe: <tabellenname-kleingeschrieben>.csv im selben Ordner.

.PARAMETER Folder
  Ordner mit den .txt-Exporten (= dataset-Ordner unter data/import/).

.PARAMETER Tables
  Optionale Liste der Tabellen (ohne .txt). Ohne Angabe werden alle *.txt konvertiert.

.EXAMPLE
  .\load\Convert-Se16Export.ps1 -Folder data\import\sachsenenergie `
     -Tables USR02,AGR_DEFINE,AGR_AGRS,AGR_USERS,ARG_PROF,UST04,USR11,AGR_1251,USOBT_C,TSTCT
#>
param(
    [Parameter(Mandatory = $true)] [string] $Folder,
    [string[]] $Tables,
    [string] $OutDelimiter = "`t"
)

$src = [System.Text.Encoding]::GetEncoding(1252)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

if (-not $Tables -or $Tables.Count -eq 0) {
    $Tables = Get-ChildItem -Path $Folder -Filter *.txt | ForEach-Object { $_.BaseName }
}

foreach ($t in $Tables) {
    $in = Join-Path $Folder "$t.txt"
    if (-not (Test-Path $in)) { Write-Warning "fehlt: $in"; continue }
    $out = Join-Path $Folder ($t.ToLower() + ".csv")

    $reader = New-Object System.IO.StreamReader($in, $src)
    $writer = New-Object System.IO.StreamWriter($out, $false, $utf8NoBom)
    $headerNames = @(); $rows = 0
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
            $writer.WriteLine([string]::Join($OutDelimiter, $fields))
            if ($headerNames.Count -eq 0) { $headerNames = $fields } else { $rows++ }
        }
    }
    finally {
        $reader.Close(); $writer.Close()
    }
    Write-Output ("{0,-12} -> {1,-16} Spalten: {2,-3} Datenzeilen: {3}" -f `
        $t, (Split-Path $out -Leaf), $headerNames.Count, $rows)
    Write-Output ("              [{0}]" -f ([string]::Join(", ", $headerNames)))
}
