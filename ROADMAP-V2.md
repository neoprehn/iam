# Roadmap V2 — SAP-Berechtigungsanalyse mit Neo4j

**Zweck:** Diese Datei sammelt die Themen, die **noch nicht** in der aktuellen v1-Roadmap umgesetzt
werden sollen. Sie beginnt bewusst wieder bei **Phase 1**, damit ein späterer Übergang ohne
Rückgriff auf verstreute Backlog-Notizen möglich ist.

**Startpunkt für V2:** V2 setzt auf dem dann stabilen v1-Stand aus [`ROADMAP.md`](ROADMAP.md) auf:
lokale Web-App, container-only, Import/Resume, geführte Auswertung, Scope-Profile,
Konsistenzchecks, interaktive Ergebnisse, Masterdata-/Query-/SoD-Administration, Backup/Restore und
CSV/PDF/XLSX-Exporte. Abgeschlossene v1-Arbeit bleibt in [`ROADMAP-ARCHIV.md`](ROADMAP-ARCHIV.md)
nachvollziehbar.

**Nicht verhandelbare Rahmenbedingungen für V2:**
- **Vertrauensgrenze bleibt bestehen:** Repo enthält nur Logik/Umgebung/Darstellung, niemals
  Mandantendaten. Lokale DB, SAP-Extrakte, Backups und Interview-Ergebnisse bleiben außerhalb von
  Git.
- **Container-only auf Windows:** Neo4j, Migrations und Backend laufen über Docker Desktop/WSL2;
  keine lokale Neo4j-/Java-Pflicht.
- **Dokumentations-DoD bleibt bestehen:** Umsetzung gilt erst als fertig, wenn die passende Doku in
  `docs/` aktualisiert, committed und gepusht ist.
- **SAP-Rohdatenmodell bleibt Ausgangspunkt:** R/3 und S/4 teilen die klassische
  Berechtigungsstruktur (`AGR_*`, `USR02`, `UST*`, `USOB*`). S/4/Fiori ergänzt Zugriffswege, ersetzt
  das Grundmodell aber nicht.
- **V2-Arbeit startet erst nach bewusstem Startsignal.** Diese Datei ist Parkfläche und
  Übergabenotiz, kein Auftrag zur sofortigen Umsetzung.

---

## Phase 1 — Admin-Editor V2 und Regelpflege

**Ziel:** Query-/SoD-Pflege von Metadaten zu vollständiger, kontrollierter Filterpflege ausbauen.

- [ ] **Authorizations/TCodes im Editor bearbeitbar** — der heutige Aufbau-Tab ist read-only;
  V2 ergänzt Bearbeitung für verschachtelte Objekt/Feld/Wert-Listen sowie Transaktionen.
- [ ] **USOBT-gestützter Query-Builder** — Transaktion auswählen und daraus relevante
  Berechtigungsobjekte/Felder ableiten, statt Objekt/Feld/Wert-Strukturen vollständig als Freitext
  anzulegen.
- [ ] **Query → System-Typ-Zuordnung** — Zuordnung zu R/3, S/4HANA usw. als Stammdatenblatt;
  Filter und Katalogansichten sollen systemtypabhängig einschränkbar sein.
- [ ] **Filterset-/Konnektor-Import weitere Systeme** — S/4HANA, Azure AD/Entra, Microsoft
  Dynamics, Salesforce. Vor jedem neuen Konnektor erst Datenmodell, Vertrauensgrenze und
  Minimal-Extrakt definieren.
