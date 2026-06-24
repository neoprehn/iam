// Konsistenzcheck (Katalog B5): Mehrfach-Konten derselben Person -- erkannt ueber
// Namensgleichheit (V_USERNAME -> User.name, Skript load/12_user_names.cypher).
// EINSCHRAENKUNG: ADRP (Adress-/Personendaten) wird bewusst NICHT importiert (s.
// docs/extraktionsleitfaden.md, "Klartextname/Adressdaten sind fuer Can-Do nicht noetig") --
// daher hier nur die schwaechere Namensgleichheits-Heuristik, kein adressbasierter Abgleich.
// Falsch-Positive moeglich (Namensvettern), falsch-Negative ebenso (Tippfehler/Titel-Suffixe
// im Namensfeld) -- als Indikator, nicht als belastbarer Einzelbefund zu lesen.
// Nur befuellte, nicht-generische Namen (leerer String wird ignoriert).
// WICHTIG: die Dubletten-GRUPPIERUNG laeuft immer ueber ALLE Konten eines Namens (sonst wuerde
// z. B. ein aktiv+gesperrt-Paar beim Filtern auf "aktiv" faelschlich als "keine Dublette"
// verschwinden); $status filtert erst danach, welche KONTEN einer bereits erkannten
// Dubletten-Gruppe angezeigt werden -- 'alle' (Default) zeigt beide. Pill-Buttons in der UI
// ueber checks/B.json "params".
// Parameter: $dataset, $asOf (ungenutzt, einheitliche Signatur), $status.

// --- 1) Zusammenfassung: Anzahl betroffener Namens-Gruppen + angezeigte Konten (-> KPI-Kacheln UI) ---
MATCH (u:User {dataset:$dataset})
WHERE coalesce(u.name, '') <> ''
WITH u.name AS name, collect(u) AS alleKonten
WHERE size(alleKonten) > 1
UNWIND alleKonten AS u
WITH name, u
WHERE $status = 'alle' OR ($status = 'gesperrt') = ('Locked' IN labels(u))
RETURN count(DISTINCT name) AS gruppenAnzahl, count(u) AS kontenAnzahl;

// --- 2) Detailliste ---
MATCH (u:User {dataset:$dataset})
WHERE coalesce(u.name, '') <> ''
WITH u.name AS name, collect(u) AS alleKonten
WHERE size(alleKonten) > 1
UNWIND alleKonten AS u
WITH name, u
WHERE $status = 'alle' OR ($status = 'gesperrt') = ('Locked' IN labels(u))
RETURN name, u.id AS user, coalesce(u.persNumber, '') AS personalnummer,
       CASE WHEN 'Dialog' IN labels(u) THEN 'Dialog'
            WHEN 'System' IN labels(u) THEN 'System'
            WHEN 'Service' IN labels(u) THEN 'Service'
            WHEN 'Communication' IN labels(u) THEN 'Communication'
            WHEN 'Reference' IN labels(u) THEN 'Reference' ELSE '?' END AS typ,
       CASE WHEN 'Locked' IN labels(u) THEN 'gesperrt' ELSE 'aktiv' END AS status,
       u.lastLogon AS letzterLogon
ORDER BY name, user;
