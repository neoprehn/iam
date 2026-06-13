// 08 — AGR_1251 -> :Authorization (AE-03), HAS_AUTH (Role->Auth), FOR_OBJECT (Auth->AuthObject).
// Ein Authorization-Knoten je (AGR_NAME, OBJECT, AUTH). Feldwerte als Properties f_<FELD> (Liste),
// Bereiche als 'LOW..HIGH', '*' bleibt erhalten (AE-06). DELETED='X' wird gefiltert. Parameter: $dataset
//
// ZWEI-PASS / Aggregate-First (analog 19): je Auth ZUERST alle Feldwerte sammeln (collect DISTINCT
// -> Map), dann den Knoten EINMAL mergen und alle f_-Properties in einem `SET a += props` setzen.
// Ersetzt das frühere pro-Zeile coalesce+toSet+setProperty (O(n^2)-Array-Append, eskalierende
// Batchzeiten). Schnell nur MIT dem Key-Index aus Migration V003 (sonst Full-Scan je MERGE).
// AGR_1251 ist die alleinige Quelle der f_-Werte der Rollen-Auths -> Overwrite ist verlustfrei
// und idempotent.
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM $url AS row FIELDTERMINATOR '\t'
   WITH row WHERE coalesce(row.DELETED,'') <> 'X' AND coalesce(row.AUTH,'') <> '' AND coalesce(row.FIELD,'') <> ''
   WITH row.AGR_NAME AS agr, row.OBJECT AS obj, row.AUTH AS auth, 'f_' + row.FIELD AS fkey,
        CASE WHEN coalesce(row.HIGH,'') = '' THEN coalesce(row.LOW,'') ELSE row.LOW + '..' + row.HIGH END AS val
   WITH agr, obj, auth, fkey, collect(DISTINCT val) AS vals
   WITH agr, obj, auth, collect([fkey, vals]) AS pairs
   RETURN agr, obj, auth, apoc.map.fromPairs(pairs) AS props",
  "MERGE (a:Authorization {key: $dataset + '|' + agr + '|' + obj + '|' + auth})
     ON CREATE SET a.dataset=$dataset, a.role=agr, a.object=obj, a.auth=auth
   SET a += props
   MERGE (r:Role {key: $dataset + '|' + agr}) ON CREATE SET r.dataset=$dataset, r.id=agr
   MERGE (r)-[:HAS_AUTH]->(a)
   MERGE (o:AuthObject {key: $dataset + '|' + obj}) ON CREATE SET o.dataset=$dataset, o.id=obj
   MERGE (a)-[:FOR_OBJECT]->(o)
   RETURN count(*)",
  {batchSize:5000, parallel:false, params:{url:'file:///'+$dataset+'/agr_1251.csv', dataset:$dataset}}
);
