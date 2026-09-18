<#
.SYNOPSIS
  Baut install.exe/manage.exe aus install.ps1/manage.ps1 (ps2exe). Kein Schritt, den der
  Drittrechner selbst braucht -- die fertigen .exe kommen im Handoff-Paket mit.

.DESCRIPTION
  Ergaenzung zu den .ps1-Skripten (bleiben die gepflegte Quelle), nachdem Doppelklick auf .ps1 auf
  einem Drittrechner nicht zuverlaessig funktionierte: je nach Dateizuordnung oeffnet Windows .ps1
  standardmaessig im Editor statt es auszufuehren, und ein fehlender throw bei fehlenden
  Adminrechten liess ein Konsolenfenster kommentarlos verschwinden. .exe umgeht beides -- echtes
  Doppelklick-Ziel, `-requireAdmin` bettet eine UAC-Manifest-Anforderung ein (Windows fragt VOR
  dem Start nach Adminrechten, zuverlaessiger als ein Skript-interner Start-Process -Verb RunAs).
  install.ps1/manage.ps1 behalten ihre eigene Admin-Pruefung/Fallback-Anhebung trotzdem, falls
  jemand die .ps1-Quelle direkt statt der .exe ausfuehrt.

  Installiert bei Bedarf das ps2exe-Modul (PowerShell Gallery, -Scope CurrentUser, kein Admin
  noetig fuer den Build selbst).

.EXAMPLE
  .\build-exe.ps1
#>
$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable ps2exe)) {
    Write-Host "Installiere ps2exe-Modul (einmalig) ..." -ForegroundColor Cyan
    try { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop | Out-Null } catch {}
    Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
}
Import-Module ps2exe

$here = $PSScriptRoot

Write-Host "Baue install.exe ..." -ForegroundColor Cyan
Invoke-ps2exe -inputFile (Join-Path $here 'install.ps1') -outputFile (Join-Path $here 'install.exe') `
    -title 'IAM Installer' -description 'Native Windows-Installation der iam-App' `
    -company 'iam' -version '1.0.0.0' -requireAdmin -STA

Write-Host "Baue manage.exe ..." -ForegroundColor Cyan
Invoke-ps2exe -inputFile (Join-Path $here 'manage.ps1') -outputFile (Join-Path $here 'manage.exe') `
    -title 'IAM verwalten' -description 'Start/Stop/Update fuer die native iam-Installation' `
    -company 'iam' -version '1.0.0.0' -requireAdmin -STA -noConsole

Write-Host "`nFertig: install.exe und manage.exe liegen in $here" -ForegroundColor Green
