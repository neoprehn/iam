// Einzelberechtigungs-Matcher: welche User erfuellen Query $query des Rulesets $ruleset?
// Semantik (combinationSemantics): Werte AND/OR je AuthReq.andLogic, Felder/Objekte UND,
// TCodes ODER, Auth-Teil UND TCode-Teil (ausser disregardTcode oder tcode '*' = beliebig).
// '*'/Bereiche 'LOW..HIGH' decken ab (AE-06). Org-Felder (:OrgField aus USORG): per DEFAULT
// "egal" (wie '*'); ueber $orgFilters je Feld einschraenkbar ({op: AND|OR|RANGE, values/from/to}).
// Effektive Auths ueber Rollen/Profile/Composite/Collective; ASSIGNED_TO stichtagsgefiltert.
// Parameter: $ruleset, $query, $dataset, $asOf, $orgFilters (Map; {} = alle Org-Felder egal).
// Aufruf: ... -P "ruleset=>'kpmg_r3'" -P "query=>'1003_BC-SEC'" -P "dataset=>'acme'"
//         -P "asOf=>date()" -P "orgFilters=>{BUKRS:{op:'OR',values:['1000','4000']}}"

MATCH (of:OrgField {dataset:$dataset})
WITH collect(of.field) AS orgFields
MATCH (q:Query {key: $ruleset + '|' + $query})
OPTIONAL MATCH (q)-[:REQUIRES]->(ar:AuthReq)
WITH orgFields, q, collect(ar) AS reqs
WITH orgFields, q, reqs, apoc.coll.toSet([r IN reqs | r.object]) AS objects,
     q.tcodes AS tcodes, q.disregardTcode AS disregard

MATCH (u:User {dataset:$dataset})
WHERE
  all(obj IN objects WHERE
    EXISTS {
      MATCH (u)-[asg:ASSIGNED_TO|HAS_PROFILE]->()-[:CONTAINS|HAS_PROFILE*0..4]->()-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:obj})
      WHERE (type(asg) = 'HAS_PROFILE'
             OR ((asg.validFrom IS NULL OR asg.validFrom <= $asOf) AND (asg.validTo IS NULL OR $asOf <= asg.validTo)))
        AND all(r IN [x IN reqs WHERE x.object = obj] WHERE
              CASE
                // Org-Feld ohne Filter -> egal
                WHEN r.field IN orgFields AND $orgFilters[r.field] IS NULL THEN true
                // Org-Feld mit Filter -> Auth-Wert muss Filter abdecken (op AND|OR|RANGE; '*' deckt alles)
                WHEN r.field IN orgFields THEN
                  apoc.any.property(a, 'f_' + r.field) IS NOT NULL
                  AND ( '*' IN apoc.any.property(a, 'f_' + r.field)
                        OR CASE $orgFilters[r.field].op
                             WHEN 'AND' THEN all(v IN $orgFilters[r.field].values WHERE
                                    v IN apoc.any.property(a, 'f_' + r.field)
                                    OR any(rg IN apoc.any.property(a, 'f_' + r.field) WHERE rg CONTAINS '..' AND split(rg,'..')[0] <= v AND v <= split(rg,'..')[1]))
                             WHEN 'OR' THEN any(v IN $orgFilters[r.field].values WHERE
                                    v IN apoc.any.property(a, 'f_' + r.field)
                                    OR any(rg IN apoc.any.property(a, 'f_' + r.field) WHERE rg CONTAINS '..' AND split(rg,'..')[0] <= v AND v <= split(rg,'..')[1]))
                             WHEN 'RANGE' THEN any(x IN apoc.any.property(a, 'f_' + r.field) WHERE
                                    (NOT x CONTAINS '..' AND $orgFilters[r.field].from <= x AND x <= $orgFilters[r.field].to)
                                    OR (x CONTAINS '..' AND split(x,'..')[0] <= $orgFilters[r.field].to AND $orgFilters[r.field].from <= split(x,'..')[1]))
                             ELSE false END )
                // normales Feld -> Query-Wertabdeckung (AND/OR je andLogic)
                ELSE
                  apoc.any.property(a, 'f_' + r.field) IS NOT NULL
                  AND ( '*' IN apoc.any.property(a, 'f_' + r.field)
                        OR CASE WHEN r.andLogic
                             THEN all(v IN r.values WHERE
                                    v IN apoc.any.property(a, 'f_' + r.field)
                                    OR any(rg IN apoc.any.property(a, 'f_' + r.field) WHERE rg CONTAINS '..' AND split(rg,'..')[0] <= v AND v <= split(rg,'..')[1]))
                             ELSE any(v IN r.values WHERE
                                    v IN apoc.any.property(a, 'f_' + r.field)
                                    OR any(rg IN apoc.any.property(a, 'f_' + r.field) WHERE rg CONTAINS '..' AND split(rg,'..')[0] <= v AND v <= split(rg,'..')[1]))
                           END )
              END )
    }
  )
  AND ( disregard OR size(tcodes) = 0 OR '*' IN tcodes OR
    EXISTS {
      MATCH (u)-[asg:ASSIGNED_TO|HAS_PROFILE]->()-[:CONTAINS|HAS_PROFILE*0..4]->()-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:'S_TCODE'})
      WHERE (type(asg) = 'HAS_PROFILE'
             OR ((asg.validFrom IS NULL OR asg.validFrom <= $asOf) AND (asg.validTo IS NULL OR $asOf <= asg.validTo)))
        AND apoc.any.property(a, 'f_TCD') IS NOT NULL
        AND ( '*' IN apoc.any.property(a, 'f_TCD')
              OR any(tc IN tcodes WHERE tc IN apoc.any.property(a, 'f_TCD')
                     OR any(rg IN apoc.any.property(a, 'f_TCD')
                            WHERE rg CONTAINS '..' AND split(rg,'..')[0] <= tc AND tc <= split(rg,'..')[1])) )
    }
  )
RETURN u.id AS user, coalesce(u.name,'') AS name,
       CASE WHEN 'Dialog' IN labels(u) THEN 'Dialog' WHEN 'System' IN labels(u) THEN 'System'
            WHEN 'Service' IN labels(u) THEN 'Service' WHEN 'Communication' IN labels(u) THEN 'Comm' ELSE '?' END AS typ,
       CASE WHEN 'Locked' IN labels(u) THEN 'gesperrt' ELSE 'aktiv' END AS status
ORDER BY status, user;
