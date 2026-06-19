// Bereinigt EIN Dataset (Mandant/Stand): alle dataset-skopierten Knoten inkl. dessen
// Runs/Findings/Matches (Run, SoDConflict, OrgField, User/Role/Profile/Authorization/...
// tragen alle ein dataset-Property; die MATCHES-Kanten haengen an den User-Knoten und gehen
// beim DETACH DELETE mit). Die KONSTANTE Ruleset-Schicht (Query/SoDRule/AuthReq/Clause hat
// KEIN dataset) und das Schema (Constraints/Indizes) bleiben unberuehrt.
// Parameter: $dataset. Gebatcht ueber apoc.periodic.iterate (grosse Mengen, eine Tx je Batch).
CALL apoc.periodic.iterate(
  "MATCH (n {dataset:$dataset}) RETURN n",
  "DETACH DELETE n",
  {batchSize:10000, parallel:false, params:{dataset:$dataset}}
);

// Registry-Knoten des Datasets (hat id statt dataset) separat entfernen.
MATCH (d:Dataset {id:$dataset}) DETACH DELETE d;