- [~] **Mehrsprachigkeit** — Deutsch/Englisch-Umschalter für UI-Texte, Kataloglabels und Reports.
  **Status (2026-07-20):** Schritte (1)–(3) bereits umgesetzt, vorgezogen auf v1 (parallel zum
  formalen V2-Start): Grundgerüst (`frontend/i18n.js`, `i18n/de.json`+`en.json`,
  Masterdata-Default über `ui.defaultLanguage`) sowie **alle fünf** Frontend-Seiten vollständig
  lokalisiert — `index.html`, `admin.html`, `admin-masterdata.html`, `admin-org-profiles.html`,
  `admin-scopes.html` (statisches HTML + JS-Strings, DE/EN-Parität geprüft, keine Konsolenfehler,
  Playwright-Spotcheck inkl. dynamischem Re-Render bei Sprachwechsel). **Offen bleibt nur Schritt
  (4)** (Backend-Fehlermeldungen + PDF/CSV-Reports, `?lang=`-Parameter) — siehe unten.
  - **Ansatz:** Leichtgewichtiges, key-basiertes i18n ohne Framework/Build-Step. Übersetzungen
    liegen in `frontend/i18n/de.json` + `en.json` (flache Keys → Text, mit Platzhaltern wie
    `{n}`). Statisches HTML wird über `data-i18n="key"`-Attribute beim Laden ersetzt;
    JS-generierte Strings laufen über einen `t('key', {…})`-Helper statt fester Literale.
    `<html lang>` wird aus der aktiven Sprache gesetzt (wirkt u. a. auf `localeCompare`).
  - **Vorgabe-/Umschaltlogik:** Default-Sprache der Installation als Stammdatenblatt
    (`config/masterdata.json` → Block `ui` mit `defaultLanguage` + verfügbare Sprachen, pflegbar
    über die bestehende Masterdata-Seite und das `GET|PUT /admin/masterdata/*`-Muster). Ein
    DE/EN-Toggle im Header überschreibt pro Sitzung und wird in `localStorage` gehalten. Die
    Übersetzungstexte selbst gehören in die i18n-JSONs, nicht in die Stammdaten (Trennung:
    Stammdaten = Konfiguration/Fachkatalog, i18n = Übersetzungen).
  - **Backend/Reports:** Sprache als Parameter (`?lang=de|en`) an die Report-Endpunkte; ein
    analoges kleines serverseitiges Dictionary für Fehlermeldungen und PDF/CSV-Beschriftungen.
  - **Umsetzungsreihenfolge:** (1) Grundgerüst + Umschalter + Masterdata-Default, (2) statisches
    HTML, (3) JS-Strings Datei für Datei (Brocken: `index.html`), (4) Backend-Meldungen + Reports.
  - **Abgrenzung:** UI-Chrome (Labels/Menüs) zuerst. Katalog-**Fachtexte** (Query-Beschreibungen,
    Risk-Texte; KPMG_R3 deutsch, CSI/CSI_BI englisch) sind ein separater, größerer Aufwand —
    mehrsprachige Felder nur ergänzen, wo Übersetzungen existieren, sonst Fallback auf die
    vorhandene Sprache. Nicht mit der UI-Übersetzung vermischen.

**Übergangshinweis:** Query- und SoD-Overlays liegen heute git-getrackt unter den Rulesets
(`queries.custom.json`, `sod_rules.custom.json`, `risks.json`, Scope-Profile). Mandantenspezifische
Bewertungen dürfen dort nur landen, wenn sie keine Mandantendaten enthalten; konkrete
Interview-/Kontrollumgebungsdaten gehören in die lokale DB.

---

## Phase 2 — Threat Modeling

**Ziel:** Einzelfilter und SoD-Regeln fachlich erklären: Wie kann eine Berechtigung durch einen
Threat-Actor über einen Threat-Vector ausgenutzt werden? Aus der reinen „diese Kombination ist
riskant"-Aussage wird ein nachvollziehbarer Angriffspfad inkl. Gegenmaßnahmen.

**Anknüpfung an v1 (wichtig):** Das Risiko-Datenmodell trägt bereits die Felder `risk` (Kurztitel),
`riskType`/`riskLevel`/`riskStatus`, `source` (Referenzen) und — als bewussten Vorläufer der
Threat-Analyse — `threat` (Freitext, Schritt-für-Schritt-Angriffspfad) in `risks.json`. Dieses
`threat`-Feld wird im Rahmen von 9.4 inhaltlich gepflegt und ist der **Seed**, den V2 zu einer
strukturierten Threat-Modellierung formalisiert (Freitext → Attack-Tree-Knoten). Nichts davon wird
verworfen.

- [ ] **Threat-Modeling-Reiter** an Einzelfilter und SoD-Regel (neben den bestehenden Tabs
  „Risiko"/„Controls"), gespeist aus `threat`/`source` und dem neuen Attack-Tree-Overlay.
