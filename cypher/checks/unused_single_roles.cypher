// Konsistenzcheck (Katalog C4): Einzelrolle (Single) ohne jede Verwendung -- weder in einer
// Sammelrolle enthalten (keine eingehende CONTAINS-Kante) noch direkt einem User zugewiesen
// (keine eingehende ASSIGNED_TO-Kante, unabhaengig von Gueltigkeit). Ungenutzte Rolle ->
// Aufraeumkandidat, reduziert Komplexitaet/Angriffsflaeche im Rollenbestand.
// Parameter: $dataset, $asOf (asOf ungenutzt, einheitliche Signatur).
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/unused_single_roles.cypher

// --- 1) Zusammenfassung (-> KPI-Kacheln UI) ---
MATCH (r:Role:Single {dataset:$dataset})
WHERE NOT EXISTS { (:Role)-[:CONTAINS]->(r) } AND NOT EXISTS { (:User)-[:ASSIGNED_TO]->(r) }
RETURN count(r) AS anzahl;

// --- 2) Detailliste ---
MATCH (r:Role:Single {dataset:$dataset})
WHERE NOT EXISTS { (:Role)-[:CONTAINS]->(r) } AND NOT EXISTS { (:User)-[:ASSIGNED_TO]->(r) }
RETURN r.id AS rolle, coalesce(r.text, '') AS text,
       EXISTS { (r)-[:HAS_AUTH]->(:Authorization) } AS hatBerechtigungen,
       EXISTS { (r)-[:HAS_PROFILE]->(:Profile) } AS hatGeneriertesProfil
ORDER BY rolle;
