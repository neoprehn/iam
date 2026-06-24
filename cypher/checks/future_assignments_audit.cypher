// Konsistenzcheck (Katalog D3): noch nicht wirksame, zukuenftige Rollenzuweisungen
// (ASSIGNED_TO.validFrom > $asOf) -- duerfen am aktuellen Stichtag nicht zaehlen. Wie D1
// (expired_assignments_audit.cypher) eine auditierbare Liste der Gegenprobe, kein eigener
// Logikfehlernachweis: jede hier gelistete Zuordnung darf in keinem Can-Do-/SoD-Treffer zum
// selben Stichtag auftauchen.
// Parameter: $dataset, $asOf.
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/future_assignments_audit.cypher

// --- 1) Zusammenfassung (-> KPI-Kacheln UI) ---
MATCH (u:User {dataset:$dataset})-[a:ASSIGNED_TO]->(r:Role {dataset:$dataset})
WHERE a.validFrom IS NOT NULL AND a.validFrom > $asOf
RETURN count(a) AS anzahl;

// --- 2) Detailliste ---
MATCH (u:User {dataset:$dataset})-[a:ASSIGNED_TO]->(r:Role {dataset:$dataset})
WHERE a.validFrom IS NOT NULL AND a.validFrom > $asOf
RETURN u.id AS user, r.id AS rolle, a.validFrom AS gueltigVon, a.validTo AS gueltigBis
ORDER BY a.validFrom;
