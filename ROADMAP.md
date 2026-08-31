# Roadmap — SAP-Berechtigungsanalyse mit Neo4j

**Projekt:** Graphbasierte Auswertung von SAP-Berechtigungen (R/3 und S/4HANA) — Can-Do (Berechtigung) und Did-Do (Nutzung), inklusive SoD-Konfliktanalyse.
**Repository:** `neoprehn/iam`.
**Zielplattform:** Windows (Container-only über Docker Desktop / WSL2 — siehe „Windows-Spezifika").

**Abgrenzung:** Diese Datei steuert den aktuellen v1-Ausbau. Spätere Themen sind in
[`ROADMAP-V2.md`](ROADMAP-V2.md) ausgelagert und werden erst nach bewusstem Startsignal umgesetzt.

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

**AE-14 — Reproduzierbarkeit über gepinnte Versionen.** Docker-Image-Tags (Neo4j, APOC) fixieren.

**AE-15 — Container-only auf Windows.** Neo4j/`neo4j-migrations` als Container; keine lokale Neo4j-/Java-Installation. `cypher-shell` über den Container.

**AE-16 — Der Stichtag (`asOf`) ist eine Eigenschaft des Datasets, kein Lauf-/Check-Parameter.** Ein Dataset ist ein SAP-Extrakt zu einem festen Downloaddatum — eine Auswertung gegen ein *anderes* Datum als den eigenen Extraktstand ergibt ohne Änderungs-Tracking (`RSUSR100N`/Change Documents über die Zeit im selben Dataset) keinen Erkenntnisgewinn. `(:Dataset).asOf` wird einmalig bei Erst-Import gesetzt — explizit übergeben oder automatisch aus den Dateizeitstempeln des Import-Ordners abgeleitet (`_infer_dataset_asof()`: alle Tabellen eines Extrakts teilen sich praktisch immer denselben Exporttag), nur falls der Quellordner fehlt als letzter Ausweg `heute` — und bleibt über Re-Importe stabil. Ältere Datasets ohne den Wert (vor Einführung dieses Felds importiert) bekommen ihn lazy über denselben Mechanismus nachgetragen. `RunReq`/`ConsistencyRunReq` nehmen kein `asOf` mehr vom Client an, sondern lösen es serverseitig über `_dataset_asof()` auf. Bewusste Korrektur ausschließlich global über `PUT /datasets/{id}/asof` — wirkt auf alle folgenden Läufe/Checks dieses Datasets.

---

## Offene Arbeit

### Phase 9 — App: offene Bausteine

Die App-Grundfunktionen stehen (siehe Archiv). Offen sind die folgenden Ausbauten.

#### Import-Evidenz — erledigt (2026-07-12)
Vollständigkeitsnachweis gegen Quell-SAP: persistente Import-Statistik je Lauf, eigene
Konsistenzcheck-Kategorie „Import" (I1) sowie dedizierter Import-Evidenz-Report (JSON/CSV/PDF).
Details im [Archiv](ROADMAP-ARCHIV.md#import-evidenz-2026-07-12).

Die folgenden offenen Ausbauten wurden am **2026-07-12** mit den handschriftlichen Notizen aus
`ideen.md` zusammengeführt und in thematische Arbeitspakete **9.1–9.8** gegliedert.
**Reihenfolge (Nutzer-Steuerung):** zunächst **9.1 + 9.2** (Interaktive Ergebnisse / Graph-Frontend),
danach **9.3 ff.** in gelisteter Folge; die geplanten Phasen 10/8/X schließen sich an.
**9.1–9.3 und 9.6 sind abgeschlossen; 9.5/9.7/9.8 sind nach V2 ausgelagert** (s. „Kürzlich
erledigt" + Archiv) — **aktiv ist 9.4 (Risikokatalog inhaltlich befüllen), das inkrementell
Schritt für Schritt befüllt wird (s. `new_chat_rule.md`).**

#### Kürzlich erledigt (Kontext, Details im Archiv)
- **Geführte Auswertung** — Assistent-Stepper, Katalog-Auswahl, zwei Auswertungsarten, persistente
  Scope-Profile, verfeinerter Katalog-Browser, Voreinstellung inkl. Benutzergruppe/Sleeping,
  scope-treue Sidebar-Filter, **Multi-Varianten-Läufe** (jede Variante ein eigener benannter `(:Run)`;
  **Titel/Beschreibung nachträglich editierbar** — `PATCH` auf den Run-Knoten), **Nutzer-Scope
  verfeinern** (Sleeping-Schnellwahl, Sperrtyp-Filter), **Evidenz default-on** (Evidenz-Perf:
  `/explain` ~90–100s → ~27,6s). [Archiv](ROADMAP-ARCHIV.md#geführte-auswertung).
- **Interaktive Drill-downs** — Findings-/Regel-/KPI-Klick, Root-Cause inkl. Pfad-/Radialgraph
  (Cytoscape). [Archiv](ROADMAP-ARCHIV.md#interaktive-ergebnisse-drill-down--graphtabelle).
- **Import-Evidenz** — Kategorie „Import"/I1, PDF/CSV-Report.
  [Archiv](ROADMAP-ARCHIV.md#import-evidenz-2026-07-12).
- **9.1 Interaktive Ergebnisse & Graph-UX (komplett)** — sortierbare Spalten überall inkl.
  Konsistenzcheck-Katalog, Zurück-Button im Drill-down, Balkendiagramm + neue aufklappbare
  Baum-Ansicht (Regel/Query → User → Rolle/Profil) samt Cytoscape-Vollansicht+Farblegende.
  [Archiv](ROADMAP-ARCHIV.md#interaktive-ergebnisse--graph-ux-91).
- **9.2 „Fancy" Cytoscape.js-Frontend + NeoDash-Ablösung (komplett, 2026-07-16)** — Konfliktpfad-Graph
  bereits über die Root-Cause-Seite abgedeckt, Farblegende jetzt auch in Pfad-/Radial-Ansicht,
  Vollbild-Toggle aus allen drei Graphansichten in die Ansichts-Leiste verschoben (statt schwebend
  über dem Canvas), NeoDash-Service/-Dashboard/-Doku-Erwähnungen vollständig entfernt. Plus vier
  Nachbesserungen aus dem ersten echten Test (Legende blieb im Vollbild unsichtbar, Overlay wurde
  bei reinem Risiko-Edit trotzdem vollgeschrieben, Einzelfilter-Wurzelknoten fälschlich rot
  eingefärbt, Kantenlabel „ODER" → „CONTAINS").
  [Archiv](ROADMAP-ARCHIV.md#92-fancy-cytoscapejs-frontend--neodash-ablösung-komplett-2026-07-16).
- **Security-Basischeck Backend (2026-07-17)** — automatischer Sicherheits-Guardrail als Test
  umgesetzt: AST-Prüfung auf riskante Muster (u. a. `eval`/`exec`, `os.system`,
  `subprocess(..., shell=True)`, unsichere Deserialisierung) plus Bandit-Scan mit
  `backend/bandit.yaml`. **Weiterer Ausbau (z. B. zusätzliche Tools/strengere Policies)
  ist bewusst nach hinten verschoben.**
- **Mehrsprachigkeit DE/EN — UI-Chrome (2026-07-19/20)** — vorgezogen auf v1 (Thema stand
  eigentlich als V2-Punkt in [`ROADMAP-V2.md`](ROADMAP-V2.md#phase-1--admin-editor-v2-und-regelpflege)
  geparkt, wurde aber parallel begonnen): leichtgewichtige key-basierte i18n-Runtime
  (`frontend/i18n.js`, `frontend/i18n/de.json`+`en.json`, DE/EN-Parität geprüft) plus
  `data-i18n`/`data-i18n-attr`/`data-i18n-html`-Attribute und `I18N.t()` für alle JS-Strings.
  **Alle fünf Frontend-Seiten vollständig lokalisiert:** `index.html`, `admin.html`,
  `admin-masterdata.html`, `admin-org-profiles.html`, `admin-scopes.html` — inkl. dynamisch
  nachgeladener Inhalte (Listen/Tabellen/Badges/Hints), die bei Sprachumschalter live neu
  gerendert werden. Verifiziert per Playwright gegen den laufenden Container (DE→EN-Umschalter je
  Seite, keine Konsolenfehler). **Offen (ausgelagert, s. [ROADMAP-V2](ROADMAP-V2.md#phase-1--admin-editor-v2-und-regelpflege)):**
  Backend-Fehlermeldungen und PDF/CSV-Reports laufen noch nur auf Deutsch.

#### 9.3 Org-Varianten & „Can-Do nach Org" — abgeschlossen (2026-07-17)
- [x] Umsetzung vollständig abgeschlossen (Org-Varianten-Batch, Org-Vergleich, verschachtelte
  Org-Kriterien, UI/UX-Verbesserungen, Import/Export von Varianten, Editierbarkeit von Namen/
  Beschreibungen).
- [x] Detailnachweis in [ROADMAP-ARCHIV.md](ROADMAP-ARCHIV.md#93-can-do-nach-org-2026-07-16).
- **Ausgelagert nach V2:** die Performance-Optimierung des Variantenaufbaus (Laufzeit bei vielen
  Org-Varianten, gemeinsame Vorfilterung/Wiederverwendung org-unabhängiger Zwischenergebnisse) steht
  in [`ROADMAP-V2.md`](ROADMAP-V2.md#phase-8--technischer-backlog).

#### 9.4 Masterdata-Verwaltung (Admin)
Zentrale, editierbare Stammdaten statt verstreuter Freitexte/Konstanten — Basis für Dropdowns,
Badges an Einzelfilter/SoD und den Reason-Code (9.6).

Bereits erledigt (Details im Archiv/Commits): Risiko-Metadaten im Editor inkl. `risks.json`-
Konsolidierung, Datenschutz-Feld, `riskLevel`-Harmonisierung, Badge-Überarbeitung. Ebenfalls
erledigt: Kritikalitäts-/Reason-Code-/Modul-/Querytyp-Stammdaten (eigene Masterdata-Seite +
Backend-API), Dropdowns statt Freitext, neue SoD-Filter als Ableitung bestehender Regeln anlegen.
[Archiv](ROADMAP-ARCHIV.md#94-masterdata-stammdaten-juli-2026).

- [ ] **Risikokatalog inhaltlich befüllen** — offene Pflege für Query-Risiken (alle Rulesets) und
  KPMG_R3-SoD-Risiken; `riskType`/`riskLevel` generisch, `riskStatus` mandantenbezogen nur aus
  lokal validierter Kontrollumgebung.
- [ ] **Kritikalität prominent an Einzelfilter/SoD** — Badge-Logik aus Findings in Katalog,
  Auswahl und Ergebniszeilen übernehmen.
- **Ausgelagert nach V2:** Mehrsprachigkeit, bearbeitbare Authorizations/TCodes,
  USOBT-gestützter Query-Builder, System-Typ-Zuordnung und Konnektoren für weitere Systeme stehen
  in [`ROADMAP-V2.md`](ROADMAP-V2.md#phase-1--admin-editor-v2-und-regelpflege).

#### 9.5 Threat Modeling (ausgelagert nach V2)
Threat Modeling wird in v1 nicht begonnen. Der vollständige Übergabestand steht in
[`ROADMAP-V2.md`](ROADMAP-V2.md#phase-2--threat-modeling).

#### 9.6 Export — abgeschlossen (2026-07-19)
System-/Mandant-Vergleich, Interview-Ergebnisse und weitere V2-Exportsichten sind ausgelagert nach
[`ROADMAP-V2.md`](ROADMAP-V2.md#phase-3--vergleich-interview-ergebnisse-und-erweiterte-exporte).
Der in v1 vorgezogene Teil (nativer XLSX-/CSV-Export der Ergebnis-Übersicht) ist abgeschlossen
(2026-07-15): Format-Dialog (CSV/Excel/ausführliches Excel mit verschachtelter Nutzer-/Rollen-
Aufschlüsselung) beim Export der Einzelfilter-/SoD-Übersicht, plus ein nebenbei behobener
Drill-down-Race-Bug. Details im [Archiv](ROADMAP-ARCHIV.md#96-export-2026-07-15).

#### 9.7 Betrieb & Mehrbenutzer (ausgelagert nach V2)
Das (bewusst fehlende) eigene Benutzer-/Berechtigungskonzept ist ein reines Mehrbenutzer-/
Zentralbetrieb-Thema: lokal/Container braucht es keinen Auth-Layer. Der vollständige Übergabestand
(Auslöser, SSO/OIDC am Ingress, App-Rollen, Mandantentrennung, Audit) steht in
[`ROADMAP-V2.md`](ROADMAP-V2.md#phase-7--mehrbenutzerbetrieb-und-zentrale-authentifizierung).

#### 9.8 Neuer SAP-Extraktor (ausgelagert nach V2)
Der neue Extraktor, Config-Konsolidierung und Did-Do-Vorbereitung werden in v1 nicht begonnen. Der
vollständige Übergabestand steht in [`ROADMAP-V2.md`](ROADMAP-V2.md#phase-4--neuer-extraktor-und-did-do).

**DoD (Phase 9):** Eine transportable App, in der Import, parametrierte Auswertung, Vergleich, Anzeige,
Export und Backup/Restore ohne JSON-Pflege bedienbar sind — lokal, ohne dass Mandantendaten die Umgebung
verlassen.

---

### Phase 10 — Verteilung & Reproduzierbarkeit
**Ziel:** Weitergabe an andere Rechner/User ohne Datenweitergabe.

- [ ] `docker-compose.yml` mit gepinnten Versionen finalisieren.
- [ ] Onboarding-`README`: klonen → `docker compose up` → eigene SAP-Extrakte (Ordner/ZIP) → App.
- [ ] Klarstellen: Über Repo/Compose wandert nur Logik/Umgebung, nie Mandantendaten.
- [~] **Verfahren für Ergebnisübergabe** (`neo4j-admin database dump`/`load`, verschlüsselt, unter
  Auflagen) — **Ablauf 2026-07-12 live end-to-end verifiziert** (Container stoppen,
  `docker compose run --rm -v <host>:/hostout neo4j neo4j-admin database dump neo4j
  --to-path=/hostout`, Restore via `load --overwrite-destination=true` in Test-Volume, Knotenzahl
  1:1 bestätigt). Community Edition kann keine einzelne Datenbank pausieren (`STOP DATABASE`
  ist Enterprise-only) — daher immer der ganze `neo4j`-Container kurz gestoppt. Noch offen: als
  RTD-Seite dokumentieren statt nur Chat-Verlauf.
- **Ausgelagert nach V2:** regelmäßige Mandantendaten-Synchronisierung zwischen eigenen Arbeitsgeräten
  steht in [`ROADMAP-V2.md`](ROADMAP-V2.md#phase-6--betrieb-verteilung-und-security-ausbau).

**Deployment-Optionen.** Verteilungseinheit ist heute **Docker Compose** (lokal, ein Befehl). Der Stack
ist **Kubernetes-fähig** (interner, abgesicherter Cluster):
- **neo4j** als `StatefulSet` mit **PVC** (Community = Single-Instance), Passwort als `Secret`.
- **backend** als `Deployment` (vorerst **1 Replica** — Jobs in-memory; für Skalierung Job-Status in Shared Store). Code/Config ins Image backen; `data/import` + `backups` als **PVC**. Hinweis: `neo4j` braucht Import-Verzeichnis und `rules/` ebenfalls als Volume.
- **Zugang** über `Service`/`Ingress` **nur clusterintern bzw. hinter Unternehmens-Auth** (SSO/OIDC, NetworkPolicy). „public" = interner, gesicherter Cluster — **nicht** offenes Internet.
- Optional: Helm-Chart/Kustomize.

**DoD:** Ein Kollege bringt das Projekt identisch zum Laufen, ohne dass Mandantendaten das Repo berühren.

---

### Phase 8 / Backlog — ausgelagert nach V2
Did-Do, neuer Extraktor, Security-Ausbau, CSI-CNF, technische Modell-Erweiterungen und sonstige
Backlog-Themen stehen gesammelt in [`ROADMAP-V2.md`](ROADMAP-V2.md). In v1 werden sie nicht begonnen.

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

 iam-migrations (Schema, profile: tools)
```

## Zielarchitektur — Repo-Struktur

```
iam/
├─ ROADMAP.md / ROADMAP-ARCHIV.md / README.md 
├─ docker-compose.yml          # neo4j + backend (+ migrations als tools-Profil), gepinnt
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

Die konkrete S/4-/Fiori-Erweiterung ist V2-Thema: [`ROADMAP-V2.md`](ROADMAP-V2.md#phase-5--s4hana-und-weitere-zielsysteme).

---

## Offene Punkte / Annahmen

- Verfügbarkeit/Format der SAP-Extrakte (SE16/Reports) je Mandant. **Feld-/Where-Spezifikation je
  Tabelle dokumentiert** (2026-07-20, `config/required_tables.json` → neuer `fields`-Block, reine
  Doku für den SAP-Downloadauftrag, keine Laufzeitwirkung): abgeglichen gegen
  `config/Download Data CSI.xls` und die tatsächlich von `load/*.cypher` gelesenen Spalten. Dabei
  Lücken der XLS-Vorlage gefunden und ergänzt (u. a. `AGR_USERS.EXCLUDE`, `AGR_TCODES.EXCLUDE`,
  `AGR_DEFINE`-Stammdatenfelder, `USR02`-Passwortfelder — ohne die bricht der bestehende Ladeprozess
  bzw. verliert Funktionalität). Sechs bislang ungenutzte Tabellen aus der XLS neu als `optional`
  aufgenommen (`ADRP`, `AGR_FLAGS`, `AGR_1250`, `AGR_1016B`, `T000`, `USR06`) — noch **ohne**
  `load/*.cypher`-Loader, nur dokumentiert; `AGR_1016B` bewusst mit Verwechslungswarnung gegenüber
  dem bereits genutzten `AGR_1016` (frühere Bug-Historie, s. Kommentar in
  `load/22_role_profile_status.cypher`).
- Umfang Org-Ebenen-Pivot (ob `OrgValue`-Knoten benötigt werden).
- S/4-Scope und Datenschutz-/Mitbestimmungsabstimmung für Did-Do sind in V2 ausgelagert.

---

## Glossar (Kurz)

- **Can-Do / Did-Do:** Was eine Berechtigung erlaubt vs. was tatsächlich ausgeführt wurde (STAD/ST03N).
- **SoD:** Segregation of Duties — unzulässige Funktionstrennung.
- **Intra-/Inter-Rollen-Konflikt:** Konflikt innerhalb einer Rolle vs. erst durch Rollenkombination.
- **Snapshot-Schicht:** Abgeleitete, regenerierbare Ergebnisse mit Provenienz (Stichtag, Run).
- **Evidenz:** Belegt pro Finding die verursachenden Rollen/Profile (`VIA_ROLE`/`VIA_PROFILE`) und intra/inter.
