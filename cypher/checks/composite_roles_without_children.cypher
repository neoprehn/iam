// Konsistenzcheck (Katalog R4): Sammelrolle ohne Einzelrollen (Composite ohne CONTAINS).
// REGRESSIONS-GUARD: das Label `Composite` wird in load/90_finalize.cypher genau dann gesetzt,
// wenn eine Rolle eine ausgehende CONTAINS-Kante hat -- eine Rolle mit dem Label Composite
// besitzt also per Konstruktion immer mindestens eine CONTAINS-Kante. Dieser Check sollte auf
// einer korrekt importierten Instanz IMMER 0 liefern; er sichert die Subtyp-Vergabe selbst ab
// (z. B. falls CONTAINS-Kanten nachtraeglich entfernt wurden, ohne das Label nachzuziehen).
// Parameter: $dataset, $asOf (asOf ungenutzt, einheitliche Signatur).
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/composite_roles_without_children.cypher

// --- 1) Zusammenfassung (-> KPI-Kacheln UI) ---
MATCH (r:Role:Composite {dataset:$dataset})
WHERE NOT EXISTS { (r)-[:CONTAINS]->(:Role) }
RETURN count(r) AS anzahl;

// --- 2) Detailliste ---
MATCH (r:Role:Composite {dataset:$dataset})
WHERE NOT EXISTS { (r)-[:CONTAINS]->(:Role) }
RETURN r.id AS rolle, coalesce(r.text, '') AS text
ORDER BY rolle;
