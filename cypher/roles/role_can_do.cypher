// Rollenzentrisch (Rollen-Detailseite, Reiter "Einzelberechtigungen"): welche Ruleset-Queries
// erfuellt die Rolle ALLEIN? Exakt die PROVIDES-Praedikate aus cypher/sod/explain_sod_one.cypher
// (Akteur-Reichweite ueber CONTAINS/HAS_PROFILE bis Tiefe 4 -> HAS_AUTH; Org-Felder "egal"),
// nur ueber die Rolle per $roleId gebunden und mit RETURN der Query-Metadaten statt MERGE PROVIDES.
// Lauf-unabhaengig (Fakt ueber Rolle+Auths). Parameter: $ruleset, $dataset, $roleId.
MATCH (actor:Role {id:$roleId, dataset:$dataset})
MATCH (of:OrgField {dataset:$dataset})
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
RETURN q.id AS id, coalesce(q.shortDescription, q.description, '') AS name,
       q.module AS module, q.criticality AS criticality
ORDER BY q.id;
