"""IAM SoD Backend (Phase 9, Bau-Schritt 1) — Runner-as-API.

Orchestriert die vorhandenen cypher/-Dateien ueber den Neo4j-Treiber (apoc.cypher.runFile),
loest Profile aus config/analysis_profiles.json auf und faehrt Materialisierung+Auswertung als
asynchronen Job. Plattformunabhaengig im Container; ersetzt die PowerShell-Runner durch HTTP.
Bewusst MVP: In-Memory-Jobs (Single-Instance), Findings bleiben im Graph (kein eigener Store).
"""
import os
import re
import io
import csv
import json
import uuid
import shutil
import zipfile
import tempfile
import datetime
import threading
from pathlib import Path

from fastapi import FastAPI, HTTPException, UploadFile, File, Form, Query
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, Response
from pydantic import BaseModel
from neo4j import GraphDatabase

import convert

NEO4J_URI = os.environ.get("NEO4J_URI", "bolt://neo4j:7687")
NEO4J_USER = os.environ.get("NEO4J_USER", "neo4j")
NEO4J_PASSWORD = os.environ["NEO4J_PASSWORD"]
CONFIG_DIR = Path(os.environ.get("CONFIG_DIR", "/app/config"))
RULES_DIR = Path(os.environ.get("RULES_DIR", "/app/rules"))
CYPHER_DIR = Path(os.environ.get("CYPHER_DIR", "/app/cypher"))
LOAD_DIR = Path(os.environ.get("LOAD_DIR", "/app/load"))
MIGRATIONS_DIR = Path(os.environ.get("MIGRATIONS_DIR", "/app/migrations"))
DATA_DIR = Path(os.environ.get("DATA_DIR", "/app/data/import"))
BACKUP_DIR = Path(os.environ.get("BACKUP_DIR", "/app/backups"))
RUN_BACKUP_DIR = BACKUP_DIR / "runs"
FRONTEND_DIR = Path(os.environ.get("FRONTEND_DIR", "/app/frontend"))
DEFAULT_LANG = [c.strip() for c in os.environ.get("IMPORT_LANG", "DE,DEU,D").split(",") if c.strip()]

driver = GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USER, NEO4J_PASSWORD))
app = FastAPI(title="IAM SoD Backend", version="0.1.0")
jobs: dict[str, dict] = {}  # jobId -> status


@app.middleware("http")
async def no_cache_frontend(request, call_next):
    """Statische UI aendert sich oft (laufende Entwicklung) -> Browser sollen IMMER
    revalidieren (ETag/Last-Modified -> billiges 304 bei unveraendertem Inhalt) statt eine
    alte index.html ungeprueft aus dem Cache zu zeigen."""
    response = await call_next(request)
    if request.url.path == "/" or request.url.path.endswith(".html"):
        response.headers["Cache-Control"] = "no-cache"
    return response


def profiles() -> dict:
    return json.loads((CONFIG_DIR / "analysis_profiles.json").read_text(encoding="utf-8"))


def list_rulesets() -> list[dict]:
    """Verfuegbare Rulesets aus rules/*/ruleset.json (id + Anzeigename)."""
    out = []
    if RULES_DIR.exists():
        for d in sorted(RULES_DIR.iterdir()):
            rj = d / "ruleset.json"
            if rj.is_file():
                meta = json.loads(rj.read_text(encoding="utf-8"))
                if meta.get("ruleset"):
                    out.append({"id": meta["ruleset"], "name": meta.get("name", meta["ruleset"]), "dir": d.name})
    return out


def ruleset_dir(ruleset: str):
    for r in list_rulesets():
        if r["id"] == ruleset:
            return r["dir"]
    return None


# --- Einzelfilter-Editor (Query-Metadaten) ----------------------------------------------
# Schreibt NIE in die Vendor-Datei (queries.json) — Edits/abgeleitete Queries landen in einem
# Overlay (queries.custom.json) je Ruleset-Ordner, das load_ruleset.cypher zusaetzlich einliest
# (siehe dort: coalesce-Merge, Overlay gewinnt bei gesetzten Feldern). Bewusst nur Metadaten in
# v1 (description/criticality/module/queryType/disregardTcode) — authorizations/transactions
# werden bei "Ableiten" 1:1 von der Quelle kopiert, aber hier nicht editiert.
def _ruleset_paths(ruleset: str) -> tuple[Path, Path]:
    rdir = ruleset_dir(ruleset)
    if not rdir:
        raise HTTPException(404, f"Ruleset '{ruleset}' nicht gefunden")
    base = RULES_DIR / rdir
    return base / "queries.json", base / "queries.custom.json"


def _load_json_list(path: Path) -> list[dict]:
    return json.loads(path.read_text(encoding="utf-8")) if path.is_file() else []


def ensure_custom_queries_file(ruleset: str) -> Path:
    _, custom_path = _ruleset_paths(ruleset)
    if not custom_path.is_file():
        custom_path.write_text("[]", encoding="utf-8")
    return custom_path


def _merged_queries(ruleset: str) -> tuple[dict[str, dict], set[str]]:
    """Vendor-Queries + Overlay, Overlay-Felder gewinnen je id; neue ids = eigene/abgeleitete
    Queries. Gibt (id -> effektive Query, Menge der ueberlagerten/eigenen ids) zurueck."""
    vendor_path, custom_path = _ruleset_paths(ruleset)
    merged = {q["query"]: dict(q) for q in _load_json_list(vendor_path)}
    custom_ids = set()
    for c in _load_json_list(custom_path):
        qid = c["query"]
        custom_ids.add(qid)
        if qid in merged:
            merged[qid] = {**merged[qid], **{k: v for k, v in c.items() if v is not None}}
        else:
            merged[qid] = c
    return merged, custom_ids


def reload_ruleset(ruleset: str):
    rdir = ruleset_dir(ruleset)
    with driver.session() as s:
        run_file(s, "ruleset/load_ruleset.cypher", {"dir": rdir, "ruleset": ruleset})


