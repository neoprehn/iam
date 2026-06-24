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

**Konvention KPI-Kacheln (Bugfix, auf Nutzer-Feedback gefunden und systematisch behoben):** die
UI zeigt je Summary-Statement eine Kachel, in der die **letzte** zurückgegebene Spalte groß/fett
("die Zahl") und alle vorigen Spalten klein als Untertitel erscheinen (`renderCcdSummary` in
`frontend/index.html`). Mehrere Checks hatten das vertauscht — z. B. lieferte
`dormant_active_dialog_users.cypher` (B1) `anzahl, schwelleTage`, wodurch die KPI-Kachel die
**Tage-Schwelle** groß zeigte statt der **betroffenen User** — und `direct_profile_assignments.cypher`
(C1) zeigte `userAnzahl, profilAnzahl`, wodurch die (oft sehr hohe) Profilanzahl statt der
Useranzahl im Vordergrund stand. **Regel ab jetzt: die letzte Spalte ist immer die
„Wie-viele-Treffer"-Zahl, alles davor ist Kontext/Label** — betraf B1, B2, C1, C3, D4, E3, E4,
R13 (Details je Kategorie unten).

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

- **A1/A2** (`sap_all.cypher`/`sap_new.cypher`): unverändert/triviale Kopie. **A1**-Detailliste
  zeigt auf Nutzer-Feedback zusätzlich `letzterLogon` (A2/A3/A6 haben dieselbe Detailstruktur
  und sind Kandidaten für dieselbe Ergänzung, falls gewünscht).
- **A3** (`critical_profiles.cypher`): Liste `S_A.SYSTEM`/`S_A.ADMIN`/`S_A.DEVELOP` als Literal
  im Dateikopf, bewusst **erweiterbar** durch direktes Editieren — SAP ergänzt regelmäßig neue
  Auslieferungsprofile. Kein optionaler Parameter dafür: Neo4j verlangt für jede im Statement
  referenzierte `$`-Variable einen gebundenen Wert (auch in `coalesce()`); der generische
  Run-Endpoint übergibt nur `dataset`/`asOf`. Zusammenfassung: Anzahl betroffener User je Profil.
- **A4** (`critical_single_auths.cypher`): Werte 1:1 aus `rules/KPMG_R3/queries.json`
  (Debug-Replace = Query `1000_BC-SEC`; breiter Tabellenzugriff nach Muster `1107`/`1110_BC-DEV`).
  `S_TABU_NAM` ohne lokales Beispiel, Feldname `TABLE` nach SAP-Standard angenommen.
  Zusammenfassung: Anzahl betroffener User je Befund. **Root-Cause-Drilldown** (auf Nutzer-
  Feedback ergänzt): eigene Datei `critical_single_auths_root_cause.cypher` (Kriterien 1:1
  gespiegelt, bei Änderung dort auch hier nachziehen) + Endpoint `POST
  /consistency-checks/A4/root-cause` (Body `{dataset, user}`) zeigt für einen einzelnen User
  die konkrete(n) Rolle(n)/Profil(e) samt Authorization-Feldwerten je Befund — Antwortformat
  identisch zum SoD-Root-Cause (`{blocks:[...]}`), UI nutzt denselben Root-Cause-Dialog. In der
  Detailtabelle erscheint dafür ein „Root-Cause"-Button, sobald `checks/A.json` für den Check
  ein `rootCauseFile` gesetzt hat und die Ergebnisspalte `user` vorhanden ist (generischer
  Mechanismus, s. `checks/SCHEMA.md` — aktuell nur für A4 genutzt).
- **A5** (`batch_rfc_on_dialog.cypher`): Erkennung über die **enthaltenen Berechtigungsobjekte**
  (`S_RFC`, `S_BTCH_ADM`, `S_BTCH_JOB`, `S_BTCH_NAM`), nicht über Namenskonventionen. **Nur die
  Richtung „Dialog-User mit Batch/RFC-Rechten"** ist umgesetzt — die Umkehrung („technischer
  User mit dialogtypischen Rechten") hat kein vergleichbar trennscharfes Kriterium und ist
  bewusst nicht Teil von v1. Zusammenfassung: Anzahl betroffener Dialog-User je Objekt, als
  selbsterklärender Text „Dialog-User mit `<Objekt>`" (nicht nur der rohe Objektcode — die
  KPI-Kachel zeigt sonst nur den Wert ohne Feldname).
- **A6** (`org_wildcard_critical_objects.cypher`): „sensible Objekte" = dieselbe Liste wie A4.
  **0 Treffer ist hier der erwartete, korrekte Befund** (kein Darstellungsfehler): diese vier
  Objekte führen i. d. R. kein Org-Feld (BUKRS/WERKS/…) — der Check ist richtig implementiert,
  greift aber erst, wenn die Liste um Objekte mit echtem Org-Bezug erweitert wird (z. B.
  `F_BKPF_BUK`, `M_BEST_WRK`). Zusammenfassung: Anzahl betroffener User je Objekt.
- **A7** (`role_profile_count_outliers.cypher`): Schwelle = **95. Perzentil** der Verteilung
  „Rollen + direkte Profile" über die gesamte Nutzerpopulation des Datasets (`percentileCont`),
  adaptiv je Mandant statt fixer Zahl. Zusammenfassung jetzt als Text „Median `<x>` / P95-
  Schwelle `<y>` Rollen+Profile" (Median zur Einordnung ergänzt, nicht nur die nackte
  Schwellenzahl ohne Kontext) + Anzahl Ausreißer.
  *Stolperstein beim Bau der Zusammenfassung:* `WITH count(DISTINCT r) + count(DISTINCT p) AS
  gesamt` ohne `u` in der `WITH`-Klausel aggregiert über **alle** User hinweg statt je User
  (Cypher gruppiert implizit nach den nicht-aggregierten Variablen einer `WITH` — fehlt `u`,
  bleibt nur eine globale Summe) — lieferte eine einzelne, falsche Riesenzahl als „Schwelle" und
  immer 0 Ausreißer. Fix: `WITH u, count(DISTINCT r) + count(DISTINCT p) AS gesamt`.

