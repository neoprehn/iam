// 22 — AGR_1016 -> Generierungs-Status des/der Rollenprofile an :Role. Parameter: $dataset
// (Quelltabelle ist AGR_1016 mit Spalten GENERATED/PSTATE — NICHT AGR_1016B. Frueher wurde
//  faelschlich agr_1016b.csv gelesen -> die Datei fehlte im Extrakt, profileGenerated blieb bei
//  ALLEN Rollen NULL, was auch Konsistenzcheck D4 aushebelte. Fix: agr_1016.csv.)
// VERLUSTFREI/nicht-konzeptspezifisch: pro Rolle wird festgehalten, ob ALLE generierten Profile
// den Status GENERATED='X' tragen (profileGenerated) und welche PSTATE-Werte vorkommen
// (profileState — roh, ohne Interpretation). Eine Rolle kann mehrere Profile haben (COUNTER>1,
// Profil-Split bei >150 Objekten) — daher Aggregation je Rolle.
//
// Zweck: In Berechtigungskonzepten mit NICHT generierten/veralteten Rollen sind die in AGR_1251
// gepflegten Berechtigungen zur Laufzeit nicht (vollständig) aktiv. Das Finding selbst (welche
// Rollen betroffen sind) gehört in die Auswertung (Phase 3) — hier nur das Rohfaktum:
//   MATCH (r:Role) WHERE r.profileGenerated = false  // bzw. HAS_AUTH aber profileGenerated IS NULL
// Idempotent (Overwrite), MATCH (kein MERGE) — Rollen kommen aus 02/08.
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM $url AS row FIELDTERMINATOR '\t'
   WITH row WHERE coalesce(row.AGR_NAME,'') <> ''
   WITH row.AGR_NAME AS agr,
        (coalesce(row.GENERATED,'') = 'X') AS gen,
        coalesce(row.PSTATE,'') AS pstate
   WITH agr, collect(gen) AS gens, collect(DISTINCT pstate) AS states
   RETURN agr, all(g IN gens WHERE g) AS profileGenerated, [s IN states WHERE s <> ''] AS profileState",
  "MATCH (r:Role {key: $dataset + '|' + agr})
   SET r.profileGenerated = profileGenerated, r.profileState = profileState",
  {batchSize:2000, parallel:false, params:{url:'file:///'+$dataset+'/agr_1016.csv', dataset:$dataset}}
);
