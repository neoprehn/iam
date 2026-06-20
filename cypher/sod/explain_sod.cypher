// Findings erklaerbar machen (AE-11): pro SoDConflict festhalten, welche Rolle(n)/Profile den
// Konflikt verursachen, und ob EINE Rolle/ein Profil allein alle Klauseln erfuellt (intra) oder
// erst die Kombination (inter). Reine Mengenlogik auf einer Hilfsrelation PROVIDES:
//   (:Role|:Profile)-[:PROVIDES {ruleset}]->(:Query)  =  dieser Akteur erfuellt die Query ALLEIN
// (gleiche Semantik wie der Matcher, aber ab dem Akteur statt ab dem User; Org-Felder im Default
// "egal"). Bounded: nur Akteure der Finding-User dieses Laufs. PROVIDES ist lauf-unabhaengig
// (Fakt ueber Akteur+Auths) -> idempotent ge-MERGE-t, ueber Laeufe wiederverwendbar.
// Parameter: $ruleset, $dataset, $asOf, $runId.

// --- 1) PROVIDES: Akteur (Rolle/Profil) erfuellt eine Clause-Query allein -------------------
CALL apoc.periodic.iterate(
  "MATCH (u:User {dataset:$dataset})-[:VIOLATES]->(:SoDConflict {ruleset:$ruleset, runId:$runId})
   MATCH (u)-[:ASSIGNED_TO|HAS_PROFILE]->(actor) RETURN DISTINCT actor",
  "MATCH (of:OrgField {dataset:$dataset})
   WITH actor, collect(of.field) AS orgFields
   MATCH (q:Query {ruleset:$ruleset}) WHERE EXISTS { (q)<-[:NEEDS]-(:Clause {ruleset:$ruleset}) }
   OPTIONAL MATCH (q)-[:REQUIRES]->(ar)
   WITH actor, orgFields, q, collect(ar) AS reqs, q.tcodes AS tcodes, q.disregardTcode AS disregard
   WITH actor, q, orgFields, reqs, tcodes, disregard, apoc.coll.toSet([r IN reqs | r.object]) AS objects
   WHERE
     all(obj IN objects WHERE
       EXISTS {
         MATCH (actor)-[:CONTAINS|HAS_PROFILE*0..4]->()-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:obj})
         WHERE all(r IN [x IN reqs WHERE x.object=obj] WHERE
                 r.field IN orgFields
                 OR ( apoc.any.property(a,'f_'+r.field) IS NOT NULL
                      AND ( '*' IN apoc.any.property(a,'f_'+r.field)
                            OR CASE WHEN r.andLogic
                                 THEN all(v IN r.values WHERE v IN apoc.any.property(a,'f_'+r.field)
                                        OR any(rg IN apoc.any.property(a,'f_'+r.field) WHERE rg CONTAINS '..' AND split(rg,'..')[0]<=v AND v<=split(rg,'..')[1]))
                                 ELSE any(v IN r.values WHERE v IN apoc.any.property(a,'f_'+r.field)
                                        OR any(rg IN apoc.any.property(a,'f_'+r.field) WHERE rg CONTAINS '..' AND split(rg,'..')[0]<=v AND v<=split(rg,'..')[1]))
                               END ) ) )
       }
     )
     AND ( disregard OR size(tcodes)=0 OR '*' IN tcodes OR
       EXISTS {
         MATCH (actor)-[:CONTAINS|HAS_PROFILE*0..4]->()-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:'S_TCODE'})
         WHERE apoc.any.property(a,'f_TCD') IS NOT NULL
           AND ( '*' IN apoc.any.property(a,'f_TCD')
                 OR any(tc IN tcodes WHERE tc IN apoc.any.property(a,'f_TCD')
                        OR any(rg IN apoc.any.property(a,'f_TCD') WHERE rg CONTAINS '..' AND split(rg,'..')[0]<=tc AND tc<=split(rg,'..')[1])) )
       }
     )
   MERGE (actor)-[:PROVIDES {ruleset:$ruleset}]->(q)",
  {batchSize:1, parallel:false, params:{ruleset:$ruleset, dataset:$dataset, asOf:$asOf, runId:$runId}}
) YIELD batches, total, committedOperations, failedOperations, errorMessages
RETURN batches, total, committedOperations, failedOperations, errorMessages;

