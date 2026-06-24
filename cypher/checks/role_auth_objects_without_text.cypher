// Konsistenzcheck (Katalog E2): AGR_1251-Objekte (rollenseitige Berechtigungen), die im
// Stammdaten-Import unbekannt sind -- auf Rollen eingeschraenkter Spezialfall von E1
// (authorizations_without_object_text.cypher), s. dortige Begruendung zur Proxy-Operation-
// alisierung ueber fehlenden TOBJT-Text statt eines nicht vorhandenen TOBJ-Imports.
// Profilseitige Berechtigungen (UST10S/scope='profile') sind hier bewusst AUSGESCHLOSSEN
// (das waere der profilseitige Anteil von E1, nicht Gegenstand von E2 laut Katalog).
// Parameter: $dataset, $asOf (asOf ungenutzt, einheitliche Signatur).
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/role_auth_objects_without_text.cypher

// --- 1) Zusammenfassung: EINE Kachel (nicht je Objekt -- analog zu E1, auf Nutzer-Feedback
// "so viele Kacheln" zusammengefasst; Aufschluesselung je Objekt bleibt in der Detailliste) ---
MATCH (r:Role {dataset:$dataset})-[:HAS_AUTH]->(a:Authorization {dataset:$dataset})-[:FOR_OBJECT]->(o:AuthObject {dataset:$dataset})
WHERE coalesce(o.text, '') = ''
WITH count(DISTINCT o) AS objektAnzahl, count(DISTINCT r) AS rollenAnzahl
RETURN (objektAnzahl + ' betroffene Objekte') AS info, rollenAnzahl AS anzahl;

// --- 2) Detailliste ---
MATCH (r:Role {dataset:$dataset})-[:HAS_AUTH]->(a:Authorization {dataset:$dataset})-[:FOR_OBJECT]->(o:AuthObject {dataset:$dataset})
WHERE coalesce(o.text, '') = ''
RETURN o.id AS objekt, r.id AS rolle
ORDER BY objekt, rolle;
