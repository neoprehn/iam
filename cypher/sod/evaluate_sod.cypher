// SoD-Auswertung auf dem Zwischenergebnis (:User)-[:MATCHES]->(:Query) — reine Mengenlogik,
// KEIN erneutes Auth-Durchlaufen. Ein User verletzt eine Regel, wenn JEDE Klausel (CNF)
// mindestens eine von ihm gematchte Query enthaelt. Findings (:SoDConflict) mit Provenienz;
// Risiko/Kritikalitaet stammt aus (:SoDRule) (wird nur angehaengt, nicht neu bewertet).
//
// Nutzertyp-Filter: $userTypes = Liste Subtyp-Labels (z. B. ['Dialog','Service']); leer = alle.
// Sleeping-Flag: userSleeping = kein Logon in $sleepDays Tagen (oder nie).
// Idempotent: alte Findings dieses (ruleset,dataset,runId) werden zuerst entfernt.
// Parameter: $ruleset, $dataset, $asOf, $runId, $userTypes (list), $sleepDays (int).
// Aufruf: ... -P "userTypes=>['Dialog','Service']" -P "sleepDays=>180" ...

CREATE CONSTRAINT sodconflict_key IF NOT EXISTS FOR (f:SoDConflict) REQUIRE f.key IS UNIQUE;

MATCH (f:SoDConflict {ruleset:$ruleset, dataset:$dataset, runId:$runId}) DETACH DELETE f;

MATCH (rule:SoDRule {ruleset:$ruleset}) WHERE EXISTS { (rule)-[:HAS_CLAUSE]->() }
MATCH (u:User {dataset:$dataset})
WHERE ( size($userTypes) = 0 OR any(t IN $userTypes WHERE t IN labels(u)) )
  AND all( cl IN [(rule)-[:HAS_CLAUSE]->(c) | c]
           WHERE EXISTS { MATCH (cl)-[:NEEDS]->(q)<-[:MATCHES {ruleset:$ruleset}]-(u) } )
MERGE (u)-[:VIOLATES]->(f:SoDConflict {key: $ruleset + '|' + $dataset + '|' + $runId + '|' + rule.id + '|' + u.id})
  SET f.ruleset = $ruleset, f.dataset = $dataset, f.runId = $runId, f.asOf = $asOf,
      f.ruleId = rule.id, f.reasonCode = rule.reasonCode,
      f.criticality = rule.criticality, f.criticalityRank = rule.criticalityRank,
      f.userSleeping = (u.lastLogon IS NULL OR u.lastLogon < ($asOf - duration({days: $sleepDays})))
MERGE (f)-[:BASED_ON]->(rule);
