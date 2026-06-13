// V003 — Unique-Constraint auf Authorization.key (Korrektur zu V001/V002).
//
// V001/V002 gingen davon aus, Authorization brauche keinen fachlichen Key (Identität nur über
// Kanten). Diese Annahme hält in der Praxis NICHT: die Can-Do-Loader (08 AGR_1251, 18 UST10S,
// 19 UST12, 20 USR13) materialisieren jede Berechtigung über einen synthetischen
//   key = "<dataset>|<AGR_NAME|@PROF>|<OBJECT>|<AUTH>"
// und MERGE-/MATCH-en ausschliesslich darauf. Ohne Index darauf ist jeder Zugriff ein
// Full-Label-Scan ueber inzwischen >150k Authorization-Knoten -> die Importe 08/18/19/20
// liefen dadurch stundenlang (pro Zeile ein Scan).
//
// Fix: Single-Property-Unique-Constraint auf key (Community-tauglich), konsistent zu
// user_key/role_key/profile_key/authobject_key/transaction_key. Liefert das Backing-Index
// fuer die MERGE/MATCH-Lookups und erzwingt zugleich die Eindeutigkeit, auf die die Loader
// (MERGE-on-key) ohnehin bauen.
//
// Das in V002 angelegte authorization_dataset-Index (nur dataset) bleibt bestehen — es ist
// fuer dataset-weite Auswertungen weiterhin nuetzlich und stoert nicht.

CREATE CONSTRAINT authorization_key IF NOT EXISTS
FOR (a:Authorization) REQUIRE a.key IS UNIQUE;
