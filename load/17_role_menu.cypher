// 17 — AGR_TCODES -> (:Role)-[:HAS_MENU]->(:Transaction). Rollenmenü (informativ; die echte
// TCode-Berechtigung läuft über S_TCODE in AGR_1251). Ausschlüsse (EXCLUDE='X') und
// Ordner-Einträge (leerer TCODE) werden übersprungen. Parameter: $dataset
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM $url AS row FIELDTERMINATOR '\t' RETURN row",
  "WITH row WHERE coalesce(row.AGR_NAME,'') <> '' AND coalesce(row.TCODE,'') <> '' AND coalesce(row.EXCLUDE,'') <> 'X'
   MERGE (r:Role {key: $dataset + '|' + row.AGR_NAME}) ON CREATE SET r.dataset=$dataset, r.id=row.AGR_NAME
   MERGE (t:Transaction {key: $dataset + '|' + row.TCODE}) ON CREATE SET t.dataset=$dataset, t.id=row.TCODE
   MERGE (r)-[:HAS_MENU]->(t)",
  {batchSize:10000, parallel:false, params:{url:'file:///'+$dataset+'/agr_tcodes.csv', dataset:$dataset}}
);
