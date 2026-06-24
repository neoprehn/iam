// Konsistenzcheck (Katalog R12): "Mega"-Sammelrollen -- Composite-Rollen mit auffaellig vielen
// (transitiv) enthaltenen Einzelrollen. Schwelle = 95. Perzentil der Verteilung ueber alle
// Composite-Rollen des Datasets (analog zu A7 role_profile_count_outliers.cypher), adaptiv statt
// fixer Zahl.
// Parameter: $dataset, $asOf (asOf ungenutzt, einheitliche Signatur).
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/mega_composite_roles.cypher

// --- 1) Zusammenfassung: Schwelle (95. Perzentil) + Anzahl Ausreisser (-> KPI-Kacheln UI) ---
MATCH (r:Role:Composite {dataset:$dataset})
OPTIONAL MATCH (r)-[:CONTAINS*1..]->(child:Role:Single)
WITH r, count(DISTINCT child) AS einzelrollenAnzahl
WITH collect(einzelrollenAnzahl) AS alle, percentileCont(einzelrollenAnzahl, 0.95) AS schwelle
UNWIND alle AS g
WITH schwelle, count(CASE WHEN g > schwelle THEN 1 END) AS ausreisserAnzahl
RETURN round(schwelle, 1) AS schwelle95, ausreisserAnzahl AS anzahl;

// --- 2) Detailliste ---
MATCH (r:Role:Composite {dataset:$dataset})
OPTIONAL MATCH (r)-[:CONTAINS*1..]->(child:Role:Single)
WITH r, count(DISTINCT child) AS einzelrollenAnzahl
WITH collect({rolle: r, anzahl: einzelrollenAnzahl}) AS alle,
     percentileCont(einzelrollenAnzahl, 0.95) AS schwelle
UNWIND alle AS x
WITH x.rolle AS r, x.anzahl AS einzelrollenAnzahl, schwelle
WHERE einzelrollenAnzahl > schwelle
RETURN r.id AS rolle, coalesce(r.text, '') AS text, einzelrollenAnzahl,
       schwelle AS perzentil95,
       count { (:User)-[:ASSIGNED_TO]->(r) } AS nutzerAnzahl
ORDER BY einzelrollenAnzahl DESC;
