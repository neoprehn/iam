// Kandidaten-Liste fuer die materialize-Phase (Zwischenergebnis "wer kann was":
// (:User)-[:MATCHES]->(:Query)): welche SoD-relevanten Queries ueberhaupt betrachtet werden
// muessen. Treibt die Python-Schleife in _run_phase() -- eine Zeile hier = eine
// Fortschritts-/Checkpoint-Einheit, abgearbeitet von materialize_matches_one.cypher.
//
// Org-Felder (:OrgField aus USORG) je nach $orgMode:
//   ignoreOrg   -> egal (Default; "kann der User die Funktion ueberhaupt") -> ALLE Queries.
//   wildcardOnly-> nur Queries, die UEBERHAUPT ein Org-Feld referenzieren (sonst gibt es keine
//                  "uebergreifend"-Frage zu stellen) UND nur wenn der Auth-Wert dort echtes '*'
//                  traegt (Vollbereich).
//   filtered    -> nur Queries, die eines der in $orgFilters gewaehlten Org-Felder referenzieren
//                  (z. B. nur Queries mit BUKRS, wenn die Variante auf BUKRS filtert); je Feld
//                  eine Bedingung {op: AND|OR|RANGE, values/from/to}.
// Diese Vorauswahl auf org-relevante Queries wirkt sich automatisch auch auf evaluate_sod aus:
// eine Klausel, deren Kandidaten-Queries alle nicht org-relevant sind, bekommt fuer diesen Lauf
// gar keine MATCHES-Kante -> die Regel kann unter dieser Variante nicht verletzt werden ("nur
// die SoDs, die auf Grundlage der Einzel-Queries gehen" -- Nutzerfeedback).
// Parameter: $ruleset, $dataset, $orgMode, $orgFilters.
MATCH (q:Query {ruleset:$ruleset}) WHERE EXISTS { (q)<-[:NEEDS]-(:Clause {ruleset:$ruleset}) }
  AND ( $orgMode = 'ignoreOrg' OR EXISTS {
    MATCH (q)-[:REQUIRES]->(ar)
    WHERE EXISTS { MATCH (:OrgField {dataset:$dataset, field:ar.field}) }
      AND ($orgMode = 'wildcardOnly' OR ar.field IN keys($orgFilters))
  } )
RETURN q.id AS id ORDER BY q.id;
