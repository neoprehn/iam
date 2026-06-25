// Graph-Rohdaten zum Konsistenzcheck A3 (kritische SAP-Standardprofile ausser SAP_ALL/SAP_NEW)
// -- analog sap_all_graph.cypher, Begruendung dort. Profilliste 1:1 aus critical_profiles.cypher
// gespiegelt (bei Aenderung dort auch hier nachziehen). Parameter: $dataset, $asOf.
WITH ['S_A.SYSTEM', 'S_A.ADMIN', 'S_A.DEVELOP'] AS criticalProfiles
UNWIND criticalProfiles AS profileId
CALL {
  WITH profileId
  MATCH (u:User {dataset:$dataset})-[:HAS_PROFILE]->(p:Profile {dataset:$dataset, id:profileId})
  RETURN u, null AS r, p, 'direkt' AS pfad
  UNION
  WITH profileId
  MATCH (u:User {dataset:$dataset})-[a:ASSIGNED_TO]->(r:Role)-[:HAS_PROFILE]->(p:Profile {dataset:$dataset, id:profileId})
  WHERE (a.validFrom IS NULL OR a.validFrom <= $asOf) AND (a.validTo IS NULL OR $asOf <= a.validTo)
  RETURN u, r, p, 'ueber Rolle' AS pfad
}
RETURN u.id AS user,
       CASE WHEN 'Dialog' IN labels(u) THEN 'Dialog'
            WHEN 'System' IN labels(u) THEN 'System'
            WHEN 'Communication' IN labels(u) THEN 'Communication'
            WHEN 'Service' IN labels(u) THEN 'Service'
            WHEN 'Reference' IN labels(u) THEN 'Reference' ELSE '?' END AS userType,
       CASE WHEN 'Locked' IN labels(u) THEN 'gesperrt' ELSE 'aktiv' END AS userStatus,
       pfad AS pathType, r.id AS role, p.id AS profile
ORDER BY user, profile;
