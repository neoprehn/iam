// Findings erklaerbar machen (AE-11), Abschluss der explain-Phase -- laeuft NACH der
// PROVIDES-Schleife (explain_sod_candidates.cypher/explain_sod_one.cypher) einmal am Stueck:
// bereits auf die Findings dieses Laufs begrenzt (nicht auf alle User/Akteure), damit schnell
// genug fuer einen einzigen Aufruf ohne eigenen Fortschritt/Resume.
// Parameter: $ruleset, $dataset, $asOf, $runId.

// --- Evidenz-Kanten zuruecksetzen (idempotent je Lauf) --------------------------------------
MATCH (:SoDConflict {ruleset:$ruleset, dataset:$dataset, runId:$runId})-[v:VIA_ROLE|VIA_PROFILE]->()
DELETE v;

// --- VIA_ROLE: belastete Rollen (decken >=1 Klausel ueber eine vom User gematchte Query) -----
MATCH (u:User {dataset:$dataset})-[:VIOLATES]->(f:SoDConflict {ruleset:$ruleset, runId:$runId})-[:BASED_ON]->(rule:SoDRule)
MATCH (u)-[g:ASSIGNED_TO]->(actor:Role)
WHERE (g.validFrom IS NULL OR g.validFrom<=$asOf) AND (g.validTo IS NULL OR $asOf<=g.validTo)
  AND EXISTS { MATCH (actor)-[:PROVIDES {ruleset:$ruleset}]->(q)<-[:NEEDS]-(:Clause)<-[:HAS_CLAUSE]-(rule)
               WHERE (u)-[:MATCHES {ruleset:$ruleset, runId:$runId}]->(q) }
MERGE (f)-[:VIA_ROLE]->(actor);

// --- VIA_PROFILE: direkt zugewiesene Profile (z. B. SAP_ALL), die >=1 Klausel decken ---------
MATCH (u:User {dataset:$dataset})-[:VIOLATES]->(f:SoDConflict {ruleset:$ruleset, runId:$runId})-[:BASED_ON]->(rule:SoDRule)
MATCH (u)-[:HAS_PROFILE]->(actor:Profile)
WHERE EXISTS { MATCH (actor)-[:PROVIDES {ruleset:$ruleset}]->(q)<-[:NEEDS]-(:Clause)<-[:HAS_CLAUSE]-(rule)
               WHERE (u)-[:MATCHES {ruleset:$ruleset, runId:$runId}]->(q) }
MERGE (f)-[:VIA_PROFILE]->(actor);

// --- conflictType: intra, wenn EIN Akteur alle Klauseln deckt; sonst inter -------------------
MATCH (u:User {dataset:$dataset})-[:VIOLATES]->(f:SoDConflict {ruleset:$ruleset, runId:$runId})-[:BASED_ON]->(rule:SoDRule)
WITH f, u, rule, size([(rule)-[:HAS_CLAUSE]->(c) | c]) AS nClauses
OPTIONAL MATCH (u)-[g:ASSIGNED_TO|HAS_PROFILE]->(actor)
WHERE (type(g)='HAS_PROFILE' OR ((g.validFrom IS NULL OR g.validFrom<=$asOf) AND (g.validTo IS NULL OR $asOf<=g.validTo)))
WITH f, rule, nClauses, actor,
     size([ (rule)-[:HAS_CLAUSE]->(cl)
            WHERE actor IS NOT NULL AND EXISTS {
              MATCH (actor)-[:PROVIDES {ruleset:$ruleset}]->(q)<-[:NEEDS]-(cl)
              WHERE (f)<-[:VIOLATES]-(:User)-[:MATCHES {ruleset:$ruleset, runId:$runId}]->(q) } | cl ]) AS nCov
WITH f, nClauses, max(nCov) AS bestCoverage
SET f.conflictType = CASE WHEN nClauses > 0 AND bestCoverage >= nClauses THEN 'intra' ELSE 'inter' END,
    f.viaRoleCount = size([(f)-[:VIA_ROLE]->(r) | r]),
    f.viaProfileCount = size([(f)-[:VIA_PROFILE]->(p) | p]);
