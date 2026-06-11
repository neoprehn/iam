#!/bin/sh
# Setzt die Verbindungs-Flags (aus der Umgebung) und reicht das Subkommando durch.
# Aufruf: docker compose run --rm migrations [migrate|info|validate|...]
set -e
exec neo4j-migrations \
  --address="${NEO4J_ADDRESS}" \
  --username="${NEO4J_USERNAME}" \
  --password="${NEO4J_PASSWORD}" \
  --location="${NEO4J_MIGRATIONS_LOCATION}" \
  "$@"
