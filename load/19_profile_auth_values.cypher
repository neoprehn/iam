// 19 — UST12 -> Feldwerte ALLER profilseitigen Berechtigungen (f_<FELD> an den @PROF-Templates).
// VERLUSTFREI by construction: keine annahmebasierte Eingrenzung. Jedes Profil bekommt seine
// tatsächlichen Feldwerte aus der Quelle — unabhängig davon, ob sie (bei diesem Konzept) den
// Rollen-Auths gleichen. Andere Berechtigungskonzepte können abweichen.
// Bereiche als 'VON..BIS', '*' bleibt (AE-06). SCHWERER Schritt (UST12 ~483k Zeilen). Parameter: $dataset
//
// MATCH (kein MERGE): nur (OBJCT,AUTH), die ein Profil referenziert (Templates aus Skript 18).
// Reine Auth-Definitionen ohne Profilbezug sind kein Zugriffspfad -> bewusst nicht materialisiert.
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM $url AS row FIELDTERMINATOR '\t' RETURN row",
  "WITH row WHERE coalesce(row.AUTH,'') <> '' AND coalesce(row.FIELD,'') <> ''
   MATCH (a:Authorization {key: $dataset + '|@PROF|' + row.OBJCT + '|' + row.AUTH})
   WITH a, 'f_' + row.FIELD AS fkey,
        CASE WHEN coalesce(row.BIS,'') = '' THEN coalesce(row.VON,'') ELSE row.VON + '..' + row.BIS END AS val
   CALL apoc.create.setProperty(a, fkey, apoc.coll.toSet(coalesce(apoc.any.property(a, fkey), []) + val)) YIELD node
   RETURN count(*)",
  {batchSize:10000, parallel:false, params:{url:'file:///'+$dataset+'/ust12.csv', dataset:$dataset}}
);
