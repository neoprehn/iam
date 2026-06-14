// Ruleset-Loader: normalisierte JSON (rules/<dir>/) -> Graph. Idempotent (MERGE auf key).
// Erzeugt die konstante Ruleset-Schicht (KEIN dataset): (:Query)/(:AuthReq)/(:SoDRule).
// Parameter: $dir (Ordner, z. B. 'KPMG_R3'), $ruleset (id, z. B. 'kpmg_r3').
// Aufruf: ... -P "dir => 'KPMG_R3'" -P "ruleset => 'kpmg_r3'" -f /cypher/ruleset/load_ruleset.cypher

CREATE CONSTRAINT query_key   IF NOT EXISTS FOR (q:Query)   REQUIRE q.key IS UNIQUE;
CREATE CONSTRAINT authreq_key IF NOT EXISTS FOR (r:AuthReq) REQUIRE r.key IS UNIQUE;
CREATE CONSTRAINT sodrule_key IF NOT EXISTS FOR (s:SoDRule) REQUIRE s.key IS UNIQUE;

// --- Queries (Funktionsbausteine) + AuthReq (Berechtigungsbedingungen) ---
CALL apoc.load.json('file:///rules/' + $dir + '/queries.json') YIELD value AS q
MERGE (query:Query {key: $ruleset + '|' + q.query})
  ON CREATE SET query.ruleset = $ruleset, query.id = q.query
  SET query.queryType = q.queryType, query.criticality = q.criticality,
      query.criticalityRank = q.criticalityRank, query.module = q.module,
      query.soxClassification = q.soxClassification,
      query.disregardTcode = coalesce(q.disregardTcode, false),
      query.tcodes = [t IN q.transactions WHERE coalesce(t.tcode,'') <> '' | t.tcode]
WITH query, q
UNWIND q.authorizations AS au
MERGE (ar:AuthReq {key: query.key + '|' + au.object + '|' + au.field})
  ON CREATE SET ar.ruleset = $ruleset, ar.object = au.object, ar.field = au.field
  SET ar.values = au.values, ar.andLogic = coalesce(au.andLogic, false)
MERGE (query)-[:REQUIRES]->(ar);

// --- SoD-Regeln + Variablen -> Query ---
CALL apoc.load.json('file:///rules/' + $dir + '/sod_rules.json') YIELD value AS s
MERGE (rule:SoDRule {key: $ruleset + '|' + s.sodRule})
  ON CREATE SET rule.ruleset = $ruleset, rule.id = s.sodRule
  SET rule.expression = s.expression, rule.reasonCode = s.reasonCode,
      rule.criticality = s.criticality, rule.criticalityRank = s.criticalityRank,
      rule.description = s.description
WITH rule, s
UNWIND keys(s.variables) AS var
MATCH (q:Query {key: $ruleset + '|' + s.variables[var]})
MERGE (rule)-[:USES {var: var}]->(q);
