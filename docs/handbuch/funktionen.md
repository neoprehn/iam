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

- **Stichtag** — Bewertungsdatum (Rollen-Gültigkeit + Sleeping). **Keine Eingabe mehr**, sondern
  eine Eigenschaft des gewählten Datasets (= Downloaddatum der SAP-Extrakte): wird beim
  Erst-Import automatisch aus den Dateizeitstempeln der Extrakte ermittelt und nur angezeigt;
  eine bewusste Korrektur läuft über „ändern…" neben der Anzeige und wirkt **global** auf alle
  künftigen Läufe/Checks dieses Datasets, nicht nur den nächsten.
- **Sleeping (Tage)** — Schwelle „kein Logon seit X Tagen" (Standard 180), frei wählbar.
- **Mindest-Kritikalität** — `alle` · ab `medium` · ab `high` · ab `critical` · nur `very-critical`.
- **Materialisierung/Ruleset-Laden überspringen** — Beschleuniger für Wiederholungsläufe.

## 3 · Ergebnisse

Gruppen mit mehreren Befehlen (hier sowie unter „Admin") klappen als **Menü** auf — Klick auf die
Gruppe öffnet eine Liste der Befehle, Klick daneben oder auf einen Befehl schließt sie wieder
(verhält sich wie ein gewohntes Anwendungsmenü statt nebeneinanderliegender Buttons).

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

## 4 · Konsistenzchecks

Menü mit zwei Punkten — beide wechseln im Hauptbereich (anstelle von Filter/Ergebnisse) auf den
Check-Katalog des jeweiligen Bereichs; „&larr; zurück zu Ergebnisse" wechselt zurück.

| Befehl | Wirkung |
| --- | --- |
| **User-spezifisch** | Check-Katalog Kategorien A/B/C/D/E (kritische Berechtigungen, Benutzerstamm-Hygiene, Zuweisungskonsistenz, Gültigkeit/Zeitbezug, referenzielle Integrität). |
| **Rollen-spezifisch** | Check-Katalog Kategorie R (Rollendesign/-qualität — Struktur/Generierung, Zuordnung/Reichweite, Risiko/SoD, Wartbarkeit). |

Adressiert die **Qualität und allgemeinen Risiken des geladenen Berechtigungskonzepts selbst** —
unabhängig von einer konkreten SoD-Regel. **Je Raster-Box eine eigene, umrahmte Tabelle** — im
User-Bereich gerastert nach Kategorie: Layout 2×2 (A·B / C·D) plus **E zentriert darunter** mit
**Kategorie-Pills A–E** (+ „alle") darüber; im Rollen-Bereich gerastert nach Thema (Struktur &
Generierung, Zuordnung & Reichweite, Risiko & SoD, Wartbarkeit & Design), ebenfalls 2×2 mit
Themen-Pills darüber — statt einer einzigen langen Tabelle. Je Zeile steht die **Prüfung fett
mit der Begründung darunter klein** — auch ohne Fachwissen verständlich, nicht nur der Kurztitel.
Die letzte Spalte **„Ergebnisse"** zeigt die zuletzt in dieser Session gesehene Trefferzahl je
Check, sonst **„noch nicht ausgeführt"**, solange keine Check-Logik existiert.

Klick auf eine Zeile **wechselt** (kein Pop-up/Dialog, derselbe Grundsatz wie beim Katalog
selbst) auf eine **eigene Ergebnis-Ansicht**: der Check-Titel links, **ID/Kategorie/Prio-Chips +
„← zurück zum Katalog"** rechtsbündig auf Höhe der Überschrift; darunter **zweispaltig wie die
Findings-Ansicht**. **Links:** Begründung (immer sichtbar, auch bei noch nicht implementierten
Checks), darunter — sobald die Check-Logik existiert — ein schmales Formular mit
**Dataset-Auswahl** und der Anzeige des **Stichtags** (= Downloaddatum der SAP-Extrakte, eine
Eigenschaft des Datasets, kein Lauf-Filter mehr — über „ändern…" global korrigierbar, wirkt dann
auf alle künftigen Läufe/Checks dieses Datasets) mit **„Ausführen"** (zeigt während der Anfrage
einen Spinner), darunter eine **Schnellauswahl „Weitere Checks · …"** mit allen Checks derselben
Box (Kategorie bzw. Thema, analog zur Läufe-Liste, funktioniert auch von einem noch nicht
implementierten Check aus) — Klick wechselt direkt zum nächsten Check, ohne zurück zum Katalog
zu müssen; die Dataset-Auswahl bleibt dabei erhalten, sodass sich eine ganze Box mit demselben
Dataset durchklicken lässt. **Rechts** das Ergebnis: einige Checks zeigen über der Tabelle eine
**Pill-Filterzeile** (z. B. Sperrgrund bei „Gesperrte User mit kritischen Rollen", Status
aktiv/gesperrt, Sleeping-Tage 90/180/360) — Klick auf einen Pill startet bei bereits sichtbarem
Ergebnis sofort einen neuen Lauf, ohne erneut „Ausführen" klicken zu müssen — daneben ein
**Tabelle/Graph-Pill** (Graph deaktiviert, „kommt später", analog zu den SoD-Ergebnissen). Hat
der Check eine Zusammenfassung **und** eine Detailliste (z. B. „Wer hat SAP_ALL"), zeigt die
Tabellenansicht oben **Summary-Kacheln** (Werte menschenlesbar, z. B. „aktiv"/„gesperrt" statt
roher Spaltennamen), darunter die **Detailtabelle** (Spalten variieren je Check, Überschriften
ebenfalls menschenlesbar übersetzt statt der rohen Cypher-Spaltennamen) — **Spaltenköpfe sind
klickbar und sortieren die Tabelle** (numerisch oder alphabetisch je nach Inhalt), ein kleines
Dreieck (▲/▼) zeigt Spalte und Richtung; erneuter Klick dreht um. Bei manchen Checks (aktuell
A4) erscheint je Zeile zusätzlich ein **„Root-Cause"-Button**, der in einem Dialog zeigt, welche
konkrete(n) Rolle(n)/Profil(e) mit welchen Berechtigungswerten den Treffer auslösen — derselbe
Dialog wie beim SoD-Root-Cause. Checks ohne Zusammenfassung zeigen nur die Detailtabelle.
„← zurück zum Katalog" wechselt zurück. Noch nicht implementierte Checks zeigen rechts nur
einen Hinweis statt eines Ergebnisses.

**Keine Persistenz (bewusst):** ein Check-Lauf erzeugt keinen `(:Run)`-Knoten und wird nirgends
gespeichert — das Ergebnis lebt nur im Browser für die Dauer der Session. Die zuletzt gesehene
**Trefferzahl** wird clientseitig zwischengespeichert und ersetzt danach in der Katalog-Tabelle
den Platzhalter „noch nicht ausgeführt" — das ist ein reiner UI-Cache, kein Server-Zustand, und
geht beim Neuladen der Seite verloren. Der vollständige Katalog mit
Begründung steht in
[`KONSISTENZCHECKS.md`](../../KONSISTENZCHECKS.md), der technische Rahmen in
[`ROADMAP.md`](../../ROADMAP.md), Phase 7.

## 5 · Sichern

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

## 6 · Verwalten

| Befehl | Wirkung |
| --- | --- |
| **Bereinigen** | Dialog: **Dieses Dataset löschen** oder **Alles zurücksetzen** (Ruleset & Schema bleiben in beiden Fällen erhalten), sowie separat **einen einzelnen Auswertungslauf löschen** (Run + Findings; Dataset und andere Läufe bleiben unberührt). |

Beide Aktionen fragen vor dem Ausführen nach.

## 7 · Admin

| Befehl | Wirkung |
| --- | --- |
| **Query Management** | Link direkt auf die eigene Seite `/admin.html` (kein Zwischendialog). |
| **Fehlerprotokoll** | Dialog mit fehlgeschlagenen Jobs (Import/Lauf/Backup/Restore/Bereinigen) — **persistent**, überlebt einen Container-Neustart (Datei `data/logs/job_errors.jsonl`). Neueste zuerst. |

### Query Management (eigene Seite, eigene Ribbon-Bar)

Erreichbar &uuml;ber das Men&uuml; „Admin" (Gruppe „7 &middot; Admin") &rarr; „Query Management".
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
