// Einzelberechtigungs-Matcher: welche User erfuellen Query $query des Rulesets $ruleset?
// Semantik (combinationSemantics): Werte AND/OR je AuthReq.andLogic, Felder/Objekte UND,
// TCodes ODER, Auth-Teil UND TCode-Teil (ausser disregardTcode oder tcode '*' = beliebig).
// '*'/Bereiche 'LOW..HIGH' decken ab (AE-06). Org-Felder (:OrgField aus USORG): per DEFAULT
// "egal" (wie '*'); ueber $orgFilters je Feld als 2-Ebenen-Kriterienbaum einschraenkbar
// ({op:'AND'|'OR', children:[{type:'value',value}|{type:'range',from,to}|{type:'group',op,children:[Leaf,...]}]},
// ROADMAP 9.3 -- Legacy-Profile werden von _normalize_org_filter() vor dem Aufruf in diese Form gebracht).
// Effektive Auths ueber Rollen/Profile/Composite/Collective; ASSIGNED_TO stichtagsgefiltert.
// Parameter: $ruleset, $query, $dataset, $asOf, $orgFilters (Map; {} = alle Org-Felder egal).
// Aufruf: ... -P "ruleset=>'kpmg_r3'" -P "query=>'1003_BC-SEC'" -P "dataset=>'acme'"
//         -P "asOf=>date()" -P "orgFilters=>{BUKRS:{op:'OR',children:[{type:'value',value:'1000'},{type:'value',value:'4000'}]}}"

MATCH (of:OrgField {dataset:$dataset})
WITH collect(of.field) AS orgFields
MATCH (q:Query {key: $ruleset + '|' + $query})
OPTIONAL MATCH (q)-[:REQUIRES]->(ar:AuthReq)
WITH orgFields, q, collect(ar) AS reqs
WITH orgFields, q, reqs, apoc.coll.toSet([r IN reqs | r.object]) AS objects,
     q.tcodes AS tcodes, q.disregardTcode AS disregard

