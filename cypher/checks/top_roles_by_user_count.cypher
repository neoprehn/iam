// Konsistenzcheck (Katalog R10, Analytik/Ranking): Top-20 Rollen nach Anzahl direkter,
// zum Stichtag gueltiger Nutzerzuordnungen -- reichweitenstaerkste Rollen, hier wirkt jede
// Aenderung am breitesten (Priorisierung fuer Review/Re-Zertifizierung). Top-N als Literal
// (20) gepflegt, kein Pass/Fail-Befund.
// Parameter: $dataset, $asOf.
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/top_roles_by_user_count.cypher

// --- 1) Zusammenfassung: Top-5 (-> KPI-Kacheln UI) ---
MATCH (r:Role {dataset:$dataset})<-[a:ASSIGNED_TO]-(u:User)
WHERE (a.validFrom IS NULL OR a.validFrom <= $asOf) AND (a.validTo IS NULL OR $asOf <= a.validTo)
WITH r, count(DISTINCT u) AS nutzerAnzahl
ORDER BY nutzerAnzahl DESC
LIMIT 5
RETURN r.id AS rolle, nutzerAnzahl;

// --- 2) Detailliste: Top-20 ---
MATCH (r:Role {dataset:$dataset})<-[a:ASSIGNED_TO]-(u:User)
WHERE (a.validFrom IS NULL OR a.validFrom <= $asOf) AND (a.validTo IS NULL OR $asOf <= a.validTo)
WITH r, count(DISTINCT u) AS nutzerAnzahl
ORDER BY nutzerAnzahl DESC
LIMIT 20
RETURN r.id AS rolle, coalesce(r.text, '') AS text,
       [l IN labels(r) WHERE l <> 'Role'] AS subtyp, nutzerAnzahl;
