// Konsistenzcheck (Katalog R17): redundante Rollen -- identische Berechtigungsmenge (gleiches
// Set referenzierter AuthObject-IDs ueber HAS_AUTH->FOR_OBJECT) unter verschiedenen Namen.
// FINGERPRINT-ANSATZ (skaliert auf grosse Rollenbestaende, kein paarweiser O(n^2)-Vergleich):
// pro Rolle wird die sortierte, eindeutige Liste der referenzierten Objekt-IDs zu einem
// String-Fingerprint zusammengefasst; Rollen mit identischem Fingerprint sind exakte Dubletten.
// GROBKOERNIG: vergleicht nur die Menge der BERECHTIGUNGSOBJEKTE, nicht die Feldwerte
// (ACTVT/Org-Werte etc.) innerhalb der Authorizations -- zwei Rollen mit identischem Objektset,
// aber unterschiedlichen Werten, waeren technisch keine echten Dubletten; das macht den Check
// bewusst als ERSTE GROBE SICHTUNG nuetzlich (Kandidatenliste), kein abschliessender Beweis.
// Nur Rollen mit mindestens einem Objekt (leere Rollen sind trivial "gleich" und nicht gemeint).
// Parameter: $dataset, $asOf (asOf ungenutzt, einheitliche Signatur).
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/redundant_roles.cypher

// --- 1) Zusammenfassung: Anzahl Dubletten-Gruppen + betroffene Rollen (-> KPI-Kacheln UI) ---
MATCH (r:Role {dataset:$dataset})-[:HAS_AUTH]->(:Authorization)-[:FOR_OBJECT]->(o:AuthObject)
WITH r, apoc.coll.sort(collect(DISTINCT o.id)) AS objekte
WHERE size(objekte) > 0
WITH apoc.text.join(objekte, ',') AS fingerprint, collect(r) AS rollen
WHERE size(rollen) > 1
RETURN count(*) AS gruppenAnzahl, sum(size(rollen)) AS rollenAnzahl;

// --- 2) Detailliste ---
MATCH (r:Role {dataset:$dataset})-[:HAS_AUTH]->(:Authorization)-[:FOR_OBJECT]->(o:AuthObject)
WITH r, apoc.coll.sort(collect(DISTINCT o.id)) AS objekte
WHERE size(objekte) > 0
WITH apoc.text.join(objekte, ',') AS fingerprint, objekte, collect(r) AS rollen
WHERE size(rollen) > 1
RETURN [x IN rollen | x.id] AS rollen, size(objekte) AS objektAnzahl
ORDER BY size(rollen) DESC, objektAnzahl DESC;
