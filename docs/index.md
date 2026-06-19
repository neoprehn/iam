# IAM — SAP-Berechtigungsanalyse mit Neo4j

Graphbasierte Auswertung von SAP-Berechtigungen (R/3 und S/4HANA): **Can-Do** (Berechtigung) und
**SoD-Konfliktanalyse**, bedienbar als lokale Web-App. Die Umgebung läuft **container-only** über
Docker Desktop/WSL2 — ohne lokale Neo4j- oder Java-Installation auf dem Host.

Die Doku ist in zwei Teile gegliedert:

- **Benutzerhandbuch** — was die App kann, was welche Funktion macht und wie der Workflow aussieht.
- **Technische Dokumentation** — Architektur (aktueller Stand), Datenmodell, Extraktion sowie der
  **Entwicklungsverlauf** (wie wir Phase für Phase zum heutigen Stand gekommen sind).

:::{admonition} Vertrauensgrenze
:class: important

Diese Doku beschreibt ausschließlich **Logik, Umgebung und Vorgehen** — niemals Mandantendaten.
SAP-Extrakte, das DB-Volume und Backups bleiben lokal (`data/`, `backups/`, gitignored).
:::

```{toctree}
:maxdepth: 2
:caption: Benutzerhandbuch

handbuch/ueberblick
handbuch/workflow
handbuch/funktionen
```

```{toctree}
:maxdepth: 2
:caption: Technische Dokumentation

technik/architektur
datamodel
extraktionsleitfaden
```

```{toctree}
:maxdepth: 1
:caption: Entwicklungsverlauf (Phasen)

phasen/phase-0
phasen/phase-1
phasen/phase-2
phasen/phase-3
phasen/phase-5
phasen/phase-9
```

## Weiterführend

- Vollständiger Fahrplan & Architektur-Entscheidungen: `ROADMAP.md` im Repo-Root.
- Quellcode & Umgebung: <https://github.com/neoprehn/iam>