def jsonable(v):
    """Neo4j-Temporaltypen (Date/DateTime/Time) -> ISO-String; Container rekursiv."""
    if hasattr(v, "isoformat"):
        return v.isoformat()
    if isinstance(v, dict):
        return {k: jsonable(x) for k, x in v.items()}
    if isinstance(v, (list, tuple)):
        return [jsonable(x) for x in v]
    return v


def split_statements(text: str) -> list[str]:
    """Cypher-Datei in Einzel-Statements zerlegen (wie cypher-shell `-f`): volle //-Kommentarzeilen
    entfernen, an ';' trennen. apoc.cypher.runFile waere apoc-extended; der Container hat nur
    apoc-core -> wir fahren die Statements direkt ueber den Treiber (je Statement Auto-Commit)."""
    lines = [ln for ln in text.splitlines() if not ln.lstrip().startswith("//")]
    stmts = [s.strip() for s in "\n".join(lines).split(";")]
    return [s for s in stmts if s]


def run_cypher_path(session, path: Path, params: dict):
    """Eine .cypher-Datei (mehrere ;-getrennte Statements) ueber den Treiber fahren."""
    for stmt in split_statements(path.read_text(encoding="utf-8")):
        session.run(stmt, **params).consume()


def run_file(session, rel_path: str, params: dict):
    run_cypher_path(session, CYPHER_DIR / rel_path, params)


class RunReq(BaseModel):
    ruleset: str = "kpmg_r3"
    dataset: str
    asOf: str                       # 'YYYY-MM-DD' (Snapshot-Stichtag)
    userTypeProfile: str = "all"
    orgProfile: str = "standard"
    sleepDays: int | None = None
    minCriticalityRank: int = 0
    sodRules: list[str] = []
    runId: str | None = None
    title: str | None = None        # menschenlesbarer Name der Variante (z. B. "Übergreifend");
                                     # leer -> runId als Fallback (siehe do_run)
    skipRulesetLoad: bool = True
    skipMaterialize: bool = False
    skipExplain: bool = True         # Evidenz (VIA_ROLE/VIA_PROFILE + intra/inter) ist teuer ->
                                     # Default aus; per Formular oder POST /runs/{id}/explain anfordern


def do_run(job_id: str, req: RunReq):
    try:
        cfg = profiles()
        utp = next((p for p in cfg["userTypeProfiles"] if p["name"] == req.userTypeProfile), None)
        if not utp:
            raise ValueError(f"userTypeProfile '{req.userTypeProfile}' unbekannt")
        op = next((p for p in cfg["profiles"] if p["name"] == req.orgProfile), None)
        if not op:
            raise ValueError(f"orgProfile '{req.orgProfile}' unbekannt")
        org_mode = op["org"].get("mode", "ignoreOrg")
        org_filters = op["org"].get("filters", {}) if org_mode == "filtered" else {}
        sleep_days = req.sleepDays if req.sleepDays is not None else int(cfg["sleeping"]["sleepDays"])
        run_id = req.runId or f"{req.ruleset}-{datetime.datetime.now():%Y%m%d%H%M%S}"
        title = req.title or run_id
        as_of = datetime.date.fromisoformat(req.asOf)
        base = {"ruleset": req.ruleset, "dataset": req.dataset, "asOf": as_of, "runId": run_id}
        org = {"orgMode": org_mode, "orgFilters": org_filters}
        jobs[job_id].update(status="running", runId=run_id, step="start")

        with driver.session() as s:
            if not req.skipRulesetLoad:
                rdir = ruleset_dir(req.ruleset)
                if not rdir:
                    raise ValueError(f"Ruleset-Ordner fuer '{req.ruleset}' nicht gefunden")
                jobs[job_id]["step"] = "ruleset"
                ensure_custom_queries_file(req.ruleset)   # queries.custom.json muss existieren (apoc.load.json)
                run_file(s, "ruleset/load_ruleset.cypher", {"dir": rdir, "ruleset": req.ruleset})
            if not req.skipMaterialize:
                jobs[job_id]["step"] = "materialize"
                run_file(s, "sod/materialize_matches.cypher", {**base, **org})
            jobs[job_id]["step"] = "evaluate"
            run_file(s, "sod/evaluate_sod.cypher", {
                **base, **org,
                "userTypes": list(utp.get("userTypes", [])),
                "excludeLocked": bool(utp.get("excludeLocked", False)),
                "sleepDays": sleep_days,
                "minCriticalityRank": req.minCriticalityRank,
                "sodRules": req.sodRules,
                "title": title,
            })
            if not req.skipExplain:
                jobs[job_id]["step"] = "explain"
                run_file(s, "sod/explain_sod.cypher", base)
            rec = s.run(
                "MATCH (f:SoDConflict {runId:$r}) "
                "RETURN count(f) AS findings, count(DISTINCT f.ruleId) AS rules, "
                "sum(CASE WHEN f.userSleeping THEN 1 ELSE 0 END) AS sleeping, "
                "sum(CASE WHEN f.conflictType='intra' THEN 1 ELSE 0 END) AS intra", r=run_id,
            ).single()
        jobs[job_id].update(status="done", step="done", findings=rec["findings"],
                            rules=rec["rules"], sleeping=rec["sleeping"], intra=rec["intra"])
    except Exception as e:  # noqa: BLE001
        jobs[job_id].update(status="error", error=str(e))


class ImportReq(BaseModel):
    dataset: str                    # Ordnername unter data/import/ (= dataset-Id)
    lang: list[str] = []            # Sprach-Schalter (SPRAS/LANGU); leer = Default (IMPORT_LANG)
    skipConvert: bool = False       # .csv liegen schon vor -> Konvertierung ueberspringen
    skipSchema: bool = False        # Migrationen (Constraints/Indizes) ueberspringen


