# cytoscape.js (vendored)

Version: 3.34.0
Quelle: https://www.npmjs.com/package/cytoscape
Lizenz: MIT (siehe `LICENSE`)

Lokal vendored statt per CDN geladen, damit die App ohne Internetzugriff lauffaehig bleibt
(Vertrauensgrenze, s. ROADMAP.md) -- `dist/cytoscape.min.js` 1:1 aus dem npm-Tarball kopiert,
keine Modifikation. Keine Laufzeit-Abhaengigkeiten (`dependencies: {}` im package.json), keine
Netzwerk-/Tracking-Aufrufe im Bundle (geprueft: kein `fetch`/`XMLHttpRequest`/`sendBeacon`).

Update: neue Version von https://registry.npmjs.org/cytoscape herunterladen, `dist/cytoscape.min.js`
ersetzen, Versionsnummer hier anpassen.
