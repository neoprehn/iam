// 04 — AGR_USERS -> ASSIGNED_TO (mit Gültigkeit). Parameter: $dataset
// EXCLUDE='X' (ausgeschlossene Zuordnung) wird übersprungen. Datumsformat DD.MM.YYYY.
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM $url AS row FIELDTERMINATOR '\t' RETURN row",
  "WITH row WHERE coalesce(row.UNAME,'') <> '' AND coalesce(row.AGR_NAME,'') <> '' AND coalesce(row.EXCLUDE,'') <> 'X'
   MERGE (u:User {key: $dataset + '|' + row.UNAME}) ON CREATE SET u.dataset=$dataset, u.id=row.UNAME
   MERGE (r:Role {key: $dataset + '|' + row.AGR_NAME}) ON CREATE SET r.dataset=$dataset, r.id=row.AGR_NAME
   MERGE (u)-[a:ASSIGNED_TO]->(r)
   SET a.validFrom = CASE WHEN coalesce(row.FROM_DAT,'') IN ['','00.00.0000'] THEN null
                          WHEN row.FROM_DAT = '31.12.9999' THEN date('9999-12-31')
                          ELSE date(right(row.FROM_DAT,4)+'-'+substring(row.FROM_DAT,3,2)+'-'+left(row.FROM_DAT,2)) END,
       a.validTo   = CASE WHEN coalesce(row.TO_DAT,'') IN ['','00.00.0000'] THEN null
                          WHEN row.TO_DAT = '31.12.9999' THEN date('9999-12-31')
                          ELSE date(right(row.TO_DAT,4)+'-'+substring(row.TO_DAT,3,2)+'-'+left(row.TO_DAT,2)) END",
  {batchSize:5000, parallel:false, params:{url:'file:///'+$dataset+'/agr_users.csv', dataset:$dataset}}
);