// --- 2) Evidenz-Kanten zuruecksetzen (idempotent je Lauf) ----------------------------------
MATCH (:SoDConflict {ruleset:$ruleset, dataset:$dataset, runId:$runId})-[v:VIA_ROLE|VIA_PROFILE]->()
DELETE v;

// --- 3) VIA_ROLE: belastete Rollen (decken >=1 Klausel ueber eine vom User gematchte Query) --
MATCH (u:User {dataset:$dataset})-[:VIOLATES]->(f:SoDConflict {ruleset:$ruleset, runId:$runId})-[:BASED_ON]->(rule:SoDRule)
MATCH (u)-[g:ASSIGNED_TO]->(actor:Role)
WHERE (g.validFrom IS NULL OR g.validFrom<=$asOf) AND (g.validTo IS NULL OR $asOf<=g.validTo)
  AND EXISTS { MATCH (actor)-[:PROVIDES {ruleset:$ruleset}]->(q)<-[:NEEDS]-(:Clause)<-[:HAS_CLAUSE]-(rule)
               WHERE (u)-[:MATCHES {ruleset:$ruleset}]->(q) }
MERGE (f)-[:VIA_ROLE]->(actor);

// --- 4) VIA_PROFILE: direkt zugewiesene Profile (z. B. SAP_ALL), die >=1 Klausel decken ------
MATCH (u:User {dataset:$dataset})-[:VIOLATES]->(f:SoDConflict {ruleset:$ruleset, runId:$runId})-[:BASED_ON]->(rule:SoDRule)
MATCH (u)-[:HAS_PROFILE]->(actor:Profile)
WHERE EXISTS { MATCH (actor)-[:PROVIDES {ruleset:$ruleset}]->(q)<-[:NEEDS]-(:Clause)<-[:HAS_CLAUSE]-(rule)
               WHERE (u)-[:MATCHES {ruleset:$ruleset}]->(q) }
MERGE (f)-[:VIA_PROFILE]->(actor);

// --- 5) conflictType: intra, wenn EIN Akteur alle Klauseln deckt; sonst inter ---------------
MATCH (u:User {dataset:$dataset})-[:VIOLATES]->(f:SoDConflict {ruleset:$ruleset, runId:$runId})-[:BASED_ON]->(rule:SoDRule)
WITH f, u, rule, size([(rule)-[:HAS_CLAUSE]->(c) | c]) AS nClauses
OPTIONAL MATCH (u)-[g:ASSIGNED_TO|HAS_PROFILE]->(actor)
WHERE (type(g)='HAS_PROFILE' OR ((g.validFrom IS NULL OR g.validFrom<=$asOf) AND (g.validTo IS NULL OR $asOf<=g.validTo)))
WITH f, rule, nClauses, actor,
     size([ (rule)-[:HAS_CLAUSE]->(cl)
            WHERE actor IS NOT NULL AND EXISTS {
              MATCH (actor)-[:PROVIDES {ruleset:$ruleset}]->(q)<-[:NEEDS]-(cl)
              WHERE (f)<-[:VIOLATES]-(:User)-[:MATCHES {ruleset:$ruleset}]->(q) } | cl ]) AS nCov
WITH f, nClauses, max(nCov) AS bestCoverage
SET f.conflictType = CASE WHEN nClauses > 0 AND bestCoverage >= nClauses THEN 'intra' ELSE 'inter' END,
    f.viaRoleCount = size([(f)-[:VIA_ROLE]->(r) | r]),
    f.viaProfileCount = size([(f)-[:VIA_PROFILE]->(p) | p]);
