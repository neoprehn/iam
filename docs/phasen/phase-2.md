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
3. **Orchestrierung**: aktuell die Skripte 00→11 der Reihe nach mit `-P "dataset => '…'"`
   (wird in Phase 5 der Runner `run/run_all.ps1`).

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
- **AGR_1251 ist der schwerste Schritt** (726k Zeilen, dynamische `f_<FELD>`-Properties je
  Berechtigung) — auf diesem Volumen mehrere Stunden. Eine getestete „aggregate-first"-Variante
  (`collect` je Feld) war hier **nicht** schneller, weil die dynamischen Property-Writes
  dominieren. Eine echte Optimierung (Zwei-Pass: erst distinct Knoten/Kanten, dann je Auth eine
  Bulk-Property-Setzung) ist als Folgearbeit offen.
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

# 2. In CSV konvertieren
.\load\Convert-Se16Export.ps1 -Folder data\import\sachsenenergie `
   -Tables USR02,AGR_DEFINE,AGR_AGRS,AGR_USERS,ARG_PROF,UST04,USR11,AGR_1251,USOBT_C,TSTCT

# 3. Schema sicherstellen (Phase 1)
docker compose run --rm migrations

# 4. Laden (Reihenfolge 00..11) — dataset = Ordnername
$pw = $env:NEO4J_PASSWORD; $ds = "dataset => 'sachsenenergie'"
foreach ($f in (Get-ChildItem .\load\*.cypher | Sort-Object Name)) {
  docker exec iam-neo4j cypher-shell -u neo4j -p $pw -P $ds -f "/load/$($f.Name)"
}

# 5. Validieren
docker exec iam-neo4j cypher-shell -u neo4j -p $pw -P $ds -f /load/99_validate.cypher
```

:::{note}
`Convert-Se16Export.ps1` und die `.cypher`-Dateien sind release-/exportabhängig in zwei
Punkten, die in diesem Datensatz so vorlagen: Datumsformat **`DD.MM.YYYY`** und Sprachschlüssel
**ISO 2-stellig** (`DE`/`EN`). Bei abweichenden Exporten dort anpassen.
:::

## Ergebnis (dataset `sachsenenergie`)

Importvalidierung (`99_validate.cypher`):

| Knoten | Anzahl |
| --- | --- |
| Transaction | 114.926 |
| Authorization | 90.700 |
| Role (Single/Composite) | 6.816 (6.447 / 369) |
| Profile | 6.088 |
| AuthObject | 5.113 |
| User (Dialog/System/Service) | 1.378 (davon 71 `Locked`) |

| Kante | Anzahl |
| --- | --- |
| CHECKS (Transaction→AuthObject) | 192.230 |
| HAS_AUTH (Role→Authorization) | 90.700 |
| FOR_OBJECT (Authorization→AuthObject) | 90.700 |
| ASSIGNED_TO (User→Role) | 72.109 |
| HAS_PROFILE (User/Role→Profile) | 63.088 |
| CONTAINS (Composite→Single) | 4.656 |

Beide Pfade sind abgebildet: **rollenbasiert** (`User -ASSIGNED_TO-> Role -HAS_AUTH->
Authorization -FOR_OBJECT-> AuthObject`) und **direkt** (`User -HAS_PROFILE-> Profile`).
Datensparsamkeit: aus USR02 wurden **keine** Passwort-/Hash-Felder geladen.

## Erweiterte Quellen (Skripte 12–17)

Zusätzlich zum Kern eingebunden:

| Skript | Quelle | Ergebnis |
| --- | --- | --- |
| 12 | V_USERNAME | `:User.name/.nameLast/.persNumber` (personenbezogen, lokal) |
| 13 | TOBJT | `:AuthObject.text` (Objekt-Texte, DE) |
| 14 | USREFUS | `(:User)-[:HAS_REFERENCE]->(:User)` — im Datensatz `sachsenenergie` **0** (keine Referenzbenutzer gepflegt) |
| 15 | UST10C | `(:Profile)-[:CONTAINS]->(:Profile)` (Sammelprofile, + `:Collective`) |
| 16 | AGR_1252 | `:Role.org_<VARBL>` (Org-Ebenen abgeleiteter Rollen) |
| 17 | AGR_TCODES | `(:Role)-[:HAS_MENU]->(:Transaction)` (Rollenmenü, informativ) |

**Noch offen (schwer):** Profil-Eigenwerte aus **UST10S + UST12** (`(:Profile)-[:HAS_AUTH]->
(:Authorization)` mit Feldwerten) — wie AGR_1251 ein zeitintensiver Lauf (UST12 ≈ 483k Zeilen).
`USR13` (Auth-Texte) gehört dort dazu.

## Weitere Stände (z. B. 2026)

Denselben Skriptsatz mit anderem `dataset` (= neuer Ordner unter `data/import/`) laufen lassen.
Beide Stände liegen dann in einer DB und sind über die fachliche `id` vergleichbar
(siehe [Datenmodell](../datamodel.md)).