- [ ] **Threat-Actor-/Threat-Vector-Taxonomie** als Masterdata (analog Kritikalität/Reason-Code):
  z. B. Innentäter mit Fachzugang, Administrator, externer Angreifer über ein kompromittiertes
  Konto — je mit typischem Vorgehen. So bleiben Akteure/Vektoren katalogpflegbar statt Freitext.
- [ ] **Graphbasierter Attack Tree** als primäre Methode: Die SoD-Logik ist bereits ein AND/OR-Baum
  (Regel = AND über Klauseln, Klausel = OR über Queries, Query = AND über Objekte, Objekt = OR über
  erfüllende Rollen/Profile). Die vorhandene Baum-/Cytoscape-Erfahrung (9.1/9.2) wird
  wiederverwendet; ein Angriffspfad ist eine Traversierung durch genau diesen Baum.
- [ ] **STRIDE als Klassifikations-Overlay** je Knoten (Spoofing/Tampering/…); PASTA bleibt vorerst
  zu schwergewichtig für den fokussierten Use Case.
- [ ] **Eigenes JSON-Schema** für Threat-Bäume im Overlay-Mechanismus, **nicht** im bestehenden
  `risk`-/`threat`-Freitextfeld. Knoten mindestens: Typ, Beschreibung, AND/OR-Struktur und optional
  Wahrscheinlichkeit, Impact, verknüpfte Gegenmaßnahme (`controls`) und Referenz (`source`).
- [ ] **Bewertung/Priorisierung** — je Pfad Likelihood × Impact (an die vorhandenen KRI-Scores der
  Kritikalitäts-Masterdata anlehnen), damit Findings nicht nur „kritisch", sondern nach
  Angriffswahrscheinlichkeit sortierbar werden.
- [ ] **Report-Sicht** — Angriffspfad + Gegenmaßnahmen exportierbar (an die bestehenden PDF/CSV/
  XLSX-Reports anschließen).
- [ ] Vor dem Bau: Schema festlegen, Editor-UX skizzieren, publizierte Neo4j-/GitHub-Attack-Tree-
  Ansätze sichten.

---

## Phase 3 — Vergleich, Interview-Ergebnisse und erweiterte Exporte

**Ziel:** Ergebnisse über Stände/Mandanten hinweg vergleichbar machen und fachliche Rückmeldungen
aus Interviews wiederverwendbar speichern.

- [ ] **Vergleich zweier Berechtigungskonzepte (System-/Mandant-/Jahresvergleich)** — ein `dataset`
  ist der Extrakt genau *eines* Berechtigungskonzepts zu einem Stichtag; der Konzeptvergleich läuft
  daher als Vergleichs-Abfrage über zwei `dataset` (z. B. altes vs. neues Konzept, zwei Systeme/
  Mandanten, Vorjahr vs. Folgejahr): neue/entfallene Konflikte, Delta je Regel/User, Delta je Query.
- [ ] **Interview-Ergebnisse einarbeiten** — pro Finding/Feld Reason Code aus den Masterdata plus
  Begründung hinterlegen, inklusive Autor/Datum.
- [ ] **Wiedervorlage im Folgejahres-Dataset** — frühere Begründungen/Klassifikationen wieder
  anziehbar machen und Abweichungen sichtbar markieren.
- [ ] **Ablage nur lokal:** Interview- und Mandantenergebnisse gehören in die lokale Neo4j-DB oder
  lokale Exportdateien, nicht ins Repo.
- [ ] **Weitere Export-Sichten** — Top-Regeln, Matrix-Sichten, ggf. nativer Excel-Export für
  Import-Evidenz und gebündelte Report-Pakete.
- [ ] **Business-Objects/Feldwerte im Detail-Export** — nicht nur Objektname, sondern bei Bedarf die
  belegenden Berechtigungsobjekt-Feldwerte ausgeben. Performance-Grenzen aus v1 beachten:
  Mega-Queries wurden bewusst gedeckelt, Root-Cause bleibt der interaktive Detailweg.

---

## Phase 4 — Neuer Extraktor und Did-Do

**Ziel:** Can-Do, Konsistenzchecks und später Did-Do mit einem passgenauen SAP-Extraktor versorgen.

- [ ] **Datenanforderungen erheben** — je (1) Can-Do, (2) Did-Do, (3) Konsistenzchecks die benötigten
  Tabellen/Spalten zusammentragen.
