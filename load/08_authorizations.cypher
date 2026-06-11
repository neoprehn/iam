// 08 — AGR_1251 -> :Authorization (AE-03), HAS_AUTH (Role->Auth), FOR_OBJECT (Auth->AuthObject).
// Ein Authorization-Knoten je (AGR_NAME, OBJECT, AUTH). Feldwerte als Properties f_<FELD> (Liste),
// Bereiche als 'LOW..HIGH', '*' bleibt erhalten (AE-06). DELETED='X' wird gefiltert. Parameter: $dataset
//
// HINWEIS: schwerster Schritt (726k Zeilen, dynamische f_<FELD>-Properties). Eine getestete
// "aggregate-first"-Variante war hier NICHT schneller (die dynamischen Property-Writes dominieren).
// Eine echte Optimierung (Zwei-Pass: distinct Knoten/Kanten, dann je Auth eine Bulk-Property-
// Setzung mit apoc.create.setProperties) ist als Folgearbeit offen.
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM $url AS row FIELDTERMINATOR '\t' RETURN row",
  "WITH row WHERE coalesce(row.DELETED,'') <> 'X' AND coalesce(row.AUTH,'') <> '' AND coalesce(row.FIELD,'') <> ''
   MERGE (a:Authorization {key: $dataset + '|' + row.AGR_NAME + '|' + row.OBJECT + '|' + row.AUTH})
     ON CREATE SET a.dataset=$dataset, a.role=row.AGR_NAME, a.object=row.OBJECT, a.auth=row.AUTH
   MERGE (r:Role {key: $dataset + '|' + row.AGR_NAME}) ON CREATE SET r.dataset=$dataset, r.id=row.AGR_NAME
   MERGE (r)-[:HAS_AUTH]->(a)
   MERGE (o:AuthObject {key: $dataset + '|' + row.OBJECT}) ON CREATE SET o.dataset=$dataset, o.id=row.OBJECT
   MERGE (a)-[:FOR_OBJECT]->(o)
   WITH a, 'f_' + row.FIELD AS fkey,
        CASE WHEN coalesce(row.HIGH,'') = '' THEN coalesce(row.LOW,'') ELSE row.LOW + '..' + row.HIGH END AS val
   CALL apoc.create.setProperty(a, fkey, apoc.coll.toSet(coalesce(apoc.any.property(a, fkey), []) + val)) YIELD node
   RETURN count(*)",
  {batchSize:10000, parallel:false, params:{url:'file:///'+$dataset+'/agr_1251.csv', dataset:$dataset}}
);
