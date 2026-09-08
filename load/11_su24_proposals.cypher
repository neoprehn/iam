// 11 — USOBT_C -> PROPOSES (Transaction->AuthObject je Feld), aus (NAME, OBJECT, FIELD, LOW, HIGH).
// Ergaenzt die deduplizierte CHECKS-Kante aus 10_su24_checks.cypher (nur "wird ueberhaupt
// geprueft") um die eigentlichen SU24-Vorschlagswerte je Feld -- Grundlage fuer den USOBT-
// gestuetzten Query-Builder (ROADMAP-V2.md Phase 1). Bewusst eine EIGENE Kante statt Properties an
// CHECKS: ein (TCode,Objekt)-Paar hat oft mehrere Felder (je eine Zeile in USOBT_C), und dasselbe
// Objekt kann bei verschiedenen TCodes unterschiedliche Vorschlagswerte tragen -- mehrere
// PROPOSES-Kanten zwischen denselben zwei Knoten sind hier also der Normalfall, kein Fehler.
// MERGE inkl. der drei Werte selbst dedupliziert exakte Wiederholungen, laesst aber unterschiedliche
// (field,low,high)-Kombinationen nebeneinander stehen. Parameter: $dataset
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM $url AS row FIELDTERMINATOR '\t' RETURN row",
  "WITH row WHERE coalesce(row.NAME,'') <> '' AND coalesce(row.OBJECT,'') <> '' AND coalesce(row.FIELD,'') <> ''
   MERGE (t:Transaction {key: $dataset + '|' + row.NAME}) ON CREATE SET t.dataset=$dataset, t.id=row.NAME
   MERGE (o:AuthObject {key: $dataset + '|' + row.OBJECT}) ON CREATE SET o.dataset=$dataset, o.id=row.OBJECT
   MERGE (t)-[:PROPOSES {field: row.FIELD, low: coalesce(row.LOW,''), high: coalesce(row.HIGH,'')}]->(o)",
  {batchSize:10000, parallel:false, params:{url:'file:///'+$dataset+'/usobt_c.csv', dataset:$dataset}}
);
