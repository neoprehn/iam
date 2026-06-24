# Konsistenzchecks — Datenschema

Operative Quelle für das Backend (`GET /consistency-checks?area=user|role`). Ein JSON je
Kategorie (`A.json`/`B.json`/`C.json`/`D.json`/`E.json`/`R.json`), analog zur Ruleset-Struktur
unter `rules/`, aber **ruleset-unabhängig** — gilt für jedes geladene Berechtigungskonzept. Die
ausführliche, mit Begründung versehene Fassung (für Menschen) ist
[`../KONSISTENZCHECKS.md`](../KONSISTENZCHECKS.md); **beide Dateien manuell synchron halten**, es
gibt (noch) keinen Generator.

## Bereiche (`area`)

Zwei getrennte Bereiche, je ein eigener Ribbon-Punkt in der App:

- **`user`** — Kategorien `A`/`B`/`C`/`D`/`E` (Qualität/Risiko bezogen auf User, Benutzerstamm,
  Import-Integrität).
- **`role`** — Kategorie `R` (Rollenqualität/-design). Aktuell die einzige Rollen-Kategorie; die
  UI rastert hier stattdessen nach dem Feld `group` (s. u.) — vier Themenboxen im 2×2-Raster
  statt einer langen Tabelle.

Die Zuordnung Kategorie→Bereich ist im Backend hinterlegt (`CHECK_AREAS` in `backend/app.py`),
nicht in den JSON-Dateien selbst.

## Datei je Kategorie

Jede Datei ist eine JSON-Liste von Check-Objekten derselben Kategorie:

| Feld | Typ | Pflicht | Bedeutung |
| --- | --- | --- | --- |
| `id` | str | ja | Stabile ID, z. B. `"A1"`/`"R1"` — Kategorie-Präfix + laufende Nummer. |
| `category` | str | ja | Eine von `A`/`B`/`C`/`D`/`E`/`R` (muss zum Dateinamen passen). |
| `group` | str | optional | Themen-Unterteilung **innerhalb** einer Kategorie für die UI-Box-Bildung (rastert dann nach `group` statt nach `category`) — aktuell nur in `R.json` gepflegt: „Struktur & Generierung" (R1–R7), „Zuordnung & Reichweite" (R8–R12), „Risiko & SoD" (R13–R16), „Wartbarkeit & Design" (R17–R18), entspricht den gleichnamigen Abschnitten in `KONSISTENZCHECKS.md`. Fehlt das Feld, rastert die UI nach `category` (A–E). |
| `title` | str | ja | Kurztitel („Prüfung"), erscheint in der Katalog-Tabelle. |
| `description` | str | ja | „Bedeutung & warum relevant" — Begründungstext für die Detailansicht. |
| `prio` | str | ja | `"Hoch"` / `"Mittel"` / `"Niedrig"` — grobe Triage, kein SoD-Kritikalitätswert. Bei Kategorie `R` zusätzlich `"Analytik"` für Ranking-Checks (Top-N, keine Pass/Fail-Prüfung) — eigener, neutraler Tag in der UI statt der Hoch/Mittel/Niedrig-Farbskala. |
| `implemented` | bool | ja | Technischer Umsetzungsstand der Check-Logik (Backend/Cypher). `false` solange keine Query existiert. |
| `cypherFile` | str | optional | Pfad zur zugehörigen `.cypher`-Datei (relativ zum Repo-Root, z. B. `cypher/checks/sap_all.cypher`), gesetzt sobald `implemented: true`. Wird vom Run-Endpoint (`POST /consistency-checks/{id}/run`) gelesen und über den Neo4j-Treiber ausgeführt — `dataset`/`asOf` werden als Parameter durchgereicht. Mehrstatement-Dateien (`;`-getrennt, wie `sap_all.cypher`) liefern je Statement ein eigenes Zeilen-Set zurück (Zusammenfassung + Detailliste). |
| `params` | list | optional | Zusätzliche, vom Nutzer wählbare Werte für die `cypherFile` — sowohl Schwellwerte (z. B. Sleeping-Tage, `type: "int"`) als auch Filter (z. B. Sperrgrund/Status, `type: "str"`) — ersetzt einen sonst hart codierten Literal-Wert (s. Begründung in `critical_profiles.cypher`: der generische Run-Endpoint kennt sonst nur `dataset`/`asOf`). Jedes Element: `{"name": "<Cypher-Parametername, z. B. sleepDays oder lockReason>", "label": "<UI-Beschriftung>", "type": "int"|"str", "options": [...Werte...], "default": <Wert>}`. Beispiele in `checks/B.json`: B1 `sleepDays` (90/180/360), B4 `lockReason` (alle/failed_logons/admin_local/admin_global), B5/C3 `status` (alle/aktiv/gesperrt). UI rastert daraus Pill-Buttons im Ausführen-Formular (analog zu den Kritikalitäts-Pills); `POST /consistency-checks/{id}/run` nimmt sie als `params`-Map entgegen (fehlt ein Wert, gilt `default`). Nur deklarierte Namen werden durchgereicht (keine beliebigen Cypher-Parameter vom Client). |
| `rootCauseFile` | str | optional | Pfad zu einer eigenen `.cypher`-Datei (analog `cypherFile`), die für einen einzelnen `$user` zeigt, welche Rolle(n)/Profil(e) mit welchen konkreten Authorization-Feldwerten den Befund auslösen — eigene Datei statt drittes Statement in `cypherFile`, damit der normale Lauf (ohne `$user`) unverändert bleibt. Wird über `POST /consistency-checks/{id}/root-cause` (Body `{dataset, user}`) ausgeführt und in dasselbe `{blocks: [...]}`-Format wie der SoD-Root-Cause (`GET /root-cause`) übersetzt; die UI zeigt dann pro Detailzeile mit `user`-Spalte einen „Root-Cause"-Button (Wiederverwendung des bestehenden Root-Cause-Dialogs). Aktuell nur für A4 (`critical_single_auths.cypher`) umgesetzt. |

Kein Overlay-Mechanismus in v1 (kein externer „Vendor" hier wie bei Rulesets) — Edits direkt in
der Datei.

## Kategorien

Reihenfolge entspricht der Anzeige in der App (2×2-Raster + `E` zentriert darunter, nur Bereich
`user`):

- `A` — Kritische & weitreichende Berechtigungen
- `B` — Benutzerstamm-Hygiene
- `C` — Zuweisungs- & Strukturkonsistenz (User ↔ Rolle ↔ Profil) — bereinigt um reine
  Rollen-Struktur-Checks, die in `R` aufgegangen sind
- `D` — Gültigkeit & Zeitbezug
- `E` — Referenzielle Integrität & Import-Vollständigkeit
- `R` — Rollenqualität/-design (Bereich `role`, eigener Ribbon-Punkt „Rollen-spezifisch")
