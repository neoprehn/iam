Lies bitte:

    Als allererstes: git pull (bzw. mind. git fetch + Abgleich mit origin/main) — es gibt seit
    2026-07-12 zwei Arbeitsgeräte (Heim-Rechner + mobiler Laptop für Zugfahrten), der lokale Stand
    kann also hinter dem sein, was vom jeweils anderen Gerät gepusht wurde. Erst danach die
    folgenden Dateien lesen, sonst ggf. veralteter Stand:
    ROADMAP.md — „Stand" + offene Punkte mit [ ]/[~]/[x] (das ist der eigentliche Übergabepunkt),
    ROADMAP-ARCHIV.md — was erledigt ist,
    Git-Historie — jeder Commit beschreibt einen Schritt,
    das persistente Memory (MEMORY.md + memory/*.md) — wird in jede neue Session geladen,
    CLAUDE.md — Projektregeln.

Was steht als nächstes an?

---

Wiederkehrende Aufgabe — Risikokatalog inkrementell befüllen (läuft parallel zu Claude Code):

    Der Risikokatalog (`rules/<Ruleset>/risks.json`, v. a. `rules/KPMG_R3/risks.json`) wird Schritt
    für Schritt befüllt (ROADMAP 9.4). Weil Claude Code dabei schnell gegen die Token-Limits läuft,
    parallelisieren wir: das inhaltliche Erarbeiten passiert in Claude Code, das Zusammenführen der
    Ergebnisse hier. Ich hänge in diesem Chat regelmäßig (i. d. R. täglich) eine oder mehrere
    JSON-Dateien an, die pro Eintrag über `alias` (SoD-Regel) bzw. `query` (Einzelfilter) mit dem
    Katalog verknüpft sind und Felder wie `source`, `threat`, `risk`, `riskType`, `riskLevel` …
    liefern.

    Aufgabe dann jeweils:
    - Die gelieferten Felder in die passenden Einträge von `risks.json` zusammenführen (Match über
      `alias`/`query`).
    - Bereits vorhandene, kuratierte Werte NICHT überschreiben — nur ergänzen, sofern das Zielfeld
      leer/fehlt (bei Konflikt nachfragen).
    - Platzierung/Format schema-konform halten (`rules/SCHEMA.md`: u. a. `source`/`threat` nach
      `threat`/`risk`, vor `description`; JSON-Array für `source`). Datei-Formatierung 1:1 erhalten
      (CRLF, 2-Space-Indent, `ensure_ascii=False`).
    - Danach JSON validieren und einen kurzen Merge-Report geben (matched / übersprungen /
      nicht gefunden).