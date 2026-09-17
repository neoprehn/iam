<#
.SYNOPSIS
  Native Windows-Setup fuer die iam-App auf einem Drittrechner ohne Docker.

.DESCRIPTION
  Abweichung vom container-only-Standardpfad (s. Haupt-README.md) fuer Maschinen, auf denen kein
  Docker Desktop installiert werden kann. Installiert/prueft Voraussetzungen (Git, Python 3.12,
  Java 21) per winget, klont/pullt das Repo, legt ein venv an, laedt + konfiguriert Neo4j Community
  Server als Windows-Dienst (Speicher-/APOC-/Import-Einstellungen 1:1 aus docker-compose.yml
  uebernommen) und richtet einen Scheduled Task fuer das Backend (uvicorn) ein, der bei jedem
  Systemstart automatisch laeuft, auch ohne Login. Zusaetzlich einen taeglichen Update-Task
  (git pull + Neustart, s. update.ps1) sowie eine Desktop-Verknuepfung "IAM verwalten" fuer ein
  kleines GUI-Fenster (manage.ps1: Start/Stop/Neustart, Jetzt aktualisieren, Web-App oeffnen,
  Logs ansehen, Ruleset-Junction verifizieren -- fuer Nutzer, die keine PowerShell bedienen
  wollen). Idempotent: mehrfaches Ausfuehren ueberspringt bereits erledigte Schritte.

  WICHTIG (s. README.md, Abschnitt "Verifizieren" + "Troubleshooting"): Die Ruleset-JSON-Dateien
  unter rules/ werden von Neo4j selbst per apoc.load.json('file:///rules/...') gelesen (identischer
  fester Pfad wie im Docker-Bind-Mount ./rules:/rules:ro, s. cypher/ruleset/load_ruleset.cypher).
  Ohne Docker loest die JVM diesen Pfad drive-relativ zum Arbeitsverzeichnis des Neo4j-Dienstes auf
  -- dieses Skript legt dafuer eine NTFS-Junction <RepoDrive>:\rules an und installiert Neo4j
  bewusst auf derselben Disk wie das Repo. Nach der Installation unbedingt den Verifizieren-Schritt
  aus der README durchgehen.

.PARAMETER InstallDir   Zielordner fuer den Git-Clone (Default: C:\iam).
.PARAMETER RepoUrl      Git-Remote-URL (Default: das Haupt-Repo).
.PARAMETER Neo4jVersion Neo4j-Server-Version -- MUSS mit dem Image-Tag in docker-compose.yml
                        uebereinstimmen (aktuell 5.26.27), sonst laufen Docker- und native
                        Installation mit unterschiedlichem Schema-/APOC-Verhalten auseinander.
.PARAMETER ApocVersion  APOC-Core-Release-Tag (github.com/neo4j/apoc/releases). Default ist ein
                        zu Neo4jVersion passender Best-Guess -- schlaegt der Download fehl, in der
                        Fehlermeldung genannte Release-Seite pruefen und Parameter anpassen.
.PARAMETER HeapSizeGb   Neo4j Heap (initial=max). Der Docker-Dev-Rechner nutzt grosszuegige 8G;
                        hier bewusst kleiner default, auf echter Hardware ggf. erhoehen.
.PARAMETER PageCacheGb  Neo4j Pagecache.

.EXAMPLE
  .\deploy\windows-native\install.ps1
.EXAMPLE
  .\deploy\windows-native\install.ps1 -InstallDir D:\iam -HeapSizeGb 4 -PageCacheGb 4
#>
param(
    [string] $InstallDir = 'C:\iam',
    [string] $RepoUrl = 'https://github.com/neoprehn/iam.git',
    [string] $Neo4jVersion = '5.26.27',
    [string] $ApocVersion = '5.26.0',
    [int] $HeapSizeGb = 2,
    [int] $PageCacheGb = 2
)
# 'Stop': dies ist eine einmalige, admin-rechte-benoetigende Setup-Kette -- anders als bei
# run_import.ps1 (Continue + $LASTEXITCODE-Checks) soll hier jeder Fehler sofort abbrechen statt
# mit halb fertigem Zustand weiterzulaufen.
$ErrorActionPreference = 'Stop'

