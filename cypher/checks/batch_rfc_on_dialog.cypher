// Einzelberechtigungs-Check (Katalog A5): Batch-/RFC-Berechtigungsobjekte auf einem Dialog-User
// (anmeldefaehige Person) -- erkannt ueber die ENTHALTENEN Berechtigungsobjekte, nicht ueber
// Profil-/Rollennamen (Namenskonventionen sind mandantenabhaengig und nicht verlaesslich).
// Objektliste ist bewusst hier als Literal gepflegt und erweiterbar (analog zu
// critical_profiles.cypher; kein optionaler Parameter dafuer -- s. dortige Begruendung,
// Neo4j verlangt sonst einen gebundenen Wert fuer jede referenzierte $-Variable).
//
// Hinweis (Scope v1): nur die Richtung "Dialog-User mit Batch/RFC-Rechten" ist umgesetzt -- die
// Umkehrung ("technischer User mit dialogtypischen Rechten") hat kein vergleichbar trennscharfes,
// objektbasiertes Kriterium und ist bewusst nicht Teil von v1 (s. KONSISTENZCHECKS.md A5).
//
// Parameter: $dataset, $asOf.
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/batch_rfc_on_dialog.cypher

// --- 1) Zusammenfassung: Anzahl betroffener Dialog-User je Objekt (-> KPI-Kacheln UI) ---
WITH ['S_RFC', 'S_BTCH_ADM', 'S_BTCH_JOB', 'S_BTCH_NAM'] AS batchRfcObjects
UNWIND batchRfcObjects AS obj
MATCH (u:User {dataset:$dataset})
WHERE 'Dialog' IN labels(u)
  AND EXISTS {
    MATCH (u)-[asg:ASSIGNED_TO|HAS_PROFILE]->()-[:CONTAINS|HAS_PROFILE*0..4]->()-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:obj})
    WHERE type(asg) = 'HAS_PROFILE'
       OR ((asg.validFrom IS NULL OR asg.validFrom <= $asOf) AND (asg.validTo IS NULL OR $asOf <= asg.validTo))
  }
RETURN obj AS objekt, count(DISTINCT u) AS anzahl
ORDER BY anzahl DESC;

// --- 2) Detailliste ---
WITH ['S_RFC', 'S_BTCH_ADM', 'S_BTCH_JOB', 'S_BTCH_NAM'] AS batchRfcObjects
UNWIND batchRfcObjects AS obj
MATCH (u:User {dataset:$dataset})
WHERE 'Dialog' IN labels(u)
  AND EXISTS {
    MATCH (u)-[asg:ASSIGNED_TO|HAS_PROFILE]->()-[:CONTAINS|HAS_PROFILE*0..4]->()-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:obj})
    WHERE type(asg) = 'HAS_PROFILE'
       OR ((asg.validFrom IS NULL OR asg.validFrom <= $asOf) AND (asg.validTo IS NULL OR $asOf <= asg.validTo))
  }
WITH u, collect(DISTINCT obj) AS objekte
RETURN u.id AS user, coalesce(u.name, '') AS name,
       CASE WHEN 'Locked' IN labels(u) THEN 'gesperrt' ELSE 'aktiv' END AS status,
       objekte
ORDER BY status, user;
