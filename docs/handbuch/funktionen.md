# Funktionsreferenz

Was macht welcher Befehl in der Ribbon-Bar — und was bedeuten die Auswahlmöglichkeiten.

## Banner

Oben links die Wortmarke, oben rechts der **Hell/Dunkel-Umschalter** (merkt sich die Wahl im
Browser), der Chip mit dem **aktiv angewendeten Ruleset** des gerade angezeigten Laufs sowie zwei
weitere **Status-Chips**: Verbindung zur Datenbank und der Kontext **„N Datasets · M Läufe"**
(aktualisiert sich nach jeder Aktion).

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
- **Mindest-Kritikalität** — `alle` · ab `medium` · ab `high` · ab `critical` · nur `very-critical`.
- **Materialisierung/Ruleset-Laden überspringen** — Beschleuniger für Wiederholungsläufe.

## 3 · Ergebnisse

| Befehl | Wirkung |
| --- | --- |
| **Aktualisieren** | lädt Läufe, Datasets, Backups neu. |
| **Export CSV** | Findings des **aktiven** Laufs als CSV (Semikolon, UTF-8 — Excel-tauglich). |

Im Hauptbereich: **KPI-Kacheln** (s. u.), **Läufe-Liste** (Klick = Lauf laden; jede Karte zeigt
Bezeichnung, Stichtag und Erstellungs-Datum/-Zeit) und die **Ergebnistabelle** (Findings oder
Matches, je nach Ergebnistyp — s. u.).

### Filter

Links in der Sidebar: **Nutzertyp** (Ankreuz-Dropdown — A/B/S/C/L = Dialog/System/Service/
Communication/Reference), **User**, **Einzelberechtigung** und **SoD** — beide zeigen **ID +
Bezeichnung** (Kurzbezeichnung, falls gepflegt, sonst die Langbezeichnung); die ID steht
**voran**, damit sie bei langen Bezeichnungen nicht durch die feste Dropdown-Breite abgeschnitten
wird. Auswahl wendet über „Filtern" an bzw. sofort bei Klick auf eine User-Zelle in der
Findings-Tabelle. Ist ein **User** gewählt, schränken sich **Einzelberechtigung**- und
**SoD**-Dropdown automatisch auf das für ihn tatsächlich Gefundene ein (kaskadierender Filter)
statt immer den vollen Katalog/alle Lauf-Regeln zu zeigen.

