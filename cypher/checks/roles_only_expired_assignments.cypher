// Konsistenzcheck (Katalog R9): Rollen, die mindestens eine direkte Nutzerzuordnung haben,
// aber AUSSCHLIESSLICH abgelaufene (alle ASSIGNED_TO-Kanten liegen ausserhalb der Gueltigkeit
// zum Stichtag) -- faktisch ungenutzt, koennte aber bei einer Stichtagslogik ohne korrekten
// Gueltigkeitsfilter faelschlich als "zugewiesen" gezaehlt werden. Validiert zugleich die
// Stichtagslogik (analog zu D1/D3).
// Parameter: $dataset, $asOf.
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/roles_only_expired_assignments.cypher

// --- 1) Zusammenfassung (-> KPI-Kacheln UI) ---
MATCH (r:Role {dataset:$dataset})<-[a:ASSIGNED_TO]-(:User)
WITH r, collect(a) AS zuordnungen
WHERE size(zuordnungen) > 0
  AND all(x IN zuordnungen WHERE NOT ((x.validFrom IS NULL OR x.validFrom <= $asOf) AND (x.validTo IS NULL OR $asOf <= x.validTo)))
RETURN count(r) AS anzahl;

// --- 2) Detailliste ---
MATCH (r:Role {dataset:$dataset})<-[a:ASSIGNED_TO]-(:User)
WITH r, collect(a) AS zuordnungen
WHERE size(zuordnungen) > 0
  AND all(x IN zuordnungen WHERE NOT ((x.validFrom IS NULL OR x.validFrom <= $asOf) AND (x.validTo IS NULL OR $asOf <= x.validTo)))
RETURN r.id AS rolle, coalesce(r.text, '') AS text, size(zuordnungen) AS zuordnungsAnzahl,
       reduce(spaetestes = date('0001-01-01'), x IN zuordnungen | CASE WHEN x.validTo IS NOT NULL AND x.validTo > spaetestes THEN x.validTo ELSE spaetestes END) AS spaetesteGueltigkeit
ORDER BY spaetesteGueltigkeit DESC;
