# Native Windows-Installation (ohne Docker)

Der Standardpfad ist **container-only** über Docker Desktop/WSL2 (s. [Architektur](architektur.md)
und die Haupt-`README.md`). Für genau einen Fall gibt es eine bewusste, zusätzliche Abweichung
davon: einen Drittrechner, auf dem Docker Desktop nicht installiert werden darf oder kann, die
einzelnen Komponenten (Python, Java, Neo4j) aber schon. Skripte, vollständige Anleitung und
Troubleshooting liegen im Repo unter [`deploy/windows-native/`][repo-deploy] — diese Seite
beschreibt Zweck, Ablauf und die Vertrauensgrenze dafür.

[repo-deploy]: https://github.com/neoprehn/iam/tree/main/deploy/windows-native

## Was entsteht

- **Neo4j Community Server** als native Windows-Dienst (kein Container) — Speicher-/APOC-/
  Import-Einstellungen sind 1:1 aus `docker-compose.yml` übernommen, damit sich Docker- und
  native Installation fachlich identisch verhalten.
- **Backend** (`uvicorn`) als Scheduled Task, der bei jedem Systemstart automatisch läuft, auch
  ohne Login — funktional das Windows-Äquivalent zum `iam-backend`-Container.
- Ein **täglicher Update-Task**: `git fetch` + `merge --ff-only`, Python-Abhängigkeiten
  synchronisieren, Backend neu starten. Bewusst ein einfacher Pull statt eines echten
  CI/CD-Build-Servers — kein zusätzlicher Betriebsaufwand, Code kommt unverändert aus dem
  Git-Repo. Bricht ab (statt zu überschreiben), wenn der lokale Stand nicht per Fast-Forward
  aktualisierbar ist.
- Ein kleines **Management-Fenster** ("IAM verwalten", Desktop-Verknüpfung) für Start/Stop/
  Neustart, "Jetzt aktualisieren", Web-App öffnen, Update-/Neo4j-Log ansehen und einen
  Verifizieren-Klick — ohne PowerShell bedienen zu müssen.

Das Paket (`install.ps1`, `manage.ps1`, `update.ps1`, `start-backend.ps1`) ist eigenständig
lauffähig: `install.ps1` klont die App selbst per `git clone`. Ein vorheriger vollständiger
Checkout ist nicht nötig — die vier Skripte reichen, z. B. als ZIP an den Drittrechner verschickt.

## Installation

Als Administrator ausführen:

```powershell
.\install.ps1
```

Ohne `-InstallDir` öffnet sich ein Ordnerauswahl-Dialog für den Zielort (Abbrechen verwendet den
Standard `C:\iam`). Das Skript ist idempotent — mehrfaches Ausführen überspringt bereits erledigte
Schritte.

:::{admonition} Vertrauensgrenze: Zielordner nicht unter OneDrive wählen
:class: important

Der gewählte Zielordner enthält SAP-Extrakte, Backups und Zugangsdaten — also echte
Mandantendaten (s. u., "Wo liegen die Daten?"). Ein OneDrive-synchronisierter Pfad würde diese
automatisch in die Microsoft-Cloud hochladen — das ist kein Performance-Detail, sondern verletzt
die Vertrauensgrenze dieses Projekts (Mandantendaten verlassen die lokale Maschine nie).
`install.ps1` erkennt einen OneDrive-Pfad automatisch und fragt vor der Installation explizit
nach; Standard-Antwort ist "Nein". Empfehlung: ein einfacher lokaler Pfad wie `C:\iam`.
:::

Direkt nach der Installation den **Verifizieren-Schritt** durchgehen (README, Abschnitt
"Verifizieren"): Die Ruleset-Dateien unter `rules/` liest Neo4j über einen festen Pfad
(`apoc.load.json('file:///rules/...')`, identisch zum Docker-Bind-Mount), den `install.ps1` ohne
Container über eine NTFS-Junction nachbildet. Das ist die einzige nicht-triviale Annahme in diesem
Setup und lässt sich mit einem einzelnen `cypher-shell`-Befehl direkt gegentesten.

## Wo liegen die Daten?

Alles, was pro Installation lokal entsteht, hängt an **einem** Ort — dem gewählten Zielordner
(`$InstallDir`, Standard `C:\iam`):

| Was | Wo | Im Git? |
|---|---|---|
| SAP-Extrakte (Rohdaten) | `<InstallDir>\data\import` | Nein (gitignored) |
| Backups (Dataset-/Lauf-Zips) | `<InstallDir>\backups` | Nein (gitignored) |
| Zugangsdaten (`NEO4J_PASSWORD`) | `<InstallDir>\.env` | Nein (gitignored) |
| App-Code (Backend/Frontend/Cypher/Regeln) | `<InstallDir>\...` | Ja |

Die **Neo4j-Datenbank selbst** liegt bewusst außerhalb von `$InstallDir`, direkt unter der
Laufwerkswurzel (`<Laufwerk>:\neo4j\neo4j-community-<Version>\...`) — technisch wegen der
rules-Junction, praktisch aber auch ein zusätzlicher Schutz: Selbst wenn `$InstallDir` versehentlich
in einem synchronisierten Ordner läge, bliebe die Datenbank davon unberührt.

## Updates

Automatisch täglich (Scheduled Task `IAM-Update`) oder manuell per Klick im Management-Fenster.
Ein Update-Lauf rührt **nur den Code** an — `data/`, `backups/` und `.env` bleiben unangetastet,
Neo4j selbst (Version, Speicher-/APOC-Konfiguration) wird nicht automatisch aktualisiert, genau
wie eine Docker-Compose-Änderung dort auch kein automatisches Update auslöst.

## Details, Troubleshooting, Deinstallation

Vollständig in [`deploy/windows-native/README.md`][repo-deploy] im Repo — u. a. Verwaltung über
die Kommandozeile als Alternative zum Management-Fenster, Umgang mit einem fehlgeschlagenen
Fast-Forward-Update, Speicher-Tuning und Deinstallation.
