// SoD-Auswertung fuer GENAU EINE Regel (alle User des Datasets dagegen geprueft) -- reine
// Mengenlogik auf dem Zwischenergebnis (:User)-[:MATCHES]->(:Query), KEIN erneutes
// Auth-Durchlaufen. Ein User verletzt die Regel, wenn JEDE Klausel (CNF) mindestens eine von
// ihm gematchte Query enthaelt. Koerper 1:1 aus dem frueheren Einzelstatement uebernommen, nur
// die bisher gemeinsame Regel-Auswahl ist jetzt ueber $ruleId auf eine Regel eingeschraenkt --
// eine solche Einheit = ein Fortschrittsschritt in _run_phase().
//
// Nutzertyp-Filter: $userTypes = Liste Subtyp-Labels (z. B. ['Dialog','Service']); leer = alle.
// Sperr-Filter: $excludeLocked = true -> gesperrte User (`:Locked`, UFLAG) ausschliessen.
// Sleeping-Flag: userSleeping = bekannter Logon, aber laenger als $sleepDays Tage her.
// lastLogonKnown = false, wenn TRDAT im Quellextrakt fehlt/leer war -- ein unbekannter Logon
// ist NICHT automatisch "sleeping" (TRDAT ist laut Extraktionsleitfaden ein optionales
// USR02-Feld).
// Parameter: $ruleset, $dataset, $asOf, $runId, $userTypes, $excludeLocked, $sleepDays, $ruleId.
MATCH (rule:SoDRule {ruleset:$ruleset, id:$ruleId})
MATCH (u:User {dataset:$dataset})
WHERE ( size($userTypes) = 0 OR any(t IN $userTypes WHERE t IN labels(u)) )
  AND ( NOT $excludeLocked OR NOT 'Locked' IN labels(u) )
  AND all( cl IN [(rule)-[:HAS_CLAUSE]->(c) | c]
           WHERE EXISTS { MATCH (cl)-[:NEEDS]->(q)<-[:MATCHES {ruleset:$ruleset, runId:$runId}]-(u) } )
MERGE (u)-[:VIOLATES]->(f:SoDConflict {key: $ruleset + '|' + $dataset + '|' + $runId + '|' + rule.id + '|' + u.id})
  SET f.ruleset = $ruleset, f.dataset = $dataset, f.runId = $runId, f.asOf = $asOf,
      f.ruleId = rule.id, f.reasonCode = rule.reasonCode,
      f.criticality = rule.criticality, f.criticalityRank = rule.criticalityRank,
      f.lastLogonKnown = (u.lastLogon IS NOT NULL),
      f.userSleeping = (u.lastLogon IS NOT NULL AND u.lastLogon < ($asOf - duration({days: $sleepDays})))
MERGE (f)-[:BASED_ON]->(rule);
