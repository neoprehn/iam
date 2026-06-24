// Konsistenzcheck (Katalog D4): veraltete/nicht (vollstaendig) generierte Profile -- Rolle hat
// Berechtigungsdaten (HAS_AUTH), aber Role.profileGenerated ist false oder fehlt (AGR_1016B,
// Loader 22). "Rot in PFCG" (Ampelsymbol): in SAP wird eine Rolle erst nach dem Generieren des
// Profils zur Laufzeit wirksam (Pflege in AGR_1251 allein reicht nicht) -- ohne (vollstaendige)
// Generierung weicht das, was tatsaechlich geprueft wird, von der gepflegten Rollendefinition
// ab. `profileGenerated IS NULL` bedeutet "nie ein AGR_1016B-Eintrag protokolliert" (nicht
// "generiert und dann ungueltig geworden" -- das waere `profileGenerated = false`).
// ZWEITE KPI-Kachel "betroffene User" (Ideal: 0) ergaenzt auf Nutzer-Feedback: die Rollen-
// Anzahl allein sagt nichts ueber das AKTUELLE Risiko -- eine nicht generierte Rolle, die
// niemand zugewiesen hat, ist ein Aufraeumkandidat ohne akute Auswirkung; sobald aber >0 User
// betroffen sind, koennte deren tatsaechliche Berechtigung von der gepflegten Definition
// abweichen (Pruefungsrisiko).
// Parameter: $dataset, $asOf (asOf ungenutzt, einheitliche Signatur).
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/stale_profile_generation.cypher

// --- 1) Zusammenfassung: zwei Kacheln -- Rollenanzahl und betroffene User (-> KPI-Kacheln UI) ---
MATCH (r:Role {dataset:$dataset})
WHERE EXISTS { (r)-[:HAS_AUTH]->(:Authorization) }
  AND (r.profileGenerated = false OR r.profileGenerated IS NULL)
OPTIONAL MATCH (u:User)-[:ASSIGNED_TO]->(r)
WITH count(DISTINCT r) AS rollenAnzahl,
     count(DISTINCT CASE WHEN r.profileGenerated IS NULL THEN r END) AS ohneStatus,
     count(DISTINCT u) AS userAnzahl
UNWIND [
  {info: (ohneStatus + ' davon ohne Generierungsstatus'), anzahl: rollenAnzahl},
  {info: 'betroffene User (Ideal: 0)', anzahl: userAnzahl}
] AS kpi
RETURN kpi.info AS info, kpi.anzahl AS anzahl;

// --- 2) Detailliste ---
MATCH (r:Role {dataset:$dataset})
WHERE EXISTS { (r)-[:HAS_AUTH]->(:Authorization) }
  AND (r.profileGenerated = false OR r.profileGenerated IS NULL)
RETURN r.id AS rolle, coalesce(r.text, '') AS text,
       r.profileGenerated AS profilGeneriert, coalesce(r.profileState, []) AS profilStatus,
       count { (:User)-[:ASSIGNED_TO]->(r) } AS nutzerAnzahl
ORDER BY nutzerAnzahl DESC;
