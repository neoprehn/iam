// Konsistenzcheck (Katalog E4): Transaction-Knoten ohne CHECKS-Kante (kein USOBT_C/SU24-
// Eintrag, Loader 10) -- Bruecke TCode->Objekt fehlt, Berechtigungsbezug der Transaktion ist
// unklar. Relevant fuer die Vollstaendigkeit der Can-Do-Kette (TCode -> Berechtigungsobjekt).
// Parameter: $dataset, $asOf (asOf ungenutzt, einheitliche Signatur).
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/transactions_without_checks.cypher

// --- 1) Zusammenfassung (-> KPI-Kacheln UI) ---
MATCH (t:Transaction {dataset:$dataset})
WHERE NOT EXISTS { (t)-[:CHECKS]->(:AuthObject) }
WITH count(t) AS anzahl, count(CASE WHEN coalesce(t.text, '') = '' THEN 1 END) AS ohneText
RETURN (ohneText + ' davon ohne Text') AS info, anzahl;

// --- 2) Detailliste ---
MATCH (t:Transaction {dataset:$dataset})
WHERE NOT EXISTS { (t)-[:CHECKS]->(:AuthObject) }
RETURN t.id AS tcode, coalesce(t.text, '') AS text,
       count { (:Role)-[:HAS_MENU]->(t) } AS imRollenmenue
ORDER BY imRollenmenue DESC, tcode;
