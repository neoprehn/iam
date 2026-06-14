// Zwischenergebnis "wer kann was": (:User)-[:MATCHES]->(:Query) fuer die SoD-relevanten
// Queries eines Rulesets (die, die in einer Klausel referenziert werden). Org-Felder im
// DEFAULT "egal". Semantik wie cypher/checks/query_match.cypher. Idempotent: alte MATCHES
// dieses Rulesets werden zuerst geloescht. Parameter: $ruleset, $dataset, $asOf, $runId.

MATCH (:User {dataset:$dataset})-[m:MATCHES {ruleset:$ruleset}]->() DELETE m;

CALL apoc.periodic.iterate(
  "MATCH (q:Query {ruleset:$ruleset}) WHERE EXISTS { (q)<-[:NEEDS]-(:Clause {ruleset:$ruleset}) } RETURN q",
  "MATCH (of:OrgField {dataset:$dataset})
   WITH q, collect(of.field) AS orgFields
   OPTIONAL MATCH (q)-[:REQUIRES]->(ar)
   WITH q, orgFields, collect(ar) AS reqs
   WITH q, orgFields, reqs, apoc.coll.toSet([r IN reqs | r.object]) AS objects,
        q.tcodes AS tcodes, q.disregardTcode AS disregard
   MATCH (u:User {dataset:$dataset})
   WHERE
     all(obj IN objects WHERE
       EXISTS {
         MATCH (u)-[asg:ASSIGNED_TO|HAS_PROFILE]->()-[:CONTAINS|HAS_PROFILE*0..4]->()-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:obj})
         WHERE (type(asg)='HAS_PROFILE' OR ((asg.validFrom IS NULL OR asg.validFrom<=$asOf) AND (asg.validTo IS NULL OR $asOf<=asg.validTo)))
           AND all(r IN [x IN reqs WHERE x.object=obj] WHERE
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
         MATCH (u)-[asg:ASSIGNED_TO|HAS_PROFILE]->()-[:CONTAINS|HAS_PROFILE*0..4]->()-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:'S_TCODE'})
         WHERE (type(asg)='HAS_PROFILE' OR ((asg.validFrom IS NULL OR asg.validFrom<=$asOf) AND (asg.validTo IS NULL OR $asOf<=asg.validTo)))
           AND apoc.any.property(a,'f_TCD') IS NOT NULL
           AND ( '*' IN apoc.any.property(a,'f_TCD')
                 OR any(tc IN tcodes WHERE tc IN apoc.any.property(a,'f_TCD')
                        OR any(rg IN apoc.any.property(a,'f_TCD') WHERE rg CONTAINS '..' AND split(rg,'..')[0]<=tc AND tc<=split(rg,'..')[1])) )
       }
     )
   MERGE (u)-[mm:MATCHES {ruleset:$ruleset}]->(q) SET mm.asOf=$asOf, mm.runId=$runId",
  {batchSize:1, parallel:false, params:{ruleset:$ruleset, dataset:$dataset, asOf:$asOf, runId:$runId}}
) YIELD batches, total, committedOperations, failedOperations, errorMessages
RETURN batches, total, committedOperations, failedOperations, errorMessages;
