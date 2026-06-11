// 06 — UST04 -> HAS_PROFILE (User->Profile, direkt zugewiesen, z. B. SAP_ALL). Parameter: $dataset
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM $url AS row FIELDTERMINATOR '\t' RETURN row",
  "WITH row WHERE coalesce(row.BNAME,'') <> '' AND coalesce(row.PROFILE,'') <> ''
   MERGE (u:User {key: $dataset + '|' + row.BNAME}) ON CREATE SET u.dataset=$dataset, u.id=row.BNAME
   MERGE (p:Profile {key: $dataset + '|' + row.PROFILE}) ON CREATE SET p.dataset=$dataset, p.id=row.PROFILE
   MERGE (u)-[:HAS_PROFILE]->(p)",
  {batchSize:5000, parallel:false, params:{url:'file:///'+$dataset+'/ust04.csv', dataset:$dataset}}
);
