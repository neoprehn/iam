// Einzelberechtigungs-Check (Katalog A7): Ausreisser bei der Anzahl zugewiesener Rollen +
// direkt zugewiesener Profile je User -- Schwelle = 95. Perzentil der Verteilung ueber die
// gesamte Nutzerpopulation des Datasets (Festlegung, s. KONSISTENZCHECKS.md A7); adaptiv je
// Mandant statt fixer Schwellwert.
// Rollenzuweisungen (ASSIGNED_TO) stichtagsgefiltert auf $asOf (AE-07/08); direkte Profile
// (HAS_PROFILE) sind nicht datiert. "Anzahl" = Rollen + direkte Profile, ohne die ueber Rollen
// generierten Profile mitzuzaehlen (sonst doppelt erfasst, s. AE-09 zwei Zuweisungswege).
// Parameter: $dataset, $asOf.
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/role_profile_count_outliers.cypher

// --- 1) Zusammenfassung: Schwelle (95. Perzentil) + Anzahl Ausreisser (-> KPI-Kacheln UI) ---
MATCH (u:User {dataset:$dataset})
OPTIONAL MATCH (u)-[a:ASSIGNED_TO]->(r:Role)
WHERE (a.validFrom IS NULL OR a.validFrom <= $asOf) AND (a.validTo IS NULL OR $asOf <= a.validTo)
OPTIONAL MATCH (u)-[:HAS_PROFILE]->(p:Profile)
WITH u, count(DISTINCT r) + count(DISTINCT p) AS gesamt
WITH collect(gesamt) AS alle, percentileCont(gesamt, 0.95) AS schwelle
UNWIND alle AS g
WITH schwelle, count(CASE WHEN g > schwelle THEN 1 END) AS ausreisserAnzahl
RETURN round(schwelle, 1) AS schwelle95, ausreisserAnzahl AS anzahl;

// --- 2) Detailliste ---
MATCH (u:User {dataset:$dataset})
OPTIONAL MATCH (u)-[a:ASSIGNED_TO]->(r:Role)
WHERE (a.validFrom IS NULL OR a.validFrom <= $asOf) AND (a.validTo IS NULL OR $asOf <= a.validTo)
OPTIONAL MATCH (u)-[:HAS_PROFILE]->(p:Profile)
WITH u, count(DISTINCT r) AS rollen, count(DISTINCT p) AS profile,
     count(DISTINCT r) + count(DISTINCT p) AS gesamt
WITH collect({user: u, rollen: rollen, profile: profile, gesamt: gesamt}) AS alle,
     percentileCont(gesamt, 0.95) AS schwelle
UNWIND alle AS x
WITH x, schwelle
WHERE x.gesamt > schwelle
RETURN x.user.id AS user, coalesce(x.user.name, '') AS name,
       CASE WHEN 'Dialog' IN labels(x.user) THEN 'Dialog'
            WHEN 'System' IN labels(x.user) THEN 'System'
            WHEN 'Service' IN labels(x.user) THEN 'Service'
            WHEN 'Communication' IN labels(x.user) THEN 'Communication'
            WHEN 'Reference' IN labels(x.user) THEN 'Reference' ELSE '?' END AS typ,
       CASE WHEN 'Locked' IN labels(x.user) THEN 'gesperrt' ELSE 'aktiv' END AS status,
       x.rollen AS rollenAnzahl, x.profile AS profilAnzahl, x.gesamt AS gesamtAnzahl,
       schwelle AS perzentil95
ORDER BY x.gesamt DESC;
