// Konsistenzcheck (Katalog R1): Rollen ohne generiertes Profil (AGR_DEFINE ohne AGR_PROF) --
// Rolle wurde nie generiert, traegt zur Laufzeit keine Berechtigung (Profil ist der eigentliche
// Berechtigungstraeger). Unfertige Rolle oder Karteileiche.
// Parameter: $dataset, $asOf (asOf ungenutzt, einheitliche Signatur).
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/roles_without_generated_profile.cypher

// --- 1) Zusammenfassung je Subtyp (-> KPI-Kacheln UI) ---
MATCH (r:Role {dataset:$dataset})
WHERE NOT EXISTS { (r)-[:HAS_PROFILE]->(:Profile) }
RETURN [l IN labels(r) WHERE l <> 'Role'] AS subtyp, count(r) AS anzahl
ORDER BY anzahl DESC;

// --- 2) Detailliste ---
MATCH (r:Role {dataset:$dataset})
WHERE NOT EXISTS { (r)-[:HAS_PROFILE]->(:Profile) }
RETURN r.id AS rolle, coalesce(r.text, '') AS text,
       [l IN labels(r) WHERE l <> 'Role'] AS subtyp,
       EXISTS { (r)-[:HAS_AUTH]->(:Authorization) } AS hatBerechtigungsdaten,
       count { (:User)-[:ASSIGNED_TO]->(r) } AS nutzerAnzahl
ORDER BY nutzerAnzahl DESC;
