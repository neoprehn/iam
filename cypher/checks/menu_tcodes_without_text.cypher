// Konsistenzcheck (Katalog E3): TCodes im Rollenmenue (AGR_TCODES -> HAS_MENU), die im
// Stammdaten-Import unbekannt sind. ANGEPASSTE OPERATIONALISIERUNG wie E1/E2: der Loader
// importiert kein TSTC-Stammdatentabelle, sondern nur TSTCT (Text, Loader 09) -- :Transaction
// wird lazy aus AGR_TCODES/USOBT_C/TSTCT erzeugt. Als Proxy fuer "nicht in TSTC": Transaction
// ohne Text aus TSTCT.
// Parameter: $dataset, $asOf (asOf ungenutzt, einheitliche Signatur).
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/menu_tcodes_without_text.cypher

// --- 1) Zusammenfassung (-> KPI-Kacheln UI) ---
MATCH (r:Role {dataset:$dataset})-[:HAS_MENU]->(t:Transaction {dataset:$dataset})
WHERE coalesce(t.text, '') = ''
WITH count(DISTINCT t) AS tcodeAnzahl, count(DISTINCT r) AS rollenAnzahl
RETURN (rollenAnzahl + ' Rollen referenzieren sie') AS info, tcodeAnzahl AS anzahl;

// --- 2) Detailliste ---
MATCH (r:Role {dataset:$dataset})-[:HAS_MENU]->(t:Transaction {dataset:$dataset})
WHERE coalesce(t.text, '') = ''
WITH t, collect(DISTINCT r.id) AS rollen
RETURN t.id AS tcode, size(rollen) AS rollenAnzahl, rollen
ORDER BY rollenAnzahl DESC;
