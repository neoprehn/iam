// V002 — Indizes.
//
// Composite-Range-Indizes auf (dataset, id) für schnelle, dataset-gefilterte Lookups und
// für den Versionsvergleich (Join über id zwischen zwei dataset-Werten). Composite-Indizes
// sind in Community erlaubt (nur Composite-/Node-Key-CONSTRAINTS sind Enterprise).

CREATE INDEX user_lookup IF NOT EXISTS
FOR (u:User) ON (u.dataset, u.id);

CREATE INDEX role_lookup IF NOT EXISTS
FOR (r:Role) ON (r.dataset, r.id);

CREATE INDEX profile_lookup IF NOT EXISTS
FOR (p:Profile) ON (p.dataset, p.id);

CREATE INDEX authobject_lookup IF NOT EXISTS
FOR (o:AuthObject) ON (o.dataset, o.id);

CREATE INDEX transaction_lookup IF NOT EXISTS
FOR (t:Transaction) ON (t.dataset, t.id);

// Authorization ohne fachlichen Key (AE-03): nur dataset-Partitionierung indizieren.
CREATE INDEX authorization_dataset IF NOT EXISTS
FOR (a:Authorization) ON (a.dataset);

// Gültigkeit auf der Zuordnungskante (AE-07/AE-08): Range-Index über validFrom/validTo.
// Relationship-Property-Indizes sind in Community verfügbar.
CREATE INDEX assigned_to_validity IF NOT EXISTS
FOR ()-[r:ASSIGNED_TO]-() ON (r.validFrom, r.validTo);