MATCH (u:User {dataset:$dataset})
WHERE
      // 9.3-Perf: billiger Vorfilter ueber das erste benoetigte Objekt, bevor die volle
      // all(obj IN objects ...)-Pruefung ausgefuehrt wird.
      (size(objects)=0 OR EXISTS {
            MATCH (u)-[asg:ASSIGNED_TO|HAS_PROFILE]->()-[:CONTAINS|HAS_PROFILE*0..4]->()-[:HAS_AUTH]->(:Authorization {dataset:$dataset, object:objects[0]})
            WHERE (type(asg) = 'HAS_PROFILE'
                               OR ((asg.validFrom IS NULL OR asg.validFrom <= $asOf) AND (asg.validTo IS NULL OR $asOf <= asg.validTo)))
      })
      AND
      // 9.3-Perf: frueher Kandidatenfilter fuer Queries mit aktivem TCode-Check.
      ( disregard OR size(tcodes)=0 OR '*' IN tcodes OR EXISTS {
            MATCH (u)-[asg:ASSIGNED_TO|HAS_PROFILE]->()-[:CONTAINS|HAS_PROFILE*0..4]->()-[:HAS_AUTH]->(t:Authorization {dataset:$dataset, object:'S_TCODE'})
            WHERE (type(asg) = 'HAS_PROFILE'
                               OR ((asg.validFrom IS NULL OR asg.validFrom <= $asOf) AND (asg.validTo IS NULL OR $asOf <= asg.validTo)))
                  AND apoc.any.property(t, 'f_TCD') IS NOT NULL
      })
      AND
  all(obj IN objects WHERE
    EXISTS {
      MATCH (u)-[asg:ASSIGNED_TO|HAS_PROFILE]->()-[:CONTAINS|HAS_PROFILE*0..4]->()-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:obj})
      WHERE (type(asg) = 'HAS_PROFILE'
             OR ((asg.validFrom IS NULL OR asg.validFrom <= $asOf) AND (asg.validTo IS NULL OR $asOf <= asg.validTo)))
        AND all(r IN [x IN reqs WHERE x.object = obj] WHERE
              CASE
                // Org-Feld ohne Filter -> egal
                WHEN r.field IN orgFields AND $orgFilters[r.field] IS NULL THEN true
                // Org-Feld mit Filter -> Auth-Wert muss den 2-Ebenen-Kriterienbaum erfuellen
                // ({op:'AND'|'OR', children:[Leaf|Gruppe]}, s. materialize_matches_one.cypher fuer
                // die ausfuehrliche Erklaerung; '*' deckt alles ab, unabhaengig vom Baum).
                WHEN r.field IN orgFields THEN
                  apoc.any.property(a, 'f_' + r.field) IS NOT NULL
                  AND ( '*' IN apoc.any.property(a, 'f_' + r.field)
                        OR CASE $orgFilters[r.field].op
                             WHEN 'AND' THEN all(child IN $orgFilters[r.field].children WHERE
                               CASE WHEN child.type = 'group' THEN
                                 CASE child.op
                                   WHEN 'AND' THEN all(lf IN child.children WHERE
                                         (lf.type = 'value' AND (lf.value IN apoc.any.property(a, 'f_' + r.field)
                                               OR any(rg IN apoc.any.property(a, 'f_' + r.field) WHERE rg CONTAINS '..' AND split(rg,'..')[0] <= lf.value AND lf.value <= split(rg,'..')[1])))
                                         OR (lf.type = 'range' AND any(v IN apoc.any.property(a, 'f_' + r.field) WHERE
                                               (NOT v CONTAINS '..' AND lf.from <= v AND v <= lf.to)
                                               OR (v CONTAINS '..' AND split(v,'..')[0] <= lf.to AND lf.from <= split(v,'..')[1]))))
                                   WHEN 'OR' THEN any(lf IN child.children WHERE
                                         (lf.type = 'value' AND (lf.value IN apoc.any.property(a, 'f_' + r.field)
                                               OR any(rg IN apoc.any.property(a, 'f_' + r.field) WHERE rg CONTAINS '..' AND split(rg,'..')[0] <= lf.value AND lf.value <= split(rg,'..')[1])))
                                         OR (lf.type = 'range' AND any(v IN apoc.any.property(a, 'f_' + r.field) WHERE
                                               (NOT v CONTAINS '..' AND lf.from <= v AND v <= lf.to)
                                               OR (v CONTAINS '..' AND split(v,'..')[0] <= lf.to AND lf.from <= split(v,'..')[1]))))
                                   ELSE false END
                               ELSE
                                 (child.type = 'value' AND (child.value IN apoc.any.property(a, 'f_' + r.field)
                                       OR any(rg IN apoc.any.property(a, 'f_' + r.field) WHERE rg CONTAINS '..' AND split(rg,'..')[0] <= child.value AND child.value <= split(rg,'..')[1])))
                                 OR (child.type = 'range' AND any(v IN apoc.any.property(a, 'f_' + r.field) WHERE
                                       (NOT v CONTAINS '..' AND child.from <= v AND v <= child.to)
                                       OR (v CONTAINS '..' AND split(v,'..')[0] <= child.to AND child.from <= split(v,'..')[1])))
                               END)
                             WHEN 'OR' THEN any(child IN $orgFilters[r.field].children WHERE
                               CASE WHEN child.type = 'group' THEN
                                 CASE child.op
                                   WHEN 'AND' THEN all(lf IN child.children WHERE
                                         (lf.type = 'value' AND (lf.value IN apoc.any.property(a, 'f_' + r.field)
                                               OR any(rg IN apoc.any.property(a, 'f_' + r.field) WHERE rg CONTAINS '..' AND split(rg,'..')[0] <= lf.value AND lf.value <= split(rg,'..')[1])))
                                         OR (lf.type = 'range' AND any(v IN apoc.any.property(a, 'f_' + r.field) WHERE
                                               (NOT v CONTAINS '..' AND lf.from <= v AND v <= lf.to)
                                               OR (v CONTAINS '..' AND split(v,'..')[0] <= lf.to AND lf.from <= split(v,'..')[1]))))
                                   WHEN 'OR' THEN any(lf IN child.children WHERE
                                         (lf.type = 'value' AND (lf.value IN apoc.any.property(a, 'f_' + r.field)
                                               OR any(rg IN apoc.any.property(a, 'f_' + r.field) WHERE rg CONTAINS '..' AND split(rg,'..')[0] <= lf.value AND lf.value <= split(rg,'..')[1])))
                                         OR (lf.type = 'range' AND any(v IN apoc.any.property(a, 'f_' + r.field) WHERE
                                               (NOT v CONTAINS '..' AND lf.from <= v AND v <= lf.to)
                                               OR (v CONTAINS '..' AND split(v,'..')[0] <= lf.to AND lf.from <= split(v,'..')[1]))))
                                   ELSE false END
                               ELSE
                                 (child.type = 'value' AND (child.value IN apoc.any.property(a, 'f_' + r.field)
                                       OR any(rg IN apoc.any.property(a, 'f_' + r.field) WHERE rg CONTAINS '..' AND split(rg,'..')[0] <= child.value AND child.value <= split(rg,'..')[1])))
                                 OR (child.type = 'range' AND any(v IN apoc.any.property(a, 'f_' + r.field) WHERE
                                       (NOT v CONTAINS '..' AND child.from <= v AND v <= child.to)
                                       OR (v CONTAINS '..' AND split(v,'..')[0] <= child.to AND child.from <= split(v,'..')[1])))
                               END)
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
