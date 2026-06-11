// 20 — USR13 -> Berechtigungs-Texte (authText) an den profilseitigen @PROF-Templates.
// Sprache robust: DE bevorzugt, sonst erster vorhandener Text. Parameter: $dataset
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM $url AS row FIELDTERMINATOR '\t' RETURN row",
  "WITH row WHERE coalesce(row.AUTH,'') <> ''
   MATCH (a:Authorization {key: $dataset + '|@PROF|' + row.OBJCT + '|' + row.AUTH})
   SET a.authText = CASE WHEN row.LANGU = 'DE' THEN row.ATEXT WHEN a.authText IS NULL THEN row.ATEXT ELSE a.authText END",
  {batchSize:5000, parallel:false, params:{url:'file:///'+$dataset+'/usr13.csv', dataset:$dataset}}
);
