# Funktionsreferenz

Was macht welcher Befehl in der Ribbon-Bar — und was bedeuten die Auswahlmöglichkeiten.

## Banner

Oben links die Wortmarke, oben rechts der **Hell/Dunkel-Umschalter** (merkt sich die Wahl im
Browser), der Chip mit dem **aktiv angewendeten Ruleset** des gerade angezeigten Laufs sowie zwei
weitere **Status-Chips**: Verbindung zur Datenbank und der Kontext **„N Datasets · M Läufe"**
(aktualisiert sich nach jeder Aktion).

## 1 · Daten

| Befehl | Wirkung |
| --- | --- |
| **Import** | Öffnet den Import-Dialog: **ZIP hochladen** (`.txt`/`.csv` im ZIP) oder **vorhandener Ordner**. Startet den Import-Job (konvertieren → Schema → laden → prüfen). |

Optionen im Dialog: **Sprachen** (für sprachabhängige Texttabellen, Standard `DE,DEU,D`),
**Schema überspringen** (wenn Constraints/Indizes schon da sind), **Konvertierung überspringen**
(wenn bereits `.csv` vorliegen).

## 2 · Auswertung

| Befehl | Wirkung |
| --- | --- |
| **Neuer Lauf** | Öffnet das Parameter-Formular und startet Materialisierung + SoD-Auswertung. |

### Nutzertyp-Profil

Welche Benutzer in die Auswertung eingehen:

| Profil | Bedeutung |
| --- | --- |
| **all** | alle Benutzertypen, inkl. gesperrte. |
| **dialog-service** | Dialog + Service (A/S), inkl. gesperrte. |
| **dialog-active** | Dialog + Service **und nicht gesperrt** — die audit-relevante Sicht. |
| **dialog-only** | nur Dialog (A). |

> Benutzertyp und „gesperrt" sind zwei getrennte Achsen: A/S sagt nichts über aktiv/gesperrt aus.
> `dialog-active` kombiniert beides.

### Org-Profil

Ob die Auswertung auf Organisationsebenen (z. B. Buchungskreis) eingeschränkt wird:

| Modus | Bedeutung |
| --- | --- |
| **Standard** | keine Org-Einschränkung — *„kann der Benutzer die Funktion überhaupt?"* |
| **Übergreifend** | zählt nur, wenn die Berechtigung den vollen Bereich (`*`) trägt. |
| **Gefiltert** | je Org-Feld eine Bedingung (UND/ODER/Bereich) — über Profile vorkonfiguriert. |

> Die Org-Filterung wirkt über **alle** Org-Ebenen (Buchungskreis `BUKRS`, Werk `WERKS`, Einkaufsorg
> `EKORG`, Verkaufsorg `VKORG`, …, aus USORG) **und Kombinationen** (z. B. Buchungskreis *und*
> Einkaufsorg). Bewertet werden die **echten Berechtigungswerte** der Nutzer (aus den Rollen-/
> Profil-Auths), nicht SU24-Vorschläge. Der gewählte Modus/Filter wird am Lauf protokolliert.

### Einzelfilter-Umfang

Welche Queries des Rulesets die Materialisierung überhaupt betrachtet (`(:User)-[:MATCHES]->(:Query)`
— die Grundlage sowohl der SoD-Auswertung als auch der Einzelfilter-Ansicht/-Übersicht):

| Modus | Bedeutung |
| --- | --- |
| **Alle Einzelfilter + SoD** (Standard) | materialisiert **jede** Query des Rulesets, auch solche, die in keiner SoD-Regel als Klausel verbaut sind. |
| **Nur SoD-relevante Einzelfilter** | beschränkt die Materialisierung auf genau die Queries, die die SoD-Regeln dieses Rulesets tatsächlich brauchen — schneller, aber die Einzelfilter-Ergebnisse/-Übersicht zeigen dann nur diese (ruleset-abhängige) Teilmenge. |

> „Alle" berechnet spürbar mehr Queries als „Nur SoD-relevant" und dauert entsprechend länger —
> bei einem Katalog mit deutlich mehr Einzelfiltern als SoD-Klauseln ein Vielfaches. Der Mehraufwand
> fällt nur beim **ersten** Lauf je Stichtag an: „Materialisierung überspringen" (s. u.) nutzt bei
> Wiederholungsläufen das bereits berechnete Zwischenergebnis weiter. Welche Queries als „SoD-
> relevant" gelten, hängt vom jeweiligen Ruleset ab (z. B. andere Zahl bei einem anderen
> Filterset) und wird am Lauf gespeichert (`queryScope`) — Einzelfilter-Auswahl/-Übersicht eines
> Laufs zeigen immer genau die Queries, die in **diesem** Lauf tatsächlich materialisiert wurden.

### Voreinstellung (statt „Einzelfilter-Umfang"/Nutzertyp-Profil/Sleeping)

Neben dem groben „alle/nur SoD-relevant"-Umfang oben lässt sich der nächste Lauf auch auf ein
**gezielt gewähltes Subset** an Einzelfiltern und/oder SoD-Regeln einschränken — **und** dabei
gleich **Nutzertyp-Profil** und **Sleeping (Tage)** mitbestimmen — über das Feld **„Gespeicherter
Scope"** im Formular. Zwei Quellen speisen diese Voreinstellung, mit fester Priorität:

1. **Ein gespeicherter Scope** (Auswahl im Dropdown) — angelegt über die Admin-Seite **„Scope"**
   (s. u.), wiederverwendbar über beliebig viele Läufe/Datasets desselben Rulesets hinweg.
