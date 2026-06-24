// Einzelberechtigungs-Check (Katalog A6): Org-Ebenen-Wildcard (z. B. BUKRS=*) auf denselben
// sensiblen Objekten wie A4 (Debug-Replace S_DEVELOP, breiter Tabellenzugriff S_TABU_DIS/
// S_TABU_NAM, Benutzergruppen-Verwaltung S_USER_GRP) -- Festlegung: dieselbe Liste wie A4,
// s. KONSISTENZCHECKS.md A6.
// Hinweis: diese vier Objekte sind klassische mandantenweite Basis-Objekte ohne Org-Ebenen-Feld
// (BUKRS/WERKS/...) -- der Check liefert daher in der Praxis oft 0 Treffer; er ist trotzdem
// korrekt nach der getroffenen Festlegung und greift, sobald eines der Objekte (oder eine
// Erweiterung der Liste) tatsaechlich ein Org-Feld fuehrt.
// '*' deckt nach AE-06 auch Vollbereich/nicht gepflegtes Org-Level ab; hier wird nur das
// literale '*' geprueft (LOW/HIGH-Bereichsfelder sind bei diesen vier Objekten nicht ueblich).
// Liste ist als Literal gepflegt (kein optionaler Parameter -- s. Begruendung in
// critical_profiles.cypher, Neo4j verlangt sonst einen gebundenen Wert je referenzierte
// $-Variable, auch innerhalb coalesce()).
// Parameter: $dataset, $asOf.
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/org_wildcard_critical_objects.cypher

// --- 1) Zusammenfassung: Anzahl betroffener User je Objekt (-> KPI-Kacheln UI) ---
MATCH (of:OrgField {dataset:$dataset})
WITH collect(of.field) AS orgFields
WITH orgFields, ['S_DEVELOP', 'S_TABU_DIS', 'S_TABU_NAM', 'S_USER_GRP'] AS sensitiveObjects
UNWIND sensitiveObjects AS obj
MATCH (u:User {dataset:$dataset})-[asg:ASSIGNED_TO|HAS_PROFILE]->()-[:CONTAINS|HAS_PROFILE*0..4]->()-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:obj})
WHERE type(asg) = 'HAS_PROFILE' OR ((asg.validFrom IS NULL OR asg.validFrom <= $asOf) AND (asg.validTo IS NULL OR $asOf <= asg.validTo))
WITH obj, u, [field IN orgFields WHERE apoc.any.property(a, 'f_' + field) IS NOT NULL AND '*' IN apoc.any.property(a, 'f_' + field)] AS orgTreffer
WHERE size(orgTreffer) > 0
RETURN obj AS objekt, count(DISTINCT u) AS anzahl
ORDER BY anzahl DESC;

// --- 2) Detailliste ---
MATCH (of:OrgField {dataset:$dataset})
WITH collect(of.field) AS orgFields
WITH orgFields, ['S_DEVELOP', 'S_TABU_DIS', 'S_TABU_NAM', 'S_USER_GRP'] AS sensitiveObjects
UNWIND sensitiveObjects AS obj
MATCH (u:User {dataset:$dataset})-[asg:ASSIGNED_TO|HAS_PROFILE]->()-[:CONTAINS|HAS_PROFILE*0..4]->()-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:obj})
WHERE type(asg) = 'HAS_PROFILE' OR ((asg.validFrom IS NULL OR asg.validFrom <= $asOf) AND (asg.validTo IS NULL OR $asOf <= asg.validTo))
WITH u, obj, [field IN orgFields WHERE apoc.any.property(a, 'f_' + field) IS NOT NULL AND '*' IN apoc.any.property(a, 'f_' + field)] AS orgTreffer
WHERE size(orgTreffer) > 0
WITH u, collect(DISTINCT {objekt: obj, orgFelder: orgTreffer}) AS befunde
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
