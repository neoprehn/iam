<#
.SYNOPSIS
  Kleines GUI-Fenster zum Verwalten der nativen Windows-Installation per Klick (Start/Stop/
  Neustart, Update jetzt, Web-App oeffnen, Update-/Neo4j-Log ansehen, Ruleset-Junction verifizieren)
  -- Alternative zu den Einzel-PowerShell-Befehlen aus README.md fuer Nutzer, die keine Konsole
  bedienen wollen. Wird von install.ps1 als Desktop-Verknuepfung "IAM verwalten" angelegt.

.DESCRIPTION
  Liest Pfade aus install-state.json (von install.ps1 geschrieben, liegt neben diesem Skript,
  NICHT versioniert -- maschinenspezifisch) statt Parameter zu verlangen, damit die
  Desktop-Verknuepfung ohne Argumente funktioniert. Fordert sich selbst per UAC-Prompt Admin-
  rechte an, da Start-Service/Stop-Service und Scheduled-Task-Steuerung das brauchen.
#>
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-Admin)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList `
        "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
    exit
}

$stateFile = Join-Path $PSScriptRoot 'install-state.json'
if (-not (Test-Path $stateFile)) {
    [System.Windows.Forms.MessageBox]::Show(
        "install-state.json fehlt neben manage.ps1.`nBitte zuerst install.ps1 ausfuehren.",
        'IAM verwalten', 'OK', 'Error') | Out-Null
    exit 1
}
$state = Get-Content $stateFile -Raw | ConvertFrom-Json
$repo = $state.RepoDir
$neoHome = $state.Neo4jHome

$envPath = Join-Path $repo '.env'
function Get-EnvVal([string] $name) {
    if (-not (Test-Path $envPath)) { return $null }
    $line = Get-Content $envPath | Where-Object { $_ -match "^$name=" } | Select-Object -First 1
    if ($line) { ($line -replace "^$name=", '').Trim() } else { $null }
}
$neoPw = Get-EnvVal 'NEO4J_PASSWORD'
$logFile = Join-Path $repo 'data\logs\windows-update.log'

# ---------- Form ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'IAM verwalten'
$form.ClientSize = New-Object System.Drawing.Size(610, 600)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false

$fontBold = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)

$lblNeo = New-Object System.Windows.Forms.Label
$lblNeo.Location = New-Object System.Drawing.Point(15, 15)
$lblNeo.Size = New-Object System.Drawing.Size(280, 20)
$lblNeo.Font = $fontBold
$form.Controls.Add($lblNeo)

$lblBackend = New-Object System.Windows.Forms.Label
$lblBackend.Location = New-Object System.Drawing.Point(15, 40)
$lblBackend.Size = New-Object System.Drawing.Size(280, 20)
$lblBackend.Font = $fontBold
$form.Controls.Add($lblBackend)

$lblUpdate = New-Object System.Windows.Forms.Label
$lblUpdate.Location = New-Object System.Drawing.Point(15, 65)
$lblUpdate.Size = New-Object System.Drawing.Size(580, 20)
$lblUpdate.ForeColor = [System.Drawing.Color]::Gray
$form.Controls.Add($lblUpdate)

function New-Btn([string] $text, [int] $x, [int] $y, [int] $w = 130) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Size = New-Object System.Drawing.Size($w, 30)
    $form.Controls.Add($b)
    return $b
}

$btnStart = New-Btn 'Start' 15 95 110
$btnStop = New-Btn 'Stop' 135 95 110
$btnRestart = New-Btn 'Neu starten' 255 95 140
$btnRefresh = New-Btn 'Status aktualisieren' 405 95 190

$btnWeb = New-Btn 'Web-App oeffnen' 15 135 150
$btnUpdate = New-Btn 'Jetzt aktualisieren' 175 135 150

$btnUpdLog = New-Btn 'Update-Log anzeigen' 15 175 150
$btnNeoLog = New-Btn 'Neo4j-Log anzeigen' 175 175 150
$btnVerify = New-Btn 'Verifizieren (Rulesets)' 335 175 190

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.ReadOnly = $true
$txtLog.WordWrap = $false
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)
$txtLog.Location = New-Object System.Drawing.Point(15, 215)
$txtLog.Size = New-Object System.Drawing.Size(580, 370)
$txtLog.Anchor = 'Top,Bottom,Left,Right'
$form.Controls.Add($txtLog)

