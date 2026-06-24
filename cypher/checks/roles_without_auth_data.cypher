// Konsistenzcheck (Katalog R2): Rollen ohne Berechtigungsdaten (keine AGR_1251 -> keine
// HAS_AUTH-Kante) -- Menuerolle mit TCodes im Menue, aber nichts an Objekten/Feldern gepflegt.
// Design-Fehler oder bewusste reine "Navigationsrolle" (TCode-Sammlung ohne eigene Rechte,
// z. B. wenn die eigentliche Berechtigung ueber eine andere Rolle/ein Profil kommt).
// Parameter: $dataset, $asOf (asOf ungenutzt, einheitliche Signatur).
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/roles_without_auth_data.cypher

// --- 1) Zusammenfassung je Subtyp (-> KPI-Kacheln UI) ---
MATCH (r:Role {dataset:$dataset})
WHERE NOT EXISTS { (r)-[:HAS_AUTH]->(:Authorization) }
RETURN [l IN labels(r) WHERE l <> 'Role'] AS subtyp, count(r) AS anzahl
ORDER BY anzahl DESC;

// --- 2) Detailliste ---
MATCH (r:Role {dataset:$dataset})
WHERE NOT EXISTS { (r)-[:HAS_AUTH]->(:Authorization) }
RETURN r.id AS rolle, coalesce(r.text, '') AS text,
       [l IN labels(r) WHERE l <> 'Role'] AS subtyp,
       EXISTS { (r)-[:HAS_MENU]->(:Transaction) } AS hatMenue,
       count { (:User)-[:ASSIGNED_TO]->(r) } AS nutzerAnzahl
ORDER BY nutzerAnzahl DESC;
