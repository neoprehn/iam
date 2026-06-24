// Konsistenzcheck (Katalog R18): stark ueberlappende Rollen (grosser gemeinsamer
// Berechtigungsanteil, aber nicht identisch -- fuer echte Dubletten s. R17). Misst Ueberlappung
// als Jaccard-Aehnlichkeit der referenzierten AuthObject-Mengen (>= 0.8 als Schwelle, Literal).
// BEWUSST BEGRENZTER UMFANG (v1, Prio Niedrig): ein vollstaendiger paarweiser Vergleich ueber
// ALLE Rollen ist O(n^2) und bei mehreren tausend Rollen in reinem Cypher nicht praktikabel.
// Eingeschraenkt auf Rollen mit einer KLEINEN, nicht-trivialen Objektmenge (2..15 Objekte) --
// deckt die typischen, gut vergleichbaren Faelle ab (kleine, fokussierte Rollen), nicht aber
// grosse/Sammelrollen. Bei Bedarf spaeter durch einen aussergraph-basierten Ansatz (z. B.
// MinHash/LSH) fuer den vollen Rollenbestand ersetzen.
// Parameter: $dataset, $asOf (asOf ungenutzt, einheitliche Signatur).
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/overlapping_roles.cypher

// --- 1) Zusammenfassung: Anzahl ueberlappender Paare (-> KPI-Kacheln UI) ---
MATCH (r:Role {dataset:$dataset})-[:HAS_AUTH]->(:Authorization)-[:FOR_OBJECT]->(o:AuthObject)
WITH r, collect(DISTINCT o.id) AS objekte
WHERE size(objekte) >= 2 AND size(objekte) <= 15
WITH collect({rolle: r.id, objekte: objekte}) AS kandidaten
UNWIND range(0, size(kandidaten)-2) AS i
UNWIND range(i+1, size(kandidaten)-1) AS j
WITH kandidaten[i] AS a, kandidaten[j] AS b
WITH a, b, apoc.coll.intersection(a.objekte, b.objekte) AS gemeinsam, apoc.coll.union(a.objekte, b.objekte) AS vereinigt
WITH a, b, size(gemeinsam) AS schnitt, size(vereinigt) AS union_
WHERE schnitt * 1.0 / union_ >= 0.8 AND NOT (schnitt = size(a.objekte) AND schnitt = size(b.objekte))
RETURN count(*) AS paarAnzahl;

// --- 2) Detailliste ---
MATCH (r:Role {dataset:$dataset})-[:HAS_AUTH]->(:Authorization)-[:FOR_OBJECT]->(o:AuthObject)
WITH r, collect(DISTINCT o.id) AS objekte
WHERE size(objekte) >= 2 AND size(objekte) <= 15
WITH collect({rolle: r.id, objekte: objekte}) AS kandidaten
UNWIND range(0, size(kandidaten)-2) AS i
UNWIND range(i+1, size(kandidaten)-1) AS j
WITH kandidaten[i] AS a, kandidaten[j] AS b
WITH a, b, apoc.coll.intersection(a.objekte, b.objekte) AS gemeinsam, apoc.coll.union(a.objekte, b.objekte) AS vereinigt
WITH a, b, size(gemeinsam) AS schnitt, size(vereinigt) AS union_
WHERE schnitt * 1.0 / union_ >= 0.8 AND NOT (schnitt = size(a.objekte) AND schnitt = size(b.objekte))
RETURN a.rolle AS rolleA, b.rolle AS rolleB, round(schnitt * 1.0 / union_, 2) AS jaccard,
       schnitt AS gemeinsameObjekte
ORDER BY jaccard DESC;
