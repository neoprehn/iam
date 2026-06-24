// Konsistenzcheck (Katalog B2): bekannte SAP-Standard-/Default-User (SAP*, DDIC, SAPCPIC,
// EARLYWATCH, TMSADM) -- Status (aktiv/gesperrt) & letzter Logon. Liste als Literal gepflegt
// (kein optionaler Parameter -- s. Begruendung in critical_profiles.cypher). 'SAP*' deckt die
// SAP-Mustervarianten (z. B. 'SAP', 'SAP&...') per Praefix-Vergleich ab, die uebrigen Namen
// werden exakt verglichen.
// Parameter: $dataset, $asOf.
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/default_users.cypher

// --- 1) Zusammenfassung: Anzahl je Default-Konto-Muster (-> KPI-Kacheln UI) ---
WITH ['SAP*', 'DDIC', 'SAPCPIC', 'EARLYWATCH', 'TMSADM'] AS defaultPatterns
UNWIND defaultPatterns AS pattern
MATCH (u:User {dataset:$dataset})
WHERE (pattern ENDS WITH '*' AND u.id STARTS WITH left(pattern, size(pattern)-1))
   OR (NOT pattern ENDS WITH '*' AND u.id = pattern)
WITH pattern, count(u) AS anzahl, count(CASE WHEN 'Locked' IN labels(u) THEN 1 END) AS gesperrt
RETURN (pattern + ' (' + gesperrt + ' gesperrt)') AS befund, anzahl
ORDER BY anzahl DESC;

// --- 2) Detailliste ---
WITH ['SAP*', 'DDIC', 'SAPCPIC', 'EARLYWATCH', 'TMSADM'] AS defaultPatterns
UNWIND defaultPatterns AS pattern
MATCH (u:User {dataset:$dataset})
WHERE (pattern ENDS WITH '*' AND u.id STARTS WITH left(pattern, size(pattern)-1))
   OR (NOT pattern ENDS WITH '*' AND u.id = pattern)
RETURN u.id AS user, coalesce(u.name, '') AS name,
       CASE WHEN 'Dialog' IN labels(u) THEN 'Dialog'
            WHEN 'System' IN labels(u) THEN 'System'
            WHEN 'Service' IN labels(u) THEN 'Service'
            WHEN 'Communication' IN labels(u) THEN 'Communication'
            WHEN 'Reference' IN labels(u) THEN 'Reference' ELSE '?' END AS typ,
       CASE WHEN 'Locked' IN labels(u) THEN 'gesperrt' ELSE 'aktiv' END AS status,
       u.lastLogon AS letzterLogon
ORDER BY status, user;
