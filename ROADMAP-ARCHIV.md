# Roadmap-Archiv — abgeschlossene Arbeit

Historischer Nachweis der **erledigten** Phasen/Bausteine. Die **offene Planung** steht in
[`ROADMAP.md`](ROADMAP.md); dort liegen auch die verbindlichen **Architektur-Entscheidungen
(AE-01…15)**, die **Vertrauensgrenze** und die Referenz (Zielarchitektur, Windows-Spezifika,
R/3-vs-S/4). Dieses Archiv beschreibt nur Logik/Vorgehen — niemals Mandantendaten.

**Erledigt:** Phasen 0–3 und 5 (Fundament, Datenmodell, Import/Can-Do, Auswertungslogik/SoD,
Runner) · Phase 6 als **PoC** (NeoDash, Showcase-Stopp) · Phase-9-Bausteine 1/3/4 (Backend-API,
Import im Container inkl. ZIP-Upload, Ribbon-UI), Backup/Restore/Clear, CSV-Export, AE-11-Evidenz v1.

---

## Phase 0 — Fundament & Umgebung
**Ziel:** Lauffähige lokale Neo4j-Umgebung und Repo-Gerüst.

- [x] **Docker Desktop mit WSL2-Backend** (keine lokale Neo4j-/Java-Installation, AE-15).
- [x] `docker-compose.yml`: Neo4j Community + NeoDash, Versionen gepinnt, APOC, Volumes für DB und Import.
- [x] Repo-Struktur, `.gitignore` (`/data`, `.env`, `*.dump`), `.env.example`.
- [x] **`.gitattributes`** (LF für `.cypher`/`.sh`, CRLF für `.ps1`).
- [x] `docker compose up` getestet; Neo4j Browser (`:7474`) und NeoDash (`:5005`) erreichbar.
- [x] `cypher-shell` über den Container aufrufbar.
- [x] Doku-Setup (Sphinx + MyST, `.readthedocs.yaml`), `docs/phasen/phase-0.md`.

**DoD ✓:** Frisch geklontes Repo bringt mit wenigen Befehlen eine leere, lauffähige Umgebung hoch.

## Phase 1 — Datenmodell
**Ziel:** Festgelegtes Schema (Labels, Relationship-Typen, Property-Keys) als Migrationen.

- [x] Kern-Knoten: `User`, `Role`, `Profile`, `Authorization`, `AuthObject`, `Transaction` (+ `Dataset`).
- [x] Label-Schichtung (Primärlabel + Subtyp) + Regelwerks-Markierung.
- [x] Kantentypen: `ASSIGNED_TO`, `CONTAINS`, `DERIVED_FROM`, `HAS_PROFILE`, `HAS_AUTH`, `FOR_OBJECT`, `CHECKS`.
- [x] `V001__constraints.cypher` (Unique-Constraints via synthetischem `key`).
- [x] `V002__indexes.cypher` (Composite-Lookups `(dataset, id)` + Range-Index `ASSIGNED_TO(validFrom, validTo)`).
- [x] `V003__authorization_key.cypher` (Unique-Constraint `Authorization.key`). **Performance-Hauptursache, behoben.**
- [x] Modell dokumentiert (`docs/datamodel.md` + Diagramm), `docs/phasen/phase-1.md`.
- [x] **Versions-/Vergleichsdimension** `dataset` im Schlüsseldesign; **Migrations-Tooling** als gepinnter Container.

**DoD ✓:** `neo4j-migrations apply` stellt das Schema reproduzierbar her.

> *Zurückgestellt (bei Bedarf):* Modellerweiterungen `AuthField`/`ObjectClass`/`OrgValue` (nur falls Pivot nötig), `Service`/`FioriTile` (S/4) — als `V004__…`.

## Phase 2 — Datenimport (Can-Do / Rohdaten)
**Ziel:** SAP-Berechtigungsstammdaten als Graph.

