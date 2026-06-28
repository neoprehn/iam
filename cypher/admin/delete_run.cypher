// Loescht EINEN Auswertungslauf vollstaendig: Run-Knoten + dessen Findings (SoDConflict)
// inkl. Evidenz-Kanten (VIA_ROLE/VIA_PROFILE, falls vorhanden) + die MATCHES-Kanten dieses
// Laufs (MATCHES ist pro runId gescoped, siehe materialize_matches.cypher). PROVIDES bleibt
// bewusst unberuehrt — das ist lauf-uebergreifend (Fakt ueber Akteur+Auths, siehe
// explain_sod.cypher). Das Dataset selbst (Rohdaten) bleibt ebenfalls unberuehrt.
// Parameter: $runId.
MATCH (f:SoDConflict {runId:$runId}) DETACH DELETE f;

MATCH (:User)-[m:MATCHES {runId:$runId}]->() DELETE m;

MATCH (run:Run {runId:$runId}) DETACH DELETE run;
