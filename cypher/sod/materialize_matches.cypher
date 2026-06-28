// Zwischenergebnis "wer kann was": (:User)-[:MATCHES]->(:Query) fuer die SoD-relevanten
// Queries eines Rulesets (die, die in einer Klausel referenziert werden). Semantik wie
// cypher/checks/query_match.cypher. Org-Felder (:OrgField aus USORG) je nach $orgMode:
//   ignoreOrg   -> egal (Default; "kann der User die Funktion ueberhaupt")
//   wildcardOnly-> nur wenn der Auth-Wert echtes '*' traegt (uebergreifend/Vollbereich)
//   filtered    -> je Org-Feld eine Bedingung aus $orgFilters {op: AND|OR|RANGE, values/from/to};
//                  nicht gelistete Org-Felder bleiben egal ('*' deckt ohnehin alles, AE-06).
// Idempotent: alte MATCHES dieses Laufs werden zuerst geloescht (MATCHES ist pro runId
// gescoped, nicht ruleset-weit geteilt -- sonst ueberschreiben sich parallele Varianten-Laeufe).
// Parameter: $ruleset, $dataset, $asOf, $runId, $orgMode, $orgFilters (Map; {} = keine Filter).

MATCH (:User {dataset:$dataset})-[m:MATCHES {ruleset:$ruleset, runId:$runId}]->() DELETE m;

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
                 CASE
                   // --- Org-Feld: Verhalten nach $orgMode ---
                   WHEN r.field IN orgFields THEN
                     CASE $orgMode
                       WHEN 'wildcardOnly' THEN
                         apoc.any.property(a,'f_'+r.field) IS NOT NULL AND '*' IN apoc.any.property(a,'f_'+r.field)
                       WHEN 'filtered' THEN
                         CASE WHEN $orgFilters[r.field] IS NULL THEN true
                           ELSE apoc.any.property(a,'f_'+r.field) IS NOT NULL
                                AND ( '*' IN apoc.any.property(a,'f_'+r.field)
                                      OR CASE $orgFilters[r.field].op
                                           WHEN 'AND' THEN all(v IN $orgFilters[r.field].values WHERE
                                                  v IN apoc.any.property(a,'f_'+r.field)
                                                  OR any(rg IN apoc.any.property(a,'f_'+r.field) WHERE rg CONTAINS '..' AND split(rg,'..')[0]<=v AND v<=split(rg,'..')[1]))
                                           WHEN 'OR' THEN any(v IN $orgFilters[r.field].values WHERE
                                                  v IN apoc.any.property(a,'f_'+r.field)
                                                  OR any(rg IN apoc.any.property(a,'f_'+r.field) WHERE rg CONTAINS '..' AND split(rg,'..')[0]<=v AND v<=split(rg,'..')[1]))
                                           WHEN 'RANGE' THEN any(x IN apoc.any.property(a,'f_'+r.field) WHERE
                                                  (NOT x CONTAINS '..' AND $orgFilters[r.field].from<=x AND x<=$orgFilters[r.field].to)
                                                  OR (x CONTAINS '..' AND split(x,'..')[0]<=$orgFilters[r.field].to AND $orgFilters[r.field].from<=split(x,'..')[1]))
                                           ELSE false END )
                         END
                       ELSE true
                     END
                   // --- normales Feld: Query-Wertabdeckung (AND/OR je andLogic) ---
                   ELSE
                     apoc.any.property(a,'f_'+r.field) IS NOT NULL
                     AND ( '*' IN apoc.any.property(a,'f_'+r.field)
                           OR CASE WHEN r.andLogic
                                THEN all(v IN r.values WHERE v IN apoc.any.property(a,'f_'+r.field)
                                       OR any(rg IN apoc.any.property(a,'f_'+r.field) WHERE rg CONTAINS '..' AND split(rg,'..')[0]<=v AND v<=split(rg,'..')[1]))
                                ELSE any(v IN r.values WHERE v IN apoc.any.property(a,'f_'+r.field)
                                       OR any(rg IN apoc.any.property(a,'f_'+r.field) WHERE rg CONTAINS '..' AND split(rg,'..')[0]<=v AND v<=split(rg,'..')[1]))
                              END )
                 END )
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
   MERGE (u)-[mm:MATCHES {ruleset:$ruleset, runId:$runId}]->(q) SET mm.asOf=$asOf",
  {batchSize:1, parallel:false, params:{ruleset:$ruleset, dataset:$dataset, asOf:$asOf, runId:$runId, orgMode:$orgMode, orgFilters:$orgFilters}}
) YIELD batches, total, committedOperations, failedOperations, errorMessages
RETURN batches, total, committedOperations, failedOperations, errorMessages;
