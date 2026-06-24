// Konsistenzcheck (Katalog B7): generische/kundeneigene Sammel-User (Namensmuster wie
// TEST*/ADMIN*/SCHULUNG*/DEMO*, abseits der bekannten SAP-Defaults aus B2) mit weiterhin
// produktiven Berechtigungen (mind. eine Rollenzuweisung oder ein direktes Profil) -- ohne
// 1:1-Personenbezug ein Mitbestimmungs-/Nachweisrisiko. Musterliste als Literal gepflegt
// (kein optionaler Parameter -- s. Begruendung in critical_profiles.cypher), bewusst
// erweiterbar je Mandant (Namenskonventionen unterscheiden sich).
// Parameter: $dataset, $asOf.
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/generic_users_with_access.cypher

// --- 1) Zusammenfassung: Anzahl betroffener User je Muster (-> KPI-Kacheln UI) ---
WITH ['TEST*', 'ADMIN*', 'SCHULUNG*', 'TRAINING*', 'DEMO*', 'MUSTER*'] AS genericPatterns
UNWIND genericPatterns AS pattern
MATCH (u:User {dataset:$dataset})
WHERE u.id STARTS WITH left(pattern, size(pattern)-1)
  AND (EXISTS { (u)-[:ASSIGNED_TO]->(:Role) } OR EXISTS { (u)-[:HAS_PROFILE]->(:Profile) })
RETURN pattern AS muster, count(DISTINCT u) AS anzahl
ORDER BY anzahl DESC;

// --- 2) Detailliste ---
WITH ['TEST*', 'ADMIN*', 'SCHULUNG*', 'TRAINING*', 'DEMO*', 'MUSTER*'] AS genericPatterns
UNWIND genericPatterns AS pattern
MATCH (u:User {dataset:$dataset})
WHERE u.id STARTS WITH left(pattern, size(pattern)-1)
  AND (EXISTS { (u)-[:ASSIGNED_TO]->(:Role) } OR EXISTS { (u)-[:HAS_PROFILE]->(:Profile) })
WITH u, collect(DISTINCT pattern) AS muster
RETURN u.id AS user, coalesce(u.name, '') AS name, muster,
       CASE WHEN 'Locked' IN labels(u) THEN 'gesperrt' ELSE 'aktiv' END AS status
ORDER BY user;