---

## B — Benutzerstamm-Hygiene

| ID | Prüfung | Bedeutung & warum relevant | Prio | Umsetzung |
|----|---------|----------------------------|------|-----------|
| B1 | **Aktive Dialog-User ohne Logon seit X Tagen** (`USR02`-Last-Logon bzw. Did-Do) | Ruhende, aber offene Konten sind Angriffsfläche und Lizenzkosten. Verbindet sich gut mit der Did-Do-Sicht (nie genutzt + berechtigt = Entzugskandidat). | Mittel | [x] |
| B2 | **Standard-/Default-User** (`SAP*`, `DDIC`, `SAPCPIC`, `EARLYWATCH`, `TMSADM`): Status & Logon | Bekannte Default-Accounts mit bekannten Passwörtern. Müssen gesichert, mit Profil ausgestattet bzw. gesperrt sein — ein Pflicht-Check jeder Basis-Prüfung. | Hoch | [x] |
| B3 | **Initial-/schwache Passwortstände** (`USR02`-Kennzeichen) | Konten mit nie geändertem Initialpasswort sind leicht übernehmbar. Indikator für lückenhaftes Onboarding. | Mittel | [x] |
| B4 | **Gesperrte User mit weiterhin kritischen Rollen** | Eine Sperre verdeckt Risiko nur, beseitigt es nicht — bei Entsperrung ist der Vollzugriff sofort wieder da. Saubere Praxis: Rechte entziehen statt nur sperren. | Mittel | [x] |
| B5 | **Mehrfach-Konten derselben Person** (gleiche Person via `ADRP`/Namensgleichheit) | Zwei Konten können eine SoD-Trennung umgehen (Funktion A auf Konto 1, Funktion B auf Konto 2). Schwer zu finden, prüferisch wertvoll. | Mittel | [~] |
| B6 | **Sleeping-User mit hochkritischen Berechtigungen** | Eigener Blickwinkel unabhängig von SoD (nutzt den bestehenden `sleepDays`-Parameter): wer lange nicht angemeldet war, aber weiterhin sehr kritische Rechte trägt, ist ein vorrangiger Entzugskandidat. | Mittel | [x] |
| B7 | **Generische/Sammel-User mit produktiven Berechtigungen** | Namensmuster (`TEST*`/`ADMIN*`/…) abseits der bekannten SAP-Defaults (s. B2): kundeneigene Sammel-IDs ohne 1:1-Personenbezug, oft schlecht nachverfolgbar, mit produktiven Rechten ein Mitbestimmungs-/Nachweisrisiko. | Mittel | [x] |

**Implementierungsnotizen Kategorie B** — sechs von sieben Checks mit Cypher (`checks/B.json`),
analog zu Kategorie A mit Zusammenfassung + Detailliste je Datei:

- **B1** (`dormant_active_dialog_users.cypher`): nur **aktive** Dialog-User (anmeldefähige
  Personen, nicht gesperrt — Sperr-Blickwinkel s. B4); Schwelle ist ein echter `$sleepDays`-
  Parameter (auf Nutzer-Feedback von Literal auf `params` umgestellt, s. `checks/SCHEMA.md`) —
  `checks/B.json` deklariert die Pill-Button-Optionen 90/180/360 Tage (Default 180, deckt sich
  mit dem SoD-Sleeping-Default `config/analysis_profiles.json`, `sleeping.sleepDays`). **Bugfix
  (Nutzer-Feedback):** KPI-Kachel zeigte die Tage-Schwelle statt der betroffenen User (s. Kachel-
  Konvention oben) — Spaltenreihenfolge getauscht, `letzterLogon` war korrekt befüllt, die KPI war
  nur falsch dargestellt. B6 (`sleeping_users_with_critical_access.cypher`) hat denselben hart
  codierten 180-Tage-Literal und ist ein Kandidat für dieselbe Parameter-Umstellung, falls
  gewünscht.
- **B2** (`default_users.cypher`): Mustererkennung mit `STARTS WITH`/exaktem Vergleich, generisch
  für Listenelemente mit/ohne `*`-Suffix (derselbe Mechanismus wiederverwendet in B7). **Auf
  Nutzer-Feedback:** Detailspalte „Muster" durch **Benutzertyp** ersetzt (war für die meisten
  Default-Accounts ohnehin nur eine Wiederholung der bereits sichtbaren User-ID); KPI-Kachel
  zeigt jetzt „`<Muster>` (`<n>` gesperrt)" als Label statt eines unmotivierten dritten Werts.
