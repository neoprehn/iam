# Phase 2 — Datenimport (Can-Do / Rohdaten)

**Ziel:** SAP-Berechtigungsstammdaten als Graph. **DoD:** beide Berechtigungspfade
(rollenbasiert + direkt) vollständig im Graphen, stichprobenartig gegen SAP nachvollziehbar.

Welche Tabellen/Spalten extrahiert werden, steht im [Extraktionsleitfaden](../extraktionsleitfaden.md).
Diese Seite beschreibt **Tooling**, **Importstrategie** und **Ablauf**.

## Tooling (kein Python)

Der Import besteht aus drei Bausteinen — alles container-only bzw. Host-PowerShell, **kein
Python, kein lokales Java** (AE-15):

1. **Konverter** `load/Convert-Se16Export.ps1` (PowerShell). SE16-„unkonvertiert"-Exporte
   (`.txt`, Windows-1252, Pipe-getrennt, fixe Breite, Markierungsspalte) → saubere UTF-8-CSV,
   **Tab-getrennt**, eine Kopfzeile mit den SAP-Feldnamen. Entfernt Padding und `"`-Zeichen.
2. **Load-Skripte** `load/00…11_*.cypher` (Cypher). Ausgeführt von **`cypher-shell` im
   Container** (`docker exec … -f /load/…`), Batching über `apoc.periodic.iterate`. Das
   Verzeichnis `load/` ist read-only in den Neo4j-Container gemountet.
3. **Orchestrierung**: die `load/*.cypher` der Reihe nach mit `-P "dataset => '…'"` / `-P "lang => […]"`
   — gebündelt im Runner `run/run_import.ps1` (Phase 5).

## Importstrategie

**Tabellen nach Muster:**

| Quelle | Ziel | Muster |
| --- | --- | --- |
| USR02 | `:User` (+ Subtyp-Labels) | Node-MERGE |
| AGR_DEFINE | `:Role` | Node-MERGE |
| TSTCT | `:Transaction` (+ Text, `SPRSL='DE'`) | Node-MERGE |
| AGR_PROF / USR11 | `:Profile` (+ Text) | Node-MERGE |
| AGR_AGRS | `CONTAINS` | Edge-MERGE |
| AGR_USERS | `ASSIGNED_TO` (+ Gültigkeit) | Edge-MERGE |
| AGR_PROF / UST04 | `HAS_PROFILE` | Edge-MERGE |
| USOBT_C | `CHECKS` | Edge-MERGE (dedupliziert, lief zügig) |
| AGR_1251 | `:Authorization` (+ HAS_AUTH/FOR_OBJECT) | Node/Edge-MERGE + dynamische `f_<FELD>` — **schwerster Schritt** |

**Querschnitt-Konventionen:**

- **Ein `$dataset`-Parameter** steuert Pfad (`file:///$dataset/<tabelle>.csv`) **und** die
  `dataset`-Property an allen Knoten/Kanten. Ordnername = `dataset`.
- **MERGE auf den synthetischen `key`** (`<dataset>|<id>`, constraint-gestützt) → schnelle,
  duplikatfreie Lookups. Die Migrationen aus Phase 1 müssen vorher angewandt sein.
- **Datum** `DD.MM.YYYY` → Neo4j-`date`; `31.12.9999` → `9999-12-31`; `00.00.0000` → `null`.
  `*`/unbeschränkt bleibt erhalten (Normalisierung erst in der Abfrage, AE-06).
- **Batching** durchgängig `apoc.periodic.iterate`, `parallel:false`, `batchSize` 2–10k.
- **Performance — Key-Index ist entscheidend.** Die Auth-Loader (`08`/`18`/`19`/`20`)
  MERGE/MATCH-en auf `Authorization.key`. Fehlt der Index darauf, ist jeder Zugriff ein
  Full-Label-Scan über >150k Knoten → Importe dauern Stunden. Der Index kommt aus Migration
  `V003` (Unique-Constraint `authorization_key`) — **vor** dem Laden anwenden (`migrations`-Service).
  Die frühere Annahme „aggregate-first bringt nichts" galt nur *ohne* diesen Index (beide
  Varianten scannten voll).
