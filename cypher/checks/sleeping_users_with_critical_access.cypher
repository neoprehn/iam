// Konsistenzcheck (Katalog B6): Sleeping-User (kein Logon seit 180 Tagen oder nie, s.
// sleeping_users.cypher) mit weiterhin hochkritischen Berechtigungen -- eigener Blickwinkel
// unabhaengig von SoD: vorrangiger Entzugskandidat. Schwelle als Literal wie in
// dormant_active_dialog_users.cypher (kein optionaler Parameter moeglich). Wiederverwendet
// dieselbe Kritisch-Definition wie A1/A2/A3 (SAP_ALL/SAP_NEW/kritische Standardprofile).
// Parameter: $dataset, $asOf.
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/sleeping_users_with_critical_access.cypher

// --- 1) Zusammenfassung: Anzahl sleepender User je kritischem Befund (-> KPI-Kacheln UI) ---
WITH 180 AS sleepDays, ['SAP_ALL', 'SAP_NEW', 'S_A.SYSTEM', 'S_A.ADMIN', 'S_A.DEVELOP'] AS criticalProfiles
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
WITH profileId, u, sleepDays
WHERE u.lastLogon IS NULL OR u.lastLogon < ($asOf - duration({days: sleepDays}))
RETURN profileId AS befund, count(DISTINCT u) AS anzahl
ORDER BY anzahl DESC;

// --- 2) Detailliste ---
WITH 180 AS sleepDays, ['SAP_ALL', 'SAP_NEW', 'S_A.SYSTEM', 'S_A.ADMIN', 'S_A.DEVELOP'] AS criticalProfiles
UNWIND criticalProfiles AS profileId
CALL {
  WITH profileId
  MATCH (u:User {dataset:$dataset})-[:HAS_PROFILE]->(:Profile {dataset:$dataset, id:profileId})
  RETURN u, profileId AS befund
  UNION
  WITH profileId
  MATCH (u:User {dataset:$dataset})-[a:ASSIGNED_TO]->(:Role)-[:HAS_PROFILE]->(:Profile {dataset:$dataset, id:profileId})
  WHERE (a.validFrom IS NULL OR a.validFrom <= $asOf) AND (a.validTo IS NULL OR $asOf <= a.validTo)
  RETURN u, profileId AS befund
}
WITH u, befund, sleepDays
WHERE u.lastLogon IS NULL OR u.lastLogon < ($asOf - duration({days: sleepDays}))
WITH u, collect(DISTINCT befund) AS befunde
RETURN u.id AS user, coalesce(u.name, '') AS name,
       CASE WHEN 'Locked' IN labels(u) THEN 'gesperrt' ELSE 'aktiv' END AS status,
       u.lastLogon AS letzterLogon, befunde
ORDER BY user;
