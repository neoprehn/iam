# Workflow Schritt für Schritt

Eine vollständige Auswertung von den Rohdaten bis zum Ergebnis — entlang der Ribbon-Bar.

## 1 · Daten laden (Import)

Ribbon **Daten → Import**. Zwei Wege:

- **ZIP hochladen** *(empfohlen)* — eine `.zip` mit den SAP-Exporten (`.txt` aus SE16 **oder**
  bereits konvertierte `.csv`). Optional einen **Dataset-Namen** vergeben (sonst aus dem Dateinamen).
- **Vorhandener Ordner** — ein bereits unter `data/import/<dataset>/` liegender Ordner.

Beim Import läuft automatisch: **konvertieren → Schema sicherstellen → laden → prüfen**. Der
Fortschritt erscheint als Statuszeile unter dem Ribbon. Ergebnis: ein **Dataset** im Graphen
(Benutzer, Rollen, Profile, Berechtigungen …).

:::{admonition} Welche Tabellen werden gebraucht?
:class: note
**Pflicht (Minimalset):** `USR02`, `AGR_DEFINE`, `AGR_AGRS`, `AGR_USERS`, `ARG_PROF`, `UST04`,
`AGR_1251`, `TSTCT`, `USOBT_C`, `UST10S`, `UST12`. Fehlt eine davon, bricht der Import mit klarer
Meldung ab. **Optional** (Anreicherung): u. a. `AGR_TEXTS`, `USR11`, `AGR_1252`, `AGR_TCODES`,
`AGR_1016B`. Vollständige Liste mit Zweck und Spalten im
[Extraktionsleitfaden](../extraktionsleitfaden.md#welche-tabellen-herunterladen). Sensible Spalten
(Passwort-Hashes) werden beim Konvertieren **verworfen** und erreichen den Graphen nie.
:::

## 2 · Auswerten (Neuer Lauf)

Ribbon **Auswertung → Neuer Lauf**. Das Formular füllt intern die Parameter — **kein JSON**:

| Parameter | Bedeutung |
| --- | --- |
| **Ruleset** | welches Regelwerk gilt (z. B. KPMG R/3). |
| **System (dataset)** | welcher Datenstand ausgewertet wird. |
| **Stichtag** | Bewertungsdatum — bestimmt Rollen-Gültigkeit und Sleeping. **Auf das Datum des Datenstands setzen**, nicht „heute". |
| **Nutzertyp-Profil** | welche Benutzer zählen (siehe [Funktionsreferenz](funktionen.md)). |
| **Org-Profil** | Org-Einschränkung (Standard: keine). |
| **Sleeping (Tage)** | ab wann ein Benutzer als „schlafend" gilt (kein Logon seit X Tagen). |
| **Mindest-Kritikalität** | nur Regeln ab einer Stufe (z. B. „ab critical"). |
| **Run-ID** | optionaler Name des Laufs (sonst automatisch). |

Der Lauf macht zwei Schritte: **Materialisierung** („wer kann was", dauert je nach Größe etwas)
und **Auswertung** (die SoD-Regeln auf dem Zwischenergebnis). Beides läuft als Hintergrund-Job mit
Fortschrittsanzeige.

:::{tip}
Hast du denselben Stichtag schon einmal materialisiert, kannst du **„Materialisierung überspringen"**
ankreuzen — dann läuft nur die (schnelle) Regelauswertung.
:::

## 3 · Ergebnisse ansehen

Der **Hauptbereich** zeigt die Ergebnisse durchgehend:

- **KPIs** — Findings, betroffene Regeln, davon „sleeping".
- **Läufe-Liste** — alle Läufe mit Findings-Zahl; ein Klick lädt den Lauf (KPIs + Findings).
- **Findings-Tabelle** — Benutzer · Regel · Kritikalität · Sleeping (nach Kritikalität sortiert).
- **Export CSV** (Ribbon **Ergebnisse → Export CSV**) — die Findings des aktiven Laufs als CSV
  (Semikolon, UTF-8 — öffnet direkt in Excel).

## 4 · Sichern (Backup/Restore)

Ribbon **Sichern → Backup / Restore**:

- **Backup erstellen** — packt die bereinigten Quelldaten des Datasets in ein ZIP.
- **danach leeren (Backup & Clear)** — sichern und den Stand anschließend aus dem Graphen entfernen
  (z. B. um Platz für ein anderes System zu machen).
- **Backups-Liste** — jedes Backup **↻ wiederherstellen** (Re-Import) oder **↓ herunterladen**
  (transportabel, z. B. für Kolleg:innen).

:::{admonition} Was steckt im Backup?
:class: note
Nur die **Quelldaten** (die bereinigten `.csv`) — nicht die Findings. Findings sind *regenerierbar*:
nach dem Wiederherstellen einfach erneut auswerten (die Parameter eines Laufs sind reproduzierbar).
Ergebnisse für Berichte exportierst du separat als CSV (Schritt 3).
:::

## 5 · Verwalten (Bereinigen)

Ribbon **Verwalten → Bereinigen**:

- **Dieses Dataset löschen** — entfernt einen Stand inkl. seiner Läufe/Findings.
- **Alles zurücksetzen** — entfernt alle Daten/Läufe.

In **beiden** Fällen bleiben **Regelwerk (Ruleset) und Schema erhalten** — danach kann sofort neu
importiert und ausgewertet werden, ohne das Regelwerk neu zu laden.

## 6 · Admin

Ribbon **Admin** zeigt die **geladenen Rulesets**. Das Nachjustieren von SoD-Filtern und der Import
neuer Filtersets (für weitere Systeme) sind vorgesehen und dort verankert — siehe
[Funktionsreferenz](funktionen.md).

## Typischer Ablauf

```
Import (ZIP)  →  Neuer Lauf (Stichtag = Datenstand, Nutzertyp = Dialog aktiv)
              →  Findings prüfen + CSV exportieren
              →  Backup erstellen  →  ggf. Dataset bereinigen / nächstes System laden
```
