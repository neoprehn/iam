// 09 — TSTCT -> :Transaction (+ Text). Parameter: $dataset, $lang
// Kein TSTC im Extrakt; Transaktions-Katalog/Text aus TSTCT. Sprache über $lang-Schalter:
// bevorzugte Sprache(n) gewinnen, sonst erster vorhandener Text (kein hartes Filter ->
// funktioniert für jedes System). $lang = Liste akzeptierter Codes, Default ['DE','DEU','D'].
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM $url AS row FIELDTERMINATOR '\t' RETURN row",
  "WITH row WHERE coalesce(row.TCODE,'') <> ''
   MERGE (t:Transaction {key: $dataset + '|' + row.TCODE}) ON CREATE SET t.dataset=$dataset, t.id=row.TCODE
   SET t.text = CASE WHEN row.SPRSL IN $lang THEN row.TTEXT WHEN t.text IS NULL THEN row.TTEXT ELSE t.text END",
  {batchSize:5000, parallel:false, params:{url:'file:///'+$dataset+'/tstct.csv', dataset:$dataset, lang:coalesce($lang,['DE','DEU','D'])}}
);
