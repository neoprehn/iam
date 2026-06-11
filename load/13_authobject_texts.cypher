// 13 — TOBJT -> :AuthObject.text (Objekt-Texte, Sprache DE). Parameter: $dataset
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM $url AS row FIELDTERMINATOR '\t' RETURN row",
  "WITH row WHERE coalesce(row.OBJECT,'') <> '' AND row.LANGU = 'DE'
   MATCH (o:AuthObject {key: $dataset + '|' + row.OBJECT})
   SET o.text = row.TTEXT",
  {batchSize:2000, parallel:false, params:{url:'file:///'+$dataset+'/tobjt.csv', dataset:$dataset}}
);
