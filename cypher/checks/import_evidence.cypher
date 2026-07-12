// I1 — Import-Evidenz: Quellzeilen je SAP-Tabelle gegen das Graph-Ergebnis abgleichen
// (ROADMAP.md "Import-Evidenz", Vollstaendigkeitsnachweis gegen Quell-SAP). Nutzt den neuesten
// (:Import)-Knoten dieses Datasets (backend/app.py _persist_import_evidence(), seit Einfuehrung
// dieses Checks geschrieben -- aeltere, davor importierte Datasets haben noch keinen: informativer
// Hinweis statt Fehler, s. u.).
//
// Die Beziehung Quelltabelle -> Graph ist als LITERALE Tabelle eingebettet statt automatisch aus
// den load/*.cypher-Dateien abgeleitet, damit Nuancen nicht faelschlich als Abweichung markiert
// werden: node_1to1/edge_1to1 (echte 1:1-Erwartung), edge_filtered (Ladelogik ueberspringt
// bewusst EXCLUDE='X'-Zeilen, Graph-Zahl <= Quellzeilen ist normal), shared_edge_type (mehrere
// Quelltabellen erzeugen denselben Kantentyp, z. B. CONTAINS fuer Rolle- UND Profil-Hierarchie --
// eine Gesamtzahl waere nicht eindeutig einer Tabelle zuzuordnen), aggregated (mehrere Quellzeilen
// buendeln sich nach AE-03 zu einem Authorization-Knoten bzw. werden dedupliziert), property
// (reichert bestehende Knoten nur an, erzeugt keine eigenen Knoten/Kanten).
// Parameter: $dataset, $asOf (asOf ungenutzt, nur fuer die generische Check-Signatur).

OPTIONAL MATCH (imp:Import {dataset:$dataset})
WITH imp ORDER BY imp.importedAt DESC LIMIT 1
WITH imp, CASE WHEN imp IS NULL THEN
  [{table:'-', kind:'none', target:'', note:'Dataset wurde seit Einfuehrung der Import-Evidenz noch nicht (erneut) importiert -- ein erneuter Import legt die Datenbasis fuer diesen Check an.'}]
ELSE [
  {table:'usr02', kind:'node_1to1', target:'User', note:'1:1'},
  {table:'agr_define', kind:'node_1to1', target:'Role', note:'1:1'},
  {table:'tstct', kind:'node_1to1', target:'Transaction', note:'1:1'},
  {table:'usorg', kind:'node_1to1', target:'OrgField', note:'1:1'},
  {table:'agr_agrs', kind:'shared_edge_type', target:'CONTAINS', note:'CONTAINS wird auch von UST10C (Profil-Profil) genutzt, Gesamtzahl nicht 1:1 einer Tabelle zuzuordnen'},
  {table:'ust10c', kind:'shared_edge_type', target:'CONTAINS', note:'CONTAINS wird auch von AGR_AGRS (Rolle-Rolle) genutzt, Gesamtzahl nicht 1:1 einer Tabelle zuzuordnen'},
  {table:'ust04', kind:'shared_edge_type', target:'HAS_PROFILE', note:'HAS_PROFILE wird auch von AGR_PROF (Rolle-Profil) genutzt'},
  {table:'agr_prof', kind:'shared_edge_type', target:'HAS_PROFILE', note:'HAS_PROFILE wird auch von UST04 (User-Profil) genutzt -- erzeugt zudem neue Profil-Knoten'},
  {table:'agr_users', kind:'edge_filtered', target:'ASSIGNED_TO', note:'EXCLUDE=X-Zeilen werden beim Laden bewusst uebersprungen, Graph-Zahl kann daher niedriger sein'},
  {table:'agr_tcodes', kind:'edge_filtered', target:'HAS_MENU', note:'EXCLUDE=X und leere TCODE-Ordnereintraege werden beim Laden bewusst uebersprungen'},
  {table:'usrefus', kind:'edge_1to1', target:'HAS_REFERENCE', note:'1:1'},
  {table:'agr_1251', kind:'aggregated', target:'Authorization', note:'Feldwerte buendeln sich je Rolle+Objekt+Berechtigung zu einem Authorization-Knoten (AE-03) -- DELETED=X separat gezaehlt (Spalte gefiltert)'},
  {table:'ust10s', kind:'aggregated', target:'Authorization', note:'Profilseitige Berechtigungs-Templates, aehnliche Buendelung wie AGR_1251'},
  {table:'ust12', kind:'aggregated', target:'Authorization', note:'Feldwerte reichern bestehende Authorization-Templates an, kein eigener Knotenzaehler'},
  {table:'usobt_c', kind:'aggregated', target:'CHECKS', note:'Dedupliziert nach NAME+OBJECT, viele Quellzeilen ergeben weniger Kanten'},
  {table:'usr11', kind:'property', target:'Profile', note:'Reichert bestehende Profil-Knoten an (Text/Status)'},
  {table:'v_username', kind:'property', target:'User', note:'Reichert bestehende User-Knoten an (Name)'},
  {table:'tobjt', kind:'property', target:'AuthObject', note:'Reichert bestehende AuthObject-Knoten an (Text)'},
  {table:'agr_1252', kind:'property', target:'Role', note:'Reichert bestehende Role-Knoten an (Org-Ebenen-Werte)'},
  {table:'usr13', kind:'property', target:'Authorization', note:'Reichert bestehende Authorization-Templates an (Text)'},
  {table:'agr_texts', kind:'property', target:'Role', note:'Reichert bestehende Role-Knoten an (sprachabhaengiger Text)'},
  {table:'agr_1016', kind:'property', target:'Role', note:'Reichert bestehende Role-Knoten an (Generierungsstatus)'}
] END AS mapping
UNWIND mapping AS m
OPTIONAL MATCH (imp)-[:HAS_TABLE]->(it:ImportTable {table:m.table})
CALL {
  WITH imp, m
  // Knoten tragen zusaetzliche Subtyp-Labels (User: Dialog/System/.../Active/Locked; Role:
  // Composite/Single) -- 99_validate.cypher gruppiert je EXAKTER Labelkombination, daher hier
  // ueber alle Kombinationen summieren, die das Ziel-Label enthalten, statt exakt [m.target] zu
  // erwarten (sonst faelschlich immer "kein Graph-Ergebnis").
  OPTIONAL MATCH (imp)-[:HAS_NODE_COUNT]->(nc:ImportNodeCount)
    WHERE m.kind = 'node_1to1' AND m.target IN nc.labels
  WITH imp, m, sum(nc.count) AS nodeSum
  OPTIONAL MATCH (imp)-[:HAS_EDGE_COUNT]->(ec:ImportEdgeCount)
    WHERE m.kind IN ['edge_1to1', 'edge_filtered', 'shared_edge_type'] AND ec.type = m.target
  RETURN CASE WHEN m.kind = 'node_1to1' THEN nodeSum
              WHEN m.kind IN ['edge_1to1', 'edge_filtered', 'shared_edge_type'] THEN ec.count
              ELSE null END AS graphCount
}
WITH imp, m, it, graphCount
WITH imp, m, it, graphCount,
  CASE
    WHEN m.kind = 'none' THEN 'Hinweis'
    WHEN it IS NULL THEN 'Tabelle nicht im Extrakt (optional)'
    WHEN m.kind IN ['node_1to1', 'edge_1to1'] THEN
      CASE WHEN it.sourceRows = graphCount THEN 'OK' ELSE 'Abweichung' END
    WHEN m.kind = 'edge_filtered' THEN
      CASE WHEN graphCount IS NOT NULL AND graphCount <= it.sourceRows THEN 'Hinweis' ELSE 'Abweichung' END
    ELSE 'Hinweis'
  END AS status
