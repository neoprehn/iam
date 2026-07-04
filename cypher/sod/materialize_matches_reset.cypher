// Loescht die MATCHES-Kanten eines Laufs vor einem frischen (Nicht-Resume-)Start der
// materialize-Phase. MATCHES ist pro runId gescoped (nicht ruleset-weit geteilt -- sonst
// ueberschreiben sich parallele Varianten-Laeufe). Wird NUR beim frischen Phasenstart
// ausgefuehrt, nicht bei Resume (sonst waeren die bereits fertigen Queries wieder weg).
// Parameter: $ruleset, $dataset, $runId.
MATCH (:User {dataset:$dataset})-[m:MATCHES {ruleset:$ruleset, runId:$runId}]->() DELETE m;
