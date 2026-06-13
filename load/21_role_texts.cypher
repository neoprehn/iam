// 21 — AGR_TEXTS -> :Role.text (sprachabhängige Rollenbeschreibung). Parameter: $dataset, $lang
// Kanonische, sprachabhängige Quelle für Rollentexte (AGR_DEFINE.TEXT in 02 ist einsprachig und
// lückenhaft). Läuft NACH 02: bevorzugte Sprache(n) aus $lang gewinnen und überschreiben den in
// 02 gesetzten Text; sonst nur füllen, wo noch kein Text steht (erster vorhandener gewinnt).
// MATCH statt MERGE — Rollen kommen aus 02/08, hier werden nur Texte ergänzt (keine Knoten aus
// der Texttabelle erzeugen). $lang = Liste akzeptierter Codes, Default ['DE','DEU','D'].
// Sprachspalte robust: AGR_TEXTS führt je nach Export SPRAS oder SPRSL.
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM $url AS row FIELDTERMINATOR '\t' RETURN row",
  "WITH row WHERE coalesce(row.AGR_NAME,'') <> ''
   MATCH (r:Role {key: $dataset + '|' + row.AGR_NAME})
   WITH r, row, coalesce(row.SPRAS, row.SPRSL, '') AS langCode
   SET r.text = CASE WHEN langCode IN $lang THEN row.TEXT WHEN r.text IS NULL THEN row.TEXT ELSE r.text END",
  {batchSize:2000, parallel:false, params:{url:'file:///'+$dataset+'/agr_texts.csv', dataset:$dataset, lang:coalesce($lang,['DE','DEU','D'])}}
);
