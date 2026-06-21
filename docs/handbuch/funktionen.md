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
Communication/Reference), **User**, **Einzelberechtigung** und **SoD** — beide zeigen **ID +
Bezeichnung** (Kurzbezeichnung, falls gepflegt, sonst die Langbezeichnung); die ID steht
**voran**, damit sie bei langen Bezeichnungen nicht durch die feste Dropdown-Breite abgeschnitten
wird. Auswahl wendet über „Filtern" an bzw. sofort bei Klick auf eine Tabellenzelle.

Über der Ergebnistabelle: **Kritikalität** und **Sleeping** als farbige Klick-Buttons (Pills) —
wirken sofort als Ergebnisfilter, unabhängig vom Lauf-Parameter „Mindest-Kritikalität"/„Sleeping
(Tage)" beim Start. Ein aktiver Filter erscheint als Chip mit „zurücksetzen".

## 4 · Sichern

| Befehl | Wirkung |
| --- | --- |
| **Backup / Restore** | Öffnet den Dialog: **Backup erstellen** (Quelldaten-ZIP), Option **danach leeren** (Backup & Clear), und die **Backups-Liste** mit **↻ Wiederherstellen** und **↓ Herunterladen**. |

Backups enthalten nur die **bereinigten Quelldaten** — keine Findings (die werden nach dem
Wiederherstellen neu ausgewertet). Backups bleiben lokal.

Im selben Dialog, separat darunter: **Lauf-Backups** — sichert einen einzelnen
**Auswertungslauf** (Run + Findings, ohne Evidenz; die ist über „Evidenz" im Ribbon jederzeit
neu berechenbar) als eigenes ZIP. Jedes Dataset trägt dafür eine **Dataset-uid**, die beim
Wiederherstellen mit der im Lauf-Backup gespeicherten uid verglichen wird: weicht sie ab (das
Dataset wurde seither neu befüllt), fragt die App vor dem Restore ausdrücklich nach.

## 5 · Verwalten

| Befehl | Wirkung |
| --- | --- |
| **Bereinigen** | Dialog: **Dieses Dataset löschen** oder **Alles zurücksetzen** (Ruleset & Schema bleiben in beiden Fällen erhalten), sowie separat **einen einzelnen Auswertungslauf löschen** (Run + Findings; Dataset und andere Läufe bleiben unberührt). |

Beide Aktionen fragen vor dem Ausführen nach.

## 6 · Admin

| Befehl | Wirkung |
| --- | --- |
| **Admin** | Zeigt die **geladenen Rulesets** (Name, ID, Standard-Markierung) und einen Link zum **Query Management** (eigene Seite, `/admin.html`). |

### Query Management (eigene Seite, eigene Ribbon-Bar)

Erreichbar über Admin &rarr; „Query Management". Eigene Ribbon-Gruppen: **Anzeige**
(Aktualisieren), **Editieren** (Speichern/Abbrechen, aktiv sobald etwas ge&auml;ndert wurde),
**Backup** (Overlay-Datei des gew&auml;hlten Rulesets herunterladen) und **Zur&uuml;ck** (zur
Auswertung).

Links: **Filterset** w&auml;hlen (aktuell 3 Rulesets), darunter **Suche** (unterst&uuml;tzt `*`
als Platzhalter, z. B. „BC-SEC*") und Filter nach **Modul/Kritikalit&auml;t/Query-Typ**, dann die
Liste aller Queries (ID + Bezeichnung, eigene/abgeleitete Queries markiert).

Rechts, nach Auswahl einer Query: oben dauerhaft sichtbar die **Stammdaten**
(Kurz-/Langbezeichnung, Kritikalit&auml;t, Modul, Query-Typ, „TCode ignorieren" — die
**Kurzbezeichnung** ist es, was in den Sidebar-Filtern der Auswertung als Name erscheint), darunter
drei **Tabs**:

- **Aufbau** — Transaktionen und Berechtigungsobjekte der Query, **nur Anzeige** (Bearbeitung
  folgt sp&auml;ter).
- **Risiko** — Freitext: potenzielles Risiko dieser Berechtigung.
- **Controls** — Freitext: mitigierende Ma&szlig;nahmen.

Unten links: eine **neue Query aus der gew&auml;hlten ableiten** (Berechtigungen/TCodes 1:1
&uuml;bernommen, Stammdaten/Risiko/Controls oben vorher anpassen).

&Auml;nderungen schreiben **nie** in die Vendor-Datei (`queries.json`), sondern in ein separates
Overlay (`queries.custom.json`) je Ruleset — Vendor-Updates &uuml;berschreiben eigene Anpassungen
dadurch nicht. Speichern/Ableiten wirkt **sofort** (kein extra Reload-Schritt n&ouml;tig).

**Geplant** in diesem Bereich:

- **Authorizations/TCodes im Aufbau-Tab bearbeitbar** — bisher nur Anzeige bzw. 1:1-Kopie beim Ableiten.
- **USOBT-gest&uuml;tzter Query-Builder** — neue Queries per Auswahl Transaktion&nbsp;&rarr;
  Berechtigungsobjekte statt freier Eingabe.
- **Stammdaten-Blatt: Query &rarr; System-Typ** (SAP R/3, S/4HANA, k&uuml;nftig weitere).
- **Neues Filterset importieren** — weitere Systeme als eigenes Ruleset, perspektivisch
  **SAP S/4HANA, Azure AD / Entra, Microsoft Dynamics, Salesforce** (das Datenmodell bleibt gleich).

> Die App hat **bewusst kein eigenes Benutzer-/Berechtigungskonzept**: sie läuft lokal bzw. wird als
> Container verteilt; der Zugriff wird über die Umgebung abgesichert.
