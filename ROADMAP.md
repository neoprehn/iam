# Roadmap — SAP-Berechtigungsanalyse mit Neo4j

**Projekt:** Graphbasierte Auswertung von SAP-Berechtigungen (R/3 und S/4HANA) — Can-Do (Berechtigung) und Did-Do (Nutzung), inklusive SoD-Konfliktanalyse.
**Repository:** `neoprehn/iam`.
**Zielplattform:** Windows (Container-only über Docker Desktop / WSL2 — siehe „Windows-Spezifika").

**Stand:** Die App ist unter `http://localhost:8000/` lauffähig: **Import (Ordner/ZIP), Auswertung
(inkl. Evidenz), Ergebnisse + CSV-Export, Backup/Restore, Bereinigen** — alles ohne JSON-Pflege.
Abgeschlossene Arbeit (Phasen 0–3, 5; Phase 6 PoC; Phase-9-Bausteine Backend-API/Import/Ribbon-UI/
Backup-Restore-Clear/CSV-Export; AE-11-Evidenz v1) ist im Detail in
[`ROADMAP-ARCHIV.md`](ROADMAP-ARCHIV.md) festgehalten. **Diese Datei führt nur noch die offenen
Punkte** plus die verbindliche Referenz (Vertrauensgrenze, Architektur-Entscheidungen,
Zielarchitektur, Windows-Spezifika, R/3-vs-S/4).

---

## Verwendung mit Claude Code

Lebendes Dokument: Checklisten (`[ ]` offen, `[~]` teilweise) als Fortschrittsanker; erledigte Blöcke
wandern nach [`ROADMAP-ARCHIV.md`](ROADMAP-ARCHIV.md). Die **Architektur-Entscheidungen** weiter unten
sind verbindlich und sollten nicht ohne bewussten Grund verworfen werden.

**Leitprinzip — Dokumentations-DoD (gilt für JEDE Phase UND jeden Baustein/Feature).** Ein Punkt gilt
erst als fertig, wenn er in der Doku (`docs/`, Sphinx + MyST) nachvollziehbar dokumentiert **und nach
GitHub gepusht** ist — **Read the Docs baut nur aus dem Push** (kein Push = kein RTD-Update). Konkret:
betroffene Handbuch-/Technik-Seite aktualisieren, committen, pushen. Die Doku enthält ausschließlich
Logik/Vorgehen — **niemals Mandantendaten** (auch keine konkreten Client-System-Zahlen;
Beispiel-`dataset` = `acme`; vor jedem Push `git grep`/`git log` gegen Name+Zahlen prüfen).

---

## Leitprinzip: die Vertrauensgrenze

Die gesamte Architektur trennt strikt zwischen **Logik** und **Daten**:

- **GitHub-Repo** enthält ausschließlich Logik, Umgebung und Darstellung — niemals Mandantendaten.
- **Lokale Umgebung** (verschlüsselt, kontrolliert) enthält die sensiblen SAP-Extrakte und führt die Auswertung durch.
- Verteilung erfolgt über das Repo (Logik) und Docker Compose (Umgebung). Daten bleiben lokal; ein befülltes Ergebnis wird nur als verschlüsselter Dump unter Mandanten-/Berufsgeheimnis-Auflagen weitergegeben.

Hintergrund: SAP-Berechtigungsdaten zeigen, wer in einem (regulierten) Finanzsystem was darf. Das berührt Datenschutz, Berufsgeheimnis sowie — je nach Mandant — DORA-Auslagerung. Diese Grenze ist nicht verhandelbar.

---

## Architektur-Entscheidungen (verbindlich)

**AE-01 — Logik/Daten/Secrets getrennt.** `.gitignore` schließt `/data`, `/backups`, `.env` und `*.dump` aus. Passwörter nur über `.env` (lokal) bzw. Umgebungsvariablen.

**AE-02 — Schema reproduzierbar über `neo4j-migrations`.** Constraints und Indizes als versionierte Migrationsdateien (`V001__…`), idempotent.

**AE-03 — `Authorization` ist ein eigener Knoten, kein Edge.** Feldwerte innerhalb einer Berechtigung sind UND-verknüpft (z. B. `ACTVT=01` UND `BUKRS=1000`). Feldwerte liegen als **Properties** am `Authorization`-Knoten.

**AE-04 — Knoten/Property/Kante-Faustregel.** Knoten = wird traversiert/eigenständig abgefragt. Property = wird nur gelesen/gefiltert. Kante = das Verb (`ASSIGNED_TO`, `CONTAINS`, `HAS_AUTH`).

**AE-05 — Org-Werte als Property, nicht als Label/Knoten.** Kein `:CompanyCode1000`-Anti-Pattern. Org-Einheiten „wie sie kommen" (inkl. `*`).

**AE-06 — `*`/unbeschränkt wird in der Abfragelogik normalisiert.** Drei gleichbedeutende Zustände auf einen Nenner: expliziter `*`, Vollbereich (`LOW=' '`, `HIGH='ZZZ…'`), nicht gepflegtes Org-Level. Effekt: `*` verbreitert einen Konflikt.

**AE-07 — Gültigkeit gehört auf die Kante.** `validFrom`/`validTo` als Neo4j-`date`. `TO_DAT='99991231'` = unbegrenzt. Range-Index auf den Relationship-Properties.

**AE-08 — Effektive Gültigkeit = Schnittmenge über den ganzen Pfad.** Bei verschachtelten Sammelrollen muss das Datumsprädikat auf **jede** relevante Kante (`all(rel IN relationships(p) …)`). Auswertungen sind **stichtagsbezogen**.

**AE-09 — Beide Berechtigungspfade abbilden.** Rollenbasiert (`AGR_1251` via `AGR_USERS`) **und** direkt zugewiesene Profile (`UST04`/`UST12`, z. B. `SAP_ALL`).

**AE-10 — Abgeleitete Schicht ist von Rohdaten getrennt und regenerierbar.** Findings tragen Provenienz (`asOf`, `runId`), werden vor jedem Lauf per `DETACH DELETE` neu gerechnet, sind **nie Eingang** der nächsten Ableitung.

**AE-11 — SoD-Konflikttyp bestimmt den Ablageort.** Intra-Rollen-Konflikt (Design der Rolle) vs. Inter-Rollen-Konflikt (erst die Kombination) → `(:SoDConflict)` mit Evidenz-Kanten (`VIA_ROLE`/`VIA_PROFILE`).

**AE-12 — Did-Do knüpft am `Transaction`-Knoten an, nicht am `Authorization`-Knoten.** STAD/ST03N kennt die ausgeführte Transaktion, nicht Objekt/Feld.

**AE-13 — STAD ist Nutzungs-, kein Audit-Log.** Für Forensik SM20/SAL bzw. `CDHDR`/`CDPOS`. STAD/ST03N für Least-Privilege.

**AE-14 — Reproduzierbarkeit über gepinnte Versionen.** Docker-Image-Tags (Neo4j, NeoDash, APOC) fixieren.

**AE-15 — Container-only auf Windows.** Neo4j/NeoDash/`neo4j-migrations` als Container; keine lokale Neo4j-/Java-Installation. `cypher-shell` über den Container.

**AE-16 — Der Stichtag (`asOf`) ist eine Eigenschaft des Datasets, kein Lauf-/Check-Parameter.** Ein Dataset ist ein SAP-Extrakt zu einem festen Downloaddatum — eine Auswertung gegen ein *anderes* Datum als den eigenen Extraktstand ergibt ohne Änderungs-Tracking (`RSUSR100N`/Change Documents über die Zeit im selben Dataset) keinen Erkenntnisgewinn. `(:Dataset).asOf` wird einmalig bei Erst-Import gesetzt — explizit übergeben oder automatisch aus den Dateizeitstempeln des Import-Ordners abgeleitet (`_infer_dataset_asof()`: alle Tabellen eines Extrakts teilen sich praktisch immer denselben Exporttag), nur falls der Quellordner fehlt als letzter Ausweg `heute` — und bleibt über Re-Importe stabil. Ältere Datasets ohne den Wert (vor Einführung dieses Felds importiert) bekommen ihn lazy über denselben Mechanismus nachgetragen. `RunReq`/`ConsistencyRunReq` nehmen kein `asOf` mehr vom Client an, sondern lösen es serverseitig über `_dataset_asof()` auf. Bewusste Korrektur ausschließlich global über `PUT /datasets/{id}/asof` — wirkt auf alle folgenden Läufe/Checks dieses Datasets.

---

## Offene Arbeit

### Phase 7 — Konsistenzchecks (Qualität & Risiko des Berechtigungskonzepts)
**Ziel:** Über die SoD-Funktionstrennung hinaus die strukturelle **Qualität und allgemeinen
Risiken des geladenen Berechtigungskonzepts selbst** sichtbar machen — unabhängig von einer
konkreten SoD-Regel. Ergebnis ist ein **Katalog einzeln auswählbarer Checks**, strukturiert
abarbeitbar (analog zur Einzelfilter-/SoD-Auswahl), mit eigenem Ribbon-Einstieg.

Der **vollständige, laufend erweiterbare Check-Katalog** steht mit Begründungstext in eigener
Datei: [`KONSISTENZCHECKS.md`](KONSISTENZCHECKS.md) — wird unabhängig von dieser Roadmap
gepflegt, neue Checks dort einfach ergänzen. Zwei Bereiche, je ein Ribbon-Punkt:
**„User-spezifisch"** (Kategorien A/B/C/D/E — kritische Berechtigungen, Benutzerstamm-Hygiene,
Zuweisungskonsistenz, Gültigkeit/Zeitbezug, referenzielle Integrität) und
**„Rollen-spezifisch"** (Kategorie `R`, 18 Checks zu Rollendesign/-qualität — Kategorie `C` wurde
um die rollenstrukturzentrierten Checks bereinigt, die dort aufgegangen sind). Hier nur der
technische Rahmen:

