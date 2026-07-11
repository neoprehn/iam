// PROVIDES fuer GENAU EINEN Akteur (Rolle/Profil) berechnen: erfuellt dieser Akteur eine
// Clause-Query ALLEIN? (gleiche Semantik wie der Matcher, aber ab dem Akteur statt ab dem User;
// Org-Felder im Default "egal"). Koerper 1:1 aus dem frueheren apoc.periodic.iterate-Batch-
// Statement uebernommen, nur das bisher implizite `actor` (aus der Batch-Zeile) wird jetzt
// explizit ueber $actorId (elementId) gebunden. PROVIDES ist lauf-unabhaengig (Fakt ueber
// Akteur+Auths) -> idempotent ge-MERGE-t, ueber Laeufe wiederverwendbar.
// Evidenz-Perf: die Erreichbarkeit Akteur->Authorization ist die vorab materialisierte
// GRANTS-Kante (s. load/91_materialize_grants.cypher) statt einer variablen
// CONTAINS|HAS_PROFILE*0..4-Pfadsuche je Aufruf.
// Parameter: $ruleset, $dataset, $actorId.
MATCH (actor) WHERE elementId(actor) = $actorId
MATCH (of:OrgField {dataset:$dataset})
WITH actor, collect(of.field) AS orgFields
MATCH (q:Query {ruleset:$ruleset}) WHERE EXISTS { (q)<-[:NEEDS]-(:Clause {ruleset:$ruleset}) }
OPTIONAL MATCH (q)-[:REQUIRES]->(ar)
WITH actor, orgFields, q, collect(ar) AS reqs, q.tcodes AS tcodes, q.disregardTcode AS disregard
WITH actor, q, orgFields, reqs, tcodes, disregard, apoc.coll.toSet([r IN reqs | r.object]) AS objects
WHERE
  all(obj IN objects WHERE
    EXISTS {
      MATCH (actor)-[:GRANTS]->(a:Authorization {dataset:$dataset, object:obj})
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
      MATCH (actor)-[:GRANTS]->(a:Authorization {dataset:$dataset, object:'S_TCODE'})
      WHERE apoc.any.property(a,'f_TCD') IS NOT NULL
        AND ( '*' IN apoc.any.property(a,'f_TCD')
              OR any(tc IN tcodes WHERE tc IN apoc.any.property(a,'f_TCD')
                     OR any(rg IN apoc.any.property(a,'f_TCD') WHERE rg CONTAINS '..' AND split(rg,'..')[0]<=tc AND tc<=split(rg,'..')[1])) )
    }
  )
MERGE (actor)-[:PROVIDES {ruleset:$ruleset}]->(q);
