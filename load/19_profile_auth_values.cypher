// 19 — UST12 -> Feldwerte ALLER profilseitigen Berechtigungen (f_<FELD> an den @PROF-Templates).
// VERLUSTFREI by construction: keine annahmebasierte Eingrenzung. Jedes Profil bekommt seine
// tatsächlichen Feldwerte aus der Quelle — unabhängig davon, ob sie (bei diesem Konzept) den
// Rollen-Auths gleichen. Andere Berechtigungskonzepte können abweichen.
// Bereiche als 'VON..BIS', '*' bleibt (AE-06). SCHWERER Schritt (UST12 ~483k Zeilen). Parameter: $dataset
//
// ZWEI-PASS / Aggregate-First: Werte je (Auth,Feld) ZUERST in der LOAD-CSV-Abfrage gruppieren
// (collect DISTINCT), dann je Auth-Feld EINMAL setzen. Vermeidet das O(n^2)-Read-Modify-Write
// der Array-Property der früheren Variante (pro Zeile coalesce+toSet+setProperty -> eskalierende
// Batchzeiten, Stunden). 18 setzt keine f_-Properties -> Overwrite ist verlustfrei und idempotent.
// MATCH (kein MERGE): nur (OBJCT,AUTH), die ein Profil referenziert (Templates aus Skript 18).
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM $url AS row FIELDTERMINATOR '\t'
   WITH row WHERE coalesce(row.AUTH,'') <> '' AND coalesce(row.FIELD,'') <> ''
   WITH $dataset + '|@PROF|' + row.OBJCT + '|' + row.AUTH AS akey,
        'f_' + row.FIELD AS fkey,
        CASE WHEN coalesce(row.BIS,'') = '' THEN coalesce(row.VON,'') ELSE row.VON + '..' + row.BIS END AS val
   WITH akey, fkey, collect(DISTINCT val) AS vals
   RETURN akey, fkey, vals",
  "MATCH (a:Authorization {key: akey})
   CALL apoc.create.setProperty(a, fkey, vals) YIELD node
   RETURN count(*)",
  {batchSize:5000, parallel:false, params:{url:'file:///'+$dataset+'/ust12.csv', dataset:$dataset}}
);