- [x] **Checks-Katalog (Datenmodell) — Katalog persistiert, Check-Logik für alle Kategorien
  nachgezogen.** Jeder Check aus `KONSISTENZCHECKS.md` liegt zusätzlich strukturiert
  (id/category/title/description/prio/`implemented`/optional `cypherFile`) als **JSON je
  Kategorie** unter [`checks/`](checks/) (Schema: [`checks/SCHEMA.md`](checks/SCHEMA.md)) —
  analog zur Ruleset-Struktur, aber **ruleset-unabhängig**, ohne Vendor/Overlay-Trennung.
  **42 von 48 Checks haben Cypher** unter `cypher/checks/`: A (7/7), B (7/7), C (5/5), D (4/4),
  E (6/7), R (15/18). Details/Festlegungen je Check in `KONSISTENZCHECKS.md`, Abschnitt
  „Implementierungsnotizen Kategorie A"–„…R". Über die App ausführbar (s. API/UI). **B3 (Passwort-
  Kennzeichen) war zunächst fälschlich als „nicht umsetzbar" eingestuft** — auf Nutzer-Rückfrage
  korrigiert: USR02 enthält neben den Hash-Feldern auch reine Status-/Datumsfelder
  (`PWDINITIAL`/`PWDCHGDATE`/`PWDSETDATE`), die nicht ausgeschlossen sind; Loader nachgezogen,
  Check implementiert. **Bewusst zurückgestellt (nicht nur „offen"):** E6 (Rowcount-Abgleich,
  setzt die noch nicht gebaute Import-Evidenz voraus) und R5–R7 (abgeleitete Rollen/
  `DERIVED_FROM` — laut `docs/extraktionsleitfaden.md` keine bestätigte Quelle in den
  extrahierten Tabellen, `PARENT_AGR` ist die Sammelrolle, nicht die Ableitungsvorlage). E1–E3
  laufen als dokumentierte Proxy-Operationalisierung (`[~]`): der
  Loader hat kein TOBJ/TSTC-Stammdaten-Import, daher fehlender Objekt-/TCode-Text als
  Ersatzkriterium statt „nicht im Stammdaten-Import"; R13–R15 (SoD-Konflikt-Checks) verwenden
  automatisch den jüngsten `(:Run)` des Datasets, da der generische Check-Endpoint keine
  `runId` kennt. R17/R18 (redundante/überlappende Rollen) sind bewusst auf skalierbare
  Fingerprint- bzw. größenbegrenzte Ansätze reduziert (kein `O(n²)`-Vollvergleich).
- [x] **API/UI — Katalog + Ausführung erledigt (für Checks mit Cypher).** `GET
  /consistency-checks?area=user|role` liefert den gemergten Katalog des jeweiligen Bereichs.
  Ribbon-Gruppe **„Konsistenzchecks"** (Gruppe 4, zwischen Ergebnisse und Sichern) ist jetzt ein
  **Menü mit zwei Punkten** — **„User-spezifisch"** und **„Rollen-spezifisch"** — beide
  **wechseln im Hauptbereich** (kein Overlay/Dialog, analog zur Findings-Ansicht) auf **je eine
  umrahmte Tabelle pro Raster-Box** (User-Bereich gerastert nach Kategorie: Layout 2×2 + E
  zentriert darunter mit Kategorie-Pills A–E + „alle"; Rollen-Bereich gerastert nach dem Feld
  `group` der einzigen Kategorie `R`, ebenfalls 2×2 mit Themen-Pills — Struktur & Generierung,
  Zuordnung & Reichweite, Risiko & SoD, Wartbarkeit & Design statt einer 18-Zeilen-Tabelle). Je
  Zeile **Prüfung fett + Begründung darunter klein** (auch für fachlich nicht
  Kundige lesbar). Klick auf eine Zeile **wechselt** (kein Overlay/Dialog, wie der Katalog
  selbst) auf eine **eigene Ergebnis-Ansicht**: Titel links, **ID/Kategorie/Prio-Chips +
  „← zurück zum Katalog"** rechtsbündig auf Höhe der Überschrift (keine eigene Zeile); darunter
  **zweispaltig wie die Findings-Ansicht** (320px + Rest). **Links:** Begründung (immer
  sichtbar, auch bei nicht implementierten Checks), darunter bei `implemented: true` das
  Formular **Dataset/Stichtag** (vorbelegt aus dem aktiven Lauf) + „Ausführen" (Spinner während
  der Anfrage) → `POST /consistency-checks/{id}/run` (führt die hinterlegte `cypherFile` aus,
  genau **ein** Check pro Lauf, keine Mehrfachauswahl in v1) — **darunter eine
  Schnellauswahl-Liste „Weitere Checks · …"** mit allen Checks derselben Raster-Box (Kategorie
  bzw. `group`) (analog zur Läufe-Liste, funktioniert auch ausgehend von einem nicht
  implementierten Check), Klick wechselt direkt ohne Umweg über den Katalog, Dataset/Stichtag
  bleiben dabei erhalten.
  **Rechts** das Ergebnis mit **Tabelle/Graph-Pill** oben rechts (Graph für A1–A3 inzwischen
  scharf, sonst weiterhin deaktiviert, s. u.): hat die Cypher-Datei mehrere Statements
  (Zusammenfassung + Detailliste, z. B. `sap_all.cypher`), erscheinen oben **Summary-Kacheln**
  (Werte menschenlesbar übersetzt, z. B. `Active`→„aktiv", `Locked`→„gesperrt", ohne rohe
  Spaltennamen), darunter die **Detailtabelle** (dynamische Spalten je Check);
  Einzelstatement-Checks zeigen nur die Detailtabelle. „← zurück zum Katalog" wechselt zurück,
  ohne den Lauf zu verlassen. Nicht implementierte Checks zeigen rechts nur einen Hinweis statt
  eines Ergebnisses. **Keine Persistenz (bewusst):** kein `(:Run)`-Knoten, Ergebnis lebt nur im
  Browser für die Session; die zuletzt gesehene Trefferzahl wird clientseitig zwischengespeichert
  und ersetzt in der Katalog-Tabelle den Platzhalter „noch nicht ausgeführt" — UI-Cache, kein
  Server-Zustand, geht beim Neuladen verloren. **Offen:** Export, Graph für weitere Checks,
  Server-seitige Persistenz/Historie (falls künftig gewünscht).
