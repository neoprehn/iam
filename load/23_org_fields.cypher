// 23 — USORG -> :OrgField (Registry der organisatorischen Berechtigungsfelder). Parameter: $dataset
// Liefert die Liste der org-relevanten Felder (z. B. BUKRS, WERKS, EKORG) fuer die Auswertung:
// im Default werden diese Felder "egal" behandelt (wie '*'), erst ein Org-Profil schraenkt sie ein.
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM $url AS row FIELDTERMINATOR '\t' RETURN row",
  "WITH row WHERE coalesce(row.FIELD,'') <> ''
   MERGE (f:OrgField {key: $dataset + '|' + row.FIELD}) ON CREATE SET f.dataset=$dataset, f.field=row.FIELD",
  {batchSize:1000, parallel:false, params:{url:'file:///'+$dataset+'/usorg.csv', dataset:$dataset}}
);
