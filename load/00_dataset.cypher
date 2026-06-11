// 00 — Dataset-Registry. Parameter: $dataset (z. B. 'sachsenenergie').
MERGE (d:Dataset {id: $dataset})
  ON CREATE SET d.createdAt = datetime(), d.source = 'SE16'
RETURN d.id AS dataset;
