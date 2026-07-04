// Stellt einen zuvor gesicherten Lauf (Run-Knoten + dessen Findings) aus einem Lauf-Backup
// wieder her. Bewusst OHNE Evidenz (VIA_ROLE/VIA_PROFILE) — die ist teuer und ueber
// POST /runs/{runId}/explain jederzeit neu berechenbar (siehe explain_sod.cypher).
// Sicherheit gegen Phantom-Knoten (AE-10, nie Fake-Rohdaten schreiben): User und SoDRule
// werden nur per MATCH (nicht MERGE) referenziert — Findings, deren User oder Regel im
// aktuellen Dataset nicht (mehr) existieren, werden dadurch automatisch uebersprungen statt
// falsche Knoten anzulegen. Der Datenstand-Abgleich (Dataset-uid) erfolgt VOR diesem Aufruf
// im Backend (siehe POST /runs/backups/{file}/restore).
// Parameter: $run (Map der gesicherten Run-Properties, inkl. ruleset/dataset/runId/asOf/...),
//            $findings (Liste von Maps: user, rule, criticality, criticalityRank, asOf,
//            reasonCode, sleeping, lastLogonKnown, conflictType), $runId.
// lastLogonKnown fehlt in Backups von vor dieser Unterscheidung -- Default true (altes
// Verhalten beibehalten, keine rueckwirkende "unbekannt"-Kennzeichnung fuer alte Backups).
MATCH (f:SoDConflict {runId:$runId}) DETACH DELETE f;

MATCH (old:Run {runId:$runId}) DETACH DELETE old;

MERGE (run:Run {key: $run.ruleset + '|' + $run.dataset + '|' + $runId})
  SET run += $run;

UNWIND $findings AS x
MATCH (u:User {dataset:$run.dataset, id: x.user})
MATCH (rule:SoDRule {ruleset:$run.ruleset, id: x.rule})
MERGE (u)-[:VIOLATES]->(f:SoDConflict {key: $run.ruleset + '|' + $run.dataset + '|' + $runId + '|' + x.rule + '|' + x.user})
  SET f.ruleset = $run.ruleset, f.dataset = $run.dataset, f.runId = $runId, f.asOf = x.asOf,
      f.ruleId = x.rule, f.reasonCode = x.reasonCode, f.criticality = x.criticality,
      f.criticalityRank = x.criticalityRank, f.userSleeping = x.sleeping,
      f.lastLogonKnown = coalesce(x.lastLogonKnown, true), f.conflictType = x.conflictType
MERGE (f)-[:BASED_ON]->(rule);
