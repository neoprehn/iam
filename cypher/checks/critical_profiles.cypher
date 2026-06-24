// Einzelberechtigungs-Check (Katalog A3): kritische SAP-Standardprofile ausser SAP_ALL/SAP_NEW
// (die haben eigene Checks -- cypher/checks/sap_all.cypher, sap_new.cypher).
// Liste ist bewusst hier als Literal gepflegt (kein Overlay-Mechanismus fuer Konsistenzchecks
// in v1, s. checks/SCHEMA.md) -- SAP ergaenzt regelmaessig neue Auslieferungsprofile, bei Bedarf
// hier direkt erweitern. Kein Parameter dafuer: Neo4j verlangt fuer JEDE im Statement referenzierte
// $-Variable einen gebundenen Wert (auch innerhalb coalesce()) -- der generische Run-Endpoint
// (POST /consistency-checks/{id}/run) uebergibt nur $dataset/$asOf, ein optionaler Parameter
// wuerde die Ausfuehrung also immer mit "Expected parameter(s)" abbrechen.
// Erfasst beide Zuweisungswege (direkt + ueber Rolle, stichtagsgefiltert) wie sap_all.cypher.
// Parameter: $dataset, $asOf.
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/critical_profiles.cypher

// --- 1) Zusammenfassung: Anzahl betroffener User je kritischem Profil (-> KPI-Kacheln UI) ---
WITH ['S_A.SYSTEM', 'S_A.ADMIN', 'S_A.DEVELOP'] AS criticalProfiles
UNWIND criticalProfiles AS profileId
CALL {
  WITH profileId
  MATCH (u:User {dataset:$dataset})-[:HAS_PROFILE]->(:Profile {dataset:$dataset, id:profileId})
  RETURN u
  UNION
  WITH profileId
  MATCH (u:User {dataset:$dataset})-[a:ASSIGNED_TO]->(:Role)-[:HAS_PROFILE]->(:Profile {dataset:$dataset, id:profileId})
  WHERE (a.validFrom IS NULL OR a.validFrom <= $asOf) AND (a.validTo IS NULL OR $asOf <= a.validTo)
  RETURN u
}
RETURN profileId AS profil, count(DISTINCT u) AS anzahl
ORDER BY anzahl DESC;

// --- 2) Detailliste ---
WITH ['S_A.SYSTEM', 'S_A.ADMIN', 'S_A.DEVELOP'] AS criticalProfiles
UNWIND criticalProfiles AS profileId
CALL {
  WITH profileId
  MATCH (u:User {dataset:$dataset})-[:HAS_PROFILE]->(:Profile {dataset:$dataset, id:profileId})
  RETURN u, profileId AS profil
  UNION
  WITH profileId
  MATCH (u:User {dataset:$dataset})-[a:ASSIGNED_TO]->(:Role)-[:HAS_PROFILE]->(:Profile {dataset:$dataset, id:profileId})
  WHERE (a.validFrom IS NULL OR a.validFrom <= $asOf) AND (a.validTo IS NULL OR $asOf <= a.validTo)
  RETURN u, profileId AS profil
}
WITH u, collect(DISTINCT profil) AS profile
RETURN u.id AS user, coalesce(u.name, '') AS name,
       CASE WHEN 'Dialog' IN labels(u) THEN 'Dialog'
            WHEN 'System' IN labels(u) THEN 'System'
            WHEN 'Service' IN labels(u) THEN 'Service'
            WHEN 'Communication' IN labels(u) THEN 'Communication'
            WHEN 'Reference' IN labels(u) THEN 'Reference' ELSE '?' END AS typ,
       CASE WHEN 'Locked' IN labels(u) THEN 'gesperrt' ELSE 'aktiv' END AS status,
       profile
ORDER BY CASE WHEN 'Dialog' IN labels(u) AND NOT 'Locked' IN labels(u) THEN 0 ELSE 1 END,
         typ, status, user;