function Write-Step([string] $msg) { Write-Host "`n== $msg ==" -ForegroundColor Cyan }
function Test-Cmd([string] $name) { [bool](Get-Command $name -ErrorAction SilentlyContinue) }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-Admin)) {
    throw "Bitte als Administrator ausfuehren (Rechtsklick auf PowerShell -> 'Als Administrator ausfuehren')."
}

# ---------- 0. Zielordner waehlen (nur wenn -InstallDir nicht explizit angegeben wurde) ----------
# $PSBoundParameters unterscheidet "Parameter-Default verwendet" von "Nutzer hat -InstallDir
# gesetzt" -- fuer automatisierte/nicht-interaktive Laeufe (z.B. per Remote-Skript) bleibt der
# stille Default C:\iam nutzbar, ohne dass ein Dialogfenster den Lauf blockiert.
Add-Type -AssemblyName System.Windows.Forms
if (-not $PSBoundParameters.ContainsKey('InstallDir')) {
    try {
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = "Zielordner fuer die iam-Installation waehlen`n(das Repo wird darin als Unterordner 'iam' angelegt -- Abbrechen = Standard $InstallDir verwenden)"
        $dlg.ShowNewFolderButton = $true
        if (Test-Path 'C:\') { $dlg.SelectedPath = 'C:\' }
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and $dlg.SelectedPath) {
            $InstallDir = Join-Path $dlg.SelectedPath 'iam'
            Write-Host "Zielordner gewaehlt: $InstallDir"
        } else {
            Write-Host "Kein Ordner gewaehlt, verwende Standard: $InstallDir"
        }
    } catch {
        Write-Host "Ordnerauswahl-Dialog nicht verfuegbar ($($_.Exception.Message)), verwende Standard: $InstallDir"
    }
}

# ---------- 0b. OneDrive-Warnung ----------
# SAP-Extrakte (data/import), Backups und .env landen direkt unter $InstallDir -- ein
# OneDrive-synchronisierter Pfad wuerde sie automatisch in die Microsoft-Cloud hochladen. Das
# verletzt die Vertrauensgrenze dieses Projekts (Mandantendaten bleiben lokal, s. Haupt-README.md)
# unabhaengig von der bekannten Performance-Problematik (haeufige fsync-Schreibzugriffe, s. auch
# der Kommentar zum DB-Volume in docker-compose.yml). Neo4j selbst landet zwar ausserhalb davon
# (Laufwerkswurzel, s. Schritt 5), aber $InstallDir ist der eigentliche Risikoort -- deshalb hart
# nachfragen statt nur zu warnen, auch wenn -InstallDir explizit als Parameter gesetzt wurde.
$oneDriveRoots = @($env:OneDrive, $env:OneDriveCommercial) | Where-Object { $_ }
$looksLikeOneDrive = ($InstallDir -match '(?i)onedrive') -or
    ($oneDriveRoots | Where-Object { $InstallDir -like "$_*" })
