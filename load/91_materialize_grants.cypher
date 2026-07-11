// 91 — GRANTS: geflachte Erreichbarkeit (Role|Profile) -> Authorization ueber die transitive
// Huelle CONTAINS/HAS_PROFILE (derselbe *0..4-Pfad, den explain_sod_one.cypher, role_can_do.cypher
// und materialize_matches_one.cypher heute je Aufruf neu traversieren). Einmal je Dataset
// materialisiert (ruleset-/run-unabhaengig, reine Struktur-Erreichbarkeit -- Feldwerte/AE-06-
// Normalisierung bleiben unveraendert am Authorization-Knoten). Evidenz-Perf (ROADMAP.md):
// explain_sod_one.cypher wird dadurch von variabler Pfadsuche zu einem einfachen Kanten-Lookup.
// Parameter: $dataset
//
// Idempotent: alte GRANTS-Kanten dieses Datasets zuerst loeschen (Re-Import/Resume-sicher).
CALL apoc.periodic.iterate(
  "MATCH (actor) WHERE actor.dataset = $dataset AND (actor:Role OR actor:Profile)
   MATCH (actor)-[r:GRANTS]->() RETURN r",
  "DELETE r",
  {batchSize:5000, parallel:false, params:{dataset:$dataset}}
);

CALL apoc.periodic.iterate(
  "MATCH (actor) WHERE actor.dataset = $dataset AND (actor:Role OR actor:Profile) RETURN actor",
  "MATCH (actor)-[:CONTAINS|HAS_PROFILE*0..4]->()-[:HAS_AUTH]->(auth:Authorization {dataset:$dataset})
   MERGE (actor)-[:GRANTS]->(auth)",
  {batchSize:200, parallel:false, params:{dataset:$dataset}}
);
