// 12 — V_USERNAME -> :User-Properties (Name). Personenbezogen, bleibt lokal. Parameter: $dataset
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM $url AS row FIELDTERMINATOR '\t' RETURN row",
  "WITH row WHERE coalesce(row.BNAME,'') <> ''
   MATCH (u:User {key: $dataset + '|' + row.BNAME})
   SET u.name = row.NAME_TEXT, u.nameLast = row.NAME_LAST,
       u.persNumber = CASE WHEN coalesce(row.PERSNUMBER,'') = '' THEN null ELSE row.PERSNUMBER END",
  {batchSize:2000, parallel:false, params:{url:'file:///'+$dataset+'/v_username.csv', dataset:$dataset}}
);
