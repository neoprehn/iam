// Konsistenzcheck (Katalog D1): zum Stichtag bereits abgelaufene Rollenzuweisungen
// (ASSIGNED_TO.validTo < $asOf) -- als eigenstaendige, auditierbare Liste neben der eigentlichen
// Auswertung. EINORDNUNG: alle Auswerte-Abfragen (query_match/materialize_matches/evaluate_sod)
// wenden das Stichtagspraedikat `(validFrom IS NULL OR validFrom <= $asOf) AND (validTo IS NULL
// OR $asOf <= validTo)` konsistent an (AE-07/08) -- dieser Check findet daher keinen eigenen
// Logikfehler im Graph, sondern macht die zugrunde liegende Datenbasis SICHTBAR und PRUEFBAR:
// jede hier gelistete Zuordnung darf in keinem Can-Do-/SoD-Treffer zum selben Stichtag
// auftauchen. Dient als manuelle Stichprobe/Validierungsbasis fuer die Stichtagslogik, nicht
// als automatischer Fehlerbeweis.
// Parameter: $dataset, $asOf.
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/expired_assignments_audit.cypher

// --- 1) Zusammenfassung: Anzahl abgelaufener vs. aller Zuordnungen (-> KPI-Kacheln UI) ---
MATCH (u:User {dataset:$dataset})-[a:ASSIGNED_TO]->(r:Role {dataset:$dataset})
WITH count(a) AS gesamt,
     count(CASE WHEN a.validTo IS NOT NULL AND a.validTo < $asOf THEN 1 END) AS abgelaufen
RETURN gesamt, abgelaufen;

// --- 2) Detailliste (abgelaufene Zuordnungen) ---
MATCH (u:User {dataset:$dataset})-[a:ASSIGNED_TO]->(r:Role {dataset:$dataset})
WHERE a.validTo IS NOT NULL AND a.validTo < $asOf
RETURN u.id AS user, r.id AS rolle, a.validFrom AS gueltigVon, a.validTo AS gueltigBis
ORDER BY a.validTo DESC;
