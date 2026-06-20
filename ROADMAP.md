# Roadmap — SAP-Berechtigungsanalyse mit Neo4j

**Projekt:** Graphbasierte Auswertung von SAP-Berechtigungen (R/3 und S/4HANA) — Can-Do (Berechtigung) und Did-Do (Nutzung), inklusive SoD-Konfliktanalyse.
**Repository:** `neoprehn/iam` (aktuell einziger vorhandener Baustein).
**Zielplattform:** Windows (Container-only über Docker Desktop / WSL2 — siehe Abschnitt „Windows-Spezifika").
**Stand:** Phasen 0–3 und 5 abgeschlossen — Import (Can-Do, beide Pfade, performant), SoD-Evaluator (Zwei-Schritt, voll parametrisiert: User-Typ/Org/Sleeping/Scope), zwei Runner (`run_import`/`run_evaluate`). Phase 6 (NeoDash) als PoC abgeschlossen (Showcase-Stopp). **Phase 9 (transportable App — das Produktziel) weit umgesetzt: Bau-Schritte 1–4 stehen** — Backend-API über die Runner (FastAPI-Container `iam-backend`), voller **Import im Container** (SE16-Konverter nach Python portiert; kein PowerShell mehr nötig) **inkl. ZIP-Upload**, **Ribbon-Oberfläche nach Lebenszyklus** (Daten → Auswertung → Ergebnisse → Sichern → Verwalten). Bedienbar unter `http://localhost:8000/`: **Import (Ordner/ZIP), Auswertung, Ergebnisse + CSV-Export, Backup/Restore (Quelldaten-ZIP, inkl. Backup & Clear, Download), Bereinigen (Clear/Reset)** — alles ohne JSON-Pflege. Offen: Phase 7 (Verteilung), restliche Phase 9 (Mandanten-Vergleich, natives `.xlsx`, NVL/React-Frontend, Ruleset-Editor), Phase X (Backlog), Phase 8 (Did-Do, Kür).

---

## Verwendung mit Claude Code

Diese Datei ist als lebendes Dokument für die Weiterarbeit gedacht. Empfehlung: als `ROADMAP.md` ins Repo-Root committen. Eine Claude-Code-Sitzung kann phasenweise abarbeiten — die Checklisten (`[ ]`) als Fortschrittsanker nutzen, abgeschlossene Punkte auf `[x]` setzen. Die **Architektur-Entscheidungen** weiter unten sind verbindlich und sollten nicht ohne bewussten Grund verworfen werden; sie sichern die prüferische Belastbarkeit und die Vertraulichkeit.

**Dokumentations-DoD (gilt für jede Phase).** Zur „Definition of Done" jeder Phase gehört, dass sie in der projektbegleitenden Doku (`docs/`, Sphinx + MyST, veröffentlicht über Read the Docs) so dokumentiert ist, dass die Schritte auf einem frischen Rechner nachvollziehbar sind. Pro Phase eine Seite unter `docs/phasen/`. Build-Konfiguration: `.readthedocs.yaml` + `docs/conf.py` + `docs/requirements.txt`. Die Doku enthält ausschließlich Logik/Vorgehen — niemals Mandantendaten.

---

## Leitprinzip: die Vertrauensgrenze

Die gesamte Architektur trennt strikt zwischen **Logik** und **Daten**:

- **GitHub-Repo** enthält ausschließlich Logik, Umgebung und Darstellung — niemals Mandantendaten.
- **Lokale Umgebung** (verschlüsselt, kontrolliert) enthält die sensiblen SAP-Extrakte und führt die Auswertung durch.
- Verteilung erfolgt über das Repo (Logik) und Docker Compose (Umgebung). Daten bleiben lokal; ein befülltes Ergebnis wird nur als verschlüsselter Dump unter Mandanten-/Berufsgeheimnis-Auflagen weitergegeben.

Hintergrund: SAP-Berechtigungsdaten zeigen, wer in einem (regulierten) Finanzsystem was darf. Das berührt Datenschutz, Berufsgeheimnis sowie — je nach Mandant — DORA-Auslagerung. Diese Grenze ist nicht verhandelbar.

---

## Architektur-Entscheidungen (verbindlich)

**AE-01 — Logik/Daten/Secrets getrennt.** `.gitignore` schließt `/data`, `.env` und `*.dump` aus. Passwörter nur über `.env` (lokal) bzw. Umgebungsvariablen.

**AE-02 — Schema reproduzierbar über `neo4j-migrations`.** Constraints und Indizes als versionierte Migrationsdateien (`V001__…`, `V002__…`), idempotent, in der DB als erledigt vermerkt.

**AE-03 — `Authorization` ist ein eigener Knoten, kein Edge.** Feldwerte innerhalb einer Berechtigung sind UND-verknüpft (z. B. `ACTVT=01` UND `BUKRS=1000`). Diese Gruppierung darf nicht durch Zerlegen in Einzelkanten verloren gehen. Feldwerte liegen als **Properties** am `Authorization`-Knoten.

**AE-04 — Knoten/Property/Kante-Faustregel.** Knoten = wird traversiert/eigenständig abgefragt/verbindet mehreres. Property = wird nur gelesen/gefiltert (Feldwerte, Gültigkeiten, Texte). Kante = das Verb (`ASSIGNED_TO`, `CONTAINS`, `HAS_AUTH`).

**AE-05 — Org-Werte als Property, nicht als Label/Knoten.** Kein `:CompanyCode1000`-Anti-Pattern. Org-Einheiten werden „genommen, wie sie kommen" (inkl. `*`). Labels nur für Kategorien kleiner, stabiler Kardinalität.

**AE-06 — `*`/unbeschränkt wird in der Abfragelogik normalisiert.** Drei gleichbedeutende Zustände auf einen Nenner bringen: expliziter `*`, Vollbereich (`LOW=' '`, `HIGH='ZZZ…'`), und nicht gepflegtes Org-Level. Effekt: `*` verbreitert einen Konflikt — scheinbar harmlose Treffer werden kritisch.

**AE-07 — Gültigkeit gehört auf die Kante.** `validFrom`/`validTo` als Neo4j-`date` (nicht String). SAP-Format `YYYYMMDD` beim Import konvertieren. `TO_DAT='99991231'` = unbegrenzt (auf fernes Datum mappen oder `null`-Konvention). Range-Index auf den Relationship-Properties.

**AE-08 — Effektive Gültigkeit = Schnittmenge über den ganzen Pfad.** Bei verschachtelten Sammelrollen muss das Datumsprädikat auf **jede** relevante Kante des Pfades (`all(rel IN relationships(p) WHERE …)`). Sonst falsch-positive/-negative Treffer. Auswertungen sind **stichtagsbezogen** (parametrisiert).

**AE-09 — Beide Berechtigungspfade abbilden.** Rollenbasiert (`AGR_1251` via `AGR_USERS`) **und** direkt zugewiesene Profile (`UST04`/`UST12`, z. B. `SAP_ALL`). Sammelrollen auflösen, abgeleitete Rollen samt Org-Ebenen berücksichtigen.

**AE-10 — Abgeleitete Schicht ist von Rohdaten getrennt und regenerierbar.** Findings/Capabilities tragen Provenienz (`asOf`, `runId`), liegen in einem Snapshot, werden vor jedem Lauf per `DETACH DELETE` neu gerechnet und sind **niemals Eingang** der nächsten Ableitung.

**AE-11 — SoD-Konflikttyp bestimmt den Ablageort.** Intra-Rollen-Konflikt (Design-Eigenschaft der Rolle) → an die Rolle (`:Role:ConflictingByDesign`). Inter-Rollen-Konflikt (erst die Kombination konfligiert) → eigener Finding-Knoten `(:SoDConflict)` mit Kanten zu User, beiden Rollen und Regel.

**AE-12 — Did-Do knüpft am `Transaction`-Knoten an, nicht am `Authorization`-Knoten.** STAD/ST03N kennt die ausgeführte Transaktion, nicht Objekt/Feld. Did-Do ist bewusst gröber und trifft Can-Do dort, wo beide den TCode teilen.

**AE-13 — STAD ist Nutzungs-, kein Audit-Log.** Für forensischen Nachweis Security Audit Log (SM20/SAL) bzw. Änderungsbelege (`CDHDR`/`CDPOS`). STAD/ST03N für Least-Privilege- und Materialisierungsanalyse.

**AE-14 — Reproduzierbarkeit über gepinnte Versionen.** Docker-Image-Tags (Neo4j Community, NeoDash, APOC) fixieren. „Läuft bei mir" = „läuft bei dir".

**AE-15 — Container-only auf Windows.** Neo4j, NeoDash und (idealerweise) `neo4j-migrations` laufen als Container über Docker Desktop/WSL2. Damit ist **keine lokale Neo4j- oder Java-Installation** auf dem Windows-Host nötig. `cypher-shell` wird über den laufenden Container aufgerufen, nicht lokal installiert. Details siehe Abschnitt „Windows-Spezifika".

---

## Phasen

### Phase 0 — Fundament & Umgebung
**Ziel:** Lauffähige lokale Neo4j-Umgebung und Repo-Gerüst.

- [x] **Docker Desktop mit WSL2-Backend** installieren. Dadurch keine lokale Neo4j-/Java-Installation nötig (AE-15).
- [x] `docker-compose.yml`: Neo4j Community + NeoDash, Versionen gepinnt, APOC-Plugin, Volumes für DB und Import (`./data/import` → `/var/lib/neo4j/import`). Relative Pfade mit Vorwärts-Slashes (`./data/db:/data`).
- [x] Repo-Struktur in `iam` anlegen (siehe Zielstruktur unten).
- [x] `.gitignore` (`/data`, `.env`, `*.dump`) und `.env.example` (Vorlage ohne echte Secrets).
- [x] **`.gitattributes`** anlegen (Zeilenenden für den Linux-Container erzwingen — sonst CRLF-Fehler):
  ```
  *.cypher text eol=lf
  *.sh     text eol=lf
  *.ps1    text eol=crlf
  ```
- [x] `docker compose up` testen; Neo4j Browser (`:7474`) und NeoDash (`:5005`) erreichbar.
- [x] `cypher-shell` über den Container aufrufbar (nicht lokal installiert — siehe Windows-Spezifika).
- [x] Doku-Setup (Sphinx + MyST, `.readthedocs.yaml`) und Phase 0 dokumentiert (`docs/phasen/phase-0.md`) — Dokumentations-DoD.

**DoD:** Frisch geklontes Repo bringt mit wenigen Befehlen eine leere, lauffähige Umgebung hoch.

---

### Phase 1 — Datenmodell
**Ziel:** Festgelegtes Schema (Labels, Relationship-Typen, Property-Keys) als Migrationen.

- [x] Kern-Knoten definieren: `User`, `Role`, `Profile`, `Authorization`, `AuthObject`, `Transaction` (+ `Dataset`-Registry).
- [ ] Erweiterungen nach Bedarf: `AuthField`, `ObjectClass`, `OrgValue` (nur falls Pivot nötig), `Service`/`FioriTile` (S/4). — *zurückgestellt, bei Bedarf als `V003__…`.*
- [x] Label-Schichtung festlegen: Primärlabel + Subtyp (`Role:Composite|Single|Derived`, `Profile:Single|Collective|Critical`, `User:Dialog|System|Communication`, `User:Active|Locked`) + Regelwerks-Markierung (`Transaction:Critical`, `AuthObject:Critical`).
- [x] Kantentypen: `ASSIGNED_TO` (User→Role, mit Gültigkeit), `CONTAINS` (Composite→Single), `DERIVED_FROM` (Derived→Master), `HAS_PROFILE` (User/Role→Profile), `HAS_AUTH` (Role/Profile→Authorization), `FOR_OBJECT` (Authorization→AuthObject), `CHECKS` (Transaction→AuthObject, aus SU24).
- [x] `V001__constraints.cypher`: Unique-Constraints (Dataset, User, Role, Profile, AuthObject, Transaction; Community-tauglich via synthetischem `key`, da `dataset` Teil des Schlüssels ist).
- [x] `V002__indexes.cypher`: Composite-Lookups `(dataset, id)` + Range-Index auf `ASSIGNED_TO(validFrom, validTo)`.
- [x] `V003__authorization_key.cypher`: Unique-Constraint auf `Authorization.key` (Korrektur — V001/V002 hatten Authorization bewusst ausgelassen, aber die Loader MERGE/MATCH-en darauf; ohne Index Full-Scans → stundenlange Importe). **Performance-Hauptursache, behoben.**
- [x] Modell dokumentieren (`docs/datamodel.md` + Mermaid-Diagramm).
- [x] **Versions-/Vergleichsdimension** `dataset` ins Schlüsseldesign aufgenommen (2025- vs. 2026-Stand in einer DB vergleichbar); mehrere Mandanten dagegen über getrennte Instanzen.
- [x] **Migrations-Tooling** als gepinnter Container (`docker/neo4j-migrations.Dockerfile`, Compose-Service `migrations`, profile `tools`) — AE-02/AE-15.
- [x] Phase in der Doku dokumentiert (`docs/phasen/phase-1.md`) — Dokumentations-DoD.

**DoD:** `neo4j-migrations apply` stellt das vollständige Schema reproduzierbar her. ✓ verifiziert (`Database migrated to version 002.`).

---

### Phase 2 — Datenimport (Can-Do / Rohdaten)
**Ziel:** SAP-Berechtigungsstammdaten als Graph.

Relevante Quelltabellen: `USR02` (Benutzer), `USR04`/`UST04` (Direktprofile), `USR10`/`UST10*` (Profile), `USR11` (Profiltexte), `UST12`/`USR12` (manuelle Feldwerte), `AGR_DEFINE` (Rollen, inkl. `PARENT_AGR`), `AGR_USERS` (Zuordnung+Gültigkeit), `AGR_AGRS` (Sammel→Einzel), `AGR_PROF` (Rolle→Profil), `AGR_1251` (Berechtigungsdaten), `AGR_1252` (Org-Ebenen), `AGR_TCODES`, `TOBJ`/`TOBC`, `TACT`/`TACTZ`, `TSTC`/`TSTCA`, `USOBT_C`/`USOBX_C` (SU24-Brücke TCode→Objekt).

- [x] Extraktionsleitfaden dokumentieren (welche Tabellen, welche Felder, Format CSV) — `docs/extraktionsleitfaden.md`.
- [x] `load/`-Skripte je Tabelle (`LOAD CSV`) → Knoten und Kanten. CSV-Dateien auf dem Host nach `./data/import` legen und in Cypher als `file:///01_users.csv` referenzieren — **keine** Windows-Absolutpfade (`C:\…`), die der Linux-Container nicht versteht.
- [x] Gültigkeiten typisieren (Date-Konvertierung) — Format hier `DD.MM.YYYY`, `31.12.9999`→`9999-12-31`, `00.00.0000`→`null` (AE-07).
- [x] `*`/unbeschränkt als Property speichern; Normalisierung erfolgt in der Abfragelogik (AE-06).
- [x] Sammelrollen-Auflösung (`CONTAINS` aus AGR_AGRS). *Abgeleitete Rollen (`DERIVED_FROM`) zurückgestellt — keine Quelle im Extrakt (`PARENT_AGR`=Sammelrolle).*
- [x] **Beide Pfade vollständig:** Rollenpfad (`AGR_1251`→08, `CHECKS` aus `USOBT_C`→10) **und** Profilpfad (direkte Profile `UST04`→06; profilseitige Auths/Feldwerte `UST10S`→18/`UST12`→19; Sammelprofile `UST10C`→15).
- [x] **Anreicherung:** Transaktions-/Objekt-/Auth-/Rollentexte (`TSTCT`→09, `TOBJT`→13, `USR13`→20, `AGR_TEXTS`→21), Rollenmenü (`AGR_TCODES`→17), Org-Ebenen (`AGR_1252`→16), Referenzuser (`USREFUS`→14), Benutzernamen (`V_USERNAME`→12), Subtyp-Labels (`90_finalize`).
- [x] **Sprach-Schalter** `$lang`/`IMPORT_LANG` für sprachabhängige Texttabellen (Default `DE,DEU,D`).
- [x] **Profil-Generierungsstatus** (`AGR_1016B`→22) als `:Role.profileGenerated`/`profileState` — erkennt Rollen mit Auth-Daten, aber ohne generiertes Profil (konzeptunabhängig).
- [x] Importvalidierung (Zähler je Knoten-/Kantentyp) — `load/99_validate.cypher`.
- [x] SE16-Konverter `load/Convert-Se16Export.ps1` (unkonvertiert → UTF-8/Tab/CSV; container-only, kein Python): konvertiert den **ganzen Ordner**, **prüft das Minimalset** vor dem Lauf (`config/required_tables.json`) und **verwirft Credential-Spalten** (Passwort-Hashes, Defense in Depth).
- [x] Phase in der Doku dokumentiert (`docs/phasen/phase-2.md`) — Dokumentations-DoD.

**DoD:** Beide Berechtigungspfade (rollenbasiert + direkt) vollständig im Graphen; stichprobenartig gegen SAP nachvollziehbar. ✓ verifiziert: beide Pfade (inkl. Feldwerte) erzeugen `Authorization`/`Transaction`/`ASSIGNED_TO`/`HAS_PROFILE`/`CHECKS`/`HAS_MENU` in plausibler Größenordnung, stichprobenartig gegen SAP nachvollzogen.

> **Performance (gelöst):** Die langsamen Importe (`08`/`18`/`19`/`20`, teils Stunden) hatten zwei Ursachen: (1) **fehlender Index auf `Authorization.key`** → Full-Label-Scan bei jedem MERGE/MATCH (Hauptursache, behoben via `V003`); (2) O(n²)-Read-Modify-Write beim `f_<FELD>`-Array-Append in `19` (UST12) → behoben durch **Zwei-Pass/Aggregate-First** (`collect DISTINCT` je Auth/Feld, dann einmal setzen). `08` (AGR_1251) und `19` (UST12) wurden auf Aggregate-First umgestellt; `18`/`20` profitieren allein vom Key-Index (kein O(n²), nur Lookups). Ergebnis end-to-end (verifiziert, byte-identische Daten): `08` ~3 h → **7 s**, `18` 88 min → **3 s**, `19` 4,6 h → **9 s**, `20` >33 min → **3 s**. Die gesamte Import-Pipeline läuft jetzt in unter einer Minute.

---

### Phase 3 — Auswertungslogik (Checks & SoD)
**Ziel:** Einzelberechtigungs-Checks und SoD-Konfliktanalyse.

**Modell-Entscheidung:** Die Rulesets sind **query-/ausdrucksbasiert** (KPMG/CSI tools), nicht eine einfache TCode-Matrix. Eine Query = Funktionsbaustein (Berechtigungsobjekte + TCodes); eine SoD-Regel = boolescher Ausdruck über Query-Variablen. Drei Rulesets, konstant; Systeme (`dataset`) variabel; **ein Ruleset pro Lauf**.

Ruleset-Aufbereitung (abgeschlossen):
- [x] **3 Rulesets nach JSON normalisiert** unter `rules/<ruleset>/`: `kpmg_r3` (R/3, aus Excel), `csi`/`csi_bi` (CSI-tools-XML). Quellen + Konverter unter `rules/_archive/`.
- [x] **Einheitliches Kern-Schema** über alle drei (`rules/SCHEMA.md`) → ein Loader/Evaluator genügt. SAP-Texte bewusst nicht im Ruleset (kommen aus dem Graphen).
- [x] **Verknüpfungssemantik** je Ruleset in `ruleset.json → combinationSemantics` (Werte AND/OR per `andLogic`, Felder/Objekte UND, TCodes ODER, Auth↔TCode UND, `queryType`=Scope).
- [x] **Kritikalität normalisiert** (`very-high>critical>high>medium>low` + Rank) ruleset-übergreifend; **Module** (CSI-Vokabular; KPMG zu 55 % via TCode-Match) + CSI-**Risk**-Objekte.
- [x] **Auswertungs-Profile** `config/analysis_profiles.json`: Org-Modi (`ignoreOrg`/`wildcardOnly`/`filtered` mit `AND`/`OR`/`RANGE`, Org-Felder aus `USORG`) **und** Scope-Selektoren (`fi-only`, `very-critical`, …).

Bau:
- [x] **Ruleset-Loader** `cypher/ruleset/load_ruleset.cypher`: `(:Query)`/`(:AuthReq)`/`(:SoDRule)` aus den JSON (apoc.load.json), idempotent; Org-Felder `(:OrgField)` aus USORG (`load/23`).
- [x] **Einzelberechtigungs-Matcher** `cypher/checks/query_match.cypher` (parametrisiert `$ruleset`/`$query`/`$dataset`/`$asOf`): Query-Matching pro User nach `combinationSemantics` + AE-06 (Werte AND/OR, Felder/Objekte UND, TCodes ODER, Auth↔TCode UND); **Org-Felder im Default „egal"** (wie `*`). Validiert (Treffermengen diskriminieren je Query; ein TCode-Fall als manueller Gegencheck ±Gültigkeit).
- [x] **SoD-Evaluator** (Zwei-Schritt, reine Mengenlogik): CNF-Klauseln beim Laden (`(:SoDRule)-[:HAS_CLAUSE]->(:Clause)-[:NEEDS]->(:Query)`). `cypher/sod/materialize_matches.cypher` materialisiert das Zwischenergebnis `(:User)-[:MATCHES]->(:Query)` (nur SoD-relevante Queries); `cypher/sod/evaluate_sod.cypher` wertet darauf aus → Findings `(:SoDConflict)` (jede Klausel ≥1 gematchte Query), Risiko/Kritikalität aus `(:SoDRule)` angehängt. **Nutzertyp-Filter** (`$userTypes`, z. B. `['Dialog','Service']` vs. alle) und **Sleeping-Regel** (`$sleepDays`=180 → `userSleeping`-Flag; `cypher/checks/sleeping_users.cypher`). Validiert (Stichtag = Datenstand): Findings entstehen, der Nutzertyp-/Kritikalitäts-Scope greift, Evidenz je Klausel geprüft.
- [x] **Org-`filtered`-Modus** (`$orgFilters`: `AND`/`OR`/`RANGE`) im `query_match` nachgerüstet (Default `{}` = „egal"); `userTypes`/`sleepDays`/`orgFilters` als Profile in `config/analysis_profiles.json`; **Phase-3-Doku** (`docs/phasen/phase-3.md`) mit voller Parametrisierung.
- [x] **Org-Level-Platzhalter aufgelöst** (`load/24_resolve_org_levels.cypher`): in role-eigenen Auths wird der Platzhalter (`$BUKRS`) durch die Rollenwerte (`Role.org_$BUKRS`, AGR_1252) ersetzt — der Org-Filter (`$orgFilters`) sieht danach echte Werte. Filter-Logik (AND/OR/RANGE, `*`, Bereiche) isoliert bewiesen; Auflösung verifiziert. *(Wo Org-Scoping kaum genutzt wird — meist `*` —, schränkt der Filter selten ein; das ist Daten, kein Bug.)*
- [x] **Scope im SoD-Lauf** (`evaluate_sod.cypher`): `$minCriticalityRank` (z. B. 5 = nur very-high) und `$sodRules` (explizite Regeln). Validiert: voller Lauf vs. „nur very-high" vs. einzelne Regel — der Scope greift erwartungsgemäß (weniger Regeln/Findings). *(Modul-Scope für SoD → Phase X.)*
- [x] **Einzel-Checks** (`cypher/checks/`) — `sap_all.cypher` (wer hat `SAP_ALL`, beide Pfade): liefert die SAP_ALL-Träger inkl. aktiver Dialog-Nutzer (`SAP*`/`DDIC`).
- [x] **Findings-Snapshot** (`evaluate_sod.cypher`): `(:SoDConflict {ruleId, ruleset, dataset, asOf, runId})` mit `VIOLATES`/`BASED_ON` + Kritikalität/`userSleeping`; `DETACH DELETE` des Laufs vor jeder Auswertung (AE-10). *(`VIA_ROLE`-Evidenz + Intra-/Inter-Unterscheidung → Phase X.)*

**DoD:** Reproduzierbarer SoD-Lauf zu frei wählbarem Stichtag, Ruleset und Profil, mit vollständiger Nachweiskette (Regel, Pfade, Stichtag, Run, Ruleset).

---

### Phase 5 — Runner & Orchestrierung
**Ziel:** Wenige Befehle rechnen Import bzw. Auswertung — **zwei** Runner (statt einem `run_all`).

- [x] **`run/run_import.ps1`** (`-Dataset`, `-Lang`, `-SkipConvert`): konvertieren (Minimalset-Prüfung + Credential-Denylist) → migrieren → alle `load/*.cypher` in Reihenfolge (`-P dataset`/`-P lang`) → `99_validate`. Container-only; Passwort aus `.env`; `$LASTEXITCODE`-geprüft.
- [x] **`run/run_evaluate.ps1`** (`-Ruleset`/`-Dataset`/`-AsOf` + Profile): Ruleset laden → `materialize_matches` → `evaluate_sod`. Löst **Profile aus `config/analysis_profiles.json`** auf (`-UserTypeProfile`, `-OrgProfile`, `-SleepDays`, `-MinCriticalityRank`, `-SodRules`) und baut die `-P`-Cypher-Literale; parametrisierbarer Stichtag/`runId`; Zusammenfassung je Lauf (Findings/Regeln/sleeping). Validiert (`dialog-service`/very-high — Scope greift).
- [ ] (optional) Linux/macOS-Varianten (`.sh`); Did-Do-Schritt erst mit Phase 8.

**DoD:** Frischer Lauf auf einem zweiten Rechner liefert identische Ergebnisse (gleiche Daten vorausgesetzt). *(Import-Runner verifiziert; Auswerte-Runner verifiziert.)*

---

### Phase 6 — Darstellung (Dashboards)
**Ziel:** Versionierte, ansprechende Ergebnisdarstellung.

> **Zwischenschritt zur App (Phase 9).** NeoDash ist die **schnelle Anzeige-Schicht**, um die visuellen Inhalte (KPIs, Graph-Pfade, Tabellen) festzulegen. Es ist **nicht** die finale App (kein Import/Backup/Excel/Workflow); die Cypher hinter den Karten sind aber 1:1 in der App (Phase 9) wiederverwendbar.

- [x] NeoDash lokal an die DB angebunden (Browser → `:5005`, Bolt `:7687`); Dashboard-Import getestet.
- [x] **PoC-Dashboard** `dashboards/sod_poc.json`: KPI-Kacheln (Findings, betroffene User, aktive, SAP_ALL **im Scope**), Top-Regeln-Tabelle, Graph der very-high-Konfliktpfade, **`runId`-Selektor** (`$neodash_runId`, Default `current`). Scope-Konsistenz über `(:Run)`-Knoten (SAP_ALL folgt dem Lauf: `current`=39 / `dialog-active`=21).
- [x] Dashboard als JSON in `dashboards/` committet (PoC); kanonische Fassung nach UI-Feinschliff erneut exportieren.
- [ ] *(Ausbau, optional)* weitere Reiter (nach Kritikalität, Nutzer-Hygiene, Org-Sicht, Drill-down) + Selektoren (Dataset/Stichtag). **Showcase-Stopp gesetzt.**

> Das **gebrandete NVL/React-Frontend** ist **nicht** Teil von Phase 6 — es ist die Oberfläche der App und steht unter **Phase 9**.

**DoD:** Dashboard reproduzierbar aus dem Repo herstellbar; Darstellung ist versioniert. *(PoC erfüllt.)*

---

### Phase 7 — Verteilung & Reproduzierbarkeit
**Ziel:** Weitergabe an andere Rechner/User ohne Datenweitergabe.

- [ ] `docker-compose.yml` mit gepinnten Versionen finalisieren.
- [ ] Onboarding-`README`: klonen → `docker compose up` → eigene SAP-Extrakte nach `data/import` → Runner → Dashboard-JSON importieren.
- [ ] Klarstellen: Über Repo/Compose wandert nur Logik/Umgebung, nie Mandantendaten.
- [ ] Verfahren für Ergebnisübergabe (`neo4j-admin database dump`, verschlüsselt, unter Auflagen) dokumentieren — Ausnahmefall.

**Deployment-Optionen.** Verteilungseinheit ist heute **Docker Compose** (ein Befehl, lokal). Der
Stack ist **Kubernetes-fähig** (z. B. interner, abgesicherter Unternehmens-Cluster) — die Compose-
Services übersetzen sich nach K8s mit überschaubarem Aufwand:
- **neo4j** als `StatefulSet` mit **PVC** (Community = Single-Instance, kein Clustering), Passwort als `Secret`.
- **backend** als `Deployment` (vorerst **1 Replica** — Jobs liegen in-memory; für horizontale Skalierung später Job-Status in einen Shared Store auslagern). Code/Config (`cypher/`, `load/`, `migrations/`, `config/`, `rules/`, `frontend/`) ins Image backen; `data/import` + `backups` als **PVC**. Hinweis: `neo4j` braucht das Import-Verzeichnis und `rules/` (für `LOAD CSV` / `apoc.load.json`) ebenfalls als Volume/ConfigMap.
- **Zugang** über `Service`/`Ingress` **nur clusterintern bzw. hinter Unternehmens-Auth** (SSO/OIDC am Ingress, NetworkPolicy). „public" = im internen, gesicherten Cluster — **nicht** ins offene Internet. Die Vertrauensgrenze bleibt: Daten/PVCs in der kontrollierten Umgebung.
- Optional: Helm-Chart/Kustomize als reproduzierbares Deployment-Artefakt.

**DoD:** Ein Kollege bringt das Projekt auf einem eigenen Rechner identisch zum Laufen, ohne dass Mandantendaten das Repo berühren.

---

### Phase X — Backlog / Sammelbecken (zurückgestellt)

Bewusst nach hinten gestellte Punkte — sinnvoll, aber nicht auf dem kritischen Pfad.

- [ ] **CSI-Rulesets CNF-zerlegen** (`clauses` in `sod_rules.json` für `csi`/`csi_bi`), damit die SoD-Auswertung auch über die CSI-Kataloge läuft. *(KPMG ist bereits scharf; die Mechanik ist generisch.)*
- [ ] **Kritische TCodes/Objekte taggen** (`:Critical`) — **Ansatz noch offen**: Kritikalität steckt bereits im Ruleset (`soxClassification`/`criticality`, Query-Scope). Ob ein zusätzliches, ruleset-unabhängiges `:Critical`-Tagging nötig/sinnvoll ist, ist zu entscheiden, bevor gebaut wird.
- [~] **Intra- vs. Inter-Rollen-Konflikt (AE-11) + Evidenz — umgesetzt (v1).** `cypher/sod/explain_sod.cypher` rechnet pro Finding die **verursachenden Rollen/Profile** aus (`(:SoDConflict)-[:VIA_ROLE]->(:Role)` / `-[:VIA_PROFILE]->(:Profile)`) und klassifiziert `conflictType` **intra** (eine Rolle/ein Profil deckt alle Klauseln allein — „by design") vs. **inter** (erst die Kombination). Hilfsrelation `(:Role|:Profile)-[:PROVIDES {ruleset}]->(:Query)` (Akteur erfüllt Query allein), reine Mengenlogik auf MATCHES. Sichtbar in `/findings`, CSV-Export und der UI (Spalten **Typ** + **Verursacht durch**). **Opt-in**, da teuer: per Lauf-Formular „Evidenz mitberechnen" oder nachträglich `POST /runs/{id}/explain` (Ribbon „Evidenz"). *Offen: Perf-Optimierung (vorab geflachte Rollen→Auth-Erreichbarkeit), und **AE-08** Pfad-Gültigkeitsschnittmenge bei verschachtelten Rollen.*

---

### Phase 8 — Did-Do (Nutzung aus STAD/ST03N) — *die Kür, zuletzt*
**Ziel:** Nutzungssicht und Can-Do×Did-Do-Matrix. Bewusst als Letztes — wertvoll, aber nicht auf dem kritischen Pfad.

- [ ] Extraktionsweg festlegen: ST03N-Aggregate (`SWNC_COLLECTOR_GET_AGGREGATES`, `ENTRY_ID`=TCode/Report, `TASKTYPE`) als pragmatischer Einstieg; bei Bedarf regelmäßige Roh-STAD-Extrakte; für Forensik SAL/`CDHDR`.
- [ ] `EXECUTED`-Kanten (User→Transaction) mit `count`, `firstSeen`, `lastSeen`, `taskType`, `asOf`, `runId` in die Snapshot-Schicht.
- [ ] Matrix-Abfragen: ungenutzte Berechtigungen (Least-Privilege-Kandidaten), materialisierte SoD (Did-Do auf beiden Konfliktseiten).
- [ ] Caveats dokumentieren: Aufbewahrungsfenster (≥1 Jahr für Abschlussprozesse), selten-aber-vital, indirekte Aufrufe nicht erfasst, kein Audit-Log (AE-13), S/4-Fiori/OData-Ebene.
- [ ] **Datenschutz/Mitbestimmung** (§ 87 BetrVG): benutzerbezogene Nutzungsauswertung als Hinweis an den Mandanten; Pseudonymisierung der User-ID für Statistik, Klartext nur im begründeten Einzelfall.

**DoD:** Matrix-Auswertung lauffähig; ungenutzte kritische Berechtigungen und materialisierte SoD-Konflikte werden ausgewiesen.

---

### Phase 9 — Anwendung (transportable Docker-App)

**Ziel:** Eine **nutzerfreundliche, transportable App** (Docker), die den gesamten Ablauf ohne JSON-Pflege steuerbar macht. Baut **auf allem Bestehenden auf** — nichts wird weggeworfen: die **Runner** werden Backend-Operationen, die **`dataset`-Dimension** trägt „neuer Mandant vs. Vergleich", die **Findings im Graph** sind der Ergebnis-Store, **Profile/Config** werden von App-Formularen gefüllt. NeoDash (Phase 6) ist der **Zwischenschritt** der Anzeige; die Cypher hinter den Karten sind in der App wiederverwendbar.

**Architektur (lokal, Vertrauensgrenze bleibt):** `Front-end (Web) → lokaler Backend-Service (Runner-as-API, Jobs) → Neo4j`. Nur die Bedienoberfläche ist außen; **keine Mandantendaten verlassen** die Umgebung.

- [x] **Backend-Service** (Runner als API) — **Bau-Schritt 1 erledigt.** FastAPI-Container (`backend/`, Compose-Service `iam-backend`, Port 8000), orchestriert die vorhandenen `cypher/`-Dateien über den Neo4j-Treiber (statt `cypher-shell -f`; `apoc.cypher.runFile` ist apoc-**extended** und fehlt → Statements werden im Backend gesplittet und einzeln gefahren). Endpunkte: `GET /health`, `GET /datasets`, `GET /runs` (Scope/Provenienz aus `(:Run)`), `GET /findings?runId&minRank`, `POST /runs` → **asynchroner Job** (Hintergrund-Thread: optional load_ruleset → materialize → evaluate), `GET /jobs/{id}` (Status/Schritt/Ergebniszähler). Profile/Sleeping aus `config/analysis_profiles.json`, Ruleset-Ordner per Scan über `rules/*/ruleset.json`. *Org-Filterung (placeholder/AGR_1252) noch nicht verdrahtet — Profil wird validiert + auf `(:Run)` protokolliert.*
- [x] **Import-Endpunkt** (`POST /imports`) — **Bau-Schritt 3 erledigt.** Voller Import als asynchroner Job **im Container** (kein PowerShell mehr nötig): **konvertieren → Schema → laden → validieren**. Der SE16-Konverter ist nach **Python portiert** (`backend/convert.py`, zeilengleich zu `load/Convert-Se16Export.ps1` inkl. Credential-Denylist; gegen die aktuelle PS-Version byte-identisch verifiziert); Schema über die idempotenten `migrations/*.cypher`, Laden über `load/*.cypher` (Reihenfolge = Dateiname) mit `$dataset`/`$lang`. Zusatz: `GET /import-folders` (vorhandene `data/import/<dataset>` mit txt/csv-Zählung). Verifiziert: voller Import (alle Pflichttabellen) in deutlich unter zwei Minuten → User/Rollen/Berechtigungen vollständig im Graphen. `data/import` als RW-Mount im Backend — **bleibt lokal**.
- [ ] **Import-Evidenz (Vollständigkeitsnachweis gegen Quell-SAP):** persistente, abrufbare
  Import-Statistik je Lauf für die Nachvollziehbarkeit. Heute nur flüchtig (Job-Counts) bzw.
  Konsole (`99_validate`).
  - **Persistenz:** `(:Import {dataset, importedAt, lang})` + je Tabelle `(:ImportTable {table,
    sourceRows, droppedColumns})` (der Konverter liefert Zeilen/verworfene Spalten bereits) und die
    resultierenden Graph-Zähler je Label/Kante (`99_validate`-Logik).
  - **Abgleich/Checks:** je Quelltabelle **Quellzeilen ↔ Graph-Ergebnis** mit dokumentierter
    Beziehung — **1:1** (USR02→User, AGR_DEFINE→Role …, Abweichung = Flag) vs. **aggregiert**
    (AGR_1251-Zeilen → gruppierte `Authorization` nach AE-03; UST12-Feldwerte) → beide Zahlen zeigen,
    nicht als Fehler werten. Gefilterte Zeilen (z. B. `DELETED='X'`) ausweisen.
  - **API/UI:** `GET /datasets/{d}/import-evidence`; in der UI **KPI-Kacheln** (Knoten/Kanten gesamt,
    Tabellen, verworfene Sensibel-Spalten) **+ Reconciliation-Tabelle** (Tabelle · Quellzeilen ·
    Graph · Status), hübsch aufbereitet.
  - **Export:** **Import-Evidenz-Report** (CSV, später PDF) zum Ablegen/Weitergeben.
- [~] **Front-end — geführte Workflows** — **Bau-Schritt 4: Ribbon-Oberfläche nach Lebenszyklus.** Schlanke statische Single-Page (`frontend/index.html`), **vom Backend ausgeliefert** (kein Node/React-Build, ein Container) unter `http://localhost:8000/`. **Ribbon-Bar oben** gegliedert wie der Ablauf: **1 Daten · 2 Auswertung · 3 Ergebnisse · 4 Sichern · 5 Verwalten**; Befehle öffnen **Dialoge**, der Hauptbereich zeigt durchgehend die **Ergebnisse** (KPIs · Läufe · Findings). **Import-Dialog** mit **ZIP-Upload** (`POST /imports/upload`, `python-multipart`; entpackt `.csv`/`.txt` → konvertiert ggf. → Import) **und** vorhandenem Ordner (`POST /imports`). **Auswerte-Dialog**: datengetriebenes Parameter-Formular statt JSON (aus `GET /profiles`). **Ergebnisse**: Läufe-Liste mit Findings-Zahl (Counts jetzt in `GET /runs`), KPIs beim Anklicken eines Laufs, Findings-Tabelle, **CSV-Export** des aktiven Laufs. **Sichern**- und **Verwalten**-Dialoge (Backup/Restore, Clear/Reset). Poliertes **Banner** (Wortmarke, Tagline, Status-Chips: Verbindung / N Datasets · M Läufe) und eine **Admin-Gruppe** (Ribbon 6) als Heimat der geplanten Regelwerks-Funktionen (zeigt die geladenen Rulesets; Editor/Filterset-Import noch „geplant"). *Offen: gebrandetes NVL/React bleibt der „Fancy"-Schritt unten.*
#### Geführte Auswertung (Auswerten v2) — gezielte Filter-/Scope-Auswahl

Statt „ein Lauf über alle 600+ Filter": nach dem Import gezielt **auswählen, was** ausgewertet wird,
**für wen**, und **wie tief**. Vieles existiert bereits als Backend-Parameter (`sodRules`,
`userTypes`, `excludeLocked`, `sleepDays`, `minCriticalityRank`) und scopeProfiles in
`config/analysis_profiles.json` — hier fehlt v. a. die **geführte Auswahl-UI** und etwas Backend.

- [ ] **Katalog-Auswahl (Filter/Regeln):** Browser über die Queries (Einzelfilter) **und** SoD-Regeln,
  **filterbar** nach Kritikalität (z. B. nur very-high), **Namensmuster** (z. B. `BC_*`), Modul,
  queryType. Mehrfachauswahl → Lauf nur über die Auswahl. *(Kritikalität/explizite Regel-IDs ✓ als
  Param; Muster-/Modul-Filter + UI neu.)*
- [ ] **Zwei Auswertungsarten:** **(a) Einzelfilter / Can-Do** — „wer matcht Query X" (nur
  Materialisierung der gewählten Queries, ohne SoD); **(b) SoD-Konflikte** — bei Auswahl bestimmter
  SoD-Regeln **zuerst nur deren Einzelfilter** (Klausel-Queries) materialisieren, dann SoD.
  → **scoped materialize** statt „alle SoD-Queries". *(neu; heute materialisiert der Lauf alle
  SoD-relevanten Queries.)*
- [ ] **Nutzer-Scope verfeinern:** Nutzertypen (A/S…) ✓; **Sleeping** als Eingabefeld **+ Schnellwahl
  90/180/360 Tage**; **Gesperrte nach Sperrtyp** auswählbar (failed_logons / admin_local /
  admin_global — Daten liegen als `lockReasons` vor) statt nur `excludeLocked`-Bool. *(Sperrtyp-Filter
  neu; Sleeping-Wert ✓ im Backend.)*
- [ ] **Lauf verwalten:** einen einzelnen **Lauf löschen** (`(:Run)` + dessen Findings/VIA/MATCHES),
  optional **vorher sichern** (Findings-CSV-Export als „Backup") oder einfach löschen. *(per-Run-Delete
  neu; CSV-Export ✓.)*
- [ ] **Evidenz-Perf:** vorab geflachte Erreichbarkeit `(:Role|:Profile)-[:GRANTS]->(:Authorization)`
  (transitive Hülle CONTAINS/HAS_PROFILE), damit `explain_sod` (intra/inter + VIA_ROLE) ein Lookup
  statt variabler Pfadsuche wird → Evidenz default-on möglich. *(Optimierung der v1 aus Phase X.)*

- [ ] **System/Mandant-Wahl:** „neuer Stand/Mandant" **oder** „Vergleich zu bestehendem" → **Vergleichs-Abfragen** über zwei `dataset` (neue/entfallene Konflikte, Delta je Regel/User).
- [ ] **Fancy Auswertungen:** KPIs, **Graph-Darstellung** der Konfliktpfade (gebrandetes Frontend mit **NVL/React** statt NeoDash), Heatmap/Matrix, Drill-down. Die NeoDash-Karten-Cypher (Phase 6) sind die Vorlage.
- [~] **Export** der Ergebnisse — **CSV erledigt.** `GET /findings/export?runId=…` liefert die Findings eines Laufs als **CSV** (Semikolon, UTF-8-BOM → direkt Excel-tauglich), getrennt vom Quell-Backup; in der UI als „Export CSV" (Ribbon, aktiver Lauf). *Offen: natives `.xlsx` (z. B. openpyxl) und weitere Sichten (Top-Regeln, Matrix).*
- [x] **Backup/Restore/Clear** — **erledigt.** **Clear:** `POST /datasets/{d}/clear` (ein Dataset inkl. dessen Runs/Findings/Matches) und `POST /reset` (alle Daten) — **Ruleset + Schema bleiben** (direkt neu importier-/auswertbar). **Backup/Restore** bewusst auf **Quelldaten-Ebene** (statt `neo4j-admin dump`, das in Community den DBMS-Stopp braucht und nicht als App-Knopf geht): Backup = ZIP der konvertierten, **credential-bereinigten** `.csv` + Manifest (`POST /datasets/{d}/backup`, `clear=true` = **Backup & Clear** in einem); Restore = entpacken + deterministischer Re-Import (`POST /backups/{file}/restore`). **Online**, **transportabel** (eine herunterladbare Datei, `GET /backups/{file}/download`), trust-aware (nie die rohen `.txt`); Findings sind regenerierbar. `GET /backups` listet. UI-Sektion „Daten verwalten" + Backups-Liste (Wiederherstellen/Download) mit Sicherheitsabfrage; `backups/` gitignored. Verifiziert end-to-end: Backup → Backup&Clear (Graph geleert) → Restore (Daten zurück, Ruleset intakt) → Download (`application/zip`). *Cold-Full-DB-Dump (`neo4j-admin`, ganze DB inkl. Findings) bleibt optional auf Compose-`tools`-Ebene (Phase 7).*
- [~] **Admin-Bereich** — **Heimat angelegt** (Ribbon-Gruppe 6 „Admin": zeigt die geladenen Rulesets). *Geplant darin:* **Ruleset-Editor** (SoD-Filter nachjustieren; Vendor-Basis regenerierbar von Kunden-Erweiterungen getrennt, Round-Trip auf die JSON) und **Filterset-/Konnektor-Import** für weitere Systeme — perspektivisch **SAP S/4HANA, Azure AD/Entra, Microsoft Dynamics, Salesforce** (je System ein eigenes Ruleset; Datenmodell bleibt gleich).
- [ ] **Kein eigenes Benutzer-/Berechtigungskonzept** (bewusste Entscheidung): die App läuft lokal bzw. wird als Container verteilt; der Zugriff wird über die (lokale/Unternehmens-)Umgebung abgesichert. Eine Auth-Schicht (SSO/OIDC am Ingress) kommt erst, wenn die App **mehrbenutzerfähig zentral** betrieben wird — siehe Deployment-Notiz in Phase 7.

**DoD:** Eine transportable App, in der Import, parametrierte Auswertung, Vergleich, Anzeige, Export und Backup/Restore ohne JSON-Pflege bedienbar sind — lokal, ohne dass Mandantendaten die Umgebung verlassen.

---

## Zielarchitektur — Laufzeit (Phase 9)

Lokal, ein Compose, Vertrauensgrenze bleibt — **keine Mandantendaten verlassen** die Umgebung:

```
 Browser (http://localhost:8000/)
   │  statische Ribbon-UI (frontend/index.html), vom Backend ausgeliefert
   ▼
 iam-backend  (FastAPI, Port 8000)            ← Runner-as-API, asynchrone Jobs
   │  Import (Ordner/ZIP) · Auswertung · Findings/Export · Backup/Restore · Clear/Reset
   │  orchestriert die cypher-/load-/migrations-Dateien über den Neo4j-Treiber
   ▼
 iam-neo4j  (Neo4j 5 Community + APOC, Bolt 7687 / Browser 7474)
   ├─ Rohschicht je `dataset` (User/Role/Profile/Authorization/…)
   ├─ konstante Ruleset-Schicht (Query/SoDRule/AuthReq/Clause)
   └─ regenerierbare Findings (:SoDConflict) + (:Run)-Scope/Provenienz

 iam-neodash (PoC-Anzeige, Port 5005)   ·   iam-migrations (Schema, profile: tools)
```

## Zielarchitektur — Repo-Struktur

```
iam/
├─ ROADMAP.md / README.md
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
│   ├─ sod/                    # SoD-Materialisierung + Auswertung
│   ├─ ruleset/               # Ruleset-Loader (JSON → Graph)
│   └─ admin/                  # clear_dataset / reset_data (gebatcht)
├─ dashboards/                 # NeoDash-Export (JSON, PoC)
├─ run/                        # run_import.ps1 / run_evaluate.ps1 (Host-Runner, weiter nutzbar)
├─ docs/                       # Sphinx/MyST (Read the Docs): Phasen, Datenmodell, Extraktionsleitfaden
├─ data/                       # GITIGNORED: SAP-CSV + Import + DB-Volume
└─ backups/                    # GITIGNORED: Dataset-Backups (.zip der bereinigten .csv)
```

> **Hinweis zu den Host-Runnern.** `run/*.ps1` (PowerShell) bleiben als Host-Variante nutzbar; die **App-Endpunkte** im `backend/` sind die plattformunabhängige, container-interne Entsprechung (kein lokales PowerShell/`cypher-shell` nötig).

---

## Windows-Spezifika (Zielplattform)

Das Setup läuft **container-only** über Docker Desktop mit WSL2-Backend. Vorteil: keine lokale Neo4j- oder Java-Installation auf dem Windows-Host.

- **cypher-shell** wird nicht lokal installiert, sondern über den laufenden Container per Pipe aufgerufen:
  ```powershell
  Get-Content .\load\01_users.cypher | docker exec -i iam-neo4j cypher-shell -u neo4j -p "$env:NEO4J_PASSWORD"
  ```
- **neo4j-migrations** entweder als eigenes Container-Image (passend zum Container-only-Ansatz) oder lokal mit Java 21. Image-Variante bevorzugen.
- **LOAD CSV:** CSV-Dateien auf dem Host nach `./data/import`, in Cypher als `file:///dateiname.csv` referenzieren. Keine Windows-Absolutpfade (`C:\…`) — der Linux-Container versteht sie nicht.
- **Zeilenenden:** `.gitattributes` erzwingt LF für `.cypher`/`.sh` (sonst scheitert die Ausführung im Container an CRLF). `.ps1` bleibt CRLF.
- **Pfade in `docker-compose.yml`:** relative Pfade mit Vorwärts-Slashes (`./data/db:/data`) — funktioniert auf Docker Desktop unter Windows problemlos.
- **Secrets:** in PowerShell über `$env:NEO4J_PASSWORD`, gespeist aus der lokalen `.env` (gitignored).
- **Container-Name:** in der Compose-Datei fest vergeben (z. B. `iam-neo4j`), damit die `docker exec`-Aufrufe im Runner stabil sind.

---

## R/3 versus S/4HANA

Die Speicherstruktur der Berechtigungen ist identisch (`AGR_1251`, `USR02`, `UST04`, `USOB*` etc.) — ein Importschema funktioniert für beide. Unterschiede liegen im Zugriffsweg:
- **Fiori/OData** statt Dialogtransaktion: zusätzliche Ebene `Fiori-Tile → Target Mapping → OData-Service → Backend-Objekt` (`S_SERVICE`, `/UI2/*`). Für vollständige S/4-Bewertung mitmodellieren.
- Neue Objekte/Transaktionen (z. B. Business Partner `BP` statt `XD01`/`XK01`) → ändert Werte im Regelkatalog, nicht die Tabellenstruktur.
- **SACF/SLDW** (schaltbare Prüfungen) bei S/4-Vollständigkeitsbetrachtung beachten.

---

## Offene Punkte / Annahmen

- ~~Betriebssystem des Zielrechners~~ → **geklärt: Windows** (Container-only, PowerShell-Runner; siehe Windows-Spezifika).
- Verfügbarkeit/Format der SAP-Extrakte (Tabellen-Downloads, SE16/Reports) je Mandant.
- Umfang Org-Ebenen-Pivot (ob `OrgValue`-Knoten benötigt werden).
- S/4-Scope: ob die Fiori/OData-Ebene Teil des aktuellen Auftrags ist.
- Datenschutz-/Mitbestimmungsabstimmung für die Did-Do-Auswertung beim Mandanten.

---

## Glossar (Kurz)

- **Can-Do:** Was eine Berechtigung erlaubt (Berechtigungssicht).
- **Did-Do:** Was tatsächlich ausgeführt wurde (Nutzungssicht, STAD/ST03N).
- **SoD:** Segregation of Duties — unzulässige Funktionstrennung.
- **Intra-/Inter-Rollen-Konflikt:** Konflikt innerhalb einer Rolle vs. erst durch Rollenkombination.
- **Snapshot-Schicht:** Abgeleitete, regenerierbare Ergebnisse mit Provenienz (Stichtag, Run).


