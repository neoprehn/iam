// Ruleset-Loader: normalisierte JSON (rules/<dir>/) -> Graph. Idempotent (MERGE auf key).
// Erzeugt die konstante Ruleset-Schicht (KEIN dataset): (:Query)/(:AuthReq)/(:SoDRule).
// Parameter: $dir (Ordner, z. B. 'KPMG_R3'), $ruleset (id, z. B. 'kpmg_r3').
// Aufruf: ... -P "dir => 'KPMG_R3'" -P "ruleset => 'kpmg_r3'" -f /cypher/ruleset/load_ruleset.cypher

CREATE CONSTRAINT query_key   IF NOT EXISTS FOR (q:Query)   REQUIRE q.key IS UNIQUE;
CREATE CONSTRAINT authreq_key IF NOT EXISTS FOR (r:AuthReq) REQUIRE r.key IS UNIQUE;
CREATE CONSTRAINT sodrule_key IF NOT EXISTS FOR (s:SoDRule) REQUIRE s.key IS UNIQUE;
CREATE CONSTRAINT clause_key  IF NOT EXISTS FOR (c:Clause)  REQUIRE c.key IS UNIQUE;

// --- Queries (Funktionsbausteine) + AuthReq (Berechtigungsbedingungen) ---
// Zwei Durchlaeufe in fester Reihenfolge: erst die Vendor-Datei (queries.json), danach das
// optionale Overlay (queries.custom.json) — eigene Metadaten-Edits an Vendor-Queries (gleiche
// id) ODER ganz neue, abgeleitete Queries (neue id). coalesce() im zweiten Durchlauf sorgt
// dafuer, dass im Overlay NICHT gesetzte Felder den bisherigen (Vendor-)Wert behalten statt ihn
// zu leeren — ein reiner Bezeichnungs-Edit loescht z. B. nicht queryType/tcodes. Overlay-Datei
// wird vom Backend bei Bedarf als [] angelegt (siehe ensure_custom_queries_file in app.py).
UNWIND ['queries.json', 'queries.custom.json'] AS qfile
CALL apoc.load.json('file:///rules/' + $dir + '/' + qfile) YIELD value AS q
MERGE (query:Query {key: $ruleset + '|' + q.query})
  ON CREATE SET query.ruleset = $ruleset, query.id = q.query
  SET query.description = coalesce(q.description, query.description),
      query.shortDescription = coalesce(q.shortDescription, query.shortDescription),
      query.queryType = coalesce(q.queryType, query.queryType),
      query.criticality = coalesce(q.criticality, query.criticality),
      query.criticalityRank = coalesce(q.criticalityRank, query.criticalityRank),
      query.module = coalesce(q.module, query.module),
      query.soxClassification = coalesce(q.soxClassification, query.soxClassification),
      query.disregardTcode = coalesce(q.disregardTcode, query.disregardTcode, false),
      query.tcodes = CASE WHEN q.transactions IS NULL THEN query.tcodes
                          ELSE [t IN q.transactions WHERE coalesce(t.tcode,'') <> '' | t.tcode] END
WITH query, q
UNWIND coalesce(q.authorizations, []) AS au
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
      rule.description = s.description, rule.shortDescription = s.shortDescription
WITH rule, s
UNWIND keys(s.variables) AS var
MATCH (q:Query {key: $ruleset + '|' + s.variables[var]})
MERGE (rule)-[:USES {var: var}]->(q);

// --- CNF-Klauseln: (:SoDRule)-[:HAS_CLAUSE]->(:Clause)-[:NEEDS]->(:Query) ---
// Ein User verletzt die Regel, wenn JEDE Klausel >=1 erfuellte (gematchte) Query enthaelt.
CALL apoc.load.json('file:///rules/' + $dir + '/sod_rules.json') YIELD value AS s
MATCH (rule:SoDRule {key: $ruleset + '|' + s.sodRule})
WITH rule, coalesce(s.clauses, []) AS clauses
UNWIND range(0, size(clauses) - 1) AS i
MERGE (cl:Clause {key: rule.key + '|c' + toString(i)})
  ON CREATE SET cl.ruleset = $ruleset, cl.idx = i
MERGE (rule)-[:HAS_CLAUSE]->(cl)
WITH cl, clauses[i] AS qids
UNWIND qids AS qid
MATCH (q:Query {key: $ruleset + '|' + qid})
MERGE (cl)-[:NEEDS]->(q);
