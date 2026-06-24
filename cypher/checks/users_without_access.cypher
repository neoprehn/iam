// Konsistenzcheck (Katalog C3): User ohne jegliche Berechtigung -- weder Rollenzuweisung
// (ASSIGNED_TO, unabhaengig von Gueltigkeit) noch direktes Profil (HAS_PROFILE). "Leere"
// Konten -- neu angelegt, ungenutzt oder fehlerhaft; Lizenz-/Aufraeumkandidaten.
// $status filtert nach aktiv/gesperrt -- 'alle' (Default) zeigt beide; Pill-Buttons in der UI
// ueber checks/B.json-Mechanismus (s. checks/SCHEMA.md "params").
// Parameter: $dataset, $asOf (ungenutzt, einheitliche Signatur), $status.
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -P "status=>'alle'" -f /cypher/checks/users_without_access.cypher

// --- 1) Zusammenfassung (-> KPI-Kacheln UI) ---
MATCH (u:User {dataset:$dataset})
WHERE NOT EXISTS { (u)-[:ASSIGNED_TO]->(:Role) } AND NOT EXISTS { (u)-[:HAS_PROFILE]->(:Profile) }
  AND ($status = 'alle' OR ($status = 'gesperrt') = ('Locked' IN labels(u)))
WITH count(u) AS anzahl, count(CASE WHEN 'Locked' IN labels(u) THEN 1 END) AS gesperrt
RETURN (gesperrt + ' davon gesperrt') AS info, anzahl;

// --- 2) Detailliste ---
MATCH (u:User {dataset:$dataset})
WHERE NOT EXISTS { (u)-[:ASSIGNED_TO]->(:Role) } AND NOT EXISTS { (u)-[:HAS_PROFILE]->(:Profile) }
  AND ($status = 'alle' OR ($status = 'gesperrt') = ('Locked' IN labels(u)))
RETURN u.id AS user, coalesce(u.name, '') AS name,
       CASE WHEN 'Dialog' IN labels(u) THEN 'Dialog'
            WHEN 'System' IN labels(u) THEN 'System'
            WHEN 'Service' IN labels(u) THEN 'Service'
            WHEN 'Communication' IN labels(u) THEN 'Communication'
            WHEN 'Reference' IN labels(u) THEN 'Reference' ELSE '?' END AS typ,
       CASE WHEN 'Locked' IN labels(u) THEN 'gesperrt' ELSE 'aktiv' END AS status,
       u.lastLogon AS letzterLogon
ORDER BY status, user;