- [ ] **RTD-Kapitel Datenanforderungen** — nachvollziehbar dokumentieren, welche Tabelle wofür
  benötigt wird.
- [ ] **Extraktor überarbeiten/neu schreiben** — unter `data/extractors`; darf gepusht werden,
  solange keine Mandantendaten enthalten sind.
- [ ] **Config konsolidieren** — `config/Download Data CSI.xls` und `config/required_tables.json`
  zusammenführen; je Tabelle Felder inklusive späterer Did-Do-Felder aufnehmen. Vorab die aktuell
  unversionierte Excel-Datei inhaltlich sichten und sicherstellen, dass sie keine Mandantendaten
  enthält.
- [ ] **Did-Do-Quelle festlegen** — ST03N-Aggregate (`SWNC_COLLECTOR_GET_AGGREGATES`) als Einstieg;
  bei Bedarf Roh-STAD; für Forensik SAL bzw. `CDHDR`/`CDPOS`.
- [ ] **`EXECUTED`-Kanten modellieren** — User→Transaction mit `count`, `firstSeen`, `lastSeen`,
  `taskType`, `asOf`, `runId` in der Snapshot-Schicht.
- [ ] **Can-Do×Did-Do-Matrix** — ungenutzte Berechtigungen, Least-Privilege, materialisierte SoD auf
  beiden Konfliktseiten.
- [ ] **Caveats dokumentieren** — Aufbewahrungsfenster, selten-aber-vital, indirekte Aufrufe,
  STAD/ST03N ist kein Audit-Log (AE-13), S/4-Fiori/OData.
- [ ] **Datenschutz/Mitbestimmung** — Pseudonymisierung der User-ID; Klartext nur im begründeten
  Einzelfall.

**Blocker:** V2-Did-Do startet erst, wenn ein echter STAD/ST03N-Auszug oder ein abgestimmter
Alternativextrakt verfügbar ist.

---

## Phase 5 — S/4HANA und weitere Zielsysteme

**Ziel:** Den klassischen SAP-R/3-Kern kontrolliert auf S/4- und Nicht-SAP-Zielsysteme erweitern.

- [ ] **S/4-Fiori/OData-Ebene** modellieren: Fiori-Tile → Target Mapping → OData-Service →
  Backend-Objekt (`S_SERVICE`, `/UI2/*`).
- [ ] **S/4-spezifische Regelwerte** pflegen: neue Objekte/Transaktionen wie `BP` statt `XD01`/
  `XK01` ändern Werte im Regelkatalog, nicht das Grundmodell.
- [ ] **SACF/SLDW** bei S/4-Vollständigkeit beachten.
- [ ] **Azure AD/Entra, Dynamics, Salesforce** erst nach separatem Mini-Design je System:
  Identitäten, Rollen/Groups/Privileges, Nutzungssignale, Importformat, lokale Speicherung.

---

## Phase 6 — Betrieb, Verteilung und Security-Ausbau

**Ziel:** Betrieb über den lokalen Einzelplatz hinaus vorbereiten, ohne die Vertrauensgrenze zu
verwässern.

- [ ] **Security-Checks weiter ausbauen** — z. B. zusätzliche SAST-Regeln/Tools wie Semgrep,
  feinere Policy-Schwellen und CI-Härtung. v1-Basis: AST-Guardrail + Bandit.
- [ ] **Kubernetes/Helm konkretisieren** — Neo4j als StatefulSet mit PVC, Backend als Deployment,
  Secrets, NetworkPolicy, Ingress nur intern bzw. hinter Unternehmens-Auth.
- [ ] **Mandantendaten zwischen eigenen Arbeitsgeräten synchron halten** — nur bei Bedarf über
  verschlüsselten `neo4j-admin dump/load`-Mechanismus; keine Cloud-Sync- oder Git-Ablage.
- [ ] **Runner-`.sh`-Varianten** — optional; App-Endpunkte bleiben die maßgebliche,
  plattformunabhängige Variante.

---

## Phase 7 — Mehrbenutzerbetrieb und zentrale Authentifizierung

