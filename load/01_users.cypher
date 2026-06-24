// 01 — USR02 -> :User  (nur benoetigte Spalten; KEINE Passwort-HASH-Felder).
// PWDINITIAL/PWDCHGDATE/PWDSETDATE sind bewusst KEINE Hash-/Klartext-Felder, sondern reine
// Status-/Datumsangaben (analog zu UFLAG/TRDAT, die schon laenger geladen werden) -- der
// Konverter (convert.py DROP_DEFAULT) entfernt weiterhin gezielt BCODE*/BCDA*/OCOD*/CODV*/
// PASSCODE/PWDSALTEDHASH/PWDHISTORY (die eigentlichen Hash-/Algorithmus-Felder), s.
// docs/extraktionsleitfaden.md. pwdInitial-Werte 0/1/2 (SAP-Kennzeichen "aktuelles Passwort ist
// das initial gesetzte"): empirisch 1 korreliert 100% mit PWDCHGDATE=PWDSETDATE ("nie geaendert
// seit Vergabe") -- 2 ist gemischt und mit geringerer Sicherheit interpretierbar, ⚠️ vor
// Produktivnutzung gegen das eigene System verifizieren (s. KONSISTENZCHECKS.md B3).
// Parameter: $dataset
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM $url AS row FIELDTERMINATOR '\t' RETURN row",
  "WITH row WHERE coalesce(row.BNAME,'') <> ''
   MERGE (u:User {key: $dataset + '|' + row.BNAME})
     ON CREATE SET u.dataset = $dataset, u.id = row.BNAME
   SET u.userType  = row.USTYP,
       u.userGroup = row.CLASS,
       u.uflag     = toInteger(coalesce(row.UFLAG,'0')),
       u.validFrom = CASE WHEN coalesce(row.GLTGV,'') IN ['','00.00.0000'] THEN null
                          WHEN row.GLTGV = '31.12.9999' THEN date('9999-12-31')
                          ELSE date(right(row.GLTGV,4)+'-'+substring(row.GLTGV,3,2)+'-'+left(row.GLTGV,2)) END,
       u.validTo   = CASE WHEN coalesce(row.GLTGB,'') IN ['','00.00.0000'] THEN null
                          WHEN row.GLTGB = '31.12.9999' THEN date('9999-12-31')
                          ELSE date(right(row.GLTGB,4)+'-'+substring(row.GLTGB,3,2)+'-'+left(row.GLTGB,2)) END,
       u.lastLogon = CASE WHEN coalesce(row.TRDAT,'') IN ['','00.00.0000'] THEN null
                          ELSE date(right(row.TRDAT,4)+'-'+substring(row.TRDAT,3,2)+'-'+left(row.TRDAT,2)) END,
       u.lockReasons = [x IN [{b:32,n:'failed_logons'},{b:64,n:'admin_local'},{b:128,n:'admin_global'}]
                          WHERE apoc.bitwise.op(toInteger(coalesce(row.UFLAG,'0')),'&',x.b) <> 0 | x.n],
       u.pwdInitial = row.PWDINITIAL,
       u.pwdChgDate = CASE WHEN coalesce(row.PWDCHGDATE,'') IN ['','00.00.0000'] THEN null
                          ELSE date(right(row.PWDCHGDATE,4)+'-'+substring(row.PWDCHGDATE,3,2)+'-'+left(row.PWDCHGDATE,2)) END,
       u.pwdSetDate = CASE WHEN coalesce(row.PWDSETDATE,'') IN ['','00.00.0000'] THEN null
                          ELSE date(right(row.PWDSETDATE,4)+'-'+substring(row.PWDSETDATE,3,2)+'-'+left(row.PWDSETDATE,2)) END
   WITH u, [CASE u.userType WHEN 'A' THEN 'Dialog' WHEN 'B' THEN 'System' WHEN 'C' THEN 'Communication'
                            WHEN 'S' THEN 'Service' WHEN 'L' THEN 'Reference' ELSE 'Dialog' END,
            CASE WHEN u.uflag = 0 THEN 'Active' ELSE 'Locked' END] AS lbls
   CALL apoc.create.addLabels(u, lbls) YIELD node
   RETURN count(*)",
  {batchSize:2000, parallel:false, params:{url:'file:///'+$dataset+'/usr02.csv', dataset:$dataset}}
);
