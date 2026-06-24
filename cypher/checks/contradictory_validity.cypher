// Konsistenzcheck (Katalog D2): widerspruechliche Gueltigkeit auf Rollenzuweisungen
// (validFrom > validTo) -- Datenfehler aus Quelle oder Import, kann Stichtagsabfragen
// unbemerkt verzerren (eine solche Zuordnung ist nach AE-07/08-Logik IMMER ausgeschlossen,
// unabhaengig vom Stichtag, da kein $asOf je beide Bedingungen gleichzeitig erfuellen kann --
// faktisch tote Zuordnung).
// Parameter: $dataset, $asOf (asOf ungenutzt, einheitliche Signatur).
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/contradictory_validity.cypher

// --- 1) Zusammenfassung (-> KPI-Kacheln UI) ---
MATCH (u:User {dataset:$dataset})-[a:ASSIGNED_TO]->(r:Role {dataset:$dataset})
WHERE a.validFrom IS NOT NULL AND a.validTo IS NOT NULL AND a.validFrom > a.validTo
RETURN count(a) AS anzahl;

// --- 2) Detailliste ---
MATCH (u:User {dataset:$dataset})-[a:ASSIGNED_TO]->(r:Role {dataset:$dataset})
WHERE a.validFrom IS NOT NULL AND a.validTo IS NOT NULL AND a.validFrom > a.validTo
RETURN u.id AS user, r.id AS rolle, a.validFrom AS gueltigVon, a.validTo AS gueltigBis
ORDER BY user, rolle;
