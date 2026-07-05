// 02 — AGR_DEFINE -> :Role (+ Text, parentAgr=Sammelrolle, Ersteller/Aenderer + Daten). Parameter: $dataset
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM $url AS row FIELDTERMINATOR '\t' RETURN row",
  "WITH row WHERE coalesce(row.AGR_NAME,'') <> ''
   MERGE (r:Role {key: $dataset + '|' + row.AGR_NAME})
     ON CREATE SET r.dataset = $dataset, r.id = row.AGR_NAME
   SET r.text = row.TEXT,
       r.parentAgr = CASE WHEN coalesce(row.PARENT_AGR,'') = '' THEN null ELSE row.PARENT_AGR END,
       // Stammdaten fuer die Rollen-Detailseite (Datum dd.mm.yyyy -> date, Muster wie lastLogon in 01)
       r.createUsr = CASE WHEN coalesce(row.CREATE_USR,'') = '' THEN null ELSE row.CREATE_USR END,
       r.createDat = CASE WHEN coalesce(row.CREATE_DAT,'') IN ['','00.00.0000'] THEN null
                          ELSE date(right(row.CREATE_DAT,4)+'-'+substring(row.CREATE_DAT,3,2)+'-'+left(row.CREATE_DAT,2)) END,
       r.changeUsr = CASE WHEN coalesce(row.CHANGE_USR,'') = '' THEN null ELSE row.CHANGE_USR END,
       r.changeDat = CASE WHEN coalesce(row.CHANGE_DAT,'') IN ['','00.00.0000'] THEN null
                          ELSE date(right(row.CHANGE_DAT,4)+'-'+substring(row.CHANGE_DAT,3,2)+'-'+left(row.CHANGE_DAT,2)) END",
  {batchSize:2000, parallel:false, params:{url:'file:///'+$dataset+'/agr_define.csv', dataset:$dataset}}
);
