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

---

## Offene Arbeit

### Phase 7 — Verteilung & Reproduzierbarkeit
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
- [ ] **Umschalter Tabelle/Graph** — **erstes echtes Graph-Einsatzszenario**: Konfliktpfad **User → Rolle/Profil → Query → Regel** (nutzt die Evidenz-Kanten `VIA_ROLE`/`VIA_PROFILE`). Einstieg ins **NVL/React**-Frontend (siehe nächster Punkt); Auswahl „als Graph oder als Tabelle anzeigen".

#### Anzeige, Vergleich, Export, Admin
- [ ] **„Fancy" Aufbereitung — gebrandetes NVL/React-Frontend.** **Ersetzt den temporären NeoDash-PoC** (Phase 6, Archiv). KPIs, **Graph-Darstellung der Konfliktpfade** (Neo4j Visualization Library / React) — visualisiert genau die Evidenz-Kanten (`VIA_ROLE`/`VIA_PROFILE`), Heatmap/Matrix, Drill-down. Die NeoDash-Karten-Cypher (`dashboards/sod_poc.json`) sind die Vorlage.
  - [ ] **NeoDash danach vollständig entfernen** (sobald NVL/React steht): Compose-Service `iam-neodash` (Port 5005) raus; Erwähnungen in `README.md`/`docs/` und im Laufzeit-Diagramm streichen; `dashboards/sod_poc.json` nach Portierung archivieren oder löschen; Pin in `AE-14` entsprechend reduzieren.
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
  - [ ] **Authorizations/TCodes im Editor bearbeitbar machen** (v2) — bisher nur 1:1-Kopie beim Ableiten/Anzeige im Aufbau-Tab, keine UI für die verschachtelten Objekt/Feld/Werte-Listen.
  - [ ] **USOBT-gestützter Query-Builder** (v2, "Profilgenerator-Logik"): neue Queries durch **kontextbasierte Auswahl von Transaktion → Berechtigungsobjekten** bauen statt freier Eingabe — USOBT/USOBX als eigener, vom Dataset getrennter Graph-Layer (ist je Berechtigungskonzept/Set stabil, aber bei Bedarf gegen das aktuelle Set **abzugleichen/neu zu laden**, wenn neue Queries gebaut werden).
  - [ ] **Stammdaten-Blatt: Query → System-Typ-Zuordnung** (v2, „für die Zukunft"): welche Query zu welchem Quellsystem-Typ gehört (SAP R/3, SAP S/4HANA, künftig weitere) — Vorstufe für system-übergreifende/-spezifische Rulesets, ohne das Datenmodell zu verzweigen.
  - [ ] **Filterset-/Konnektor-Import** für weitere Systeme — perspektivisch **SAP S/4HANA, Azure AD/Entra, Microsoft Dynamics, Salesforce** (je System ein eigenes Ruleset; Datenmodell bleibt gleich).
- [ ] **Kein eigenes Benutzer-/Berechtigungskonzept** (bewusste Entscheidung): die App läuft lokal bzw. wird als Container verteilt; Zugriff über die (lokale/Unternehmens-)Umgebung abgesichert. Eine Auth-Schicht (SSO/OIDC am Ingress) kommt erst, wenn die App **mehrbenutzerfähig zentral** betrieben wird — siehe Deployment-Notiz (Phase 7).

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

 iam-neodash (PoC-Anzeige, Port 5005 — temporär, wird durch NVL/React ersetzt)   ·   iam-migrations (Schema, profile: tools)
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