def do_import(job_id: str, req: ImportReq):
    try:
        folder = DATA_DIR / req.dataset
        if not folder.is_dir():
            raise ValueError(f"Import-Ordner fehlt: data/import/{req.dataset}")
        lang = req.lang or DEFAULT_LANG
        jobs[job_id].update(status="running", dataset=req.dataset, step="start")

        # 1. Konvertieren (SE16-.txt -> .csv; Minimalset-Pruefung + Credential-Denylist im Konverter)
        if not req.skipConvert:
            jobs[job_id]["step"] = "convert"
            conv = convert.convert_folder(folder, required_config=CONFIG_DIR / "required_tables.json")
            jobs[job_id]["converted"] = conv["converted"]
            jobs[job_id]["missingOptional"] = conv["missingOptional"]

        with driver.session() as s:
            # 2. Schema sicherstellen (idempotente CREATE ... IF NOT EXISTS)
            if not req.skipSchema:
                jobs[job_id]["step"] = "schema"
                for f in sorted(MIGRATIONS_DIR.glob("*.cypher")):
                    run_cypher_path(s, f, {})
            # 3. Laden (Reihenfolge = Dateiname), mit dataset + lang
            for f in sorted(LOAD_DIR.glob("*.cypher")):
                jobs[job_id]["step"] = f"load {f.name}"
                run_cypher_path(s, f, {"dataset": req.dataset, "lang": lang})
            # 4. Validieren (eigene Zaehler statt Konsolen-Output)
            jobs[job_id]["step"] = "validate"
            rec = s.run(
                "OPTIONAL MATCH (u:User {dataset:$d}) WITH count(u) AS users "
                "OPTIONAL MATCH (r:Role {dataset:$d}) WITH users, count(r) AS roles "
                "OPTIONAL MATCH (a:Authorization {dataset:$d}) RETURN users, roles, count(a) AS auths",
                d=req.dataset).single()
        jobs[job_id].update(status="done", step="done",
                            users=rec["users"], roles=rec["roles"], auths=rec["auths"])
    except Exception as e:  # noqa: BLE001
        jobs[job_id].update(status="error", error=str(e))


def do_explain(job_id: str, run_id: str):
    """Evidenz (VIA_ROLE/VIA_PROFILE + conflictType) fuer einen bestehenden Lauf nachrechnen.
    Scope (ruleset/dataset/asOf) kommt aus dem (:Run)-Knoten."""
    try:
        with driver.session() as s:
            run = s.run("MATCH (r:Run {runId:$id}) RETURN r.ruleset AS ruleset, r.dataset AS dataset, "
                        "r.asOf AS asOf", id=run_id).single()
            if not run:
                raise ValueError(f"Lauf '{run_id}' nicht gefunden")
            jobs[job_id].update(status="running", step="explain", runId=run_id)
            run_file(s, "sod/explain_sod.cypher",
                     {"ruleset": run["ruleset"], "dataset": run["dataset"],
                      "asOf": run["asOf"], "runId": run_id})
            rec = s.run("MATCH (f:SoDConflict {runId:$id}) RETURN count(f) AS findings, "
                        "sum(CASE WHEN f.conflictType='intra' THEN 1 ELSE 0 END) AS intra, "
                        "sum(CASE WHEN f.conflictType='inter' THEN 1 ELSE 0 END) AS inter", id=run_id).single()
        jobs[job_id].update(status="done", step="done",
                            findings=rec["findings"], intra=rec["intra"], inter=rec["inter"])
    except Exception as e:  # noqa: BLE001
        jobs[job_id].update(status="error", error=str(e))


def do_delete_run(job_id: str, run_id: str):
    """Loescht einen einzelnen Auswertungslauf (Run + Findings); Dataset bleibt unberuehrt."""
    try:
        jobs[job_id].update(status="running", step="delete", runId=run_id)
        with driver.session() as s:
            run_file(s, "admin/delete_run.cypher", {"runId": run_id})
        jobs[job_id].update(status="done", step="done")
    except Exception as e:  # noqa: BLE001
        jobs[job_id].update(status="error", error=str(e))


def do_clear(job_id: str, dataset: str):
    try:
        jobs[job_id].update(status="running", step="clear", dataset=dataset)
        with driver.session() as s:
            run_file(s, "admin/clear_dataset.cypher", {"dataset": dataset})
            rec = s.run("MATCH (n {dataset:$d}) RETURN count(n) AS remaining", d=dataset).single()
        jobs[job_id].update(status="done", step="done", remaining=rec["remaining"])
    except Exception as e:  # noqa: BLE001
        jobs[job_id].update(status="error", error=str(e))


def do_reset(job_id: str):
    try:
        jobs[job_id].update(status="running", step="reset")
        with driver.session() as s:
            run_file(s, "admin/reset_data.cypher", {})
            rec = s.run("MATCH (n) WHERE NOT n:Query AND NOT n:SoDRule AND NOT n:AuthReq "
                        "AND NOT n:Clause AND NOT n:__Neo4jMigration "
                        "RETURN count(n) AS remaining").single()
            q = s.run("MATCH (q:Query) RETURN count(q) AS queries").single()
        jobs[job_id].update(status="done", step="done",
                            remaining=rec["remaining"], rulesetQueries=q["queries"])
    except Exception as e:  # noqa: BLE001
        jobs[job_id].update(status="error", error=str(e))


# --- Backup/Restore (Quelldaten-Ebene) -------------------------------------------------
# Backup = ZIP der konvertierten, credential-bereinigten .csv eines Datasets (+ manifest.json);
# Restore = entpacken + deterministischer Re-Import. Online, transportabel (eine Datei), trust-aware
# (nur bereinigte .csv, nie die rohen .txt). Findings sind regenerierbar (neu auswerten nach Restore).
_SAFE_NAME = re.compile(r"^[A-Za-z0-9._-]+$")


def _backup_path(file: str) -> Path:
    if not _SAFE_NAME.match(file) or not file.endswith(".zip"):
        raise HTTPException(400, "ungueltiger Dateiname")
    p = (BACKUP_DIR / file).resolve()
    if p.parent != BACKUP_DIR.resolve() or not p.is_file():
        raise HTTPException(404, "Backup nicht gefunden")
    return p