if ($looksLikeOneDrive) {
    $msg = "Der gewaehlte Zielordner`n`n  $InstallDir`n`nliegt vermutlich unter OneDrive. " +
           "SAP-Extrakte, Backups und Zugangsdaten wuerden dann automatisch in die " +
           "Microsoft-Cloud synchronisiert -- das verletzt die Vertrauensgrenze dieses Projekts " +
           "(Mandantendaten bleiben lokal) und macht Schreibzugriffe zudem spuerbar langsamer." +
           "`n`nTrotzdem an diesem Ort installieren?"
    $res = [System.Windows.Forms.MessageBox]::Show($msg, 'Warnung: OneDrive-Pfad',
        [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
    if ($res -ne [System.Windows.Forms.DialogResult]::Yes) {
        throw "Abgebrochen -- bitte einen lokalen, nicht synchronisierten Pfad waehlen (z. B. C:\iam)."
    }
    Write-Host "OneDrive-Warnung bestaetigt, fahre trotzdem fort." -ForegroundColor Yellow
}

# ---------- 1. Voraussetzungen (Git, Python, Java) ----------
Write-Step "1/8 Voraussetzungen pruefen"
if (-not (Test-Cmd git)) {
    if (Test-Cmd winget) { winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements }
    else { throw "git fehlt und winget ist nicht verfuegbar -- bitte manuell installieren: https://git-scm.com/download/win" }
}
if (-not (Test-Cmd python)) {
    if (Test-Cmd winget) { winget install --id Python.Python.3.12 -e --accept-source-agreements --accept-package-agreements }
    else { throw "python fehlt und winget ist nicht verfuegbar -- bitte manuell installieren: https://www.python.org/downloads/" }
}
if (-not (Test-Cmd java)) {
    if (Test-Cmd winget) { winget install --id EclipseAdoptium.Temurin.21.JRE -e --accept-source-agreements --accept-package-agreements }
    else { throw "java fehlt und winget ist nicht verfuegbar -- bitte manuell installieren: https://adoptium.net/de/temurin/releases/?version=21" }
}
# winget-Installationen aktualisieren PATH erst in einer neuen Sitzung -- fuer den Rest dieses
# Laufs aus Machine+User-PATH nachziehen, damit git/python/java sofort nutzbar sind.
$env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
            [System.Environment]::GetEnvironmentVariable('Path', 'User')
foreach ($c in 'git', 'python', 'java') {
    if (-not (Test-Cmd $c)) {
        throw "$c weiterhin nicht gefunden -- neue PowerShell-Sitzung (als Administrator) oeffnen und Skript erneut starten."
    }
}

# ---------- 2. Repo klonen/aktualisieren ----------
Write-Step "2/8 Repo unter $InstallDir"
if (Test-Path (Join-Path $InstallDir '.git')) {
    Write-Host "Repo existiert bereits, pull statt clone."
    git -C $InstallDir pull --ff-only
} else {
    git clone $RepoUrl $InstallDir
}
$repo = (Resolve-Path $InstallDir).Path

# ---------- 3. .env ----------
Write-Step "3/8 .env"
$envPath = Join-Path $repo '.env'
if (-not (Test-Path $envPath)) {
    Copy-Item (Join-Path $repo '.env.example') $envPath
    $pwChars = (48..57) + (65..90) + (97..122)
    $pw = -join ((1..24) | ForEach-Object { [char]($pwChars | Get-Random) })
    (Get-Content $envPath) -replace 'NEO4J_PASSWORD=.*', "NEO4J_PASSWORD=$pw" | Set-Content $envPath
    Write-Host "Neues zufaelliges Passwort in $envPath erzeugt."
} else {
    Write-Host ".env existiert bereits, unveraendert gelassen."
}
function Get-EnvVal([string] $name, [string] $path) {
    $line = Get-Content $path | Where-Object { $_ -match "^$name=" } | Select-Object -First 1
    if ($line) { ($line -replace "^$name=", '').Trim() } else { $null }
}
$neoPw = Get-EnvVal 'NEO4J_PASSWORD' $envPath
if (-not $neoPw) { throw "NEO4J_PASSWORD fehlt in $envPath" }

# ---------- 4. Python venv ----------
Write-Step "4/8 Python-venv (.venv-win)"
$venv = Join-Path $repo '.venv-win'
if (-not (Test-Path $venv)) { python -m venv $venv }
& "$venv\Scripts\pip.exe" install --upgrade pip -q
& "$venv\Scripts\pip.exe" install -r (Join-Path $repo 'backend\requirements.txt') -q

# ---------- 5. Neo4j Community Server als Windows-Dienst ----------
Write-Step "5/8 Neo4j Community $Neo4jVersion als Windows-Dienst"
# Bewusst auf derselben Disk wie das Repo installiert -- s. Kommentar zur rules-Junction unten.
$repoDrive = Split-Path $repo -Qualifier   # z.B. "D:"
$neoRoot = Join-Path "$repoDrive\" 'neo4j'
$neoHome = Join-Path $neoRoot "neo4j-community-$Neo4jVersion"
if (-not (Test-Path $neoHome)) {
    New-Item -ItemType Directory -Force -Path $neoRoot | Out-Null
    $zipUrl = "https://dist.neo4j.org/neo4j-community-$Neo4jVersion-windows.zip"
    $zipPath = Join-Path $neoRoot "neo4j-community-$Neo4jVersion.zip"
    Write-Host "Lade $zipUrl ..."
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath
    Expand-Archive -Path $zipPath -DestinationPath $neoRoot -Force
    Remove-Item $zipPath
}
if (-not (Test-Path $neoHome)) { throw "Neo4j-Entpackung fehlgeschlagen -- $neoHome nicht gefunden." }

# APOC-Plugin (im Docker-Image per NEO4J_PLUGINS automatisch geladen, hier manuell).
$apocJar = Join-Path $neoHome "plugins\apoc-$ApocVersion-core.jar"
if (-not (Test-Path $apocJar)) {
    $apocUrl = "https://github.com/neo4j/apoc/releases/download/$ApocVersion/apoc-$ApocVersion-core.jar"
    Write-Host "Lade APOC $ApocVersion ..."
    try {
        Invoke-WebRequest -Uri $apocUrl -OutFile $apocJar
    } catch {
        throw ("APOC-Download fehlgeschlagen ($apocUrl). Passende Version zu Neo4j $Neo4jVersion " +
               "auf https://github.com/neo4j/apoc/releases pruefen und -ApocVersion setzen.")
    }
}

# neo4j.conf -- Einstellungen 1:1 aus docker-compose.yml (environment: NEO4J_*) uebertragen.
$confPath = Join-Path $neoHome 'conf\neo4j.conf'
$importDir = (Join-Path $repo 'data\import') -replace '\\', '/'
$marker = '# --- iam windows-native (von install.ps1 verwaltet, s. deploy/windows-native/README.md) ---'
$confBody = @"

$marker
server.directories.import=$importDir
dbms.security.procedures.unrestricted=apoc.*
apoc.import.file.enabled=true
apoc.import.file.use_neo4j_config=false
server.memory.heap.initial_size=${HeapSizeGb}G
server.memory.heap.max_size=${HeapSizeGb}G
server.memory.pagecache.size=${PageCacheGb}G
dbms.memory.transaction.total.max=0
"@
$existing = Get-Content $confPath -Raw
if ($existing -notmatch [regex]::Escape($marker)) {
    Add-Content -Path $confPath -Value $confBody
    Write-Host "neo4j.conf ergaenzt (Marker: '$marker')."
} else {
    Write-Host "neo4j.conf enthaelt bereits den iam-Block, unveraendert gelassen (bei Bedarf manuell anpassen)."
}

New-Item -ItemType Directory -Force -Path (Join-Path $repo 'data\import') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $repo 'data\logs') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $repo 'backups') | Out-Null

