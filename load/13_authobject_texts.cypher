// 13 — TOBJT -> :AuthObject.text (Objekt-Texte). Sprache robust: DE bevorzugt, sonst erster
// vorhandener Text. Parameter: $dataset
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM $url AS row FIELDTERMINATOR '\t' RETURN row",
  "WITH row WHERE coalesce(row.OBJECT,'') <> ''
   MATCH (o:AuthObject {key: $dataset + '|' + row.OBJECT})
   SET o.text = CASE WHEN row.LANGU = 'DE' THEN row.TTEXT WHEN o.text IS NULL THEN row.TTEXT ELSE o.text END",
  {batchSize:2000, parallel:false, params:{url:'file:///'+$dataset+'/tobjt.csv', dataset:$dataset}}
);