def do_backup(job_id: str, dataset: str, clear: bool):
    try:
        folder = DATA_DIR / dataset
        if not folder.is_dir():
            raise ValueError(f"Import-Ordner fehlt: data/import/{dataset}")
        jobs[job_id].update(status="running", step="backup", dataset=dataset)
        csvs = sorted(folder.glob("*.csv"))
        if not csvs:   # nur .txt vorhanden -> erst konvertieren (bereinigte .csv erzeugen)
            convert.convert_folder(folder, required_config=CONFIG_DIR / "required_tables.json")
            csvs = sorted(folder.glob("*.csv"))
        if not csvs:
            raise ValueError("keine .csv/.txt zum Sichern gefunden")

        BACKUP_DIR.mkdir(parents=True, exist_ok=True)
        ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        name = f"{dataset}__{ts}.zip"
        manifest = {"dataset": dataset, "createdAt": datetime.datetime.now().isoformat(timespec="seconds"),
                    "tables": [{"table": c.stem, "bytes": c.stat().st_size} for c in csvs]}
        with zipfile.ZipFile(BACKUP_DIR / name, "w", zipfile.ZIP_DEFLATED) as z:
            z.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))
            for c in csvs:
                z.write(c, arcname=f"csv/{c.name}")
        jobs[job_id].update(backup=name, sizeBytes=(BACKUP_DIR / name).stat().st_size, tables=len(csvs))

        if clear:   # "Backup & Clear": Graph des Datasets leeren (Ruleset/Schema bleiben)
            jobs[job_id]["step"] = "clear"
            with driver.session() as s:
                run_file(s, "admin/clear_dataset.cypher", {"dataset": dataset})
            jobs[job_id]["cleared"] = True
        jobs[job_id].update(status="done", step="done")
    except Exception as e:  # noqa: BLE001
        jobs[job_id].update(status="error", error=str(e))


def do_restore(job_id: str, path: Path, dataset: str | None):
    try:
        jobs[job_id].update(status="running", step="unpack")
        with zipfile.ZipFile(path) as z:
            manifest = json.loads(z.read("manifest.json"))
            target = dataset or manifest["dataset"]
            if not _SAFE_NAME.match(target):
                raise ValueError(f"ungueltiger Ziel-Dataset-Name: {target}")
            dest = DATA_DIR / target
            dest.mkdir(parents=True, exist_ok=True)
            for n in z.namelist():
                if n.startswith("csv/") and n.endswith(".csv"):
                    (dest / Path(n).name).write_bytes(z.read(n))
        # .csv liegen jetzt vor -> Re-Import ohne Konvertierung (Schema idempotent sicherstellen)
        do_import(job_id, ImportReq(dataset=target, skipConvert=True, skipSchema=False))
    except Exception as e:  # noqa: BLE001
        jobs[job_id].update(status="error", error=str(e))


# --- Backup/Restore (Auswertungslauf-Ebene) --------------------------------------------
# Lauf-Backup = ZIP aus manifest.json (Provenienz inkl. Dataset-uid) + run.json + findings.json.
# Getrennt von Quelldaten-Backups (oben): sichert das ABGELEITETE Ergebnis eines Laufs, kein
# Re-Import. Restore prueft die Dataset-uid aus dem Manifest gegen die aktuelle Dataset-uid —
# Mismatch bedeutet "das Dataset wurde seit dem Lauf neu befuellt", Restore dann nur mit
# force=true (Warnung wird vom Frontend angezeigt).
def _run_backup_path(file: str) -> Path:
    if not _SAFE_NAME.match(file) or not file.endswith(".zip"):
        raise HTTPException(400, "ungueltiger Dateiname")
    p = (RUN_BACKUP_DIR / file).resolve()
    if p.parent != RUN_BACKUP_DIR.resolve() or not p.is_file():
        raise HTTPException(404, "Lauf-Backup nicht gefunden")
    return p


def _dataset_uid(s, dataset: str) -> str | None:
    """Aktuelle Dataset-uid; legt sie nach (lazy backfill), falls das Dataset noch keine hat."""
    rec = s.run("MATCH (d:Dataset {id:$id}) SET d.uid = coalesce(d.uid, randomUUID()) "
                "RETURN d.uid AS uid", id=dataset).single()
    return rec["uid"] if rec else None


def do_backup_run(job_id: str, run_id: str):
    try:
        jobs[job_id].update(status="running", step="backup", runId=run_id)
        with driver.session() as s:
            rec = s.run("MATCH (r:Run {runId:$id}) RETURN r AS run", id=run_id).single()
            if not rec:
                raise ValueError(f"Lauf '{run_id}' nicht gefunden")
            run_d = jsonable(dict(rec["run"]))
            dataset_uid = _dataset_uid(s, run_d["dataset"])
            findings = [jsonable(dict(r)) for r in s.run(
                "MATCH (u:User)-[:VIOLATES]->(f:SoDConflict {runId:$id})-[:BASED_ON]->(rule:SoDRule) "
                "RETURN u.id AS user, f.ruleId AS rule, f.criticality AS criticality, "
                "f.criticalityRank AS criticalityRank, f.asOf AS asOf, f.reasonCode AS reasonCode, "
                "coalesce(f.userSleeping,false) AS sleeping, f.conflictType AS conflictType",
                id=run_id)]
        RUN_BACKUP_DIR.mkdir(parents=True, exist_ok=True)
        ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        name = f"{run_id}__{ts}.run.zip"
        manifest = {"runId": run_id, "dataset": run_d["dataset"], "datasetUid": dataset_uid,
                    "ruleset": run_d.get("ruleset"), "title": run_d.get("title"), "asOf": run_d.get("asOf"),
                    "generatedAt": run_d.get("generatedAt"),
                    "createdAt": datetime.datetime.now().isoformat(timespec="seconds"),
                    "findingsCount": len(findings)}
        with zipfile.ZipFile(RUN_BACKUP_DIR / name, "w", zipfile.ZIP_DEFLATED) as z:
            z.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))
            z.writestr("run.json", json.dumps(run_d, ensure_ascii=False, indent=2))
            z.writestr("findings.json", json.dumps(findings, ensure_ascii=False, indent=2))
        jobs[job_id].update(status="done", step="done", backup=name, findings=len(findings),
                            sizeBytes=(RUN_BACKUP_DIR / name).stat().st_size)
    except Exception as e:  # noqa: BLE001
        jobs[job_id].update(status="error", error=str(e))


