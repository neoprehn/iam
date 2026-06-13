# Ruleset `csi_bi` — CSI SoD-Ruleset BI/BW

Normalisierte JSON-Fassung des CSI-tools-Rulesets für **BI/BW** (Quelle:
`rules/_archive/CSI_BI/csi_400_ruleset_BI.xml`, Konverter `rules/_archive/_convert_csi.py`).

Struktur und Verknüpfungssemantik identisch zu [`CSI_Ruleset`](../CSI_Ruleset/README.md) /
[`KPMG_R3`](../KPMG_R3/README.md). Siehe dort für das Modell und `ruleset.json` →
`combinationSemantics`.

## Besonderheit

BI-Variante mit zusätzlichem **Control-Katalog** — sofern in der Quelle vorhanden, unter
`legends.controlMeasures` abgelegt. Dateien sonst wie bei `csi`
(`queries.json`, `sod_rules.json`, `risks.json`, `legends.json`, `ruleset.json`).
