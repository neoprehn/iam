// V004 — Unique-Constraints fuer die Import-Evidenz (ROADMAP.md "Import-Evidenz").
//
// Neue, abgeleitete Knotentypen (kein Rohdaten-Import, sondern vom Backend nach jedem
// erfolgreichen Import-Lauf geschrieben, s. backend/app.py _persist_import_evidence()):
//   (:Dataset)-[:HAS_IMPORT]->(:Import)-[:HAS_TABLE]->(:ImportTable)
//                                       -[:HAS_NODE_COUNT]->(:ImportNodeCount)
//                                       -[:HAS_EDGE_COUNT]->(:ImportEdgeCount)
// Ein (:Import)-Knoten je Import-Vorgang (nicht ueberschrieben -> Historie ueber Re-Importe),
// je mit fest gebauten synthetischen key-Properties (analog user_key/role_key/... aus V001).

CREATE CONSTRAINT import_key IF NOT EXISTS
FOR (i:Import) REQUIRE i.key IS UNIQUE;

CREATE CONSTRAINT import_table_key IF NOT EXISTS
FOR (t:ImportTable) REQUIRE t.key IS UNIQUE;

CREATE CONSTRAINT import_node_count_key IF NOT EXISTS
FOR (c:ImportNodeCount) REQUIRE c.key IS UNIQUE;

CREATE CONSTRAINT import_edge_count_key IF NOT EXISTS
FOR (c:ImportEdgeCount) REQUIRE c.key IS UNIQUE;