def do_restore_run(job_id: str, path: Path, force: bool):
    try:
        jobs[job_id].update(status="running", step="check")
        with zipfile.ZipFile(path) as z:
            manifest = json.loads(z.read("manifest.json"))
            run_d = json.loads(z.read("run.json"))
            findings = json.loads(z.read("findings.json"))
        with driver.session() as s:
            current_uid = _dataset_uid(s, manifest["dataset"])
            if not force and current_uid != manifest.get("datasetUid"):
                raise ValueError(
                    f"Dataset '{manifest['dataset']}' hat sich seit diesem Lauf-Backup geaendert "
                    "(anderer Datenstand) — Wiederherstellung nur mit ausdruecklicher Bestaetigung.")
            jobs[job_id]["step"] = "restore"
            run_file(s, "admin/restore_run.cypher",
                     {"run": run_d, "findings": findings, "runId": manifest["runId"]})
            rec = s.run("MATCH (f:SoDConflict {runId:$id}) RETURN count(f) AS restored",
                        id=manifest["runId"]).single()
        jobs[job_id].update(status="done", step="done", runId=manifest["runId"],
                            restored=rec["restored"], total=len(findings))
    except Exception as e:  # noqa: BLE001
        jobs[job_id].update(status="error", error=str(e))


def do_upload_import(job_id: str, zip_path: str, dataset: str, lang: list[str], skip_schema: bool):
    """Entpackt ein hochgeladenes ZIP (.csv und/oder .txt) nach data/import/<dataset> und importiert.
    .txt vorhanden -> konvertieren; nur .csv -> Konvertierung ueberspringen."""
    try:
        jobs[job_id].update(status="running", step="unpack", dataset=dataset)
        dest = DATA_DIR / dataset
        dest.mkdir(parents=True, exist_ok=True)
        extracted, has_txt = 0, False
        with zipfile.ZipFile(zip_path) as z:
            for n in z.namelist():
                low = n.lower()
                if low.endswith(".csv") or low.endswith(".txt"):
                    (dest / Path(n).name).write_bytes(z.read(n))
                    extracted += 1
                    has_txt = has_txt or low.endswith(".txt")
        if not extracted:
            raise ValueError("ZIP enthielt keine .csv/.txt-Dateien")
        do_import(job_id, ImportReq(dataset=dataset, lang=lang,
                                    skipConvert=not has_txt, skipSchema=skip_schema))
    except Exception as e:  # noqa: BLE001
        jobs[job_id].update(status="error", error=str(e))
    finally:
        try:
            os.remove(zip_path)
        except OSError:
            pass


@app.get("/health")
def health():
    with driver.session() as s:
        s.run("RETURN 1").consume()
    return {"status": "ok"}


@app.get("/datasets")
def datasets():
    with driver.session() as s:
        return [r["id"] for r in s.run("MATCH (d:Dataset) RETURN d.id AS id ORDER BY id")]


@app.get("/profiles")
def profiles_meta():
    """Speist die Formular-Dropdowns der UI (datengetrieben aus config + rules)."""
    cfg = profiles()
    return {
        "rulesets": list_rulesets(),
        "defaultRuleset": cfg.get("defaults", {}).get("ruleset"),
        "orgProfiles": [{"name": p["name"], "description": p.get("description", "")} for p in cfg["profiles"]],
        "userTypeProfiles": [{"name": p["name"], "description": p.get("description", "")} for p in cfg["userTypeProfiles"]],
        "scopeProfiles": [{"name": p["name"], "description": p.get("description", "")} for p in cfg.get("scopeProfiles", [])],
        "sleepDays": cfg["sleeping"]["sleepDays"],
    }


@app.get("/admin/rulesets/{ruleset}/queries")
def admin_list_queries(ruleset: str):
    """Alle Queries eines Rulesets (Vendor + Overlay effektiv gemerged) fuer den
    Einzelfilter-Editor; 'custom' markiert eigene Edits/abgeleitete Queries."""
    merged, custom_ids = _merged_queries(ruleset)
    return [{"id": qid, "description": q.get("description", ""),
             "shortDescription": q.get("shortDescription", ""), "criticality": q.get("criticality"),
             "module": q.get("module"), "queryType": q.get("queryType"),
             "disregardTcode": bool(q.get("disregardTcode", False)), "custom": qid in custom_ids}
            for qid, q in sorted(merged.items())]


class QueryEditReq(BaseModel):
    description: str | None = None
    shortDescription: str | None = None
    criticality: str | None = None
    module: str | None = None
    queryType: str | None = None
    disregardTcode: bool | None = None


@app.put("/admin/rulesets/{ruleset}/queries/{queryId}")
def admin_update_query(ruleset: str, queryId: str, req: QueryEditReq):
    """Bearbeitet Metadaten einer Query als Overlay-Eintrag (queries.custom.json) — Vendor-Datei
    bleibt unberuehrt. Ladet das Ruleset danach sofort neu (Edit wirkt ohne extra Schritt)."""
    merged, _ = _merged_queries(ruleset)
    if queryId not in merged:
        raise HTTPException(404, f"Query '{queryId}' nicht gefunden")
    custom_path = ensure_custom_queries_file(ruleset)
    custom = _load_json_list(custom_path)
    entry = next((c for c in custom if c["query"] == queryId), None)
    fields = {k: v for k, v in req.model_dump().items() if v is not None}
    if entry:
        entry.update(fields)
    else:
        custom.append({"query": queryId, **fields})
    custom_path.write_text(json.dumps(custom, ensure_ascii=False, indent=2), encoding="utf-8")
    reload_ruleset(ruleset)
    return {"query": queryId, "saved": fields}


class QueryDeriveReq(BaseModel):
    newId: str
    fromId: str
    description: str | None = None
    shortDescription: str | None = None
    criticality: str | None = None
    module: str | None = None
    queryType: str | None = None
    disregardTcode: bool | None = None