# Junction <repoDrive>:\rules -> <repo>\rules. Grund: cypher/ruleset/load_ruleset.cypher liest
# Rulesets ueber apoc.load.json('file:///rules/' + ...) -- exakt derselbe feste Pfad wie im
# Docker-Bind-Mount ./rules:/rules:ro. Ohne Drive-Letter loest die JVM diesen Pfad drive-relativ
# zum Arbeitsverzeichnis des startenden Prozesses auf; der Neo4j-Dienst startet mit CWD = eigener
# Installationsordner -> Junction muss auf DERSELBEN Disk wie $neoHome liegen (hier sichergestellt,
# da $neoRoot bewusst auf $repoDrive liegt). Falls Neo4j spaeter auf eine andere Disk verschoben
# wird, Junction dort manuell nachziehen (s. README.md, Troubleshooting).
$rulesJunction = Join-Path "$repoDrive\" 'rules'
if (-not (Test-Path $rulesJunction)) {
    cmd /c mklink /J "$rulesJunction" "$repo\rules" | Out-Null
    Write-Host "Junction angelegt: $rulesJunction -> $repo\rules"
} elseif ((Get-Item $rulesJunction).LinkType -ne 'Junction') {
    Write-Warning "$rulesJunction existiert bereits und ist KEINE Junction -- Ruleset-Laden wird vermutlich fehlschlagen. Manuell pruefen (s. README.md, Troubleshooting)."
} else {
    Write-Host "Junction existiert bereits: $rulesJunction"
}

