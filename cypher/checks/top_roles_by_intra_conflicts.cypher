// Konsistenzcheck (Katalog R14, Analytik/Ranking): Top-10 Rollen nach Anzahl built-in
// (Intra-Rollen-)SoD-Konflikte -- Rangliste der problematischsten Rollendesigns, steuert wo
// Redesign den groessten Hebel hat. Top-N als Literal (10) gepflegt, kein Pass/Fail-Befund.
// VORAUSSETZUNG wie R13: nutzt den juengsten (:Run) des Datasets samt dessen Evidenz
// (explain_sod). Kein Lauf/keine Evidenz -> 0 Treffer, keine Fehlermeldung.
// Parameter: $dataset, $asOf (asOf ungenutzt, der Lauf bringt seinen eigenen Stichtag mit).
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/top_roles_by_intra_conflicts.cypher

// --- 1) Zusammenfassung: Top-5 (-> KPI-Kacheln UI) ---
OPTIONAL MATCH (run:Run {dataset:$dataset})
WITH run ORDER BY run.generatedAt DESC LIMIT 1
WITH run
MATCH (f:SoDConflict {dataset:$dataset, runId:run.runId, ruleset:run.ruleset, conflictType:'intra'})-[:VIA_ROLE]->(r:Role)
WITH r, count(DISTINCT f) AS konfliktAnzahl
ORDER BY konfliktAnzahl DESC
LIMIT 5
RETURN r.id AS rolle, konfliktAnzahl;

// --- 2) Detailliste: Top-10 ---
OPTIONAL MATCH (run:Run {dataset:$dataset})
WITH run ORDER BY run.generatedAt DESC LIMIT 1
WITH run
MATCH (f:SoDConflict {dataset:$dataset, runId:run.runId, ruleset:run.ruleset, conflictType:'intra'})-[:VIA_ROLE]->(r:Role)
WITH r, count(DISTINCT f) AS konfliktAnzahl, collect(DISTINCT f.ruleId) AS regeln
ORDER BY konfliktAnzahl DESC
LIMIT 10
RETURN r.id AS rolle, coalesce(r.text, '') AS text, konfliktAnzahl, regeln;