function Add-Log([string] $text) {
    $txtLog.AppendText("$text`r`n")
    $txtLog.SelectionStart = $txtLog.TextLength
    $txtLog.ScrollToCaret()
}

function Update-StatusLabels {
    $svc = Get-Service -Name 'neo4j' -ErrorAction SilentlyContinue
    if ($svc) {
        $lblNeo.Text = "Neo4j: $($svc.Status)"
        $lblNeo.ForeColor = if ($svc.Status -eq 'Running') { [System.Drawing.Color]::DarkGreen } else { [System.Drawing.Color]::Firebrick }
    } else {
        $lblNeo.Text = 'Neo4j: Dienst nicht gefunden'
        $lblNeo.ForeColor = [System.Drawing.Color]::Firebrick
    }
    $task = Get-ScheduledTask -TaskName 'IAM-Backend' -ErrorAction SilentlyContinue
    if ($task) {
        $lblBackend.Text = "Backend: $($task.State)"
        $lblBackend.ForeColor = if ($task.State -eq 'Running') { [System.Drawing.Color]::DarkGreen } else { [System.Drawing.Color]::Firebrick }
    } else {
        $lblBackend.Text = 'Backend: Task nicht gefunden'
        $lblBackend.ForeColor = [System.Drawing.Color]::Firebrick
    }
    $updTask = Get-ScheduledTask -TaskName 'IAM-Update' -ErrorAction SilentlyContinue
    if ($updTask) {
        $info = $updTask | Get-ScheduledTaskInfo
        if ($info.LastRunTime) {
            $lblUpdate.Text = "Letztes Update: {0:g}  (Ergebnis-Code 0x{1:X8})" -f $info.LastRunTime, $info.LastTaskResult
        } else {
            $lblUpdate.Text = 'Letztes Update: noch nie gelaufen'
        }
    } else {
        $lblUpdate.Text = 'Update-Task nicht gefunden'
    }
}
Update-StatusLabels

$btnRefresh.Add_Click({ Update-StatusLabels })

$btnStart.Add_Click({
    Add-Log '-- Starte Neo4j + Backend --'
    Start-Service -Name 'neo4j' -ErrorAction SilentlyContinue
    Start-ScheduledTask -TaskName 'IAM-Backend' -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Update-StatusLabels
    Add-Log 'Fertig.'
})
$btnStop.Add_Click({
    Add-Log '-- Stoppe Backend + Neo4j --'
    Stop-ScheduledTask -TaskName 'IAM-Backend' -ErrorAction SilentlyContinue
    Stop-Service -Name 'neo4j' -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Update-StatusLabels
    Add-Log 'Fertig.'
})
$btnRestart.Add_Click({
    Add-Log '-- Neustart Neo4j + Backend --'
    Stop-ScheduledTask -TaskName 'IAM-Backend' -ErrorAction SilentlyContinue
    Restart-Service -Name 'neo4j' -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    Start-ScheduledTask -TaskName 'IAM-Backend' -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Update-StatusLabels
    Add-Log 'Fertig.'
})
$btnWeb.Add_Click({ Start-Process 'http://localhost:8000/' })

