// 00 — Dataset-Registry. Parameter: $dataset (z. B. 'acme'), $asOf (Stichtag, Neo4j-date).
// d.uid wird einmalig bei Erst-Anlage vergeben und bleibt ueber erneute Re-Importe desselben
// Datasets stabil; nur ein vollstaendiges Loeschen+Neuanlegen (Bereinigen) unter demselben Namen
// erzeugt eine neue uid. Damit erkennbar: ein Lauf-Backup, das gegen einen anderen Datenstand
// erstellt wurde, auch wenn der Dataset-Name identisch ist (siehe runs/backup-Restore-Check).
//
// d.asOf ist der Stichtag des Datenstands (= Downloaddatum der SAP-Extrakte) -- KEIN
// Auswertungs-/Lauf-Parameter mehr. Wird bei Erst-Import gesetzt (ON CREATE) und bleibt ueber
// Re-Importe stabil; eine bewusste Korrektur laeuft ausschliesslich ueber den eigenen Endpoint
// PUT /datasets/{id}/asof (globale Variable, kein Filter je Lauf/Check -- s. ROADMAP/Backend
// _dataset_asof()).
MERGE (d:Dataset {id: $dataset})
  ON CREATE SET d.createdAt = datetime(), d.source = 'SE16', d.uid = randomUUID(), d.asOf = $asOf
RETURN d.id AS dataset, d.uid AS uid, d.asOf AS asOf;