- [x] Extraktionsleitfaden (`docs/extraktionsleitfaden.md`).
- [x] `load/`-Skripte je Tabelle (`LOAD CSV`) → Knoten/Kanten; `file:///…` (keine Windows-Pfade).
- [x] Gültigkeiten typisiert (Date), `*`/unbeschränkt als Property (AE-06/AE-07).
- [x] Sammelrollen-Auflösung (`CONTAINS`). *Abgeleitete Rollen (`DERIVED_FROM`) zurückgestellt — keine Quelle im Extrakt.*
- [x] **Beide Pfade vollständig:** Rollenpfad (`AGR_1251`→08, `CHECKS` aus `USOBT_C`→10) **und** Profilpfad (`UST04`→06, `UST10S`→18/`UST12`→19, `UST10C`→15).
- [x] **Anreicherung:** Texte (`TSTCT`/`TOBJT`/`USR13`/`AGR_TEXTS`), Rollenmenü, Org-Ebenen, Referenzuser, Benutzernamen, Subtyp-Labels.
- [x] **Sprach-Schalter** `$lang`/`IMPORT_LANG` (Default `DE,DEU,D`).
- [x] **Profil-Generierungsstatus** (`AGR_1016B`→22).
- [x] Importvalidierung `load/99_validate.cypher`.
- [x] SE16-Konverter `load/Convert-Se16Export.ps1` (Minimalset-Prüfung + Credential-Denylist).
- [x] `docs/phasen/phase-2.md`.

**DoD ✓:** Beide Berechtigungspfade vollständig im Graphen; stichprobenartig gegen SAP nachvollzogen.

> **Performance (gelöst).** Langsame Importe (`08`/`18`/`19`/`20`, teils Stunden) hatten zwei Ursachen:
> (1) **fehlender Index auf `Authorization.key`** → Full-Label-Scan je MERGE/MATCH (Hauptursache,
> behoben via `V003`); (2) O(n²)-Read-Modify-Write beim `f_<FELD>`-Array-Append in `19` → behoben
> via **Aggregate-First** (`collect DISTINCT`, einmal setzen). Ergebnis (byte-identische Daten):
> die gesamte Import-Pipeline läuft jetzt in **unter einer Minute** (vorher Stunden).

## Phase 3 — Auswertungslogik (Checks & SoD)
**Ziel:** Einzelberechtigungs-Checks und SoD-Konfliktanalyse.

**Modell:** Rulesets **query-/ausdrucksbasiert** (KPMG/CSI), nicht eine TCode-Matrix. Query =
Funktionsbaustein (Objekte + TCodes); SoD-Regel = boolescher Ausdruck über Query-Variablen. Drei
Rulesets konstant; Systeme (`dataset`) variabel; ein Ruleset pro Lauf.

