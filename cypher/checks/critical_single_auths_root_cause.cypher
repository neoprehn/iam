// Root-Cause-Drilldown fuer Katalog A4 (critical_single_auths.cypher): zeigt fuer einen
// konkreten User, welche Rolle(n)/Profil(e) mit welcher konkreten Authorization (Feldwerte)
// jeden Befund tatsaechlich ausloesen -- analog zum SoD-Root-Cause (GET /root-cause), aber fuer
// die vier Ad-hoc-Kriterien dieses Konsistenzchecks statt eines Ruleset-Query. Eigene Datei
// (nicht als drittes Statement in critical_single_auths.cypher), damit der normale Run
// (POST /consistency-checks/A4/run, ohne $user) unveraendert nur zwei Statements ausfuehrt.
// Kriterien 1:1 wie in critical_single_auths.cypher -- bei Aenderung dort auch hier nachziehen.
// Parameter: $dataset, $asOf, $user.
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -P "user=>'MUSTERM'" -f /cypher/checks/critical_single_auths_root_cause.cypher

CALL {
  MATCH (u:User {dataset:$dataset, id:$user})-[asg:ASSIGNED_TO|HAS_PROFILE]->(traeger)-[:CONTAINS|HAS_PROFILE*0..4]->(akteur)-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:'S_DEVELOP'})
  WHERE (type(asg) = 'HAS_PROFILE' OR ((asg.validFrom IS NULL OR asg.validFrom <= $asOf) AND (asg.validTo IS NULL OR $asOf <= asg.validTo)))
    AND apoc.any.property(a, 'f_ACTVT') IS NOT NULL
    AND '02' IN apoc.any.property(a, 'f_ACTVT') AND '03' IN apoc.any.property(a, 'f_ACTVT')
    AND apoc.any.property(a, 'f_OBJTYPE') IS NOT NULL AND 'DEBUG' IN apoc.any.property(a, 'f_OBJTYPE')
  RETURN 'Debug-Replace (S_DEVELOP)' AS befund, a.object AS objekt,
         CASE WHEN 'Role' IN labels(akteur) THEN 'Role' ELSE 'Profile' END AS akteurTyp,
         akteur.id AS akteurId,
         apoc.map.fromPairs([k IN keys(a) WHERE k STARTS WITH 'f_' | [substring(k,2), a[k]]]) AS felder
  UNION
  MATCH (u:User {dataset:$dataset, id:$user})-[asg:ASSIGNED_TO|HAS_PROFILE]->(traeger)-[:CONTAINS|HAS_PROFILE*0..4]->(akteur)-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:'S_TABU_DIS'})
  WHERE (type(asg) = 'HAS_PROFILE' OR ((asg.validFrom IS NULL OR asg.validFrom <= $asOf) AND (asg.validTo IS NULL OR $asOf <= asg.validTo)))
    AND apoc.any.property(a, 'f_ACTVT') IS NOT NULL AND '02' IN apoc.any.property(a, 'f_ACTVT')
    AND apoc.any.property(a, 'f_DICBERCLS') IS NOT NULL
    AND any(v IN ['*', '$'] WHERE v IN apoc.any.property(a, 'f_DICBERCLS'))
  RETURN 'Breiter Tabellenzugriff, aendern (S_TABU_DIS)' AS befund, a.object AS objekt,
         CASE WHEN 'Role' IN labels(akteur) THEN 'Role' ELSE 'Profile' END AS akteurTyp,
         akteur.id AS akteurId,
         apoc.map.fromPairs([k IN keys(a) WHERE k STARTS WITH 'f_' | [substring(k,2), a[k]]]) AS felder
  UNION
  MATCH (u:User {dataset:$dataset, id:$user})-[asg:ASSIGNED_TO|HAS_PROFILE]->(traeger)-[:CONTAINS|HAS_PROFILE*0..4]->(akteur)-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:'S_TABU_NAM'})
  WHERE (type(asg) = 'HAS_PROFILE' OR ((asg.validFrom IS NULL OR asg.validFrom <= $asOf) AND (asg.validTo IS NULL OR $asOf <= asg.validTo)))
    AND apoc.any.property(a, 'f_ACTVT') IS NOT NULL AND '02' IN apoc.any.property(a, 'f_ACTVT')
    AND apoc.any.property(a, 'f_TABLE') IS NOT NULL AND '*' IN apoc.any.property(a, 'f_TABLE')
  RETURN 'Breiter Tabellenzugriff, aendern (S_TABU_NAM)' AS befund, a.object AS objekt,
         CASE WHEN 'Role' IN labels(akteur) THEN 'Role' ELSE 'Profile' END AS akteurTyp,
         akteur.id AS akteurId,
         apoc.map.fromPairs([k IN keys(a) WHERE k STARTS WITH 'f_' | [substring(k,2), a[k]]]) AS felder
  UNION
  MATCH (u:User {dataset:$dataset, id:$user})-[asg:ASSIGNED_TO|HAS_PROFILE]->(traeger)-[:CONTAINS|HAS_PROFILE*0..4]->(akteur)-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:'S_USER_GRP'})
  WHERE type(asg) = 'HAS_PROFILE' OR ((asg.validFrom IS NULL OR asg.validFrom <= $asOf) AND (asg.validTo IS NULL OR $asOf <= asg.validTo))
  RETURN 'Benutzergruppen-Verwaltung (S_USER_GRP)' AS befund, a.object AS objekt,
         CASE WHEN 'Role' IN labels(akteur) THEN 'Role' ELSE 'Profile' END AS akteurTyp,
         akteur.id AS akteurId,
         apoc.map.fromPairs([k IN keys(a) WHERE k STARTS WITH 'f_' | [substring(k,2), a[k]]]) AS felder
}
RETURN befund, objekt, akteurTyp, akteurId, felder
ORDER BY befund, akteurTyp, akteurId;
