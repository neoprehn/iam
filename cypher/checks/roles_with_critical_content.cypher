// Konsistenzcheck (Katalog R16): Rollen mit kritischen Inhalten -- buendeln SAP_ALL-aequivalente
// Profile, weite S_TABU_DIS/S_TABU_NAM, Debug-Replace (S_DEVELOP ACTVT 02+03+OBJTYPE DEBUG) oder
// '*' auf kritischen Org-Ebenen bei denselben sensiblen Objekten. Wiederverwendet dieselbe
// Kritisch-Definition wie A3/A4/A6, jetzt auf Rollenebene (HAS_AUTH/HAS_PROFILE direkt an der
// Rolle, nicht ueber den User).
// Parameter: $dataset, $asOf (asOf ungenutzt, einheitliche Signatur).
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/roles_with_critical_content.cypher

// --- 1) Zusammenfassung je Befund (-> KPI-Kacheln UI) ---
CALL {
  WITH ['SAP_ALL', 'SAP_NEW', 'S_A.SYSTEM', 'S_A.ADMIN', 'S_A.DEVELOP'] AS criticalProfiles
  UNWIND criticalProfiles AS profileId
  MATCH (r:Role {dataset:$dataset})-[:HAS_PROFILE]->(:Profile {dataset:$dataset, id:profileId})
  RETURN r, profileId AS befund
  UNION
  MATCH (r:Role {dataset:$dataset})-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:'S_DEVELOP'})
  WHERE apoc.any.property(a, 'f_ACTVT') IS NOT NULL
    AND '02' IN apoc.any.property(a, 'f_ACTVT') AND '03' IN apoc.any.property(a, 'f_ACTVT')
    AND apoc.any.property(a, 'f_OBJTYPE') IS NOT NULL AND 'DEBUG' IN apoc.any.property(a, 'f_OBJTYPE')
  RETURN r, 'Debug-Replace (S_DEVELOP)' AS befund
  UNION
  MATCH (r:Role {dataset:$dataset})-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:'S_TABU_DIS'})
  WHERE apoc.any.property(a, 'f_ACTVT') IS NOT NULL AND '02' IN apoc.any.property(a, 'f_ACTVT')
    AND apoc.any.property(a, 'f_DICBERCLS') IS NOT NULL
    AND any(v IN ['*', '$'] WHERE v IN apoc.any.property(a, 'f_DICBERCLS'))
  RETURN r, 'Breiter Tabellenzugriff (S_TABU_DIS)' AS befund
  UNION
  MATCH (r:Role {dataset:$dataset})-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:'S_TABU_NAM'})
  WHERE apoc.any.property(a, 'f_ACTVT') IS NOT NULL AND '02' IN apoc.any.property(a, 'f_ACTVT')
    AND apoc.any.property(a, 'f_TABLE') IS NOT NULL AND '*' IN apoc.any.property(a, 'f_TABLE')
  RETURN r, 'Breiter Tabellenzugriff (S_TABU_NAM)' AS befund
  UNION
  WITH ['S_DEVELOP', 'S_TABU_DIS', 'S_TABU_NAM', 'S_USER_GRP'] AS sensitiveObjects
  UNWIND sensitiveObjects AS obj
  MATCH (of:OrgField {dataset:$dataset})
  WITH obj, collect(of.field) AS orgFields
  MATCH (r:Role {dataset:$dataset})-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:obj})
  WHERE any(field IN orgFields WHERE apoc.any.property(a, 'f_' + field) IS NOT NULL AND '*' IN apoc.any.property(a, 'f_' + field))
  RETURN r, ('Org-Wildcard (' + obj + ')') AS befund
}
RETURN befund, count(DISTINCT r) AS anzahl
ORDER BY anzahl DESC;

// --- 2) Detailliste ---
CALL {
  WITH ['SAP_ALL', 'SAP_NEW', 'S_A.SYSTEM', 'S_A.ADMIN', 'S_A.DEVELOP'] AS criticalProfiles
  UNWIND criticalProfiles AS profileId
  MATCH (r:Role {dataset:$dataset})-[:HAS_PROFILE]->(:Profile {dataset:$dataset, id:profileId})
  RETURN r, profileId AS befund
  UNION
  MATCH (r:Role {dataset:$dataset})-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:'S_DEVELOP'})
  WHERE apoc.any.property(a, 'f_ACTVT') IS NOT NULL
    AND '02' IN apoc.any.property(a, 'f_ACTVT') AND '03' IN apoc.any.property(a, 'f_ACTVT')
    AND apoc.any.property(a, 'f_OBJTYPE') IS NOT NULL AND 'DEBUG' IN apoc.any.property(a, 'f_OBJTYPE')
  RETURN r, 'Debug-Replace (S_DEVELOP)' AS befund
  UNION
  MATCH (r:Role {dataset:$dataset})-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:'S_TABU_DIS'})
  WHERE apoc.any.property(a, 'f_ACTVT') IS NOT NULL AND '02' IN apoc.any.property(a, 'f_ACTVT')
    AND apoc.any.property(a, 'f_DICBERCLS') IS NOT NULL
    AND any(v IN ['*', '$'] WHERE v IN apoc.any.property(a, 'f_DICBERCLS'))
  RETURN r, 'Breiter Tabellenzugriff (S_TABU_DIS)' AS befund
  UNION
  MATCH (r:Role {dataset:$dataset})-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:'S_TABU_NAM'})
  WHERE apoc.any.property(a, 'f_ACTVT') IS NOT NULL AND '02' IN apoc.any.property(a, 'f_ACTVT')
    AND apoc.any.property(a, 'f_TABLE') IS NOT NULL AND '*' IN apoc.any.property(a, 'f_TABLE')
  RETURN r, 'Breiter Tabellenzugriff (S_TABU_NAM)' AS befund
  UNION
  WITH ['S_DEVELOP', 'S_TABU_DIS', 'S_TABU_NAM', 'S_USER_GRP'] AS sensitiveObjects
  UNWIND sensitiveObjects AS obj
  MATCH (of:OrgField {dataset:$dataset})
  WITH obj, collect(of.field) AS orgFields
  MATCH (r:Role {dataset:$dataset})-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:obj})
  WHERE any(field IN orgFields WHERE apoc.any.property(a, 'f_' + field) IS NOT NULL AND '*' IN apoc.any.property(a, 'f_' + field))
  RETURN r, ('Org-Wildcard (' + obj + ')') AS befund
}
WITH r, collect(DISTINCT befund) AS befunde
RETURN r.id AS rolle, coalesce(r.text, '') AS text, befunde,
       count { (:User)-[:ASSIGNED_TO]->(r) } AS nutzerAnzahl
ORDER BY nutzerAnzahl DESC;
