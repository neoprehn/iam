// Konsistenzcheck (Katalog C2): verwaiste Profile -- ein Profile-Knoten ohne eine einzige
// Rolle, die es generiert/trägt (`(:Role)-[:HAS_PROFILE]->(:Profile)` fehlt). Inkonsistenz
// zwischen USR10/AGR_PROF: das Profil existiert (referenziert ueber UST04 direkte Zuweisung
// und/oder als Sub-/Sammelprofil in UST10C), aber keine Rolle steht mehr dahinter.
// ABGRENZUNG: SAP-Standardprofile wie SAP_ALL/SAP_NEW sind KEINE Rollenprofile (nie ueber eine
// Rolle generiert) und wuerden diesen Check sonst dauerhaft triggern -- daher ausgeschlossen
// ueber denselben Mechanismus wie A3 (Literal-Liste kritischer/bekannter Standardprofile,
// erweiterbar).
// Parameter: $dataset, $asOf (asOf ungenutzt, einheitliche Signatur).
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/orphaned_profiles.cypher

// --- 1) Zusammenfassung (-> KPI-Kacheln UI) ---
WITH ['SAP_ALL', 'SAP_NEW', 'S_A.SYSTEM', 'S_A.ADMIN', 'S_A.DEVELOP'] AS standardProfiles
MATCH (p:Profile {dataset:$dataset})
WHERE NOT p.id IN standardProfiles AND NOT EXISTS { (:Role)-[:HAS_PROFILE]->(p) }
RETURN count(p) AS anzahl;

// --- 2) Detailliste ---
WITH ['SAP_ALL', 'SAP_NEW', 'S_A.SYSTEM', 'S_A.ADMIN', 'S_A.DEVELOP'] AS standardProfiles
MATCH (p:Profile {dataset:$dataset})
WHERE NOT p.id IN standardProfiles AND NOT EXISTS { (:Role)-[:HAS_PROFILE]->(p) }
RETURN p.id AS profil, coalesce(p.text, '') AS text,
       [l IN labels(p) WHERE l <> 'Profile'] AS subtyp,
       count { (u:User)-[:HAS_PROFILE]->(p) } AS direkteUserAnzahl
ORDER BY profil;
