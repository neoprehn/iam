// 07 — USR11 -> :Profile-Texte/Status. Parameter: $dataset
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM $url AS row FIELDTERMINATOR '\t' RETURN row",
  "WITH row WHERE coalesce(row.PROFN,'') <> ''
   MERGE (p:Profile {key: $dataset + '|' + row.PROFN}) ON CREATE SET p.dataset=$dataset, p.id=row.PROFN
   SET p.text = coalesce(row.PTEXT, p.text), p.active = row.AKTPS",
  {batchSize:2000, parallel:false, params:{url:'file:///'+$dataset+'/usr11.csv', dataset:$dataset}}
);
