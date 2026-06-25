// Graph-Rohdaten zum Konsistenzcheck A1 (SAP_ALL) -- Pilot fuer die Tabelle/Graph-Umschaltung
// in der Konsistenzcheck-UI (ROADMAP.md, Phase 9 "Umschalter Tabelle/Graph"). Gleiche Kriterien
// wie sap_all.cypher, aber als User-(-> Rolle ->)-> Profile-Pfad statt aggregierter Liste --
// das Backend baut daraus Cytoscape-Knoten/Kanten (POST /consistency-checks/{id}/graph).
// Parameter: $dataset, $asOf.
CALL {
  MATCH (u:User {dataset:$dataset})-[:HAS_PROFILE]->(p:Profile {dataset:$dataset, id:'SAP_ALL'})
  RETURN u, null AS r, p, 'direkt' AS pfad
  UNION
  MATCH (u:User {dataset:$dataset})-[a:ASSIGNED_TO]->(r:Role)-[:HAS_PROFILE]->(p:Profile {dataset:$dataset, id:'SAP_ALL'})
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
ORDER BY user;