- [x] **Graph-Pilot für A1–A3 — erledigt, mit Lizenz-Kurswechsel weg von NVL.** Geprüft, ob
  **Neo4j Visualization Library (NVL)** für den ersten echten Graph-Einsatz (s. „Umschalter
  Tabelle/Graph" weiter unten) genutzt werden kann — **verworfen**: NVLs Lizenz erlaubt den
  Einsatz nur mit Neo4j Aura (Cloud) oder einer kommerziellen Neo4j-Subscription, nicht mit der
  hier eingesetzten **Community Edition**; Aura wäre zudem ein Bruch der Vertrauensgrenze (Daten
  verlassen die lokale Umgebung). Stattdessen **Cytoscape.js** (MIT-Lizenz, keine
  Laufzeit-Abhängigkeiten, keine Telemetrie/Netzwerkaufrufe — geprüft im gebauten Bundle) lokal
  vendored unter `frontend/vendor/cytoscape/` (kein CDN, App bleibt offline lauffähig). Neues
  Schema-Feld `graphFile` (`checks/SCHEMA.md`, analog `rootCauseFile`) für Checks mit
  User→(Rolle→)Profil-Pfad; neuer Endpoint `POST /consistency-checks/{id}/graph` wandelt die
  Cypher-Zeilen generisch in Cytoscape-Knoten/Kanten um. Für **A1 (SAP_ALL)**, **A2 (SAP_NEW)**,
  **A3 (kritische Standardprofile)** umgesetzt (`*_graph.cypher`); der bisher deaktivierte
  „Graph"-Pill in der Konsistenzcheck-Ergebnisansicht ist für diese drei jetzt scharf (sonst
  weiterhin deaktiviert). Verifiziert per Playwright-Smoketest gegen einen laufenden Container:
  Knoten/Kanten rendern (User blau, Profile grün), Umschalten Tabelle↔Graph funktioniert, keine
  Konsolenfehler. **Offen:** weitere Checks mit Graph-Ansicht ausstatten; Layout-Feinschliff
  (Label-Überlappung bei vielen Usern um einen Profil-Knoten).
- [x] **Auf Nutzer-Feedback: generische Schwellwert-Parameter + Root-Cause-Drilldown.** Zwei
  neue, wiederverwendbare Erweiterungen des Check-Schemas (`checks/SCHEMA.md`): **`params`**
  (z. B. B1 „Tage ohne Logon" als Pill-Buttons 90/180/360 statt hart codiertem Literal — ersetzt
  bei Bedarf den in mehreren Checks verwendeten Literal-Workaround, B6 hat denselben Kandidaten)
  und **`rootCauseFile`** (eigene `.cypher`-Datei + `POST /consistency-checks/{id}/root-cause`,
  zeigt für einen einzelnen User aus der Detailtabelle die konkrete(n) Rolle(n)/Profil(e) samt
  Authorization-Feldwerten — Antwortformat identisch zum SoD-Root-Cause, UI nutzt denselben
  Dialog; aktuell nur für A4 umgesetzt, generisch für weitere Checks nutzbar). Außerdem:
  KPI-Kacheln, die nur eine nackte Zahl/Code ohne Kontext zeigten (A5, A7), liefern jetzt
  selbsterklärende Texte.
- [x] **Zweite Feedback-Runde: KPI-Spaltenreihenfolge-Bugfix + weitere Filter/Spalten.**
  Systematischer Bug gefunden und behoben: in mehreren Checks (B1, B2, C1, C3, D4/R3, E3, E4,
  R13) zeigte die KPI-Kachel die **falsche** Spalte groß (Sekundärwert statt Haupttreffer-
  zahl, in R13 sogar einen Lauf-**Namen** statt einer Zahl) — Konvention jetzt explizit in
  `KONSISTENZCHECKS.md` festgehalten: die letzte Spalte eines Summary-Statements ist immer die
  Treffer-Zahl. Außerdem auf Nutzer-Feedback: B2 zeigt Benutzertyp statt der wenig aussagekräftigen
  „Muster"-Spalte; B4 hat einen `$lockReason`-Pill-Filter (Sperrgrund); B5 zeigt `letzterLogon` +
  `personalnummer` als eigene Spalten, Status ist in einen Pill-Filter gewandert; C3 hat einen
  `$status`-Pill-Filter (aktiv/gesperrt); C1 zeigt Profilanzahl + Kurzvorschau statt einer
  teils >200 Einträge langen Profilliste je Zelle; A1 zeigt zusätzlich `letzterLogon`.
  Verifiziert (keine Bugs, sondern echte Datenlage): B6s viele `NULL`-Werte bei `letzterLogon`
  sind korrekt („nie angemeldet" zählt als sleeping) — auffällig hoher Anteil (~47 % der
  Dialog-User) im Testdatenbestand, ggf. gegen die Quelle zu prüfen; B7s 0 Treffer sind korrekt
  (keine User-IDs mit den geprüften Namensmustern in diesem Mandanten vorhanden).
