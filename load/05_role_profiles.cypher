// 05 — AGR_PROF -> :Profile + HAS_PROFILE (Role->Profile). Parameter: $dataset
// Quelldatei heißt arg_prof.csv (SE16-Tabellenname war ARG_PROF).
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM $url AS row FIELDTERMINATOR '\t' RETURN row",
  "WITH row WHERE coalesce(row.AGR_NAME,'') <> '' AND coalesce(row.PROFILE,'') <> ''
   MERGE (p:Profile {key: $dataset + '|' + row.PROFILE}) ON CREATE SET p.dataset=$dataset, p.id=row.PROFILE
   SET p.text = coalesce(row.PTEXT, p.text)
   MERGE (r:Role {key: $dataset + '|' + row.AGR_NAME}) ON CREATE SET r.dataset=$dataset, r.id=row.AGR_NAME
   MERGE (r)-[:HAS_PROFILE]->(p)",
  {batchSize:2000, parallel:false, params:{url:'file:///'+$dataset+'/arg_prof.csv', dataset:$dataset}}
);
