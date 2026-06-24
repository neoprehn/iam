// Konsistenzcheck (Katalog R13): Rollen mit Intra-Rollen-SoD-Konflikt (built-in/conflicting-
// by-design, AE-11) -- die Rolle buendelt selbst zwei konfligierende Funktionen, jeder Traeger
// erbt den Konflikt unabhaengig von Kombination mit anderen Rollen.
// VORAUSSETZUNG (s. KONSISTENZCHECKS.md, Abschnitt "Konsistenzchecks fuer Rollen"): setzt die
// abgeleitete Snapshot-/Evidenz-Schicht aus Phase 3 voraus (SoDConflict.conflictType +
// VIA_ROLE, gesetzt durch cypher/sod/explain_sod.cypher NACH einem SoD-Lauf). Der generische
// Konsistenzcheck-Run-Endpoint kennt keine runId -- dieser Check verwendet daher automatisch
// den JUENGSTEN (:Run) des Datasets (ueber alle Rulesets). Wurde fuer diesen Lauf noch keine
// Evidenz berechnet (explain_sod nicht gelaufen), liefert der Check 0 Treffer statt eines
// Fehlers -- kein SoD-Lauf vorhanden bedeutet keine Aussage moeglich, nicht "keine Konflikte".
// Parameter: $dataset, $asOf (asOf ungenutzt, einheitliche Signatur -- der Lauf bringt seinen
// eigenen Stichtag/asOf mit).
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/roles_with_intra_conflict.cypher

// --- 1) Zusammenfassung (-> KPI-Kacheln UI) ---
OPTIONAL MATCH (run:Run {dataset:$dataset})
WITH run ORDER BY run.generatedAt DESC LIMIT 1
WITH run
MATCH (f:SoDConflict {dataset:$dataset, runId:run.runId, ruleset:run.ruleset, conflictType:'intra'})-[:VIA_ROLE]->(r:Role)
RETURN ('Lauf: ' + coalesce(run.title, run.runId)) AS lauf, count(DISTINCT r) AS anzahl;

// --- 2) Detailliste ---
OPTIONAL MATCH (run:Run {dataset:$dataset})
WITH run ORDER BY run.generatedAt DESC LIMIT 1
WITH run
MATCH (f:SoDConflict {dataset:$dataset, runId:run.runId, ruleset:run.ruleset, conflictType:'intra'})-[:VIA_ROLE]->(r:Role)
WITH r, collect(DISTINCT f.ruleId) AS regeln
RETURN r.id AS rolle, coalesce(r.text, '') AS text, regeln,
       count { (:User)-[:ASSIGNED_TO]->(r) } AS nutzerAnzahl
ORDER BY size(regeln) DESC;
