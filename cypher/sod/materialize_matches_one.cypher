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
MERGE (u)-[mm:MATCHES {ruleset:$ruleset, runId:$runId}]->(q) SET mm.asOf=$asOf;
