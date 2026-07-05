// Rollenzentrisch (Rollen-Detailseite, Reiter "SoD-Regeln"): welche SoD-Regeln kann die Rolle
// ALLEIN ausloesen (Intra-Rollen-Konflikt)? Eine Regel ist es, wenn JEDE ihrer Klauseln eine
// Query enthaelt, die die Rolle erfuellt (Query-Ids aus role_can_do.cypher).
// Parameter: $ruleset, $providedIds (Liste der von der Rolle erfuellten Query-Ids).
MATCH (rule:SoDRule {ruleset:$ruleset})
WHERE EXISTS { (rule)-[:HAS_CLAUSE]->() }
  AND all(cl IN [(rule)-[:HAS_CLAUSE]->(c) | c]
          WHERE EXISTS { MATCH (cl)-[:NEEDS]->(q:Query) WHERE q.id IN $providedIds })
RETURN rule.id AS id, coalesce(rule.shortDescription, rule.description, '') AS name,
       rule.criticality AS criticality
ORDER BY rule.id;
