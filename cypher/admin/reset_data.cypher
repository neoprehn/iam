// Setzt die DATEN komplett zurueck: loescht ALLE Knoten AUSSER der Ruleset-Schicht
// (Query/SoDRule/AuthReq/Clause) — also alle Mandanten/Staende inkl. Dataset-Registry,
// Runs, Findings und Matches. Das Ruleset (konstante Logik, kein Mandantenwert) UND das
// Schema (Constraints/Indizes) bleiben erhalten -> direkt danach kann ein neues Set
// importiert und ohne Ruleset-Neuladen ausgewertet werden. Gebatcht.
// __Neo4jMigration: Versions-Tracking von neo4j-migrations bleibt ebenfalls erhalten,
// damit `docker compose run migrations` konsistent bleibt.
CALL apoc.periodic.iterate(
  "MATCH (n) WHERE NOT n:Query AND NOT n:SoDRule AND NOT n:AuthReq AND NOT n:Clause
    AND NOT n:__Neo4jMigration RETURN n",
  "DETACH DELETE n",
  {batchSize:10000, parallel:false}
);
