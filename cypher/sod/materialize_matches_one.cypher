// Materialisiert MATCHES fuer GENAU EINE Query (alle User des Datasets dagegen geprueft) --
// Koerper 1:1 aus dem frueheren apoc.periodic.iterate-Batch-Statement uebernommen, nur das
// bisher implizite `q` (aus der Batch-Zeile) wird jetzt explizit ueber $qid gebunden. Eine
// solche Einheit = ein Fortschrittsschritt in _run_phase().
// Parameter: $ruleset, $dataset, $asOf, $runId, $orgMode, $orgFilters, $qid.
MATCH (q:Query {ruleset:$ruleset, id:$qid})
MATCH (of:OrgField {dataset:$dataset})
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
                    // --- Org-Feld je Feld boolesch verschachtelt (ROADMAP 9.3): $orgFilters[feld] =
                    // {op:'AND'|'OR', children:[node,...]}. Ein node ist entweder ein Leaf
                    // ({type:'value',value} / {type:'range',from,to}) oder eine Gruppe
                    // ({type:'group', op:'AND'|'OR', children:[Leaf,...]}) -- Gruppen enthalten laut
                    // Backend-Validierung (_validate_org_node) ausschliesslich Leafs, keine
                    // Gruppe-in-Gruppe (bewusste 2-Ebenen-Grenze). Legacy-Profile ({op,values}/
                    // {op:'RANGE',from,to}) werden von _normalize_org_filter() vor dem Lauf bereits
                    // in diese Form gebracht -- hier kommt immer schon die Baumform an.
                    WHEN 'filtered' THEN
                      CASE WHEN $orgFilters[r.field] IS NULL THEN true
                        ELSE apoc.any.property(a,'f_'+r.field) IS NOT NULL
                             AND ( '*' IN apoc.any.property(a,'f_'+r.field)
                                   OR CASE $orgFilters[r.field].op
                                        WHEN 'AND' THEN all(child IN $orgFilters[r.field].children WHERE
                                          CASE WHEN child.type='group' THEN
                                            CASE child.op
                                              WHEN 'AND' THEN all(lf IN child.children WHERE
                                                    (lf.type='value' AND (lf.value IN apoc.any.property(a,'f_'+r.field)
                                                          OR any(rg IN apoc.any.property(a,'f_'+r.field) WHERE rg CONTAINS '..' AND split(rg,'..')[0]<=lf.value AND lf.value<=split(rg,'..')[1])))
                                                    OR (lf.type='range' AND any(v IN apoc.any.property(a,'f_'+r.field) WHERE
                                                          (NOT v CONTAINS '..' AND lf.from<=v AND v<=lf.to)
                                                          OR (v CONTAINS '..' AND split(v,'..')[0]<=lf.to AND lf.from<=split(v,'..')[1]))))
                                              WHEN 'OR' THEN any(lf IN child.children WHERE
                                                    (lf.type='value' AND (lf.value IN apoc.any.property(a,'f_'+r.field)
                                                          OR any(rg IN apoc.any.property(a,'f_'+r.field) WHERE rg CONTAINS '..' AND split(rg,'..')[0]<=lf.value AND lf.value<=split(rg,'..')[1])))
                                                    OR (lf.type='range' AND any(v IN apoc.any.property(a,'f_'+r.field) WHERE
                                                          (NOT v CONTAINS '..' AND lf.from<=v AND v<=lf.to)
                                                          OR (v CONTAINS '..' AND split(v,'..')[0]<=lf.to AND lf.from<=split(v,'..')[1]))))
                                              ELSE false END
                                          ELSE
                                            (child.type='value' AND (child.value IN apoc.any.property(a,'f_'+r.field)
                                                  OR any(rg IN apoc.any.property(a,'f_'+r.field) WHERE rg CONTAINS '..' AND split(rg,'..')[0]<=child.value AND child.value<=split(rg,'..')[1])))
                                            OR (child.type='range' AND any(v IN apoc.any.property(a,'f_'+r.field) WHERE
                                                  (NOT v CONTAINS '..' AND child.from<=v AND v<=child.to)
                                                  OR (v CONTAINS '..' AND split(v,'..')[0]<=child.to AND child.from<=split(v,'..')[1])))
                                          END)
                                        WHEN 'OR' THEN any(child IN $orgFilters[r.field].children WHERE
                                          CASE WHEN child.type='group' THEN
                                            CASE child.op
                                              WHEN 'AND' THEN all(lf IN child.children WHERE
                                                    (lf.type='value' AND (lf.value IN apoc.any.property(a,'f_'+r.field)
                                                          OR any(rg IN apoc.any.property(a,'f_'+r.field) WHERE rg CONTAINS '..' AND split(rg,'..')[0]<=lf.value AND lf.value<=split(rg,'..')[1])))
                                                    OR (lf.type='range' AND any(v IN apoc.any.property(a,'f_'+r.field) WHERE
                                                          (NOT v CONTAINS '..' AND lf.from<=v AND v<=lf.to)
                                                          OR (v CONTAINS '..' AND split(v,'..')[0]<=lf.to AND lf.from<=split(v,'..')[1]))))
                                              WHEN 'OR' THEN any(lf IN child.children WHERE
                                                    (lf.type='value' AND (lf.value IN apoc.any.property(a,'f_'+r.field)
                                                          OR any(rg IN apoc.any.property(a,'f_'+r.field) WHERE rg CONTAINS '..' AND split(rg,'..')[0]<=lf.value AND lf.value<=split(rg,'..')[1])))
                                                    OR (lf.type='range' AND any(v IN apoc.any.property(a,'f_'+r.field) WHERE
                                                          (NOT v CONTAINS '..' AND lf.from<=v AND v<=lf.to)
                                                          OR (v CONTAINS '..' AND split(v,'..')[0]<=lf.to AND lf.from<=split(v,'..')[1]))))
                                              ELSE false END
                                          ELSE
                                            (child.type='value' AND (child.value IN apoc.any.property(a,'f_'+r.field)
                                                  OR any(rg IN apoc.any.property(a,'f_'+r.field) WHERE rg CONTAINS '..' AND split(rg,'..')[0]<=child.value AND child.value<=split(rg,'..')[1])))
                                            OR (child.type='range' AND any(v IN apoc.any.property(a,'f_'+r.field) WHERE
                                                  (NOT v CONTAINS '..' AND child.from<=v AND v<=child.to)
                                                  OR (v CONTAINS '..' AND split(v,'..')[0]<=child.to AND child.from<=split(v,'..')[1])))
                                          END)
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
MERGE (u)-[mm:MATCHES {ruleset:$ruleset, runId:$runId}]->(q) SET mm.asOf=$asOf;
