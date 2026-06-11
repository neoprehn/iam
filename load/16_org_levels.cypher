// 16 — AGR_1252 -> :Role.org_<VARBL> (Org-Ebenen-Werte abgeleiteter Rollen). VARBL ist die
// Org-Variable (z. B. $BUKRS), Werte als Liste, Bereiche 'LOW..HIGH'. Parameter: $dataset
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM $url AS row FIELDTERMINATOR '\t' RETURN row",
  "WITH row WHERE coalesce(row.AGR_NAME,'') <> '' AND coalesce(row.VARBL,'') <> ''
   MATCH (r:Role {key: $dataset + '|' + row.AGR_NAME})
   WITH r, 'org_' + row.VARBL AS okey,
        CASE WHEN coalesce(row.HIGH,'') = '' THEN coalesce(row.LOW,'') ELSE row.LOW + '..' + row.HIGH END AS val
   CALL apoc.create.setProperty(r, okey, apoc.coll.toSet(coalesce(apoc.any.property(r, okey), []) + val)) YIELD node
   RETURN count(*)",
  {batchSize:2000, parallel:false, params:{url:'file:///'+$dataset+'/agr_1252.csv', dataset:$dataset}}
);
