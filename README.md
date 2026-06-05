# IAM
Identity & Access Management für SAP-Berechtigungsanalysen

Dieses Verzeichnis enthält Projekte zur Auswertung von SAP-Berechtigungen mit Graphdatenbanken und Cypher.

## Inhalt
- `SAP ABAP Importer`
  - Bestehende Cypher/Neo4j-Skripte zum Import von SAP-Berechtigungsdaten aus JSON.
  - Definiert Knoten und Beziehungen für Benutzer, Rollen, Profile, Berechtigungsobjekte und Referenznutzer.

## Ziel
- SAP-Berechtigungen automatisiert auswerten
- Zugriffsbeziehungen zwischen Benutzern, Rollen, Profilen und Berechtigungen im Graph darstellen
- Graphbasierte Abfragen zur Risikoanalyse und Berechtigungsprüfung ermöglichen

## Anforderungen
- Neo4j (Server, Desktop oder Aura)
- APOC-Plugin aktiviert
- SAP-Exportdaten als JSON-Dateien
- JSON-Dateien im Neo4j-Importverzeichnis oder `dbms.directories.import` entsprechend konfiguriert

## Vorgehen
1. JSON-Exportdateien erzeugen (z. B. `USR02.json`, `AGR_DEFINE.json`, `AGR_USERS.json` usw.)
2. Dateien in das Neo4j-Importverzeichnis kopieren
3. `SAP ABAP Importer` in Neo4j ausführen
4. Graphabfragen zur Berechtigungsanalyse nutzen

## Wichtig
- Die aktuellen Skripte verwenden `CALL apoc.load.json(...)`
- Neo4j muss Leserechte auf die JSON-Dateien haben
- `SAP ABAP Importer` ist derzeit eine Textdatei mit den Cypher-Befehlen für den Import

## Weiteres
Wenn du möchtest, kann ich das Importskript auch in eine `.cypher`-Datei umbenennen oder ein separates `README` im Importer-Teil anlegen.

---

Kontakt: Mirko Prehn
Email: mirko.prehn@web.de
