// 14 — USREFUS -> (:User)-[:HAS_REFERENCE]->(:User). Der Dialog-User (BNAME) erbt die
// Berechtigungen des Referenzbenutzers (REFUSER). Parameter: $dataset
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM $url AS row FIELDTERMINATOR '\t' RETURN row",
  "WITH row WHERE coalesce(row.BNAME,'') <> '' AND coalesce(row.REFUSER,'') <> ''
   MERGE (u:User {key: $dataset + '|' + row.BNAME})    ON CREATE SET u.dataset=$dataset, u.id=row.BNAME
   MERGE (ref:User {key: $dataset + '|' + row.REFUSER}) ON CREATE SET ref.dataset=$dataset, ref.id=row.REFUSER
   MERGE (u)-[:HAS_REFERENCE]->(ref)",
  {batchSize:2000, parallel:false, params:{url:'file:///'+$dataset+'/usrefus.csv', dataset:$dataset}}
);