- **`08` (AGR_1251) und `19` (UST12) als Zwei-Pass.** Feldwerte je (Auth,Feld) erst per
  `collect(DISTINCT)` zu einer Map gruppieren, dann den Knoten einmal mergen und alle f_-Properties
  in **einem** `SET a += props` setzen — statt pro Zeile `coalesce+toSet+setProperty` (O(n²),
  eskalierende Batchzeiten). `18`/`20` haben kein O(n²) (reine MERGE/MATCH) und brauchen nur den
  Key-Index. Verifiziert (byte-identische Daten): `08` ~3 h → 7 s, `18` 88 min → 3 s, `19` 4,6 h →
  9 s, `20` >33 min → 3 s. Gesamte Pipeline jetzt < 1 min.
- **Reihenfolge:** `00 dataset → 01–09 Knoten/Kanten → 10 SU24 → 11 Subtyp-Labels →
  99 Validierung`. Subtyp-Labels (Role `Composite`/`Single`) bewusst am Ende, damit auch erst
  spät (über AGR_1251/AGR_USERS) angelegte Rollen erfasst sind.
- **Idempotenz/Re-Run:** alles MERGE-basiert → erneuter Lauf erzeugt keine Duplikate. Für einen
  sauberen Neu-Load eines Stands vorab zurücksetzen:
  `MATCH (n {dataset:$dataset}) DETACH DELETE n`.

## Ablauf

```powershell
# 1. SE16-Tabellen exportieren ("unkonvertiert"), .txt nach data/import/<dataset>/ legen
#    (Ordnername = dataset, z. B. data/import/sachsenenergie/)

# 2. In CSV konvertieren — ALLE Tabellen des Ordners; sensible Credential-Spalten
#    (PWDSALTEDHASH, BCODE, PASSCODE, OCOD*/BCDA*/CODV* ...) werden dabei automatisch
#    verworfen (-DropColumnsLike), landen also in keiner CSV.
.\load\Convert-Se16Export.ps1 -Folder data\import\sachsenenergie

# 3. Schema sicherstellen (Phase 1)
docker compose run --rm migrations

# 4. Laden (Reihenfolge 00..11) — dataset = Ordnername, Sprache über $lang-Schalter
$pw = $env:NEO4J_PASSWORD
$ds = "dataset => 'sachsenenergie'"
# Sprach-Schalter aus .env (IMPORT_LANG, z. B. "DE,DEU,D"); leer = Default DE,DEU,D
$codes = ($env:IMPORT_LANG, 'DE,DEU,D' -ne '')[0].Split(',').ForEach({ "'$($_.Trim())'" }) -join ','
$lang = "lang => [$codes]"
foreach ($f in (Get-ChildItem .\load\*.cypher | Sort-Object Name)) {
  docker exec iam-neo4j cypher-shell -u neo4j -p $pw -P $ds -P $lang -f "/load/$($f.Name)"
}

# 5. Validieren
docker exec iam-neo4j cypher-shell -u neo4j -p $pw -P $ds -P $lang -f /load/99_validate.cypher
```

Der **`$lang`-Schalter** ist eine Liste akzeptierter Sprachcodes. Nur die Text-Skripte
`09` (TSTCT/`SPRSL`), `13` (TOBJT/`LANGU`) und `20` (USR13/`LANGU`) werten ihn aus: der erste
gelistete Treffer gewinnt, sonst bleibt der erste vorhandene Text erhalten. Das überzählige
`-P $lang` an den übrigen Skripten ist harmlos. Default deckt die deutschen Schreibweisen
`DE`/`DEU`/`D` ab (SAP speichert je nach Tabelle ISO-2, ISO-3 oder den 1-Zeichen-`SPRAS`-Code).
Andere Sprache = `IMPORT_LANG` in der `.env` setzen (z. B. `EN,ENG,E`).

:::{note}
`Convert-Se16Export.ps1` und die `.cypher`-Dateien sind release-/exportabhängig beim
Datumsformat (**`DD.MM.YYYY`**, in diesem Datensatz). Der Sprachschlüssel ist dagegen über den
`$lang`-Schalter (`IMPORT_LANG`) parametrisiert und muss nicht mehr im Cypher angefasst werden —
die Default-Liste deckt die deutschen Schreibweisen (`DE`/`DEU`/`D`) ab.
:::

