# Roadmap-Archiv — abgeschlossene Arbeit

Historischer Nachweis der **erledigten** Phasen/Bausteine. Die **offene Planung** steht in
[`ROADMAP.md`](ROADMAP.md); dort liegen auch die verbindlichen **Architektur-Entscheidungen
(AE-01…15)**, die **Vertrauensgrenze** und die Referenz (Zielarchitektur, Windows-Spezifika,
R/3-vs-S/4). Dieses Archiv beschreibt nur Logik/Vorgehen — niemals Mandantendaten.

**Erledigt:** Phasen 0–3 und 5 (Fundament, Datenmodell, Import/Can-Do, Auswertungslogik/SoD,
Runner) · Phase 6 als **PoC** (NeoDash, Showcase-Stopp) · Phase-9-Bausteine 1/3/4 (Backend-API,
Import im Container inkl. ZIP-Upload, Ribbon-UI), Backup/Restore/Clear, CSV-Export, AE-11-Evidenz v1
· Phase 7 (Konsistenzchecks) bis auf den CSV-Export · Phase 9: Org-Filter/MATCHES-Scoping,
Lauf verwalten + Backup/Restore, interaktive Drill-downs (Findings/Root-Cause/Sidebar-Filter),
Query-/SoD-Management-Seite mit Overlay-Mechanismus + Fehlerprotokoll, Assistent-Stepper für die
geführte Auswertung, Import-Robustheit (Abbrechen/Resume/parallele Konvertierung).

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

## Phase 7 — Konsistenzchecks ✓ abgeschlossen
**Ziel:** Über die SoD-Funktionstrennung hinaus die strukturelle Qualität und allgemeinen Risiken
des geladenen Berechtigungskonzepts selbst sichtbar machen. Katalog in [`KONSISTENZCHECKS.md`](KONSISTENZCHECKS.md).

