// Konsistenzcheck (Katalog E5): doppelte Knoten je fachlichem Business-Key (dataset + id) ueber
// User/Role/Profile/AuthObject/Transaction. REGRESSIONS-GUARD: die Unique-Constraints aus
// migrations/V001__constraints.cypher (synthetischer key = "<dataset>|<id>") verhindern echte
// Dubletten bereits auf DB-Ebene -- dieser Check sollte auf einer korrekt migrierten Instanz
// IMMER 0 liefern. Wertvoll als Absicherung, falls Constraints fehlen/uebersprungen wurden
// (z. B. frische Instanz ohne gelaufene neo4j-migrations) oder ein Import-/Restore-Pfad sie
// umgangen hat.
// Parameter: $dataset, $asOf (asOf ungenutzt, einheitliche Signatur).
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/duplicate_business_keys.cypher

// --- 1) Zusammenfassung je Label (-> KPI-Kacheln UI) ---
CALL {
  MATCH (n:User {dataset:$dataset}) RETURN 'User' AS label, n.id AS id
  UNION ALL
  MATCH (n:Role {dataset:$dataset}) RETURN 'Role' AS label, n.id AS id
  UNION ALL
  MATCH (n:Profile {dataset:$dataset}) RETURN 'Profile' AS label, n.id AS id
  UNION ALL
  MATCH (n:AuthObject {dataset:$dataset}) RETURN 'AuthObject' AS label, n.id AS id
  UNION ALL
  MATCH (n:Transaction {dataset:$dataset}) RETURN 'Transaction' AS label, n.id AS id
}
WITH label, id, count(*) AS anzahl
WHERE anzahl > 1
RETURN label, count(*) AS dublettenAnzahl
ORDER BY dublettenAnzahl DESC;

// --- 2) Detailliste ---
CALL {
  MATCH (n:User {dataset:$dataset}) RETURN 'User' AS label, n.id AS id
  UNION ALL
  MATCH (n:Role {dataset:$dataset}) RETURN 'Role' AS label, n.id AS id
  UNION ALL
  MATCH (n:Profile {dataset:$dataset}) RETURN 'Profile' AS label, n.id AS id
  UNION ALL
  MATCH (n:AuthObject {dataset:$dataset}) RETURN 'AuthObject' AS label, n.id AS id
  UNION ALL
  MATCH (n:Transaction {dataset:$dataset}) RETURN 'Transaction' AS label, n.id AS id
}
WITH label, id, count(*) AS anzahl
WHERE anzahl > 1
RETURN label, id, anzahl
ORDER BY label, id;
