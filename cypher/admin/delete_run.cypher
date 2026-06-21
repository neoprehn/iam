// Loescht EINEN Auswertungslauf vollstaendig: Run-Knoten + dessen Findings (SoDConflict)
// inkl. Evidenz-Kanten (VIA_ROLE/VIA_PROFILE, falls vorhanden). MATCHES/PROVIDES sind
// lauf-uebergreifende Zwischenergebnisse (gehoeren zum Ruleset+Dataset, nicht zum einzelnen
// Lauf — siehe materialize_matches.cypher/explain_sod.cypher) und bleiben unberuehrt.
// Das Dataset selbst (Rohdaten) bleibt ebenfalls unberuehrt.
// Parameter: $runId.
MATCH (f:SoDConflict {runId:$runId}) DETACH DELETE f;

MATCH (run:Run {runId:$runId}) DETACH DELETE run;
