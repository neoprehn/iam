// 24 — Org-Level-Platzhalter auflösen. Parameter: $dataset
// Org-pflichtige (abgeleitete) Rollen tragen in ihren Auths einen Platzhalter im Org-Feld
// (z. B. f_BUKRS = ['$BUKRS']); die echten Werte stehen an der OWNENDEN Rolle als
// org_<Platzhalter> (AGR_1252, Skript 16). Hier werden die Platzhalterwerte in f_<orgfeld>
// durch die Rollenwerte ersetzt (literale Werte bleiben). Nur Org-Felder (:OrgField), nur
// role-eigene Auths. Idempotent (resolvt nur, was noch '$' trägt). Default-Auswertung („egal")
// bleibt unberührt; der Org-Filter (filtered) sieht danach echte Werte.
MATCH (of:OrgField {dataset:$dataset})
WITH collect(of.field) AS orgFields
CALL apoc.periodic.iterate(
  "MATCH (r:Role {dataset:$dataset})-[:HAS_AUTH]->(a:Authorization {dataset:$dataset})
   WHERE any(k IN keys(a) WHERE k STARTS WITH 'f_' AND substring(k,2) IN $orgFields
             AND any(v IN a[k] WHERE v STARTS WITH '$'))
   RETURN r, a",
  "WITH r, a, [k IN keys(a) WHERE k STARTS WITH 'f_' AND substring(k,2) IN $orgFields
              AND any(v IN a[k] WHERE v STARTS WITH '$')] AS phKeys
   UNWIND phKeys AS fk
   WITH a, fk, reduce(acc=[], v IN apoc.any.property(a, fk) |
          acc + CASE WHEN v STARTS WITH '$' THEN coalesce(apoc.any.property(r, 'org_' + v), [])
                     ELSE [v] END) AS resolved
   CALL apoc.create.setProperty(a, fk, apoc.coll.toSet(resolved)) YIELD node
   RETURN count(*)",
  {batchSize:2000, parallel:false, params:{dataset:$dataset, orgFields:orgFields}}
) YIELD batches, total, committedOperations, failedOperations, errorMessages
RETURN batches, total, committedOperations, failedOperations, errorMessages;