Über der Ergebnistabelle, in einer eigenen Zeile: **Kritikalität** (very-critical…low) immer,
**Ergebnistyp** (`alle` / `Einzelfilter` / `SoD`) **nur außerhalb der Einstiegstabelle** (s. u.)
und — nur bei Ergebnistyp „alle" — **Sleeping** (`alle` / `nur sleeping` / `nicht sleeping`) als
farbige Klick-Buttons (Pills), wirken sofort. Rechtsbündig in derselben Zeile: der **Tabelle/
Graph-Umschalter** (Graph ist als Vorgriff auf das künftige NVL/React-Frontend angelegt, aktuell
aber deaktiviert — „kommt später"). „Einzelfilter" zeigt die **Matches-Tabelle** („wer matcht
welche Query") auch **ohne** vorher eine konkrete Einzelberechtigung in der Sidebar zu wählen —
dann für alle Queries, sonst nur für die gewählte.

**Einstiegstabelle.** Ist **kein** Filter aktiv (frisch geladener Lauf bzw. „Zurücksetzen"), zeigt
die letzte Spalte **Sleeping** statt **Root-Cause** und die Ergebnistyp-Pillzeile ist ausgeblendet
— bei (potenziell hunderten) ungefilterten Findings lohnt der Root-Cause-Absprung pro Zeile noch
nicht. Sobald irgendein Filter greift (User, Regel, Kritikalität, Nutzertyp, Ergebnistyp), wechselt
die letzte Spalte zu **Root-Cause** und die Ergebnistyp-Pillzeile erscheint.
„SoD"/„alle" zeigen die **Findings-Tabelle**. Ein aktiver Filter erscheint zusätzlich als Chip mit
„zurücksetzen".

### Nutzerzentrische Auswahl: KPI-Kacheln, verursachende Rollen

Sobald ein **User** gefiltert ist, ersetzt eine **Stammdaten-Kachel** (UserID · Name · Typ ·
Status, über `GET /users/{id}`) die KPI-Kachel an der Stelle, an der sonst nichts Drittes stünde.
Wählt man zusätzlich eine **Regel** (z. B. über den Root-Cause-Zugang, s. u.), bleibt der
User-Filter erhalten und ein Chip **„Regel: …"** erscheint oben über den KPI-Kacheln (additiver
Drill-down: erst Nutzer, dann Nutzer **und** Regel — nicht exklusiv).

Sind **User und Regel zusammen** gesetzt (genau ein Finding), erscheint unter den KPI-Kacheln ein
eigenes Feld **„Verursachende Rollen/Profile"** — die Rollen/Profile, die laut Evidenz
(`VIA_ROLE`/`VIA_PROFILE`) diesen Konflikt auslösen, plus ein eigener **Root-Cause**-Button (s. u.).
Ohne berechnete Evidenz (Ribbon „Evidenz" nicht ausgeführt) erscheint dort ein Hinweis statt der
Liste.

### Root-Cause

Sowohl die **Findings-Tabelle** (SoD) als auch die **Matches-Tabelle** („wer matcht", Einzelfilter)
haben pro Zeile einen **„Root-Cause"**-Button. Er öffnet eine Detailansicht, gruppiert **pro
Berechtigungsobjekt** der Query (und ggf. einen eigenen Block für die TCode-Prüfung) — bei einer
SoD-Regel zusätzlich **pro Klausel** (für die tatsächlich vom User gematchte Query dieser Klausel):
oben die **Anforderung** (Feld, UND/ODER-Logik, geforderte Werte), darunter die **Rolle(n)/
Profil(e)**, die genau dieses Objekt mit welcher konkreten Authorization erfüllen. Anders als die
Evidenz (die nur „welche Rolle" zeigt) macht das sichtbar, wenn **verschiedene Objekte/Klauseln
durch verschiedene Rollen** gedeckt werden — der eigentliche Root-Cause, nicht nur der Träger des
Konflikts.

Die Matches-Tabelle zeigt dafür **User · Name · Query · Bezeichnung (Kurzbezeichnung der Query) ·
Kritikalität · Root-Cause** — Nutzertyp/Status sind hier bewusst weggelassen (stehen ggf. in der
Stammdaten-Kachel), stattdessen ist auf einen Blick erkennbar, **welche** Query mit **welcher
Kritikalität** gematcht wurde. Die Findings-Tabelle hat **keine klickbare Regel-Zelle** mehr (der
Root-Cause-Button deckt diesen Absprung jetzt ab) und zeigt keine Sleeping-Spalte mehr.

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
| **Query Management** | Link direkt auf die eigene Seite `/admin.html` (kein Zwischendialog). |
| **Fehlerprotokoll** | Dialog mit fehlgeschlagenen Jobs (Import/Lauf/Backup/Restore/Bereinigen) — **persistent**, überlebt einen Container-Neustart (Datei `data/logs/job_errors.jsonl`). Neueste zuerst. |

### Query Management (eigene Seite, eigene Ribbon-Bar)

Erreichbar direkt &uuml;ber den Ribbon-Punkt „Query Management" (Gruppe „6 &middot; Admin").
Eigene Ribbon-Gruppen: **Anzeige**
(Aktualisieren), **Editieren** (Speichern/Abbrechen, aktiv sobald etwas ge&auml;ndert wurde),
**Backup** (Overlay-Datei des gew&auml;hlten Rulesets herunterladen) und **Zur&uuml;ck** (zur
Auswertung).

Links: **Filterset** w&auml;hlen (aktuell 3 Rulesets), darunter der **Modus-Umschalter
„Einzelfilter"/„SoD"** — wechselt Liste, Filter und Detailbereich, ohne die Auswahl im jeweils
anderen Modus zu verwerfen. Darunter **Suche** (unterst&uuml;tzt `*` als Platzhalter, z. B.
„BC-SEC*", wirkt in beiden Modi) und je Modus eigene Filter: **Einzelfilter** nach
**Modul/Kritikalit&auml;t/Query-Typ**, **SoD** nur nach **Kritikalit&auml;t**. Die Liste zeigt
ID + Bezeichnung, eigene/abgeleitete bzw. bearbeitete Eintr&auml;ge markiert.

**Modus Einzelfilter** — rechts nach Auswahl einer Query: oben dauerhaft sichtbar die
**Stammdaten** (Kurz-/Langbezeichnung, Kritikalit&auml;t, Modul, Query-Typ, „TCode ignorieren" —
die **Kurzbezeichnung** ist es, was in den Sidebar-Filtern der Auswertung als Name erscheint),
darunter drei **Tabs**:

- **Aufbau** — Transaktionen und Berechtigungsobjekte der Query, **nur Anzeige** (Bearbeitung
  folgt sp&auml;ter).
- **Risiko** — Freitext: potenzielles Risiko dieser Berechtigung.
- **Controls** — Freitext: mitigierende Ma&szlig;nahmen.

Unten links: eine **neue Query aus der gew&auml;hlten ableiten** (Berechtigungen/TCodes 1:1
&uuml;bernommen, Stammdaten/Risiko/Controls oben vorher anpassen) — nur im Modus Einzelfilter.

**Modus SoD** — rechts nach Auswahl einer Regel: Stammdaten (Kurz-/Langbezeichnung,
Kritikalit&auml;t, Reason-Code, read-only), darunter drei **Tabs**:

- **Aufbau** — die CNF-Klausel-Struktur: je Klausel die enthaltenen Queries (ID + Bezeichnung);
  alle Klauseln zusammen sind UND-verkn&uuml;pft, innerhalb einer Klausel reicht eine gematchte
  Query. Hat ein Ruleset noch keine `clauses` hinterlegt (aktuell CSI/CSI_BI, s. ROADMAP), zeigt
  der Tab ersatzweise den rohen Ausdruck (`expression`) und die Variablen-Zuordnung.
- **Risiko** / **Controls** — wie beim Einzelfilter, eigene Freitext-Felder je SoD-Regel.

SoD-Regeln haben **kein „Ableiten"** (keine UI f&uuml;r neue/abgeleitete Regeln) — nur
Metadaten-Edits an bestehenden Regeln. Speichern/Abbrechen (Ribbon **oder** Detailbereich) sowie
„Overlay sichern" (Ribbon **Backup**) wirken im jeweils aktiven Modus auf den passenden Overlay
(`queries.custom.json` bzw. `sod_rules.custom.json`).

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