@app.post("/admin/rulesets/{ruleset}/queries/derive")
def admin_derive_query(ruleset: str, req: QueryDeriveReq):
    """Legt eine neue Query als Kopie einer bestehenden an (authorizations/transactions 1:1
    uebernommen; nur Metadaten hier optional ueberschrieben) — landet im Overlay, die
    Quell-Query bleibt unberuehrt. Ladet das Ruleset danach sofort neu."""
    if not _SAFE_NAME.match(req.newId):
        raise HTTPException(400, "ungueltige Query-ID (erlaubt: Buchstaben/Ziffern/._-)")
    merged, _ = _merged_queries(ruleset)
    if req.newId in merged:
        raise HTTPException(409, f"Query-ID '{req.newId}' existiert bereits")
    src = merged.get(req.fromId)
    if not src:
        raise HTTPException(404, f"Quell-Query '{req.fromId}' nicht gefunden")
    new_q = dict(src)
    new_q["query"] = req.newId
    new_q["derivedFrom"] = req.fromId
    for field in ("description", "shortDescription", "criticality", "module", "queryType", "disregardTcode"):
        v = getattr(req, field)
        if v is not None:
            new_q[field] = v
    custom_path = ensure_custom_queries_file(ruleset)
    custom = _load_json_list(custom_path)
    custom.append(new_q)
    custom_path.write_text(json.dumps(custom, ensure_ascii=False, indent=2), encoding="utf-8")
    reload_ruleset(ruleset)
    return {"query": req.newId, "derivedFrom": req.fromId}


@app.get("/runs")
def list_runs():
    with driver.session() as s:
        out = []
        for r in s.run(
                "MATCH (run:Run) "
                "CALL { WITH run MATCH (f:SoDConflict {runId:run.runId, dataset:run.dataset}) "
                "  RETURN count(f) AS findings, count(DISTINCT f.ruleId) AS rules, "
                "         sum(CASE WHEN f.userSleeping THEN 1 ELSE 0 END) AS sleeping } "
                "RETURN run, findings, rules, sleeping ORDER BY run.runId"):
            d = jsonable(dict(r["run"]))
            d.update(findings=r["findings"], rules=r["rules"], sleeping=r["sleeping"])
            out.append(d)
        return out


_FINDINGS_WHERE = (
    "WHERE coalesce(f.criticalityRank,0) >= $minRank "
    "  AND ($user IS NULL OR u.id = $user) "
    "  AND ($rule IS NULL OR f.ruleId = $rule) "
    "  AND (size($userTypes) = 0 OR any(t IN $userTypes WHERE t IN labels(u))) "
    "  AND ($sleeping IS NULL OR coalesce(f.userSleeping,false) = $sleeping) "
    "  AND ($ruleCriticality IS NULL OR f.criticality = $ruleCriticality) "
)


@app.get("/findings")
def findings(runId: str, minRank: int = 0, limit: int = 200,
             user: str | None = None, rule: str | None = None,
             userType: list[str] = Query(default=[]), sleeping: bool | None = None,
             ruleCriticality: str | None = None):
    """Findings eines Laufs; optional auf User/Regel/Nutzertyp(en)/Sleeping/Kritikalitaet
    eingeschraenkt (Drill-down: Klick auf User-/Regel-Zelle, oder Ergebnisfilter in der Sidebar)."""
    with driver.session() as s:
        return [jsonable(dict(r)) for r in s.run(
            "MATCH (u:User)-[:VIOLATES]->(f:SoDConflict {runId:$runId})-[:BASED_ON]->(rule:SoDRule) "
            + _FINDINGS_WHERE +
            "RETURN u.id AS user, f.ruleId AS rule, f.criticality AS criticality, "
            "       coalesce(f.userSleeping,false) AS sleeping, f.conflictType AS conflictType, "
            "       [(f)-[:VIA_ROLE]->(r) | r.id] AS roles, "
            "       [(f)-[:VIA_PROFILE]->(p) | p.id] AS profiles "
            "ORDER BY coalesce(f.criticalityRank,0) DESC, user LIMIT $limit",
            runId=runId, minRank=minRank, limit=limit, user=user, rule=rule,
            userTypes=userType, sleeping=sleeping, ruleCriticality=ruleCriticality)]


@app.get("/findings/summary")
def findings_summary(runId: str, minRank: int = 0, user: str | None = None, rule: str | None = None,
                      userType: list[str] = Query(default=[]), sleeping: bool | None = None,
                      ruleCriticality: str | None = None):
    """KPI-Aggregate (Findings/betroffene Regeln/sleeping) fuer den aktuellen Filterkontext —
    unabhaengig vom Limit der Findings-Liste, damit die KPI-Kacheln zum gewaehlten Filter passen."""
    with driver.session() as s:
        rec = s.run(
            "MATCH (u:User)-[:VIOLATES]->(f:SoDConflict {runId:$runId})-[:BASED_ON]->(rule:SoDRule) "
            + _FINDINGS_WHERE +
            "RETURN count(f) AS findings, count(DISTINCT f.ruleId) AS rules, "
            "       sum(CASE WHEN coalesce(f.userSleeping,false) THEN 1 ELSE 0 END) AS sleeping",
            runId=runId, minRank=minRank, user=user, rule=rule,
            userTypes=userType, sleeping=sleeping, ruleCriticality=ruleCriticality).single()
        return jsonable(dict(rec))


@app.get("/queries")
def queries(runId: str):
    """SoD-relevante Queries (Einzelfilter) des Rulesets eines Laufs — speist die
    Query-Auswahl fuer den Matches-Drill-down ('wer matcht Query X')."""
    with driver.session() as s:
        run = s.run("MATCH (r:Run {runId:$id}) RETURN r.ruleset AS ruleset", id=runId).single()
        if not run:
            raise HTTPException(404, f"Lauf '{runId}' nicht gefunden")
        return [dict(r) for r in s.run(
            "MATCH (q:Query {ruleset:$ruleset}) "
            "WHERE EXISTS { (q)<-[:NEEDS]-(:Clause {ruleset:$ruleset}) } "
            "RETURN q.id AS id, q.description AS description, q.shortDescription AS shortDescription, "
            "q.criticality AS criticality, q.module AS module ORDER BY id", ruleset=run["ruleset"])]


