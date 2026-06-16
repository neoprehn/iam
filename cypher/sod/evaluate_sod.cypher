// SoD-Auswertung auf dem Zwischenergebnis (:User)-[:MATCHES]->(:Query) — reine Mengenlogik,
// KEIN erneutes Auth-Durchlaufen. Ein User verletzt eine Regel, wenn JEDE Klausel (CNF)
// mindestens eine von ihm gematchte Query enthaelt. Findings (:SoDConflict) mit Provenienz;
// Risiko/Kritikalitaet stammt aus (:SoDRule) (wird nur angehaengt, nicht neu bewertet).
//
// Nutzertyp-Filter: $userTypes = Liste Subtyp-Labels (z. B. ['Dialog','Service']); leer = alle.
// Sperr-Filter: $excludeLocked = true -> gesperrte User (`:Locked`, UFLAG) ausschliessen.
//   (Nutzertyp und Sperre sind getrennte Achsen: A/S sagt nichts ueber gesperrt/aktiv.)
// Sleeping-Flag: userSleeping = kein Logon in $sleepDays Tagen (oder nie).
// Scope: $minCriticalityRank (0..5; nur Regeln >= Rang, 5=very-high) und $sodRules (Liste
// expliziter Regel-IDs; leer = alle) — so laufen z. B. „nur very-critical" oder einzelne Regeln.
// Idempotent: alte Findings dieses (ruleset,dataset,runId) werden zuerst entfernt.
// Parameter: $ruleset, $dataset, $asOf, $runId, $userTypes (list), $excludeLocked (bool),
//            $sleepDays (int), $minCriticalityRank (int), $sodRules (list).
// Aufruf: ... -P "userTypes=>['Dialog','Service']" -P "excludeLocked=>true" -P "sleepDays=>180" ...

CREATE CONSTRAINT sodconflict_key IF NOT EXISTS FOR (f:SoDConflict) REQUIRE f.key IS UNIQUE;
CREATE CONSTRAINT run_key IF NOT EXISTS FOR (r:Run) REQUIRE r.key IS UNIQUE;

MATCH (f:SoDConflict {ruleset:$ruleset, dataset:$dataset, runId:$runId}) DETACH DELETE f;

// Run-Knoten trägt den Scope des Laufs -> Can-Do-KPIs (z. B. SAP_ALL) können denselben
// Nutzertyp-/Sperr-Filter anwenden wie die SoD-Auswertung.
MERGE (run:Run {key: $ruleset + '|' + $dataset + '|' + $runId})
  SET run.runId = $runId, run.ruleset = $ruleset, run.dataset = $dataset, run.asOf = $asOf,
      run.userTypes = $userTypes, run.excludeLocked = $excludeLocked, run.sleepDays = $sleepDays,
      run.minCriticalityRank = $minCriticalityRank, run.generatedAt = datetime();

MATCH (rule:SoDRule {ruleset:$ruleset})
WHERE EXISTS { (rule)-[:HAS_CLAUSE]->() }
  AND coalesce(rule.criticalityRank, 0) >= $minCriticalityRank
  AND ( size($sodRules) = 0 OR rule.id IN $sodRules )
MATCH (u:User {dataset:$dataset})
WHERE ( size($userTypes) = 0 OR any(t IN $userTypes WHERE t IN labels(u)) )
  AND ( NOT $excludeLocked OR NOT 'Locked' IN labels(u) )
  AND all( cl IN [(rule)-[:HAS_CLAUSE]->(c) | c]
           WHERE EXISTS { MATCH (cl)-[:NEEDS]->(q)<-[:MATCHES {ruleset:$ruleset}]-(u) } )
MERGE (u)-[:VIOLATES]->(f:SoDConflict {key: $ruleset + '|' + $dataset + '|' + $runId + '|' + rule.id + '|' + u.id})
  SET f.ruleset = $ruleset, f.dataset = $dataset, f.runId = $runId, f.asOf = $asOf,
      f.ruleId = rule.id, f.reasonCode = rule.reasonCode,
      f.criticality = rule.criticality, f.criticalityRank = rule.criticalityRank,
      f.userSleeping = (u.lastLogon IS NULL OR u.lastLogon < ($asOf - duration({days: $sleepDays})))
MERGE (f)-[:BASED_ON]->(rule);
