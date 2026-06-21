# Funktionsreferenz

Was macht welcher Befehl in der Ribbon-Bar — und was bedeuten die Auswahlmöglichkeiten.

## Banner

Oben links die Wortmarke, oben rechts der **Hell/Dunkel-Umschalter** (merkt sich die Wahl im
Browser) sowie zwei **Status-Chips**: Verbindung zur Datenbank und der Kontext
**„N Datasets · M Läufe"** (aktualisiert sich nach jeder Aktion).

## 1 · Daten

| Befehl | Wirkung |
| --- | --- |
| **Import** | Öffnet den Import-Dialog: **ZIP hochladen** (`.txt`/`.csv` im ZIP) oder **vorhandener Ordner**. Startet den Import-Job (konvertieren → Schema → laden → prüfen). |

Optionen im Dialog: **Sprachen** (für sprachabhängige Texttabellen, Standard `DE,DEU,D`),
**Schema überspringen** (wenn Constraints/Indizes schon da sind), **Konvertierung überspringen**
(wenn bereits `.csv` vorliegen).

## 2 · Auswertung

| Befehl | Wirkung |
| --- | --- |
| **Neuer Lauf** | Öffnet das Parameter-Formular und startet Materialisierung + SoD-Auswertung. |

### Nutzertyp-Profil

Welche Benutzer in die Auswertung eingehen:

| Profil | Bedeutung |
| --- | --- |
| **all** | alle Benutzertypen, inkl. gesperrte. |
| **dialog-service** | Dialog + Service (A/S), inkl. gesperrte. |
| **dialog-active** | Dialog + Service **und nicht gesperrt** — die audit-relevante Sicht. |
| **dialog-only** | nur Dialog (A). |

> Benutzertyp und „gesperrt" sind zwei getrennte Achsen: A/S sagt nichts über aktiv/gesperrt aus.
> `dialog-active` kombiniert beides.

### Org-Profil

Ob die Auswertung auf Organisationsebenen (z. B. Buchungskreis) eingeschränkt wird:

| Modus | Bedeutung |
| --- | --- |
| **Standard** | keine Org-Einschränkung — *„kann der Benutzer die Funktion überhaupt?"* |
| **Übergreifend** | zählt nur, wenn die Berechtigung den vollen Bereich (`*`) trägt. |
| **Gefiltert** | je Org-Feld eine Bedingung (UND/ODER/Bereich) — über Profile vorkonfiguriert. |

> Die Org-Filterung wirkt über **alle** Org-Ebenen (Buchungskreis `BUKRS`, Werk `WERKS`, Einkaufsorg
> `EKORG`, Verkaufsorg `VKORG`, …, aus USORG) **und Kombinationen** (z. B. Buchungskreis *und*
> Einkaufsorg). Bewertet werden die **echten Berechtigungswerte** der Nutzer (aus den Rollen-/
> Profil-Auths), nicht SU24-Vorschläge. Der gewählte Modus/Filter wird am Lauf protokolliert.

### Weitere Parameter

- **Stichtag** — Bewertungsdatum (Rollen-Gültigkeit + Sleeping). Auf den Datenstand setzen.
- **Sleeping (Tage)** — Schwelle „kein Logon seit X Tagen" (Standard 180), frei wählbar.
- **Mindest-Kritikalität** — `alle` · ab `medium` · ab `high` · ab `critical` · nur `very-high`.
- **Materialisierung/Ruleset-Laden überspringen** — Beschleuniger für Wiederholungsläufe.

## 3 · Ergebnisse

| Befehl | Wirkung |
| --- | --- |
| **Aktualisieren** | lädt Läufe, Datasets, Backups neu. |
| **Export CSV** | Findings des **aktiven** Laufs als CSV (Semikolon, UTF-8 — Excel-tauglich). |

Im Hauptbereich: **KPIs** (Findings / betroffene Regeln / davon sleeping — folgen dem aktuell
gesetzten Filter, nicht nur den Gesamtzahlen des Laufs), **Läufe-Liste** (Klick = Lauf laden;
jede Karte zeigt Bezeichnung, Stichtag und Erstellungs-Datum/-Zeit) und die **Findings-Tabelle**
(nach Kritikalität sortiert; Sleeping markiert; Klick auf User-/Regel-Zelle filtert direkt danach).

### Filter

Links in der Sidebar: **Nutzertyp** (Ankreuz-Dropdown — A/B/S/C/L = Dialog/System/Service/
Communication/Reference), **User**, **Einzelberechtigung** und **SoD** — Auswahl wendet über
„Filtern" an bzw. sofort bei Klick auf eine Tabellenzelle.

Über der Ergebnistabelle: **Kritikalität** und **Sleeping** als farbige Klick-Buttons (Pills) —
wirken sofort als Ergebnisfilter, unabhängig vom Lauf-Parameter „Mindest-Kritikalität"/„Sleeping
(Tage)" beim Start. Ein aktiver Filter erscheint als Chip mit „zurücksetzen".

## 4 · Sichern

| Befehl | Wirkung |
| --- | --- |
| **Backup / Restore** | Öffnet den Dialog: **Backup erstellen** (Quelldaten-ZIP), Option **danach leeren** (Backup & Clear), und die **Backups-Liste** mit **↻ Wiederherstellen** und **↓ Herunterladen**. |

Backups enthalten nur die **bereinigten Quelldaten** — keine Findings (die werden nach dem
Wiederherstellen neu ausgewertet). Backups bleiben lokal.

## 5 · Verwalten

| Befehl | Wirkung |
| --- | --- |
| **Bereinigen** | Dialog: **Dieses Dataset löschen** oder **Alles zurücksetzen**. **Ruleset & Schema bleiben** in beiden Fällen erhalten. |

Beide Aktionen fragen vor dem Ausführen nach.

## 6 · Admin

| Befehl | Wirkung |
| --- | --- |
| **Admin** | Zeigt die **geladenen Rulesets** (Name, ID, Standard-Markierung). |

**Geplant** in diesem Bereich:

- **SoD-Filter nachjustieren** (Ruleset-Editor) — Regeln/Queries über die UI anpassen, Vendor-Basis
  von eigenen Erweiterungen getrennt.
- **Neues Filterset importieren** — weitere Systeme als eigenes Ruleset, perspektivisch
  **SAP S/4HANA, Azure AD / Entra, Microsoft Dynamics, Salesforce** (das Datenmodell bleibt gleich).

> Die App hat **bewusst kein eigenes Benutzer-/Berechtigungskonzept**: sie läuft lokal bzw. wird als
> Container verteilt; der Zugriff wird über die Umgebung abgesichert.