@app.get("/sodrules")
def sod_rules(runId: str):
    """SoD-Regeln (mit Bezeichnung) des Rulesets eines Laufs — speist die SoD-Auswahl
    in der Sidebar (Bezeichnung statt nur der Regel-ID)."""
    with driver.session() as s:
        run = s.run("MATCH (r:Run {runId:$id}) RETURN r.ruleset AS ruleset", id=runId).single()
        if not run:
            raise HTTPException(404, f"Lauf '{runId}' nicht gefunden")
        return [dict(r) for r in s.run(
            "MATCH (rule:SoDRule {ruleset:$ruleset}) "
            "RETURN rule.id AS id, rule.description AS description, "
            "rule.shortDescription AS shortDescription, rule.criticality AS criticality "
            "ORDER BY id", ruleset=run["ruleset"])]


@app.get("/matches")
def matches(runId: str, query: str | None = None, user: str | None = None,
            userType: list[str] = Query(default=[])):
    """Wer matcht Query X (Einzelberechtigung) im Zwischenergebnis (:User)-[:MATCHES]->(:Query)
    eines Laufs — optional auf einen User/Nutzertyp(en) eingeschraenkt (Drill-down 'Query -> wer matcht')."""
    with driver.session() as s:
        return [dict(r) for r in s.run(
            "MATCH (u:User)-[:MATCHES {runId:$runId}]->(q:Query) "
            "WHERE ($qid IS NULL OR q.id = $qid) AND ($user IS NULL OR u.id = $user) "
            "  AND (size($userTypes) = 0 OR any(t IN $userTypes WHERE t IN labels(u))) "
            "RETURN u.id AS user, coalesce(u.name,'') AS name, "
            "       CASE WHEN 'Dialog' IN labels(u) THEN 'Dialog' WHEN 'System' IN labels(u) THEN 'System' "
            "            WHEN 'Service' IN labels(u) THEN 'Service' WHEN 'Communication' IN labels(u) THEN 'Comm' ELSE '?' END AS typ, "
            "       CASE WHEN 'Locked' IN labels(u) THEN 'gesperrt' ELSE 'aktiv' END AS status, "
            "       q.id AS query "
            "ORDER BY status, user", runId=runId, qid=query, user=user, userTypes=userType)]


@app.get("/findings/export")
def export_findings(runId: str):
    """Findings eines Laufs als CSV (Semikolon, UTF-8-BOM -> Excel-tauglich) — Ergebnis-Export
    getrennt vom Quell-Backup."""
    with driver.session() as s:
        rows = list(s.run(
            "MATCH (u:User)-[:VIOLATES]->(f:SoDConflict {runId:$r})-[:BASED_ON]->(rule:SoDRule) "
            "RETURN u.id AS user, f.ruleId AS rule, f.ruleset AS ruleset, f.dataset AS dataset, "
            "f.criticality AS criticality, coalesce(f.criticalityRank,0) AS criticalityRank, "
            "coalesce(f.userSleeping,false) AS sleeping, f.conflictType AS conflictType, "
            "[(f)-[:VIA_ROLE]->(r) | r.id] AS roles, [(f)-[:VIA_PROFILE]->(p) | p.id] AS profiles, "
            "f.reasonCode AS reasonCode "
            "ORDER BY criticalityRank DESC, user", r=runId))
    buf = io.StringIO()
    w = csv.writer(buf, delimiter=";")
    w.writerow(["user", "rule", "ruleset", "dataset", "criticality", "criticalityRank",
                "sleeping", "conflictType", "roles", "profiles", "reasonCode"])
    for x in rows:
        w.writerow([x["user"], x["rule"], x["ruleset"], x["dataset"], x["criticality"],
                    x["criticalityRank"], x["sleeping"], x["conflictType"],
                    "|".join(x["roles"] or []), "|".join(x["profiles"] or []), x["reasonCode"]])
    data = "﻿" + buf.getvalue()   # BOM, damit Excel UTF-8/Umlaute korrekt liest
    return Response(content=data, media_type="text/csv; charset=utf-8",
                   headers={"Content-Disposition": f'attachment; filename="findings_{runId}.csv"'})


@app.post("/imports")
def start_import(req: ImportReq):
    job_id = str(uuid.uuid4())
    jobs[job_id] = {"status": "queued", "kind": "import", "request": req.model_dump()}
    threading.Thread(target=do_import, args=(job_id, req), daemon=True).start()
    return {"jobId": job_id}


@app.post("/imports/upload")
async def upload_import(file: UploadFile = File(...), dataset: str = Form(""),
                        lang: str = Form(""), skipSchema: bool = Form(False)):
    """Import per ZIP-Upload: .csv/.txt im ZIP -> data/import/<dataset> -> Import-Job."""
    ds = re.sub(r"[^A-Za-z0-9._-]", "_", dataset or Path(file.filename or "import").stem)
    if not ds:
        raise HTTPException(400, "dataset-Name leer/ungueltig")
    tmp = Path(tempfile.gettempdir()) / f"upload_{uuid.uuid4().hex}.zip"
    with open(tmp, "wb") as out:
        shutil.copyfileobj(file.file, out)
    langs = [c.strip() for c in lang.split(",") if c.strip()]
    job_id = str(uuid.uuid4())
    jobs[job_id] = {"status": "queued", "kind": "import",
                    "request": {"dataset": ds, "upload": file.filename}}
    threading.Thread(target=do_upload_import, args=(job_id, str(tmp), ds, langs, skipSchema),
                     daemon=True).start()
    return {"jobId": job_id, "dataset": ds}


@app.get("/import-folders")
def import_folders():
    """Vorhandene data/import/<dataset>-Ordner (mit/ohne bereits konvertierte .csv)."""
    if not DATA_DIR.exists():
        return []
    out = []
    for d in sorted(p for p in DATA_DIR.iterdir() if p.is_dir()):
        txt, csv = len(list(d.glob("*.txt"))), len(list(d.glob("*.csv")))
        if txt or csv:   # nur echte Import-Ordner (SE16-.txt oder bereits konvertierte .csv)
            out.append({"dataset": d.name, "txt": txt, "csv": csv})
    return out