- [x] **Dritte Feedback-Runde: B3 fälschlich als „nicht umsetzbar" korrigiert, C1-Logikfehler
  behoben, Pill-Filter ans Ergebnis verschoben.** B3 jetzt implementiert (s. „Bewusst
  zurückgestellt" oben). **C1 hatte einen echten Denkfehler:** „direkt zugewiesenes Profil" wurde
  als jede `HAS_PROFILE`-Kante vom User gelesen — tatsächlich schreibt SAP beim
  Benutzerabgleich generierte Rollenprofile (`T-*`) zusätzlich in `UST04` zurück, sodass `UST04`
  die **effektive**, nicht die rein manuelle Zuweisung abbildet. Im Testdatenbestand waren 582
  von 651 direkten `T-*`-Profil-Kanten (89 %) zugleich das generierte Profil einer aktuell
  zugewiesenen Rolle desselben Users — `direct_profile_assignments.cypher` schließt solche über
  eine gültige Rollenzuweisung erklärbaren Profile jetzt aus (377 statt 1349 betroffene User,
  deutlich präziser). **UI-Layout:** die `params`-Pills (B1/B4/B5/C3) sitzen jetzt — wie bei den
  SoD-Findings (Kritikalität/Ergebnistyp/Sleeping-Pills über der Tabelle) — in einer Pill-Zeile
  direkt am Ergebnis (über der Detailtabelle, unter den KPI-Kacheln) statt im linken
  „Ausführen"-Formular; Klick auf einen Pill löst bei bereits sichtbarem Ergebnis sofort einen
  neuen Lauf aus.
- [ ] **Export:** Konsistenz-Report (CSV, später Teil des Gesamt-Reports zusammen mit
  Import-Evidenz).
- [x] **Ribbon-Layout: Gruppen mit mehreren Befehlen als Menü — erledigt.** Gruppen mit mehr als
  einem Befehl („Ergebnisse", „Admin", „Konsistenzchecks") klappen als **aufklappbares Menü** auf
  (Klick öffnet, Klick daneben/auf einen Befehl schließt) statt alle Befehle nebeneinander zu
  zeigen. Gruppen mit nur einem Befehl bleiben ein direkter Button. Ribbon-Gruppen durchnummeriert
  (1 Daten · 2 Auswertung · 3 Ergebnisse · 4 Konsistenzchecks · 5 Sichern · 6 Verwalten · 7 Admin).

**DoD:** Ein strukturierter, erweiterbarer Katalog an Qualitäts-/Risiko-Checks ist über die UI
auswählbar, ausführbar und mit Drill-down auf die betroffenen Objekte einsehbar — unabhängig von
der SoD-Funktionstrennungsprüfung.

---

### Phase 9 — App: offene Bausteine

Die App-Grundfunktionen stehen (siehe Archiv). Offen sind die folgenden Ausbauten.

#### Import-Evidenz (Vollständigkeitsnachweis gegen Quell-SAP)
- [ ] **Persistente, abrufbare Import-Statistik je Lauf.** Heute nur flüchtig (Job-Counts) bzw. Konsole (`99_validate`).
  - **Persistenz:** `(:Import {dataset, importedAt, lang})` + je Tabelle `(:ImportTable {table, sourceRows, droppedColumns})` (der Konverter liefert Zeilen/verworfene Spalten bereits) + resultierende Graph-Zähler je Label/Kante.
  - **Abgleich/Checks:** je Quelltabelle **Quellzeilen ↔ Graph-Ergebnis** mit dokumentierter Beziehung — **1:1** (USR02→User, AGR_DEFINE→Role …, Abweichung = Flag) vs. **aggregiert** (AGR_1251→gruppierte `Authorization` nach AE-03; UST12-Feldwerte) → beide Zahlen zeigen, nicht als Fehler werten. Gefilterte Zeilen (`DELETED='X'`) ausweisen.
  - **API/UI:** `GET /datasets/{d}/import-evidence`; UI mit **KPI-Kacheln** (Knoten/Kanten, Tabellen, verworfene Sensibel-Spalten) **+ Reconciliation-Tabelle** (Tabelle · Quellzeilen · Graph · Status), hübsch.
  - **Export:** **Import-Evidenz-Report** (CSV, später PDF).

#### Geführte Auswertung (Auswerten v2) — gezielte Filter-/Scope-Auswahl
Statt „ein Lauf über alle 600+ Filter": gezielt **auswählen, was** ausgewertet wird, **für wen**, **wie
tief**. Vieles existiert als Backend-Parameter (`sodRules`, `userTypes`, `excludeLocked`, `sleepDays`,
`minCriticalityRank`) — es fehlt v. a. die **geführte Auswahl-UI** und etwas Backend.

- [ ] **Katalog-Auswahl (Filter/Regeln):** Browser über Queries (Einzelfilter) **und** SoD-Regeln, **filterbar** nach Kritikalität (z. B. nur very-critical), **Namensmuster** (z. B. `BC_*`), Modul, queryType. Mehrfachauswahl → Lauf nur über die Auswahl. *(Kritikalität/explizite Regel-IDs ✓ als Param; Muster-/Modul-Filter + UI neu.)*
- [ ] **Zwei Auswertungsarten:** **(a) Einzelfilter / Can-Do** — „wer matcht Query X" (nur Materialisierung der gewählten Queries, ohne SoD); **(b) SoD-Konflikte** — bei Auswahl bestimmter SoD-Regeln **zuerst nur deren Einzelfilter** (Klausel-Queries) materialisieren, dann SoD → **scoped materialize** statt „alle SoD-Queries". *(neu.)* Damit auch **„Can-Do nach Org"**: „wer kann *Funktion* in *Buchungskreis X* (AND/OR/Bereich)" — Einzelfilter + `orgFilters` auf BUKRS/WERKS/EKORG/… (Matching-Seite ✓; braucht nur die Einzelfilter-Ansicht).
- [x] **Org-Filter im App-Lauf wirksam machen — erledigt.** `materialize_matches.cypher` wertet jetzt `$orgMode` (`ignoreOrg`/`wildcardOnly`/`filtered`) + `$orgFilters` aus (Logik aus `query_match` + Modus `wildcardOnly` ergänzt; AGR_1252-Auflösung genutzt). **Allgemein über ALLE Org-Ebenen** (BUKRS, WERKS, EKORG, VKORG, GSBER, … — aus USORG) **und Kombinationen** (`orgFilters` = Map je Feld, z. B. `{BUKRS:…, EKORG:…}` = „Buchungskreis **und** Einkaufsorg"). Org-Modus + Filter werden auf `(:Run)` protokolliert (`run.orgMode`/`run.orgFilters`). Verifiziert: standard ≠ übergreifend (`wildcardOnly` schränkt ein). *Hinweis: USORG = Org-Feld-Registry (welche Felder Org-Ebenen sind); die bindenden Werte stehen in den Auths (AGR_1251/UST12/AGR_1252) — **nicht** in USOBT_C/USOBX_C (das ist die SU24-Vorschlags-/Prüfschicht, → `CHECKS`).*
- [~] **Multi-Varianten-Läufe.** Jede Variante (z. B. „Standard", „Übergreifend", „BUKRS=…") = ein eigener, **benannter** `(:Run)`: `(:Run).title` (optional, Backend-Fallback auf `runId`) ergänzt in `evaluate_sod.cypher` + `RunReq`; Dialog „Neuer Lauf" hat ein **Titel-Feld**, das aus dem Org-Profil **automatisch vorausgefüllt** wird (manuell überschreibbar). Lauf-Liste zeigt den Titel als Hauptlabel (Run-ID als Mini-Chip darunter), Ergebnis-Überschrift folgt dem aktiven Lauf. UI-Sidebar umsortiert: **Filter oben, Läufe darunter** in eigenem umrahmten Kasten. Offen: **paralleles Anlegen/Starten mehrerer Varianten in einem Schritt** + Gruppierung als „Varianten-Set" — setzt zudem „MATCHES nach runId scopen" (s. u.) voraus, sonst überschreiben sich parallele Läufe beim Materialisieren.
- [~] **Nutzer-Scope verfeinern:** Nutzertyp und Sleeping sind jetzt zusätzlich **Ergebnisfilter** (nicht nur Lauf-Kriterium) — `GET /findings`/`/findings/summary`/`/matches` nehmen `userType`/`sleeping` an, Sidebar hat dafür eigene Auswahlmenüs (s. u., erledigt). Noch offen: **Sleeping-Schnellwahl 90/180/360 Tage** als eigenes Eingabefeld (Sleeping ist bisher nur das beim Lauf gesetzte `sleepDays`-Fenster, nicht frei wählbar pro Filter); **Gesperrte nach Sperrtyp** auswählbar (failed_logons / admin_local / admin_global — Daten liegen als `lockReasons` vor) statt nur `excludeLocked`-Bool. *(Sperrtyp-Filter neu.)*
- [x] **Lauf verwalten — erledigt.** `POST /runs/{runId}/delete` löscht einen einzelnen Lauf (`(:Run)` + dessen `SoDConflict`-Findings inkl. Evidenz-Kanten; `MATCHES`/`PROVIDES` sind lauf-übergreifende Zwischenergebnisse und bleiben unberührt, s. o.) — UI: eigener Lauf-Select im „Bereinigen"-Dialog. Zusätzlich **Lauf-Backup/-Restore** als eigener Bereich im „Sichern"-Dialog (getrennt von den Quelldaten-Backups): `POST /runs/{runId}/backup` sichert Run+Findings (ohne Evidenz — die ist teuer und über „Evidenz" jederzeit neu berechenbar) als ZIP (`manifest.json`/`run.json`/`findings.json`); `GET /runs/backups` (Liste) + `.../download` + `POST /runs/backups/{file}/restore`. Dafür neu: **`Dataset.uid`** (randomUUID, einmalig bei Erst-Anlage in `load/00_dataset.cypher`, lazy Backfill für ältere Datasets) — bleibt über Re-Importe desselben Datasets stabil, ändert sich nur bei Löschen+Neuanlage unter demselben Namen. Jeder Lauf trägt seine `datasetUid` (`evaluate_sod.cypher`); Restore vergleicht sie gegen die aktuelle Dataset-uid und verlangt bei Abweichung eine explizite Bestätigung (`force=true`), bevor er wiederherstellt. Restore selbst matcht User/Regel nur per `MATCH` (nie `MERGE`) — Findings, deren Bezug im aktuellen Dataset nicht mehr existiert, werden übersprungen statt Phantom-Knoten anzulegen (AE-10).
- [ ] **Evidenz-Perf:** vorab geflachte Erreichbarkeit `(:Role|:Profile)-[:GRANTS]->(:Authorization)` (transitive Hülle CONTAINS/HAS_PROFILE), damit `explain_sod` (intra/inter + VIA_ROLE) ein Lookup statt variabler Pfadsuche wird → **Evidenz default-on** möglich. *(Optimierung der v1.)*

#### Interaktive Ergebnisse (Drill-down) + Graph/Tabelle
Heute sind die Ergebnis-Listen statisch. Interaktiv machen — größtenteils mit vorhandenen Daten:

- [x] **Klickbare Drill-downs — erledigt.** `GET /findings` nimmt optional `user`/`rule`/`userType` (Mehrfachauswahl)/`sleeping`/`ruleCriticality` an (User-/Regel-Zelle in der Findings-Tabelle ist klickbar); `GET /matches?runId&query&user&userType` + `GET /queries?runId` (Query-Auswahl der SoD-relevanten Queries des Laufs) liefern „wer matcht Query X" über das `MATCHES`-Zwischenergebnis. `GET /findings/summary` liefert die KPI-Aggregate (Findings/betroffene Regeln/sleeping) für denselben Filterkontext — unabhängig vom 500er-Limit der Liste. UI: **Sidebar links jetzt schlank** — nur noch Nutzertyp, User, Einzelberechtigung, SoD. Nutzertyp als **Ankreuz-Dropdown** (Checkbox-Panel statt nativem `<select multiple>`, Button zeigt gewählte Typen, Labels mit SAP-Code-Präfix „A – Dialog", „B – System", „S – Service", „C – Communication", „L – Reference"). *Layout-Bug behoben:* die globale Regel `input, select { width:100% }` hatte auch die Checkboxen im Panel auf volle Zeilenbreite gestreckt, was im Zusammenspiel mit dem ursprünglichen Flex-Layout zum schiefen/überlaufenden Rendering führte (Text lief in die Tabelle); Panel jetzt auf einfaches Block-Layout (kein Flex) umgestellt, Checkbox-Breite explizit `auto`. Kritikalität (SoD) und Sleeping sind aus der Sidebar raus und sitzen jetzt **als farbige Pill-Buttons über der Ergebnistabelle** (eigene `.resultbar`-Zeile, immer sichtbar, klickbar statt Dropdown — Kritikalität-Pills nutzen dieselben `.tag.*`-Farben wie die Tabelle, aktive Pille hervorgehoben per Ring/Opazität); Klick wendet sofort an. Die bisherige „Kritikalität (Einzelberechtigung)"-Eingrenzung wurde ersatzlos entfernt (Einzelberechtigung-Liste zeigt jetzt immer alle Queries). Klick auf eine User-/Regel-Zelle setzt den passenden Filter weiterhin direkt (setzt dabei die SoD-Kritikalität-Pille zurück, falls sie die Zielregel sonst ausblenden würde); aktiver Filter als Chip über der Tabelle mit „zurücksetzen". **KPI-Kacheln folgen dem aktiven Filterkontext** (`refreshKpis()` ruft `/findings/summary` mit allen aktuell gesetzten Filtern). Einheitlicher 5-stufiger Kritikalitäts-Farbverlauf (sehr-hoch=tiefrot … niedrig=grün) in Findings-Tabelle und Kritikalitäts-Pills (`CRIT_COLOR`). **Lauf-Karten reduziert** auf Bezeichnung (Titel/Run-ID), **Filterset-Name** (Ruleset, aus `metaCache.rulesets`), Stichtag und Erstellungs-Datum/-Zeit (`run.generatedAt`). **Hell/Dunkel-Umschalter** ganz oben im Header (`#themeToggle`, persistiert in `localStorage`), CSS-Variablen (`--bg`/`--panel`/`--line`/`--fg`/`--muted`/`--accent`) per `html[data-theme="light"]` überschrieben, inkl. angepasster Kritikalitäts-Tag-Farben für besseren Kontrast auf hellem Hintergrund. *Bekannte Einschränkung (unverändert, betrifft auch Variante A): `MATCHES` ist nur pro Ruleset materialisiert, nicht pro `runId` — der Query-Check zeigt daher den Stand der zuletzt materialisierten Variante, nicht zwingend des gerade angezeigten Laufs, bis „MATCHES nach runId scopen" (Multi-Varianten) erledigt ist.*
- [ ] **Kaskadierende Sidebar-Filter.** Aktuell sind User-/Einzelberechtigung-/SoD-Dropdown unabhängig: alle drei werden einmalig beim Laden des Laufs befüllt (`populateFilterSelects()`/`loadQueriesForRun()`/`loadSodRuleNames()`, `frontend/index.html`) und bleiben bei Auswahl eines anderen Filters unverändert. Gewünscht: Auswahl eines Users schränkt Einzelberechtigung- **und** SoD-Dropdown auf das für ihn tatsächlich Mögliche ein (statt immer den vollen Katalog/alle Lauf-Regeln zu zeigen) — macht die Listen kürzer und verhindert „Auswahl ohne Treffer".
- [x] **Root-Cause-Drill-down unter die Evidenz — erledigt.** Neuer Endpoint `GET /root-cause?runId&user&query` (`backend/app.py`): pro Berechtigungsobjekt der Query (+ TCode-Prüfung als eigener Pseudo-Block, falls `disregardTcode=false`) wird gezeigt, **welche Rolle(n)/Profil(e) mit welcher konkreten `Authorization` (Objekt/Feld/Werte)** die Anforderung (`AuthReq`) erfüllen — nicht mehr nur „welche Rolle" wie `VIA_ROLE`/`VIA_PROFILE` (AE-11), sondern der tatsächliche Root-Cause-Datensatz; macht sichtbar, wenn verschiedene Objekte durch verschiedene Rollen gedeckt werden (AE-03/AE-09). Logik (`_SATISFIED_BY_CYPHER`) ist dieselbe Treffer-Prüfung wie in `explain_sod.cypher`/Schritt 1 (`PROVIDES`), nur pro Objekt statt pro ganzer Query, und pro Rolle/Profil statt nur „irgendein Akteur". *Stolperstein:* Cypher-String-Slicing `k[2..]` auf einer Map-Comprehension-Variable löste einen `CypherSyntaxError` aus („Type mismatch: expected List<T> but was String") — `substring(k,2)` statt `k[2..]` behoben. UI: in der Matches-Tabelle „wer matcht" (Einzelfilter-Kontext) hat jede Zeile einen **„Root-Cause"-Button**, öffnet einen Dialog mit den Objekt-Blöcken (Anforderung oben, erfüllende Rolle/Profil + Werte darunter).
- [x] **Nutzerzentrische Auswahl: KPI-Kontext-Chips + Ergebnistyp-Pills — erledigt.** Wählt man einen User (und optional zusätzlich eine Regel über Klick auf die Regel-Zelle, ohne den User-Filter zu verwerfen — Drill-down ist jetzt additiv statt exklusiv), erscheinen **Kontext-Chips „Nutzer: X" / „Regel: Y"** oben bei den KPI-Kacheln (`#resultContext`) + ein **Tabelle/Graph-Umschalter** (Graph vorerst deaktiviert, „kommt später" — echter Graph hängt am Cytoscape.js-Punkt unten, Technik bereits am Konsistenzcheck-Graph-Pilot A1–A3 erprobt, s. Phase 7). Bei User **und** Regel zusammen (= genau 1 Finding) erscheint ein **„Verursachende Rollen/Profile"-Panel** (`#causingActors`, aus `f.roles`/`f.profiles`) — ersetzt die alte Tabellenspalte „Verursacht durch", die aus der Findings-Tabelle entfernt wurde; stattdessen zeigt die Tabelle jetzt **„Bezeichnung"** neben der Regel-Spalte (`sodRuleNames[f.rule]`). Die **Sleeping-Pillzeile wurde ersetzt** durch **Ergebnistyp (alle/Einzelfilter/SoD)**: „Einzelfilter" zeigt die Matches-Tabelle („wer matcht") auch **ohne** vorher eine konkrete Query in der Sidebar zu wählen (alle Queries des Users); „alle"/„SoD" zeigen unverändert die Findings-Tabelle (es gibt noch keine kombinierte Ansicht beider Typen). *Bekannte Einschränkung:* Sleeping ist dadurch **nicht mehr über die UI filterbar** (Backend-Parameter `sleeping` existiert weiterhin, nur kein Pill/Control mehr dafür) — falls das vermisst wird, müsste es an anderer Stelle (z. B. im Nutzertyp-Panel) wieder angeboten werden.
- [x] **Root-Cause auch für SoD-Regeln — erledigt.** `GET /root-cause` nimmt jetzt alternativ `rule` statt `query` an: pro Klausel der Regel wird die vom User tatsächlich gematchte Query (`(:User)-[:MATCHES]->(:Query)`, auf Klausel-Kandidaten `(:SoDRule)-[:HAS_CLAUSE]->(:Clause)-[:NEEDS]->(:Query)` eingeschränkt) genauso aufgeschlüsselt wie im Einzelfilter-Fall — Antwortformat einheitlich auf `blocks[]` (Label + Objekte) umgestellt. UI: „Root-Cause"-Button im „Verursachende Rollen/Profile"-Panel (Nutzer+Regel-Kontext).
- [x] **SoD-Kurzbezeichnung nachgezogen — erledigt.** Die Query-Kurzbezeichnungs-Bereinigung (s. o.) hatte `SoDRule.shortDescription` nicht mitgenommen. Da SoD-Regeln **keinen Overlay-Mechanismus** wie Queries haben (`sod_rules.json` ist die einzige Quelle, kein `*.custom.json`), wurde die Bereinigung direkt in die drei `sod_rules.json` geschrieben (reine Datenänderung, keine Logikänderung) — nur wo die Beschreibung auf einen abtrennbaren Code-/Query-Klammerausdruck endet, nicht bei booleschen Teilausdrücken wie „(A) AND (B)" (KPMG_R3: 21/22 Treffer; CSI/CSI_BI: 0, da deren Beschreibungen keine solchen Klammern haben).
- [x] **Kaskadierende Sidebar-Filter — erledigt.** Bei gewähltem User schränken sich Einzelberechtigung- (`updateQueryCascade()`, über `/matches?user=` ohne `query`) **und** SoD-Dropdown (`renderRuleSelect()`, aus dem schon geladenen `allFindingsForRun`) auf das für ihn tatsächlich Gefundene ein — sowohl beim Ändern des User-Dropdowns als auch beim Filtern/Tabellenzellen-Klick. Außerdem: neuer Endpoint `GET /users/{id}?runId=` (Name/Typ/Status); der Kontext-Chip „Nutzer: …" zeigt jetzt **UserID · Name · Typ · Status** statt nur der ID. Sleeping-Pillzeile ist jetzt **nur bei Ergebnistyp „alle" sichtbar** (bei „Einzelfilter"/„SoD" ausgeblendet + zurückgesetzt — beim „SoD"-Modus auf Wunsch nicht mehr anwendbar).
- [ ] **Umschalter Tabelle/Graph — echter Graph für SoD-Konfliktpfade** — Konfliktpfad **User → Rolle/Profil → Query → Regel** (nutzt die Evidenz-Kanten `VIA_ROLE`/`VIA_PROFILE`). Der Tabelle/Graph-Umschalter selbst ist da (s. o.), nur „Graph" ist noch deaktiviert. Technik/Lib-Entscheidung ist bereits getroffen und am einfacheren Fall erprobt (Konsistenzcheck-Graph-Pilot A1–A3, Phase 7: **Cytoscape.js**, lokal vendored, nicht NVL — Lizenzgrund dort dokumentiert); hier nur noch Cypher (mehrere Knotentypen + Evidenz-Kanten statt nur User→Profil) + Wiring auf den bestehenden Pill.

#### Anzeige, Vergleich, Export, Admin
- [ ] **„Fancy" Aufbereitung — gebrandetes Frontend mit Cytoscape.js.** **Ersetzt den temporären NeoDash-PoC** (Phase 6, Archiv). KPIs, **Graph-Darstellung der Konfliktpfade** (Cytoscape.js statt Neo4j Visualization Library — NVL verworfen, Lizenz nur für Aura/kommerzielle Subscription, s. Phase 7 Graph-Pilot) — visualisiert genau die Evidenz-Kanten (`VIA_ROLE`/`VIA_PROFILE`), Heatmap/Matrix, Drill-down. Die NeoDash-Karten-Cypher (`dashboards/sod_poc.json`) sind die Vorlage.
  - [ ] **NeoDash danach vollständig entfernen** (sobald das Cytoscape.js-Frontend steht): Compose-Service `iam-neodash` (Port 5005) raus; Erwähnungen in `README.md`/`docs/` und im Laufzeit-Diagramm streichen; `dashboards/sod_poc.json` nach Portierung archivieren oder löschen; Pin in `AE-14` entsprechend reduzieren.
- [ ] **System/Mandant-Vergleich:** „neuer Stand/Mandant" **oder** „Vergleich zu bestehendem" → **Vergleichs-Abfragen** über zwei `dataset` (neue/entfallene Konflikte, Delta je Regel/User).
- [~] **Export native `.xlsx`.** CSV-Export der Findings ist erledigt (Archiv). Offen: natives Excel (z. B. `openpyxl`) und weitere Sichten (Top-Regeln, Matrix). Schließt den **Import-Evidenz-Report** und den Ergebnis-Export zusammen.
- [~] **Admin-Bereich — Funktionen.** Heimat (Ribbon-Gruppe „Admin", zeigt Rulesets) ist erledigt (Archiv). **Einzelfilter-Editor (Query-Metadaten) — erledigt, vorgezogen.** „Einzelfilter nachjustieren (Ruleset-Editor)" im Admin-Dialog scharfgeschaltet: bearbeitet **Bezeichnung/Kritikalität/Modul/Query-Typ/disregardTcode** bestehender Queries und kann neue Queries **aus einer bestehenden ableiten** (authorizations/transactions 1:1 übernommen, nicht editierbar in v1). Persistenz **Round-Trip auf die JSON**, aber **vendor-getrennt**: Edits/Ableitungen landen in einem Overlay `rules/<Ruleset>/queries.custom.json`, die Vendor-Datei (`queries.json`) bleibt unberührt — `load_ruleset.cypher` liest beide Dateien (Vendor zuerst, Overlay danach, `coalesce()`-Merge: im Overlay nicht gesetzte Felder bleiben unverändert), Speichern/Ableiten löst sofort einen Reload aus (`POST /admin/rulesets/{ruleset}/queries/...`). Voraussetzung: Backend-Mount für `rules/` von `:ro` auf **rw** (nur Backend-Container; der neo4j-Mount bleibt `:ro`). Dabei nebenbei: **Bezeichnung statt nur ID** in den Sidebar-Filtern „Einzelberechtigung" (`Query.description`, bisher nicht geladen → Loader ergänzt) und „SoD" (neuer `GET /sodrules?runId=` liefert `SoDRule.description`, war im Graph schon vorhanden). Offen/zurückgestellt:
  - [x] **Kurz-/Langbezeichnung vorbereitet — erledigt.** Neues optionales Feld `shortDescription` (Kurzbezeichnung) neben `description` (Langbezeichnung) für `Query` **und** `SoDRule` (`rules/SCHEMA.md`, `load_ruleset.cypher`, `/queries`, `/sodrules`, Editor-Formular). Sidebar-Filter „Einzelberechtigung"/„SoD" zeigen jetzt `shortDescription || description || id` — solange keine Kurzbezeichnungen gepflegt sind, bleibt es bei der (oft langen) Langbezeichnung, daher noch keine reale Daten-Pflege in v1. *Bekannte Einschränkung:* ein Feld, das ausschließlich im Overlay existiert (kein Vendor-Gegenstück), lässt sich über den Editor aktuell nicht auf „leer" zurücksetzen (Reload kann ein rein-Overlay-Feld nicht durch `coalesce()` löschen) — für v1 hingenommen, bei Bedarf später ein explizites „löschen"-Token einführen.
  - [x] **Kurzbezeichnungen vorbereinigt — erledigt.** Einmaliges Skript (nicht Teil der App)
    hat fuer alle drei Rulesets `shortDescription` = Langbezeichnung **ohne den abschließenden
    Klammer-Ausdruck** (i. d. R. die Transaktionscodes, z. B. „BC-SEC - Replace in Debugging (/h)"
    → „BC-SEC - Replace in Debugging") ins Overlay (`queries.custom.json`) geschrieben — nur wo
    sich dadurch tatsaechlich etwas aendert (KPMG_R3: 600/604, CSI: 150/733, CSI_BI: 152/735 —
    CSI-Bezeichnungen sind meist schon kurz/ohne Klammern, daher seltener Treffer). Vendor-Datei
    unberuehrt; jederzeit im Query Management nachschaerfbar.
  - [x] **Query Management als eigene Seite — erledigt.** Statt Modal-Dialog: eigene Seite `frontend/admin.html` mit eigener Ribbon-Bar (**Anzeige** = Aktualisieren · **Editieren** = Speichern/Abbrechen, aktiv erst bei Änderung · **Backup** = Overlay-Datei herunterladen, `GET /admin/rulesets/{ruleset}/overlay/download` · **Zurück** = Link zur Auswertung). Layout: links Filterset-Auswahl (von 3 Rulesets) + durchsuchbare Query-Liste, rechts Detail mit **vier Tabs** — **Stammdaten** (bisherige Metadatenfelder), **Aufbau** (TCodes + Berechtigungsobjekte, reine Anzeige, neuer Detail-Endpoint `GET /admin/rulesets/{ruleset}/queries/{queryId}` liefert die vollständige gemergte Query inkl. `authorizations[]`/`transactions[]`), **Risiko** und **Controls** (je ein Freitext-Feld, neue optionale Query-Felder `risk`/`controls` — Schema/Loader/API analog zu `shortDescription` ergänzt, landen ebenfalls im Overlay). Admin-Dialog in der Haupt-App verlinkt jetzt nur noch dorthin (`<a href="/admin.html">`); der alte Editor-Modal-Dialog wurde entfernt. „Ableiten" (neue Query aus bestehender) ist mit auf die neue Seite gewandert. **Stammdaten stehen dauerhaft sichtbar** (eigener umrahmter Block) **über** den Tabs (nur noch Aufbau/Risiko/Controls als Tabs, nicht mehr Stammdaten als vierter Tab); Tab-Leiste optisch deutlicher (aktiver Tab hervorgehoben statt nur Unterstrich). **Suche** unterstützt `*` als Platzhalter (z. B. `BC-SEC*`); zusätzliche Filter nach **Modul/Kritikalität/Query-Typ** (aus den geladenen Queries abgeleitete Dropdowns).
  - [x] **Admin-Ribbon entschlackt + Fehlerprotokoll — erledigt.** Der alte Admin-Dialog (Rulesets-Übersicht + Link) ist weg: die Ribbon-Gruppe „Admin" hat jetzt zwei direkte Punkte — **„Query Management"** (Link direkt auf `/admin.html`, kein Zwischendialog mehr) und **„Fehlerprotokoll"** (neuer Dialog, listet fehlgeschlagene Jobs). Neu **persistent über Container-Neustarts hinweg**: `backend/app.py` schreibt bei jedem Job-Fehler (Import/Lauf/Backup/Restore/Bereinigen/Reset/Explain) zusätzlich zum `jobs`-Dict eine Zeile (`{ts, jobId, kind, request, message}`) nach `data/logs/job_errors.jsonl` (`_log_job_error()`); neuer Mount `./data/logs:/app/data/logs` im Backend-Service (war bisher nur in den Neo4j-Container gemountet). `GET /admin/job-errors?limit=` liefert die Einträge neueste zuerst. Zusätzlich: **Kopfzeile zeigt jetzt das aktiv angewendete Ruleset** als eigenen Chip (`#chipRuleset`, zwischen Hell/Dunkel-Umschalter und „verbunden"), gefüllt aus dem Ruleset des gerade angezeigten Laufs (`showFindings()`).
  - [x] **SoD-Pflegeseite analog zu Queries — erledigt.** Query Management hat jetzt einen **Modus-Umschalter „Einzelfilter"/„SoD"** (`#modePills`), der Liste/Filter/Detailbereich umschaltet, ohne die Auswahl im jeweils anderen Modus zu verwerfen. SoD-Detail: **Stammdaten** dauerhaft sichtbar (Kurz-/Langbezeichnung, Kritikalität, Reason-Code, read-only) + drei **Tabs** — **Aufbau** (CNF-Klauseln, je Klausel die enthaltenen Queries mit Bezeichnung — nutzt die schon geladene Query-Liste, kein Extra-Request; Fallback auf `expression`+`variables`-Tabelle, solange ein Ruleset noch keine `clauses` hat, s. Phase-X-Backlog „CSI-Rulesets CNF-zerlegen"), **Risiko**, **Controls** (Freitext, neue optionale SoDRule-Felder `risk`/`controls`, analog zu Query). Backend: SoD-Regeln haben jetzt ebenfalls einen **Overlay-Mechanismus** (`sod_rules.custom.json`, vorher nicht vorhanden — die einmalige Kurzbezeichnungs-Bereinigung hatte deshalb direkt in die Vendor-Datei geschrieben) — `load_ruleset.cypher` liest Vendor+Overlay zweistufig wie bei Queries (`coalesce()`-Merge); neue Endpoints `GET /admin/rulesets/{ruleset}/sodrules`, `GET .../sodrules/{ruleId}`, `PUT .../sodrules/{ruleId}`, `GET .../sodrules/overlay/download`. **Kein „Ableiten"** für SoD in v1 (nicht angefragt) — nur Metadaten-Edits an bestehenden Regeln, keine neuen/abgeleiteten SoD-Regeln über die UI.
  - [ ] **Authorizations/TCodes im Editor bearbeitbar machen** (v2) — bisher nur 1:1-Kopie beim Ableiten/Anzeige im Aufbau-Tab, keine UI für die verschachtelten Objekt/Feld/Werte-Listen.
  - [ ] **USOBT-gestützter Query-Builder** (v2, "Profilgenerator-Logik"): neue Queries durch **kontextbasierte Auswahl von Transaktion → Berechtigungsobjekten** bauen statt freier Eingabe — USOBT/USOBX als eigener, vom Dataset getrennter Graph-Layer (ist je Berechtigungskonzept/Set stabil, aber bei Bedarf gegen das aktuelle Set **abzugleichen/neu zu laden**, wenn neue Queries gebaut werden).
  - [ ] **Stammdaten-Blatt: Query → System-Typ-Zuordnung** (v2, „für die Zukunft"): welche Query zu welchem Quellsystem-Typ gehört (SAP R/3, SAP S/4HANA, künftig weitere) — Vorstufe für system-übergreifende/-spezifische Rulesets, ohne das Datenmodell zu verzweigen.
  - [ ] **Filterset-/Konnektor-Import** für weitere Systeme — perspektivisch **SAP S/4HANA, Azure AD/Entra, Microsoft Dynamics, Salesforce** (je System ein eigenes Ruleset; Datenmodell bleibt gleich).
- [ ] **Kein eigenes Benutzer-/Berechtigungskonzept** (bewusste Entscheidung): die App läuft lokal bzw. wird als Container verteilt; Zugriff über die (lokale/Unternehmens-)Umgebung abgesichert. Eine Auth-Schicht (SSO/OIDC am Ingress) kommt erst, wenn die App **mehrbenutzerfähig zentral** betrieben wird — siehe Deployment-Notiz (Phase 10).

**DoD (Phase 9):** Eine transportable App, in der Import, parametrierte Auswertung, Vergleich, Anzeige, Export und Backup/Restore ohne JSON-Pflege bedienbar sind — lokal, ohne dass Mandantendaten die Umgebung verlassen.

---

### Phase 8 — Did-Do (Nutzung aus STAD/ST03N) — *die Kür, zuletzt*
**Ziel:** Nutzungssicht und Can-Do×Did-Do-Matrix. Bewusst als Letztes — wertvoll, aber nicht auf dem kritischen Pfad.

- [ ] Extraktionsweg festlegen: ST03N-Aggregate (`SWNC_COLLECTOR_GET_AGGREGATES`) als Einstieg; bei Bedarf Roh-STAD; für Forensik SAL/`CDHDR`.
- [ ] `EXECUTED`-Kanten (User→Transaction) mit `count`/`firstSeen`/`lastSeen`/`taskType`/`asOf`/`runId` in die Snapshot-Schicht.
- [ ] Matrix-Abfragen: ungenutzte Berechtigungen (Least-Privilege), materialisierte SoD (Did-Do auf beiden Konfliktseiten).
- [ ] Caveats dokumentieren: Aufbewahrungsfenster, selten-aber-vital, indirekte Aufrufe, kein Audit-Log (AE-13), S/4-Fiori/OData.
- [ ] **Datenschutz/Mitbestimmung** (§ 87 BetrVG): Pseudonymisierung der User-ID; Klartext nur im begründeten Einzelfall.

**DoD:** Matrix-Auswertung lauffähig; ungenutzte kritische Berechtigungen und materialisierte SoD-Konflikte werden ausgewiesen.

---

### Phase 10 — Verteilung & Reproduzierbarkeit
**Ziel:** Weitergabe an andere Rechner/User ohne Datenweitergabe.

- [ ] `docker-compose.yml` mit gepinnten Versionen finalisieren.
- [ ] Onboarding-`README`: klonen → `docker compose up` → eigene SAP-Extrakte (Ordner/ZIP) → App.
- [ ] Klarstellen: Über Repo/Compose wandert nur Logik/Umgebung, nie Mandantendaten.
- [ ] Verfahren für Ergebnisübergabe (`neo4j-admin database dump`, verschlüsselt, unter Auflagen) dokumentieren — Ausnahmefall.

**Deployment-Optionen.** Verteilungseinheit ist heute **Docker Compose** (lokal, ein Befehl). Der Stack
ist **Kubernetes-fähig** (interner, abgesicherter Cluster):
- **neo4j** als `StatefulSet` mit **PVC** (Community = Single-Instance), Passwort als `Secret`.
- **backend** als `Deployment` (vorerst **1 Replica** — Jobs in-memory; für Skalierung Job-Status in Shared Store). Code/Config ins Image backen; `data/import` + `backups` als **PVC**. Hinweis: `neo4j` braucht Import-Verzeichnis und `rules/` ebenfalls als Volume.
- **Zugang** über `Service`/`Ingress` **nur clusterintern bzw. hinter Unternehmens-Auth** (SSO/OIDC, NetworkPolicy). „public" = interner, gesicherter Cluster — **nicht** offenes Internet.
- Optional: Helm-Chart/Kustomize.

**DoD:** Ein Kollege bringt das Projekt identisch zum Laufen, ohne dass Mandantendaten das Repo berühren.

---

### Phase X — Backlog (zurückgestellt)
Sinnvoll, aber nicht auf dem kritischen Pfad.

- [ ] **CSI-Rulesets CNF-zerlegen** (`clauses` in `sod_rules.json` für `csi`/`csi_bi`), damit die SoD-Auswertung auch über die CSI-Kataloge läuft. *(KPMG ist scharf; die Mechanik ist generisch.)*
- [ ] **Kritische TCodes/Objekte taggen** (`:Critical`) — **Ansatz offen**: Kritikalität steckt bereits im Ruleset; ob ein zusätzliches, ruleset-unabhängiges Tagging nötig ist, ist vor dem Bau zu entscheiden.
- [ ] **AE-08 — Pfad-Gültigkeitsschnittmenge** bei verschachtelten Sammelrollen sauber prüfen (Datumsprädikat auf jede Kante des Pfades).
- [ ] **Modell-Erweiterungen bei Bedarf:** `AuthField`/`ObjectClass`/`OrgValue`-Pivot, `Service`/`FioriTile` (S/4) — als `V004__…`.
- [ ] **Runner-`.sh`-Varianten** (Linux/macOS) — optional; die App-Endpunkte sind die plattformunabhängige Variante.

---

## Zielarchitektur — Laufzeit

Lokal, ein Compose, Vertrauensgrenze bleibt — **keine Mandantendaten verlassen** die Umgebung:

```
 Browser (http://localhost:8000/)
   │  statische Ribbon-UI (frontend/index.html), vom Backend ausgeliefert
   ▼
 iam-backend  (FastAPI, Port 8000)            ← Runner-as-API, asynchrone Jobs
   │  Import (Ordner/ZIP) · Auswertung (+ Evidenz) · Findings/Export · Backup/Restore · Clear/Reset
   │  orchestriert die cypher-/load-/migrations-Dateien über den Neo4j-Treiber
   ▼
 iam-neo4j  (Neo4j 5 Community + APOC, Bolt 7687 / Browser 7474)
   ├─ Rohschicht je `dataset` (User/Role/Profile/Authorization/…)
   ├─ konstante Ruleset-Schicht (Query/SoDRule/AuthReq/Clause)
   └─ regenerierbare Findings (:SoDConflict) + Evidenz (VIA_ROLE/VIA_PROFILE) + (:Run)-Provenienz

 iam-neodash (PoC-Anzeige, Port 5005 — temporär, wird durch Cytoscape.js-Frontend ersetzt)   ·   iam-migrations (Schema, profile: tools)
```

## Zielarchitektur — Repo-Struktur

```
iam/
├─ ROADMAP.md / ROADMAP-ARCHIV.md / README.md
├─ docker-compose.yml          # neo4j + neodash + backend (+ migrations als tools-Profil), gepinnt
├─ .gitignore                  # /data, /backups, .env, *.dump
├─ .gitattributes              # Zeilenenden (LF für .cypher/.sh) für Linux-Container
├─ backend/                    # FastAPI-App (app.py), SE16-Konverter (convert.py), Dockerfile, requirements
├─ frontend/                   # statische Ribbon-UI (index.html), vom Backend ausgeliefert
├─ config/                     # analysis_profiles.json (Profile), required_tables.json (Minimalset)
├─ migrations/                 # neo4j-migrations: Constraints, Indizes (idempotent)
├─ load/                       # LOAD-CSV-Skripte + Convert-Se16Export.ps1 (Host-Variante)
├─ rules/                      # normalisierte Rulesets (KPMG_R3/CSI/CSI_BI) + _archive/ (Quellen/Konverter)
├─ cypher/
│   ├─ checks/                 # Einzelberechtigungs-Checks (SAP_ALL, query_match, …)
│   ├─ sod/                    # SoD-Materialisierung + Auswertung + Evidenz (explain_sod)
│   ├─ ruleset/               # Ruleset-Loader (JSON → Graph)
│   └─ admin/                  # clear_dataset / reset_data (gebatcht)
├─ dashboards/                 # NeoDash-Export (JSON, PoC — temporär)
├─ run/                        # run_import.ps1 / run_evaluate.ps1 (Host-Runner, weiter nutzbar)
├─ docs/                       # Sphinx/MyST (Read the Docs): Benutzerhandbuch + Technische Doku
├─ data/                       # GITIGNORED: SAP-CSV + Import + DB-Volume
└─ backups/                    # GITIGNORED: Dataset-Backups (.zip der bereinigten .csv)
```

> **Host-Runner.** `run/*.ps1` (PowerShell) bleiben als Host-Variante nutzbar; die **App-Endpunkte** im `backend/` sind die plattformunabhängige, container-interne Entsprechung.

---

## Windows-Spezifika (Zielplattform)

Container-only über Docker Desktop mit WSL2-Backend — keine lokale Neo4j-/Java-Installation.

- **cypher-shell** über den laufenden Container (nicht lokal installiert).
- **LOAD CSV:** Dateien nach `./data/import`, in Cypher als `file:///dateiname.csv` (keine Windows-Absolutpfade — der Linux-Container versteht sie nicht).
- **Zeilenenden:** `.gitattributes` erzwingt LF für `.cypher`/`.sh`; `.ps1` bleibt CRLF.
- **Pfade in `docker-compose.yml`:** relative Pfade mit Vorwärts-Slashes.
- **Secrets:** `$env:NEO4J_PASSWORD` aus der lokalen `.env` (gitignored).
- **Container-Namen** fest vergeben (`iam-neo4j` …) für stabile `docker exec`-Aufrufe.

---

## R/3 versus S/4HANA

Die Speicherstruktur der Berechtigungen ist identisch (`AGR_1251`, `USR02`, `UST04`, `USOB*`) — ein Importschema für beide. Unterschiede im Zugriffsweg:
- **Fiori/OData** statt Dialogtransaktion: zusätzliche Ebene `Fiori-Tile → Target Mapping → OData-Service → Backend-Objekt` (`S_SERVICE`, `/UI2/*`).
- Neue Objekte/Transaktionen (z. B. `BP` statt `XD01`/`XK01`) → ändert Werte im Regelkatalog, nicht die Tabellenstruktur.
- **SACF/SLDW** (schaltbare Prüfungen) bei S/4-Vollständigkeit beachten.

---

## Offene Punkte / Annahmen

- Verfügbarkeit/Format der SAP-Extrakte (SE16/Reports) je Mandant.
- Umfang Org-Ebenen-Pivot (ob `OrgValue`-Knoten benötigt werden).
- S/4-Scope: ob die Fiori/OData-Ebene Teil des aktuellen Auftrags ist.
- Datenschutz-/Mitbestimmungsabstimmung für die Did-Do-Auswertung beim Mandanten.

---

## Glossar (Kurz)

- **Can-Do / Did-Do:** Was eine Berechtigung erlaubt vs. was tatsächlich ausgeführt wurde (STAD/ST03N).
- **SoD:** Segregation of Duties — unzulässige Funktionstrennung.
- **Intra-/Inter-Rollen-Konflikt:** Konflikt innerhalb einer Rolle vs. erst durch Rollenkombination.
- **Snapshot-Schicht:** Abgeleitete, regenerierbare Ergebnisse mit Provenienz (Stichtag, Run).
- **Evidenz:** Belegt pro Finding die verursachenden Rollen/Profile (`VIA_ROLE`/`VIA_PROFILE`) und intra/inter.
