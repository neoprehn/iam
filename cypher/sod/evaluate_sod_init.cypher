// Einmaliger Init der evaluate-Phase (NUR beim frischen Phasenstart, nicht bei Resume -- sonst
// waeren bereits fertig ausgewertete Regeln wieder weg): Constraints, alte Findings dieses
// Laufs loeschen, Run-Knoten mit dem Scope des Laufs anlegen/aktualisieren.
// Parameter: $ruleset, $dataset, $runId, $title, $asOf, $userTypes, $excludeLocked, $sleepDays,
//            $minCriticalityRank, $orgMode, $orgFilters, $queryScope, $queryIds, $sodRules.
CREATE CONSTRAINT sodconflict_key IF NOT EXISTS FOR (f:SoDConflict) REQUIRE f.key IS UNIQUE;
CREATE CONSTRAINT run_key IF NOT EXISTS FOR (r:Run) REQUIRE r.key IS UNIQUE;

MATCH (f:SoDConflict {ruleset:$ruleset, dataset:$dataset, runId:$runId}) DETACH DELETE f;

// Dataset-uid am Run festhalten (Vergleichsanker fuer Lauf-Backup/Restore: erkennt, ob der
// Dataset-Name seit dem Lauf neu befuellt wurde). Aeltere Datasets ohne uid bekommen sie hier
// nachgetragen (lazy backfill), damit auch sie ab jetzt vergleichbar sind.
OPTIONAL MATCH (ds:Dataset {id:$dataset})
SET ds.uid = coalesce(ds.uid, randomUUID())
WITH ds

// Run-Knoten traegt den Scope des Laufs -> Can-Do-KPIs (z. B. SAP_ALL) koennen denselben
// Nutzertyp-/Sperr-Filter anwenden wie die SoD-Auswertung. queryScope/queryIds/sodRules werden
// u. a. von GET /queries, GET /sodrules und GET /queries/summary gelesen, um die
// Einzelfilter-/SoD-Auswahl (Sidebar-Filter + Uebersicht) auf genau das zu beschraenken, was in
// DIESEM Lauf tatsaechlich materialisiert/ausgewertet wurde (Katalog-Auswahl-Scope, s. ROADMAP).
MERGE (run:Run {key: $ruleset + '|' + $dataset + '|' + $runId})
  SET run.runId = $runId, run.title = $title, run.ruleset = $ruleset, run.dataset = $dataset, run.asOf = $asOf,
      run.userTypes = $userTypes, run.excludeLocked = $excludeLocked, run.sleepDays = $sleepDays,
      run.minCriticalityRank = $minCriticalityRank, run.generatedAt = datetime(),
      run.orgMode = $orgMode, run.orgFilters = apoc.convert.toJson($orgFilters),
      run.queryScope = $queryScope, run.queryIds = $queryIds, run.sodRules = $sodRules,
      run.datasetUid = ds.uid;
