// Sleeping-Check: User ohne Anmeldung in den letzten $sleepDays Tagen (oder nie angemeldet) —
// als Stichtag $asOf. Dormante Konten sind ein eigenes Audit-Finding und dienen zugleich als
// Filter/Flag fuer die SoD-Auswertung (userSleeping). Parameter: $dataset, $asOf, $sleepDays.
// Aufruf: ... -P "dataset=>'sachsenenergie'" -P "asOf=>date()" -P "sleepDays=>180"

MATCH (u:User {dataset:$dataset})
WHERE u.lastLogon IS NULL OR u.lastLogon < ($asOf - duration({days: $sleepDays}))
RETURN u.id AS user, coalesce(u.name,'') AS name,
       CASE WHEN 'Dialog' IN labels(u) THEN 'Dialog' WHEN 'System' IN labels(u) THEN 'System'
            WHEN 'Service' IN labels(u) THEN 'Service' WHEN 'Communication' IN labels(u) THEN 'Comm'
            WHEN 'Reference' IN labels(u) THEN 'Reference' ELSE '?' END AS typ,
       CASE WHEN 'Locked' IN labels(u) THEN 'gesperrt' ELSE 'aktiv' END AS status,
       u.lastLogon AS letzterLogon
ORDER BY (CASE WHEN 'Dialog' IN labels(u) AND NOT 'Locked' IN labels(u) THEN 0 ELSE 1 END), letzterLogon;
