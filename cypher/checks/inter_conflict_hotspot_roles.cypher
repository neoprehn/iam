// Konsistenzcheck (Katalog R15): Konflikt-Hotspot-Rollen -- am haeufigsten an Inter-Rollen-
// SoD-Konflikten beteiligt (conflictType='inter', AE-11: Konflikt entsteht erst durch die
// Kombination mehrerer Rollen). Auch wenn jede Rolle fuer sich sauber ist, sind Hotspots die
// wirksamsten Stellschrauben zur Konfliktreduktion. Top-10 als Literal gepflegt.
// VORAUSSETZUNG wie R13/R14: nutzt den juengsten (:Run) des Datasets samt Evidenz
// (explain_sod). Kein Lauf/keine Evidenz -> 0 Treffer, keine Fehlermeldung.
// Parameter: $dataset, $asOf (asOf ungenutzt, der Lauf bringt seinen eigenen Stichtag mit).
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/inter_conflict_hotspot_roles.cypher

// --- 1) Zusammenfassung: Top-5 (-> KPI-Kacheln UI) ---
OPTIONAL MATCH (run:Run {dataset:$dataset})
WITH run ORDER BY run.generatedAt DESC LIMIT 1
WITH run
MATCH (f:SoDConflict {dataset:$dataset, runId:run.runId, ruleset:run.ruleset, conflictType:'inter'})-[:VIA_ROLE]->(r:Role)
WITH r, count(DISTINCT f) AS konfliktAnzahl
ORDER BY konfliktAnzahl DESC
LIMIT 5
RETURN r.id AS rolle, konfliktAnzahl;

// --- 2) Detailliste: Top-10 ---
OPTIONAL MATCH (run:Run {dataset:$dataset})
WITH run ORDER BY run.generatedAt DESC LIMIT 1
WITH run
MATCH (f:SoDConflict {dataset:$dataset, runId:run.runId, ruleset:run.ruleset, conflictType:'inter'})-[:VIA_ROLE]->(r:Role)
WITH r, count(DISTINCT f) AS konfliktAnzahl, collect(DISTINCT f.ruleId) AS regeln
ORDER BY konfliktAnzahl DESC
LIMIT 10
RETURN r.id AS rolle, coalesce(r.text, '') AS text, konfliktAnzahl, regeln;