## Ergebnis / Validierung

`99_validate.cypher` zählt je **Knoten- und Kantentyp** (Transaction, Authorization, Role
inkl. Single/Composite, Profile, AuthObject, User inkl. Subtypen; CHECKS, HAS_AUTH,
FOR_OBJECT, ASSIGNED_TO, HAS_PROFILE, CONTAINS …) und macht den Import stichprobenartig gegen
SAP nachvollziehbar.

> **Keine konkreten Zahlen in dieser Doku.** Mengengerüste sind mandanten-/standspezifisch und
> gehören nicht ins Repo (Vertrauensgrenze: Doku = nur Logik/Vorgehen). Die aktuellen Zähler
> liefert `99_validate.cypher` auf dem jeweiligen `dataset`.

Beide Pfade sind abgebildet: **rollenbasiert** (`User -ASSIGNED_TO-> Role -HAS_AUTH->
Authorization -FOR_OBJECT-> AuthObject`) und **direkt** (`User -HAS_PROFILE-> Profile`).
Datensparsamkeit: aus USR02 wurden **keine** Passwort-/Hash-Felder geladen.

## Erweiterte Quellen (Skripte 12–24)

Zusätzlich zum Kern eingebunden:

| Skript | Quelle | Ergebnis |
| --- | --- | --- |
| 12 | V_USERNAME | `:User.name/.nameLast/.persNumber` (personenbezogen, lokal) |
| 13 | TOBJT | `:AuthObject.text` (Objekt-Texte, sprachgeschaltet `$lang`) |
| 14 | USREFUS | `(:User)-[:HAS_REFERENCE]->(:User)` — Referenzbenutzer-Zuordnung (sofern im Mandanten gepflegt) |
| 15 | UST10C | `(:Profile)-[:CONTAINS]->(:Profile)` (Sammelprofile, + `:Collective`) |
| 16 | AGR_1252 | `:Role.org_<VARBL>` (Org-Ebenen abgeleiteter Rollen) |
| 17 | AGR_TCODES | `(:Role)-[:HAS_MENU]->(:Transaction)` (Rollenmenü, informativ) |
| 18 | UST10S | `(:Profile)-[:HAS_AUTH]->(:Authorization{scope:'profile'})-[:FOR_OBJECT]->…` (Struktur) |
| 19 | UST12 | Feldwerte `f_<FELD>` an den Profil-Templates (**verlustfrei, alle Profile**) |
| 20 | USR13 | `:Authorization.authText` (Berechtigungs-Texte, sprachgeschaltet) |
| 21 | AGR_TEXTS | `:Role.text` (Rollentexte, sprachgeschaltet `$lang`) |
| 22 | AGR_1016B | `:Role.profileGenerated/.profileState` (Profil-Generierungsstatus, konzeptunabhängig) |
| 23 | USORG | `(:OrgField)` — Registry der organisatorischen Felder (für die Org-Dimension der Auswertung) |
| 24 | — | Org-Level-Platzhalter auflösen: `$<Feld>` in role-eigenen Auths → echte Werte aus `Role.org_$<Feld>` (AGR_1252) |

:::{admonition} Verlustfrei by construction
:class: important
Skript 19 lädt die Profil-Feldwerte **ohne** annahmebasierte Eingrenzung — jedes Profil
erhält seine tatsächlichen Werte aus der Quelle, auch wenn sie (bei diesem Konzept) den
Rollen-Auths gleichen. Andere Berechtigungskonzepte können abweichen; der Import darf sich
darauf nicht verlassen. Performance wird strukturell gelöst, **nie** durch Weglassen von Daten.
Ebenso sind Sprach-/Textfilter robust (DE bevorzugt, sonst Fallback), nicht hart auf eine Sprache.
:::

## Weitere Stände (z. B. 2026)

Denselben Skriptsatz mit anderem `dataset` (= neuer Ordner unter `data/import/`) laufen lassen.
Beide Stände liegen dann in einer DB und sind über die fachliche `id` vergleichbar
(siehe [Datenmodell](../datamodel.md)).
