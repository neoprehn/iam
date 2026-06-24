// Konsistenzcheck (Katalog B3): Initial-/schwache Passwortstaende. KORREKTUR (auf Nutzer-
// Rueckfrage "warum koennen wir das nicht auswerten, wenn wir die Daten haben?"): die fruehere
// Einschaetzung "keine Datengrundlage" war zu pauschal -- USR02 fuehrt neben den echten
// Hash-Feldern (BCODE/PASSCODE/PWDSALTEDHASH/PWDHISTORY, weiterhin bewusst NICHT extrahiert,
// s. docs/extraktionsleitfaden.md) auch reine STATUS-/Datumsfelder (PWDINITIAL/PWDCHGDATE/
// PWDSETDATE), die schon im konvertierten CSV vorlagen, aber vom Loader bisher nicht ins
// Property uebernommen wurden (load/01_users.cypher nachgezogen).
//
// PWDINITIAL-Werte 0/1/2 -- Bedeutung empirisch hergeleitet (SAP dokumentiert die Kodierung
// nicht oeffentlich einheitlich, ⚠️ vor Produktivnutzung gegen das eigene System verifizieren):
//   1 -> korreliert im Testdatenbestand 100% mit pwdChgDate = pwdSetDate ("Passwort seit
//        Vergabe nie geaendert") -- der KLARE, belastbare Befund.
//   2 -> Datumsfelder NICHT durchgaengig gleich (Mischfall, z. B. admin-gesetztes/zurueck-
//        gesetztes Passwort) -- als SEPARATER, weicherer Befund ausgewiesen statt mit 1
//        zusammengefasst.
//   0 -> regulaer geaendert, kein Befund.
// Parameter: $dataset, $asOf (asOf ungenutzt, einheitliche Signatur).
// Aufruf: ... -P "dataset=>'acme'" -P "asOf=>date()" -f /cypher/checks/initial_passwords.cypher

// --- 1) Zusammenfassung je Befund (-> KPI-Kacheln UI) ---
MATCH (u:User {dataset:$dataset})
WHERE u.pwdInitial IN ['1', '2']
WITH (CASE u.pwdInitial
        WHEN '1' THEN 'Nie geändert seit Vergabe (pwdInitial=1)'
        ELSE 'Möglich initial/zurückgesetzt (pwdInitial=2, weicherer Befund)' END) AS befund,
     count(u) AS anzahl
RETURN befund, anzahl
ORDER BY anzahl DESC;

// --- 2) Detailliste ---
MATCH (u:User {dataset:$dataset})
WHERE u.pwdInitial IN ['1', '2']
RETURN u.id AS user, coalesce(u.name, '') AS name,
       CASE WHEN 'Dialog' IN labels(u) THEN 'Dialog'
            WHEN 'System' IN labels(u) THEN 'System'
            WHEN 'Service' IN labels(u) THEN 'Service'
            WHEN 'Communication' IN labels(u) THEN 'Communication'
            WHEN 'Reference' IN labels(u) THEN 'Reference' ELSE '?' END AS typ,
       CASE WHEN 'Locked' IN labels(u) THEN 'gesperrt' ELSE 'aktiv' END AS status,
       u.pwdInitial AS pwdInitial, u.pwdSetDate AS gesetztAm, u.pwdChgDate AS geaendertAm,
       u.lastLogon AS letzterLogon
ORDER BY CASE WHEN 'Dialog' IN labels(u) AND NOT 'Locked' IN labels(u) THEN 0 ELSE 1 END,
         pwdInitial, typ, status, user;
