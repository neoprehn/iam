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

#### Import-Evidenz (Vollständigkeitsnachweis gegen Quell-SAP)
Erledigt (Details im [Archiv](ROADMAP-ARCHIV.md#geführte-auswertung)): **Import-Robustheit** —
Abbrechen laufender Importe, Resume über Checkpoint nach Abbruch/Fehler, fehlende optionale
Quelltabelle bricht nicht mehr ab, parallele CSV-Konvertierung, Quelldateien nach Backup löschbar.

- [ ] **Persistente, abrufbare Import-Statistik je Lauf.** Heute nur flüchtig (Job-Counts) bzw. Konsole (`99_validate`).
  - **Persistenz:** `(:Import {dataset, importedAt, lang})` + je Tabelle `(:ImportTable {table, sourceRows, droppedColumns})` (der Konverter liefert Zeilen/verworfene Spalten bereits) + resultierende Graph-Zähler je Label/Kante.
  - **Abgleich/Checks:** je Quelltabelle **Quellzeilen ↔ Graph-Ergebnis** mit dokumentierter Beziehung — **1:1** (USR02→User, AGR_DEFINE→Role …, Abweichung = Flag) vs. **aggregiert** (AGR_1251→gruppierte `Authorization` nach AE-03; UST12-Feldwerte) → beide Zahlen zeigen, nicht als Fehler werten. Gefilterte Zeilen (`DELETED='X'`) ausweisen.
  - **API/UI:** `GET /datasets/{d}/import-evidence`; UI mit **KPI-Kacheln** (Knoten/Kanten, Tabellen, verworfene Sensibel-Spalten) **+ Reconciliation-Tabelle** (Tabelle · Quellzeilen · Graph · Status), hübsch.
  - **Export:** **Import-Evidenz-Report** (CSV, später PDF).

#### Geführte Auswertung (Auswerten v2) — gezielte Filter-/Scope-Auswahl
Statt „ein Lauf über alle 600+ Filter": gezielt **auswählen, was** ausgewertet wird, **für wen**, **wie
tief**. Vieles existiert als Backend-Parameter (`sodRules`, `userTypes`, `excludeLocked`, `sleepDays`,
`minCriticalityRank`) — es fehlt v. a. die **geführte Auswahl-UI** und etwas Backend.

Erledigt (Details im [Archiv](ROADMAP-ARCHIV.md#geführte-auswertung)): Org-Filter im App-Lauf
wirksam, MATCHES nach `runId` gescoped (Vorbedingung für Multi-Varianten-Läufe), Lauf
verwalten + Backup/Restore, **Assistent-Stepper** (7 Schritte Import→Bestand→Scoping→Konsistenz→
SoD→Root-Cause→Bericht, bindet für Konsistenz/SoD/Root-Cause die bestehenden Seiten ein),
**Katalog-Auswahl** (voller Katalog-Browser in Schritt ③ Scoping: Queries + SoD-Regeln,
filterbar nach Kritikalität/Namensmuster/Modul/queryType, Mehrfachauswahl) + **zwei
Auswertungsarten** (Can-Do — nur Einzelfilter materialisiert, SoD-Auswertung übersprungen — vs.
scoped SoD-Konflikte — nur die Klausel-Queries der gewählten Regeln materialisiert) +
**persistente Scope-Profile** (neue Admin-Seite „Scope", `frontend/admin-scopes.html`: dieselbe
Katalog-Auswahl wie im Assistenten, aber benannt gespeichert je Ruleset unter
`rules/<Ruleset>/scope_profiles.custom.json` — git-getrackt wie die Query-/SoD-Overlays, da
keine Mandantendaten enthalten — und im „Neuer Lauf"-Dialog auswählbar, unabhängig vom
Assistenten und über Datasets hinweg wiederverwendbar) + **verfeinerter Katalog-Browser**
(Namensmuster filtert nur die Bezeichnung, ~20 Tabellenzeilen ohne Scrollen, zweistufiger Ablauf
Einzelfilter→SoD-Regeln mit „nur mögliche SoD-Regeln"-Umschalter über die CNF-Klausel-Struktur,
inkl. automatischer additiver Ergänzung fehlender Klausel-Queries beim Finalisieren) +
**Voreinstellung inkl. Benutzergruppe/Sleeping** (Scope-Profile und Assistent-Ad-hoc-Auswahl
legen jetzt auch Nutzertyp-Profil + Sleeping fest — bei aktiver Voreinstellung verschwinden die
entsprechenden Felder im „Neuer Lauf"-Dialog zugunsten der Voreinstellungswerte).

- [ ] **„Can-Do nach Org"** (Rest von „Zwei Auswertungsarten", noch offen): „wer kann *Funktion* in
  *Buchungskreis X* (AND/OR/Bereich)" — Einzelfilter + `orgFilters` auf BUKRS/WERKS/EKORG/…
  (Matching-Seite ✓, Org-Varianten ✓; braucht nur noch die kombinierte Einzelfilter-nach-Org-Ansicht).
- [x] **Multi-Varianten-Läufe — erledigt.** Jede Variante (z. B. „Standard", „Übergreifend", „BUKRS=…") = ein eigener, **benannter** `(:Run)` (Titel-Feld, Lauf-Liste zeigt Titel als Hauptlabel + Run-ID als Mini-Chip). **Org-Varianten sind jetzt frei konfigurierbar:** neue Admin-Seite **„Org-Varianten"** (`frontend/admin-org-profiles.html`, verlinkt aus Ribbon „Admin") — wählt aus den tatsächlich im Dataset vorkommenden Org-Feldern (`GET /admin/org-profiles/org-fields`) und Werten (`GET /admin/org-profiles/org-field-values`, **echte Werte aus den Authorization-Daten**, kein Freitext) ein oder mehrere Kriterien (UND/ODER/Bereich) und speichert sie unter einem Namen. Overlay-Mechanismus wie bei Query-/SoD-Metadaten (`config/analysis_profiles.custom.json`, Vendor-Datei `analysis_profiles.json` bleibt unberührt) — **aber bewusst `.gitignore`d** (anders als `queries.custom.json`), da Org-Varianten echte Mandanten-Org-Codes enthalten können. **„Standard"/„Übergreifend" sind geschützt** (nicht editierbar/löschbar, `PROTECTED_ORG_PROFILES`). **Paralleles Anlegen mehrerer Varianten in einem Schritt:** „Neuer Lauf"-Dialog hat jetzt eine **Mehrfachauswahl** (Checkbox-Dropdown, gleiches `ddcheck`-Pattern wie der Nutzertyp-Filter) statt eines Single-Select; bei mehreren gewählten Varianten entsteht über den neuen Endpoint `POST /runs/batch` **ein Job mit je einem eigenen Lauf pro Variante** (Titel = Variantenname, sequenziell abgearbeitet — gemeinsame Neo4j-Session, kein Parallel-Schreiben). Backend-Refactor: `do_run()`-Kern in `_run_one()` ausgelagert, von Einzel- (`do_run`) und Batch-Lauf (`do_run_batch`) gemeinsam genutzt. Verifiziert gegen den laufenden Container: Variante mit echten Org-Werten angelegt/bearbeitet/gelöscht (Vendor-Datei unverändert, geschützte Profile lehnen Edit/Delete mit 400 ab), Batch-Lauf mit drei Varianten erzeugt drei `(:Run)` mit unterschiedlichen Trefferzahlen und kurzen Titeln. **Nicht Teil dieses Schritts:** sichtbare Gruppierung mehrerer Läufe als „Varianten-Set" in der UI (jeder Batch-Lauf erscheint einzeln in der Lauf-Liste).
  **Nachträglicher Korrekturbedarf (Nutzer-Feedback nach erster Nutzung):** `materialize_matches.cypher`
  ließ unter `wildcardOnly`/`filtered` **alle** Queries laufen, nicht nur die org-relevanten — die
  `$orgMode`-Logik griff nur je Berechtigungsfeld, das *zufällig* ein Org-Feld ist; Queries ganz
  ohne Org-Feld-Bezug liefen am Modus vorbei unverändert wie unter „Standard" durch (Ergebnis:
  „Übergreifend" zeigte praktisch dieselben Treffer/Regeln wie „Standard"). Korrigiert: die
  Driving-Query von `apoc.periodic.iterate` wählt jetzt **vorab nur Queries mit Bezug zu einem
  relevanten Org-Feld** (`wildcardOnly` → irgendein Org-Feld; `filtered` → eines der in
  `$orgFilters` gewählten Felder, z. B. nur Queries mit BUKRS bei einer BUKRS-Variante) — wirkt
  automatisch auch auf SoD-Regeln durch (eine Klausel ohne org-relevante Kandidaten-Query bekommt
  keine `MATCHES`-Kante mehr, die Regel kann unter der Variante nicht mehr verletzt werden, ganz
  ohne separate SoD-Filterlogik). Verifiziert: „Übergreifend" sank von 22 auf 16 betroffene Regeln
  (38 → 22 betrachtete Queries), eine BUKRS-spezifische Testvariante auf 4 Regeln (10 Queries).
- [~] **Nutzer-Scope verfeinern:** Nutzertyp und Sleeping sind bereits zusätzlich **Ergebnisfilter** (nicht nur Lauf-Kriterium, Details im Archiv). Offen: **Sleeping-Schnellwahl 90/180/360 Tage** als eigenes Eingabefeld (Sleeping ist bisher nur das beim Lauf gesetzte `sleepDays`-Fenster, nicht frei wählbar pro Filter); **Gesperrte nach Sperrtyp** auswählbar (failed_logons / admin_local / admin_global — Daten liegen als `lockReasons` vor) statt nur `excludeLocked`-Bool. *(Sperrtyp-Filter neu.)*
- [ ] **Evidenz-Perf:** vorab geflachte Erreichbarkeit `(:Role|:Profile)-[:GRANTS]->(:Authorization)` (transitive Hülle CONTAINS/HAS_PROFILE), damit `explain_sod` (intra/inter + VIA_ROLE) ein Lookup statt variabler Pfadsuche wird → **Evidenz default-on** möglich. *(Optimierung der v1.)*

#### Interaktive Ergebnisse (Drill-down) + Graph/Tabelle
Heute sind die Ergebnis-Listen statisch. Interaktiv machen — größtenteils mit vorhandenen Daten:

Erledigt (Details im [Archiv](ROADMAP-ARCHIV.md#interaktive-ergebnisse-drill-down--graphtabelle)):
klickbare Drill-downs (Findings-Filter, KPI-Kontext-Chips, Ergebnistyp-Pills), Root-Cause-Drill-down
(Einzelfilter **und** SoD-Regeln), kaskadierende Sidebar-Filter, SoD-Kurzbezeichnung,
**Root-Cause-Graph (Pfad + Radial, Cytoscape)** als Ansicht-Umschalter neben der Tabelle.

- [~] **Umschalter Tabelle/Graph — echter Graph für SoD-Konfliktpfade.** **Auf Root-Cause-Ebene
  erledigt:** die Root-Cause-Seite hat jetzt einen Ansicht-Umschalter **Tabelle · Pfadgraph ·
  Radial** (Cytoscape.js, aus denselben `/root-cause`-Daten — voller Pfad User → Regel → Klausel →
  Query → Objekt → Rolle/Profil inkl. technisch/verwaist/„via generiertem Profil"; Details im
  Archiv). **Noch offen:** der **listenweite** Tabelle/Graph-Umschalter über der Findings-Liste
  (`viewTogglePills`, „Graph" dort noch deaktiviert) — ein Graph **aller** Findings eines Laufs auf
  einmal (Heatmap/Matrix-artig, viele User × Regeln) statt des fokussierten Einzel-Pfads; sowie die
  perf-optimierte Variante über die vorab geflachten Evidenz-Kanten (`VIA_ROLE`/`VIA_PROFILE`, s.
  „Evidenz-Perf") statt der Root-Cause-Live-Abfrage.
- [~] **Design-Regel: sortierbare Spalten in Ergebnistabellen.** Klick auf eine Kopfzelle sortiert,
  erneuter Klick kehrt die Richtung um (Pfeil-Indikator) — generische `makeSortable()`-Hilfsfunktion
  im Frontend statt Einzellösung je Tabelle. **Umgesetzt:** Ergebnisse-Übersicht (Einzelfilter
  **und** SoD-Regeln, dieselbe `summaryTable`-Komponente), Nutzerliste (`ulTable`), Konsistenzcheck-
  Detail (`ccdDetailTable`, dort schon vorher vorhanden — eigene Implementierung wegen dynamischer
  Spalten aus den Zeilen-Keys, nicht auf `makeSortable()` umgestellt). **Gilt als Standard für jede
  neue tabellarische Ergebnisliste.** Noch offen: Findings-/Matches-Haupttabelle (`findingsTable`/
  `matchesTable`) und der Konsistenzcheck-Katalog (`ccGrid`) sind bisher nicht sortierbar.

#### Anzeige, Vergleich, Export, Admin
- [ ] **„Fancy" Aufbereitung — gebrandetes Frontend mit Cytoscape.js.** **Ersetzt den temporären NeoDash-PoC** (Phase 6, Archiv). KPIs, **Graph-Darstellung der Konfliktpfade** (Cytoscape.js statt Neo4j Visualization Library — NVL verworfen, Lizenz nur für Aura/kommerzielle Subscription, s. Phase 7 Graph-Pilot) — visualisiert genau die Evidenz-Kanten (`VIA_ROLE`/`VIA_PROFILE`), Heatmap/Matrix, Drill-down. Die NeoDash-Karten-Cypher (`dashboards/sod_poc.json`) sind die Vorlage.
  - [ ] **NeoDash danach vollständig entfernen** (sobald das Cytoscape.js-Frontend steht): Compose-Service `iam-neodash` (Port 5005) raus; Erwähnungen in `README.md`/`docs/` und im Laufzeit-Diagramm streichen; `dashboards/sod_poc.json` nach Portierung archivieren oder löschen; Pin in `AE-14` entsprechend reduzieren.
- [ ] **System/Mandant-Vergleich:** „neuer Stand/Mandant" **oder** „Vergleich zu bestehendem" → **Vergleichs-Abfragen** über zwei `dataset` (neue/entfallene Konflikte, Delta je Regel/User).
- [~] **Export native `.xlsx`.** CSV-Export der Findings ist erledigt (Archiv). Offen: natives Excel (z. B. `openpyxl`) und weitere Sichten (Top-Regeln, Matrix). Schließt den **Import-Evidenz-Report** und den Ergebnis-Export zusammen.
- [~] **Admin-Bereich — Funktionen.** Heimat, Einzelfilter-Editor + Query-/SoD-Management-Seite
  (Overlay-Mechanismus, Kurzbezeichnungen, Risiko/Controls-Tabs, Fehlerprotokoll) sind erledigt
  — Details im [Archiv](ROADMAP-ARCHIV.md#admin-bereich). Offen/zurückgestellt:
  - [ ] **Authorizations/TCodes im Editor bearbeitbar machen** (v2) — bisher nur 1:1-Kopie beim Ableiten/Anzeige im Aufbau-Tab, keine UI für die verschachtelten Objekt/Feld/Werte-Listen.
  - [ ] **Strukturierter Threat-/Attack-Baum am Risiko-Feld** (v2, „nicht vergessen"): Heute ist `risk` (Query **und** SoD-Regel) ein **einzelnes Freitextfeld** im Overlay (`queries.custom.json`/`sod_rules.custom.json`, coalesce-Merge in `load_ruleset.cypher`) — ein Threat-Baum müsste dort als serialisierter Text abgelegt werden und ist weder traversierbar noch wiederverwendbar. Idee: den Risiko-Teil zu einem **strukturierten Threat-Baum** ausbauen (AND/OR-Verzweigungen, Knoten = Bedrohungsschritt/Voraussetzung, optional Wahrscheinlichkeit/Impact/Gegenmaßnahme je Knoten) — eigenes JSON-Schema statt Freitext, im selben Overlay-Mechanismus gespeichert (bleibt Vendor-Datei-schonend + git-tracked). **Doppelnutzen:** (a) die SoD-Verletzungslogik ist selbst schon ein AND/OR-Baum (Regel = AND über Klauseln, Klausel = OR über Queries, Query = AND über Objekte, Objekt = OR über erfüllende Rollen/Profile) — ein Threat-Baum-Renderer und die neue Root-Cause-Graph-/Baum-Darstellung (s. „Interaktive Ergebnisse") könnten **dieselbe Baum-Komponente** teilen; (b) perspektivisch verlinkbar/wiederverwendbar über mehrere Queries/Regeln. Vor dem Bau: Schema festlegen (an ein etabliertes Format anlehnen, z. B. Fault-/Attack-Tree), Editor-UX skizzieren.
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
