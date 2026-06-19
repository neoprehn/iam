// 00 — Dataset-Registry. Parameter: $dataset (z. B. 'acme').
MERGE (d:Dataset {id: $dataset})
  ON CREATE SET d.createdAt = datetime(), d.source = 'SE16'
RETURN d.id AS dataset;