**Ziel:** Den in v1 bewusst fehlenden Auth-Layer erst dann einführen, wenn die App vom lokalen
Einzelplatz zum zentral betriebenen Mehrbenutzer-Dienst wird — ohne die Vertrauensgrenze zu
verwässern.

**Ausgangslage (v1, bewusst):** Die App hat **kein eigenes Benutzer-/Berechtigungskonzept**. Sie
läuft lokal bzw. als Container hinter der Vertrauensgrenze; Zugriffsschutz ist heute die lokale
Umgebung selbst (kein offener Netzzugang). Für den Einzelplatzbetrieb ist das korrekt und soll nicht
künstlich verkompliziert werden.

- [ ] **Auslöser definieren** — erst bei zentralem/gemeinsamem Betrieb (mehrere Prüfer, geteilter
  Server/Cluster) wird ein Auth-Layer nötig; für den Einzelplatz bleibt er bewusst aus.
- [ ] **Authentifizierung am Ingress (SSO/OIDC)** — Anbindung an den Unternehmens-IdP (OIDC/SAML)
  vor dem Backend; die App selbst verwaltet keine Passwörter. Baut auf die K8s-/Ingress-Arbeit aus
  Phase 6 auf.
- [ ] **Autorisierung/Rollen in der App** — mindestens Lesen vs. Pflege (Query-/SoD-/Masterdata-
  Editor, Import, Clear/Reset); Mapping aus IdP-Gruppen. Vorab entscheiden, wie feingranular
  (Dataset-/Mandantentrennung je Nutzer?).
- [ ] **Mandantentrennung bei geteiltem Betrieb** — wie werden mehrere Mandanten-Datasets auf einem
  gemeinsamen Server voneinander und gegen unbefugte Einsicht abgeschirmt (Berufsgeheimnis)?
- [ ] **Audit/Nachvollziehbarkeit** — wer hat wann welchen Lauf/Edit/Export ausgelöst; relevant,
  sobald mehrere Personen auf denselben Stand zugreifen.

**Abgrenzung:** Reine Deployment-/Netz-Härtung (K8s, NetworkPolicy, Ingress-Betrieb) bleibt in
Phase 6; hier geht es um das fachliche Benutzer-/Berechtigungskonzept der App selbst.

---

## Phase 8 — Technischer Backlog

Sinnvoll, aber nicht Startvoraussetzung für V2.

- [ ] **CSI-Rulesets CNF-zerlegen** — `clauses` in `sod_rules.json` für `csi`/`csi_bi`, damit die
  SoD-Auswertung auch über diese Kataloge vollständig läuft. KPMG ist bereits scharf; die Mechanik
  ist generisch.
- [ ] **Kritische TCodes/Objekte taggen** (`:Critical`) — Ansatz offen: Kritikalität steckt bereits
  im Ruleset; vor Umsetzung entscheiden, ob ein zusätzliches ruleset-unabhängiges Tagging nötig ist.
- [ ] **AE-08 prüfen** — Pfad-Gültigkeitsschnittmenge bei verschachtelten Sammelrollen sauber über
  jede relevante Kante des Pfades validieren.
- [ ] **Modellerweiterungen bei Bedarf** — `AuthField`/`ObjectClass`/`OrgValue`-Pivot,
  `Service`/`FioriTile` für S/4 als neue Migrationen.
- [ ] **Performance Variantenaufbau** — Laufzeit bei vielen Org-Varianten weiter optimieren, z. B.
  gemeinsame Vorfilterung und Wiederverwendung org-unabhängiger Zwischenergebnisse.

---

## Übergabe-Checkliste beim Start von V2

1. `git pull` bzw. `git fetch` + Abgleich mit `origin/main`.
2. [`ROADMAP.md`](ROADMAP.md), [`ROADMAP-ARCHIV.md`](ROADMAP-ARCHIV.md) und diese Datei lesen.
3. Jüngste Git-Historie prüfen (`git log --oneline --decorate -n 20`).
4. Prüfen, ob lokale unversionierte Dateien Mandantendaten enthalten; nichts ungeprüft committen.
5. Laufende Container/App-Version validieren, bevor größere Datenmodell- oder UI-Änderungen starten.
6. Für jede V2-Phase zuerst kleinstes fachliches Datenmodell/Schema festlegen, dann UI/API bauen.
