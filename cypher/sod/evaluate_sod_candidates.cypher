// Kandidaten-Liste fuer die evaluate-Phase: welche Regeln (nach Scope $minCriticalityRank/
// $sodRules) ueberhaupt geprueft werden muessen. Treibt die Python-Schleife in _run_phase() --
// eine Zeile hier = eine Fortschritts-/Checkpoint-Einheit, abgearbeitet von evaluate_sod_one.cypher.
// Parameter: $ruleset, $minCriticalityRank, $sodRules.
MATCH (rule:SoDRule {ruleset:$ruleset})
WHERE EXISTS { (rule)-[:HAS_CLAUSE]->() }
  AND coalesce(rule.criticalityRank, 0) >= $minCriticalityRank
  AND ( size($sodRules) = 0 OR rule.id IN $sodRules )
RETURN rule.id AS id ORDER BY rule.id;
