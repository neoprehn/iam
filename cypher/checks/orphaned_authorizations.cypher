// Konsistenzcheck (Katalog E7): verwaiste Authorization-Knoten ohne erreichbaren Rollen-/
// Profilpfad -- weder eine Rolle noch ein Profil zeigt (mehr) per HAS_AUTH auf den Knoten.
// Karteileiche aus Reorganisation/Teil-Import/-Bereinigung, verzerrt Auswertungen ueber alle
// Authorization-Knoten (z. B. Zaehlungen je Objekt). Unter dem aktuellen Loader (08/18 legen
// Authorization und HAS_AUTH immer gemeinsam an) sollte dies nur nach nachtraeglichen
// Teil-Loeschungen auftreten -- als Absicherung trotzdem sinnvoll (analog zu E5).
// Parameter: $dataset, $asOf (asOf ungenutzt, einheitliche Signatur).
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/orphaned_authorizations.cypher

// --- 1) Zusammenfassung je Objekt (-> KPI-Kacheln UI) ---
MATCH (a:Authorization {dataset:$dataset})
WHERE NOT EXISTS { (:Role)-[:HAS_AUTH]->(a) } AND NOT EXISTS { (:Profile)-[:HAS_AUTH]->(a) }
OPTIONAL MATCH (a)-[:FOR_OBJECT]->(o:AuthObject)
RETURN coalesce(o.id, '(ohne Objekt)') AS objekt, count(a) AS anzahl
ORDER BY anzahl DESC;

// --- 2) Detailliste ---
MATCH (a:Authorization {dataset:$dataset})
WHERE NOT EXISTS { (:Role)-[:HAS_AUTH]->(a) } AND NOT EXISTS { (:Profile)-[:HAS_AUTH]->(a) }
OPTIONAL MATCH (a)-[:FOR_OBJECT]->(o:AuthObject)
RETURN coalesce(o.id, '(ohne Objekt)') AS objekt, coalesce(a.role, '') AS rolle, coalesce(a.auth, '') AS auth
ORDER BY objekt;
