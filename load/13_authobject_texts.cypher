// 13 — TOBJT -> :AuthObject.text (Objekt-Texte). Sprache über $lang-Schalter: bevorzugte
// Sprache(n) gewinnen, sonst erster vorhandener Text. Parameter: $dataset, $lang
// $lang = Liste akzeptierter Codes, Default ['DE','DEU','D'].
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM $url AS row FIELDTERMINATOR '\t' RETURN row",
  "WITH row WHERE coalesce(row.OBJECT,'') <> ''
   MATCH (o:AuthObject {key: $dataset + '|' + row.OBJECT})
   SET o.text = CASE WHEN row.LANGU IN $lang THEN row.TTEXT WHEN o.text IS NULL THEN row.TTEXT ELSE o.text END",
  {batchSize:2000, parallel:false, params:{url:'file:///'+$dataset+'/tobjt.csv', dataset:$dataset, lang:coalesce($lang,['DE','DEU','D'])}}
);