- [x] **3 Rulesets nach JSON normalisiert** (`rules/<ruleset>/`: `kpmg_r3`, `csi`, `csi_bi`; Quellen + Konverter in `rules/_archive/`).
- [x] **Einheitliches Kern-Schema** (`rules/SCHEMA.md`) → ein Loader/Evaluator. SAP-Texte aus dem Graphen, nicht im Ruleset.
- [x] **Verknüpfungssemantik** je Ruleset (`combinationSemantics`: Werte AND/OR, Felder/Objekte UND, TCodes ODER, Auth↔TCode UND, `queryType`=Scope).
- [x] **Kritikalität normalisiert** (`very-high…low` + Rank) ruleset-übergreifend; **Module** + CSI-**Risk**-Objekte.
- [x] **Auswertungs-Profile** `config/analysis_profiles.json` (Org-Modi + Scope-Selektoren).
- [x] **Ruleset-Loader** `cypher/ruleset/load_ruleset.cypher` (`(:Query)`/`(:AuthReq)`/`(:SoDRule)`; OrgFelder aus USORG).
- [x] **Einzelberechtigungs-Matcher** `cypher/checks/query_match.cypher` (Org-Felder Default „egal").
- [x] **SoD-Evaluator** (Zwei-Schritt): `materialize_matches.cypher` (`(:User)-[:MATCHES]->(:Query)`) → `evaluate_sod.cypher` (Findings `(:SoDConflict)`, CNF-Klauseln). Nutzertyp-Filter + Sleeping-Regel.
- [x] **Org-`filtered`-Modus** + **Org-Level-Platzhalter aufgelöst** (`load/24`, AGR_1252).
- [x] **Scope im SoD-Lauf** (`$minCriticalityRank`, `$sodRules`).
- [x] **Einzel-Checks** (`sap_all.cypher`).
- [x] **Findings-Snapshot** mit `VIOLATES`/`BASED_ON` + Provenienz; `DETACH DELETE` je Lauf (AE-10).
- [x] `docs/phasen/phase-3.md`.

**DoD ✓:** Reproduzierbarer SoD-Lauf zu Stichtag/Ruleset/Profil mit Nachweiskette.

## Phase 5 — Runner & Orchestrierung
**Ziel:** Wenige Befehle rechnen Import bzw. Auswertung (zwei Runner).

- [x] **`run/run_import.ps1`** (konvertieren → migrieren → laden → `99_validate`; container-only).
- [x] **`run/run_evaluate.ps1`** (Ruleset laden → materialize → evaluate; Profile aus `config/`).

**DoD ✓:** Frischer Lauf liefert identische Ergebnisse (gleiche Daten vorausgesetzt).

> *Zurückgestellt (optional):* Linux/macOS-`.sh`-Varianten der Runner.

## Phase 6 — Darstellung (NeoDash-PoC) · **temporär**
**Ziel:** Visuelle Inhalte (KPIs, Graph-Pfade, Tabellen) schnell festlegen.

- [x] NeoDash lokal angebunden; Dashboard-Import getestet.
- [x] **PoC-Dashboard** `dashboards/sod_poc.json` (KPI-Kacheln, Top-Regeln, Konfliktpfad-Graph, `runId`-Selektor, Scope-Konsistenz über `(:Run)`).
- [x] Dashboard als JSON committet. **Showcase-Stopp gesetzt.**

**DoD ✓ (PoC):** Dashboard reproduzierbar aus dem Repo.

> **Wichtig:** NeoDash war bewusst der **Zwischenschritt** zur App, **nicht** die finale Oberfläche.
> Die Karten-Cypher sind 1:1 wiederverwendbar; das **gebrandete NVL/React-Frontend** ersetzt NeoDash
> und steht als offener Punkt in [`ROADMAP.md`](ROADMAP.md) („Fancy Auswertungen").

---

## Phase 9 — App: erledigte Bausteine

- [x] **Backend-Service (Bau-Schritt 1).** FastAPI-Container `iam-backend` (Port 8000), orchestriert die `cypher/`-Dateien über den Neo4j-Treiber (apoc-core: Statements im Backend gesplittet). Endpunkte u. a. `GET /health|/datasets|/runs|/findings`, `POST /runs` (async Job), `GET /jobs/{id}`. Profile/Sleeping aus `config/`.
- [x] **Import-Endpunkt (Bau-Schritt 3).** Voller Import im Container (konvertieren → Schema → laden → validieren), **kein PowerShell nötig**. SE16-Konverter nach **Python portiert** (`backend/convert.py`, byte-identisch zur PS-Version verifiziert). **ZIP-Upload** (`POST /imports/upload`) und vorhandener Ordner (`POST /imports`); `GET /import-folders`. Verifiziert: voller Import in unter zwei Minuten.
- [x] **Front-end — Ribbon-UI (Bau-Schritt 4).** Statische Single-Page (`frontend/index.html`), vom Backend ausgeliefert, gegliedert nach Lebenszyklus (1 Daten · 2 Auswertung · 3 Ergebnisse · 4 Sichern · 5 Verwalten · 6 Admin); Befehle öffnen Dialoge, Ergebnisse (KPIs · Läufe · Findings) im Hauptbereich. Poliertes Banner + Status-Chips.
- [x] **Backup/Restore/Clear.** Clear je Dataset / Full-Reset (Ruleset + Schema bleiben); Backup/Restore auf **Quelldaten-Ebene** (ZIP der bereinigten `.csv`, `clear=true` = Backup & Clear, Download, Re-Import). `backups/` gitignored.
- [x] **CSV-Export** der Findings (`GET /findings/export`, Semikolon/UTF-8-BOM, Excel-tauglich).
- [x] **Admin-Bereich (Heimat).** Ribbon-Gruppe „Admin" zeigt die geladenen Rulesets. *(Editor/Konnektor-Import offen → ROADMAP.)*

## Phase X — erledigt

- [x] **Intra-/Inter-Rollen-Evidenz (AE-11) v1.** `cypher/sod/explain_sod.cypher`: pro Finding die verursachenden Rollen/Profile (`(:SoDConflict)-[:VIA_ROLE]->(:Role)` / `-[:VIA_PROFILE]->(:Profile)`) und `conflictType` **intra** vs. **inter**; Hilfsrelation `(:Role|:Profile)-[:PROVIDES]->(:Query)`. Sichtbar in `/findings`, CSV-Export und UI. **Opt-in** (teuer). *(Perf-Optimierung offen → ROADMAP.)*
