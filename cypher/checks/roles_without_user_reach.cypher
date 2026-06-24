// Konsistenzcheck (Katalog R8): Rollen ohne jegliche Nutzerzuordnung -- weder direkt
// zugewiesen (ASSIGNED_TO, gueltig am Stichtag) noch ueber eine (verschachtelte) Sammelrolle
// erreichbar, die selbst gueltig zugewiesen ist. Tote Rollen -> Aufraeumkandidaten.
// Reichweite ueber CONTAINS rueckwaerts (Einzelrolle <- Sammelrolle <- ggf. weitere Sammelrolle),
// beliebige Tiefe; Gueltigkeit zaehlt nur auf der ASSIGNED_TO-Kante (AE-07/08, CONTAINS trägt
// keine eigene Gueltigkeit).
// Parameter: $dataset, $asOf.
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/roles_without_user_reach.cypher

// --- 1) Zusammenfassung je Subtyp (-> KPI-Kacheln UI) ---
MATCH (r:Role {dataset:$dataset})
WHERE NOT EXISTS {
  MATCH (u:User)-[a:ASSIGNED_TO]->(parent:Role)-[:CONTAINS*0..]->(r)
  WHERE (a.validFrom IS NULL OR a.validFrom <= $asOf) AND (a.validTo IS NULL OR $asOf <= a.validTo)
}
RETURN [l IN labels(r) WHERE l <> 'Role'] AS subtyp, count(r) AS anzahl
ORDER BY anzahl DESC;

// --- 2) Detailliste ---
MATCH (r:Role {dataset:$dataset})
WHERE NOT EXISTS {
  MATCH (u:User)-[a:ASSIGNED_TO]->(parent:Role)-[:CONTAINS*0..]->(r)
  WHERE (a.validFrom IS NULL OR a.validFrom <= $asOf) AND (a.validTo IS NULL OR $asOf <= a.validTo)
}
RETURN r.id AS rolle, coalesce(r.text, '') AS text,
       [l IN labels(r) WHERE l <> 'Role'] AS subtyp
ORDER BY rolle;