# "Jetzt aktualisieren" startet update.ps1 als Hintergrund-Job (damit das Fenster nicht einfriert)
# und pollt die Log-Datei per Timer live in die Textbox -- Write-Host aus einem Job liesse sich
# sonst nicht sauber abgreifen, die Datei ist ohnehin die verlaessliche Quelle (s. update.ps1).
$script:updateJob = $null
$script:logOffset = 0
$updateTimer = New-Object System.Windows.Forms.Timer
$updateTimer.Interval = 700
$updateTimer.Add_Tick({
    if (Test-Path $logFile) {
        $stream = [System.IO.File]::Open($logFile, 'Open', 'Read', 'ReadWrite')
        $stream.Seek($script:logOffset, 'Begin') | Out-Null
        $reader = New-Object System.IO.StreamReader($stream)
        $new = $reader.ReadToEnd()
        $script:logOffset = $stream.Position
        $reader.Close(); $stream.Close()
        if ($new) { Add-Log $new.TrimEnd() }
    }
    if ($script:updateJob -and $script:updateJob.State -in 'Completed', 'Failed', 'Stopped') {
        $updateTimer.Stop()
        # update.ps1 schreibt sein eigenes Fortschritts-Log bereits in $logFile (oben live
        # mitgelesen) -- Receive-Job faengt hier nur einen unerwarteten Absturz AUSSERHALB dieses
        # Loggings ab (z.B. ein nicht abgefangener Fehler vor dem ersten Log-Write), damit der
        # Job nicht stillschweigend im Fehlerfall verschwindet.
        $jobOutput = Receive-Job $script:updateJob -ErrorAction SilentlyContinue 2>&1
        if ($jobOutput) { $jobOutput | ForEach-Object { Add-Log "  [Job] $_" } }
        Remove-Job $script:updateJob -ErrorAction SilentlyContinue
        Add-Log "-- Update-Lauf beendet (Status: $($script:updateJob.State)) --"
        $btnUpdate.Enabled = $true
        Update-StatusLabels
    }
})
$btnUpdate.Add_Click({
    $btnUpdate.Enabled = $false
    Add-Log '-- Update gestartet (git pull + Neustart) --'
    $script:logOffset = if (Test-Path $logFile) { (Get-Item $logFile).Length } else { 0 }
    $updateScript = Join-Path $PSScriptRoot 'update.ps1'
    $script:updateJob = Start-Job -FilePath $updateScript -ArgumentList $repo
    $updateTimer.Start()
})

$btnUpdLog.Add_Click({
    $txtLog.Clear()
    Add-Log "== Update-Log: $logFile (letzte 300 Zeilen) =="
    if (Test-Path $logFile) { Get-Content $logFile -Tail 300 | ForEach-Object { Add-Log $_ } }
    else { Add-Log '(noch keine Log-Datei -- Update wurde noch nie ausgefuehrt)' }
})
$btnNeoLog.Add_Click({
    $neoLog = Join-Path $neoHome 'logs\neo4j.log'
    $txtLog.Clear()
    Add-Log "== Neo4j-Log: $neoLog (letzte 300 Zeilen) =="
    Add-Log "(ausfuehrlicheres Log bei Bedarf: $(Join-Path $neoHome 'logs\debug.log'))"
    if (Test-Path $neoLog) { Get-Content $neoLog -Tail 300 | ForEach-Object { Add-Log $_ } }
    else { Add-Log '(Log-Datei nicht gefunden)' }
})
$btnVerify.Add_Click({
    $txtLog.Clear()
    Add-Log '== Verifizieren: Ruleset-Junction (apoc.load.json) =='
    $cypherShell = Join-Path $neoHome 'bin\cypher-shell.bat'
    if (-not (Test-Path $cypherShell)) { Add-Log "FEHLER: cypher-shell nicht gefunden unter $cypherShell"; return }
    if (-not $neoPw) { Add-Log "FEHLER: NEO4J_PASSWORD fehlt in $envPath"; return }
    $query = "CALL apoc.load.json('file:///rules/KPMG_R3/legends.json') YIELD value RETURN count(value) AS n;"
    $out = & $cypherShell -u neo4j -p $neoPw $query 2>&1 | Out-String
    Add-Log $out.TrimEnd()
    if ($out -match '(?m)^\s*[1-9]\d*\s*$' -and $out -notmatch 'Error|Exception') {
        Add-Log 'ERGEBNIS: OK -- Junction funktioniert, Rulesets koennen geladen werden.'
    } else {
        Add-Log 'ERGEBNIS: FEHLGESCHLAGEN -- s. README.md, Abschnitt "Verifizieren"/"Troubleshooting".'
    }
})

# Leichter Auto-Refresh der Statuszeilen, unabhaengig vom Update-Log-Timer.
$autoRefresh = New-Object System.Windows.Forms.Timer
$autoRefresh.Interval = 4000
$autoRefresh.Add_Tick({ Update-StatusLabels })
$autoRefresh.Start()

[void]$form.ShowDialog()
