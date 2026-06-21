// 00 — Dataset-Registry. Parameter: $dataset (z. B. 'acme').
// d.uid wird einmalig bei Erst-Anlage vergeben und bleibt ueber erneute Re-Importe desselben
// Datasets stabil; nur ein vollstaendiges Loeschen+Neuanlegen (Bereinigen) unter demselben Namen
// erzeugt eine neue uid. Damit erkennbar: ein Lauf-Backup, das gegen einen anderen Datenstand
// erstellt wurde, auch wenn der Dataset-Name identisch ist (siehe runs/backup-Restore-Check).
MERGE (d:Dataset {id: $dataset})
  ON CREATE SET d.createdAt = datetime(), d.source = 'SE16', d.uid = randomUUID()
RETURN d.id AS dataset, d.uid AS uid;