- **B3** (`initial_passwords.cypher`) — **Korrektur einer früheren Fehleinschätzung** (auf
  Nutzer-Rückfrage „wenn wir die Daten haben, warum dann nicht auswerten?"): ursprünglich als
  „nicht umsetzbar" eingestuft, weil pauschal angenommen wurde, USR02 würde *alle*
  Passwort-bezogenen Spalten ausschließen. Tatsächlich verwirft der Konverter nur die echten
  Hash-/Algorithmus-Felder (`BCODE*`/`BCDA*`/`OCOD*`/`CODV*`/`PASSCODE`/`PWDSALTEDHASH`/
  `PWDHISTORY`) — die reinen Status-/Datumsfelder `PWDINITIAL`/`PWDCHGDATE`/`PWDSETDATE` waren
  im konvertierten CSV bereits vorhanden, wurden vom Loader nur noch nicht ins Graph-Property
  übernommen (`load/01_users.cypher` jetzt nachgezogen, s. `docs/extraktionsleitfaden.md`).
  **`pwdInitial`-Kodierung empirisch hergeleitet** (SAP dokumentiert sie nicht einheitlich
  öffentlich, ⚠️ vor Produktivnutzung gegen das eigene System verifizieren): im Testdatenbestand
  korreliert `pwdInitial = '1'` zu 100 % mit `pwdChgDate = pwdSetDate` („nie geändert seit
  Vergabe") — der klare Befund (768 von 1378 Usern, 56 %); `pwdInitial = '2'` ist ein Mischfall
  und wird daher als separater, weicherer Befund ausgewiesen statt mit `1` zusammengefasst
  (566 User); `0` = regulär geändert, kein Befund.
- **B4** (`locked_users_with_critical_access.cypher`): wiederverwendet dieselbe
  Kritisch-Definition wie A1-A4 (SAP_ALL/SAP_NEW/kritische Standardprofile/Debug-Replace/
  `S_USER_GRP`), eingeschränkt auf `Locked`-User. **Auf Nutzer-Feedback:** `$lockReason`-Parameter
  (Pill-Buttons „alle"/`failed_logons`/`admin_local`/`admin_global`, gegen `u.lockReasons`
  geprüft) ergänzt, um nach Sperrgrund durchschalten zu können.
- **B5** (`duplicate_persons_by_name.cypher`) — **als `[~]` markiert, nicht `[x]`:** `ADRP`
  (Adress-/Personendaten) wird wie Passwörter bewusst nicht importiert
  (`docs/extraktionsleitfaden.md`: „für Can-Do nicht nötig"). Implementiert ist daher nur die
  schwächere **Namensgleichheits-Heuristik** über `V_USERNAME`/`User.name` — liefert
  Falsch-Positive (Namensvettern) und Falsch-Negative (Tippfehler/Titel im Namensfeld) und ist als
  Indikator, nicht als belastbarer Einzelbefund zu lesen. Vollständige Umsetzung würde einen
  ADRP-Import voraussetzen (aktuell nicht Scope, s. Trust-Boundary/Datenschutz-Erwägungen). **Auf
  Nutzer-Feedback ergänzt:** Detailliste zeigt jetzt `letzterLogon` und `personalnummer`
  (`u.persNumber`, aus `V_USERNAME`, Loader 12) als eigene Spalten neben dem Namen; Status
  (aktiv/gesperrt) ist aus der Detailtabelle in einen `$status`-Pill-Filter gewandert. **Wichtig:**
  die Dubletten-**Erkennung** (welche Namen mehrfach vorkommen) läuft immer über alle Konten eines
  Namens — der Statusfilter blendet erst danach einzelne Konten der bereits erkannten Gruppe aus,
  sonst würde z. B. ein aktiv+gesperrt-Paar beim Filtern auf „aktiv" fälschlich als „keine
  Dublette" verschwinden.
- **B6** (`sleeping_users_with_critical_access.cypher`): kombiniert B1-Schwelle (180 Tage,
  Literal) mit der A1-A3-Kritisch-Definition, unabhängig vom Sperrstatus. **Auf Nutzer-Rückfrage:**
  `NULL` bei `letzterLogon` ist hier korrekt und beabsichtigt — es bedeutet „nie angemeldet"
  (`u.lastLogon IS NULL`), was nach der Check-Definition ebenfalls als „sleeping" gilt. Im
  Testdatenbestand betrifft das einen auffällig hohen Anteil (635 von 1378 Usern, davon 626
  Dialog-User, ca. 47 % der Dialog-Population) — technisch korrekt ausgelesen, aber ein derart
  hoher Anteil ist ungewöhnlich und sollte mandantenseitig gegen die Quelle (USR02-TRDAT)
  gegengeprüft werden, falls das nicht plausibel erscheint.
- **B7** (`generic_users_with_access.cypher`): Musterliste (`TEST*`/`ADMIN*`/`SCHULUNG*`/
  `TRAINING*`/`DEMO*`/`MUSTER*`) als Literal, bewusst erweiterbar je Mandant; „produktive
  Berechtigung" = mindestens eine Rollenzuweisung oder ein direktes Profil. **Auf Nutzer-
  Rückfrage verifiziert:** 0 Treffer im Testdatenbestand ist korrekt — es gibt dort **keine**
  User-IDs, die auch nur mit einem der Muster beginnen (unabhängig von Berechtigung geprüft),
  nicht etwa Muster-Treffer ohne Zugriff. Kein Bug, sondern Datenrealität dieses Mandanten.

---

## C — Zuweisungs- & Strukturkonsistenz (User ↔ Rolle ↔ Profil)

**Bereinigt um Rollen-Checks, die in der Rollen-spezifischen Liste (s. u.) aufgegangen sind**
(vormals C2/C3/C6/C8/C9/C10/C11 → jetzt R1/R2/R4/R5/R6/R8/R17) — IDs neu durchnummeriert.
Verbleibend: echte User↔Rolle/Profil-Zuweisungs-Checks ohne reinen Rollen-Strukturfokus.

| ID | Prüfung | Bedeutung & warum relevant | Prio | Umsetzung |
|----|---------|----------------------------|------|-----------|
| C1 | User mit **direkt zugewiesenen Profilen** (`UST04`, ohne Rolle) | Umgeht die PFCG-Pflege; schwer wartbar, oft Altlast aus R/3-Zeiten oder manuelle „Schnellschüsse". Direktprofile entziehen sich dem Rollenkonzept und werden bei Auswertungen leicht übersehen. | Hoch | [x] |
| C2 | **Verwaiste Profile** (generiertes Profil ohne zugehörige Rolle) | Inkonsistenz zwischen `USR10`/`AGR_PROF`; Hinweis auf fehlerhafte Generierung oder unsaubere Reorganisation. Kann Auswertungen verfälschen. | Mittel | [x] |
| C3 | **User ohne jegliche Berechtigung** (kein Rollen- *und* kein Profilbezug) | „Leere" Konten — neu angelegt, ungenutzt oder fehlerhaft. Lizenz- und Aufräumkandidaten; in Summe ein Indikator für mangelnde User-Lifecycle-Pflege. | Niedrig | [x] |
| C4 | **Einzelrolle ohne jede Verwendung** (in keiner Sammelrolle, keine direkte Zuweisung) | Ungenutzte Rolle → Aufräumkandidat. Reduziert Komplexität und Angriffsfläche im Rollenbestand. | Niedrig | [x] |
| C5 | **Rollen ohne Beschreibung/Dokumentation** | Erschwert Re-Zertifizierung und Nachvollziehbarkeit „wofür ist diese Rolle gedacht" — Basis-Hygiene für jedes Rollenkonzept. | Niedrig | [x] |

**Implementierungsnotizen Kategorie C** — alle fünf Checks mit Cypher (`checks/C.json`):

- **C1** (`direct_profile_assignments.cypher`): erfasst **jede** direkte `HAS_PROFILE`-Zuweisung
  (NUR direkt, niemals über eine Rolle generierte Profile — das war schon vor dem Feedback so)
  unabhängig davon, ob derselbe User daneben auch Rollen hat (`hatAuchRollen` als Zusatzinfo in
  der Detailliste) — das Risiko liegt an der Zuweisung selbst, nicht am Fehlen jeglicher Rolle
  (dafür s. C3). **Auf Nutzer-Feedback („Fülle der aufgelisteten Profile"):** im Testdatenbestand
  haben praktisch alle User (1349 von 1378) direkt zugewiesene Profile, **Median 39, Maximum 232**
  pro User — eine volle Liste je Tabellenzelle war dadurch unlesbar. Detailspalte zeigt jetzt
  `profilAnzahl` (Zahl) + `profilVorschau` (erste 5, sortiert) statt aller Profile; zusätzlich war
  die KPI-Kachel verkehrt (zeigte `profilAnzahl` groß statt `userAnzahl`, s. Kachel-Konvention
  oben) — behoben. Die hohe Profildichte selbst ist echte Datenlage, kein Darstellungsfehler.
- **C2** (`orphaned_profiles.cypher`): „verwaist" = kein `(:Role)-[:HAS_PROFILE]->(:Profile)`.
  SAP-Standardprofile (`SAP_ALL`/`SAP_NEW`/`S_A.*`) sind **nie** über eine Rolle generiert und
  daher explizit ausgeschlossen (dieselbe Literal-Liste wie A3) — sonst würde der Check
  dauerhaft auf bekannten Nicht-Befunden sitzen.
- **C3** (`users_without_access.cypher`): Basis-Kanten (`ASSIGNED_TO`/`HAS_PROFILE`) ohne
  Stichtagsfilter — ein User ganz ohne jede Zuweisung hat unabhängig vom Datum keinen Zugriff.
  **Auf Nutzer-Feedback:** `$status`-Pill-Filter (alle/aktiv/gesperrt) ergänzt; KPI-Kachel-
  Spaltenreihenfolge korrigiert (s. Kachel-Konvention oben).
- **C4** (`unused_single_roles.cypher`): nur Subtyp `Single` (Composite-Rollen sind per
  Definition „verwendet", solange sie selbst zugewiesen sind — eigener Blickwinkel, nicht Teil
  von C4); liefert auf einem typischen SAP-Standardrollenbestand eine hohe Trefferzahl
  (mitgelieferte, nie zugewiesene Standardrollen) — bewusst so, kein Bug.
- **C5** (`roles_without_description.cypher`): `Role.text` leer/`NULL` — Quelle ist
  `AGR_DEFINE.TEXT` (Loader 02) bzw. die sprachabhängige `AGR_TEXTS`-Ergänzung (Loader 21);
  Detailliste zeigt zusätzlich die Nutzeranzahl, um Dokumentationslücken nach Reichweite zu
  priorisieren.

---

## D — Gültigkeit & Zeitbezug

| ID | Prüfung | Bedeutung & warum relevant | Prio | Umsetzung |
|----|---------|----------------------------|------|-----------|
| D1 | **Abgelaufene Zuweisungen, die noch als „aktiv" gezählt werden** | Direkter Fehler in der Stichtagslogik; führt zu falsch-positiven Berechtigungen. Validiert zugleich die Pfad-Gültigkeitsschnittmenge. | Hoch | [x] |
| D2 | **Widersprüchliche Gültigkeit** (`validFrom` > `validTo`) | Datenfehler aus Quelle oder Import. Kann Stichtagsabfragen unbemerkt verzerren. | Mittel | [x] |
| D3 | **Zukünftige, noch nicht wirksame Zuweisungen** | Dürfen am aktuellen Stichtag nicht zählen — Prüfung, dass die Logik sie korrekt ausblendet. | Niedrig | [x] |
| D4 | **Veraltete Profilgenerierung** (Rolle nach letzter Profilgenerierung geändert — „rot" in PFCG) | Die laufzeitwirksame Berechtigung weicht von der gepflegten Rollendefinition ab. Auswertung auf Basis der Definition kann dann täuschen. | Mittel | [x] |

**Implementierungsnotizen Kategorie D** — alle vier Checks mit Cypher (`checks/D.json`):

- **D1/D3** (`expired_assignments_audit.cypher`/`future_assignments_audit.cypher`) — **wichtige
  Einordnung:** das Stichtagsprädikat (`validFrom IS NULL OR validFrom <= $asOf) AND (validTo
  IS NULL OR $asOf <= validTo)`) wird in allen Auswerte-Abfragen (`query_match`/
  `materialize_matches`/`evaluate_sod`) konsistent angewendet (AE-07/08) — diese beiden Checks
  finden daher **keinen eigenen Logikfehler im Graph**, sondern legen die abgelaufenen bzw.
  zukünftigen Zuordnungen offen als **auditierbare Gegenprobe**: jede hier gelistete Zuordnung
  darf in keinem Can-Do-/SoD-Treffer zum selben Stichtag auftauchen — manuell stichprobenhaft
  prüfbar, kein automatischer Fehlerbeweis. D1 liefert auf dem aktuellen Datenstand naturgemäß
  eine hohe Zahl (jede historisch beendete Zuordnung zählt mit; im Testdatenbestand 246 von
  72.109 Zuordnungen insgesamt, ~0,3 %).
  **Auf Nutzer-Rückfrage „könnten die abgelaufenen Zuordnungen dann auch entzogen werden?":**
  ja, fachlich sind das genau die Kandidaten für eine SAP-seitige Benutzer-/Rollen-Reorganisation
  (`AGR_USERS`-Einträge ohne Wirkung, die in SU01/PFCG bzw. per Reorg-Report bereinigt werden
  könnten) — **aber nicht hier im Graph.** Die Rohschicht (Can-Do) wird bei jedem Import 1:1 aus
  dem SAP-Extrakt nachgezogen (AE-01/AE-10) und ist bewusst nicht manuell editierbar; ein
  Löschen im Graph hätte keine Wirkung auf SAP und würde beim nächsten Import ohnehin wieder
  überschrieben. D1s Liste taugt als **Worklist-Export** für die Basis-/Security-Abteilung, kein
  Selbstbedienungs-„Entziehen"-Knopf in der App (passt zum offenen CSV-Export, Phase 7).
- **D2** (`contradictory_validity.cypher`): `validFrom > validTo` ist nach AE-07/08-Logik
  ohnehin **immer** ausgeschlossen (kein `$asOf` kann beide Bedingungen erfüllen) — der Check
  deckt also reine Datenfehler aus Quelle/Import auf, kein Auswertungsrisiko.
- **D4** (`stale_profile_generation.cypher`, identisch wiederverwendet für **R3**): nutzt das
  bereits geladene `Role.profileGenerated` (Loader 22, `AGR_1016B`) — Rollen mit `HAS_AUTH`, aber
  `profileGenerated = false` **oder** fehlendem Status (nie über `AGR_1016B` erfasst).
  Detailliste priorisiert nach Nutzeranzahl. KPI-Kachel-Spaltenreihenfolge korrigiert (zeigte
  vorher die Teilmenge „ohne Generierungsstatus" groß statt der Gesamtzahl, s. Kachel-Konvention
  oben). **Hintergrund/PFCG-Mechanik (auf Nutzer-Rückfrage ergänzt):** in SAP wird eine Rolle
  erst nach dem Generieren des Profils zur Laufzeit wirksam — die Pflege der Berechtigungen in
  `AGR_1251` allein reicht nicht. Eine Rolle mit gepflegten Berechtigungen, aber ohne
  (vollständige) Generierung, ist das klassische **„rote Ampelsymbol" in PFCG**: was in der
  Rolle steht, ist nicht das, was beim User tatsächlich geprüft wird. `profileGenerated IS NULL`
  bedeutet konkret „nie ein `AGR_1016B`-Eintrag protokolliert" — nicht „generiert und dann
  ungültig geworden" (das wäre `profileGenerated = false`). **Zweite KPI-Kachel „betroffene
  User" ergänzt (Ideal: 0):** die Rollenanzahl allein sagt nichts über das aktuelle Risiko — eine
  nicht generierte Rolle ohne Zuweisung ist ein Aufräumkandidat ohne akute Auswirkung, sobald
  aber `>0` User betroffen sind, könnte deren tatsächliche Berechtigung von der gepflegten
  Definition abweichen. Im Testdatenbestand: alle 150 gefundenen Rollen haben `profileGenerated
  = NULL` (nie protokolliert, nicht „ungültig geworden") **und** `betroffene User = 0` — vermutlich
  Rollen-Entwürfe/-Leichen ohne reale Auswirkung, kein akutes Risiko bei echten Usern, aber ein
  sinnvoller Review-Kandidat vor künftiger Zuweisung.

---

## E — Referenzielle Integrität & Import-Vollständigkeit (graph-spezifisch)

| ID | Prüfung | Bedeutung & warum relevant | Prio | Umsetzung |
|----|---------|----------------------------|------|-----------|
| E1 | **`Authorization` ohne `FOR_OBJECT`** (Objekt nicht im `TOBJ`-Import) | Importlücke — die Berechtigung hängt „in der Luft". Verfälscht jede objektbasierte Auswertung. | Hoch | [~] |
| E2 | **`AGR_1251`-Objekt, das nicht in `TOBJ` existiert** | Dangling Reference; oft veraltetes oder kundeneigenes (Z-)Objekt. Hinweis auf unvollständigen Stammdaten-Import. | Mittel | [~] |
| E3 | **TCode in `AGR_TCODES`, der nicht in `TSTC` existiert** | Menüeintrag auf eine nicht (mehr) existierende Transaktion — Rollenmenü-Leiche oder fehlende Import-Tabelle. | Niedrig | [~] |
| E4 | **`Transaction` ohne `CHECKS`-Kante** (kein `USOBX_C`/SU24-Eintrag) | TCode ohne Vorschlagswerte → Brücke TCode→Objekt fehlt, Berechtigungsbezug unklar. Relevant für die Vollständigkeit der Can-Do-Kette. | Mittel | [x] |
| E5 | **Doppelte Knoten je Business-Key** | Sollte durch Constraints verhindert sein; als Absicherung wertvoll, weil Dubletten Zähler und Pfade verfälschen. | Hoch | [x] |
| E6 | **Rowcount-Abgleich Knoten/Kanten gegen Quell-CSV** | Bestätigt die Import-Vollständigkeit (Phase-2-DoD). Ohne diesen Abgleich sind alle anderen Befunde nur so verlässlich wie der Import. | Hoch | [ ] |
| E7 | **Verwaiste `Authorization`-Knoten ohne erreichbaren Rollen-/Profilpfad** | Berechtigung existiert im Graph, aber kein `Role`/`Profile` verweist (mehr) darauf — Karteileiche aus Reorganisation/Teil-Import, verzerrt Auswertungen über alle `Authorization`-Knoten. | Mittel | [x] |

**Implementierungsnotizen Kategorie E** — sechs von sieben Checks mit Cypher (`checks/E.json`):

- **E1/E2/E3 — als `[~]` markiert, bewusste Abweichung von der wörtlichen Katalog-
  Formulierung:** der Loader importiert **kein** `TOBJ`/`TSTC`-Stammdatentabelle, sondern legt
  `:AuthObject`/`:Transaction` **lazy** direkt aus `AGR_1251`/`UST10S`/`USOBT_C`/`AGR_TCODES`
  an — `FOR_OBJECT` existiert dadurch **strukturell immer** (`docs/extraktionsleitfaden.md`,
  Abschnitt „Was hier (noch) NICHT abgebildet ist"). Der wörtliche Check „Authorization ohne
  FOR_OBJECT" liefert mit diesem Loader daher **immer 0 Treffer** — kein praktikabler Befund.
  Operationalisiert als **Proxy**: `AuthObject`/`Transaction` **ohne Text** aus `TOBJT`
  (Loader 13) bzw. `TSTCT` (Loader 09) — liefert echte, nützliche Treffer (z. B. kundeneigene
  Z-Objekte ohne gepflegten Objekttext) und ist die naheliegendste verfügbare Annäherung an
  „nicht im Stammdaten-Import". E1 (`authorizations_without_object_text.cypher`) deckt
  Rollen- **und** Profil-Authorizations ab, E2 (`role_auth_objects_without_text.cypher`) nur
  den auf `AGR_1251` (Rollen) eingeschränkten Fall wie im Katalog benannt, E3
  (`menu_tcodes_without_text.cypher`) den TCode-Fall im Rollenmenü. E3/E4 hatten zudem die KPI-
  Spaltenreihenfolge vertauscht (Sekundärzahl groß statt Hauptzahl) — korrigiert. **Auf
  Nutzer-Feedback „so viele Kacheln":** E1/E2 gruppierten die Zusammenfassung ursprünglich **je
  betroffenem Objekt** — bei vielen unterschiedlichen Objekten (275 bei E1, 19 bei E2 im
  Testdatenbestand) entstand dadurch eine KPI-Kachel pro Objekt statt einer Übersicht. Jetzt
  **eine** Kachel je Statement („`<n>` betroffene Objekte" + Gesamtzahl der Authorizations/
  Rollen); die Aufschlüsselung je Objekt steht unverändert in der Detailliste.
- **E4** (`transactions_without_checks.cypher`): `CHECKS` kommt aus `USOBT_C` (Loader 10) — die
  Katalog-Erwähnung von `USOBX_C` ist die SU24-Schwestertabelle für das Prüfkennzeichen
  (`OKFLAG`, „aktiv/unterdrückt"), die laut `docs/extraktionsleitfaden.md` nicht extrahiert
  wird; der Check prüft daher gegen die tatsächlich geladene Kante. Liefert auf dem aktuellen
  Datenstand eine sehr hohe Zahl (viele `TSTCT`-Transaktionen ohne `USOBT_C`-Vorschlagswerte) —
  plausibel bei einem nur teilweise SU24-gepflegten Mandanten, kein Hinweis auf einen Fehler im
  Check selbst.
- **E5** (`duplicate_business_keys.cypher`) — **Regressions-Guard:** die Unique-Constraints aus
  `migrations/V001__constraints.cypher` verhindern echte Dubletten bereits auf DB-Ebene; dieser
  Check sollte auf einer korrekt migrierten Instanz immer 0 liefern und dient als Absicherung
  (z. B. frische Instanz ohne gelaufene `neo4j-migrations`). Verifiziert: 0 Treffer auf dem
  aktuellen Datenstand.
- **E6 — bleibt offen:** setzt die in Phase 9 noch nicht gebaute **Import-Evidenz**
  (persistente Quellzeilen-Statistik je Tabelle, `(:ImportTable)`) voraus — aktuell gibt es nur
  die flüchtige Konsolenausgabe aus `load/99_validate.cypher`, keine im Graph gespeicherte
  Quell-Rowcount-Referenz zum Abgleich. Nachzuziehen, sobald Phase 9 „Import-Evidenz" steht.
- **E7** (`orphaned_authorizations.cypher`) — ebenfalls **Regressions-Guard**: unter dem
  aktuellen Loader (08/18 legen `Authorization` und `HAS_AUTH` immer gemeinsam an) sollte dies
  nur nach nachträglichen Teil-Löschungen auftreten. Verifiziert: 0 Treffer auf dem aktuellen
  Datenstand.

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
| R1 | **Rollen ohne generiertes Profil** (`AGR_DEFINE` ohne `AGR_PROF`) | Rolle wurde nie generiert → trägt zur Laufzeit **keine** Berechtigung. Unfertige Rolle oder Karteileiche; Zuweisungsempfänger haben evtl. weniger Rechte als angenommen. | Hoch | [x] |
| R2 | **Rollen ohne Berechtigungsdaten** (keine `AGR_1251`) | Menürolle ohne Objekte — TCodes im Menü, aber nichts gepflegt. Design-Fehler oder reine „Navigationsrolle". | Mittel | [x] |
| R3 | **Veraltet generierte / nicht lauffähige Rollen** (Rolle nach letzter Profilgenerierung geändert — „rot" in PFCG) | Klassische „ungültige" Rolle: die laufzeitwirksame Berechtigung weicht von der gepflegten Definition ab. Auswertung auf Definitionsbasis täuscht dann. | Hoch | [x] |
| R4 | **Sammelrolle ohne Einzelrollen** (`Composite` ohne `CONTAINS`) | Leere Sammelrolle ohne Wirkung. Designfehler oder Rest aus einem Umbau. | Niedrig | [x] |
| R5 | **Abgeleitete Rolle ohne gültigen Master** (`Derived` ohne `DERIVED_FROM`) | Gebrochene Ableitung; zentrale Master-Pflege greift nicht durch, Org-Werte laufen ins Leere. | Mittel | [ ] |
| R6 | **Abgeleitete Rolle weicht über Org-Ebenen hinaus vom Master ab** | Ableitungskonzept verletzt — eine Ableitung sollte sich nur in Org-Werten unterscheiden. Abweichungen deuten auf manuelle Eingriffe und Wildwuchs. | Mittel | [ ] |
| R7 | **Master-Rolle mit direkt gepflegten Org-Werten** statt Org-Variablen | Hebelt das Ableitungskonzept aus: feste Org-Werte im Master verhindern saubere Ableitungen. Wartbarkeitsrisiko. | Niedrig | [ ] |

---

## Zuordnung & Reichweite

| ID | Prüfung | Bedeutung & warum relevant | Prio | Umsetzung |
|----|---------|----------------------------|------|-----------|
| R8 | **Rollen ohne jegliche Nutzerzuordnung** (keine aktive `AGR_USERS`, auch nicht über eine Sammelrolle) | Tote Rollen → Aufräumkandidaten. Reduzieren Komplexität und Angriffsfläche im Rollenbestand. Großer Anteil deutet auf fehlende Rollen-Lifecycle-Pflege. | Mittel | [x] |
| R9 | **Rollen nur mit abgelaufenen Zuordnungen** (alle `AGR_USERS` außerhalb der Gültigkeit) | Faktisch ungenutzt, am Stichtag aber leicht als „zugewiesen" fehlgezählt. Validiert zugleich die Stichtagslogik. | Mittel | [x] |
| R10 | **Top-N Rollen nach Anzahl Nutzerzuordnungen** | Reichweitenstärkste Rollen — hier wirkt jede Änderung am breitesten. Priorisierungssicht für Review, Rezertifizierung und Risikoeinschätzung. | Analytik | [x] |
| R11 | **Rollen mit genau einem Nutzer** (personengebundene Sonderrollen) | „1:1"-Rollen sind oft manueller Wildwuchs oder Schattenlösungen am Rollenkonzept vorbei; Konsolidierungs-/Bereinigungskandidaten. | Niedrig | [x] |
| R12 | **„Mega"-Sammelrollen** (auffällig viele Einzelrollen / sehr breite Berechtigungsmenge) | Hohe Komplexität erschwert Nachvollziehbarkeit und begünstigt unbeabsichtigte SoD-Kombinationen. Kandidaten für Aufteilung. | Mittel | [x] |

---

## Risiko & SoD

| ID | Prüfung | Bedeutung & warum relevant | Prio | Umsetzung |
|----|---------|----------------------------|------|-----------|
| R13 | **Rollen mit Intra-Rollen-SoD-Konflikt** (built-in / conflicting-by-design) | Die Rolle bündelt selbst zwei konfligierende Funktionen — jeder Träger erbt den Konflikt. Design-Fehler an der Wurzel, hoch wiederverwendbar als Befund. | Hoch | [x] |
| R14 | **Top-N Rollen nach Anzahl built-in SoD-Konflikte** | Rangliste der problematischsten Rollendesigns. Steuert, wo Redesign den größten Hebel hat. | Analytik | [x] |
| R15 | **Konflikt-Hotspot-Rollen** (am häufigsten an **Inter**-Rollen-Konflikten beteiligt) | Rollen, die in Kombination mit vielen anderen Konflikte erzeugen. Auch wenn jede für sich sauber ist, sind sie die wirksamsten Stellschrauben zur Konfliktreduktion. | Hoch | [x] |
| R16 | **Rollen mit kritischen Inhalten** (enthalten `SAP_ALL`-äquivalente Profile, weite `S_TABU_DIS`/`S_TABU_NAM`, Debug-Replace `S_DEVELOP ACTVT 02`, `*` auf kritischen Org-Ebenen) | Hochrisiko-Berechtigung gebündelt in einer Rolle — verteilt sich über jede Zuweisung. Erstrangige Review-Kandidaten. | Hoch | [x] |

---

## Wartbarkeit & Design

| ID | Prüfung | Bedeutung & warum relevant | Prio | Umsetzung |
|----|---------|----------------------------|------|-----------|
| R17 | **Redundante Rollen** (identische bzw. nahezu identische Berechtigungsmenge unter verschiedenen Namen) | Dubletten blähen den Bestand auf, erschweren Pflege und führen zu inkonsistenten Änderungen. Konsolidierungskandidaten. | Mittel | [x] |
| R18 | **Stark überlappende Rollen** (großer gemeinsamer Berechtigungsanteil) | Hinweis auf fehlende Modularisierung; Kandidaten für eine gemeinsame Basisrolle. Senkt langfristig SoD-Risiko und Pflegeaufwand. | Niedrig | [x] |

**Implementierungsnotizen Kategorie R** — 15 von 18 Checks mit Cypher (`checks/R.json`):

- **R1/R2** (`roles_without_generated_profile.cypher`/`roles_without_auth_data.cypher`):
  spiegelbildlich — R1 prüft fehlendes `HAS_PROFILE` (Rolle nie generiert), R2 fehlendes
  `HAS_AUTH` (Rolle ohne Berechtigungsdaten, ggf. reine Menürolle).
- **R3** (`stale_profile_generation.cypher`) — **bewusst dieselbe Cypher-Datei wie D4**: beide
  Checks beschreiben exakt denselben Befund (Rolle mit `HAS_AUTH`, aber `profileGenerated =
  false`/fehlend) aus zwei Blickwinkeln (Datenqualität vs. Rollenqualität) — analog zur
  Dedup-Logik, die frühere C-Checks nach `R` verschoben hat (s. Hinweis oben). Kein Mehraufwand,
  ein gepflegter Cypher-Stand.
- **R4** (`composite_roles_without_children.cypher`) — **Regressions-Guard**: das Label
  `Composite` wird in `load/90_finalize.cypher` genau dann gesetzt, wenn eine Rolle eine
  ausgehende `CONTAINS`-Kante hat — der wörtliche Befund ist also durch die Labelvergabe
  ausgeschlossen; der Check sichert nur ab, dass diese Invariante hält. Verifiziert: 0 Treffer.
- **R8** (`roles_without_user_reach.cypher`): Reichweite über `CONTAINS*0..` rückwärts (beliebig
  tief verschachtelte Sammelrollen) **plus** direkte `ASSIGNED_TO`, jeweils stichtagsgefiltert
  auf der `ASSIGNED_TO`-Kante (`CONTAINS` trägt keine eigene Gültigkeit, AE-07/08).
- **R9** (`roles_only_expired_assignments.cypher`): Rolle hat mindestens eine Zuordnung, aber
  ALLE liegen außerhalb der Gültigkeit zum Stichtag — Gegenstück zu „komplett ohne Zuordnung"
  (R8).
- **R12** (`mega_composite_roles.cypher`): Schwelle = 95. Perzentil der transitiv enthaltenen
  Einzelrollenanzahl über alle Composite-Rollen, adaptiv wie A7/`role_profile_count_outliers`.
- **R13–R15** (`roles_with_intra_conflict.cypher`/`top_roles_by_intra_conflicts.cypher`/
  `inter_conflict_hotspot_roles.cypher`) — **wichtige Einordnung:** diese Checks setzen die
  abgeleitete SoD-Snapshot-/Evidenz-Schicht (Phase 3, `explain_sod.cypher`) voraus. Der
  generische Konsistenzcheck-Run-Endpoint kennt aber keine `runId` (nur `dataset`/`asOf`) —
  daher verwenden alle drei automatisch den **jüngsten `(:Run)` des Datasets** (über alle
  Rulesets, sortiert nach `generatedAt`). Wurde für diesen Lauf keine Evidenz berechnet oder
  existiert noch kein Lauf, liefern sie **0 Treffer statt eines Fehlers** — das bedeutet „keine
  Aussage möglich", nicht zwingend „keine Konflikte". Verifiziert: aktuell kein passender Lauf
  im Testdatenbestand vorhanden → erwartungsgemäß 0 Treffer. R13s KPI-Kachel zeigte zudem den
  Lauf-Namen (Text) groß statt der Trefferzahl — korrigiert (s. Kachel-Konvention oben).
- **R16** (`roles_with_critical_content.cypher`): wiederverwendet dieselbe Kritisch-Definition
  wie A3/A4/A6, jetzt direkt auf Rollenebene (`HAS_AUTH`/`HAS_PROFILE` an der Rolle statt am
  User). Läuft auf dem Testdatenbestand ca. 20 Sekunden (Org-Wildcard-Teilabfrage über alle
  `OrgField`-Werte je sensiblem Objekt) — spürbar, aber im Rahmen eines manuell ausgelösten
  Einzelchecks akzeptabel.
- **R17** (`redundant_roles.cypher`): **Fingerprint-Ansatz statt paarweisem Vergleich** —
  gruppiert Rollen nach der sortierten Liste ihrer referenzierten `AuthObject`-IDs, skaliert auf
  große Rollenbestände (kein `O(n²)`). Bewusst **grobkörnig**: vergleicht nur die Objektmenge,
  nicht die Feldwerte innerhalb der Authorizations — taugt als erste Kandidatensichtung, nicht
  als abschließender Dublettenbeweis.
- **R18** (`overlapping_roles.cypher`) — **bewusst begrenzter Umfang (v1):** ein vollständiger
  paarweiser Vergleich über alle Rollen ist `O(n²)` und bei mehreren tausend Rollen in reinem
  Cypher nicht praktikabel. Eingeschränkt auf Rollen mit einer kleinen, nicht-trivialen
  Objektmenge (2–15 Objekte) — deckt typische, gut vergleichbare Fälle ab, nicht aber große
  Sammelrollen. Auf dem aktuellen Testdatenbestand (~3.100 Rollen in diesem Größenfenster, rund
  4.900 Rollenpaare mit Jaccard ≥ 0,8) lief der Check in wenigen Sekunden durch. Bei Bedarf
  später durch einen außergraph-basierten Ansatz (MinHash/LSH) für den vollen Rollenbestand
  ersetzen.

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
  **Spaltenüberschriften** kommen 1:1 aus den Cypher-`RETURN ... AS`-Aliasen — auf Nutzer-
  Feedback („sehen unprofessionell aus") läuft das nicht mehr roh durch, sondern über eine feste
  Übersetzungstabelle `CC_COLUMN_LABELS` (`frontend/index.html`, z. B. `gueltigVon`→„Gültig
  von", `nutzerAnzahl`→„Anzahl Nutzer") mit generischem camelCase-Fallback (Wortgrenzen
  auftrennen + erster Buchstabe groß) für alles, was die Tabelle nicht kennt. **Sortierbare
  Spalten** (ebenfalls auf Nutzer-Feedback): Klick auf einen Spaltenkopf sortiert die
  Detailtabelle nach dieser Spalte (numerisch, wenn alle Werte Zahlen sind, sonst alphabetisch
  via `localeCompare('de')`), erneuter Klick dreht die Richtung um; ein kleines Dreieck (▲/▼)
  markiert Spalte + Richtung. Rein clientseitig auf dem zuletzt geladenen Ergebnis, kein
  erneuter Server-Request.
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
