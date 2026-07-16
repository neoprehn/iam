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
geführte Auswertung, Import-Robustheit (Abbrechen/Resume/parallele Konvertierung), Lauf-Fortschritt
+ Resume (materialize/evaluate/explain, inkl. Batch-Varianten).

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
  **Nachträglicher Korrekturbedarf (Nutzer-Feedback):** `f.userSleeping = (u.lastLogon IS NULL OR
  u.lastLogon < asOf - sleepDays)` behandelte „kein bekannter Logon" und „bestätigt sleeping"
  gleich — bereits bei der zweiten Konsistenzcheck-Feedback-Runde als Datenlage vermerkt (B6,
  s. u., ~47 % `NULL` im Testdatenbestand), aber nicht als eigener Zustand ausgewiesen. Bricht
  vollständig zusammen, sobald `TRDAT` (laut Extraktionsleitfaden ein optionales USR02-Feld) in
  einer Extraktion **gar nicht** mitgeliefert wird: dann ist `lastLogon` für 100 % der User
  `NULL`, und **jeder** Fund erscheint als „sleeping" — verifiziert gegen einen realen
  Produktivfall (26.949 von 26.949 Usern ohne `lastLogon`). Korrigiert: neues Flag
  `f.lastLogonKnown = (u.lastLogon IS NOT NULL)`; `f.userSleeping` ist jetzt nur noch **true**,
  wenn der Logon bekannt **und** älter als die Schwelle ist. `GET /findings`+`/findings/summary`
  (`sleeping`-Parameter jetzt `'true'|'false'|'unknown'` statt bool; `false` verlangt zusätzlich
  bekannten Logon, sonst würden „unbekannt" fälschlich unter „nicht sleeping" mitgezählt),
  CSV-Export und Lauf-Backup/-Restore (`cypher/admin/restore_run.cypher`, Default
  `lastLogonKnown=true` für Backups von vor dieser Unterscheidung) ziehen das Flag nach. UI:
  vierter Sleeping-Pill „unbekannt", Findings-Tabelle zeigt eigenen `unbekannt`-Tag statt
  fälschlich `–` oder `sleeping`. **Bewusst nicht angefasst:** die Consistency-Check-Familie
  `sleeping_users*.cypher`/`dormant_active_dialog_users.cypher` hat denselben
  „nie angemeldet zählt als sleeping"-Wortlaut — dort ist das die *beabsichtigte* Definition
  eines eigenen Checks („Dormant-User finden"), nicht Nebenprodukt einer SoD-Auswertung; bei
  vollständig fehlendem `TRDAT` verzerrt das denselben Check aber genauso und sollte bei
  Gelegenheit dieselbe Unterscheidung bekommen.
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
  **Nachträglicher Korrekturbedarf:** beim Verifizieren des Sleeping-Fixes (s. Phase 3) fiel auf,
  dass der „Abbrechen"-Button im Neuer-Lauf-Dialog (`runCancelBtn`, ruft denselben
  `POST /jobs/{id}/cancel` auf) bei SoD-Läufen **wirkungslos** war — `_check_cancel()` wurde nur
  in `do_import` aufgerufen, nie in `_run_one` (gemeinsamer Kern von `do_run`/`do_run_batch`).
  Ein Abbruch setzte zwar `cancelRequested`, der Lauf lief aber unbeeinflusst zu Ende (in einem
  Testlauf über das gesamte Dataset ohne Scoping >20 Minuten unbemerkt weiter). Korrigiert:
  `_check_cancel()` jetzt vor jeder Phase (ruleset/materialize/evaluate/explain) plus
  `except InterruptedError` in `do_run`/`do_run_batch` (Status `cancelled`, Frontend hatte diesen
  Status bereits erwartet). **Bewusste Grenze (durch den nächsten Punkt aufgehoben):** eine
  einzelne Phase (v. a. `materialize`, meist die teuerste) war selbst nicht unterbrechbar — sie
  lief als ein `apoc.periodic.iterate`-Aufruf am Stück; Abbruch wirkte erst, sobald diese Phase
  durchgelaufen war.
- [x] **Lauf-Fortschritt + Resume (materialize/evaluate/explain, inkl. Batch) — Nutzer-Feedback.**
  Direkte Folge des vorigen Punkts: ein ungescopter Lauf über alle Filter dauert auf echten
  Produktivdaten >20 Minuten (real gemessen: 38 SoD-relevante Queries × 27.000 User, ~30 s je
  Query) und zeigte bis hierhin nur den Phasennamen, keinen Fortschritt darin — bei Abbruch (Reload
  durch `--reload`, Netzwerkfehler, Cancel) war die ganze Phase verloren. Alle drei teuren Phasen
  laufen jetzt als **Reset (einmalig, nur bei frischem Phasenstart) → Kandidaten ermitteln → pro
  Einheit** statt als ein einziger Aufruf — dieselbe Grundidee wie beim Import-Loader, nur auf
  Query- (materialize) / Regel- (evaluate) / Akteur-Ebene (explain-PROVIDES). Dafür `cypher/sod/
  materialize_matches.cypher`, `evaluate_sod.cypher`, `explain_sod.cypher` in je drei Dateien
  aufgeteilt (`..._reset`/`..._init`, `..._candidates`, `..._one`, bei explain zusätzlich
  `..._finalize` für den bereits schnellen Abschluss) — fachliche Logik 1:1 übernommen, nur die
  Iterationssteuerung wandert von `apoc.periodic.iterate` (Neo4j-intern) zu einer Python-Schleife
  (`_run_phase()`/`_run_candidates()` in `backend/app.py`). Checkpoint pro Dataset
  (`data/<dataset>/_run_state.json`, analog zum Import) nach **jeder** Einheit geschrieben —
  Absturz verliert höchstens eine Einheit; bleibt nach Abbruch/Fehler erhalten, wird nur bei
  vollständigem Erfolg gelöscht. Resume (`resume:true` an `POST /runs`/`/runs/batch`) übernimmt
  alle fachlichen Parameter **aus dem Checkpoint**, nicht erneut vom Client — verhindert
  inkonsistente Ergebnisse, falls der Nutzer Formularwerte zwischenzeitlich geändert hat; einzig
  `dataset` (und optional `runId`) kommen vom Client. **Batch-Läufe** resumen exakt die Variante,
  bei der abgebrochen wurde (`variantIndex`/`completedResults` im Checkpoint), bereits fertige
  Varianten werden nicht neu gerechnet. UI: Resume-Banner im Neuer-Lauf-Dialog
  („Weitermachen"/„Verwerfen" — Verwerfen löscht den abgebrochenen Lauf über den bestehenden
  `POST /runs/{runId}/delete`-Mechanismus + den Checkpoint); Fortschrittsanzeige zeigt jetzt
  „(Query 5/38)"/„(Regel 7/22)"/„(Akteur 320/4219)" zusätzlich zum Phasennamen (bzw. zur
  Batch-Variante). Der Ribbon-Button „Evidenz nachrechnen" (`do_explain`) nutzt denselben
  `_explain_one()`-Kern — eigene, nach `runId` benannte Checkpoint-Datei (nicht die dataset-weite
  `_run_state.json`), damit ein parallel laufender „echter" Lauf sie nicht überschreibt; ein
  abgebrochener Aufruf wird beim nächsten Klick automatisch fortgesetzt (kein Formular nötig).
  Host-Runner `run/run_evaluate.ps1` auf dieselben, jetzt aufgeteilten `.cypher`-Dateien
  umgestellt (kein doppelt gepflegter Cypher-Text) — läuft die Kandidaten/Pro-Einheit-Schleife
  ohne Checkpoint/Resume (einmaliger interaktiver Lauf, alle Schritte idempotent); dabei nebenbei
  einen Bestandsfehler behoben (`$orgMode` wurde nie an `evaluate_sod` übergeben, obwohl referenziert).
  **Verifiziert** gegen den laufenden Container (Zähler/Status, keine Nutzerdaten): Fortschritt
  sichtbar (`stepNum`/`stepTotal` steigen: z. B. 1→2 während `materialize`, 626→4219 während
  `explain`); Abbruch wirkt jetzt innerhalb einer Einheit (Sekunden statt der ganzen Phase);
  Resume eines abgebrochenen Einzellaufs setzt exakt bei der zuletzt geschriebenen Einheit fort
  (nicht bei 0); Resume eines abgebrochenen Batch-Laufs bleibt in der richtigen Variante; Discard
  räumt Run/Findings/MATCHES **und** Checkpoint vollständig weg (0 Restknoten/-kanten geprüft);
  `do_explain` mit Fortschritt einmal komplett durchgelaufen (4219 Akteure, Ergebnis 492 intra /
  9 inter identisch zur vorherigen Berechnung). PowerShell-Host-Runner smoke-getestet (Auswerten
  von 5 bzw. 22 Regeln gegen bereits materialisierte Matches).
