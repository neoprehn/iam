// 18 — UST10S -> profilseitige Berechtigungen (Struktur, ohne Feldwerte).
// (:Profile)-[:HAS_AUTH]->(:Authorization {scope:'profile'})-[:FOR_OBJECT]->(:AuthObject).
// Template-Auth je (OBJCT, AUTH); Schlüssel mit @PROF-Marker, getrennt von Rollen-Auths.
// Feldwerte folgen separat aus UST12 (Skript 19). Parameter: $dataset
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM $url AS row FIELDTERMINATOR '\t' RETURN row",
  "WITH row WHERE coalesce(row.PROFN,'') <> '' AND coalesce(row.OBJCT,'') <> '' AND coalesce(row.AUTH,'') <> ''
   MERGE (a:Authorization {key: $dataset + '|@PROF|' + row.OBJCT + '|' + row.AUTH})
     ON CREATE SET a.dataset=$dataset, a.object=row.OBJCT, a.auth=row.AUTH, a.scope='profile'
   MERGE (p:Profile {key: $dataset + '|' + row.PROFN}) ON CREATE SET p.dataset=$dataset, p.id=row.PROFN
   MERGE (p)-[:HAS_AUTH]->(a)
   MERGE (o:AuthObject {key: $dataset + '|' + row.OBJCT}) ON CREATE SET o.dataset=$dataset, o.id=row.OBJCT
   MERGE (a)-[:FOR_OBJECT]->(o)",
  {batchSize:5000, parallel:false, params:{url:'file:///'+$dataset+'/ust10s.csv', dataset:$dataset}}
);
