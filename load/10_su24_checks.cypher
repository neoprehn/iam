// 10 — USOBT_C -> CHECKS (Transaction->AuthObject), aus (NAME, OBJECT). Parameter: $dataset
// MERGE dedupliziert die vielen Wiederholungen der (NAME,OBJECT)-Paare; lief zügig durch.
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM $url AS row FIELDTERMINATOR '\t' RETURN row",
  "WITH row WHERE coalesce(row.NAME,'') <> '' AND coalesce(row.OBJECT,'') <> ''
   MERGE (t:Transaction {key: $dataset + '|' + row.NAME}) ON CREATE SET t.dataset=$dataset, t.id=row.NAME
   MERGE (o:AuthObject {key: $dataset + '|' + row.OBJECT}) ON CREATE SET o.dataset=$dataset, o.id=row.OBJECT
   MERGE (t)-[:CHECKS]->(o)",
  {batchSize:10000, parallel:false, params:{url:'file:///'+$dataset+'/usobt_c.csv', dataset:$dataset}}
);
