// Konsistenzcheck (Katalog R11): Rollen mit genau einem Nutzer (zum Stichtag gueltige direkte
// Zuordnung) -- personengebundene Sonderrollen, oft manueller Wildwuchs am Rollenkonzept
// vorbei, Konsolidierungs-/Bereinigungskandidaten.
// Parameter: $dataset, $asOf.
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/single_user_roles.cypher

// --- 1) Zusammenfassung je Subtyp (-> KPI-Kacheln UI) ---
MATCH (r:Role {dataset:$dataset})<-[a:ASSIGNED_TO]-(u:User)
WHERE (a.validFrom IS NULL OR a.validFrom <= $asOf) AND (a.validTo IS NULL OR $asOf <= a.validTo)
WITH r, collect(DISTINCT u) AS nutzer
WHERE size(nutzer) = 1
RETURN [l IN labels(r) WHERE l <> 'Role'] AS subtyp, count(r) AS anzahl
ORDER BY anzahl DESC;

// --- 2) Detailliste ---
MATCH (r:Role {dataset:$dataset})<-[a:ASSIGNED_TO]-(u:User)
WHERE (a.validFrom IS NULL OR a.validFrom <= $asOf) AND (a.validTo IS NULL OR $asOf <= a.validTo)
WITH r, collect(DISTINCT u) AS nutzer
WHERE size(nutzer) = 1
RETURN r.id AS rolle, coalesce(r.text, '') AS text, nutzer[0].id AS user
ORDER BY rolle;
