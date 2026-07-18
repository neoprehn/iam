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
- [ ] **Mehrsprachigkeit** — Deutsch/Englisch-Umschalter für UI-Texte, Kataloglabels und Reports.

**Übergangshinweis:** Query- und SoD-Overlays liegen heute git-getrackt unter den Rulesets
(`queries.custom.json`, `sod_rules.custom.json`, `risks.json`, Scope-Profile). Mandantenspezifische
Bewertungen dürfen dort nur landen, wenn sie keine Mandantendaten enthalten; konkrete
Interview-/Kontrollumgebungsdaten gehören in die lokale DB.

---

## Phase 2 — Threat Modeling

**Ziel:** Einzelfilter und SoD-Regeln fachlich erklären: Wie kann eine Berechtigung durch einen
Threat-Actor über einen Threat-Vector ausgenutzt werden?

- [ ] **Threat-Modeling-Reiter** an Einzelfilter und SoD-Regel.
- [ ] **Graphbasierter Attack Tree** als primäre Methode: Die SoD-Logik ist bereits ein AND/OR-Baum
  (Regel = AND über Klauseln, Klausel = OR über Queries, Query = AND über Objekte, Objekt = OR über
  erfüllende Rollen/Profile). Dadurch kann die vorhandene Baum-/Cytoscape-Erfahrung wiederverwendet
  werden.
- [ ] **STRIDE als Klassifikations-Overlay** je Knoten; PASTA bleibt vorerst zu schwergewichtig für
  den fokussierten Use Case.
- [ ] **Eigenes JSON-Schema** für Threat-Bäume im Overlay-Mechanismus, nicht im bestehenden
  `risk`-Freitextfeld. Knoten sollten mindestens Typ, Beschreibung, AND/OR-Struktur und optional
  Wahrscheinlichkeit, Impact und Gegenmaßnahme tragen.
- [ ] Vor dem Bau: Schema festlegen, Editor-UX skizzieren, publizierte Neo4j-/GitHub-Attack-Tree-
  Ansätze sichten.

---

## Phase 3 — Vergleich, Interview-Ergebnisse und erweiterte Exporte

**Ziel:** Ergebnisse über Stände/Mandanten hinweg vergleichbar machen und fachliche Rückmeldungen
aus Interviews wiederverwendbar speichern.

- [ ] **System-/Mandant-/Jahresvergleich** — Vergleichs-Abfragen über zwei `dataset`:
  neue/entfallene Konflikte, Delta je Regel/User, Delta je Query.
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
- [ ] **Zentrales Benutzer-/Berechtigungskonzept nur bei Mehrbenutzerbetrieb** — lokal bewusst ohne
  eigenes Auth-Konzept; bei zentralem Betrieb Auth-Schicht über SSO/OIDC am Ingress.
- [ ] **Kubernetes/Helm konkretisieren** — Neo4j als StatefulSet mit PVC, Backend als Deployment,
  Secrets, NetworkPolicy, Ingress nur intern bzw. hinter Unternehmens-Auth.
- [ ] **Mandantendaten zwischen eigenen Arbeitsgeräten synchron halten** — nur bei Bedarf über
  verschlüsselten `neo4j-admin dump/load`-Mechanismus; keine Cloud-Sync- oder Git-Ablage.
- [ ] **Runner-`.sh`-Varianten** — optional; App-Endpunkte bleiben die maßgebliche,
  plattformunabhängige Variante.

---

## Phase 7 — Technischer Backlog

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
