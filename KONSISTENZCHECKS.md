# Qualitäts- & Konsistenzprüfungen — SAP-Berechtigungsanalyse

Lebendes Dokument: der vollständige Katalog der **Konsistenzchecks** (Diagnose-Checks,
überwiegend read-only, zur Absicherung von Datenqualität und zur Aufdeckung fachlicher
Risikobefunde — unabhängig von einer konkreten SoD-Regel). Referenziert aus
[`ROADMAP.md`](ROADMAP.md), Phase 7 (dort steht der technische Rahmen). **Diese Datei wird
unabhängig von der ROADMAP weitergepflegt** — neue Checks hier ergänzen.

**Operative Quelle für die App** sind die strukturierten Kataloge unter [`checks/`](checks/)
(ein JSON je Kategorie, Schema in [`checks/SCHEMA.md`](checks/SCHEMA.md)) — diese Markdown-Datei
ist die **ausführliche, lesbare Fassung mit Begründung**. Beim Ergänzen/Ändern eines Checks
**beides pflegen**: hier (Begründungstext) und im passenden `checks/<Kategorie>.json`
(Kurzform für die UI). Es gibt (noch) keine automatische Synchronisierung.

Die `Prio` ist grobe Triage; der reale Schweregrad hängt von Mandant und
Produktiv-/Nicht-Produktiv-Status ab. `Umsetzung` ist der technische Stand der Check-Logik
(Backend/Cypher), unabhängig von Prio.

Zwei getrennte Bereiche, je ein eigener Ribbon-Punkt (Gruppe 4, s. u.):

- **„User-spezifisch"** — Kategorien A–E (Reihenfolge = Anzeige in der App: 2×2-Raster + `E`
  zentriert darunter): **A** kritische Berechtigungen · **B** Benutzerstamm-Hygiene · **C**
  Zuweisungskonsistenz (User ↔ Rolle/Profil) · **D** Gültigkeit/Zeitbezug · **E** referenzielle
  Integrität.
- **„Rollen-spezifisch"** — Kategorie `R` (Rollenqualität/-design, eigener Abschnitt unten,
  s. „Konsistenzchecks für Rollen"), aktuell die einzige Rollen-Kategorie; die UI rastert hier
  über das Feld `group` in **vier Themenboxen** im 2×2-Raster (Struktur & Generierung,
  Zuordnung & Reichweite, Risiko & SoD, Wartbarkeit & Design) statt einer einzigen langen Tabelle.

Die IDs sind stabil (kategoriebezogen), unabhängig von Reihenfolge-Änderungen in der Anzeige.

`Umsetzung`: `[ ]` offen · `[~]` teilweise (z. B. Cypher vorhanden, aber kein UI-Drill-down) ·
`[x]` erledigt.

---

## A — Kritische & weitreichende Berechtigungen

| ID | Prüfung | Bedeutung & warum relevant | Prio | Umsetzung |
|----|---------|----------------------------|------|-----------|
| A1 | Wer hat **`SAP_ALL`** | Vollzugriff auf praktisch alles — höchstes Einzelrisiko. Muss auf wenige, begründete (idealerweise Notfall-)User beschränkt und nachweisbar sein. Klassischer Erstbefund jeder Prüfung. | Hoch | [x] |
| A2 | Wer hat **`SAP_NEW`** | Überbrückt neue Berechtigungsprüfungen nach Upgrades. Produktiv/dauerhaft zugewiesen hebelt es Sicherheitsverschärfungen aus — gehört nur temporär in der Übergangsphase eingesetzt. | Hoch | [x] |
| A3 | Wer hat **SAP-Standardprofile** außer `SAP_ALL`/`SAP_NEW` (z. B. `S_A.SYSTEM`, `S_A.ADMIN`, `S_A.DEVELOP`) | Weitreichende Admin-/Entwickler-Rechte über Auslieferungsprofile. Sollten nicht breit gestreut sein; oft unbemerkt mitgeschleppt. | Hoch | [x] |
| A4 | User mit **kritischen Einzelberechtigungen** aus dem Regelkatalog (z. B. Debug-Replace `S_DEVELOP ACTVT 02`, weite `S_TABU_DIS`/`S_TABU_NAM`, `S_USER_GRP`) | Gezielte Hochrisiko-Objekte/-Aktivitäten unterhalb der Profilebene. Debug-Replace etwa erlaubt Laufzeit-Manipulation und umgeht fachliche Kontrollen. | Hoch | [x] |
| A5 | **Berechtigung weiter als der Benutzertyp es nahelegt** (z. B. Batch-/RFC-Profil auf Dialog-User oder umgekehrt) | Typkonflikt; deutet auf Fehlzuweisung und erschwert die saubere Trennung technischer vs. menschlicher Konten. | Mittel | [x] |
| A6 | User mit **`*` auf kritischen Org-Ebenen** (z. B. `BUKRS=*`) bei sensiblen Objekten | Unbeschränkter Scope (siehe `*`-Normalisierung): ein scheinbar harmloser Treffer ist real unternehmensweit wirksam und verbreitert jeden Konflikt. | Hoch | [x] |
| A7 | **Ausreißer bei Rollen-/Profilanzahl je User** | Ungewöhnlich viele Zuweisungen im Vergleich zur Nutzerpopulation — typischer Bereinigungs-/Re-Zertifizierungskandidat, oft historisch gewachsen statt bewusst vergeben. | Mittel | [x] |

