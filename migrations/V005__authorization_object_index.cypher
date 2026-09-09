// V005 — Composite-Index Authorization(dataset, object).
//
// Nutzer-Fund (2026-09-09): der neue PFCG-Vorschlags-Endpoint (/admin/pfcg-proposal,
// _pfcg_real_values) brauchte je Feld ~2-3s -- bei ~8-10 Feldern je TCode insgesamt >20s fuer
// einen einzelnen interaktiven Dialog-Aufruf. Ursache war NICHT dieser Index, sondern die
// Cypher-Abfrage selbst (traversierte von ALLEN Role-Knoten aus, s. Fix in backend/app.py) --
// aber beim Debuggen fiel auf, dass Authorization NUR ueber (dataset) indiziert ist (V002/V003),
// nicht ueber (dataset, object). Dasselbe Zugriffsmuster "(a:Authorization {dataset:$d,
// object:$o})" existiert bereits in mehreren Stellen (_SATISFIED_BY_CYPHER,
// admin_org_field_values, _pfcg_real_values) -- ein Composite-Index darauf ist fuer alle drei
// gleichermassen nuetzlich, unabhaengig vom eigentlichen Root-Cause-Fix.
//
// In einem getesteten, grossen Datensatz stand einer sehr hohen Gesamtzahl an Role-Knoten eine
// um Groessenordnungen kleinere Menge an Authorization-Knoten fuer EIN konkretes Objekt
// gegenueber -- ein objektgefiltertes Lookup ist entsprechend viel kleiner als ein Role-weiter Scan.

CREATE INDEX authorization_object IF NOT EXISTS
FOR (a:Authorization) ON (a.dataset, a.object);
