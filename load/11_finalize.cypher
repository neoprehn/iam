// 11 — Abschluss: Subtyp-Labels nach allen Lade-Schritten setzen. Parameter: $dataset
// Composite = Rolle mit ausgehender CONTAINS-Kante; Single = alle übrigen Rollen
// (inkl. der erst spät über AGR_1251/AGR_USERS angelegten). addLabels ist idempotent.
MATCH (r:Role {dataset:$dataset}) WHERE (r)-[:CONTAINS]->()
CALL apoc.create.addLabels(r, ['Composite']) YIELD node
RETURN count(*) AS composite;

MATCH (r:Role {dataset:$dataset}) WHERE NOT (r)-[:CONTAINS]->()
CALL apoc.create.addLabels(r, ['Single']) YIELD node
RETURN count(*) AS single;
