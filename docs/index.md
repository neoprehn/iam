# IAM — SAP-Berechtigungsanalyse mit Neo4j

Graphbasierte Auswertung von SAP-Berechtigungen (R/3 und S/4HANA): **Can-Do**
(Berechtigung) und **Did-Do** (Nutzung), inklusive SoD-Konfliktanalyse. Die Umgebung
läuft **container-only** über Docker Desktop/WSL2 — ohne lokale Neo4j- oder
Java-Installation auf dem Windows-Host.

Diese Doku begleitet die Umsetzung Phase für Phase. Jede abgeschlossene Phase wird hier
dokumentiert (Dokumentations-DoD) — die Schritte sind so beschrieben, dass sie auf einem
frischen Rechner nachvollziehbar sind.

:::{admonition} Vertrauensgrenze
:class: important

Diese Doku beschreibt ausschließlich **Logik, Umgebung und Vorgehen** — niemals
Mandantendaten. SAP-Extrakte und das DB-Volume bleiben lokal (`data/`, gitignored).
:::

```{toctree}
:maxdepth: 2
:caption: Phasen

phasen/phase-0
```

## Weiterführend

- Vollständiger Fahrplan & Architektur-Entscheidungen: `ROADMAP.md` im Repo-Root.
- Quellcode & Umgebung: <https://github.com/neoprehn/iam>