# Initiales Passwort setzen -- geht nur vor dem allerersten Start (vor Anlage von data\dbms).
$dbmsDataDir = Join-Path $neoHome 'data\dbms'
if (-not (Test-Path $dbmsDataDir)) {
    Write-Host "Setze initiales Neo4j-Passwort ..."
    & "$neoHome\bin\neo4j-admin.bat" dbms set-initial-password $neoPw
}

# Als Windows-Dienst registrieren + starten.
$svc = Get-Service -Name 'neo4j' -ErrorAction SilentlyContinue
if (-not $svc) {
    & "$neoHome\bin\neo4j.bat" install-service
    Start-Sleep -Seconds 2
}
Set-Service -Name 'neo4j' -StartupType Automatic
Start-Service -Name 'neo4j'
Write-Host "Neo4j-Dienst gestartet (kann beim ersten Start 30-60s brauchen)."

# ---------- 6. Backend als Scheduled Task ----------
Write-Step "6/8 Backend-Scheduled-Task"
$startScript = Join-Path $PSScriptRoot 'start-backend.ps1'
$taskName = 'IAM-Backend'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$startScript`" -RepoDir `"$repo`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
# MultipleInstances IgnoreNew: verhindert einen zweiten parallelen uvicorn-Prozess, falls z.B. das
# manage.ps1-Fenster "Start" klickt, waehrend der Task bereits laeuft.
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -MultipleInstances IgnoreNew
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings | Out-Null
Start-ScheduledTask -TaskName $taskName
Write-Host "Scheduled Task '$taskName' angelegt und gestartet (laeuft bei jedem Systemstart automatisch, auch ohne Login)."

# ---------- 7. Auto-Update-Task ----------
Write-Step "7/8 Taeglicher Auto-Update-Task"
$updateScript = Join-Path $PSScriptRoot 'update.ps1'
$updTaskName = 'IAM-Update'
$updAction = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$updateScript`" -RepoDir `"$repo`""
$updTrigger = New-ScheduledTaskTrigger -Daily -At 6am
$updPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
# IgnoreNew: verhindert, dass der taegliche Trigger und ein manueller "Jetzt aktualisieren"-Klick
# in manage.ps1 sich ueberlappen (git-Operationen vertragen sich nicht mit Parallellauf).
$updSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew
if (Get-ScheduledTask -TaskName $updTaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $updTaskName -Confirm:$false
}
Register-ScheduledTask -TaskName $updTaskName -Action $updAction -Trigger $updTrigger `
    -Principal $updPrincipal -Settings $updSettings | Out-Null
Write-Host "Taeglicher Update-Task '$updTaskName' (06:00 Uhr) angelegt -- manuell sofort ausloesen: Start-ScheduledTask -TaskName $updTaskName"

# ---------- 8. Management-GUI: Zustand + Desktop-Verknuepfung ----------
Write-Step "8/8 Management-Fenster (manage.ps1)"
$stateFile = Join-Path $PSScriptRoot 'install-state.json'
[PSCustomObject]@{
    RepoDir      = $repo
    Neo4jHome    = $neoHome
    Neo4jVersion = $Neo4jVersion
} | ConvertTo-Json | Set-Content -Path $stateFile -Encoding UTF8

$manageScript = Join-Path $PSScriptRoot 'manage.ps1'
$shortcutPath = Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'IAM verwalten.lnk'
$wsh = New-Object -ComObject WScript.Shell
$shortcut = $wsh.CreateShortcut($shortcutPath)
$shortcut.TargetPath = 'powershell.exe'
$shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$manageScript`""
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.IconLocation = 'shell32.dll,13'
$shortcut.Description = 'IAM Backend/Neo4j starten, stoppen, aktualisieren'
$shortcut.Save()
Write-Host "Desktop-Verknuepfung 'IAM verwalten' angelegt (fuer alle Benutzer)."

Write-Host "`nFertig. Web-App: http://localhost:8000/  |  Neo4j Browser: http://localhost:7474" -ForegroundColor Green
Write-Host "Naechster Schritt: README.md in diesem Ordner lesen, Abschnitt 'Verifizieren' (Ruleset-Junction testen)." -ForegroundColor Yellow
