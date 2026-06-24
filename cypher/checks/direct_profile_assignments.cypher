// Konsistenzcheck (Katalog C1): User mit direkt zugewiesenen Profilen (UST04 -> HAS_PROFILE
// User->Profile), die NICHT durch eine aktuell gueltige Rollenzuweisung erklaerbar sind --
// umgeht die PFCG-Pflege, schwer wartbar, oft Altlast aus R/3-Zeiten oder manuelle Direktvergabe.
//
// WICHTIGE KORREKTUR (auf Nutzer-Rueckfrage "warum sind da T-* Profile in der Liste, sind das
// nicht immer generierte Profile?"): UST04 enthaelt in der Praxis NICHT nur "echte" Direkt-
// vergaben, sondern auch generierte Rollenprofile (T-*), die SAP beim "Benutzerabgleich" in
// UST04 zurueckschreibt -- UST04 ist die vom Kernel tatsaechlich ausgewertete, EFFEKTIVE Profil-
// liste, nicht nur "manuell ohne Rolle vergeben". Stichprobe im Testdatenbestand: von 651
// direkten T-*-Profil-Kanten waren 582 (89 %) zugleich das generierte Profil einer aktuell
// zugewiesenen Rolle des betroffenen Users -- ohne Ausschluss waere der Check also weit
// ueberwiegend falsch-positiv. "Echt direkt" = HAS_PROFILE(User) MINUS alle Profile, die ueber
// eine zum Stichtag gueltige ASSIGNED_TO-Rolle generiert werden (Role-HAS_PROFILE->Profile,
// AE-07/08 stichtagsgefiltert). Verbleibt z. B.: SAP_ALL/Standardprofile direkt vergeben, oder
// ein Profil, dessen Rolle zwischenzeitlich entzogen/abgelaufen ist, aber in UST04 zurueckblieb
// (eigenstaendig interessanter Befund -- Karteileiche).
// Parameter: $dataset, $asOf.
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/direct_profile_assignments.cypher

// --- 1) Zusammenfassung: Anzahl betroffener User (-> KPI-Kacheln UI) ---
MATCH (u:User {dataset:$dataset})-[:HAS_PROFILE]->(p:Profile {dataset:$dataset})
WHERE NOT EXISTS {
  MATCH (u)-[a:ASSIGNED_TO]->(:Role)-[:HAS_PROFILE]->(p)
  WHERE (a.validFrom IS NULL OR a.validFrom <= $asOf) AND (a.validTo IS NULL OR $asOf <= a.validTo)
}
WITH count(DISTINCT u) AS userAnzahl, count(DISTINCT p) AS profilAnzahl
RETURN ('über alle betroffenen User verteilt: ' + profilAnzahl + ' verschiedene Profile, ohne über Rollen erklärbare') AS profilInfo,
       userAnzahl AS anzahl;

// --- 2) Detailliste -- NUR Anzahl + kurze Vorschau statt aller Profile (manche User haben
// hunderte direkte Profile, eine volle Liste je Zelle ist dann unlesbar). Volle Liste bleibt
// im Graph abrufbar, ist hier bewusst auf eine Vorschau (erste 5) gekuerzt. ---
MATCH (u:User {dataset:$dataset})-[:HAS_PROFILE]->(p:Profile {dataset:$dataset})
WHERE NOT EXISTS {
  MATCH (u)-[a:ASSIGNED_TO]->(:Role)-[:HAS_PROFILE]->(p)
  WHERE (a.validFrom IS NULL OR a.validFrom <= $asOf) AND (a.validTo IS NULL OR $asOf <= a.validTo)
}
WITH u, collect(DISTINCT p.id) AS profile
RETURN u.id AS user, coalesce(u.name, '') AS name,
       CASE WHEN 'Locked' IN labels(u) THEN 'gesperrt' ELSE 'aktiv' END AS status,
       size(profile) AS profilAnzahl,
       apoc.coll.sort(profile)[0..5] AS profilVorschau,
       EXISTS { (u)-[:ASSIGNED_TO]->(:Role) } AS hatAuchRollen
ORDER BY profilAnzahl DESC, user;