@app.post("/runs/{runId}/explain")
def explain_run(runId: str):
    """Evidenz (verursachende Rollen/Profile, intra/inter) fuer einen Lauf nachrechnen (teuer)."""
    job_id = str(uuid.uuid4())
    jobs[job_id] = {"status": "queued", "kind": "explain", "request": {"runId": runId}}
    threading.Thread(target=do_explain, args=(job_id, runId), daemon=True).start()
    return {"jobId": job_id}


@app.post("/runs/{runId}/delete")
def delete_run(runId: str):
    """Loescht einen einzelnen Auswertungslauf (Run + Findings); Dataset bleibt unberuehrt."""
    job_id = str(uuid.uuid4())
    jobs[job_id] = {"status": "queued", "kind": "delete_run", "request": {"runId": runId}}
    threading.Thread(target=do_delete_run, args=(job_id, runId), daemon=True).start()
    return {"jobId": job_id}


@app.post("/runs/{runId}/backup")
def backup_run(runId: str):
    """Sichert einen Auswertungslauf (Run + Findings, ohne Evidenz) als eigenes ZIP."""
    job_id = str(uuid.uuid4())
    jobs[job_id] = {"status": "queued", "kind": "backup_run", "request": {"runId": runId}}
    threading.Thread(target=do_backup_run, args=(job_id, runId), daemon=True).start()
    return {"jobId": job_id}


@app.get("/runs/backups")
def list_run_backups():
    if not RUN_BACKUP_DIR.exists():
        return []
    out = []
    for p in sorted(RUN_BACKUP_DIR.glob("*.zip"), key=lambda x: x.stat().st_mtime, reverse=True):
        with zipfile.ZipFile(p) as z:
            manifest = json.loads(z.read("manifest.json"))
        out.append({"file": p.name, **manifest, "sizeBytes": p.stat().st_size})
    return out


@app.get("/runs/backups/{file}/download")
def download_run_backup(file: str):
    return FileResponse(_run_backup_path(file), filename=file, media_type="application/zip")


class RunRestoreReq(BaseModel):
    force: bool = False     # true = trotz abweichender Dataset-uid wiederherstellen


@app.post("/runs/backups/{file}/restore")
def restore_run_backup(file: str, req: RunRestoreReq):
    path = _run_backup_path(file)
    job_id = str(uuid.uuid4())
    jobs[job_id] = {"status": "queued", "kind": "restore_run", "request": {"file": file, "force": req.force}}
    threading.Thread(target=do_restore_run, args=(job_id, path, req.force), daemon=True).start()
    return {"jobId": job_id}


@app.post("/datasets/{dataset}/clear")
def clear_dataset(dataset: str):
    """Loescht ein Dataset (inkl. Runs/Findings); Ruleset + Schema bleiben."""
    job_id = str(uuid.uuid4())
    jobs[job_id] = {"status": "queued", "kind": "clear", "request": {"dataset": dataset}}
    threading.Thread(target=do_clear, args=(job_id, dataset), daemon=True).start()
    return {"jobId": job_id}


@app.post("/reset")
def reset_data():
    """Setzt alle Daten zurueck (alle Datasets/Runs/Findings); Ruleset + Schema bleiben."""
    job_id = str(uuid.uuid4())
    jobs[job_id] = {"status": "queued", "kind": "reset", "request": {}}
    threading.Thread(target=do_reset, args=(job_id,), daemon=True).start()
    return {"jobId": job_id}


@app.post("/datasets/{dataset}/backup")
def backup_dataset(dataset: str, clear: bool = False):
    """Sichert die .csv eines Datasets als ZIP; clear=true leert danach den Graph (Backup & Clear)."""
    job_id = str(uuid.uuid4())
    jobs[job_id] = {"status": "queued", "kind": "backup", "request": {"dataset": dataset, "clear": clear}}
    threading.Thread(target=do_backup, args=(job_id, dataset, clear), daemon=True).start()
    return {"jobId": job_id}


@app.get("/backups")
def list_backups():
    if not BACKUP_DIR.exists():
        return []
    out = []
    for p in sorted(BACKUP_DIR.glob("*.zip"), key=lambda x: x.stat().st_mtime, reverse=True):
        st = p.stat()
        out.append({"file": p.name, "dataset": p.name.split("__")[0], "sizeBytes": st.st_size,
                    "createdAt": datetime.datetime.fromtimestamp(st.st_mtime).isoformat(timespec="seconds")})
    return out


@app.get("/backups/{file}/download")
def download_backup(file: str):
    return FileResponse(_backup_path(file), filename=file, media_type="application/zip")


class RestoreReq(BaseModel):
    dataset: str | None = None      # Ziel-Dataset (Default: aus dem Manifest des Backups)


@app.post("/backups/{file}/restore")
def restore_backup(file: str, req: RestoreReq):
    path = _backup_path(file)
    job_id = str(uuid.uuid4())
    jobs[job_id] = {"status": "queued", "kind": "restore", "request": {"file": file, "dataset": req.dataset}}
    threading.Thread(target=do_restore, args=(job_id, path, req.dataset), daemon=True).start()
    return {"jobId": job_id}


@app.post("/runs")
def start_run(req: RunReq):
    job_id = str(uuid.uuid4())
    jobs[job_id] = {"status": "queued", "kind": "run", "request": req.model_dump()}
    threading.Thread(target=do_run, args=(job_id, req), daemon=True).start()
    return {"jobId": job_id}


@app.get("/jobs/{job_id}")
def job_status(job_id: str):
    if job_id not in jobs:
        raise HTTPException(404, "unbekannte Job-Id")
    return jobs[job_id]


# Minimale UI (Phase 9, Bau-Schritt 2): statische Single-Page, vom Backend ausgeliefert.
# Bewusst leichtgewichtig (kein Node/React-Build, ein Container) — das gebrandete NVL/React-
# Frontend bleibt der spaetere "Fancy"-Schritt. MUSS nach allen API-Routen gemountet werden,
# damit "/" die UI liefert, ohne /health, /runs, ... zu ueberdecken.
if FRONTEND_DIR.exists():
    app.mount("/", StaticFiles(directory=str(FRONTEND_DIR), html=True), name="ui")
