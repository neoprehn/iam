// 15 — UST10C -> (:Profile)-[:CONTAINS]->(:Profile). Sammelprofil (PROFN) enthält Subprofil
// (SUBPROF), z. B. SAP_ALL. Subtyp-Label Collective wird in 11_finalize gesetzt. Parameter: $dataset
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM $url AS row FIELDTERMINATOR '\t' RETURN row",
  "WITH row WHERE coalesce(row.PROFN,'') <> '' AND coalesce(row.SUBPROF,'') <> ''
   MERGE (p:Profile {key: $dataset + '|' + row.PROFN})   ON CREATE SET p.dataset=$dataset, p.id=row.PROFN
   MERGE (s:Profile {key: $dataset + '|' + row.SUBPROF}) ON CREATE SET s.dataset=$dataset, s.id=row.SUBPROF
   MERGE (p)-[:CONTAINS]->(s)",
  {batchSize:2000, parallel:false, params:{url:'file:///'+$dataset+'/ust10c.csv', dataset:$dataset}}
);
