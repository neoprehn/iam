#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Einmalige Migration: CSI-Ruleset (QuerySet-XML von CSI tools) -> normalisierte JSON,
gleiche Form wie KPMG_R3 (queries/sod_rules/legends/ruleset) + risks.json (CSI-nativ).

NICHT Teil der Runtime-Pipeline. Reines Dev-/Konvertierungswerkzeug.
Aufruf:  python rules/_archive/_convert_csi.py
"""
import json, os, datetime
import xml.etree.ElementTree as ET
from collections import OrderedDict, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
RULES = os.path.normpath(os.path.join(HERE, ".."))

def txt(el, tag):
    c = el.find(tag)
    return (c.text or "").strip() if c is not None and c.text else ""

def boolean(el, tag):
    return txt(el, tag).lower() == "true"

def children(root, tag):
    return [e for e in root if e.tag == tag]

def convert(xml_rel, out_name, ruleset_id, name, note):
    src = os.path.join(HERE, xml_rel)
    out = os.path.join(RULES, out_name)
    os.makedirs(out, exist_ok=True)
    root = ET.parse(src).getroot()

    # --- Queries (Master) ---
    queries = OrderedDict()
    for q in children(root, "Queries"):
        qn = txt(q, "QueryName")
        if not qn:
            continue
        queries[qn] = {
            "query": qn,
            "description": txt(q, "Description"),
            "module": txt(q, "ModuleRef"),
            "subModule": txt(q, "SubModule"),
            "riskText": txt(q, "Risk"),
            "queryType": txt(q, "QueryType"),
            "soxClassification": txt(q, "SourceSoxClassification"),
            "gdprClassification": txt(q, "SourceGdprClassification"),
            "multipleRun": boolean(q, "MultipleRun"),
            "disregardTcode": boolean(q, "DisregardTCode"),
            "authorizations": [],
            "transactions": [],
        }

    def ensure(qn):
        if qn not in queries:
            queries[qn] = {"query": qn, "description": "", "module": "", "subModule": "",
                           "riskText": "", "queryType": "", "soxClassification": "",
                           "gdprClassification": "", "multipleRun": False, "disregardTcode": False,
                           "authorizations": [], "transactions": []}
        return queries[qn]

    # --- Authorizations: je (Query,Object,Field) Werte sammeln (eine Value je XML-Zeile) ---
    auth_grp = OrderedDict()   # (qn,obj,field) -> dict
    for r in children(root, "rQueriesAuthorizations"):
        qn, obj, fld = txt(r, "SourceQueries"), txt(r, "Object"), txt(r, "Field")
        if not qn or not obj or not fld:
            continue
        key = (qn, obj, fld)
        g = auth_grp.get(key)
        if g is None:
            g = {"object": obj, "field": fld, "values": [], "andLogic": boolean(r, "AndLogicForValues"),
                 "audit": boolean(r, "Audit")}
            auth_grp[key] = g
        v = txt(r, "Value")
        if v != "" and v not in g["values"]:
            g["values"].append(v)
    for (qn, obj, fld), g in auth_grp.items():
        ensure(qn)["authorizations"].append(g)

    # --- TCodes ---
    for r in children(root, "rQueriesTCodes"):
        qn, tc = txt(r, "SourceQueries"), txt(r, "TCodes")
        if not qn or not tc:
            continue
        ensure(qn)["transactions"].append({"tcode": tc, "audit": boolean(r, "Audit"), "stad": boolean(r, "STAD")})

    queries_list = list(queries.values())

    # --- SoD-Regeln ---
    rules = OrderedDict()
    for h in children(root, "SODHeader"):
        nm = txt(h, "Name")
        if not nm:
            continue
        rules[nm] = {
            "sodRule": nm,
            "description": txt(h, "Description"),
            "comment": txt(h, "Comment"),
            "expression": txt(h, "SourceSODDefinitions"),   # die boolesche Verknuepfung, z. B. "QA AND QB"
            "reasonCode": txt(h, "SourceSODReasonCodes"),
            "multipleRun": boolean(h, "MultipleRun"),
            "variables": {},
            "risks": [],
        }
    for d in children(root, "SODDetail"):
        h, var, qn = txt(d, "SourceSODHeader"), txt(d, "Variable"), txt(d, "SourceQueries")
        if h in rules and var:
            rules[h]["variables"][var] = qn
    for rr in children(root, "rSODHeaderRisk"):
        h, rk = txt(rr, "SoD"), txt(rr, "Risk")
        if h in rules and rk:
            rules[h]["risks"].append(rk)
    rules_list = list(rules.values())

    # Normalisierte Kritikalitaet (einheitliche Skala wie KPMG): Query aus soxClassification
    # (CSI 'SOX_C/H/M/L'); SoD-reasonCode ist bei CSI ein Template-Code (A_F1+) -> KEINE Schwere
    # -> criticality bleibt null (CSI fuehrt keine native SoD-Schwere).
    _CRIT = {"V": ("very-high", 5), "C": ("critical", 4), "H": ("high", 3), "M": ("medium", 2), "L": ("low", 1)}
    def criticality(code):
        lvl = (code or "").rsplit("_", 1)[-1].strip().upper()
        return _CRIT.get(lvl, (None, None))
    for q in queries_list:
        q["criticality"], q["criticalityRank"] = criticality(q.get("soxClassification"))
    for r in rules_list:
        r["criticality"], r["criticalityRank"] = criticality(r.get("reasonCode"))

    # --- Risks (CSI-nativ) ---
    risks = []
    for r in children(root, "Risk"):
        nm = txt(r, "Name")
        if not nm:
            continue
        risks.append({
            "risk": nm,
            "alias": txt(r, "Alias"),
            "description": txt(r, "Description"),
            "comment": txt(r, "Comment"),
            "riskType": txt(r, "RiskType"),
            "riskLevel": txt(r, "RiskLevel"),
            "riskStatus": txt(r, "RiskStatus"),
        })

    # --- Legenden ---
    def lookup(tag, key="Name", val="Description"):
        return {txt(e, key): txt(e, val) for e in children(root, tag) if txt(e, key)}
    legends = {
        "queryTypes": lookup("QueryTypes"),                 # z. B. AO -> "Audit - Optional"
        "soxClassification": lookup("SoxClassification"),
        "gdprClassification": lookup("GdprClassification"),
        "sodReasonCodes": lookup("SODReasonCodes"),
        "sodDefinitions": [{"name": txt(e, "Name"), "alias": txt(e, "Alias"),
                             "expression": txt(e, "Expression"), "description": txt(e, "Description")}
                            for e in children(root, "SODDefinitions")],
        "riskLevels": sorted({txt(e, "Name") for e in children(root, "RiskLevel") if txt(e, "Name")}),
        "riskTypes": sorted({txt(e, "Name") for e in children(root, "RiskType") if txt(e, "Name")}),
        "riskStatuses": sorted({txt(e, "Name") for e in children(root, "RiskStatus") if txt(e, "Name")}),
    }
    # BI-Variante: Control-Kataloge falls vorhanden
    controls = [{"name": txt(e, "Name"), "description": txt(e, "Description")}
                for e in children(root, "ControlMeasure") if txt(e, "Name")]
    if controls:
        legends["controlMeasures"] = controls

    ruleset = {
        "ruleset": ruleset_id,
        "name": name,
        "note": note,
        "model": "query-based (CSI tools QuerySet) — identisch zu KPMG_R3, nativ + reicher (Risk-Objekte, DisregardTCode)",
        "source": f"rules/_archive/{out_name}/ (CSI QuerySet-XML)",
        "generatedAt": datetime.date.today().isoformat(),
        "combinationSemantics": {
            "valuesWithinField": "AND wenn andLogic=true, sonst OR (AndLogicForValues)",
            "fieldsWithinObject": "AND",
            "objectsWithinQuery": "AND",
            "transactions": "OR (mehrere TCodes); tcode '*' = beliebig",
            "authVsTransaction": "AND (TCode UND Berechtigungsobjekte); bei query.disregardTcode=true nur Auth",
            "type": "SCOPE-Filter (queryType, siehe legends.queryTypes), KEIN Operator",
            "_note": "Identisch zum bestaetigten KPMG_R3-Modell; CSI hat DisregardTCode explizit je Query.",
        },
        "counts": {
            "queries": len(queries_list),
            "queriesWithAuthorizations": sum(1 for q in queries_list if q["authorizations"]),
            "queriesWithTransactions": sum(1 for q in queries_list if q["transactions"]),
            "sodRules": len(rules_list),
            "variableMappings": sum(len(r["variables"]) for r in rules_list),
            "risks": len(risks),
        },
    }

    def dump(fn, obj):
        with open(os.path.join(out, fn), "w", encoding="utf-8") as fh:
            json.dump(obj, fh, ensure_ascii=False, indent=2)
    dump("queries.json", queries_list)
    dump("sod_rules.json", rules_list)
    dump("risks.json", risks)
    dump("legends.json", legends)
    dump("ruleset.json", ruleset)
    print(f"\n=== {ruleset_id} -> rules/{out_name}/ ===")
    print(json.dumps(ruleset["counts"], indent=2, ensure_ascii=False))
    print("  queryTypes:", json.dumps(legends["queryTypes"], ensure_ascii=False))
    return ruleset["counts"]

convert("CSI_Ruleset/CSI_400_Ruleset20191201.xml", "CSI_Ruleset", "csi",
        "CSI SoD-Ruleset (ECC/R3)", "Native CSI-tools-Vorlage; Plattform ECC/R3.")
convert("CSI_BI/csi_400_ruleset_BI.xml", "CSI_BI", "csi_bi",
        "CSI SoD-Ruleset BI/BW", "CSI-tools-Vorlage fuer BI/BW (mit Control-Katalog).")
