# Roadmap — SAP-Berechtigungsanalyse mit Neo4j

**Projekt:** Graphbasierte Auswertung von SAP-Berechtigungen (R/3 und S/4HANA) — Can-Do (Berechtigung) und Did-Do (Nutzung), inklusive SoD-Konfliktanalyse.
**Repository:** `neoprehn/iam` (aktuell einziger vorhandener Baustein).
**Zielplattform:** Windows (Container-only über Docker Desktop / WSL2 — siehe Abschnitt „Windows-Spezifika").
**Stand:** Initiale Roadmap, abgeleitet aus der Konzeptionsphase.

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
- [x] Importvalidierung (Zähler je Knoten-/Kantentyp) — `load/99_validate.cypher`.
- [x] SE16-Konverter `load/Convert-Se16Export.ps1` (unkonvertiert → UTF-8/Tab/CSV); container-only via cypher-shell + APOC (kein Python).
- [x] Phase in der Doku dokumentiert (`docs/phasen/phase-2.md`) — Dokumentations-DoD.

**DoD:** Beide Berechtigungspfade (rollenbasiert + direkt) vollständig im Graphen; stichprobenartig gegen SAP nachvollziehbar. ✓ verifiziert am dataset `sachsenenergie` (90.700 Authorizations, 72.109 `ASSIGNED_TO`, 63.088 `HAS_PROFILE`, 192.230 `CHECKS`).

> **Hinweis:** `08_authorizations` (AGR_1251) ist der zeitintensivste Schritt; Performance-Optimierung (Zwei-Pass) als Folgearbeit offen.

---

### Phase 3 — Auswertungslogik (Checks & SoD)
**Ziel:** Einzelberechtigungs-Checks und SoD-Konfliktanalyse.

- [ ] Excel-Regelkatalog nach `rules/sod_matrix.csv` überführen (Regel-ID → kritische TCode-/Objekt-Kombination → Risikobeschreibung).
- [ ] Kritische TCodes/Objekte beim Import mit `:Critical` taggen (Einstiegspunkte).
- [ ] `cypher/checks/`: Einzelberechtigungs-Checks, stichtagsparametrisiert.
- [ ] `cypher/sod/`: SoD-Abfragen mit korrekter Pfad-Gültigkeitsschnittmenge (AE-08) und `*`-Normalisierung (AE-06).
- [ ] Intra- vs. Inter-Rollen-Konflikt sauber unterscheiden (AE-11).
- [ ] Findings in die Snapshot-Schicht schreiben: `(:SoDConflict {ruleId, asOf, runId})` mit `VIOLATED_BY`/`VIA_ROLE`/`BASED_ON_RULE`; Regelkatalog als `(:Rule)`-Knoten.
- [ ] `DETACH DELETE` der Snapshot-Schicht vor jedem Lauf (AE-10).

**DoD:** Reproduzierbarer SoD-Lauf zu einem frei wählbaren Stichtag mit vollständiger Nachweiskette (Regel, Pfade, Stichtag, Run).

---

### Phase 4 — Did-Do (Nutzung aus STAD/ST03N)
**Ziel:** Nutzungssicht und Can-Do×Did-Do-Matrix.

- [ ] Extraktionsweg festlegen: ST03N-Aggregate (`SWNC_COLLECTOR_GET_AGGREGATES`, `ENTRY_ID`=TCode/Report, `TASKTYPE`) als pragmatischer Einstieg; bei Bedarf regelmäßige Roh-STAD-Extrakte; für Forensik SAL/`CDHDR`.
- [ ] `EXECUTED`-Kanten (User→Transaction) mit `count`, `firstSeen`, `lastSeen`, `taskType`, `asOf`, `runId` in die Snapshot-Schicht.
- [ ] Matrix-Abfragen: ungenutzte Berechtigungen (Least-Privilege-Kandidaten), materialisierte SoD (Did-Do auf beiden Konfliktseiten).
- [ ] Caveats dokumentieren: Aufbewahrungsfenster (≥1 Jahr für Abschlussprozesse), selten-aber-vital, indirekte Aufrufe nicht erfasst, kein Audit-Log (AE-13), S/4-Fiori/OData-Ebene.
- [ ] **Datenschutz/Mitbestimmung** (§ 87 BetrVG): benutzerbezogene Nutzungsauswertung als Hinweis an den Mandanten; Pseudonymisierung der User-ID für Statistik, Klartext nur im begründeten Einzelfall.

**DoD:** Matrix-Auswertung lauffähig; ungenutzte kritische Berechtigungen und materialisierte SoD-Konflikte werden ausgewiesen.

---

### Phase 5 — Runner & Orchestrierung
**Ziel:** Ein Befehl rechnet die gesamte Auswertung.

- [ ] `run/run_all.ps1` (Windows, primär) und `run/run_all.sh` (Linux/macOS, optional für andere User).
- [ ] Pipeline: `migrate` → `load` (lokale CSV) → `checks/sod` → `did-do` → Snapshot.
- [ ] `cypher-shell` über den Container per Pipe aufrufen, z. B.:
  ```powershell
  Get-Content .\load\01_users.cypher | docker exec -i iam-neo4j cypher-shell -u neo4j -p "$env:NEO4J_PASSWORD"
  ```
  Runner = Schleife über die `load/`- und `cypher/`-Dateien nach diesem Muster.
- [ ] Secrets aus `.env`/Umgebungsvariablen (`$env:NEO4J_PASSWORD`); kein Klartext im Skript.
- [ ] Parametrisierbarer Stichtag und `runId`.
- [ ] Logging/Zusammenfassung je Lauf (Anzahl Findings, betroffene User/Rollen).

**DoD:** Frischer Lauf auf einem zweiten Rechner liefert identische Ergebnisse (gleiche Daten vorausgesetzt).

---

### Phase 6 — Darstellung (Dashboards)
**Ziel:** Versionierte, ansprechende Ergebnisdarstellung.

- [ ] NeoDash lokal an die DB anbinden.
- [ ] Dashboard-Inhalte: KPI-Kacheln (User mit SoD-Konflikt, kritische Einzelberechtigungen, Top-Konflikttypen), Konflikt-Tabelle mit Drill-down, Graph-Visualisierung der Konfliktpfade (kritische Pfade farblich), SoD-Heatmap/Matrix, Parameter-Selektoren (Stichtag, Organisationseinheit, Risikoklasse).
- [ ] Dashboard als JSON exportieren → `dashboards/` committen.
- [ ] (Optional, später) gebrandetes Frontend mit NVL/React.

**DoD:** Dashboard reproduzierbar aus dem Repo herstellbar; Darstellung ist versioniert.

---

### Phase 7 — Verteilung & Reproduzierbarkeit
**Ziel:** Weitergabe an andere Rechner/User ohne Datenweitergabe.

- [ ] `docker-compose.yml` mit gepinnten Versionen finalisieren.
- [ ] Onboarding-`README`: klonen → `docker compose up` → eigene SAP-Extrakte nach `data/import` → Runner → Dashboard-JSON importieren.
- [ ] Klarstellen: Über Repo/Compose wandert nur Logik/Umgebung, nie Mandantendaten.
- [ ] Verfahren für Ergebnisübergabe (`neo4j-admin database dump`, verschlüsselt, unter Auflagen) dokumentieren — Ausnahmefall.

**DoD:** Ein Kollege bringt das Projekt auf einem eigenen Rechner identisch zum Laufen, ohne dass Mandantendaten das Repo berühren.

---

## Zielarchitektur — Repo-Struktur

```
iam/
├─ ROADMAP.md
├─ README.md                   # Onboarding
├─ docker-compose.yml          # Neo4j + NeoDash, Versionen gepinnt
├─ .gitignore                  # /data, .env, *.dump
├─ .gitattributes              # Zeilenenden (LF für .cypher/.sh) für Linux-Container
├─ .env.example
├─ migrations/                 # neo4j-migrations: Constraints, Indizes
├─ load/                       # LOAD CSV-Skripte (Daten liegen lokal)
├─ rules/                      # Regelkatalog (sod_matrix.csv)
├─ cypher/
│   ├─ checks/                 # Einzelberechtigungs-Checks
│   └─ sod/                    # SoD-Abfragen
├─ dashboards/                 # NeoDash-Export (JSON)
├─ run/                        # run_all.ps1 (primär) / run_all.sh
├─ docs/                       # datamodel.md, Extraktionsleitfaden
└─ data/                       # GITIGNORED: SAP-CSV + DB-Volume + Import
```

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