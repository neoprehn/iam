// 99 — Importvalidierung: Zähler je Knoten-/Kantentyp für $dataset.
MATCH (n {dataset: $dataset})
WITH [l IN labels(n) WHERE l <> 'Dataset'] AS lbls
RETURN lbls AS labels, count(*) AS knoten
ORDER BY knoten DESC;

MATCH (a {dataset: $dataset})-[r]->(b {dataset: $dataset})
RETURN type(r) AS kante, count(*) AS anzahl
ORDER BY anzahl DESC;
