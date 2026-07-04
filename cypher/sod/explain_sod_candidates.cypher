// Kandidaten-Liste fuer die explain-Phase (Schritt 1, PROVIDES): welche Akteure (Rolle/Profil)
// der Finding-User dieses Laufs ueberhaupt betrachtet werden muessen. Treibt die
// Python-Schleife in _run_phase() -- eine Zeile hier = eine Fortschritts-/Checkpoint-Einheit,
// abgearbeitet von explain_sod_one.cypher. elementId() ist die einzige gemeinsame stabile ID
// ueber Rolle UND Profil hinweg (beide haben nur je eigene .id-Property/-Constraint).
// Parameter: $ruleset, $dataset, $runId.
MATCH (u:User {dataset:$dataset})-[:VIOLATES]->(:SoDConflict {ruleset:$ruleset, runId:$runId})
MATCH (u)-[:ASSIGNED_TO|HAS_PROFILE]->(actor)
RETURN DISTINCT elementId(actor) AS id;
