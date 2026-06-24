// Konsistenzcheck (Katalog C5): Rollen ohne Beschreibung/Dokumentation (Role.text leer oder
// nicht gesetzt -- aus AGR_DEFINE.TEXT bzw. der sprachabhaengigen AGR_TEXTS-Quelle, s.
// load/02_roles.cypher/load/21_role_texts.cypher). Erschwert Re-Zertifizierung und
// Nachvollziehbarkeit "wofuer ist diese Rolle gedacht".
// Parameter: $dataset, $asOf (asOf ungenutzt, einheitliche Signatur).
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/roles_without_description.cypher

// --- 1) Zusammenfassung je Subtyp (-> KPI-Kacheln UI) ---
MATCH (r:Role {dataset:$dataset})
WHERE coalesce(r.text, '') = ''
RETURN [l IN labels(r) WHERE l <> 'Role'] AS subtyp, count(r) AS anzahl
ORDER BY anzahl DESC;

// --- 2) Detailliste ---
MATCH (r:Role {dataset:$dataset})
WHERE coalesce(r.text, '') = ''
RETURN r.id AS rolle, [l IN labels(r) WHERE l <> 'Role'] AS subtyp,
       count { (:User)-[:ASSIGNED_TO]->(r) } AS nutzerAnzahl
ORDER BY rolle;