2. **Eine Ad-hoc-Auswahl aus der geführten Auswertung** (Assistent, Schritt „Scoping", Stufe
   „SoD-Regeln") — gilt nur für die laufende Sitzung, verschwindet beim Neustart des Assistenten.
3. Ist beides leer, bleiben „Einzelfilter-Umfang", Nutzertyp-Profil und Sleeping wie gewohnt
   eigene, frei editierbare Felder (heutiges Standardverhalten).

Ist eine der beiden Quellen aktiv, ersetzt eine Zusammenfassungszeile den „Einzelfilter-Umfang"-
Umschalter **und** blendet die eigenen Felder für Nutzertyp-Profil/Sleeping aus — die
Voreinstellung bestimmt alle drei. Zwei Auswertungsarten ergeben sich automatisch aus der
Einzelfilter-/SoD-Auswahl: **nur Einzelfilter** (keine SoD-Regel dabei) materialisiert
ausschließlich diese Einzelfilter und überspringt die SoD-Auswertung komplett („Can-Do"); sind
**auch SoD-Regeln** ausgewählt, materialisiert der Lauf nur deren Klausel-Queries (statt aller
SoD-relevanten Queries des Rulesets) und wertet nur diese Regeln aus.

### Weitere Parameter

- **Stichtag** — Bewertungsdatum (Rollen-Gültigkeit + Sleeping). **Keine Eingabe mehr**, sondern
  eine Eigenschaft des gewählten Datasets (= Downloaddatum der SAP-Extrakte): wird beim
  Erst-Import automatisch aus den Dateizeitstempeln der Extrakte ermittelt und nur angezeigt;
  eine bewusste Korrektur läuft über „ändern…" neben der Anzeige und wirkt **global** auf alle
  künftigen Läufe/Checks dieses Datasets, nicht nur den nächsten.
- **Sleeping (Tage)** — Schwelle „kein Logon seit X Tagen" (Standard 180), frei wählbar.
- **Mindest-Kritikalität** — `alle` · ab `medium` · ab `high` · ab `critical` · nur `very-critical`.
- **Materialisierung/Ruleset-Laden überspringen** — Beschleuniger für Wiederholungsläufe.

## 3 · Ergebnisse

Gruppen mit mehreren Befehlen (hier sowie unter „Admin") klappen als **Menü** auf — Klick auf die
Gruppe öffnet eine Liste der Befehle, Klick daneben oder auf einen Befehl schließt sie wieder
(verhält sich wie ein gewohntes Anwendungsmenü statt nebeneinanderliegender Buttons).

| Befehl | Wirkung |
| --- | --- |
| **Aktualisieren** | lädt Läufe, Datasets, Backups neu. |
| **Evidenz** | berechnet VIA_ROLE/VIA_PROFILE + intra/inter für den aktiven Lauf nach — seit Evidenz-Perf standardmäßig Teil jedes neuen Laufs, dieser Befehl ist nur noch für ältere Läufe ohne Evidenz oder nach „Evidenz überspringen" im Lauf-Formular nötig. |
| **Export CSV/PDF** | Exportiert **exakt die gerade sichtbare Ansicht** — Beschriftung und Format wechseln automatisch: Findings, Matches, Einzelberechtigungen-/SoD-Übersicht und Nutzerliste (jeweils echte Tabellen) gehen als **CSV**, mit denselben aktiven Filtern/derselben Sortierung wie auf dem Bildschirm; ohne aktive Filter der komplette Lauf. Rollen-Detail und Root-Cause (keine flache Tabelle) gehen als **PDF** über den Browser-Druckdialog („Als PDF speichern"). Findings-Export enthält auch die Regel-**Bezeichnung** (nicht nur die ID). |
| **Einzelberechtigungen** | Übersicht: **jede** Query mit mindestens einem Treffer in diesem Lauf (innerhalb des am Lauf gewählten Einzelfilter-Umfangs, s. „Neuer Lauf"), mit Kritikalität und Anzahl matchender User. Kachel oben zeigt die **distinkte** Gesamtzahl betroffener User über alle Zeilen (kein Aufsummieren der Einzelzeilen, da ein User meist mehrere Queries matcht). Klick auf eine Zeile springt in die normale Einzelfilter-Ansicht, gefiltert auf genau diese Query. |
| **SoD-Regeln** | Dieselbe Übersicht für SoD-Regeln (Anzahl verletzender User statt matchender, Kachel entsprechend). Klick springt in die normale Findings-Ansicht, gefiltert auf diese Regel. |

Im Hauptbereich: **KPI-Kacheln** (s. u.), **Läufe-Liste** (Klick = Lauf laden; jede Karte zeigt
Bezeichnung, Stichtag und Erstellungs-Datum/-Zeit) und die **Ergebnistabelle** (Findings oder
Matches, je nach Ergebnistyp — s. u.).

### Filter

Links in der Sidebar: **Nutzertyp** (Ankreuz-Dropdown — A/B/S/C/L = Dialog/System/Service/
Communication/Reference), **User**, **Einzelberechtigung** und **SoD** — beide zeigen **ID +
Bezeichnung** (Kurzbezeichnung, falls gepflegt, sonst die Langbezeichnung); die ID steht
**voran**, damit sie bei langen Bezeichnungen nicht durch die feste Dropdown-Breite abgeschnitten
wird. Auswahl wendet über „Filtern" an bzw. sofort bei Klick auf eine User-Zelle in der
Findings-Tabelle. Ist ein **User** gewählt, schränken sich **Einzelberechtigung**- und
**SoD**-Dropdown automatisch auf das für ihn tatsächlich Gefundene ein (kaskadierender Filter)
statt immer den vollen Katalog/alle Lauf-Regeln zu zeigen. **Einzelberechtigung**/**SoD** zeigen
außerdem von sich aus nur das, was für **diesen Lauf** tatsächlich in Frage kam: lief der Lauf
mit einer Katalog-Auswahl/Voreinstellung (s. „Voreinstellung" oben), stehen nur die dabei
gewählten Einzelfilter bzw. SoD-Regeln zur Auswahl — nicht der gesamte Ruleset-Katalog.

Über der Ergebnistabelle, in einer eigenen Zeile: **Kritikalität** (very-critical…low) immer,
**Ergebnistyp** (`alle` / `Einzelfilter` / `SoD`) **nur außerhalb der Einstiegstabelle** (s. u.)
und — nur bei Ergebnistyp „alle" — **Sleeping** (`alle` / `nur sleeping` / `nicht sleeping` /
`unbekannt`) sowie **Gesperrt** (`alle` / `gesperrt` / `nicht gesperrt`) als farbige Klick-Buttons
(Pills), wirken sofort. Bei „nur sleeping"/„nicht sleeping" erscheint zusätzlich eine
**Tage-Schnellwahl** (`Lauf-Standard` / `90` / `180` / `360`) — weicht sie vom beim Lauf gesetzten
`sleepDays`-Fenster ab, rechnet der Filter live gegen das Logon-Datum statt gegen den beim Lauf
materialisierten Wert (funktioniert nur, wenn TRDAT im Extrakt vorhanden ist). Bei „gesperrt"
erscheint zusätzlich der **Sperrgrund** (`alle` / `Fehlanmeldungen` / `Admin (lokal)` /
`Admin (global)`, aus dem UFLAG-Bitfeld) — wirkt nur für Läufe, die gesperrte User nicht bereits
beim Materialisieren ausgeschlossen haben (Nutzertyp-Profil ohne „nicht gesperrt", s. o.), sonst
fehlen deren Findings von vornherein. Rechtsbündig in derselben Zeile: der **Tabelle/
Graph-Umschalter** (Graph ist als Vorgriff auf das künftige Cytoscape.js-Frontend angelegt,
für SoD-Konfliktpfade aktuell noch deaktiviert — „kommt später"; für die Konsistenzchecks A1–A3
bereits scharf, s. Kapitel Konsistenzchecks). „Einzelfilter" zeigt die **Matches-Tabelle** („wer matcht
welche Query") auch **ohne** vorher eine konkrete Einzelberechtigung in der Sidebar zu wählen —
dann für alle Queries, sonst nur für die gewählte.

**Einstiegstabelle.** Ist **kein** Filter aktiv (frisch geladener Lauf bzw. „Zurücksetzen"), zeigt
die letzte Spalte **Sleeping** statt **Root-Cause** und die Ergebnistyp-Pillzeile ist ausgeblendet
— bei (potenziell hunderten) ungefilterten Findings lohnt der Root-Cause-Absprung pro Zeile noch
nicht. Sobald irgendein Filter greift (User, Regel, Kritikalität, Nutzertyp, Ergebnistyp), wechselt
die letzte Spalte zu **Root-Cause** und die Ergebnistyp-Pillzeile erscheint.
„SoD"/„alle" zeigen die **Findings-Tabelle**. Ein aktiver Filter erscheint zusätzlich als Chip mit
„zurücksetzen".

### Nutzerzentrische Auswahl: KPI-Kacheln, verursachende Rollen

Sobald ein **User** gefiltert ist, ersetzt eine **Stammdaten-Kachel** (UserID · Name · Typ ·
Status, über `GET /users/{id}`) die KPI-Kachel an der Stelle, an der sonst nichts Drittes stünde.
Wählt man zusätzlich eine **Regel** (z. B. über den Root-Cause-Zugang, s. u.), bleibt der
User-Filter erhalten und ein Chip **„Regel: …"** erscheint oben über den KPI-Kacheln (additiver
Drill-down: erst Nutzer, dann Nutzer **und** Regel — nicht exklusiv).

Sind **User und Regel zusammen** gesetzt (genau ein Finding), erscheint unter den KPI-Kacheln ein
eigenes Feld **„Verursachende Rollen/Profile"** — die Rollen/Profile, die laut Evidenz
(`VIA_ROLE`/`VIA_PROFILE`) diesen Konflikt auslösen, plus ein eigener **Root-Cause**-Button (s. u.).
Ohne berechnete Evidenz (Ribbon „Evidenz" nicht ausgeführt) erscheint dort ein Hinweis statt der
Liste.

### Root-Cause

Sowohl die **Findings-Tabelle** (SoD) als auch die **Matches-Tabelle** („wer matcht", Einzelfilter)
haben pro Zeile einen **„Root-Cause"**-Button. Er wechselt (kein Dialog/Overlay, wie die
Findings-/Konsistenzcheck-Ansicht) auf eine **eigene Seite** mit „← zurück" — oben die gesuchte
**Query bzw. SoD-Regel** mitsamt ihrer Kurz-/Langbezeichnung (aus dem bereits geladenen
Queries-/SoD-Cache, keine neue Anfrage), darunter der allgemeine Erklärtext und gruppiert **pro
Berechtigungsobjekt** der Query (Überschrift mit Klammerzusatz „(Berechtigungsobjekt-Prüfung)",
analog „S_TCODE (TCode-Prüfung)") — bei einer SoD-Regel zusätzlich **pro Klausel** (für die
tatsächlich vom User gematchte Query dieser Klausel, Block-Überschrift zeigt zusätzlich deren
Bezeichnung): je Objekt zunächst die **Anforderung** — `FELD (UND/ODER): Wert1, Wert2, …` —,
darunter die **Rolle(n)/Profil(e)**, die genau dieses Objekt mit welcher konkreten Authorization
erfüllen; der jeweils tatsächlich zutreffende Wert (bzw. `*`/ein abdeckender Bereich) ist darin
grün hervorgehoben — auf einen Blick erkennbar, **warum** eine Zeile matcht, ohne Anforderung und
Werte manuell zu vergleichen. Anders als die Evidenz (die nur „welche Rolle" zeigt) macht das
sichtbar, wenn **verschiedene Objekte/Klauseln durch verschiedene Rollen** gedeckt werden — der
eigentliche Root-Cause, nicht nur der Träger des Konflikts.

Ein Umschalter **„ohne technische" / „alle (inkl. technisch generierte)" / „nur generierte Rollen"**
über der Ergebnisliste steuert, welche Akteure gezeigt werden. **„ohne technische"** (Default)
blendet SAP-generierte Profile aus: ein direkt zugewiesenes Profil gilt als „technisch", wenn
irgendeine Rolle im Datenbestand dieses Profil erzeugt (Role-`HAS_PROFILE`, unabhängig vom
betrachteten User) **oder** der Name mit `T-` beginnt (Namens-Fallback für „verwaiste" generierte
Profile, deren erzeugende Rolle im Extrakt nicht mehr existiert — die Berechtigung bleibt laut
`UST04` trotzdem aktiv, daher bewusst **nicht** verborgen, sondern mit Hinweistext versehen).
**„alle"** zeigt zusätzlich diese technischen Profile. **„nur generierte Rollen"** zeigt die
**Laufzeitsicht**: nur Rollen, die über ihr **generiertes Profil** tatsächlich aktiv sind (das, was
in `UST04` zieht) — reine Design-Zeilen ohne Profil-Deckung (D4-Divergenz) fallen weg —, **plus**
direkt zugewiesene Profile (z. B. `SAP_ALL`), damit kein kritischer Direktzugriff aus dem Bild
fällt. In den **Graph-Ansichten** wird in diesem Modus zusätzlich jeder Akteur nur **einmal**
gezeigt (Dedup über alle Objekte), was den Graphen deutlich verschlankt. Ein Zähler bzw. Hinweis
zeigt, wie viele Zeilen aktuell ausgeblendet sind.

Die Graph-Ansichten haben außerdem einen **Vollbild**-Button und einen **Zoom-Regler** am rechten
Rand für schnelles Rein-/Rauszoomen.

**Ansicht Tabelle · Pfadgraph · Radial.** Über der Ergebnisliste schaltet ein zweiter Umschalter
zwischen der **Tabelle** (Default, mit allen Anmerkungen unten) und zwei **Graph-Darstellungen
derselben Daten** um. Der **Pfadgraph** zeigt den Weg **User → Regel → Klausel → Query →
Berechtigungsobjekt → Rolle/Profil** als Baum von oben nach unten; die **Radiale** Ansicht setzt
den User ins Zentrum und legt die Ursachen ringförmig nach außen. Farben unterscheiden
Regel/Klausel/Query/Objekt/Rolle/Profil; **technische/generierte** Profile sind gestrichelt und
blasser, **verwaiste** rot umrandet, ein Treffer **„über generiertes Profil"** als rote gestrichelte
Kante; **UND/ODER** stehen an den Kanten (braucht der User *alle* oder *eine* Voraussetzung). Der
„ohne technische"-Filter wirkt auch hier. Ein Klick auf einen Knoten hebt seinen Pfad hervor (Rest
ausgegraut), Hover zeigt Details (technisch/„via"/konkrete Feldwerte), „Einpassen" zentriert die
Ansicht. Die Graph-Ansicht ergänzt die Tabelle für den Überblick — für den lückenlosen Wert-für-Wert-
Abgleich (grün hervorgehobene Treffer, D4-Divergenz-Link) bleibt die Tabelle die Detailsicht.

**Quellenkennzeichnung.** Derselbe Akteur kann einen Treffer über **mehrere Quellen** erreichen —
das wird je Zeile als kurze Anmerkung kenntlich gemacht. Wertidentische Paare aus eigener Definition
und generiertem Profil werden dabei zu **einer** Zeile zusammengefasst (das Profil ist dann nur die
kompilierte Form der Definition); nur bei **abweichenden** Werten bleiben beide Zeilen stehen — das
ist der aussagekräftige Divergenzfall (→ D4). Mehrere Zeilen für dieselbe Rolle mit
**unterschiedlichen** Werten sind also kein Anzeige-Fehler, sondern echte, verschiedene
Berechtigungsinstanzen bzw. eine Design-≠-Generiert-Divergenz:

| Anmerkung | Bedeutung |
| --- | --- |
| **(eigene Definition)** | Die Rolle trägt die Berechtigung direkt selbst (`AGR_1251` → Role-`HAS_AUTH`) — erscheint nur, wenn es für denselben Akteur zusätzlich eine zweite Quelle gibt. |
| **(eigene Definition = generiertes Profil X)** | Eigene Definition **und** das generierte Profil X tragen für dieses Objekt **exakt dieselben** Werte — das Profil ist hier nur die kompilierte Form der Definition. Beide werden dann zu **einer** Zeile zusammengefasst (statt zweier wertidentischer Zeilen). |
| **(über generiertes Profil X)** | Kommt über das von der Rolle generierte Profil X (Role-`HAS_PROFILE`→Profile-`HAS_AUTH`) — das, was beim Benutzerabgleich tatsächlich in `UST04` geschrieben und zur Laufzeit geprüft wird. Erscheint eigenständig nur, wenn es von der eigenen Definition **abweicht** (sonst zusammengefasst, s. o.). |
| **(über enthaltene Rolle X)** | Die angezeigte Rolle ist eine **Sammelrolle**, die Rolle X als Einzelrolle bündelt (`CONTAINS`); X selbst trägt die Berechtigung. |

Fallen „eigene Definition" und „generiertes Profil" für **dasselbe** Berechtigungsobjekt
**auseinander** (unterschiedliche Werte je Feld), erscheint zusätzlich ein roter Link
**„weicht vom generierten Profil ab · D4"**, der direkt zur Detailansicht des Konsistenzchecks
**D4** („veraltete/nicht generierte Profile") springt. Hintergrund: in SAP wird eine Rolle erst
nach dem Generieren des Profils zur Laufzeit wirksam — weicht die gepflegte Definition vom
generierten Profil ab, zeigt die „eigene Definition"-Zeile etwas, das ggf. **nicht** (mehr) aktiv
ist. Diese Annahme (Rollendefinition ≈ generiertes Profil) ist keine Root-Cause-Eigenheit, sondern
gilt für die gesamte Can-Do-/SoD-Auswertung der App (`materialize_matches_*.cypher`); D4 ist der
dafür vorgesehene Konsistenzcheck.

**Gruppierung + Werte-Filter.** Eine Rolle mit **mehreren Berechtigungsinstanzen** für dasselbe
Objekt (in SAP zulässig; die Instanzen dürfen **nicht** aggregiert werden, s. AE-03) erscheint
**einmal** als Kopf, ihre matchenden Instanzen darunter eingerückt — statt vieler Zeilen mit
gleichem Rollennamen. Ein zweiter Umschalter **„alle" / „nur Treffer"** (Default **„nur Treffer"**)
zeigt wahlweise alle Feldwerte (Treffer grün markiert) oder **nur** die zur Anforderung passenden
Werte (ohne Markierung) — hilfreich bei Rollen mit sehr vielen TCodes/Werten. Wirkt gleichermaßen in
der Tabelle wie in den **Graph-Ansichten** (Knoten-Label + Hover-Tooltip zeigen dieselbe Reduktion);
liefert die Reduktion für ein Feld keinen Treffer (z. B. weil der Treffer nur über ein anderes Feld
zustande kommt), fällt die Anzeige auf die vollen Werte zurück statt leer zu bleiben.

**Rolle anklickbar → Detailseite.** Rollennamen (Tabelle) bzw. Rollen-Knoten (Graph) öffnen per
Klick eine **Rollen-Detailseite** (die linke Filter-/Läufe-Sidebar bleibt dabei sichtbar). Oben
immer sichtbar die **Stammdaten** (Beschreibung, Subtyp, Elternrolle, generiertes Profil +
Generierungsstatus inkl. Profilstatus-Bedeutung, Ersteller/letzter Änderer als „Name (Kürzel)" +
Datum, Gültigkeit der Zuweisung des betrachteten Users, Anzahl zugewiesener User) — analog den
immer sichtbaren Metadaten im Query-Editor. Ersteller/Änderer **und** die Zuweisungs-Gültigkeit
zeigen den Usernamen, sofern der betreffende User (noch) im Dataset vorhanden ist — sonst nur das
SAP-Kürzel (Basis-Team-Accounts ohne Dialog-Zugang stehen z. B. nicht zwingend als eigener User im
Extrakt). Die **Anzahl zugewiesener User** ist anklickbar und öffnet eine eigene **Nutzerliste**
(ID · Name · Benutzertyp · Benutzergruppe · Letzter Login · Sleeping) — dieselbe Listenseite wie
beim Konsistenzcheck-Drilldown (s. u.). Darunter als Reiter: **TCodes** (effektiv aus
`S_TCODE` + Rollenmenü), **Berechtigungsobjekte** (mit Instanz-Anzahl), **Einzelberechtigungen**
(welche Einzelfilter die Rolle **allein** erfüllt) und **SoD-Regeln** (welche Regeln die Rolle
**allein** auslösen kann — Intra-Rollen-Konflikt); die letzten beiden **rollenzentrisch** (frisch
berechnet, unabhängig vom Lauf). Ein separates **Generierungsdatum** ist im SAP-Extrakt nicht
enthalten und wird daher nicht gezeigt.

Die Matches-Tabelle zeigt dafür **User · Name · Query · Bezeichnung (Kurzbezeichnung der Query) ·
Kritikalität · Root-Cause** — Nutzertyp/Status sind hier bewusst weggelassen (stehen ggf. in der
Stammdaten-Kachel), stattdessen ist auf einen Blick erkennbar, **welche** Query mit **welcher
Kritikalität** gematcht wurde. Die Findings-Tabelle zeigt keine Sleeping-Spalte mehr (dafür den
Root-Cause-Button, s. o.). Die **Regel-Zelle** der Findings-Tabelle ist klickbar — filtert (analog
zur klickbaren User-Zelle sowie zur Regel-/Query-Spalte der Ergebnisse-Übersicht) dieselbe Ansicht
auf diese Regel, statt zur Root-Cause-Seite zu wechseln (die braucht immer einen konkreten User).

## 4 · Konsistenzchecks

Menü mit zwei Punkten — beide wechseln im Hauptbereich (anstelle von Filter/Ergebnisse) auf den
Check-Katalog des jeweiligen Bereichs; „&larr; zurück zu Ergebnisse" wechselt zurück.

| Befehl | Wirkung |
| --- | --- |
| **User-spezifisch** | Check-Katalog Kategorien A/B/C/D/E (kritische Berechtigungen, Benutzerstamm-Hygiene, Zuweisungskonsistenz, Gültigkeit/Zeitbezug, referenzielle Integrität). |
| **Rollen-spezifisch** | Check-Katalog Kategorie R (Rollendesign/-qualität — Struktur/Generierung, Zuordnung/Reichweite, Risiko/SoD, Wartbarkeit). |

Adressiert die **Qualität und allgemeinen Risiken des geladenen Berechtigungskonzepts selbst** —
unabhängig von einer konkreten SoD-Regel. **Je Raster-Box eine eigene, umrahmte Tabelle** — im
User-Bereich gerastert nach Kategorie: Layout 2×2 (A·B / C·D) plus **E zentriert darunter** mit
**Kategorie-Pills A–E** (+ „alle") darüber; im Rollen-Bereich gerastert nach Thema (Struktur &
Generierung, Zuordnung & Reichweite, Risiko & SoD, Wartbarkeit & Design), ebenfalls 2×2 mit
Themen-Pills darüber — statt einer einzigen langen Tabelle. Je Zeile steht die **Prüfung fett
mit der Begründung darunter klein** — auch ohne Fachwissen verständlich, nicht nur der Kurztitel.
Die letzte Spalte **„Ergebnisse"** zeigt die zuletzt in dieser Session gesehene Trefferzahl je
Check, sonst **„noch nicht ausgeführt"**, solange keine Check-Logik existiert.

Klick auf eine Zeile **wechselt** (kein Pop-up/Dialog, derselbe Grundsatz wie beim Katalog
selbst) auf eine **eigene Ergebnis-Ansicht**: der Check-Titel links, **ID/Kategorie/Prio-Chips +
„← zurück zum Katalog"** rechtsbündig auf Höhe der Überschrift; darunter **zweispaltig wie die
Findings-Ansicht**. **Links:** Begründung (immer sichtbar, auch bei noch nicht implementierten
Checks), darunter — sobald die Check-Logik existiert — ein schmales Formular mit
**Dataset-Auswahl** und der Anzeige des **Stichtags** (= Downloaddatum der SAP-Extrakte, eine
Eigenschaft des Datasets, kein Lauf-Filter mehr — über „ändern…" global korrigierbar, wirkt dann
auf alle künftigen Läufe/Checks dieses Datasets) mit **„Ausführen"** (zeigt während der Anfrage
einen Spinner), darunter eine **Schnellauswahl „Weitere Checks · …"** mit allen Checks derselben
Box (Kategorie bzw. Thema, analog zur Läufe-Liste, funktioniert auch von einem noch nicht
implementierten Check aus) — Klick wechselt direkt zum nächsten Check, ohne zurück zum Katalog
zu müssen; die Dataset-Auswahl bleibt dabei erhalten, sodass sich eine ganze Box mit demselben
Dataset durchklicken lässt. **Rechts** das Ergebnis: einige Checks zeigen über der Tabelle eine
**Pill-Filterzeile** (z. B. Sperrgrund bei „Gesperrte User mit kritischen Rollen", Status
aktiv/gesperrt, Sleeping-Tage 90/180/360) — Klick auf einen Pill startet bei bereits sichtbarem
Ergebnis sofort einen neuen Lauf, ohne erneut „Ausführen" klicken zu müssen — daneben ein
**Tabelle/Graph-Pill**: für **A1–A3** (SAP_ALL/SAP_NEW/kritische Standardprofile) scharf — zeigt
den User→(Rolle→)Profil-Pfad als Graph (Cytoscape.js, User-Knoten blau, Profil-Knoten grün), für
alle anderen Checks weiterhin deaktiviert („kommt später", analog zu den SoD-Ergebnissen). Hat
der Check eine Zusammenfassung **und** eine Detailliste (z. B. „Wer hat SAP_ALL"), zeigt die
Tabellenansicht oben **Summary-Kacheln** (Werte menschenlesbar, z. B. „aktiv"/„gesperrt" statt
roher Spaltennamen), darunter die **Detailtabelle** (Spalten variieren je Check, Überschriften
ebenfalls menschenlesbar übersetzt statt der rohen Cypher-Spaltennamen) — **Spaltenköpfe sind
klickbar und sortieren die Tabelle** (numerisch oder alphabetisch je nach Inhalt), ein kleines
Dreieck (▲/▼) zeigt Spalte und Richtung; erneuter Klick dreht um. Bei manchen Checks (aktuell
A4) erscheint je Zeile zusätzlich ein **„Root-Cause"-Button**, der auf dieselbe **Root-Cause-Seite**
wechselt wie beim SoD-/Einzelfilter-Root-Cause (s. o.) und zeigt, welche konkrete(n) Rolle(n)/
Profil(e) mit welchen Berechtigungswerten den Treffer auslösen; deren „← zurück" führt wieder zu
diesem Konsistenzcheck-Ergebnis (nicht zum Katalog). Checks ohne Zusammenfassung zeigen nur die
Detailtabelle. Besteht die Summary aus **genau einer** Kachel und ist die Detailtabelle eine
Nutzerliste (z. B. „Aktive Dialog-User ohne Anmeldung" B1), ist die große Kennzahl **anklickbar**
und öffnet — frisch aus der Datenbank angereichert (ID · Name · Benutzertyp · Benutzergruppe ·
Letzter Login · Sleeping) — dieselbe Nutzerliste-Seite wie bei „Zugewiesene User" auf der
Rollen-Detailseite. „← zurück zum Katalog" (eigener Button am Check-Ergebnis selbst) wechselt zurück
zum Katalog. Noch nicht implementierte Checks zeigen rechts nur einen Hinweis statt eines Ergebnisses.

**Keine Persistenz (bewusst):** ein Check-Lauf erzeugt keinen `(:Run)`-Knoten und wird nirgends
gespeichert — das Ergebnis lebt nur im Browser für die Dauer der Session. Die zuletzt gesehene
**Trefferzahl** wird clientseitig zwischengespeichert und ersetzt danach in der Katalog-Tabelle
den Platzhalter „noch nicht ausgeführt" — das ist ein reiner UI-Cache, kein Server-Zustand, und
geht beim Neuladen der Seite verloren. Der vollständige Katalog mit
Begründung steht in
[`KONSISTENZCHECKS.md`](../../KONSISTENZCHECKS.md), der technische Rahmen in
[`ROADMAP.md`](../../ROADMAP.md), Phase 7.

## 5 · Sichern

| Befehl | Wirkung |
| --- | --- |
| **Backup / Restore** | Öffnet den Dialog: **Backup erstellen** (Quelldaten-ZIP), Option **danach leeren** (Backup & Clear), und die **Backups-Liste** mit **↻ Wiederherstellen** und **↓ Herunterladen**. |

Backups enthalten nur die **bereinigten Quelldaten** — keine Findings (die werden nach dem
Wiederherstellen neu ausgewertet). Backups bleiben lokal.

Im selben Dialog, separat darunter: **Lauf-Backups** — sichert einen einzelnen
**Auswertungslauf** (Run + Findings, ohne Evidenz; die ist über „Evidenz" im Ribbon jederzeit
neu berechenbar) als eigenes ZIP. Jedes Dataset trägt dafür eine **Dataset-uid**, die beim
Wiederherstellen mit der im Lauf-Backup gespeicherten uid verglichen wird: weicht sie ab (das
Dataset wurde seither neu befüllt), fragt die App vor dem Restore ausdrücklich nach.

## 6 · Verwalten

| Befehl | Wirkung |
| --- | --- |
| **Bereinigen** | Dialog: **Dieses Dataset löschen** oder **Alles zurücksetzen** (Ruleset & Schema bleiben in beiden Fällen erhalten), sowie separat **einen einzelnen Auswertungslauf löschen** (Run + Findings; Dataset und andere Läufe bleiben unberührt). |

Beide Aktionen fragen vor dem Ausführen nach.

## 7 · Admin

| Befehl | Wirkung |
| --- | --- |
| **Query Management** | Link direkt auf die eigene Seite `/admin.html` (kein Zwischendialog). |
| **Scope** | Link direkt auf die eigene Seite `/admin-scopes.html` (kein Zwischendialog). |
| **Fehlerprotokoll** | Dialog mit fehlgeschlagenen Jobs (Import/Lauf/Backup/Restore/Bereinigen) — **persistent**, überlebt einen Container-Neustart (Datei `data/logs/job_errors.jsonl`). Neueste zuerst. |

### Query Management (eigene Seite, eigene Ribbon-Bar)

Erreichbar &uuml;ber das Men&uuml; „Admin" (Gruppe „7 &middot; Admin") &rarr; „Query Management".
Eigene Ribbon-Gruppen: **Anzeige**
(Aktualisieren), **Editieren** (Speichern/Abbrechen, aktiv sobald etwas ge&auml;ndert wurde),
**Backup** (Overlay-Datei des gew&auml;hlten Rulesets herunterladen) und **Zur&uuml;ck** (zur
Auswertung).

Links: **Filterset** w&auml;hlen (aktuell 3 Rulesets), darunter der **Modus-Umschalter
„Einzelfilter"/„SoD"** — wechselt Liste, Filter und Detailbereich, ohne die Auswahl im jeweils
anderen Modus zu verwerfen. Darunter **Suche** (unterst&uuml;tzt `*` als Platzhalter, z. B.
„BC-SEC*", wirkt in beiden Modi) und je Modus eigene Filter: **Einzelfilter** nach
**Modul/Kritikalit&auml;t/Query-Typ**, **SoD** nur nach **Kritikalit&auml;t**. Die Liste zeigt
ID + Bezeichnung, eigene/abgeleitete bzw. bearbeitete Eintr&auml;ge markiert.

**Modus Einzelfilter** — rechts nach Auswahl einer Query: oben dauerhaft sichtbar die
**Stammdaten** (Kurz-/Langbezeichnung, Kritikalit&auml;t, Modul, Query-Typ, „TCode ignorieren" —
die **Kurzbezeichnung** ist es, was in den Sidebar-Filtern der Auswertung als Name erscheint),
darunter drei **Tabs**:

- **Aufbau** — Transaktionen und Berechtigungsobjekte der Query, **nur Anzeige** (Bearbeitung
  folgt sp&auml;ter).
- **Risiko** — Freitext: potenzielles Risiko dieser Berechtigung.
- **Controls** — Freitext: mitigierende Ma&szlig;nahmen.

Unten links: eine **neue Query aus der gew&auml;hlten ableiten** (Berechtigungen/TCodes 1:1
&uuml;bernommen, Stammdaten/Risiko/Controls oben vorher anpassen) — nur im Modus Einzelfilter.

**Modus SoD** — rechts nach Auswahl einer Regel: Stammdaten (Kurz-/Langbezeichnung,
Kritikalit&auml;t, Reason-Code, read-only), darunter drei **Tabs**:

- **Aufbau** — die CNF-Klausel-Struktur: je Klausel die enthaltenen Queries (ID + Bezeichnung);
  alle Klauseln zusammen sind UND-verkn&uuml;pft, innerhalb einer Klausel reicht eine gematchte
  Query. Hat ein Ruleset noch keine `clauses` hinterlegt (aktuell CSI/CSI_BI, s. ROADMAP), zeigt
  der Tab ersatzweise den rohen Ausdruck (`expression`) und die Variablen-Zuordnung.
- **Risiko** / **Controls** — wie beim Einzelfilter, eigene Freitext-Felder je SoD-Regel.

SoD-Regeln haben **kein „Ableiten"** (keine UI f&uuml;r neue/abgeleitete Regeln) — nur
Metadaten-Edits an bestehenden Regeln. Speichern/Abbrechen (Ribbon **oder** Detailbereich) sowie
„Overlay sichern" (Ribbon **Backup**) wirken im jeweils aktiven Modus auf den passenden Overlay
(`queries.custom.json` bzw. `sod_rules.custom.json`).

&Auml;nderungen schreiben **nie** in die Vendor-Datei (`queries.json`), sondern in ein separates
Overlay (`queries.custom.json`) je Ruleset — Vendor-Updates &uuml;berschreiben eigene Anpassungen
dadurch nicht. Speichern/Ableiten wirkt **sofort** (kein extra Reload-Schritt n&ouml;tig).

### Scope (eigene Seite, eigene Ribbon-Bar)

Erreichbar über das Menü „Admin" (Gruppe „7 · Admin") → „Scope". Verwaltet **persistente,
benannte Scope-Profile** — dieselbe Katalog-Auswahl (Einzelfilter/SoD-Regeln, filterbar nach
Namensmuster **der Bezeichnung** /Modul/Kritikalität/Query-Typ, Mehrfachauswahl per Checkbox) wie
im Assistenten-Schritt „Scoping", aber **dauerhaft gespeichert** und über beliebig viele Läufe/
Datasets desselben Rulesets hinweg wiederverwendbar (siehe „Gespeicherter Scope" oben).

Links: **Ruleset** wählen, darunter die Liste der für dieses Ruleset gespeicherten Scopes (mit
Zählung „N Einzelfilter, M SoD-Regel(n)"), „+ Neuer Scope". Rechts ein frei klickbarer
Mini-Stepper **① Einzelfilter · ② SoD-Regeln · ③ Speichern**:

- **① Einzelfilter** — Katalog-Tabelle (ca. 20 Zeilen sichtbar, Rest scrollt), Filter Namensmuster
  (matcht die Bezeichnung)/Modul/Query-Typ/Kritikalität, „alle (gefiltert) wählen"/„Auswahl
  leeren". Optional — auch ganz ohne Auswahl weiter zu ②.
- **② SoD-Regeln** — dieselbe Tabellenlogik für SoD-Regeln, zusätzlich ein Umschalter **„alle" /
  „nur mögliche"**: „nur mögliche" zeigt nur Regeln, deren sämtliche Klauseln durch die unter ①
  gewählten Einzelfilter abgedeckt sind (bidirektionale Verknüpfung über die CNF-Klausel-Struktur
  des Rulesets — aktuell nur bei KPMG R/3 vorhanden; ohne diese Struktur erscheint ein Hinweis
  statt des Umschalters, alle Regeln bleiben sichtbar).
- **③ Speichern** — Name (nur bei Neuanlage änderbar), Beschreibung, **Nutzertyp-Profil** und
  **Sleeping (Tage)** (dieselben Achsen wie im „Neuer Lauf"-Formular), Zusammenfassung. Wählt man
  eine SoD-Regel, deren Klausel-Queries nicht schon unter ① angehakt sind, ergänzt die App diese
  beim Speichern **automatisch** (nie löschend) — die Zusammenfassung weist das aus („davon N
  automatisch ergänzt"), damit die Regel später auch tatsächlich auswertbar ist. Speichern
  erfordert mindestens einen Einzelfilter **oder** eine SoD-Regel.

Ein **neuer** Scope startet geführt bei ①; ein **bestehender** Scope öffnet sich direkt bei ③
(Zusammenfassung) — über den Stepper jederzeit zurück zu ①/② zum Nachjustieren, danach erneut
speichern oder löschen.

Scope-Profile beziehen sich auf Query-/SoD-Regel-**IDs** eines Rulesets — reines
Katalog-Vokabular, keine Mandantendaten — und liegen daher wie die Einzelfilter-/SoD-Regel-
Overlays im Ruleset-Ordner (`rules/<Ruleset>/scope_profiles.custom.json`), git-getrackt.

**Geplant** in diesem Bereich:

- **Authorizations/TCodes im Aufbau-Tab bearbeitbar** — bisher nur Anzeige bzw. 1:1-Kopie beim Ableiten.
- **USOBT-gest&uuml;tzter Query-Builder** — neue Queries per Auswahl Transaktion&nbsp;&rarr;
  Berechtigungsobjekte statt freier Eingabe.
- **Stammdaten-Blatt: Query &rarr; System-Typ** (SAP R/3, S/4HANA, k&uuml;nftig weitere).
- **Neues Filterset importieren** — weitere Systeme als eigenes Ruleset, perspektivisch
  **SAP S/4HANA, Azure AD / Entra, Microsoft Dynamics, Salesforce** (das Datenmodell bleibt gleich).

> Die App hat **bewusst kein eigenes Benutzer-/Berechtigungskonzept**: sie läuft lokal bzw. wird als
> Container verteilt; der Zugriff wird über die Umgebung abgesichert.