- [x] **Export (letzter offener Punkt): Konsistenz-Report (CSV).** Neuer Menüpunkt
  „Bericht herunterladen" (Gruppe 4, Konsistenzchecks-Dropdown). Neuer Backend-Endpoint
  `GET /consistency-checks/export?dataset=…` führt alle implementierten Checks mit ihren
  Default-Params durch, zählt die Detailzeilen (= was die UI als „N Treffer" zeigt) und gibt
  eine Überblick-CSV aus (Semikolon/UTF-8-BOM): Spalten `Dataset · Stichtag · Bereich ·
  Check-ID · Kategorie · Titel · Priorität · Status · Treffer · Params`. Nicht implementierte
  Checks erscheinen als Zeile ohne Treffer. Dialog mit Dataset-Auswahl (vorbelegt aus aktivem
  Lauf/Check-Kontext) und Spinner während der Laufzeit; Dateiname
  `konsistenz_<dataset>_<asOf>.csv`. Später Basis für den Gesamt-Report (zusammen mit
  Import-Evidenz) und PDF-Variante.

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
  Server-Zustand, geht beim Neuladen verloren.
- [x] **Graph-Pilot für A1–A3 — erledigt, mit Lizenz-Kurswechsel weg von NVL.** Geprüft, ob
  **Neo4j Visualization Library (NVL)** für den ersten echten Graph-Einsatz genutzt werden kann —
  **verworfen**: NVLs Lizenz erlaubt den Einsatz nur mit Neo4j Aura (Cloud) oder einer
  kommerziellen Neo4j-Subscription, nicht mit der hier eingesetzten **Community Edition**; Aura
  wäre zudem ein Bruch der Vertrauensgrenze (Daten verlassen die lokale Umgebung). Stattdessen
  **Cytoscape.js** (MIT-Lizenz, keine Laufzeit-Abhängigkeiten, keine Telemetrie/Netzwerkaufrufe —
  geprüft im gebauten Bundle) lokal vendored unter `frontend/vendor/cytoscape/` (kein CDN, App
  bleibt offline lauffähig). Neues Schema-Feld `graphFile` (`checks/SCHEMA.md`, analog
  `rootCauseFile`) für Checks mit User→(Rolle→)Profil-Pfad; neuer Endpoint
  `POST /consistency-checks/{id}/graph` wandelt die Cypher-Zeilen generisch in
  Cytoscape-Knoten/Kanten um. Für **A1 (SAP_ALL)**, **A2 (SAP_NEW)**, **A3 (kritische
  Standardprofile)** umgesetzt (`*_graph.cypher`); der „Graph"-Pill in der
  Konsistenzcheck-Ergebnisansicht ist für diese drei scharf (sonst weiterhin deaktiviert →
  `ROADMAP.md`, „Umschalter Tabelle/Graph"). Verifiziert per Playwright-Smoketest gegen einen
  laufenden Container: Knoten/Kanten rendern (User blau, Profile grün), Umschalten
  Tabelle↔Graph funktioniert, keine Konsolenfehler.
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
- [x] **Ribbon-Layout: Gruppen mit mehreren Befehlen als Menü — erledigt.** Gruppen mit mehr als
  einem Befehl („Ergebnisse", „Admin", „Konsistenzchecks") klappen als **aufklappbares Menü** auf
  (Klick öffnet, Klick daneben/auf einen Befehl schließt) statt alle Befehle nebeneinander zu
  zeigen. Gruppen mit nur einem Befehl bleiben ein direkter Button. Ribbon-Gruppen durchnummeriert
  (1 Daten · 2 Auswertung · 3 Ergebnisse · 4 Konsistenzchecks · 5 Sichern · 6 Verwalten · 7 Admin).

## Phase 9 — App: erledigte Bausteine

- [x] **Backend-Service (Bau-Schritt 1).** FastAPI-Container `iam-backend` (Port 8000), orchestriert die `cypher/`-Dateien über den Neo4j-Treiber (apoc-core: Statements im Backend gesplittet). Endpunkte u. a. `GET /health|/datasets|/runs|/findings`, `POST /runs` (async Job), `GET /jobs/{id}`. Profile/Sleeping aus `config/`.
- [x] **Import-Endpunkt (Bau-Schritt 3).** Voller Import im Container (konvertieren → Schema → laden → validieren), **kein PowerShell nötig**. SE16-Konverter nach **Python portiert** (`backend/convert.py`, byte-identisch zur PS-Version verifiziert). **ZIP-Upload** (`POST /imports/upload`) und vorhandener Ordner (`POST /imports`); `GET /import-folders`. Verifiziert: voller Import in unter zwei Minuten.
- [x] **Front-end — Ribbon-UI (Bau-Schritt 4).** Statische Single-Page (`frontend/index.html`), vom Backend ausgeliefert, gegliedert nach Lebenszyklus (1 Daten · 2 Auswertung · 3 Ergebnisse · 4 Sichern · 5 Verwalten · 6 Admin); Befehle öffnen Dialoge, Ergebnisse (KPIs · Läufe · Findings) im Hauptbereich. Poliertes Banner + Status-Chips.
- [x] **Backup/Restore/Clear.** Clear je Dataset / Full-Reset (Ruleset + Schema bleiben); Backup/Restore auf **Quelldaten-Ebene** (ZIP der bereinigten `.csv`, `clear=true` = Backup & Clear, Download, Re-Import). `backups/` gitignored.
- [x] **CSV-Export** der Findings (`GET /findings/export`, Semikolon/UTF-8-BOM, Excel-tauglich).
- [x] **Admin-Bereich (Heimat).** Ribbon-Gruppe „Admin" zeigt die geladenen Rulesets. *(Editor/Konnektor-Import offen → ROADMAP.)*

## Phase 9 — App: weitere erledigte Bausteine (Auswertung v2 / Drill-down / Admin)

#### Geführte Auswertung
- [x] **Org-Filter im App-Lauf wirksam machen.** `materialize_matches.cypher` wertet `$orgMode`
  (`ignoreOrg`/`wildcardOnly`/`filtered`) + `$orgFilters` aus (Logik aus `query_match` + Modus
  `wildcardOnly` ergänzt; AGR_1252-Auflösung genutzt). **Allgemein über ALLE Org-Ebenen** (BUKRS,
  WERKS, EKORG, VKORG, GSBER, … — aus USORG) **und Kombinationen** (`orgFilters` = Map je Feld,
  z. B. `{BUKRS:…, EKORG:…}` = „Buchungskreis **und** Einkaufsorg"). Org-Modus + Filter werden
  auf `(:Run)` protokolliert (`run.orgMode`/`run.orgFilters`). Verifiziert: standard ≠
  übergreifend (`wildcardOnly` schränkt ein). *Hinweis: USORG = Org-Feld-Registry (welche Felder
  Org-Ebenen sind); die bindenden Werte stehen in den Auths (AGR_1251/UST12/AGR_1252) — **nicht**
  in USOBT_C/USOBX_C (das ist die SU24-Vorschlags-/Prüfschicht, → `CHECKS`).*
- [x] **MATCHES nach runId scopen.** Das Zwischenergebnis `(:User)-[:MATCHES]->(:Query)` war nur
  nach `ruleset+dataset` gescoped: ein zweiter Org-Varianten-Lauf hat beim Materialisieren
  (`materialize_matches.cypher`) die MATCHES eines vorherigen Laufs stillschweigend
  gelöscht/überschrieben (DELETE und MERGE-Schlüssel ohne `runId`) — Findings/Root-Cause des
  ersten Laufs wurden dadurch nachträglich falsch. Jetzt trägt sowohl der DELETE- als auch der
  MERGE-Schlüssel `runId` (`materialize_matches.cypher`); `evaluate_sod.cypher` und
  `explain_sod.cypher` (VIA_ROLE/VIA_PROFILE-Herleitung) lesen MATCHES ebenfalls
  `runId`-gescoped — `PROVIDES` bleibt bewusst lauf-übergreifend (Fakt über Akteur+Auths, nicht
  über den Match). `delete_run.cypher` löscht jetzt zusätzlich die MATCHES-Kanten des gelöschten
  Laufs (sonst Karteileichen bei vielen Varianten). Verifiziert gegen den laufenden Container:
  zwei Org-Varianten desselben Rulesets/Datasets nacheinander angelegt (`standard` vs.
  `uebergreifend`) — unterschiedliche, stabile Treffermengen je `runId`, der erste Lauf bleibt
  nach Anlage des zweiten unverändert; Löschen eines Laufs entfernt nur dessen eigene MATCHES,
  der andere bleibt intakt. War die technische Vorbedingung für „Multi-Varianten-Läufe" (offen →
  `ROADMAP.md`).
- [x] **Lauf verwalten.** `POST /runs/{runId}/delete` löscht einen einzelnen Lauf (`(:Run)` +
  dessen `SoDConflict`-Findings inkl. Evidenz-Kanten und — seit „MATCHES nach runId scopen" —
  dessen eigene MATCHES-Kanten) — UI: eigener Lauf-Select im „Bereinigen"-Dialog. Zusätzlich
  **Lauf-Backup/-Restore** als eigener Bereich im „Sichern"-Dialog (getrennt von den
  Quelldaten-Backups): `POST /runs/{runId}/backup` sichert Run+Findings (ohne Evidenz — die ist
  teuer und über „Evidenz" jederzeit neu berechenbar) als ZIP (`manifest.json`/`run.json`/
  `findings.json`); `GET /runs/backups` (Liste) + `.../download` + `POST
  /runs/backups/{file}/restore`. Dafür neu: **`Dataset.uid`** (randomUUID, einmalig bei
  Erst-Anlage in `load/00_dataset.cypher`, lazy Backfill für ältere Datasets) — bleibt über
  Re-Importe desselben Datasets stabil, ändert sich nur bei Löschen+Neuanlage unter demselben
  Namen. Jeder Lauf trägt seine `datasetUid` (`evaluate_sod.cypher`); Restore vergleicht sie
  gegen die aktuelle Dataset-uid und verlangt bei Abweichung eine explizite Bestätigung
  (`force=true`), bevor er wiederherstellt. Restore selbst matcht User/Regel nur per `MATCH`
  (nie `MERGE`) — Findings, deren Bezug im aktuellen Dataset nicht mehr existiert, werden
  übersprungen statt Phantom-Knoten anzulegen (AE-10).
- [x] **Assistent — Geführte Auswertung als Stepper.** Neuer Ribbon-Befehl „Assistent" (`frontend/index.html`)
  führt in 7 Schritten durch den kompletten Zyklus: **① Import → ② Bestand → ③ Scoping → ④ Konsistenz
  → ⑤ SoD → ⑥ Root-Cause → ⑦ Bericht** (Stepper-Leiste, bereits besuchte/erreichbare Schritte klickbar,
  `asst`-State hält aktiven Schritt + gewähltes Dataset). Schritte ①/②/⑦ sind eigene, neue Inline-Views
  (Dataset-Übersicht mit Backup/Löschen, Dataset-/Stichtag-Auswahl, Bericht-Download CSV/PDF mit den
  PDF-Deckblattfeldern); Schritte ④–⑥ binden die **bestehenden** Konsistenz-/Ergebnis-/Root-Cause-Seiten
  ein (kein Duplikat, „zurück" springt jeweils einen Schritt zurück statt in die normale Navigation).
  **Schritt ③ Scoping ist bewusst nur ein Platzhalter** („wird in kommender Phase implementiert") —
  das ist exakt die noch offene Katalog-Auswahl-UI (→ ROADMAP.md).
- [x] **Import-Robustheit.** Reaktion auf reale Abbrüche bei großen Importen (Speicherlimit,
  Verbindungsabbruch mitten im Ladevorgang): **Abbrechen** (`POST /jobs/{id}/cancel` setzt ein Flag,
  der Import-Thread prüft es zwischen den Lade-Schritten via `_check_cancel()` und stoppt sauber,
  Job-Status `cancelled`); **Resume** über eine Checkpoint-Datei (`data/<dataset>/_import_state.json`,
  Liste der bereits abgeschlossenen `load/*.cypher`-Schritte) — ein Re-Import mit `resume=true`
  überspringt sie und macht ab dem letzten Stand weiter (UI: Resume-Banner im Import-Dialog mit
  „Weitermachen"/„Von vorne"); State wird bei Erfolg und bei „vorher leeren" (`clearFirst`) gelöscht,
  bleibt nach Abbruch/Fehler erhalten. **Fehlende optionale Quelltabelle bricht den Import nicht mehr
  ab** (`NoSuchFileException` beim Laden → Schritt überspringen statt Abbruch; direkt gegen einen
  realen Fall verifiziert, bei dem eine optionale Tabelle im Export fehlte). **Parallele CSV-Konvertierung**
  (`backend/convert.py`, `ThreadPoolExecutor`, 6 Worker — I/O-bound bei üblicherweise 15–25 Tabellen)
  plus Skip bereits aktueller `.csv` (mtime-Vergleich) und `errors="replace"` statt Abbruch bei
  einzelnen kaputten Bytes in der `cp1252`-Quelle. **Fortschrittsanzeige** im Import-Dialog (Schritt
  X/Y, zuletzt geschriebene Knoten/Kanten, Konvertierungsstand). **Quelldateien löschen**
  (`DELETE /datasets/{d}/import-files`) räumt `.txt`/`.csv` im Import-Ordner nach erfolgtem Backup
  auf (Re-Import bleibt über das Backup-ZIP möglich) — UI im Sichern-Dialog mit Größenanzeige und
  Sicherheitsabfrage. Neo4j-Speicher in `docker-compose.yml` nachgezogen (Heap 4G→8G, `dbms.memory
  .transaction.total.max=0`) — Ursache war ein `MemoryPoolOutOfMemoryError` bei einem großen
  Batch-Import (`AGR_1251`).

#### Interaktive Ergebnisse (Drill-down) + Graph/Tabelle
- [x] **Klickbare Drill-downs.** `GET /findings` nimmt optional `user`/`rule`/`userType`
  (Mehrfachauswahl)/`sleeping`/`ruleCriticality` an (User-/Regel-Zelle in der Findings-Tabelle
  ist klickbar); `GET /matches?runId&query&user&userType` + `GET /queries?runId`
  (Query-Auswahl der SoD-relevanten Queries des Laufs) liefern „wer matcht Query X" über das
  `MATCHES`-Zwischenergebnis. `GET /findings/summary` liefert die KPI-Aggregate (Findings/
  betroffene Regeln/sleeping) für denselben Filterkontext — unabhängig vom 500er-Limit der
  Liste. UI: **Sidebar links jetzt schlank** — nur noch Nutzertyp, User, Einzelberechtigung, SoD.
  Nutzertyp als **Ankreuz-Dropdown** (Checkbox-Panel statt nativem `<select multiple>`, Button
  zeigt gewählte Typen, Labels mit SAP-Code-Präfix „A – Dialog", „B – System", „S – Service",
  „C – Communication", „L – Reference"). *Layout-Bug behoben:* die globale Regel
  `input, select { width:100% }` hatte auch die Checkboxen im Panel auf volle Zeilenbreite
  gestreckt, was im Zusammenspiel mit dem ursprünglichen Flex-Layout zum schiefen/überlaufenden
  Rendering führte (Text lief in die Tabelle); Panel jetzt auf einfaches Block-Layout (kein
  Flex) umgestellt, Checkbox-Breite explizit `auto`. Kritikalität (SoD) und Sleeping sind aus
  der Sidebar raus und sitzen jetzt **als farbige Pill-Buttons über der Ergebnistabelle** (eigene
  `.resultbar`-Zeile, immer sichtbar, klickbar statt Dropdown — Kritikalität-Pills nutzen
  dieselben `.tag.*`-Farben wie die Tabelle, aktive Pille hervorgehoben per Ring/Opazität);
  Klick wendet sofort an. Die bisherige „Kritikalität (Einzelberechtigung)"-Eingrenzung wurde
  ersatzlos entfernt (Einzelberechtigung-Liste zeigt jetzt immer alle Queries). Klick auf eine
  User-/Regel-Zelle setzt den passenden Filter weiterhin direkt (setzt dabei die
  SoD-Kritikalität-Pille zurück, falls sie die Zielregel sonst ausblenden würde); aktiver Filter
  als Chip über der Tabelle mit „zurücksetzen". **KPI-Kacheln folgen dem aktiven Filterkontext**
  (`refreshKpis()` ruft `/findings/summary` mit allen aktuell gesetzten Filtern). Einheitlicher
  5-stufiger Kritikalitäts-Farbverlauf (sehr-hoch=tiefrot … niedrig=grün) in Findings-Tabelle und
  Kritikalitäts-Pills (`CRIT_COLOR`). **Lauf-Karten reduziert** auf Bezeichnung (Titel/Run-ID),
  **Filterset-Name** (Ruleset, aus `metaCache.rulesets`), Stichtag und Erstellungs-Datum/-Zeit
  (`run.generatedAt`). **Hell/Dunkel-Umschalter** ganz oben im Header (`#themeToggle`,
  persistiert in `localStorage`), CSS-Variablen (`--bg`/`--panel`/`--line`/`--fg`/`--muted`/
  `--accent`) per `html[data-theme="light"]` überschrieben, inkl. angepasster
  Kritikalitäts-Tag-Farben für besseren Kontrast auf hellem Hintergrund.
- [x] **Root-Cause-Drill-down unter die Evidenz.** Neuer Endpoint `GET /root-cause?runId&user&query`
  (`backend/app.py`): pro Berechtigungsobjekt der Query (+ TCode-Prüfung als eigener
  Pseudo-Block, falls `disregardTcode=false`) wird gezeigt, **welche Rolle(n)/Profil(e) mit
  welcher konkreten `Authorization` (Objekt/Feld/Werte)** die Anforderung (`AuthReq`) erfüllen —
  nicht mehr nur „welche Rolle" wie `VIA_ROLE`/`VIA_PROFILE` (AE-11), sondern der tatsächliche
  Root-Cause-Datensatz; macht sichtbar, wenn verschiedene Objekte durch verschiedene Rollen
  gedeckt werden (AE-03/AE-09). Logik (`_SATISFIED_BY_CYPHER`) ist dieselbe Treffer-Prüfung wie
  in `explain_sod.cypher`/Schritt 1 (`PROVIDES`), nur pro Objekt statt pro ganzer Query, und pro
  Rolle/Profil statt nur „irgendein Akteur". *Stolperstein:* Cypher-String-Slicing `k[2..]` auf
  einer Map-Comprehension-Variable löste einen `CypherSyntaxError` aus („Type mismatch: expected
  List<T> but was String") — `substring(k,2)` statt `k[2..]` behoben. UI: in der Matches-Tabelle
  „wer matcht" (Einzelfilter-Kontext) hat jede Zeile einen **„Root-Cause"-Button**, öffnet einen
  Dialog mit den Objekt-Blöcken (Anforderung oben, erfüllende Rolle/Profil + Werte darunter).
- [x] **Nutzerzentrische Auswahl: KPI-Kontext-Chips + Ergebnistyp-Pills.** Wählt man einen User
  (und optional zusätzlich eine Regel über Klick auf die Regel-Zelle, ohne den User-Filter zu
  verwerfen — Drill-down ist additiv statt exklusiv), erscheinen **Kontext-Chips „Nutzer: X" /
  „Regel: Y"** oben bei den KPI-Kacheln (`#resultContext`) + ein **Tabelle/Graph-Umschalter**
  (Graph vorerst deaktiviert, „kommt später" — echter Graph hängt am Cytoscape.js-Punkt, Technik
  bereits am Konsistenzcheck-Graph-Pilot A1–A3 erprobt). Bei User **und** Regel zusammen (= genau
  1 Finding) erscheint ein **„Verursachende Rollen/Profile"-Panel** (`#causingActors`, aus
  `f.roles`/`f.profiles`) — ersetzt die alte Tabellenspalte „Verursacht durch", die aus der
  Findings-Tabelle entfernt wurde; stattdessen zeigt die Tabelle jetzt **„Bezeichnung"** neben
  der Regel-Spalte (`sodRuleNames[f.rule]`). Die **Sleeping-Pillzeile wurde ersetzt** durch
  **Ergebnistyp (alle/Einzelfilter/SoD)**: „Einzelfilter" zeigt die Matches-Tabelle („wer
  matcht") auch **ohne** vorher eine konkrete Query in der Sidebar zu wählen (alle Queries des
  Users); „alle"/„SoD" zeigen unverändert die Findings-Tabelle. *Bekannte Einschränkung:*
  Sleeping ist dadurch nicht mehr über die UI filterbar (Backend-Parameter `sleeping` existiert
  weiterhin, nur kein Pill/Control mehr dafür).
- [x] **Root-Cause auch für SoD-Regeln.** `GET /root-cause` nimmt alternativ `rule` statt `query`
  an: pro Klausel der Regel wird die vom User tatsächlich gematchte Query
  (`(:User)-[:MATCHES]->(:Query)`, auf Klausel-Kandidaten
  `(:SoDRule)-[:HAS_CLAUSE]->(:Clause)-[:NEEDS]->(:Query)` eingeschränkt) genauso aufgeschlüsselt
  wie im Einzelfilter-Fall — Antwortformat einheitlich auf `blocks[]` (Label + Objekte)
  umgestellt. UI: „Root-Cause"-Button im „Verursachende Rollen/Profile"-Panel (Nutzer+Regel-Kontext).
- [x] **SoD-Kurzbezeichnung nachgezogen.** Die Query-Kurzbezeichnungs-Bereinigung hatte
  `SoDRule.shortDescription` nicht mitgenommen. Da SoD-Regeln **keinen Overlay-Mechanismus** wie
  Queries haben (`sod_rules.json` ist die einzige Quelle, kein `*.custom.json`), wurde die
  Bereinigung direkt in die drei `sod_rules.json` geschrieben (reine Datenänderung, keine
  Logikänderung) — nur wo die Beschreibung auf einen abtrennbaren Code-/Query-Klammerausdruck
  endet, nicht bei booleschen Teilausdrücken wie „(A) AND (B)" (KPMG_R3: 21/22 Treffer;
  CSI/CSI_BI: 0, da deren Beschreibungen keine solchen Klammern haben).
- [x] **Kaskadierende Sidebar-Filter.** Bei gewähltem User schränken sich Einzelberechtigung-
  (`updateQueryCascade()`, über `/matches?user=` ohne `query`) **und** SoD-Dropdown
  (`renderRuleSelect()`, aus dem schon geladenen `allFindingsForRun`) auf das für ihn
  tatsächlich Gefundene ein — sowohl beim Ändern des User-Dropdowns als auch beim
  Filtern/Tabellenzellen-Klick. Außerdem: neuer Endpoint `GET /users/{id}?runId=` (Name/Typ/
  Status); der Kontext-Chip „Nutzer: …" zeigt jetzt **UserID · Name · Typ · Status** statt nur
  der ID. Sleeping-Pillzeile ist jetzt **nur bei Ergebnistyp „alle" sichtbar** (bei
  „Einzelfilter"/„SoD" ausgeblendet + zurückgesetzt).

#### Admin-Bereich
- [x] **Einzelfilter-Editor (Query-Metadaten).** „Einzelfilter nachjustieren
  (Ruleset-Editor)" im Admin-Dialog scharfgeschaltet: bearbeitet **Bezeichnung/Kritikalität/
  Modul/Query-Typ/disregardTcode** bestehender Queries und kann neue Queries **aus einer
  bestehenden ableiten** (authorizations/transactions 1:1 übernommen, nicht editierbar in v1).
  Persistenz **Round-Trip auf die JSON**, aber **vendor-getrennt**: Edits/Ableitungen landen in
  einem Overlay `rules/<Ruleset>/queries.custom.json`, die Vendor-Datei (`queries.json`) bleibt
  unberührt — `load_ruleset.cypher` liest beide Dateien (Vendor zuerst, Overlay danach,
  `coalesce()`-Merge: im Overlay nicht gesetzte Felder bleiben unverändert), Speichern/Ableiten
  löst sofort einen Reload aus (`POST /admin/rulesets/{ruleset}/queries/...`). Voraussetzung:
  Backend-Mount für `rules/` von `:ro` auf **rw** (nur Backend-Container; der neo4j-Mount bleibt
  `:ro`). Dabei nebenbei: **Bezeichnung statt nur ID** in den Sidebar-Filtern
  „Einzelberechtigung" (`Query.description`, bisher nicht geladen → Loader ergänzt) und „SoD"
  (neuer `GET /sodrules?runId=` liefert `SoDRule.description`, war im Graph schon vorhanden).
- [x] **Kurz-/Langbezeichnung vorbereitet.** Neues optionales Feld `shortDescription`
  (Kurzbezeichnung) neben `description` (Langbezeichnung) für `Query` **und** `SoDRule`
  (`rules/SCHEMA.md`, `load_ruleset.cypher`, `/queries`, `/sodrules`, Editor-Formular).
  Sidebar-Filter „Einzelberechtigung"/„SoD" zeigen jetzt `shortDescription || description || id`
  — solange keine Kurzbezeichnungen gepflegt sind, bleibt es bei der (oft langen)
  Langbezeichnung. *Bekannte Einschränkung:* ein Feld, das ausschließlich im Overlay existiert
  (kein Vendor-Gegenstück), lässt sich über den Editor aktuell nicht auf „leer" zurücksetzen
  (Reload kann ein rein-Overlay-Feld nicht durch `coalesce()` löschen) — für v1 hingenommen, bei
  Bedarf später ein explizites „löschen"-Token einführen.
- [x] **Kurzbezeichnungen vorbereinigt.** Einmaliges Skript (nicht Teil der App) hat für alle
  drei Rulesets `shortDescription` = Langbezeichnung **ohne den abschließenden
  Klammer-Ausdruck** (i. d. R. die Transaktionscodes, z. B. „BC-SEC - Replace in Debugging (/h)"
  → „BC-SEC - Replace in Debugging") ins Overlay (`queries.custom.json`) geschrieben — nur wo
  sich dadurch tatsächlich etwas ändert (KPMG_R3: 600/604, CSI: 150/733, CSI_BI: 152/735 —
  CSI-Bezeichnungen sind meist schon kurz/ohne Klammern, daher seltener Treffer). Vendor-Datei
  unberührt; jederzeit im Query Management nachschärfbar.
- [x] **Query Management als eigene Seite.** Statt Modal-Dialog: eigene Seite
  `frontend/admin.html` mit eigener Ribbon-Bar (**Anzeige** = Aktualisieren · **Editieren** =
  Speichern/Abbrechen, aktiv erst bei Änderung · **Backup** = Overlay-Datei herunterladen,
  `GET /admin/rulesets/{ruleset}/overlay/download` · **Zurück** = Link zur Auswertung). Layout:
  links Filterset-Auswahl (von 3 Rulesets) + durchsuchbare Query-Liste, rechts Detail mit
  **vier Tabs** — **Stammdaten** (bisherige Metadatenfelder), **Aufbau** (TCodes +
  Berechtigungsobjekte, reine Anzeige, neuer Detail-Endpoint
  `GET /admin/rulesets/{ruleset}/queries/{queryId}` liefert die vollständige gemergte Query
  inkl. `authorizations[]`/`transactions[]`), **Risiko** und **Controls** (je ein Freitext-Feld,
  neue optionale Query-Felder `risk`/`controls`). Admin-Dialog in der Haupt-App verlinkt jetzt
  nur noch dorthin (`<a href="/admin.html">`); der alte Editor-Modal-Dialog wurde entfernt.
  „Ableiten" (neue Query aus bestehender) ist mit auf die neue Seite gewandert. **Stammdaten
  stehen dauerhaft sichtbar** (eigener umrahmter Block) **über** den Tabs (nur noch
  Aufbau/Risiko/Controls als Tabs); Tab-Leiste optisch deutlicher (aktiver Tab hervorgehoben
  statt nur Unterstrich). **Suche** unterstützt `*` als Platzhalter (z. B. `BC-SEC*`);
  zusätzliche Filter nach **Modul/Kritikalität/Query-Typ** (aus den geladenen Queries
  abgeleitete Dropdowns).
- [x] **Admin-Ribbon entschlackt + Fehlerprotokoll.** Der alte Admin-Dialog (Rulesets-Übersicht
  + Link) ist weg: die Ribbon-Gruppe „Admin" hat jetzt zwei direkte Punkte — **„Query
  Management"** (Link direkt auf `/admin.html`, kein Zwischendialog mehr) und
  **„Fehlerprotokoll"** (neuer Dialog, listet fehlgeschlagene Jobs). Neu **persistent über
  Container-Neustarts hinweg**: `backend/app.py` schreibt bei jedem Job-Fehler
  (Import/Lauf/Backup/Restore/Bereinigen/Reset/Explain) zusätzlich zum `jobs`-Dict eine Zeile
  (`{ts, jobId, kind, request, message}`) nach `data/logs/job_errors.jsonl`
  (`_log_job_error()`); neuer Mount `./data/logs:/app/data/logs` im Backend-Service. `GET
  /admin/job-errors?limit=` liefert die Einträge neueste zuerst. Zusätzlich: **Kopfzeile zeigt
  jetzt das aktiv angewendete Ruleset** als eigenen Chip (`#chipRuleset`, zwischen
  Hell/Dunkel-Umschalter und „verbunden"), gefüllt aus dem Ruleset des gerade angezeigten Laufs
  (`showFindings()`).
- [x] **SoD-Pflegeseite analog zu Queries.** Query Management hat einen **Modus-Umschalter
  „Einzelfilter"/„SoD"** (`#modePills`), der Liste/Filter/Detailbereich umschaltet, ohne die
  Auswahl im jeweils anderen Modus zu verwerfen. SoD-Detail: **Stammdaten** dauerhaft sichtbar
  (Kurz-/Langbezeichnung, Kritikalität, Reason-Code, read-only) + drei **Tabs** — **Aufbau**
  (CNF-Klauseln, je Klausel die enthaltenen Queries mit Bezeichnung — nutzt die schon geladene
  Query-Liste, kein Extra-Request; Fallback auf `expression`+`variables`-Tabelle, solange ein
  Ruleset noch keine `clauses` hat, s. Phase-X-Backlog „CSI-Rulesets CNF-zerlegen"), **Risiko**,
  **Controls** (Freitext, neue optionale SoDRule-Felder `risk`/`controls`, analog zu Query).
  Backend: SoD-Regeln haben jetzt ebenfalls einen **Overlay-Mechanismus**
  (`sod_rules.custom.json`, vorher nicht vorhanden — die einmalige Kurzbezeichnungs-Bereinigung
  hatte deshalb direkt in die Vendor-Datei geschrieben) — `load_ruleset.cypher` liest
  Vendor+Overlay zweistufig wie bei Queries (`coalesce()`-Merge); neue Endpoints
  `GET /admin/rulesets/{ruleset}/sodrules`, `GET .../sodrules/{ruleId}`,
  `PUT .../sodrules/{ruleId}`, `GET .../sodrules/overlay/download`. **Kein „Ableiten"** für SoD
  in v1 — nur Metadaten-Edits an bestehenden Regeln.

## Phase X — erledigt

- [x] **Intra-/Inter-Rollen-Evidenz (AE-11) v1.** `cypher/sod/explain_sod.cypher`: pro Finding die verursachenden Rollen/Profile (`(:SoDConflict)-[:VIA_ROLE]->(:Role)` / `-[:VIA_PROFILE]->(:Profile)`) und `conflictType` **intra** vs. **inter**; Hilfsrelation `(:Role|:Profile)-[:PROVIDES]->(:Query)`. Sichtbar in `/findings`, CSV-Export und UI. **Opt-in** (teuer). *(Perf-Optimierung offen → ROADMAP.)*
