// Einzelberechtigungs-Check (Katalog A4): kritische Einzelberechtigungen unterhalb der
// Profilebene -- gezielte Hochrisiko-Objekte/-Aktivitaeten statt eines ganzen Profils.
// Drei Definitionen (erweiterbar: neuen UNION-Block nach demselben Muster ergaenzen):
//   - Debug-Replace: S_DEVELOP, ACTVT enthaelt 02 UND 03 (andLogic), UND OBJTYPE enthaelt DEBUG,
//     auf derselben Authorization (AE-03) -- Werte 1:1 aus rules/KPMG_R3/queries.json,
//     Query 1000_BC-SEC ("Replace in Debugging"). Erlaubt Laufzeit-Manipulation im Debugger.
//   - Breiter Tabellenzugriff (aendern): S_TABU_DIS mit ACTVT enthaelt 02 UND DICBERCLS enthaelt
//     '*' oder '$' (alle bzw. nicht gruppierte Tabellen, s. z. B. Query 1107_BC-DEV/1110_BC-DEV);
//     S_TABU_NAM analog ueber Feld TABLE (kein Beispiel im aktuellen Ruleset vorhanden, Feldname
//     nach SAP-Standard).
//   - Benutzergruppen-Verwaltung: S_USER_GRP -- jede Auspraegung gilt als kritisch (ermoeglicht
//     Benutzerverwaltung ueber Gruppen hinweg, s. Queries 1200-1206_BC-USR).
// Beide Zuweisungswege (direkt + ueber Rolle, stichtagsgefiltert) wie in query_match.cypher.
// Parameter: $dataset, $asOf.
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/critical_single_auths.cypher

// --- 1) Zusammenfassung: Anzahl betroffener User je Befund (-> KPI-Kacheln UI) ---
CALL {
  MATCH (u:User {dataset:$dataset})-[asg:ASSIGNED_TO|HAS_PROFILE]->()-[:CONTAINS|HAS_PROFILE*0..4]->()-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:'S_DEVELOP'})
  WHERE (type(asg) = 'HAS_PROFILE' OR ((asg.validFrom IS NULL OR asg.validFrom <= $asOf) AND (asg.validTo IS NULL OR $asOf <= asg.validTo)))
    AND apoc.any.property(a, 'f_ACTVT') IS NOT NULL
    AND '02' IN apoc.any.property(a, 'f_ACTVT') AND '03' IN apoc.any.property(a, 'f_ACTVT')
    AND apoc.any.property(a, 'f_OBJTYPE') IS NOT NULL AND 'DEBUG' IN apoc.any.property(a, 'f_OBJTYPE')
  RETURN u, 'Debug-Replace (S_DEVELOP)' AS befund
  UNION
  MATCH (u:User {dataset:$dataset})-[asg:ASSIGNED_TO|HAS_PROFILE]->()-[:CONTAINS|HAS_PROFILE*0..4]->()-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:'S_TABU_DIS'})
  WHERE (type(asg) = 'HAS_PROFILE' OR ((asg.validFrom IS NULL OR asg.validFrom <= $asOf) AND (asg.validTo IS NULL OR $asOf <= asg.validTo)))
    AND apoc.any.property(a, 'f_ACTVT') IS NOT NULL AND '02' IN apoc.any.property(a, 'f_ACTVT')
    AND apoc.any.property(a, 'f_DICBERCLS') IS NOT NULL
    AND any(v IN ['*', '$'] WHERE v IN apoc.any.property(a, 'f_DICBERCLS'))
  RETURN u, 'Breiter Tabellenzugriff, aendern (S_TABU_DIS)' AS befund
  UNION
  MATCH (u:User {dataset:$dataset})-[asg:ASSIGNED_TO|HAS_PROFILE]->()-[:CONTAINS|HAS_PROFILE*0..4]->()-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:'S_TABU_NAM'})
  WHERE (type(asg) = 'HAS_PROFILE' OR ((asg.validFrom IS NULL OR asg.validFrom <= $asOf) AND (asg.validTo IS NULL OR $asOf <= asg.validTo)))
    AND apoc.any.property(a, 'f_ACTVT') IS NOT NULL AND '02' IN apoc.any.property(a, 'f_ACTVT')
    AND apoc.any.property(a, 'f_TABLE') IS NOT NULL AND '*' IN apoc.any.property(a, 'f_TABLE')
  RETURN u, 'Breiter Tabellenzugriff, aendern (S_TABU_NAM)' AS befund
  UNION
  MATCH (u:User {dataset:$dataset})-[asg:ASSIGNED_TO|HAS_PROFILE]->()-[:CONTAINS|HAS_PROFILE*0..4]->()-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:'S_USER_GRP'})
  WHERE type(asg) = 'HAS_PROFILE' OR ((asg.validFrom IS NULL OR asg.validFrom <= $asOf) AND (asg.validTo IS NULL OR $asOf <= asg.validTo))
  RETURN u, 'Benutzergruppen-Verwaltung (S_USER_GRP)' AS befund
}
RETURN befund, count(DISTINCT u) AS anzahl
ORDER BY anzahl DESC;

