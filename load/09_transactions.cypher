// 09 — TSTCT -> :Transaction (+ deutscher Text). Parameter: $dataset
// Kein TSTC im Extrakt; Transaktions-Katalog/Text aus TSTCT (Sprache D).
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM $url AS row FIELDTERMINATOR '\t' RETURN row",
  "WITH row WHERE coalesce(row.TCODE,'') <> '' AND row.SPRSL = 'DE'
   MERGE (t:Transaction {key: $dataset + '|' + row.TCODE}) ON CREATE SET t.dataset=$dataset, t.id=row.TCODE
   SET t.text = row.TTEXT",
  {batchSize:5000, parallel:false, params:{url:'file:///'+$dataset+'/tstct.csv', dataset:$dataset}}
);
