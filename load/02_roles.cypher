// 02 — AGR_DEFINE -> :Role (+ Text, parentAgr=Sammelrolle). Parameter: $dataset
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM $url AS row FIELDTERMINATOR '\t' RETURN row",
  "WITH row WHERE coalesce(row.AGR_NAME,'') <> ''
   MERGE (r:Role {key: $dataset + '|' + row.AGR_NAME})
     ON CREATE SET r.dataset = $dataset, r.id = row.AGR_NAME
   SET r.text = row.TEXT,
       r.parentAgr = CASE WHEN coalesce(row.PARENT_AGR,'') = '' THEN null ELSE row.PARENT_AGR END",
  {batchSize:2000, parallel:false, params:{url:'file:///'+$dataset+'/agr_define.csv', dataset:$dataset}}
);
