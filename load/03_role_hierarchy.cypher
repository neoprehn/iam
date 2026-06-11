// 03 — AGR_AGRS -> CONTAINS (Composite->Single) + Subtyp-Labels. Parameter: $dataset
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM $url AS row FIELDTERMINATOR '\t' RETURN row",
  "WITH row WHERE coalesce(row.AGR_NAME,'') <> '' AND coalesce(row.CHILD_AGR,'') <> ''
   MERGE (p:Role {key: $dataset + '|' + row.AGR_NAME}) ON CREATE SET p.dataset=$dataset, p.id=row.AGR_NAME
   MERGE (c:Role {key: $dataset + '|' + row.CHILD_AGR}) ON CREATE SET c.dataset=$dataset, c.id=row.CHILD_AGR
   MERGE (p)-[:CONTAINS]->(c)",
  {batchSize:2000, parallel:false, params:{url:'file:///'+$dataset+'/agr_agrs.csv', dataset:$dataset}}
);
// Subtyp-Labels (Composite/Single) werden in 11_finalize.cypher gesetzt — nach ALLEN
// Lade-Schritten, damit auch erst spät angelegte Rollen (aus AGR_1251/AGR_USERS) erfasst sind.
