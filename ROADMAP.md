# Roadmap — SAP-Berechtigungsanalyse mit Neo4j

**Projekt:** Graphbasierte Auswertung von SAP-Berechtigungen (R/3 und S/4HANA) — Can-Do (Berechtigung) und Did-Do (Nutzung), inklusive SoD-Konfliktanalyse.
**Repository:** `neoprehn/iam`.
**Zielplattform:** Windows (Container-only über Docker Desktop / WSL2 — siehe „Windows-Spezifika").

**Stand:** Die App ist unter `http://localhost:8000/` lauffähig: **Import (Ordner/ZIP, mit
Abbrechen/Resume), geführte Auswertung (Assistent-Stepper), Auswertung (inkl. Fortschritt/Resume je
Query/Regel/Akteur, Evidenz, Org-Varianten, interaktive Drill-downs), Konsistenzchecks +
Konsistenz-Report (CSV/PDF), Query-/SoD-Management, Ergebnisse + CSV-Export, Backup/Restore,
Bereinigen** — alles ohne JSON-Pflege. Abgeschlossene Arbeit (Phasen 0–3, 5; Phase 6 PoC; Phase 7
vollständig; Phase-9-Bausteine Backend-API/Import/Ribbon-UI/Backup-Restore-Clear/CSV-Export/
Org-Filter+MATCHES-Scoping/Drill-downs/Admin-Management-Seiten/Assistent-Stepper/Import-Robustheit/
Lauf-Fortschritt+Resume; AE-11-Evidenz v1) ist im Detail in
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

### Phase 9 — App: offene Bausteine

Die App-Grundfunktionen stehen (siehe Archiv). Offen sind die folgenden Ausbauten.

#### Import-Evidenz (Vollständigkeitsnachweis gegen Quell-SAP) — erledigt (2026-07-12)
Erledigt (Details im [Archiv](ROADMAP-ARCHIV.md#geführte-auswertung)): **Import-Robustheit** —
Abbrechen laufender Importe, Resume über Checkpoint nach Abbruch/Fehler, fehlende optionale
Quelltabelle bricht nicht mehr ab, parallele CSV-Konvertierung, Quelldateien nach Backup löschbar.

- [x] **Persistente, abrufbare Import-Statistik je Lauf.** War bisher nur flüchtig (Job-Counts)
  bzw. verworfen (`99_validate.cypher` lief nur via `.consume()`, s. `run_cypher_path()`).
  - **Persistenz:** `(:Dataset)-[:HAS_IMPORT]->(:Import {dataset, importedAt, lang})` (ein Knoten
    je Import-Vorgang, keine Überschreibung → Historie über Re-Importe) mit
    `-[:HAS_TABLE]->(:ImportTable {table, sourceRows, droppedColumns, filteredRows})` je
    Quelltabelle (Konverter liefert Zeilen/verworfene Sensibel-Spalten bereits, `filteredRows`
    zusätzlich per eigenem `DELETED='X'`-Zähler für AGR_1251) + `-[:HAS_NODE_COUNT]->`/
    `-[:HAS_EDGE_COUNT]->` Graph-Zähler je Label-Kombination/Kantentyp (`99_validate.cypher`,
    jetzt über `run_cypher_path_capturing()` statt verworfen). `backend/app.py
    _persist_import_evidence()`, aufgerufen am Ende von `do_import()`. Migration
    `V004__import_evidence.cypher` (Unique-Constraints).
  - **Abgleich/Checks:** `cypher/checks/import_evidence.cypher` — 22 SAP-Quelltabellen als
    literal eingebettete Zuordnung (node_1to1/edge_1to1 echte 1:1-Erwartung, edge_filtered
    bewusst gefilterte Zeilen wie EXCLUDE='X', shared_edge_type mehrere Quelltabellen auf
    denselben Kantentyp — z. B. CONTAINS für Rolle- **und** Profil-Hierarchie, aggregated
    Bündelung nach AE-03/Dedupe, property reine Anreicherung ohne eigenen Zähler). **Wichtiger
    Fund beim Testen:** Knoten tragen zusätzliche Subtyp-Labels (`User`+`Dialog`/`Active`/…,
    `Role`+`Composite`/`Single`) — `99_validate.cypher` gruppiert nach der **exakten**
    Label-Kombination, ein naiver Abgleich gegen `[Zielabel]` fand daher nie etwas; Fix: über
    alle Kombinationen summieren, die das Ziel-Label enthalten (`CALL`-Subquery je
    Rekonziliierungszeile).
  - **Als eigene Konsistenzcheck-Kategorie „Import" (I) aufgenommen** (Nutzer-Wunsch, weicht vom
    ursprünglichen Plan ab, das unter der bestehenden Kategorie E als E6 zu führen — E6 verweist
    jetzt auf I1): `CHECK_AREAS`/`area_names` um `"import": ["I"]` erweitert, `checks/I1.json`
    (`group` für die Box-Überschrift), dritter Ribbon-Punkt „Import" neben „User-spezifisch"/
    „Rollen-spezifisch" — die komplette Rendering-Pipeline (Grid/Pillfilter/Detailansicht) war
    bereits generisch über `CHECK_AREAS` gebaut, bis auf eine hart auf `.role` verdrahtete Stelle
    in `ccGroupOrder()` (jetzt `consistencyCatalog[ccArea]`). Damit läuft I1 automatisch im
    allgemeinen Konsistenz-Report (CSV/PDF, fpdf2) mit.
  - **Dedizierter Import-Evidenz-Report** (`GET /datasets/{d}/import-evidence` JSON,
    `.../export` CSV, `.../export/pdf` PDF) — der allgemeine Konsistenz-Report zeigt I1 nur als
    einen Katalogeintrag mit Trefferzahl, für die Prüfungsnachweisführung („alle wichtigen
    Informationen") braucht es die **volle** Tabelle-für-Tabelle-Rekonziliierung mit
    Deckblatt-Metafeldern (Unternehmen/System/Anlass/Ersteller/Stichtag/Import-Zeitpunkt) —
    `_build_import_evidence_pdf()` als Schwester-Funktion zu `_build_consistency_pdf()`, gleiche
    fpdf2-Bibliothek/Optik. Downloadbar direkt vom I1-Check-Detail (eigener Report-Block, PDF/CSV,
    Dataset aus dem Ausführen-Formular). Truncation über `pdf.get_string_width()` statt
    Zeichen-Schätzung (sonst harte, wortmittige Abschnitte bei sehr langen Hinweistexten).
  - Verifiziert gegen den laufenden Container: I1 im Leerzustand (Dataset noch nicht mit
    Import-Evidenz importiert) liefert informativen Hinweis statt Fehler; mit simulierten
    realistischen Zähldaten (echte Node-/Edge-Counts + eine bewusst falsche Zeile) liefert die
    Rekonziliierung korrekt OK/Hinweis/Abweichung; allgemeiner CSV/PDF-Report läuft mit
    Kategorie „Import" durch ohne Fehler; PDF-Layout Zelle für Zelle geprüft (keine
    abgeschnittenen Texte mehr nach dem Truncation-Fix); Playwright-UI-Test (Ribbon-Button,
    Single-Box-Grid, Detailansicht, Export-Links). Testdaten danach entfernt.

Die folgenden offenen Ausbauten wurden am **2026-07-12** mit den handschriftlichen Notizen aus
`ideen.md` zusammengeführt und in thematische Arbeitspakete **9.1–9.8** gegliedert.
**Reihenfolge (Nutzer-Steuerung):** zunächst **9.1 + 9.2** (Interaktive Ergebnisse / Graph-Frontend),
danach **9.3 ff.** in gelisteter Folge; die geplanten Phasen 10/8/X schließen sich an.

#### Kürzlich erledigt (Kontext, Details im Archiv)
- **Geführte Auswertung** — Assistent-Stepper, Katalog-Auswahl, zwei Auswertungsarten, persistente
  Scope-Profile, verfeinerter Katalog-Browser, Voreinstellung inkl. Benutzergruppe/Sleeping,
  scope-treue Sidebar-Filter, **Multi-Varianten-Läufe** (jede Variante ein eigener benannter `(:Run)`;
  **Titel/Beschreibung nachträglich editierbar** — `PATCH` auf den Run-Knoten), **Nutzer-Scope
  verfeinern** (Sleeping-Schnellwahl, Sperrtyp-Filter), **Evidenz default-on** (Evidenz-Perf:
  `/explain` ~90–100s → ~27,6s). [Archiv](ROADMAP-ARCHIV.md#geführte-auswertung).
- **Interaktive Drill-downs** — Findings-/Regel-/KPI-Klick, Root-Cause inkl. Pfad-/Radialgraph
  (Cytoscape). [Archiv](ROADMAP-ARCHIV.md#interaktive-ergebnisse-drill-down--graphtabelle).
- **Import-Evidenz** — s. Block oben (Kategorie „Import"/I1, PDF/CSV-Report).

#### 9.1 Interaktive Ergebnisse & Graph-UX  ← als Nächstes
- [~] **Sortierbare Spalten** in allen Ergebnistabellen (generische `makeSortable()`): umgesetzt für
  Ergebnis-Übersicht (Einzelfilter+SoD), Nutzerliste, Konsistenzcheck-Detail **und jetzt die
  Findings-/Matches-Haupttabelle** (`findingsTable`/`matchesTable`, je erste 5 Spalten;
  Sleeping/Root-Cause-Button bewusst nicht sortierbar; Kritikalität über `critRank`). **Offen nur
  noch:** Konsistenzcheck-Katalog (`ccGrid`) — gruppierte Mini-Tabellen je Kategorie, separater,
  kleinerer Umbau. Gilt als **Standard** für jede neue Ergebnisliste.
- [~] **Listenweiter Tabelle/Graph-Umschalter** über der Findings-Liste (`viewTogglePills`, „Graph"
  noch deaktiviert): ein Graph **aller** Findings eines Laufs (Heatmap/Matrix, User × Regeln) statt des
  fokussierten Einzelpfads — perf-optimiert über die geflachten Evidenz-Kanten
  (`VIA_ROLE`/`VIA_PROFILE`) statt Root-Cause-Live-Abfrage. (Root-Cause-Ebene erledigt: Umschalter
  Tabelle · Pfadgraph · Radial.)
- [ ] **Farblegende in allen Graphansichten** — erklärt die Knotenbedeutung (User/Regel/Klausel/Query/
  Objekt/Rolle/Profil, technisch/verwaist). Gilt für Pfad-, Radial- und den listenweiten Graphen.
- [ ] **Vollbild-Bedienung der Graphen überarbeiten** — heutiger Vollbild-Knopf ist ungünstig; besseres
  Muster (Toggle in der Ansichts-Leiste, ESC zum Verlassen).
- [x] **Zurück-Button im Drill-down** — „← zurück" in der Aktiv-Filter-Leiste stellt die Ausgangsliste
  wieder her (Filter-Historie als Stack, Schnappschuss vor jedem Sprung; erkennt auch die
  Übersichts-Sicht als Ursprung). Erledigt 2026-07-12.
- [ ] **Kritikalität prominent an Einzelfilter/SoD** — dieselbe farbige Badge-Logik wie bei den Findings
  (Farbwahl beibehalten) auch in Katalog/Auswahl/Ergebniszeilen der Einzelfilter und SoD-Regeln; Stufen/
  Farben aus den Kritikalitäts-Stammdaten (→ 9.4).

#### 9.2 „Fancy" Cytoscape.js-Frontend + NeoDash-Ablösung
- [ ] **Gebrandetes Frontend mit Cytoscape.js** — ersetzt den temporären NeoDash-PoC (Phase 6). KPIs,
  Graph-Darstellung der Konfliktpfade (Cytoscape statt NVL — NVL verworfen, Lizenz nur Aura/kommerziell),
  Heatmap/Matrix, Drill-down; visualisiert die Evidenz-Kanten (`VIA_ROLE`/`VIA_PROFILE`). Vorlage:
  `dashboards/sod_poc.json`. Die Graph-UX-Punkte aus 9.1 (Legende, Vollbild) sind Teil davon.
- [ ] **NeoDash danach vollständig entfernen** — Compose-Service `iam-neodash` (Port 5005), Erwähnungen
  in `README.md`/`docs/`/Laufzeitdiagramm, `dashboards/sod_poc.json` archivieren/löschen, `AE-14`-Pin
  reduzieren.

#### 9.3 Org-Varianten & „Can-Do nach Org" — Ausbau, UX, Performance
- [ ] **„Can-Do nach Org"** (Rest von „Zwei Auswertungsarten"): „wer kann *Funktion* in *Buchungskreis
  X*" — Einzelfilter + `orgFilters` auf BUKRS/WERKS/EKORG/…. **Entschieden (2026-07-11):** über den
  bestehenden Org-Varianten-Mechanismus (eigener `(:Run)` je Kombination), **kein** Live-Post-hoc-Filter
  (die `MATCHES`-Kante ist rein boolesch; Nachfiltern müsste die `$orgMode`/`$orgFilters`-Logik aus
  `materialize_matches_one.cypher` als Live-Query nachbauen — kein echter Vorteil). Fehlt nur die
  kombinierte Einzelfilter-nach-Org-Ansicht.
- [ ] **Verschachtelte Org-Abfragen** — heute je Org-Feld genau **ein** Operator (`AND`/`OR`/`RANGE`)
  über eine flache Werteliste (`materialize_matches_one.cypher`, `$orgFilters[feld].op/.values`).
  Gewünscht: boolesche Verschachtelung wie **„(1000 & 2000) OR 3000"** je Feld. Braucht (a) einen
  Ausdrucks-/Baum-Editor in der Varianten-UI und (b) eine rekursive Auswertung im Cypher statt des
  flachen `op`.
- [ ] **Feldübergreifende Semantik in der UI ausweisen** — *mehrere* Org-Felder (z. B. BUKRS **und**
  Verkaufsorg) werden mit **UND** verknüpft (bestätigt: `all(obj IN objects …)` in
  `materialize_matches_one.cypher`; die Wahl AND/OR/RANGE gilt nur **innerhalb** eines Feldes).
  Hinweistext/Badge „alle Felder = UND" ergänzen.
- [ ] **Beschreibungsfeld 2-zeilig + Vergrößern** — analog zum Risikotext-Feld (Textarea + Expand-Icon).
- [ ] **Responsive Kriterien-Layout bei der Varianten-Erstellung** — eine Spalte bei einem Kriterium;
  ab dem Hinzufügen: 2 nebeneinander, das 3. über volle Breite darunter, 4 als 2×2.
- [ ] **Importformat für neue Varianten** — Org-Kombinationen als Datei ein-/auslesbar statt nur per
  UI-Eingabe.
- [ ] **Performance des Varianten-Aufbaus untersuchen** — Ursache: jede Variante ist ein **eigener, voll
  materialisierter Lauf** (MATCHES über alle User × Queries je Variante). Ansätze: gemeinsame
  Kandidaten-Vorfilterung über Varianten hinweg, Wiederverwendung der org-unabhängigen MATCHES-Basis,
  Parallelität/Checkpoint-Throttling (analog Evidenz-Perf).
- **Erledigt:** Variantenname/-beschreibung nachträglich editierbar — sowohl je Lauf (`PATCH` auf den
  `(:Run)`-Knoten) als auch im **Org-Varianten-Editor** (Umbenennen eigener Profile via
  `PUT /admin/org-profiles/{name}` mit `newName`; Kollisions-/Schutz-Prüfung, geschützte Basis-Varianten
  bleiben gesperrt).
#### 9.4 Masterdata-Verwaltung (Admin)
Zentrale, editierbare Stammdaten statt verstreuter Freitexte/Konstanten — Basis für Dropdowns, die
Kritikalitäts-Anzeige (9.1) und den Reason-Code (9.6).
- [ ] **Kritikalitäts-Stammdaten** — Stufen + Farben (aktuelle Farbwahl beibehalten) für Einzelfilter
  und SoD, Stufenlogik editier-/erweiterbar; zusätzlich ein **versteckter KRI-Score** je Stufe
  mitführen (später für Heatmap-Gewichtung).
- [ ] **Reason-Code-Stammdaten (SoD)** — Reason Code als Prozess führen: `PtP_C` → Code `PtP`,
  Beschreibung „Purchase to Pay". Im SoD-Filter steht die Kritikalität bereits vorn; der Reason-Code
  wird durch den Prozessnamen ersetzt/angereichert.
- [ ] **Modul-Stammdaten** — aktuelle SAP-Module aus den Filtern übernehmen, editier-/erweiterbar.
- [ ] **Querytyp-Stammdaten** — aktuelle Querytypen übernehmen, editier-/erweiterbar.
- [ ] **Dropdowns statt Freitext** — Kritikalität/Modul/Querytyp/Reason-Code im Query-/SoD-Management
  aus den Stammdaten wählbar (soweit noch nicht umgesetzt).
- [ ] **Neuen SoD-Filter anlegen** — der Overlay-Mechanismus erlaubt heute nur das *Bearbeiten*
  bestehender Regeln (`sod_rules.custom.json`); das *Neuanlegen* einer SoD-Regel (Klausel-/CNF-Struktur)
  über die UI fehlt.
- [ ] **Authorizations/TCodes im Editor bearbeitbar** (v2) — bisher nur 1:1-Kopie beim Ableiten/Anzeige
  im Aufbau-Tab, keine UI für die verschachtelten Objekt/Feld/Werte-Listen.
- [ ] **USOBT-gestützter Query-Builder** (v2) — neue Queries per Auswahl Transaktion → Berechtigungsobjekt
  statt Freitext; USOBT/USOBX als eigener, vom Dataset getrennter Graph-Layer (stabil je
  Berechtigungskonzept, bei Bedarf gegen das aktuelle Set abgleichen/neu laden).
- [ ] **Query → System-Typ-Zuordnung** (v2) — Stammdatenblatt, welche Query zu welchem Quellsystem-Typ
  gehört (R/3, S/4HANA, künftig weitere) — Vorstufe system-übergreifender/-spezifischer Rulesets, ohne
  das Datenmodell zu verzweigen.
- [ ] **Filterset-/Konnektor-Import weitere Systeme** (v2) — perspektivisch S/4HANA, Azure AD/Entra,
  Microsoft Dynamics, Salesforce (je System ein eigenes Ruleset, Datenmodell bleibt gleich).

#### 9.5 Threat Modeling (Reiter an Einzelfilter/SoD)
- [ ] **Threat-Modeling-Reiter** an Einzelfilter und SoD-Regel — grafisch zeigen, wie eine Berechtigung
  über einen Threat-Vector durch einen Threat-Actor ausgenutzt werden kann.
  **Empfehlung Methodik (2026-07-12):** primär **graphbasierter Attack Tree**, weil (a) die
  SoD-Verletzungslogik selbst schon ein AND/OR-Baum ist (Regel = AND über Klauseln, Klausel = OR über
  Queries, Query = AND über Objekte, Objekt = OR über erfüllende Rollen/Profile) → **dieselbe
  Baum-/Cytoscape-Komponente** wie Root-Cause/9.1 nutzbar; (b) traversierbar und wiederverwendbar über
  mehrere Queries/Regeln, anders als Freitext. **STRIDE** zusätzlich als *Klassifikations-Overlay* je
  Knoten (Bedrohungskategorie); **PASTA** als vollständiger 7-Stufen-Prozess ist für diesen fokussierten
  Zweck zu schwergewichtig. Vor dem Bau: Schema festlegen (an Fault-/Attack-Tree anlehnen), Editor-UX
  skizzieren, publizierte Neo4j-/GitHub-Attack-Tree-Ansätze sichten.
- **Datenablage:** heute ist `risk` (Query **und** SoD) ein einzelnes Freitextfeld im Overlay
  (coalesce-Merge in `load_ruleset.cypher`). Der Threat-Baum wird ein **eigenes JSON-Schema** (AND/OR,
  Knoten = Bedrohungsschritt/Voraussetzung, optional Wahrscheinlichkeit/Impact/Gegenmaßnahme je Knoten)
  im selben git-getrackten Overlay-Mechanismus — nicht in den Freitext gequetscht.

#### 9.6 Export, System-/Mandant-Vergleich, Interview-Ergebnisse
- [ ] **System/Mandant-Vergleich** — „neuer Stand/Mandant" **oder** „Vergleich zu bestehendem":
  Vergleichs-Abfragen über zwei `dataset` (neue/entfallene Konflikte, Delta je Regel/User).
- [ ] **Interview-Ergebnisse einarbeiten** — pro Finding/Feld einen **Reason Code** (aus den Masterdata,
  9.4) plus **Begründung** hinterlegen (z. B. „Replace/Debug bei drei Personen"). Persistiert und im
  **Folgejahres-Dataset wieder anziehbar** (Wiedervorlage/Delta beim neuen Import) — Grundlage für den
  Jahresvergleich. Autor/Datum mitführen; **keine Mandantendaten ins Repo** (Ablage in der lokalen DB,
  nicht git-getrackt).
- [~] **Nativer `.xlsx`-Export** — CSV der Findings ist erledigt. Offen: natives Excel (`openpyxl`) und
  weitere Sichten (Top-Regeln, Matrix); bündelt Import-Evidenz-Report + Ergebnis-Export.

#### 9.7 Betrieb
- [ ] **Kein eigenes Benutzer-/Berechtigungskonzept** (bewusst) — lokal/Container; Auth-Schicht
  (SSO/OIDC am Ingress) erst bei zentralem Mehrbenutzerbetrieb (siehe Phase 10).

#### 9.8 Neuer SAP-Extraktor (Can-Do + Did-Do + Konsistenzchecks)
Angepasster Extraktor, der die Quelltabellen/-spalten **genau im hier benötigten Zuschnitt** zieht —
inkl. der Spalten für alle Konsistenzchecks und (vorbereitend) Did-Do.
- [ ] **Datenanforderungen erheben** — je (1) Can-Do, (2) Did-Do, (3) Konsistenzchecks die benötigten
  Tabellen/Spalten zusammentragen.
- [ ] **RTD-Kapitel** — Datenanforderungen dokumentieren (Nachvollziehbarkeit, Dokumentations-DoD).
- [ ] **Extraktor überarbeiten/neu schreiben** — liegt unter `data/extractors` (darf gepusht werden).
- [ ] **Config konsolidieren** — `config/Download Data CSI.xls` + `config/required_tables.json`
  zusammenführen; je Tabelle die Felder (inkl. Did-Do) in die JSON aufnehmen. **Vorab:** `Download Data
  CSI.xls` inhaltlich sichten (untracked, Herkunft unklar) und sicherstellen, dass **keine
  Mandantendaten** enthalten sind, bevor etwas committet wird (Vertrauensgrenze).
- **Abhängigkeit:** die **Did-Do-Spalten** hängen an Phase 8 (blockiert — kein STAD/ST03N-Auszug); die
  **Can-Do-/Konsistenzcheck**-Anteile und die Config-Konsolidierung können **jetzt** starten.

**DoD (Phase 9):** Eine transportable App, in der Import, parametrierte Auswertung, Vergleich, Anzeige,
Export und Backup/Restore ohne JSON-Pflege bedienbar sind — lokal, ohne dass Mandantendaten die Umgebung
verlassen.

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

### Phase 8 — Did-Do (Nutzung aus STAD/ST03N) — **blockiert, hinter Phase 10 verschoben**
**Blockiert (2026-07-11):** Dem Mandanten liegt aktuell **kein STAD/ST03N-Auszug** (Nutzungsdaten)
vor — ohne dieses Dataset ist an dieser Phase nichts umsetzbar. Deshalb bewusst hinter Phase 10
zurückgestellt (statt wie zuvor nur „zuletzt, aber vor Verteilung"): sobald ein Extrakt mit
Nutzungsdaten verfügbar ist, rückt die Phase wieder nach vorne.

**Ziel:** Nutzungssicht und Can-Do×Did-Do-Matrix.

- [ ] Extraktionsweg festlegen: ST03N-Aggregate (`SWNC_COLLECTOR_GET_AGGREGATES`) als Einstieg; bei Bedarf Roh-STAD; für Forensik SAL/`CDHDR`.
- [ ] `EXECUTED`-Kanten (User→Transaction) mit `count`/`firstSeen`/`lastSeen`/`taskType`/`asOf`/`runId` in die Snapshot-Schicht.
- [ ] Matrix-Abfragen: ungenutzte Berechtigungen (Least-Privilege), materialisierte SoD (Did-Do auf beiden Konfliktseiten).
- [ ] Caveats dokumentieren: Aufbewahrungsfenster, selten-aber-vital, indirekte Aufrufe, kein Audit-Log (AE-13), S/4-Fiori/OData.
- [ ] **Datenschutz/Mitbestimmung** (§ 87 BetrVG): Pseudonymisierung der User-ID; Klartext nur im begründeten Einzelfall.

**DoD:** Matrix-Auswertung lauffähig; ungenutzte kritische Berechtigungen und materialisierte SoD-Konflikte werden ausgewiesen.

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
