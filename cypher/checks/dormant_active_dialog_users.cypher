// Konsistenzcheck (Katalog B1): aktive Dialog-User ohne Logon seit X Tagen (oder nie angemeldet).
// Schwelle ist ein echter Parameter ($sleepDays, ueber checks/B.json "params" als Pill-Buttons
// 90/180/360 in der UI waehlbar -- s. checks/SCHEMA.md). Default 180 Tage, deckt sich mit dem
// SoD-Sleeping-Default (config/analysis_profiles.json, sleeping.sleepDays).
// Nur AKTIVE Dialog-User (anmeldefaehige Person, nicht gesperrt): gesperrte/nicht-Dialog-User
// sind kein Lizenz-/Zugriffsrisiko in diesem Sinn (s. B4 fuer den Sperr-Blickwinkel).
// Parameter: $dataset, $asOf, $sleepDays.
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -P "sleepDays=>180" -f /cypher/checks/dormant_active_dialog_users.cypher

// --- 1) Zusammenfassung (-> KPI-Kacheln UI) ---
MATCH (u:User {dataset:$dataset})
WHERE 'Dialog' IN labels(u) AND 'Active' IN labels(u)
  AND (u.lastLogon IS NULL OR u.lastLogon < ($asOf - duration({days: $sleepDays})))
RETURN ('Schwelle ' + $sleepDays + ' Tage') AS schwelleInfo, count(u) AS anzahl;

// --- 2) Detailliste ---
MATCH (u:User {dataset:$dataset})
WHERE 'Dialog' IN labels(u) AND 'Active' IN labels(u)
  AND (u.lastLogon IS NULL OR u.lastLogon < ($asOf - duration({days: $sleepDays})))
RETURN u.id AS user, coalesce(u.name, '') AS name, u.lastLogon AS letzterLogon
ORDER BY letzterLogon;
