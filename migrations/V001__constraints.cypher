// V001 — Eindeutigkeits-Constraints (Neo4j Community: nur Single-Property-Unique).
//
// Versions-/Vergleichsdimension: jeder Extrakt ist ein `dataset` (z. B. "acme-2026-12-31").
// Da Community keine zusammengesetzten Keys (dataset,id) als Constraint kann, nutzen wir
// einen synthetischen Single-Property-Key `key = "<dataset>|<id>"`. Darauf wird ge-MERGE-t.
// Lookup/Join über (dataset, id) via Composite-Index in V002.
//
// Authorization hat bewusst KEINEN fachlichen Unique-Key (AE-03): Identität entsteht über
// die Kanten; Feldwerte liegen als Properties am Knoten.

// Registry der Extrakte (global eindeutig)
CREATE CONSTRAINT dataset_id IF NOT EXISTS
FOR (d:Dataset) REQUIRE d.id IS UNIQUE;

// Rohdaten-Knoten: eindeutig je (dataset,id) über synthetischen key
CREATE CONSTRAINT user_key IF NOT EXISTS
FOR (u:User) REQUIRE u.key IS UNIQUE;

CREATE CONSTRAINT role_key IF NOT EXISTS
FOR (r:Role) REQUIRE r.key IS UNIQUE;

CREATE CONSTRAINT profile_key IF NOT EXISTS
FOR (p:Profile) REQUIRE p.key IS UNIQUE;

CREATE CONSTRAINT authobject_key IF NOT EXISTS
FOR (o:AuthObject) REQUIRE o.key IS UNIQUE;

CREATE CONSTRAINT transaction_key IF NOT EXISTS
FOR (t:Transaction) REQUIRE t.key IS UNIQUE;