// --- 2) Detailliste ---
CALL {
  // Debug-Replace
  MATCH (u:User {dataset:$dataset})-[asg:ASSIGNED_TO|HAS_PROFILE]->()-[:CONTAINS|HAS_PROFILE*0..4]->()-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:'S_DEVELOP'})
  WHERE (type(asg) = 'HAS_PROFILE' OR ((asg.validFrom IS NULL OR asg.validFrom <= $asOf) AND (asg.validTo IS NULL OR $asOf <= asg.validTo)))
    AND apoc.any.property(a, 'f_ACTVT') IS NOT NULL
    AND '02' IN apoc.any.property(a, 'f_ACTVT') AND '03' IN apoc.any.property(a, 'f_ACTVT')
    AND apoc.any.property(a, 'f_OBJTYPE') IS NOT NULL AND 'DEBUG' IN apoc.any.property(a, 'f_OBJTYPE')
  RETURN u, 'Debug-Replace (S_DEVELOP)' AS befund
  UNION
  // Breiter Tabellenzugriff (aendern) ueber S_TABU_DIS
  MATCH (u:User {dataset:$dataset})-[asg:ASSIGNED_TO|HAS_PROFILE]->()-[:CONTAINS|HAS_PROFILE*0..4]->()-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:'S_TABU_DIS'})
  WHERE (type(asg) = 'HAS_PROFILE' OR ((asg.validFrom IS NULL OR asg.validFrom <= $asOf) AND (asg.validTo IS NULL OR $asOf <= asg.validTo)))
    AND apoc.any.property(a, 'f_ACTVT') IS NOT NULL AND '02' IN apoc.any.property(a, 'f_ACTVT')
    AND apoc.any.property(a, 'f_DICBERCLS') IS NOT NULL
    AND any(v IN ['*', '$'] WHERE v IN apoc.any.property(a, 'f_DICBERCLS'))
  RETURN u, 'Breiter Tabellenzugriff, aendern (S_TABU_DIS)' AS befund
  UNION
  // Breiter Tabellenzugriff (aendern) ueber S_TABU_NAM (Tabellenname statt -gruppe)
  MATCH (u:User {dataset:$dataset})-[asg:ASSIGNED_TO|HAS_PROFILE]->()-[:CONTAINS|HAS_PROFILE*0..4]->()-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:'S_TABU_NAM'})
  WHERE (type(asg) = 'HAS_PROFILE' OR ((asg.validFrom IS NULL OR asg.validFrom <= $asOf) AND (asg.validTo IS NULL OR $asOf <= asg.validTo)))
    AND apoc.any.property(a, 'f_ACTVT') IS NOT NULL AND '02' IN apoc.any.property(a, 'f_ACTVT')
    AND apoc.any.property(a, 'f_TABLE') IS NOT NULL AND '*' IN apoc.any.property(a, 'f_TABLE')
  RETURN u, 'Breiter Tabellenzugriff, aendern (S_TABU_NAM)' AS befund
  UNION
  // Benutzergruppen-Verwaltung -- jede Auspraegung von S_USER_GRP gilt als kritisch
  MATCH (u:User {dataset:$dataset})-[asg:ASSIGNED_TO|HAS_PROFILE]->()-[:CONTAINS|HAS_PROFILE*0..4]->()-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:'S_USER_GRP'})
  WHERE type(asg) = 'HAS_PROFILE' OR ((asg.validFrom IS NULL OR asg.validFrom <= $asOf) AND (asg.validTo IS NULL OR $asOf <= asg.validTo))
  RETURN u, 'Benutzergruppen-Verwaltung (S_USER_GRP)' AS befund
}
WITH u, collect(DISTINCT befund) AS befunde
RETURN u.id AS user, coalesce(u.name, '') AS name,
       CASE WHEN 'Dialog' IN labels(u) THEN 'Dialog'
            WHEN 'System' IN labels(u) THEN 'System'
            WHEN 'Service' IN labels(u) THEN 'Service'
            WHEN 'Communication' IN labels(u) THEN 'Communication'
            WHEN 'Reference' IN labels(u) THEN 'Reference' ELSE '?' END AS typ,
       CASE WHEN 'Locked' IN labels(u) THEN 'gesperrt' ELSE 'aktiv' END AS status,
       befunde
ORDER BY CASE WHEN 'Dialog' IN labels(u) AND NOT 'Locked' IN labels(u) THEN 0 ELSE 1 END,
         typ, status, user;
