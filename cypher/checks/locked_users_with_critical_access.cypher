// Konsistenzcheck (Katalog B4): gesperrte User, die weiterhin kritische Rollen/Profile/
// Einzelberechtigungen tragen -- die Sperre verdeckt das Risiko nur, eine Entsperrung wuerde es
// sofort wieder freischalten. Wiederverwendet dieselbe Kritisch-Definition wie A1-A4
// (SAP_ALL/SAP_NEW/kritische Standardprofile via HAS_PROFILE, kritische Einzelauths via
// HAS_AUTH) -- s. dortige Begruendung zu Literal-Listen statt Parameter.
// Beide Zuweisungswege (direkt + ueber Rolle, stichtagsgefiltert) wie in den A-Checks.
// $lockReason filtert nach Sperrgrund (u.lockReasons, gesetzt in load/01_users.cypher aus dem
// UFLAG-Bitfeld): 'alle' (Default) / 'failed_logons' / 'admin_local' / 'admin_global' --
// Pill-Buttons in der UI ueber checks/B.json "params" (s. checks/SCHEMA.md).
// Parameter: $dataset, $asOf, $lockReason.
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -P "lockReason=>'alle'" -f /cypher/checks/locked_users_with_critical_access.cypher

// --- 1) Zusammenfassung: Anzahl gesperrter User je Befund (-> KPI-Kacheln UI) ---
CALL {
  WITH ['SAP_ALL', 'SAP_NEW', 'S_A.SYSTEM', 'S_A.ADMIN', 'S_A.DEVELOP'] AS criticalProfiles
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
  RETURN u, befund
  UNION
  MATCH (u:User {dataset:$dataset})-[asg:ASSIGNED_TO|HAS_PROFILE]->()-[:CONTAINS|HAS_PROFILE*0..4]->()-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:'S_DEVELOP'})
  WHERE (type(asg) = 'HAS_PROFILE' OR ((asg.validFrom IS NULL OR asg.validFrom <= $asOf) AND (asg.validTo IS NULL OR $asOf <= asg.validTo)))
    AND apoc.any.property(a, 'f_ACTVT') IS NOT NULL
    AND '02' IN apoc.any.property(a, 'f_ACTVT') AND '03' IN apoc.any.property(a, 'f_ACTVT')
    AND apoc.any.property(a, 'f_OBJTYPE') IS NOT NULL AND 'DEBUG' IN apoc.any.property(a, 'f_OBJTYPE')
  RETURN u, 'Debug-Replace (S_DEVELOP)' AS befund
  UNION
  MATCH (u:User {dataset:$dataset})-[asg:ASSIGNED_TO|HAS_PROFILE]->()-[:CONTAINS|HAS_PROFILE*0..4]->()-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:'S_USER_GRP'})
  WHERE type(asg) = 'HAS_PROFILE' OR ((asg.validFrom IS NULL OR asg.validFrom <= $asOf) AND (asg.validTo IS NULL OR $asOf <= asg.validTo))
  RETURN u, 'Benutzergruppen-Verwaltung (S_USER_GRP)' AS befund
}
WITH u, befund
WHERE 'Locked' IN labels(u) AND ($lockReason = 'alle' OR $lockReason IN coalesce(u.lockReasons, []))
RETURN befund, count(DISTINCT u) AS anzahl
ORDER BY anzahl DESC;

// --- 2) Detailliste ---
CALL {
  WITH ['SAP_ALL', 'SAP_NEW', 'S_A.SYSTEM', 'S_A.ADMIN', 'S_A.DEVELOP'] AS criticalProfiles
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
  RETURN u, befund
  UNION
  MATCH (u:User {dataset:$dataset})-[asg:ASSIGNED_TO|HAS_PROFILE]->()-[:CONTAINS|HAS_PROFILE*0..4]->()-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:'S_DEVELOP'})
  WHERE (type(asg) = 'HAS_PROFILE' OR ((asg.validFrom IS NULL OR asg.validFrom <= $asOf) AND (asg.validTo IS NULL OR $asOf <= asg.validTo)))
    AND apoc.any.property(a, 'f_ACTVT') IS NOT NULL
    AND '02' IN apoc.any.property(a, 'f_ACTVT') AND '03' IN apoc.any.property(a, 'f_ACTVT')
    AND apoc.any.property(a, 'f_OBJTYPE') IS NOT NULL AND 'DEBUG' IN apoc.any.property(a, 'f_OBJTYPE')
  RETURN u, 'Debug-Replace (S_DEVELOP)' AS befund
  UNION
  MATCH (u:User {dataset:$dataset})-[asg:ASSIGNED_TO|HAS_PROFILE]->()-[:CONTAINS|HAS_PROFILE*0..4]->()-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:'S_USER_GRP'})
  WHERE type(asg) = 'HAS_PROFILE' OR ((asg.validFrom IS NULL OR asg.validFrom <= $asOf) AND (asg.validTo IS NULL OR $asOf <= asg.validTo))
  RETURN u, 'Benutzergruppen-Verwaltung (S_USER_GRP)' AS befund
}
WITH u, befund
WHERE 'Locked' IN labels(u) AND ($lockReason = 'alle' OR $lockReason IN coalesce(u.lockReasons, []))
WITH u, collect(DISTINCT befund) AS befunde
RETURN u.id AS user, coalesce(u.name, '') AS name, befunde, u.lockReasons AS sperrgruende
ORDER BY user;