RETURN
  count(*) AS tabellenGeprueft,
  sum(CASE WHEN status = 'OK' THEN 1 ELSE 0 END) AS ok,
  sum(CASE WHEN status = 'Hinweis' THEN 1 ELSE 0 END) AS hinweis,
  sum(CASE WHEN status = 'Tabelle nicht im Extrakt (optional)' THEN 1 ELSE 0 END) AS nichtImExtrakt,
  sum(CASE WHEN status = 'Abweichung' THEN 1 ELSE 0 END) AS abweichung,
  imp.importedAt AS importiertAm;

OPTIONAL MATCH (imp:Import {dataset:$dataset})
WITH imp ORDER BY imp.importedAt DESC LIMIT 1
WITH imp, CASE WHEN imp IS NULL THEN
  [{table:'-', kind:'none', target:'', note:'Dataset wurde seit Einfuehrung der Import-Evidenz noch nicht (erneut) importiert -- ein erneuter Import legt die Datenbasis fuer diesen Check an.'}]
ELSE [
  {table:'usr02', kind:'node_1to1', target:'User', note:'1:1'},
  {table:'agr_define', kind:'node_1to1', target:'Role', note:'1:1'},
  {table:'tstct', kind:'node_1to1', target:'Transaction', note:'1:1'},
  {table:'usorg', kind:'node_1to1', target:'OrgField', note:'1:1'},
  {table:'agr_agrs', kind:'shared_edge_type', target:'CONTAINS', note:'CONTAINS wird auch von UST10C (Profil-Profil) genutzt, Gesamtzahl nicht 1:1 einer Tabelle zuzuordnen'},
  {table:'ust10c', kind:'shared_edge_type', target:'CONTAINS', note:'CONTAINS wird auch von AGR_AGRS (Rolle-Rolle) genutzt, Gesamtzahl nicht 1:1 einer Tabelle zuzuordnen'},
  {table:'ust04', kind:'shared_edge_type', target:'HAS_PROFILE', note:'HAS_PROFILE wird auch von AGR_PROF (Rolle-Profil) genutzt'},
  {table:'agr_prof', kind:'shared_edge_type', target:'HAS_PROFILE', note:'HAS_PROFILE wird auch von UST04 (User-Profil) genutzt -- erzeugt zudem neue Profil-Knoten'},
  {table:'agr_users', kind:'edge_filtered', target:'ASSIGNED_TO', note:'EXCLUDE=X-Zeilen werden beim Laden bewusst uebersprungen, Graph-Zahl kann daher niedriger sein'},
  {table:'agr_tcodes', kind:'edge_filtered', target:'HAS_MENU', note:'EXCLUDE=X und leere TCODE-Ordnereintraege werden beim Laden bewusst uebersprungen'},
  {table:'usrefus', kind:'edge_1to1', target:'HAS_REFERENCE', note:'1:1'},
  {table:'agr_1251', kind:'aggregated', target:'Authorization', note:'Feldwerte buendeln sich je Rolle+Objekt+Berechtigung zu einem Authorization-Knoten (AE-03) -- DELETED=X separat gezaehlt (Spalte gefiltert)'},
  {table:'ust10s', kind:'aggregated', target:'Authorization', note:'Profilseitige Berechtigungs-Templates, aehnliche Buendelung wie AGR_1251'},
  {table:'ust12', kind:'aggregated', target:'Authorization', note:'Feldwerte reichern bestehende Authorization-Templates an, kein eigener Knotenzaehler'},
  {table:'usobt_c', kind:'aggregated', target:'CHECKS', note:'Dedupliziert nach NAME+OBJECT, viele Quellzeilen ergeben weniger Kanten'},
  {table:'usr11', kind:'property', target:'Profile', note:'Reichert bestehende Profil-Knoten an (Text/Status)'},
  {table:'v_username', kind:'property', target:'User', note:'Reichert bestehende User-Knoten an (Name)'},
  {table:'tobjt', kind:'property', target:'AuthObject', note:'Reichert bestehende AuthObject-Knoten an (Text)'},
  {table:'agr_1252', kind:'property', target:'Role', note:'Reichert bestehende Role-Knoten an (Org-Ebenen-Werte)'},
  {table:'usr13', kind:'property', target:'Authorization', note:'Reichert bestehende Authorization-Templates an (Text)'},
  {table:'agr_texts', kind:'property', target:'Role', note:'Reichert bestehende Role-Knoten an (sprachabhaengiger Text)'},
  {table:'agr_1016', kind:'property', target:'Role', note:'Reichert bestehende Role-Knoten an (Generierungsstatus)'}
] END AS mapping
UNWIND mapping AS m
OPTIONAL MATCH (imp)-[:HAS_TABLE]->(it:ImportTable {table:m.table})
CALL {
  WITH imp, m
  // Knoten tragen zusaetzliche Subtyp-Labels (User: Dialog/System/.../Active/Locked; Role:
  // Composite/Single) -- 99_validate.cypher gruppiert je EXAKTER Labelkombination, daher hier
  // ueber alle Kombinationen summieren, die das Ziel-Label enthalten, statt exakt [m.target] zu
  // erwarten (sonst faelschlich immer "kein Graph-Ergebnis").
  OPTIONAL MATCH (imp)-[:HAS_NODE_COUNT]->(nc:ImportNodeCount)
    WHERE m.kind = 'node_1to1' AND m.target IN nc.labels
  WITH imp, m, sum(nc.count) AS nodeSum
  OPTIONAL MATCH (imp)-[:HAS_EDGE_COUNT]->(ec:ImportEdgeCount)
    WHERE m.kind IN ['edge_1to1', 'edge_filtered', 'shared_edge_type'] AND ec.type = m.target
  RETURN CASE WHEN m.kind = 'node_1to1' THEN nodeSum
              WHEN m.kind IN ['edge_1to1', 'edge_filtered', 'shared_edge_type'] THEN ec.count
              ELSE null END AS graphCount
}
WITH imp, m, it, graphCount
WITH imp, m, it, graphCount,
  CASE
    WHEN m.kind = 'none' THEN 'Hinweis'
    WHEN it IS NULL THEN 'Tabelle nicht im Extrakt (optional)'
    WHEN m.kind IN ['node_1to1', 'edge_1to1'] THEN
      CASE WHEN it.sourceRows = graphCount THEN 'OK' ELSE 'Abweichung' END
    WHEN m.kind = 'edge_filtered' THEN
      CASE WHEN graphCount IS NOT NULL AND graphCount <= it.sourceRows THEN 'Hinweis' ELSE 'Abweichung' END
    ELSE 'Hinweis'
  END AS status
RETURN
  m.table AS tabelle, m.kind AS art, m.target AS ziel,
  it.sourceRows AS quellzeilen, it.filteredRows AS gefiltert, it.droppedColumns AS verworfeneSpalten,
  graphCount AS graphErgebnis, status AS status, m.note AS hinweis
ORDER BY
  CASE status WHEN 'Abweichung' THEN 0 WHEN 'Hinweis' THEN 1
    WHEN 'Tabelle nicht im Extrakt (optional)' THEN 2 WHEN 'OK' THEN 3 ELSE 4 END,
  tabelle;
