// Konsistenzcheck (Katalog E1): Authorization-Knoten, deren Berechtigungsobjekt im
// Stammdaten-Import unbekannt ist. ANGEPASSTE OPERATIONALISIERUNG: der Loader importiert kein
// TOBJ-Stammdatentabelle, sondern erzeugt :AuthObject lazy direkt aus AGR_1251/UST10S/USOBT_C
// (FOR_OBJECT existiert dadurch IMMER -- der woertliche Check "Authorization ohne FOR_OBJECT"
// liefert mit diesem Loader strukturell 0 Treffer). Als praktikabler Ersatz fuer "nicht im
// TOBJ-Import": AuthObject OHNE Text aus TOBJT (Loader 13) -- deckt echte Faelle ab (z. B.
// kundeneigene Z-Objekte, die im Extrakt ohne Objekttext angekommen sind). Bewusste Abweichung
// von der woertlichen Katalog-Formulierung, s. KONSISTENZCHECKS.md.
// Umfasst BEIDE Auth-Quellen (Rolle UND Profil, s. E2 fuer den auf Rollen eingeschraenkten Fall).
// Parameter: $dataset, $asOf (asOf ungenutzt, einheitliche Signatur).
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/authorizations_without_object_text.cypher

// --- 1) Zusammenfassung: EINE Kachel (nicht je Objekt -- bei vielen betroffenen Objekten
// (z. B. 275 im Testdatenbestand) waeren sonst genauso viele KPI-Kacheln einzeln gerendert,
// auf Nutzer-Feedback "so viele Kacheln" zusammengefasst; Aufschluesselung je Objekt bleibt
// in der Detailliste) (-> KPI-Kacheln UI) ---
MATCH (a:Authorization {dataset:$dataset})-[:FOR_OBJECT]->(o:AuthObject {dataset:$dataset})
WHERE coalesce(o.text, '') = ''
WITH count(DISTINCT o) AS objektAnzahl, count(DISTINCT a) AS authAnzahl
RETURN (objektAnzahl + ' betroffene Objekte') AS info, authAnzahl AS anzahl;

// --- 2) Detailliste (je betroffenes Objekt, mit Trägeranzahl) ---
MATCH (a:Authorization {dataset:$dataset})-[:FOR_OBJECT]->(o:AuthObject {dataset:$dataset})
WHERE coalesce(o.text, '') = ''
WITH o, a,
     EXISTS { (:Role)-[:HAS_AUTH]->(a) } AS viaRole,
     EXISTS { (:Profile)-[:HAS_AUTH]->(a) } AS viaProfile
RETURN o.id AS objekt, count(DISTINCT a) AS authAnzahl,
       count(CASE WHEN viaRole THEN 1 END) AS ueberRollen,
       count(CASE WHEN viaProfile THEN 1 END) AS ueberProfile
ORDER BY authAnzahl DESC;
