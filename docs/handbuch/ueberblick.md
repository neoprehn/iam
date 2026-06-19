# Überblick

**IAM** ist eine lokale Web-App zur **graphbasierten Analyse von SAP-Berechtigungen** mit
**SoD-Konflikterkennung** (Segregation of Duties). Sie beantwortet zwei Fragen:

- **Can-Do** — *Wer darf was?* (Berechtigungen aus Rollen und direkt zugewiesenen Profilen)
- **SoD** — *Wer kann unvereinbare Dinge kombinieren?* (z. B. Lieferant anlegen **und** Zahlung freigeben)

Die Auswertung läuft **container-only** (Docker) und vollständig **lokal**. Bedient wird alles im
Browser unter <http://localhost:8000/>.

:::{admonition} Daten bleiben lokal
:class: important
Es verlassen **keine Mandantendaten** die Umgebung. SAP-Extrakte, die Datenbank und Backups liegen
lokal und sind von der Versionierung ausgeschlossen. Nur die Bedienoberfläche ist „außen".
:::

## Der Lebenszyklus einer Auswertung

Die Oberfläche ist als **Ribbon-Bar** genau nach diesem Ablauf gegliedert:

```
 1 Daten      →   2 Auswertung   →   3 Ergebnisse   →   4 Sichern    →   5 Verwalten   ·   6 Admin
 Import           Neuer Lauf         KPIs/Findings      Backup/Restore   Clear/Reset       Regelwerke
 (ZIP/Ordner)     (Parameter)        CSV-Export                                            (geplant)
```

1. **Daten** — die SAP-Exporte eines Systems laden (per ZIP-Upload oder vorhandenem Ordner).
2. **Auswertung** — einen SoD-Lauf mit Parametern starten (Ruleset, Stichtag, Nutzertyp …).
3. **Ergebnisse** — Kennzahlen und Findings ansehen, als CSV exportieren.
4. **Sichern** — die Quelldaten eines Systems als Backup sichern, wiederherstellen, herunterladen.
5. **Verwalten** — einen Stand oder alle Daten bereinigen (Regelwerk bleibt erhalten).
6. **Admin** — geladene Regelwerke (Rulesets); Editor/Filterset-Import sind in Vorbereitung.

## Starten

```bash
docker compose up -d --build      # Neo4j + Backend (+ NeoDash) starten
docker compose run --rm migrations  # Schema einmalig anlegen (idempotent)
# Browser öffnen: http://localhost:8000/
```

Beim ersten Start werden die Images gezogen und das Backend gebaut. Danach ist die App unter
Port **8000** erreichbar; der Neo4j-Browser liegt auf **7474**, NeoDash (Showcase) auf **5005**.

## Begriffe in Kürze

| Begriff | Bedeutung |
| --- | --- |
| **Dataset** | ein Daten-/Systemstand (ein SAP-Mandant zu einem Zeitpunkt). Mehrere Stände liegen nebeneinander. |
| **Ruleset** | das Regelwerk (z. B. KPMG, CSI) mit Queries und SoD-Regeln. Konstant, gilt über alle Datasets. |
| **Lauf (Run)** | eine Auswertung mit festen Parametern; trägt Stichtag, Nutzertyp-/Org-Auswahl und die Findings. |
| **Finding** | ein erkannter SoD-Konflikt: *dieser Benutzer* verletzt *diese Regel*. |

Weiter zum [Workflow](workflow.md) (Schritt für Schritt) oder zur
[Funktionsreferenz](funktionen.md) (was macht welcher Befehl).
