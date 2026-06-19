// Einzelberechtigungs-Check: Wer hat SAP_ALL?
// Erfasst beide Zuweisungswege:
//   - direkt (UST04 -> HAS_PROFILE, User -> Profile)
//   - ueber Rolle (ASSIGNED_TO -> HAS_PROFILE), stichtagsgefiltert auf $asOf;
//     offene Gueltigkeiten (validFrom/validTo = null) gelten als unbegrenzt (AE-07/08).
// Parameter: $dataset, $asOf (Neo4j-date, z. B. date()).
// Aufruf:
//   ... cypher-shell -P "dataset => 'acme'" -P "asOf => date()" -f /cypher/checks/sap_all.cypher
//
// Risikofokus: aktive Dialog-User mit SAP_ALL (anmeldefaehige Personen mit Vollzugriff).

// --- 1) Aufschluesselung nach Benutzertyp + Aktiv/Gesperrt ---
CALL {
  MATCH (u:User {dataset:$dataset})-[:HAS_PROFILE]->(:Profile {dataset:$dataset, id:'SAP_ALL'})
  RETURN u
  UNION
  MATCH (u:User {dataset:$dataset})-[a:ASSIGNED_TO]->(:Role)-[:HAS_PROFILE]->(:Profile {dataset:$dataset, id:'SAP_ALL'})
  WHERE (a.validFrom IS NULL OR a.validFrom <= $asOf) AND (a.validTo IS NULL OR $asOf <= a.validTo)
  RETURN u
}
WITH DISTINCT u
RETURN [l IN labels(u) WHERE l <> 'User'] AS typ_status, count(*) AS anzahl
ORDER BY anzahl DESC;

// --- 2) Detailliste (aktive Dialog-User zuerst = hoechstes Risiko) ---
CALL {
  MATCH (u:User {dataset:$dataset})-[:HAS_PROFILE]->(:Profile {dataset:$dataset, id:'SAP_ALL'})
  RETURN u, 'direkt' AS pfad
  UNION
  MATCH (u:User {dataset:$dataset})-[a:ASSIGNED_TO]->(:Role)-[:HAS_PROFILE]->(:Profile {dataset:$dataset, id:'SAP_ALL'})
  WHERE (a.validFrom IS NULL OR a.validFrom <= $asOf) AND (a.validTo IS NULL OR $asOf <= a.validTo)
  RETURN u, 'ueber Rolle' AS pfad
}
WITH u, collect(DISTINCT pfad) AS pfade
RETURN u.id AS user, coalesce(u.name, '') AS name,
       CASE WHEN 'Dialog' IN labels(u) THEN 'Dialog'
            WHEN 'System' IN labels(u) THEN 'System'
            WHEN 'Communication' IN labels(u) THEN 'Communication'
            WHEN 'Service' IN labels(u) THEN 'Service'
            WHEN 'Reference' IN labels(u) THEN 'Reference' ELSE '?' END AS typ,
       CASE WHEN 'Locked' IN labels(u) THEN 'gesperrt' ELSE 'aktiv' END AS status,
       pfade
ORDER BY CASE WHEN 'Dialog' IN labels(u) AND NOT 'Locked' IN labels(u) THEN 0 ELSE 1 END,
         typ, status, user;