**Implementierungsnotizen Kategorie A** — durchgängig **fertig** (Cypher, Run-Endpoint, UI mit
Ausführen/Ergebnis/Schnellauswahl, `implemented: true` in `checks/A.json`); offen bleiben nur die
bereichsübergreifenden Punkte CSV-Export und echter Graph (s. „UI/Technischer Rahmen" unten):

Alle sieben Dateien haben mittlerweile **zwei Statements** (Zusammenfassung + Detailliste) —
jeder A-Check zeigt also KPI-Kacheln, nicht nur A1/A2 wie zuerst:

- **A1/A2** (`sap_all.cypher`/`sap_new.cypher`): unverändert/triviale Kopie.
- **A3** (`critical_profiles.cypher`): Liste `S_A.SYSTEM`/`S_A.ADMIN`/`S_A.DEVELOP` als Literal
  im Dateikopf, bewusst **erweiterbar** durch direktes Editieren — SAP ergänzt regelmäßig neue
  Auslieferungsprofile. Kein optionaler Parameter dafür: Neo4j verlangt für jede im Statement
  referenzierte `$`-Variable einen gebundenen Wert (auch in `coalesce()`); der generische
  Run-Endpoint übergibt nur `dataset`/`asOf`. Zusammenfassung: Anzahl betroffener User je Profil.
- **A4** (`critical_single_auths.cypher`): Werte 1:1 aus `rules/KPMG_R3/queries.json`
  (Debug-Replace = Query `1000_BC-SEC`; breiter Tabellenzugriff nach Muster `1107`/`1110_BC-DEV`).
  `S_TABU_NAM` ohne lokales Beispiel, Feldname `TABLE` nach SAP-Standard angenommen.
  Zusammenfassung: Anzahl betroffener User je Befund.
- **A5** (`batch_rfc_on_dialog.cypher`): Erkennung über die **enthaltenen Berechtigungsobjekte**
  (`S_RFC`, `S_BTCH_ADM`, `S_BTCH_JOB`, `S_BTCH_NAM`), nicht über Namenskonventionen. **Nur die
  Richtung „Dialog-User mit Batch/RFC-Rechten"** ist umgesetzt — die Umkehrung („technischer
  User mit dialogtypischen Rechten") hat kein vergleichbar trennscharfes Kriterium und ist
  bewusst nicht Teil von v1. Zusammenfassung: Anzahl betroffener Dialog-User je Objekt.
- **A6** (`org_wildcard_critical_objects.cypher`): „sensible Objekte" = dieselbe Liste wie A4.
  Hinweis: diese vier Objekte führen i. d. R. kein Org-Feld (BUKRS/WERKS/…) — der Check ist
  korrekt, liefert aber oft 0 Treffer, bis die Liste um org-tragende Objekte erweitert wird.
  Zusammenfassung: Anzahl betroffener User je Objekt (bei aktuellem Datenstand i. d. R. 0).
- **A7** (`role_profile_count_outliers.cypher`): Schwelle = **95. Perzentil** der Verteilung
  „Rollen + direkte Profile" über die gesamte Nutzerpopulation des Datasets (`percentileCont`),
  adaptiv je Mandant statt fixer Zahl. Zusammenfassung: Schwelle + Anzahl Ausreißer.
  *Stolperstein beim Bau der Zusammenfassung:* `WITH count(DISTINCT r) + count(DISTINCT p) AS
  gesamt` ohne `u` in der `WITH`-Klausel aggregiert über **alle** User hinweg statt je User
  (Cypher gruppiert implizit nach den nicht-aggregierten Variablen einer `WITH` — fehlt `u`,
  bleibt nur eine globale Summe) — lieferte eine einzelne, falsche Riesenzahl als „Schwelle" und
  immer 0 Ausreißer. Fix: `WITH u, count(DISTINCT r) + count(DISTINCT p) AS gesamt`.

---

## B — Benutzerstamm-Hygiene

| ID | Prüfung | Bedeutung & warum relevant | Prio | Umsetzung |
|----|---------|----------------------------|------|-----------|
| B1 | **Aktive Dialog-User ohne Logon seit X Tagen** (`USR02`-Last-Logon bzw. Did-Do) | Ruhende, aber offene Konten sind Angriffsfläche und Lizenzkosten. Verbindet sich gut mit der Did-Do-Sicht (nie genutzt + berechtigt = Entzugskandidat). | Mittel | [ ] |
| B2 | **Standard-/Default-User** (`SAP*`, `DDIC`, `SAPCPIC`, `EARLYWATCH`, `TMSADM`): Status & Logon | Bekannte Default-Accounts mit bekannten Passwörtern. Müssen gesichert, mit Profil ausgestattet bzw. gesperrt sein — ein Pflicht-Check jeder Basis-Prüfung. | Hoch | [ ] |
| B3 | **Initial-/schwache Passwortstände** (`USR02`-Kennzeichen) | Konten mit nie geändertem Initialpasswort sind leicht übernehmbar. Indikator für lückenhaftes Onboarding. | Mittel | [ ] |
| B4 | **Gesperrte User mit weiterhin kritischen Rollen** | Eine Sperre verdeckt Risiko nur, beseitigt es nicht — bei Entsperrung ist der Vollzugriff sofort wieder da. Saubere Praxis: Rechte entziehen statt nur sperren. | Mittel | [ ] |
| B5 | **Mehrfach-Konten derselben Person** (gleiche Person via `ADRP`/Namensgleichheit) | Zwei Konten können eine SoD-Trennung umgehen (Funktion A auf Konto 1, Funktion B auf Konto 2). Schwer zu finden, prüferisch wertvoll. | Mittel | [ ] |
| B6 | **Sleeping-User mit hochkritischen Berechtigungen** | Eigener Blickwinkel unabhängig von SoD (nutzt den bestehenden `sleepDays`-Parameter): wer lange nicht angemeldet war, aber weiterhin sehr kritische Rechte trägt, ist ein vorrangiger Entzugskandidat. | Mittel | [ ] |
| B7 | **Generische/Sammel-User mit produktiven Berechtigungen** | Namensmuster (`TEST*`/`ADMIN*`/…) abseits der bekannten SAP-Defaults (s. B2): kundeneigene Sammel-IDs ohne 1:1-Personenbezug, oft schlecht nachverfolgbar, mit produktiven Rechten ein Mitbestimmungs-/Nachweisrisiko. | Mittel | [ ] |

---

## C — Zuweisungs- & Strukturkonsistenz (User ↔ Rolle ↔ Profil)

**Bereinigt um Rollen-Checks, die in der Rollen-spezifischen Liste (s. u.) aufgegangen sind**
(vormals C2/C3/C6/C8/C9/C10/C11 → jetzt R1/R2/R4/R5/R6/R8/R17) — IDs neu durchnummeriert.
Verbleibend: echte User↔Rolle/Profil-Zuweisungs-Checks ohne reinen Rollen-Strukturfokus.

| ID | Prüfung | Bedeutung & warum relevant | Prio | Umsetzung |
|----|---------|----------------------------|------|-----------|
| C1 | User mit **direkt zugewiesenen Profilen** (`UST04`, ohne Rolle) | Umgeht die PFCG-Pflege; schwer wartbar, oft Altlast aus R/3-Zeiten oder manuelle „Schnellschüsse". Direktprofile entziehen sich dem Rollenkonzept und werden bei Auswertungen leicht übersehen. | Hoch | [ ] |
| C2 | **Verwaiste Profile** (generiertes Profil ohne zugehörige Rolle) | Inkonsistenz zwischen `USR10`/`AGR_PROF`; Hinweis auf fehlerhafte Generierung oder unsaubere Reorganisation. Kann Auswertungen verfälschen. | Mittel | [ ] |
| C3 | **User ohne jegliche Berechtigung** (kein Rollen- *und* kein Profilbezug) | „Leere" Konten — neu angelegt, ungenutzt oder fehlerhaft. Lizenz- und Aufräumkandidaten; in Summe ein Indikator für mangelnde User-Lifecycle-Pflege. | Niedrig | [ ] |
| C4 | **Einzelrolle ohne jede Verwendung** (in keiner Sammelrolle, keine direkte Zuweisung) | Ungenutzte Rolle → Aufräumkandidat. Reduziert Komplexität und Angriffsfläche im Rollenbestand. | Niedrig | [ ] |
| C5 | **Rollen ohne Beschreibung/Dokumentation** | Erschwert Re-Zertifizierung und Nachvollziehbarkeit „wofür ist diese Rolle gedacht" — Basis-Hygiene für jedes Rollenkonzept. | Niedrig | [ ] |

---

## D — Gültigkeit & Zeitbezug

| ID | Prüfung | Bedeutung & warum relevant | Prio | Umsetzung |
|----|---------|----------------------------|------|-----------|
| D1 | **Abgelaufene Zuweisungen, die noch als „aktiv" gezählt werden** | Direkter Fehler in der Stichtagslogik; führt zu falsch-positiven Berechtigungen. Validiert zugleich die Pfad-Gültigkeitsschnittmenge. | Hoch | [ ] |
| D2 | **Widersprüchliche Gültigkeit** (`validFrom` > `validTo`) | Datenfehler aus Quelle oder Import. Kann Stichtagsabfragen unbemerkt verzerren. | Mittel | [ ] |
| D3 | **Zukünftige, noch nicht wirksame Zuweisungen** | Dürfen am aktuellen Stichtag nicht zählen — Prüfung, dass die Logik sie korrekt ausblendet. | Niedrig | [ ] |
| D4 | **Veraltete Profilgenerierung** (Rolle nach letzter Profilgenerierung geändert — „rot" in PFCG) | Die laufzeitwirksame Berechtigung weicht von der gepflegten Rollendefinition ab. Auswertung auf Basis der Definition kann dann täuschen. | Mittel | [ ] |

---

## E — Referenzielle Integrität & Import-Vollständigkeit (graph-spezifisch)

| ID | Prüfung | Bedeutung & warum relevant | Prio | Umsetzung |
|----|---------|----------------------------|------|-----------|
| E1 | **`Authorization` ohne `FOR_OBJECT`** (Objekt nicht im `TOBJ`-Import) | Importlücke — die Berechtigung hängt „in der Luft". Verfälscht jede objektbasierte Auswertung. | Hoch | [ ] |
| E2 | **`AGR_1251`-Objekt, das nicht in `TOBJ` existiert** | Dangling Reference; oft veraltetes oder kundeneigenes (Z-)Objekt. Hinweis auf unvollständigen Stammdaten-Import. | Mittel | [ ] |
| E3 | **TCode in `AGR_TCODES`, der nicht in `TSTC` existiert** | Menüeintrag auf eine nicht (mehr) existierende Transaktion — Rollenmenü-Leiche oder fehlende Import-Tabelle. | Niedrig | [ ] |
| E4 | **`Transaction` ohne `CHECKS`-Kante** (kein `USOBX_C`/SU24-Eintrag) | TCode ohne Vorschlagswerte → Brücke TCode→Objekt fehlt, Berechtigungsbezug unklar. Relevant für die Vollständigkeit der Can-Do-Kette. | Mittel | [ ] |
| E5 | **Doppelte Knoten je Business-Key** | Sollte durch Constraints verhindert sein; als Absicherung wertvoll, weil Dubletten Zähler und Pfade verfälschen. | Hoch | [ ] |
| E6 | **Rowcount-Abgleich Knoten/Kanten gegen Quell-CSV** | Bestätigt die Import-Vollständigkeit (Phase-2-DoD). Ohne diesen Abgleich sind alle anderen Befunde nur so verlässlich wie der Import. | Hoch | [ ] |
| E7 | **Verwaiste `Authorization`-Knoten ohne erreichbaren Rollen-/Profilpfad** | Berechtigung existiert im Graph, aber kein `Role`/`Profile` verweist (mehr) darauf — Karteileiche aus Reorganisation/Teil-Import, verzerrt Auswertungen über alle `Authorization`-Knoten. | Mittel | [ ] |

---

## Einordnung

- **Datenqualität/Konsistenz:** Kategorien **C**, **D**, **E** — taugen als Gütesiegel für den
  Import, bevor fachliche Aussagen getroffen werden.
- **Fachliche Risikobefunde:** Kategorien **A**, **B** — bereits inhaltliche Prüfungsfeststellungen.
- **Reihenfolge-Empfehlung (Ausführung, unabhängig von der Anzeigereihenfolge):** **E zuerst.**
  Erst wenn Integrität und Import-Vollständigkeit stehen, sind A/B/C/D belastbar. Die App zeigt
  E aus Platzgründen zentriert als fünfte Box — das ist reine Anzeigereihenfolge, keine
  Ausführungsempfehlung.

---

## Konsistenzchecks für Rollen

Rollenzentrierte Diagnose-Checks, ergänzend zum allgemeinen Qualitätskatalog von oben — eigener
Ribbon-Punkt **„Rollen-spezifisch"**, operative Quelle [`checks/R.json`](checks/R.json) (Kategorie
`R`, Schema in [`checks/SCHEMA.md`](checks/SCHEMA.md)).
Fokus: Struktur und Generierung der Rollen, ihre Reichweite über Zuordnungen, sowie Risiko-/SoD-Eigenschaften je Rolle.

Hinweise:
- Einige Checks sind **analytische Rankings** (Top-N), keine Pass/Fail-Prüfung — sie steuern Priorität und Aufmerksamkeit. In der `Prio`-Spalte als **Analytik** markiert (eigener, neutraler Tag in der UI statt der Hoch/Mittel/Niedrig-Farbskala).
- Die SoD-bezogenen Checks (R13–R16) setzen die **abgeleitete Snapshot-Schicht** (Phase 3) voraus. „Built-in"/Intra-Rollen-Konflikt = Konflikt, den die Rolle **selbst** durch ihr Design trägt (AE-11), unabhängig vom Träger.
- IDs sind stabil und fortlaufend (`R1`…`R18`), gruppiert nach Thema — die vier Abschnitts-
  Überschriften unten (Struktur & Generierung, Zuordnung & Reichweite, Risiko & SoD,
  Wartbarkeit & Design) sind 1:1 das `group`-Feld in `checks/R.json` und werden in der UI als
  eigene, nebeneinander liegende Boxen (2×2-Raster) gerastert statt einer langen Tabelle.
- **Dedupliziert gegen Kategorie C:** die vormaligen C-Checks C2/C3/C6/C8/C9/C10/C11 (alle
  rollenstrukturzentriert) sind hier bereits enthalten (R1/R2/R4/R5/R6/R8/R17) und wurden aus C
  entfernt, s. Hinweis dort.

---

## Struktur & Generierung

| ID | Prüfung | Bedeutung & warum relevant | Prio | Umsetzung |
|----|---------|----------------------------|------|-----------|
| R1 | **Rollen ohne generiertes Profil** (`AGR_DEFINE` ohne `AGR_PROF`) | Rolle wurde nie generiert → trägt zur Laufzeit **keine** Berechtigung. Unfertige Rolle oder Karteileiche; Zuweisungsempfänger haben evtl. weniger Rechte als angenommen. | Hoch | [ ] |
| R2 | **Rollen ohne Berechtigungsdaten** (keine `AGR_1251`) | Menürolle ohne Objekte — TCodes im Menü, aber nichts gepflegt. Design-Fehler oder reine „Navigationsrolle". | Mittel | [ ] |
| R3 | **Veraltet generierte / nicht lauffähige Rollen** (Rolle nach letzter Profilgenerierung geändert — „rot" in PFCG) | Klassische „ungültige" Rolle: die laufzeitwirksame Berechtigung weicht von der gepflegten Definition ab. Auswertung auf Definitionsbasis täuscht dann. | Hoch | [ ] |
| R4 | **Sammelrolle ohne Einzelrollen** (`Composite` ohne `CONTAINS`) | Leere Sammelrolle ohne Wirkung. Designfehler oder Rest aus einem Umbau. | Niedrig | [ ] |
| R5 | **Abgeleitete Rolle ohne gültigen Master** (`Derived` ohne `DERIVED_FROM`) | Gebrochene Ableitung; zentrale Master-Pflege greift nicht durch, Org-Werte laufen ins Leere. | Mittel | [ ] |
| R6 | **Abgeleitete Rolle weicht über Org-Ebenen hinaus vom Master ab** | Ableitungskonzept verletzt — eine Ableitung sollte sich nur in Org-Werten unterscheiden. Abweichungen deuten auf manuelle Eingriffe und Wildwuchs. | Mittel | [ ] |
| R7 | **Master-Rolle mit direkt gepflegten Org-Werten** statt Org-Variablen | Hebelt das Ableitungskonzept aus: feste Org-Werte im Master verhindern saubere Ableitungen. Wartbarkeitsrisiko. | Niedrig | [ ] |

---

## Zuordnung & Reichweite

| ID | Prüfung | Bedeutung & warum relevant | Prio | Umsetzung |
|----|---------|----------------------------|------|-----------|
| R8 | **Rollen ohne jegliche Nutzerzuordnung** (keine aktive `AGR_USERS`, auch nicht über eine Sammelrolle) | Tote Rollen → Aufräumkandidaten. Reduzieren Komplexität und Angriffsfläche im Rollenbestand. Großer Anteil deutet auf fehlende Rollen-Lifecycle-Pflege. | Mittel | [ ] |
| R9 | **Rollen nur mit abgelaufenen Zuordnungen** (alle `AGR_USERS` außerhalb der Gültigkeit) | Faktisch ungenutzt, am Stichtag aber leicht als „zugewiesen" fehlgezählt. Validiert zugleich die Stichtagslogik. | Mittel | [ ] |
| R10 | **Top-N Rollen nach Anzahl Nutzerzuordnungen** | Reichweitenstärkste Rollen — hier wirkt jede Änderung am breitesten. Priorisierungssicht für Review, Rezertifizierung und Risikoeinschätzung. | Analytik | [ ] |
| R11 | **Rollen mit genau einem Nutzer** (personengebundene Sonderrollen) | „1:1"-Rollen sind oft manueller Wildwuchs oder Schattenlösungen am Rollenkonzept vorbei; Konsolidierungs-/Bereinigungskandidaten. | Niedrig | [ ] |
| R12 | **„Mega"-Sammelrollen** (auffällig viele Einzelrollen / sehr breite Berechtigungsmenge) | Hohe Komplexität erschwert Nachvollziehbarkeit und begünstigt unbeabsichtigte SoD-Kombinationen. Kandidaten für Aufteilung. | Mittel | [ ] |

---

## Risiko & SoD

| ID | Prüfung | Bedeutung & warum relevant | Prio | Umsetzung |
|----|---------|----------------------------|------|-----------|
| R13 | **Rollen mit Intra-Rollen-SoD-Konflikt** (built-in / conflicting-by-design) | Die Rolle bündelt selbst zwei konfligierende Funktionen — jeder Träger erbt den Konflikt. Design-Fehler an der Wurzel, hoch wiederverwendbar als Befund. | Hoch | [ ] |
| R14 | **Top-N Rollen nach Anzahl built-in SoD-Konflikte** | Rangliste der problematischsten Rollendesigns. Steuert, wo Redesign den größten Hebel hat. | Analytik | [ ] |
| R15 | **Konflikt-Hotspot-Rollen** (am häufigsten an **Inter**-Rollen-Konflikten beteiligt) | Rollen, die in Kombination mit vielen anderen Konflikte erzeugen. Auch wenn jede für sich sauber ist, sind sie die wirksamsten Stellschrauben zur Konfliktreduktion. | Hoch | [ ] |
| R16 | **Rollen mit kritischen Inhalten** (enthalten `SAP_ALL`-äquivalente Profile, weite `S_TABU_DIS`/`S_TABU_NAM`, Debug-Replace `S_DEVELOP ACTVT 02`, `*` auf kritischen Org-Ebenen) | Hochrisiko-Berechtigung gebündelt in einer Rolle — verteilt sich über jede Zuweisung. Erstrangige Review-Kandidaten. | Hoch | [ ] |

---

## Wartbarkeit & Design

| ID | Prüfung | Bedeutung & warum relevant | Prio | Umsetzung |
|----|---------|----------------------------|------|-----------|
| R17 | **Redundante Rollen** (identische bzw. nahezu identische Berechtigungsmenge unter verschiedenen Namen) | Dubletten blähen den Bestand auf, erschweren Pflege und führen zu inkonsistenten Änderungen. Konsolidierungskandidaten. | Mittel | [ ] |
| R18 | **Stark überlappende Rollen** (großer gemeinsamer Berechtigungsanteil) | Hinweis auf fehlende Modularisierung; Kandidaten für eine gemeinsame Basisrolle. Senkt langfristig SoD-Risiko und Pflegeaufwand. | Niedrig | [ ] |

---

## Einordnung

- **Struktur & Generierung** (R1–R7) und **Wartbarkeit** (R17–R18) prüfen primär Rollen­qualität und Pflegezustand.
- **Zuordnung & Reichweite** (R8–R12) verbindet Rollen mit ihrer realen Verbreitung — die Basis jeder Priorisierung.
- **Risiko & SoD** (R13–R16) liefert die fachlichen Befunde und setzt die Snapshot-/SoD-Schicht aus Phase 3 voraus.
- **Rankings** (R10, R14) sind Steuerungssichten, keine Defekte — sie sagen, *wo* sich Tiefenprüfung am meisten lohnt.


## UI/Technischer Rahmen (Details s. ROADMAP Phase 7)

- **Zwei Ribbon-Punkte** (Gruppe 4): **„User-spezifisch"** (Kategorien A–E) und
  **„Rollen-spezifisch"** (Kategorie `R`) — beide öffnen dieselbe Ansicht im Hauptbereich, nur
  mit unterschiedlichem `area`-Parameter (`GET /consistency-checks?area=user|role`).
- **Eine eigene, umrahmte Tabelle je Raster-Box** (statt einer Tabelle für alle) — bei
  „User-spezifisch" gerastert nach **Kategorie** (A–E), Layout 2×2 (A·B / C·D) plus **E zentriert
  darunter** (ungerade Anzahl), mit **Kategorie-Pills A–E** (+ „alle") darüber; bei
  „Rollen-spezifisch" gerastert nach dem Feld **`group`** der einzigen Kategorie `R`, ebenfalls
  2×2 (Struktur & Generierung · Zuordnung & Reichweite / Risiko & SoD · Wartbarkeit & Design) mit
  **Themen-Pills** darüber — vermeidet eine einzige lange 18-Zeilen-Tabelle. Je Zeile: **Prüfung
  fett, Begründung darunter klein** (auch für fachlich nicht Kundige lesbar, nicht nur der
  Kurztitel).
- **Ausführung:** Klick auf eine Tabellenzeile **wechselt** (kein Overlay/Dialog, derselbe
  Grundsatz wie beim Katalog selbst) im Hauptbereich auf eine **eigene Ergebnis-Ansicht**: oben
  eine Zeile mit dem **Check-Titel links** und **ID/Kategorie/Prio-Chips + „← zurück zum
  Katalog"-Button rechtsbündig** (auf Höhe der Überschrift, keine eigene Zeile mehr); darunter
  **zweispaltig wie die Findings-Ansicht** (320px + Rest). **Links:** Begründung (Stammdaten,
  immer sichtbar — auch bei nicht implementierten Checks), darunter das Formular
  **Dataset/Stichtag** (vorbelegt aus dem aktuell aktiven Lauf, falls vorhanden) mit
  **„Ausführen"**-Button (zeigt Spinner + „läuft…" während der Anfrage) — aktuell **ein Check
  pro Lauf** (keine Mehrfachauswahl, spätere Ausbaustufe); **rechts** das Ergebnis. Nicht
  implementierte Checks (`implemented: false`) zeigen links nur Begründung + Schnellauswahl (kein
  Formular) und rechts einen Hinweis statt eines Ergebnisses.
- **Schnellauswahl innerhalb derselben Raster-Box:** unter dem Ausführen-Formular (links) listet
  „Weitere Checks · …" **alle Checks derselben Box** wie der gerade gezeigte — bei
  „User-spezifisch" derselben Kategorie, bei „Rollen-spezifisch" derselben `group` (analog zur
  Läufe-Liste) — Klick wechselt direkt zum nächsten Check **ohne** Umweg über den Katalog;
  Dataset/Stichtag bleiben dabei erhalten (nur beim allerersten Öffnen aus dem aktiven Lauf
  vorbelegt), sodass sich eine ganze Box mit denselben Werten durchklicken lässt. Funktioniert
  auch von einem nicht implementierten Check aus, um zu einem implementierten in derselben Box
  zu wechseln.
- **Keine Persistenz (bewusst, v1):** Ein Check-Lauf erzeugt **keinen** `(:Run)`-Knoten und wird
  nirgends im Graph gespeichert — die Cypher-Datei liest nur den aktuellen Graphzustand
  (read-only) und das Ergebnis lebt ausschließlich im Browser für die Dauer der Session. Die
  zuletzt gesehene **Trefferzahl** wird clientseitig zwischengespeichert und erscheint danach in
  der Katalog-Tabelle in der Spalte „Ergebnisse" (statt „noch nicht ausgeführt") — das ist aber
  nur ein UI-Cache, kein Server-Zustand, geht beim Neuladen der Seite verloren. Persistenz/
  Historie (Vergleich über Zeit, Re-Zertifizierung) ist nicht v1-Scope.
- **Ergebnisdarstellung:** rechte Spalte, oben rechts ein **Tabelle/Graph-Pill** (Graph
  deaktiviert, „kommt später" — analog zum Pill in den SoD-Ergebnissen). Hat die Cypher-Datei
  mehrere Statements (Zusammenfassung + Detailliste — inzwischen alle sieben A-Checks, s.
  „Implementierungsnotizen Kategorie A" oben), zeigt die Tabellenansicht **oben Summary-Kacheln**
  (aus dem ersten Statement, Werte menschenlesbar übersetzt — z. B. `Active`→„aktiv",
  `Locked`→„gesperrt", ohne rohe Spaltennamen wie „typ_status:") **und darunter die
  Detailtabelle** (aus dem letzten Statement, dynamische Spalten je nach Rückgabe). Hat eine
  Cypher-Datei nur ein Statement (z. B. künftige Checks ohne sinnvolle Aggregation), zeigt sich
  automatisch nur die Detailtabelle — die UI erkennt das generisch an der Anzahl Statements.
- **Persistenz:** der Katalog liegt als **JSON je Kategorie** unter [`checks/`](checks/)
  (`A.json`/`B.json`/`C.json`/`D.json`/`E.json`/`R.json`, Schema in `checks/SCHEMA.md`) — analog
  zur Ruleset-Struktur (`rules/<Ruleset>/sod_rules.json`), aber **ruleset-unabhängig** und ohne
  Vendor/Overlay-Trennung (kein externer „Lieferant" hier, daher v1 ohne Overlay-Mechanismus).
  **Jede Tabelle entspricht 1:1 einer Datei** — die Tabelle für Kategorie A liest/schreibt
  `checks/A.json`, usw.
- API: `GET /consistency-checks?area=user|role` (Katalog, aus den JSON-Dateien des jeweiligen
  Bereichs gemerged) + `POST /consistency-checks/{id}/run` (führt die hinterlegte `cypherFile`
  mit `dataset`/`asOf` aus, gibt die Zeilen je Statement zurück — nur für Checks mit
  `implemented: true` und gesetztem `cypherFile`).
- Export: CSV (später Teil des Gesamt-Reports zusammen mit der Import-Evidenz).
