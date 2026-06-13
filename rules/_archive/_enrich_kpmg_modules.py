#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Enrichment: uebertraegt die Modul-Information aus dem CSI-Ruleset auf KPMG_R3, indem die
TCodes der KPMG-Queries gegen die CSI-Abbildung TCode->module gematcht werden (CSI-Vokabular,
einheitlich). Laeuft NACH den Konvertern (liest rules/CSI_Ruleset/queries.json + rules/KPMG_R3/
queries.json) und schreibt 'module'/'moduleSource' in die KPMG-queries.json zurueck.

CSI TCode->module ist zu ~97% eindeutig; pro KPMG-Query gewinnt das Mehrheitsmodul ihrer TCodes.
Nicht abgedeckte Queries bleiben ohne Modul (kein Raten). Aufruf:
  python rules/_archive/_enrich_kpmg_modules.py
"""
import json, os
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
RULES = os.path.normpath(os.path.join(HERE, ".."))

def load(rs):
    p = os.path.join(RULES, rs, "queries.json")
    return p, json.load(open(p, encoding="utf-8"))

_, csi = load("CSI_Ruleset")
kpmg_path, kpmg = load("KPMG_R3")

# CSI: TCode -> Counter(module)
tc2mod = {}
for q in csi:
    m = q.get("module", "")
    if not m:
        continue
    for t in q.get("transactions", []):
        tc2mod.setdefault(t["tcode"], Counter())[m] += 1

assigned = 0
for q in kpmg:
    votes = Counter()
    for t in q.get("transactions", []):
        tc = t["tcode"]
        if tc in tc2mod:
            votes += tc2mod[tc]
    if votes:
        q["module"] = votes.most_common(1)[0][0]
        q["moduleSource"] = "csi-tcode"
        assigned += 1
    else:
        q["module"] = ""
        q["moduleSource"] = ""

with open(kpmg_path, "w", encoding="utf-8") as fh:
    json.dump(kpmg, fh, ensure_ascii=False, indent=2)

print(f"KPMG-Queries gesamt: {len(kpmg)} | Modul via CSI-TCode zugeordnet: {assigned} "
      f"({100*assigned//max(len(kpmg),1)}%)")
print("Top-Module:", dict(Counter(q['module'] for q in kpmg if q['module']).most_common(8)))
