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
//                  (z. B. nur Queries mit BUKRS, wenn die Variante auf BUKRS filtert); je Feld ein
//                  2-Ebenen-Kriterienbaum {op:'AND'|'OR', children:[...]} (ROADMAP 9.3) -- hier nur
//                  ueber keys($orgFilters) relevant, die Baumstruktur selbst wird nicht ausgewertet.
// Diese Vorauswahl auf org-relevante Queries wirkt sich automatisch auch auf evaluate_sod aus:
// eine Klausel, deren Kandidaten-Queries alle nicht org-relevant sind, bekommt fuer diesen Lauf
// gar keine MATCHES-Kante -> die Regel kann unter dieser Variante nicht verletzt werden ("nur
// die SoDs, die auf Grundlage der Einzel-Queries gehen" -- Nutzerfeedback).
// $queryScope steuert den Query-Umfang (Nutzer-Wunsch): 'all' (Default) -> JEDE Query des
// Rulesets, auch Einzelfilter ohne SoD-Klausel-Verwendung; 'sodOnly' -> nur die Queries, die
// tatsaechlich als Klausel-Baustein einer SoD-Regel dieses Rulesets dienen (schneller, aber die
// Einzelfilter-Ergebnisse/Uebersicht zeigen dann nur diese Teilmenge -- welche Queries das sind,
// ist ruleset-abhaengig, nicht fest). $queryScope greift nur, wenn WEDER $queryIds NOCH $sodRules
// gesetzt sind (s. u.) -- bisheriges Verhalten bleibt fuer alle Aufrufer ohne Katalog-Auswahl
// unveraendert.
//
// Katalog-Auswahl (Assistent Schritt "Scoping"), Prioritaet vor $queryScope:
//   $queryIds nicht leer  -> NUR diese Queries (explizite Einzelfilter-Auswahl, ignoriert
//                            $sodRules/$queryScope komplett).
//   sonst $sodRules nicht leer -> nur Queries, die ueber (q)<-[:NEEDS]-(:Clause)<-[:HAS_CLAUSE]-
//                            (:SoDRule) von EINER der gewaehlten Regeln erreichbar sind ("scoped
//                            materialize" -- nur deren Klausel-Queries statt aller SoD-Queries).
//   beide leer             -> bestehende $queryScope-Logik.
// Parameter: $ruleset, $dataset, $orgMode, $orgFilters, $queryScope, $queryIds, $sodRules.
MATCH (q:Query {ruleset:$ruleset})
WHERE (
    ( size($queryIds) > 0 AND q.id IN $queryIds )
    OR ( size($queryIds) = 0 AND size($sodRules) > 0 AND EXISTS {
      MATCH (q)<-[:NEEDS]-(:Clause {ruleset:$ruleset})<-[:HAS_CLAUSE]-(rule:SoDRule {ruleset:$ruleset})
      WHERE rule.id IN $sodRules
    } )
    OR ( size($queryIds) = 0 AND size($sodRules) = 0 AND
      ($queryScope = 'all' OR EXISTS { (q)<-[:NEEDS]-(:Clause {ruleset:$ruleset}) }) )
  )
  AND ( $orgMode = 'ignoreOrg' OR EXISTS {
    MATCH (q)-[:REQUIRES]->(ar)
    WHERE EXISTS { MATCH (:OrgField {dataset:$dataset, field:ar.field}) }
      AND ($orgMode = 'wildcardOnly' OR ar.field IN keys($orgFilters))
  } )
RETURN q.id AS id ORDER BY q.id;