- [x] **Einzelfilter-Umfang beim Lauf wählbar (Default umgedreht) — Nutzer-Wunsch, teilweise
  Vorgriff auf „Katalog-Auswahl".** Bisher materialisierte `materialize_matches_candidates.cypher`
  IMMER nur die Queries, die als Klausel-Baustein mindestens einer SoD-Regel des Rulesets dienen
  (`WHERE EXISTS {(q)<-[:NEEDS]-(:Clause ...)}`, fest verdrahtet) — Nutzer-Beobachtung: von >600
  Einzelfiltern im Vendor-Katalog erschienen dadurch nur 38 in der Einzelfilter-Übersicht, obwohl
  alle 22 SoD-Regeln aufgetaucht sind (kein Bug, s. vorheriger Eintrag). Neues Feld **„Einzelfilter-
  Umfang"** im „Neuer Lauf"-Dialog (`queryScope`, neuer `RunReq`/`RunBatchReq`-Parameter): **„Alle
  Einzelfilter + SoD"** (neuer Default — bewusst umgedreht gegenüber dem bisherigen impliziten
  Verhalten) materialisiert **jede** Query des Rulesets; **„Nur SoD-relevante Einzelfilter"**
  behält das bisherige, schnellere Verhalten (Klausel-Queries only) bei — welche das sind, ist
  ruleset-abhängig (z. B. andere Zahl bei einem anderen Filterset). `queryScope` wird am `(:Run)`
  gespeichert (`evaluate_sod_init.cypher`); `GET /queries` (Einzelfilter-Dropdown) liest es zurück
  (`coalesce(r.queryScope,'sodOnly')` für ältere Läufe ohne das Feld) und zeigt genau die Queries,
  die in **diesem** Lauf tatsächlich materialisiert wurden — auch mit 0 Treffern (Katalog-Browsing).
  `GET /queries/summary` brauchte **keine** Scope-Logik: die dortige `MATCH (u)-[:MATCHES]->(q)`-
  Kardinalität filtert implizit exakt richtig (eine nie materialisierte Query kann nie eine
  MATCHES-Kante haben), der bisherige zusätzliche Klausel-Filter dort war redundant und wurde
  entfernt. **Performance-Hinweis dokumentiert** (Handbuch): „Alle" kann bei einem Katalog mit
  deutlich mehr Einzelfiltern als SoD-Klauseln ein Vielfaches länger dauern; „Materialisierung
  überspringen" federt das für Wiederholungsläufe auf denselben Stichtag ab. Verifiziert gegen den
  laufenden Container (nur Cypher-Logik/Kandidaten-Zählung, **keine** volle Materialisierung mit
  „alle" gegen die echten 27.000 User gefahren — das wäre ein Vielfaches der bereits als lang
  bekannten Laufzeit): `materialize_matches_candidates.cypher` liefert mit `queryScope='all'`
  genau 604 Kandidaten, mit `queryScope='sodOnly'` genau 38 (deckt sich mit dem vorherigen
  Eintrag); `/queries` und `/queries/summary` liefern für einen bestehenden Lauf ohne gespeichertes
  `queryScope` weiterhin unverändert 38 Zeilen (Rückwärtskompatibilität bestätigt); `POST /runs`
  akzeptiert einen Request ohne `queryScope`-Feld (Default „all" greift, Pydantic-Validierung ok).
  **Offen (ROADMAP „Katalog-Auswahl"):** dies ist nur ein binärer Umfang-Schalter, keine
  Kritikalitäts-/Namensmuster-/Modul-Filterung einzelner Queries/Regeln — das bleibt der volle
  Scoping-Schritt ③ im Assistenten.
- [x] **Katalog-Auswahl — füllt Schritt ③ „Scoping" im Assistenten (voller Katalog-Browser statt
  Platzhalter/binärem Schalter) + zwei Auswertungsarten (Can-Do vs. scoped SoD).** Schritt ③
  zeigt jetzt zwei nebeneinander liegende Panels (Einzelfilter, SoD-Regeln), gespeist aus den
  bestehenden `GET /admin/rulesets/{ruleset}/queries`/`/sodrules` (kein `runId` nötig,
  Katalog-Browsing statt Editor — dafür beide Endpunkte um `criticalityRank` ergänzt, das JSON-Feld
  war zuvor nur intern am Neo4j-Knoten genutzt) — je Panel Filter (Namensmuster inkl. `*`-Wildcard,
  Modul, queryType nur bei Queries, Mindest-Kritikalität) über eine scrollbare Checkbox-Tabelle,
  „alle (gefiltert)"/„leeren"-Buttons, Live-Summary. Auswahl liegt in `asst.queryIds`/
  `asst.sodRuleIds` (Sets), wird beim Verlassen des Assistenten (`startAssistent()`) zurückgesetzt.
  **Backend:** `RunReq`/`RunBatchReq` um `queryIds: list[str]` und `evaluateSod: bool` erweitert.
  `materialize_matches_candidates.cypher` bekommt `$queryIds`/`$sodRules` mit Priorität vor
  `$queryScope` (explizite Query-Auswahl > nur die Klausel-Queries der gewählten SoD-Regeln >
  bisherige `all`/`sodOnly`-Logik, unverändert wenn beide leer). `_run_one()`: `evaluate_sod_init.cypher`
  legt den `(:Run)`-Knoten weiterhin **immer** an (Ergebnis-Views brauchen ihn), der eigentliche
  Regel-Auswertungs-Loop + Explain laufen aber nur noch `if evaluate_sod` — Can-Do-Modus (nur
  Einzelfilter gewählt, keine SoD-Regel) materialisiert und überspringt SoD komplett automatisch
  (`evaluateSod = asst.sodRuleIds.size > 0` beim Absenden von „Neuer Lauf"). **„Neuer Lauf"-Dialog:**
  solange eine Assistent-Katalog-Auswahl besteht, ersetzt eine Zusammenfassungszeile („Katalog-Auswahl
  aus Assistent … / Auswahl ändern…") den `queryScope`-Dropdown; ohne Auswahl unverändertes
  Verhalten (volle Rückwärtskompatibilität, leere Listen = alter Default). Verifiziert gegen den
  laufenden Container: `materialize_matches_candidates.cypher` liefert mit `queryScope='all'`
  weiterhin 604 und mit `sodOnly` weiterhin 38 Kandidaten (Regressionscheck); explizite
  `queryIds`-Auswahl (1 Query) liefert genau 1 Kandidaten; `sodRules`-Scoping (1 Regel) liefert
  exakt die Anzahl ihrer Klausel-Queries (Cypher-Zählung gegen manuelle `HAS_CLAUSE`/`NEEDS`-
  Traversierung abgeglichen, 5 von 5); ein echter `POST /runs` mit `queryIds` + `evaluateSod:false`
  erzeugt einen `(:Run)`-Knoten mit `findings:0`/`rules:0`, `GET /queries/summary` zeigt korrekt nur
  die gewählte Query mit echter Nutzerzahl (Testlauf danach über `POST /runs/{id}/delete` entfernt).
  Playwright-UI-Check: Katalog lädt (604/22 Zeilen), Namensmuster- und Kritikalitäts-Filter grenzen
  sichtbar ein, Checkbox-Auswahl bleibt über Filteränderungen hinweg erhalten, Summary-Text
  aktualisiert korrekt zwischen „nur Einzelfilter → Can-Do" und „+ SoD-Regel → scoped SoD", „Neuer
  Lauf" zeigt die Scoping-Zusammenfassung statt des Dropdowns, keine Konsolenfehler.
  **Nicht Teil dieses Schritts:** Host-Runner (`run/run_evaluate.ps1`) übergibt weiterhin kein
  `$queryScope`/`$queryIds`/`$sodRules` an die Cypher-Datei (vorbestehende Lücke, App-Endpunkte
  sind die maßgebliche Variante); USOBT-Query-Builder und Threat-Baum bleiben eigene, größere
  Vorhaben (s. Admin-Bereich-Backlog).
- [x] **Persistente Scope-Profile — neue Admin-Seite „Scope" (Nutzer-Wunsch nach der
  Katalog-Auswahl: dieselbe Auswahl-Erfahrung, aber gespeichert statt nur session-gebunden im
  Assistenten).** Neue Seite `frontend/admin-scopes.html` (Layout/Ribbon/Theme wie
  `admin-org-profiles.html`): links Ruleset-Auswahl + Liste der gespeicherten Scope-Profile
  dieses Rulesets (mit Zählung „N Einzelfilter, M SoD-Regel(n)"), rechts derselbe
  Zwei-Panel-Katalog-Browser wie Assistent Schritt ③ (Namensmuster/Modul/Kritikalität/queryType-
  Filter + Checkbox-Tabellen je Einzelfilter/SoD-Regeln — Logik dupliziert, kein Shared-JS in
  diesem Projekt üblich), darunter Name/Beschreibung + Speichern/Löschen. **Backend:** neue
  Endpunkte `GET/POST/PUT/DELETE /admin/rulesets/{ruleset}/scopes`, Speicherort
  `rules/<RulesetDir>/scope_profiles.custom.json` (reine Custom-Datei ohne Vendor-Gegenstück,
  analog `queries.custom.json`/`sod_rules.custom.json` — **git-getrackt**, da Query-/SoD-Regel-
  IDs Ruleset-Vokabular sind, keine Mandantendaten; anders als die bewusst `.gitignore`te
  `config/analysis_profiles.custom.json` der Org-Varianten). Validierung: `_SAFE_NAME` für den
  Namen, Namenskollision → 409, leere Auswahl (weder Query- noch SoD-Regel-IDs) → 400. Ein totes
  Phase-3-Scaffold (`config/analysis_profiles.json` Key `scopeProfiles`, nie ins Frontend/einen
  Lauf verdrahtet) bleibt bewusst unangetastet stehen — die neue Funktion ersetzt es funktional.
  **„Neuer Lauf"-Dialog:** neues Auswahlfeld „Gespeicherter Scope" (`#scopeProfileSel`, lädt bei
  jedem Ruleset-Wechsel neu); Scoping-Quellen-Auflösung verallgemeinert
  (`currentRunScopingSource()`) mit Priorität **gewählter gespeicherter Scope** > **aktive
  Assistent-Ad-hoc-Auswahl** > keiner (altes `queryScope`-Verhalten) — ersetzt die bisherige, nur
  auf den Assistenten bezogene `asstRunScopingPayload()`/`refreshRunScopingSummary()`-Logik.
  Verifiziert gegen den laufenden Container: `POST/GET/PUT/DELETE` auf `/scopes` mit korrekten
  Statuscodes (201-artig `saved:true`/409/400/404), Datei landet unter
  `rules/KPMG_R3/scope_profiles.custom.json` und ist git-sichtbar (nicht ignoriert). Playwright:
  Scope in der Admin-Seite anlegen (2 Einzelfilter + 1 SoD-Regel per Filter+Checkbox ausgewählt),
  erscheint in der Liste mit korrekter Zählung, übersteht einen Seiten-Reload, Checkbox-
  Vorbelegung beim erneuten Öffnen korrekt; im „Neuer Lauf"-Dialog Scope ausgewählt → Dropdown
  „Einzelfilter-Umfang" verschwindet, Zusammenfassung zeigt Namen + korrekte Zahlen, Bearbeiten-
  Link ausgeblendet (kein Rücksprung zu Assistent-Schritt ③ bei einem gespeicherten Scope); Reset
  auf „kein gespeicherter Scope" stellt das alte Dropdown wieder her; danach Löschen bestätigt.
  Keine Konsolenfehler.
- [x] **Katalog-Auswahl verfeinert (Nutzer-Feedback nach erster Nutzung): Bezeichnung- statt
  ID-Filter, mehr Zeilen, bidirektionale Einzelfilter↔SoD-Verknüpfung, zweistufiger Ablauf.**
  Betrifft Assistent Schritt ③ **und** die Admin-Seite „Scope" (Nutzer-Wunsch: beide
  Oberflächen). Vier Korrekturen:
  1. **Namensmuster matcht nur noch die Bezeichnung** (`shortDescription || description`, dieselbe
     Spalte wie in der Tabelle) statt zusätzlich die ID — ID-Treffer waren „ungünstig"
     (Nutzer-Zitat), da IDs oft keine sprechenden Substrings tragen.
  2. **Tabelle zeigt ~20 Zeilen ohne Scrollen** (`max-height` von `280px` auf `min(620px, 65vh)`),
     mehr Scrollen darüber hinaus ist bewusst in Kauf genommen.
  3. **Bidirektionale Verknüpfung** über die CNF-Klausel-Struktur (`clauses: [[qid,...],...]`,
     jetzt zusätzlich in `GET /admin/rulesets/{r}/sodrules` projiziert, lag in `_merged_sodrules()`
     schon vor) — **„nur mögliche SoD-Regeln"**-Umschalter (Pill „alle"/„nur mögliche") in Stufe 2:
     eine Regel gilt als möglich, wenn jede ihrer Klauseln mindestens eine Query der
     Einzelfilter-Auswahl enthält (clientseitig berechnet, keine neue Cypher-Logik). Nur `kpmg_r3`
     hat heute CNF-Klauseln (CSI/CSI_BI: 0 von je 455 Regeln) — dort zeigt der Umschalter
     stattdessen einen Hinweis („keine Klausel-Struktur, automatische Verknüpfung nicht möglich")
     und bleibt auf „alle". **Korrektheits-Sicherheitsnetz:** da
     `materialize_matches_candidates.cypher` bei gesetzten `queryIds` diese **immer** vor der
     SoD-Regel-Ableitung priorisiert, würde eine gewählte SoD-Regel ohne alle ihre Klausel-Queries
     in der Einzelfilter-Auswahl sonst nie erfüllbar sein (stille Fehlauswertung) — eine neue
     `effectiveQueryIds()`-Funktion ergänzt beim Finalisieren automatisch **additiv** (nie
     löschend) die fehlenden Klausel-Queries; Summary/Speichern-Zusammenfassung weisen „davon N
     automatisch ergänzt" separat aus.
  4. **Zweistufiger Ablauf** statt zwei Panels nebeneinander: **Stufe 1 Einzelfilter** (optional,
     überspringbar) → **Stufe 2 SoD-Regeln** (mit dem „nur mögliche"-Umschalter). Im Assistenten
     als erzwungene Mini-Navigation innerhalb Schritt ③ (`asst.scopeStage`, „Weiter"/„Zurück"
     zwischen den Stufen, wie der übrige Assistent); auf der Admin-Seite „Scope" als **frei
     klickbarer** Mini-Stepper „① Einzelfilter · ② SoD-Regeln · ③ Speichern" (kein erzwungener
     linearer Zwang — ein bestehender Scope öffnet direkt bei ③ mit Rücksprung in ①/② zum
     Nachjustieren, ein neuer startet bei ①). Layout je Stufe jetzt vollbreites Einzelpanel statt
     Zwei-Spalten-Grid (mehr Platz für die höhere Tabelle).
  Verifiziert gegen den laufenden Container: Namensmuster, das nur in einer ID (nicht der
  Bezeichnung) vorkommt, liefert jetzt 0 Treffer, ein Bezeichnungs-Muster weiterhin Treffer;
  Modul-Filter „Basis Module" + „alle wählen" (90 Queries) → Stufe 2 zeigt unter „nur mögliche"
  automatisch exakt `BCX_0001/0002/0003` (3 von 22 Regeln) — genau das vom Nutzer vorhergesagte
  Beispiel; ohne Stufe-1-Auswahl bleibt der Default korrekt „alle" (sonst wäre „nur mögliche"
  leer); eine SoD-Regel ohne vorherige Einzelfilter-Auswahl gewählt → Speichern-Zusammenfassung
  weist alle 5 benötigten Klausel-Queries korrekt als „automatisch ergänzt" aus; bestehender
  Scope öffnet direkt bei Stufe „Speichern", Rücksprung nach „Einzelfilter" zeigt die
  gespeicherte Auswahl korrekt vorbelegt. Keine Konsolenfehler auf beiden Oberflächen.
- [x] **Voreinstellung um Benutzergruppe + Sleeping erweitert (Nutzer-Wunsch direkt im
  Anschluss).** Sowohl gespeicherte Scope-Profile (Admin „Scope", Stufe ③ „Speichern") als auch
  die Ad-hoc-Auswahl im Assistenten (Schritt ③, Stufe „SoD-Regeln") legen jetzt zusätzlich
  **Nutzertyp-Profil** und **Sleeping (Tage)** fest — dieselben Achsen, die „Neuer Lauf" schon
  kennt. Backend: `ScopeProfileEditReq`/`-CreateReq` um `userTypeProfile: str = "all"`,
  `sleepDays: int = 180` erweitert, 1:1 in den gespeicherten Eintrag übernommen (keine
  Server-seitige Existenzprüfung des Profilnamens nötig, `_run_one()` validiert das ohnehin beim
  Lauf). **„Neuer Lauf":** `currentRunScopingSource()` liefert jetzt zusätzlich
  `userTypeProfile`/`sleepDays` der aktiven Quelle; ist eine Voreinstellung aktiv (gespeicherter
  Scope **oder** Assistent-Ad-hoc-Auswahl), blendet `refreshRunScopingSummary()` zusätzlich zu
  `#queryScopeGroup` auch die neuen Wrapper `#userTypeProfileGroup`/`#sleepDaysGroup` aus (Felder
  bislang unverpackt bzw. Teil einer `.row`, jetzt mit eigener `id`) — die Formularfelder
  „verschwinden", der Lauf nutzt die Werte der Voreinstellung. Zusammenfassungstext nennt sie
  („… · Nutzertyp-Profil: X · Sleeping: Y Tage"), Label heißt jetzt generischer „Voreinstellung"
  statt „Katalog-Auswahl" (spiegelt den breiteren Umfang, Seiten-/Menü-Branding „Scope" bleibt
  unverändert). Verifiziert gegen den laufenden Container: `POST .../scopes` mit
  `userTypeProfile`/`sleepDays` → `GET` liefert sie zurück (bestehender, vom Nutzer selbst
  angelegter Scope „Basisberechtigungen" blieb dabei unangetastet, fehlende Felder degradieren
  dort clientseitig sauber auf die Standardwerte); Playwright bestätigt für beide Quellen (Admin-
  Scope „dialog-active"/90 Tage, Assistent „dialog-only"/365 Tage), dass alle drei Gruppen im
  „Neuer Lauf"-Dialog korrekt aus-/eingeblendet werden und die Zusammenfassung die richtigen
  Werte zeigt. Keine Konsolenfehler.
- [x] **Sidebar-Filter (Einzelfilter/SoD) auf den tatsächlichen Katalog-Auswahl-Scope des Laufs
  beschränkt (Nutzer-Feedback: „nur die möglichen Einzel-/SoD-Filter").** `GET /queries`/
  `GET /sodrules` (Sidebar-Dropdowns der normalen Ergebnis-Ansicht, nicht die schon vorher
  korrekte Ergebnisse-Übersicht `/queries/summary`/`/sodrules/summary`, die über echte
  `MATCHES`/`VIOLATES`-Kanten filtert) kannten bislang nur das alte binäre `queryScope`
  („all"/„sodOnly") — bei einem Lauf mit `queryIds`/`sodRules`-Katalog-Auswahl zeigten sie
  trotzdem weiterhin den **gesamten** Ruleset-Katalog, weil diese beiden Felder bisher gar nicht
  am `(:Run)`-Knoten gespeichert wurden (nur als Cypher-Laufzeitparameter für die Materialisierung
  existent). Fix: `evaluate_sod_init.cypher` speichert jetzt zusätzlich `run.queryIds`/
  `run.sodRules` (leere Liste = altes Verhalten, volle Rückwärtskompatibilität für Läufe vor
  diesem Fix); `_query_scope_where()` in `backend/app.py` bekommt dieselbe Prioritätslogik wie
  `materialize_matches_candidates.cypher`: explizite `queryIds` > `sodRules`-Scoping (nur
  Klausel-Queries dieser Regeln) > altes `queryScope`. `GET /sodrules` filtert zusätzlich analog
  auf `run.sodRules`, wenn gesetzt (sonst weiterhin alle Regeln, da `queryScope` allein die
  SoD-Regel-Auswahl nicht einschränkt). Verifiziert gegen den laufenden Container: ein Lauf mit
  `queryIds=[2 IDs]` liefert über `/queries` exakt diese 2 (statt 604/38); ein Lauf mit
  `sodRules=['BCX_0001']` liefert über `/sodrules` exakt 1 Regel und über `/queries` exakt deren
  5 Klausel-Queries; drei bestehende, vor diesem Fix gelaufene Läufe (ohne `queryIds`/`sodRules`
  am Run-Knoten) liefern weiterhin unverändert 38/604 Queries bzw. alle 22 SoD-Regeln —
  Rückwärtskompatibilität bestätigt. Testläufe danach gelöscht.
- [x] **Multi-Varianten-Läufe.** Jede Variante (z. B. „Standard", „Übergreifend", „BUKRS=…") = ein eigener, **benannter** `(:Run)` (Titel-Feld, Lauf-Liste zeigt Titel als Hauptlabel + Run-ID als Mini-Chip). **Org-Varianten sind jetzt frei konfigurierbar:** neue Admin-Seite **„Org-Varianten"** (`frontend/admin-org-profiles.html`, verlinkt aus Ribbon „Admin") — wählt aus den tatsächlich im Dataset vorkommenden Org-Feldern (`GET /admin/org-profiles/org-fields`) und Werten (`GET /admin/org-profiles/org-field-values`, **echte Werte aus den Authorization-Daten**, kein Freitext) ein oder mehrere Kriterien (UND/ODER/Bereich) und speichert sie unter einem Namen. Overlay-Mechanismus wie bei Query-/SoD-Metadaten (`config/analysis_profiles.custom.json`, Vendor-Datei `analysis_profiles.json` bleibt unberührt) — **aber bewusst `.gitignore`d** (anders als `queries.custom.json`), da Org-Varianten echte Mandanten-Org-Codes enthalten können. **„Standard"/„Übergreifend" sind geschützt** (nicht editierbar/löschbar, `PROTECTED_ORG_PROFILES`). **Paralleles Anlegen mehrerer Varianten in einem Schritt:** „Neuer Lauf"-Dialog hat jetzt eine **Mehrfachauswahl** (Checkbox-Dropdown, gleiches `ddcheck`-Pattern wie der Nutzertyp-Filter) statt eines Single-Select; bei mehreren gewählten Varianten entsteht über den neuen Endpoint `POST /runs/batch` **ein Job mit je einem eigenen Lauf pro Variante** (Titel = Variantenname, sequenziell abgearbeitet — gemeinsame Neo4j-Session, kein Parallel-Schreiben). Backend-Refactor: `do_run()`-Kern in `_run_one()` ausgelagert, von Einzel- (`do_run`) und Batch-Lauf (`do_run_batch`) gemeinsam genutzt. Verifiziert gegen den laufenden Container: Variante mit echten Org-Werten angelegt/bearbeitet/gelöscht (Vendor-Datei unverändert, geschützte Profile lehnen Edit/Delete mit 400 ab), Batch-Lauf mit drei Varianten erzeugt drei `(:Run)` mit unterschiedlichen Trefferzahlen und kurzen Titeln. **Nicht Teil dieses Schritts:** sichtbare Gruppierung mehrerer Läufe als „Varianten-Set" in der UI (jeder Batch-Lauf erscheint einzeln in der Lauf-Liste).
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
  **Titel/Beschreibung nachträglich änderbar (2026-07-11):** neuer Endpoint
  `PUT /runs/{runId}/meta` (reines Metadaten-Update, kein Neu-Lauf); Stift-Icon an jeder
  Lauf-Karte öffnet einen Dialog mit Titel-Input + mehrzeiliger, per Ziehgriff vergrößerbarer
  Beschreibung (`textarea{resize:vertical}`, analog Risiko-Feld im Editor) — Nutzer-Feedback,
  dass ein einmal vergebener Variantenname bisher nicht korrigierbar war.
- [x] **Nutzer-Scope verfeinern (2026-07-11).** Nutzertyp und Sleeping waren bereits
  zusätzlich **Ergebnisfilter** (nicht nur Lauf-Kriterium). Ergänzt:
  **Sleeping-Schnellwahl 90/180/360 Tage** — erscheint bei „nur sleeping"/„nicht sleeping" als
  eigene Pillgroup; weicht der gewählte Wert vom beim Lauf gesetzten `sleepDays`-Fenster ab, schaltet
  `GET /findings`/`/findings/summary`/`/findings/export` (`_FINDINGS_WHERE`, `backend/app.py`) von
  der materialisierten `f.userSleeping`/`f.lastLogonKnown` auf eine **Live-Berechnung** gegen
  `u.lastLogon`/`run.asOf` um (gleiche Formel wie `_USER_ENRICH_RETURN`) — ohne Override unverändert
  die materialisierten Werte. **Gesperrte nach Sperrtyp:** neuer Ergebnisfilter „Gesperrt"
  (alle/gesperrt/nicht gesperrt) + bei „gesperrt" Sperrgrund-Pills (alle/`failed_logons`/
  `admin_local`/`admin_global`, direkt gegen `u.lockReasons` — kein materialisiertes Äquivalent
  am Finding nötig, da `u` in `_FINDINGS_WHERE` bereits gebunden ist). Wirkt nur für Läufe, die
  gesperrte User nicht schon beim Materialisieren ausgeschlossen haben (`excludeLocked=false`) —
  sonst fehlen deren Findings von vornherein, dokumentiert im Code-Kommentar. Verifiziert:
  Pass-Through-Grenzfälle gegen echte Lauf-Daten (`locked=false` bzw. `sleeping=unknown` liefern
  exakt dieselbe Trefferzahl wie ganz ohne Filter, da dieses Dataset weder TRDAT noch gesperrte
  User enthält — bekannte Datenlücke) sowie Playwright-UI-Test (Pill-Sichtbarkeit, Request-Parameter,
  Filter-Chip-Text, Reset).
- [x] **Evidenz-Perf (2026-07-11).** Vorab geflachte Erreichbarkeit `(:Role|:Profile)-[:GRANTS]->(:Authorization)`
  (transitive Hülle CONTAINS/HAS_PROFILE, `load/91_materialize_grants.cypher`, einmal je Dataset
  beim Import, ~62s für 5,1 Mio. Kanten) — `explain_sod_one.cypher` nutzt sie jetzt als Lookup statt
  der `CONTAINS|HAS_PROFILE*0..4`-Pfadsuche. **Benchmark-Überraschung:** die Traversierung selbst war
  in diesem Datenbestand gar nicht der Flaschenhals (~2ms/Akteur vorher, GRANTS spart davon nur
  ~10–15 %) — die eigentlichen Kostentreiber lagen woanders und wurden mit behoben:
  1. `_run_phase()` (gemeinsamer Batching-Rahmen für Materialisierung/Auswertung/Evidenz) schrieb
     nach **jeder einzelnen** Einheit die komplette, wachsende Checkpoint-Liste neu auf die
     Festplatte (O(n²) bei tausenden Akteuren). **Nutzer-Entscheidung:** Wiederaufnehmen
     abgebrochener Läufe bleibt wichtiger als ein einziger gebatchter `apoc.periodic.iterate`-Aufruf
     (der die Pro-Akteur-Resume-Granularität gekostet hätte) — also stattdessen zeitgesteuertes
     Schreiben (höchstens alle 2s + garantiert am Ende), bei exakt gleicher Resume-Granularität;
     ein Absturz verliert dadurch höchstens ein paar Sekunden bereits erledigter, aber ohnehin
     idempotenter (`MERGE`) Arbeit.
  2. `explain_sod_finalize.cypher` (intra/inter-Berechnung) leitete den violierenden User in der
     verschachtelten `EXISTS`-Klausel je Akteur×Klausel **redundant neu her**
     (`(f)<-[:VIOLATES]-(:User)-[:MATCHES]->(q)`), obwohl `u` aus dem äußeren `MATCH` bereits
     gebunden war und nur durch ein zwischenzeitliches `WITH` aus dem Scope gefallen ist — Fix:
     `u` durchreichen, direkt `(u)-[:MATCHES]->(q)` prüfen. **Effekt: 53,5s → 0,7s** (72×) für
     501 Findings.
  **Gesamtergebnis (verifiziert, bit-identische Resultate vor/nach allen drei Fixes):** kompletter
  `/runs/{id}/explain`-Durchlauf für ~4.200 Akteure/501 Findings von ~90–100s auf **~27,6s**
  (≈3,5×). **Evidenz default-on aktiviert:** `RunReq.skipExplain`/`RunBatchReq.skipExplain`
  Default auf `False` gedreht, „Neuer Lauf"-Formular hat jetzt eine **„Evidenz überspringen"**-
  Checkbox (Default aus, analog „Materialisierung überspringen"/„Ruleset-Laden überspringen") statt
  der bisherigen Opt-in-Checkbox „Evidenz mitberechnen" — jeder neue Lauf berechnet VIA_ROLE/
  VIA_PROFILE/intra-inter jetzt automatisch mit, abwählbar für schnellere Läufe, Ribbon „Evidenz"
  bleibt für ältere Läufe ohne Evidenz.

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
  **Nachträglicher Korrekturbedarf (Nutzer-Feedback):** Klick auf einen Lauf in der „Läufe"-
  Sidebar direkt aus der (später ergänzten) eigenen Root-Cause-Seite heraus zeigte scheinbar
  nichts an. Ursache: `showFindings(runId)` lädt nur die Findings-Daten neu, schaltet aber nie
  die Sichtbarkeit auf die Ergebnis-Ansicht zurück — sie ging bislang davon aus, bereits
  sichtbar zu sein. Kam der Klick aus einer anderen Ansicht (Root-Cause, Konsistenzcheck-
  Ergebnis), blieb diese sichtbar, während die (unsichtbare) Ergebnis-Ansicht im Hintergrund
  aktualisiert wurde. Fix: gemeinsame `_showResultsLayout()`-Hilfsfunktion (aus
  `showResultsView()` herausgezogen) wird jetzt auch vom Sidebar-Klick-Handler aufgerufen —
  bewusst **nicht** in `showFindings()` selbst, da diese Funktion auch vom generischen
  Job-Abschluss-Refresh (`poll()`) verwendet wird und dort kein Ansichtswechsel gewünscht ist
  (sonst würde z. B. ein Dataset-Backup während einer Root-Cause-Analyse ungefragt aus der
  Ansicht herausspringen).
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
- [x] **Root-Cause-Graph (Pfad + Radial) — Nutzer-Wunsch.** Die Root-Cause-Seite hat neben der
  Tabelle einen **Ansicht-Umschalter „Tabelle · Pfadgraph · Radial"** (`rcViewPills`). Beide
  Graph-Varianten nutzen die **bereits vendored Cytoscape.js** (MIT, `frontend/vendor/cytoscape/`,
  wie der Konsistenzcheck-Graph-Pilot) und werden aus **denselben `/root-cause`-Daten** gebaut wie
  die Tabelle — kein neuer Endpoint, keine Zusatz-Cypher. Der Builder (`rcBuildGraph()`) projiziert
  die `blocks`-Struktur auf einen Baum **User → Regel → Klausel → Query → Objekt(+Anforderung) →
  Rolle/Profil**: Klauseln werden aus den `Klausel N · Query X`-Labels rekonstruiert und dedupliziert,
  Einzelfilter-Root-Cause hängt die Objekte direkt unter die Query (keine Klausel-Ebene),
  Konsistenzcheck-Befunde (Label ohne Query-/Klausel-Muster) hängen direkt unter den Check-Knoten.
  Knoten-Styling kodiert die Semantik: Rolle vs. Profil (Farbe), **technisch/generiert** (gestrichelt,
  halbtransparent), **verwaist** (roter Rand), **„via generiertem Profil"** (rote gestrichelte Kante);
  UND/ODER stehen als Kantenbeschriftung. Der bestehende **„ohne technische / alle"-Filter** wirkt
  auch im Graph. Interaktion: Knoten-Klick hebt den Pfad hervor (Rest ausgegraut), Hover zeigt Details
  (technisch/via/Feldwerte), „Einpassen"-Button, Zoom/Pan. Theme-aware (liest die CSS-Variablen der
  App, funktioniert in Hell/Dunkel). **Pfadgraph** = `breadthfirst`-Layout (Wurzel User),
  **Radial** = `concentric`-Layout (User im Zentrum, Ebenen als Ringe nach außen). Nebenbei ein
  Render-Race behoben: `showFindings()` lädt Findings + Regel-Bezeichnungen jetzt parallel (`Promise.all`),
  sonst fehlte die Bezeichnung beim allerersten Öffnen — war schon vorher offen, hier miterledigt.
  Verifiziert gegen einen echten Lauf: Builder erzeugt aus den Live-`/root-cause`-Daten einen
  wohlgeformten, zusammenhängenden Baum (69 Knoten / 68 Kanten, keine doppelten IDs, keine
  ins-Leere-Kanten, kein unverbundener Knoten) für Pfad- **und** Radial-Layout. **Kein** Browser-
  Rendering-Test in der Session möglich (nur Server-/Builder-Ebene geprüft; die Cytoscape-Render-
  Mechanik ist die 1:1 aus dem Wegwerf-Prototyp übernommene, dort visuell bestätigte).
  **Nachträgliche Verfeinerungen (Nutzer-Feedback):** (1) Cytoscape-Größen-Fix — Knoten
  kollabierten zu „dünnen Linien", weil `text-max-width`/`padding` als `'…px'`-Strings statt Zahlen
  gesetzt waren (jetzt numerisch, feste Knotenbreite, frische Instanz je Render). (2) **Vollbild +
  vertikaler Zoom-Slider** am Graph. (3) Dritter Profil-Filter **„nur generierte Rollen"** =
  Laufzeitsicht (nur über generiertes Profil aktive Rollen + Direktprofile; Design-only/D4 raus),
  im Graph zusätzlich **Dedup** (jeder Akteur einmal, Baum→DAG; echte Daten 28→9 Knoten).
  (4) **Wertidentische** „eigene Definition = generiertes Profil"-Zeilen zusammenfassen. (5)
  **Zeilen pro Rolle gruppieren** (mehrere Berechtigungsinstanzen je Objekt sind reale SAP-Daten,
  AE-03 — nicht aggregierbar, nur optisch gruppiert) + Werte-Filter **„nur Treffer"** (nur die
  passenden grünen Werte, entlastet Rollen mit vielen TCodes: 63→2 im Beispiel).
- [x] **Rollen-Detailseite (anklickbare Rolle) — Nutzer-Wunsch.** Rollennamen (Tabelle) und
  Rollen-Knoten (Graph) öffnen eine eigene View mit 5 Reitern: **Stammdaten** (Beschreibung,
  Subtyp, Elternrolle, generiertes Profil + Generierungsstatus, Ersteller/letzter Änderer + Daten,
  Zuweisungs-Gültigkeit des betrachteten Users, User-Anzahl), **TCodes** (effektiv S_TCODE +
  Rollenmenü), **Berechtigungsobjekte** (Instanz-Anzahl), **Einzelberechtigungen** und
  **SoD-Regeln** — die letzten beiden **rollenzentrisch** (was die Rolle **allein** erfüllt/auslöst,
  frisch berechnet über `cypher/roles/role_can_do.cypher`/`role_sod_rules.cypher`, die
  PROVIDES-Prädikate aus `explain_sod_one.cypher` für eine Rolle; lazy geladen). Neue Endpoints
  `GET /roles/{id}` (Stammdaten/TCodes/BOs) + `GET /roles/{id}/can-do`. Nur aus dem lauf-basierten
  Root-Cause klickbar (Dataset über `runId` eindeutig; im Konsistenzcheck-Root-Cause gesperrt).
  **Loader-Erweiterung + Bugfix:** `load/02_roles.cypher` lädt jetzt `CREATE_USR/DAT`,
  `CHANGE_USR/DAT` (Stammdaten); **`load/22_role_profile_status.cypher` las `agr_1016b.csv`, der
  Export heißt aber `agr_1016.csv`** (Tabelle AGR_1016 mit `GENERATED`/`PSTATE`) → `profileGenerated`
  war bei **allen** Rollen NULL, was auch Konsistenzcheck **D4** aushebelte — auf `agr_1016.csv`
  umgestellt (`required_tables.json` + Extraktionsleitfaden nachgezogen). Verifiziert: nach dem Fix
  `profileGenerated` auf 307.595 Rollen gesetzt (vorher 0); `/roles`/`/can-do` liefern korrekte
  Zählwerte, die rollenzentrische can-do-Liste enthält die erwarteten Queries. Ein separates
  **Generierungsdatum** ist im Extrakt nicht vorhanden → wird als „nicht im Extrakt" ausgewiesen.
  Die korrigierten Loader wurden zur Verifikation direkt gegen den laufenden Container ausgeführt
  (kein separater Re-Import nötig, um die neuen Properties am bestehenden Dataset zu sehen — nur
  bei einem **künftigen** Neu-Import greift der Fix automatisch mit). **Kein** Browser-Rendering-
  Test in der Session (nur API/Loader-Ebene geprüft).
  **Nachträgliche Verfeinerung (Nutzer-Feedback):** Stammdaten sind jetzt **immer sichtbar** (wie
  die Metadaten im Query-Editor, `admin.html`), TCodes/Berechtigungsobjekte/Einzelberechtigungen/
  SoD-Regeln darunter als 4 Reiter (Stammdaten selbst kein Reiter mehr). `roleDetailView` in
  `.cols` verschachtelt (wie `rootCauseView`) — die linke Filter-/Läufe-Sidebar bleibt sichtbar
  statt zu verschwinden. Ersteller/Änderer zeigen jetzt **„Name (Kürzel)"** wenn ein Name bekannt
  ist (`V_USERNAME` → `User.name`, `OPTIONAL MATCH` da nicht jedes SAP-Kürzel als `:User` im
  Dataset vorhanden ist — z. B. Basis-Team ohne Dialog-Zugang), sonst nur das Kürzel. Profilstatus
  zeigt die Bedeutung von `PSTATE='A'` ("Aktiv") mit Hinweis-Icon, da die Codes SAP-seitig nicht
  einheitlich dokumentiert sind (Extraktionsleitfaden §22 entsprechend ergänzt).
- [x] **Ergebnisse-Übersicht Einzelberechtigungen/SoD-Regeln + CSV-Export-Fix — Nutzer-Wunsch.**
  Zwei neue Ribbon-Menüpunkte unter „Ergebnisse": **„Einzelberechtigungen"** und **„SoD-Regeln"**
  zeigen je eine Tabelle **Query/Regel-ID · Bezeichnung · Kritikalität · Anzahl Nutzer** — nur
  Zeilen mit mindestens einem Treffer in diesem Lauf (neue Endpoints `GET /queries/summary` bzw.
  `GET /sodrules/summary`, `MATCH` statt `OPTIONAL MATCH` filtert 0-Treffer implizit über die
  Kardinalität weg). Klick auf eine Zeile springt in die normale Einzelfilter-/Findings-Ansicht,
  gefiltert auf genau diese Query/Regel (`jumpToQueryFilter`/`jumpToRuleFilter`, dieselbe
  `applyFilters()`-Logik wie die „nach User filtern"-Zelle in der Findings-Tabelle; setzt dabei
  bewusst auch stehengebliebene Kritikalitäts-/Sleeping-Filter zurück, sonst könnte ein Klick auf
  eine Regel mit echten Treffern durch einen unpassenden Alt-Filter „0 Findings" zeigen). Neue
  gemeinsame View `summaryView` in `.cols` verschachtelt (Sidebar bleibt sichtbar).
  **CSV-Export-Bugfix (Nutzer-Meldung: Export passte nicht zur angezeigten Tabelle), zwei
  unabhängige Ursachen:** (1) `GET /findings/export` nahm **keinerlei Filter-Parameter** entgegen
  — der Export dumpte immer den kompletten Lauf, unabhängig von der gerade angezeigten gefilterten
  Ansicht. Jetzt dieselbe `_FINDINGS_WHERE`-Klausel wie `GET /findings` (identische Parameter);
  ohne Parameter weiterhin alles (Abwärtskompatibilität). (2) Die Regel-**Bezeichnung** fehlte im
  Export komplett (nur die ID war drin, obwohl die Tabelle sie anzeigt) — neue Spalte `ruleName`.
  (3) Der Export-Button exportierte **immer** Findings, auch während die Einzelfilter-Matches-
  Tabelle sichtbar war — neuer Endpoint `GET /matches/export` (Pendant zu `GET /matches`,
  gleiche Parameter/Spalten wie die Matches-Tabelle) und `cmdExport` folgt jetzt exakt derselben
  Verzweigung wie `applyFilters()` (Einzelfilter → `/matches/export`, sonst → `/findings/export`),
  mit denselben Filterparametern wie die aktuell sichtbare Tabelle. Verifiziert gegen den
  laufenden Container: `/sodrules/summary` liefert 22 Regeln (deckt sich mit der bekannten
  Regelanzahl dieses Laufs), `/queries/summary` 38 Queries (deckt sich mit der bekannten
  Query-Anzahl); `userCount` einer Stichproben-Regel exakt gleich der Anzahl distinkter User im
  vorher exportierten Findings-CSV für diese Regel; `/findings/export` liefert ungefiltert 501,
  mit `ruleCriticality=very-critical` 63 Zeilen (deckt sich mit der vom Nutzer beigelegten CSV);
  `/matches/export` liefert für eine Query exakt die `userCount` aus der Summary-Tabelle.
- [x] **Ergebnisse-Übersicht: Kopf-Kachel mit distinkter Gesamtnutzerzahl — Nutzer-Wunsch.**
  `GET /queries/summary`/`GET /sodrules/summary` liefern jetzt `{totalUsers, rows}` statt einer
  reinen Liste; `totalUsers` ist die **distinkte** Userzahl über alle Zeilen (naives Aufsummieren
  von `userCount` je Zeile wäre falsch, da ein User i. d. R. mehrere Queries/Regeln gleichzeitig
  erfüllt/verletzt). Frontend zeigt das als Kachel (`.kpi`, wie im Konsistenzcheck-Ergebnis) über
  der Tabelle. Im selben Zuge geklärt: Nutzer-Rückfrage, warum von >600 Einzelberechtigungs-Queries
  im Vendor-Katalog nur 38 in der Übersicht auftauchen, während alle 22 SoD-Regeln erscheinen —
  **kein Bug**: „SoD-relevant" bedeutet hier (wie beim bestehenden `GET /queries`-Endpoint für die
  Einzelfilter-Dropdown-Auswahl) „als Klausel in mindestens einer SoD-Regel verwendet"; der
  Materialize-Schritt (`materialize_matches.cypher`) berechnet `MATCHES`-Kanten nur für genau diese
  Teilmenge, nicht für den gesamten Query-Katalog (Performance-Scoping). Verifiziert gegen den
  laufenden Container: 604 `Query`-Knoten im Ruleset insgesamt, aber nur 38 sind einer Klausel
  zugeordnet **und** genau diese 38 haben `MATCHES`-Kanten (kein Query außerhalb dieser Teilmenge
  wurde je materialisiert) — deckt sich mit den 22 von 22 SoD-Regeln, die alle mindestens einen
  Fund haben. `totalUsers` je Endpoint gegen einen realen Lauf geprüft (9.360 distinkte User über
  alle Einzelberechtigungen, 143 über alle SoD-Regeln — beide plausibel kleiner als die Summe der
  Einzelzeilen). Betrifft direkt den offenen Roadmap-Punkt „Katalog-Auswahl-UI (Scoping)": künftig
  soll die Query-Auswahl fürs Materialize erweiterbar sein, statt implizit auf SoD-Klauseln
  beschränkt zu bleiben.
- [x] **Rollen-Detailseite: Usernamen-Auflösung + anklickbare Nutzerliste — Nutzer-Wunsch.**
  „Zuweisung"-Zeile der Stammdaten (Gültigkeit der `ASSIGNED_TO`-Kante des betrachteten Users)
  zeigt jetzt ebenfalls „Name (ID)" statt der rohen ID (`GET /roles/{id}` liefert zusätzlich
  `forUserName`, per `OPTIONAL MATCH` wie bei Ersteller/Änderer). Die **Anzahl zugewiesener User**
  ist anklickbar und öffnet eine neue, wiederverwendbare **Nutzerliste-Seite** (`#userListView`,
  in `.cols` verschachtelt wie Root-Cause/Rollen-Detail) mit den Spalten **ID · Name ·
  Benutzertyp · Benutzergruppe · Letzter Login · Sleeping** (neuer Endpoint
  `GET /roles/{id}/users?runId=`, dataset über den Lauf aufgelöst; Sleeping-Definition identisch
  zum SoD-Root-Cause: `lastLogonKnown = lastLogon IS NOT NULL`,
  `sleeping = lastLogon vorhanden UND älter als sleepDays`).
  **Dieselbe Nutzerliste-Seite** wird auch aus den **Konsistenzchecks** heraus angeboten: hat ein
  Check-Ergebnis genau **eine** Summary-Kachel und ist die Detailtabelle eine Nutzerliste (Spalte
  `user` vorhanden — Heuristik, da Check-Ergebnisse strukturell sehr unterschiedlich sind, vgl.
  Rollenpaare/Objektlisten bei anderen Checks), wird die große Kennzahl anklickbar; die IDs aus der
  bereits geladenen Detailtabelle gehen an den neuen generischen Endpoint `POST /users/list`
  (Body `{dataset, ids}`), der sie mit denselben 6 Spalten frisch aus der Datenbank anreichert
  (liefert z. B. Benutzergruppe/Sleeping, die viele Check-Cyphers selbst nicht zurückgeben).
  Rückweg (`ulBackBtn`) merkt sich die Herkunft (`ulReturnTo`: „role" → zurück zur Rollen-
  Detailseite mit Sidebar, „consistency" → zurück zum Konsistenzcheck-Ergebnis ohne Sidebar,
  analog zum bestehenden `rcReturnTo`-Muster des Root-Cause). Verifiziert gegen den laufenden
  Container (nur IDs/Zahlen, keine Namen ausgegeben): `/roles/{id}/users` liefert für eine Rolle
  mit bekannter Zuweisungszahl (3) exakt 3 Zeilen mit allen 6 Feldern; `/users/list` liefert für
  eine gemischte ID-Liste (inkl. einer nicht existierenden ID) genau die tatsächlich vorhandenen
  Nutzer; `forUserName`/`createUsrName` lösen für einen bekannten User erfolgreich auf; ein echter
  Konsistenzcheck (B1, „aktive Dialog-User ohne Anmeldung") liefert genau eine Summary-Kachel +
  eine Detailtabelle mit `user`-Spalte (26.823 Zeilen) — Drilldown-Bedingung korrekt erkannt.

#### Interaktive Ergebnisse & Graph-UX (9.1)
- [x] **Sortierbare Spalten** in allen Ergebnistabellen (generische `makeSortable()`): umgesetzt für
  Ergebnis-Übersicht (Einzelfilter+SoD), Nutzerliste, Konsistenzcheck-Detail **und die
  Findings-/Matches-Haupttabelle** (`findingsTable`/`matchesTable`, je erste 5 Spalten;
  Sleeping/Root-Cause-Button bewusst nicht sortierbar; Kritikalität über `critRank`). **Standard-
  Klickzyklus je Spalte** (2026-07-12, generisch in `makeSortable()`): 1. Klick auf/steigend,
  2. Klick ab/fallend, **3. Klick zurück zur Ursprungsreihenfolge** (Pfeil verschwindet,
  `originalOrder`-Schnappschuss beim jeweiligen `reset()` je Tabelle) — Klick auf eine andere Spalte
  startet den Zyklus immer wieder bei „auf". Gilt automatisch für alle vier sortierbaren Tabellen.
  **Konsistenzcheck-Katalog (`ccGrid`) nachgezogen** (2026-07-15): dort keine einzelne feste Tabelle
  wie bei den übrigen vier, sondern mehrere dynamisch pro Kategorie nachgebaute Mini-Tabellen
  (`renderConsistencyTable()`, Neuaufbau bei jedem Kategorie-/Filterwechsel) — die generische
  `makeSortable()` setzt ein einziges, persistentes `<thead>` voraus und passt hier nicht direkt.
  Eigener, kleiner Sortier-Mechanismus je Box (`ccAttachBoxSort()`, gleicher 3-Klick-Zyklus, gleiche
  `genericCompare()`), unabhängig je Mini-Tabelle (Sortieren einer Kategorie-Box lässt die anderen
  unberührt). Prio-Spalte über neuen `ccPrioRank()` (Hoch/Mittel/Analytik/Niedrig), Ergebnisse-Spalte
  über die schon vorhandenen `ccdLastCounts`. Mit Playwright verifiziert (auf/ab/Reset-Zyklus,
  Box-Unabhängigkeit, Indikator-Pfeil, keine Konsolenfehler). Gilt jetzt als **Standard** für jede
  neue Ergebnisliste.
- [x] **Listenweiter Tabelle/Graph-Umschalter** über der Findings-Liste (`viewTogglePills`) —
  funktional und end-to-end verifiziert (2026-07-12), **UX laut Nutzer-Feedback noch nicht
  optimal** — welche Aspekte konkret (Layout/Farbwahl/Interaktion/Informationsdichte) ist noch
  offen zu klären, bevor der Punkt als abgeschlossen gilt. Bewusst **nicht** als Heatmap/User×
  Regeln-Matrix oder Cytoscape-
  Node-Graph umgesetzt: bei ~4.200 betroffenen Akteuren vs. wenigen Dutzend Regeln wäre ein Knoten
  je User unlesbar und eine literale Matrix ein DOM-Performance-Problem (Entscheidung nach
  Dataviz-Skill-Konsultation + Nutzerauswahl). Stattdessen ein **regel-/query-zentriertes
  Balkendiagramm** (`#findingsGraph`, `.fg-row`): eine Zeile je SoD-Regel bzw. Einzelfilter,
  Balkenlänge = betroffene Nutzerzahl (absteigend sortiert), Farbe = bestehende
  `CRIT_COLOR`-Statusfarbe (keine neue Palette). Datenquelle sind die schon vorhandenen
  `/sodrules/summary`/`/queries/summary`-Endpunkte (dieselben wie die „Ergebnisse-Übersicht") —
  **keine neue Backend-Aggregation**; folgt damit `resultTypeValue` (SoD vs. Einzelfilter) und
  bleibt bewusst unabhängig von den Sidebar-Filtern (Untertitel weist explizit darauf hin).
  Klick auf einen Balken nutzt die bestehenden `jumpToRuleFilter`/`jumpToQueryFilter` (inkl. des
  neuen Zurück-Buttons darüber). „Als Tabelle"-Link führt zur bestehenden Ergebnisse-Übersicht
  (Tabellen-Fallback laut Dataviz-Skill-Anforderung). Mit Playwright gegen den laufenden Container
  end-to-end verifiziert (Sortierung, Farben, Drill-down, Modus-Wechsel, keine Konsolenfehler).
  **UX-Feedback konkretisiert (2026-07-15):** Balken „sehen langweilig aus" — noch keine konkrete
  Alternative vom Nutzer benannt, bleibt offen zu erarbeiten (nicht Farbe, grundsätzlich die
  Balkenform). **Bug gefunden+gefixt:** `currentFindingsGraphMode()` prüfte nur `resultTypeValue`
  (SoD/Einzelfilter-Pill) — dieser Pill ist aber nur eingeblendet, sobald `isEntry=false`
  (`toggleEntryUi()`), was nur `renderFindingsTable()` setzt, **nicht** `renderMatchesTable()`. Wer
  stattdessen über das (immer sichtbare) Sidebar-Dropdown „Einzelberechtigung" (`filterQuery`) eine
  Query auswählt, landet zwar korrekt in der Matches-Ansicht, aber `resultTypeValue` bleibt `''` —
  der Graph zeigte dann weiterhin die **SoD**-Regeln statt der erwarteten Einzelfilter-Übersicht.
  Fix: `currentFindingsGraphMode()` prüft jetzt zusätzlich `$('filterQuery').value`, exakt dieselbe
  Bedingung wie in `applyFilters()` (`if (q || resultTypeValue === 'query')`). Mit Playwright gegen
  den laufenden Container in beide Richtungen verifiziert (Query über Sidebar ausgewählt → Graph
  zeigt jetzt 43 Einzelfilter-Balken statt 3 SoD-Balken; zurückgesetzt → wieder SoD-Balken).
- [x] **„Baum"-Ansicht als dritte Option neben Tabelle/Balken** (2026-07-15, löst das „langweilig"-
  Feedback zum Balkendiagramm über eine Alternative statt eines Redesigns — Nutzer hatte noch keine
  konkrete Balken-Alternative, wollte stattdessen einen auf-/zuklappbaren Baum): Regel/Query → User →
  belegende Rolle(n)/Profil(e), Akkordeon (pro Ebene immer nur ein Geschwisterzweig offen). Ebene 1
  übernimmt 1:1 die bewährte Balkenoptik (Länge/Farbe/Sortierung). Ebene 2 (User) kostet **keinen
  neuen Endpunkt**: SoD über `GET /findings?rule=Y&limit=100000` (statt des bisherigen globalen
  `&limit=500`, liefert je Zeile bereits `roles`/`profiles`-Arrays aus der materialisierten
  VIA_ROLE/VIA_PROFILE-Evidenz, AE-11 — Ebene 3 braucht dort **keinen** Request mehr), Einzelfilter
  über das bereits ungedeckelte `GET /matches?query=Y`; Client-seitiges Suchfeld ab 30 Usern (bis zu
  ~8.000 möglich). Ebene 3 bei Einzelfilter live über `GET /root-cause` (dieselbe Pro-User-Berechnung
  wie die interaktive Root-Cause-Seite), dedupliziert auf Rolle/Profil, generierte Profile
  ausgeblendet (Default `rcTechMode='hide'`). Direkt zugewiesenes Profil wird als eigener,
  nicht-klickbarer Chip-Typ gezeigt (kein Profil-Detail existiert app-weit, bewusste Scope-Grenze).
  Klick auf User/Rolle öffnet ein **kompaktes Overlay** (nicht die volle `roleDetailView`-Seite, die
  würde den Akkordeon-Zustand darunter verstecken) mit Stammdaten — neuer, schlanker Endpunkt
  `GET /users/{id}/detail` fürs User-Overlay (USR02-Rohfelder: Typ/Gruppe/Gültigkeit/Login/Sleeping/
  Passwort-Historie), Rollen-Overlay nutzt den bestehenden `GET /roles/{id}?user=`. Zusätzlich eine
  **"Vollansicht"** (Cytoscape) für genau den aktuell aufgeklappten Pfad (Regel/Query + 1 User +
  dessen Rollen/Profile, nie alle User gleichzeitig — bei ~8.000 Usern unlesbar, derselbe Grund wie
  beim Balkendiagramm) mit **Farblegende** (User/Regel/Query/Rolle/Profil) und dem bewährten
  Zoom-Slider-/Vollbild-Muster der Root-Cause-Seite 1:1 übernommen. **Nebenbei gefundener Bug:**
  verschachtelte `.overlay`-Dialoge (User-/Rollen-Overlay aus der Vollansicht heraus geöffnet)
  blockierten sich gegenseitig (gleicher z-index, App-Muster geht von immer nur einem offenen Dialog
  aus) — Fix: Vollansicht schließt sich selbst, bevor das verschachtelte Overlay öffnet. Mit
  Playwright end-to-end verifiziert (Akkordeon-Verschachtelung beide Ebenen, SoD- und
  Einzelfilter-Modus, beide Overlays, Vollansicht-Graph inkl. Knoten-Klick/Zoom/Legende, Regression
  auf „Balken"/„Tabelle").

  ROADMAP-Punkt „Farblegende in allen Graphansichten" (s. u.) damit für den **listenweiten** Graphen
  erledigt; Pfad-/Radial-Ansicht der Root-Cause-Seite bleiben wie unten offen.
- [x] **Zurück-Button im Drill-down** — „← zurück" in der Aktiv-Filter-Leiste stellt die Ausgangsliste
  wieder her (Filter-Historie als Stack, Schnappschuss vor jedem Sprung; erkennt auch die
  Übersichts-Sicht als Ursprung). Erledigt 2026-07-12.

> **Kritikalität prominent an Einzelfilter/SoD** ist nach **9.4** verschoben (2026-07-12) — Farben/
> Stufen kommen aus den dortigen Kritikalitäts-Stammdaten, vorher wäre die Badge-Logik hartkodiert.

#### 9.2 „Fancy" Cytoscape.js-Frontend + NeoDash-Ablösung (komplett, 2026-07-16)
- [x] **Gebrandetes Cytoscape.js-Frontend mit Konfliktpfad-Graph** — bereits über die Root-Cause-Seite
  (Tabelle/Pfadgraph/Radial, `rcViewPills`) und die 9.1-Baumvollansicht abgedeckt (KPI-Kacheln,
  Konfliktpfad-Darstellung inkl. `VIA_ROLE`/`VIA_PROFILE`-Evidenzkanten, Drill-down per Knotenklick)
  — löst den NeoDash-PoC (`dashboards/sod_poc.json`) vollständig ab, kein separater Baustein mehr
  nötig.
- [x] **Farblegende in allen Graphansichten (komplett)** — Pfad-/Radial-Ansicht der Root-Cause-Seite
  ergänzt (`rcRenderLegend()`/`#rcLegend`, neun Einträge: User/SoD-Regel/Klausel/Einzelfilter/
  Berechtigungsobjekt/Rolle/Profil sowie die beiden Rand-Modifier „technisch generiert" (gestrichelt)
  und „verwaist" (roter Rand) — deckungsgleich mit den Cytoscape-Knotenklassen aus `rcCyStyle()`.
  Farbzuordnung aus der bestehenden Baum-Vollansichts-Legende in eine gemeinsame `graphNodeColor()`
  ausgelagert (ein Source of Truth für Legende **und** tatsächliche Knotenfarbe). Nur sichtbar im
  Graph-Modus (mit Tabelle/Pfadgraph/Radial-Umschalter synchronisiert).
- [x] **Vollbild-Bedienung der Graphen überarbeitet** — der bisherige Vollbild-Knopf schwebte
  absolut positioniert **über** dem Graph-Canvas (`.rc-graph-fsbtn`, verdeckte teils den Inhalt);
  jetzt ein Toggle-Button (`.pill.graph-fsbtn`, aktiver Zustand optisch hervorgehoben) fest in der
  Ansichts-Leiste (`resultbar`/Pillgroup-Zeile) für alle drei Graphansichten — Root-Cause
  (`rcFullscreenBtn`), Baum-Vollansicht (`ftfvFullscreenBtn`, neben dem Dialogtitel) und
  Konsistenzcheck-Graph (`ccdGraphFullscreen`, neben dem Tabelle/Graph-Umschalter). ESC zum
  Verlassen war über die native Fullscreen-API schon immer vorhanden (Browser-Standardverhalten),
  neu ist nur die Platzierung/das Toggle-Feedback. Die kleineren „Einpassen"/Zoom-Regler bleiben
  bewusst am Canvas-Rand (kein Nutzer-Feedback dazu, anders als beim Vollbild-Knopf).
- [x] **NeoDash vollständig entfernt** — Compose-Service `iam-neodash` (Port 5005) samt laufendem
  Container gestoppt/entfernt, `dashboards/sod_poc.json` gelöscht (Git-Historie bleibt als Referenz),
  Erwähnungen in `README.md`/`docs/handbuch/ueberblick.md`/`docs/technik/architektur.md`
  (Laufzeitdiagramm) sowie in `docs/phasen/phase-9.md` bereinigt bzw. auf den heutigen Stand
  aktualisiert; historische Phasendoku (`docs/phasen/phase-0.md`, `phase-3.md`, Phase 6 im Archiv)
  bewusst **unverändert** gelassen — dokumentiert den damaligen Bau-Stand, wird wie die
  Git-Historie nicht rückwirkend umgeschrieben. `AE-14`-Pin-Hinweis auf Neo4j/APOC reduziert
  (NeoDash-Image-Tag entfällt).
  Mit Playwright gegen den laufenden Container verifiziert: Legende zeigt in Pfad- **und**
  Radial-Ansicht alle 9 Einträge mit den erwarteten Beschriftungen; Vollbild-/Legende-Sichtbarkeit
  korrekt an Tabellen- vs. Graph-Modus gekoppelt (`display:none` im Tabellenmodus); Vollbild-Klick
  setzt `document.fullscreenElement` + `.active`-Klasse korrekt (und wieder zurück beim Verlassen);
  Konsistenzcheck-Graph-Toggle strukturell identisch geprüft (Button-Sichtbarkeit/Position wechselt
  korrekt mit dem Tabelle/Graph-Pill); Port 5005 nicht mehr erreichbar, kein `iam-neodash`-Container
  mehr vorhanden, App (`iam-backend`/`iam-neo4j`) läuft unverändert weiter, keine neuen
  Konsolenfehler.
- [x] **Vier Nachbesserungen aus dem ersten echten Test** (2026-07-16, direkt im Anschluss, alle vom
  Nutzer beim Ausprobieren gefunden):
  - **Legende im Vollbild unsichtbar** — `#rcLegend`/`#ftfvLegend` waren Geschwister des
    Fullscreen-Elements; die native Fullscreen-API rendert nur Element+Nachfahren, Geschwister
    verschwinden. Fix: Legende als schwebende Leiste (`.graph-legend-bar`) in
    `rcGraphWrap`/`ftfvGraphWrap` verschoben (analog zum bestehenden Zoom-Slider-Muster); dabei
    einen toten ftfv-Fullscreen-Höhen-CSS-Selektor mitkorrigiert (Klasse saß direkt auf dem
    Element, nicht auf einem Nachfahren, griff also nie).
  - **Overlay wurde bei reinem Risiko-Edit trotzdem vollgeschrieben** — Nutzer bemerkte, dass
    `queries.custom.json`/`sod_rules.custom.json` beim Speichern auch unveränderte Felder
    (Kurzbezeichnung/Kritikalität/Modul/…) explizit übernahmen, weil der Editor immer den vollen
    Formularschnappschuss sendet (nicht nur das geänderte Feld). Risiko: eine spätere
    Vendor-Korrektur an diesen Feldern wäre durch den unbeabsichtigten Overlay-Eintrag dauerhaft
    verdeckt geblieben. Fix: `admin_update_query`/`admin_update_sodrule` vergleichen jetzt gegen
    den aktuell gemergten Wert und schreiben nur noch **tatsächlich geänderte** Filterset-Felder
    ins Overlay.
  - **Root-Cause-Graph färbte den Einzelfilter-Wurzelknoten wie eine SoD-Regel** — `rcBuildGraph()`
    setzte die Klasse des Wurzelknotens (`rc_top`) hart auf `rc-rule`, unabhängig vom tatsächlichen
    Modus; fiel erst durch die neue Farblegende auf (Nutzer: „SoD und Einzelfilter vertauscht").
    Die Baum-Vollansicht hatte diese Unterscheidung schon korrekt (`ftfvState.topClass`). Fix:
    Klasse jetzt abhängig von `topIsRule` (`rc-rule` vs. `rc-query`).
  - **Kantenlabel „ODER" zwischen Objekt/BO und Rolle war irreführend** — beschrieb nur die Menge
    paralleler Kanten insgesamt, nicht die einzelne Kante. Per `AskUserQuestion` geklärt: Label auf
    Englisch **„CONTAINS"** (passend zu AE-04, Kanten als englische Verben wie
    `ASSIGNED_TO`/`HAS_AUTH`) **und** Pfeilspitze visuell ans Objekt-Ende verschoben
    (`source-arrow-shape`/`target-arrow-shape:none`, neue Klasse `.rc-contains`) — Quelle/Ziel der
    Kante selbst bleiben unverändert, damit das breadthfirst-Baum-Layout (Objekt bleibt
    Elternknoten des Akteurs) nicht bricht. Gilt einheitlich für Berechtigungsobjekte **und**
    S_TCODE-Prüfungen (beide über dieselbe `attachObject()`-Funktion).
  Alle vier mit Playwright/API-Tests gegen den laufenden Container verifiziert (Legende bleibt im
  aktiven Vollbild sichtbar; ein reiner `riskLevel`-Edit landet nachweislich ausschließlich in
  `risks.json`, `queries.custom.json` bleibt byte-identisch; Wurzelknoten-Klasse korrekt je Modus;
  `CONTAINS`-Kanten mit korrekter Klasse/Quelle/Ziel). Testartefakt (testweise geänderter
  `riskLevel` bei `1005_BC-SEC`) danach zurückgesetzt.

#### 9.3 „Can-Do nach Org" (2026-07-16)
- [x] **„Can-Do nach Org"** — „wer kann *Funktion* in *Buchungskreis X*", aufbauend auf dem
  bestehenden Org-Varianten-Mechanismus (Entscheidung 2026-07-11: eigener `(:Run)` je Kombination,
  kein Live-Post-hoc-Filter). Es fehlte nur die **kombinierte Ansicht** über mehrere Varianten
  eines Batches hinweg — bisher musste man nach einem `POST /runs/batch`-Lauf manuell zwischen den
  resultierenden Einzelläufen hin- und herschalten.
  - **`batchId` am Run-Knoten** (neues, explizites Korrelationsfeld): `(:Run)`-Knoten eines Batches
    hatten bisher keine gemeinsame ID, nur implizit denselben `runId`-Präfix
    (`{ruleset}-{ts}-{i}-{slug}`). `do_run_batch()` berechnet jetzt einmalig
    `batch_id = f"{ruleset}-{ts}"` (wiederverwendet die ohnehin vorhandene `ts`-Variable, bleibt
    auch beim Resume stabil) und reicht sie durch `_run_one()` an
    `cypher/sod/evaluate_sod_init.cypher` weiter (`SET run.batchId = $batchId`). Einzelläufe
    (`POST /runs`) übergeben nichts → Property bleibt ungesetzt, kein Migrations-/Backfill-Bedarf
    für bestehende Runs.
  - **Neuer Endpunkt `GET /runs/{runId}/org-compare?query=<id>` bzw. `?rule=<id>`** — analog zu
    `GET /root-cause` (Query ODER Regel als Alternative): löst über `run.batchId` alle
    Geschwister-Läufe auf und zählt pro Variante die betroffene User-Zahl (Zähllogik 1:1 aus
    `queries_summary()`/`sod_rules_summary()` übernommen, nur über alle Batch-Runs statt eines
    einzelnen `runId`, in einer Cypher-Abfrage statt N Einzelrequests). **Stolperstein:** `query`
    als Cypher-Parametername kollidierte mit dem intern gleichnamigen ersten Positionsparameter
    von `Session.run()` im Neo4j-Treiber (`TypeError: got multiple values for argument 'query'`) —
    Parameter auf `queryId` umbenannt.
  - **UI:** neuer „Org-Vergleich"-Button in der Aktiv-Filter-Leiste (`#filterActive`), sichtbar nur
    wenn der aktive Lauf zu einem Batch gehört **und** genau eine Query oder Regel als Filter aktiv
    ist (`applyFilters()`, `hideFilterActive()` blendet ihn konsistent mit aus). Öffnet
    `dlg-org-compare`: sortierbare Tabelle (Org-Variante · betroffene User · „Treffer anzeigen"),
    Zeilenklick wechselt den aktiven Lauf (`showFindings()`) und wendet denselben Query-/Regel-Filter
    dort erneut an (`jumpToOrgVariant()`, analog zu `jumpToQueryFilter()`/`jumpToRuleFilter()`, nur
    zusätzlich mit Laufwechsel).
  - Mit einem echten 2-Varianten-Testbatch gegen den laufenden Container verifiziert: `batchId`
    korrekt geteilt zwischen den Geschwister-Runs, ungesetzt bei bestehenden Alt-Runs;
    `org-compare`-Zählung deckungsgleich mit einer unabhängigen Gegenprobe über
    `GET /matches?runId=&query=` je Variante; 404 bei einem Einzellauf ohne `batchId`. Playwright:
    Button erscheint nur bei Batch-Lauf + Einzelfilter, Dialog zeigt korrekte Zeilenzahl,
    Zeilenklick wechselt Lauf und Filter korrekt und schließt den Dialog, Gegenprobe (Einzellauf)
    hält den Button ausgeblendet. Test-Batch (2 Runs) danach über `POST /runs/{runId}/delete`
    wieder entfernt.

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
