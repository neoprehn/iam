"""IAM SoD Backend (Phase 9, Bau-Schritt 1) — Runner-as-API.

Orchestriert die vorhandenen cypher/-Dateien ueber den Neo4j-Treiber (apoc.cypher.runFile),
loest Profile aus config/analysis_profiles.json auf und faehrt Materialisierung+Auswertung als
asynchronen Job. Plattformunabhaengig im Container; ersetzt die PowerShell-Runner durch HTTP.
Bewusst MVP: In-Memory-Jobs (Single-Instance), Findings bleiben im Graph (kein eigener Store).
"""
import os
import re
import json
import uuid
import zipfile
import datetime
import threading
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
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
FRONTEND_DIR = Path(os.environ.get("FRONTEND_DIR", "/app/frontend"))
DEFAULT_LANG = [c.strip() for c in os.environ.get("IMPORT_LANG", "DE,DEU,D").split(",") if c.strip()]

driver = GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USER, NEO4J_PASSWORD))
app = FastAPI(title="IAM SoD Backend", version="0.1.0")
jobs: dict[str, dict] = {}  # jobId -> status


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
    skipRulesetLoad: bool = True
    skipMaterialize: bool = False


def do_run(job_id: str, req: RunReq):
    try:
        cfg = profiles()
        utp = next((p for p in cfg["userTypeProfiles"] if p["name"] == req.userTypeProfile), None)
        if not utp:
            raise ValueError(f"userTypeProfile '{req.userTypeProfile}' unbekannt")
        op = next((p for p in cfg["profiles"] if p["name"] == req.orgProfile), None)
        if not op:
            raise ValueError(f"orgProfile '{req.orgProfile}' unbekannt")
        # orgProfile wird validiert + auf (:Run) protokolliert; die org-Feld-Filterung selbst ist
        # in materialize/evaluate noch nicht verdrahtet (Platzhalter-Aufloesung via AGR_1252 offen,
        # siehe config _runParameters.orgFilters) -> kein orgFilters-Param an die Cypher-Dateien.
        sleep_days = req.sleepDays if req.sleepDays is not None else int(cfg["sleeping"]["sleepDays"])
        run_id = req.runId or f"{req.ruleset}-{datetime.datetime.now():%Y%m%d%H%M%S}"
        as_of = datetime.date.fromisoformat(req.asOf)
        base = {"ruleset": req.ruleset, "dataset": req.dataset, "asOf": as_of, "runId": run_id}
        jobs[job_id].update(status="running", runId=run_id, step="start")

        with driver.session() as s:
            if not req.skipRulesetLoad:
                rdir = ruleset_dir(req.ruleset)
                if not rdir:
                    raise ValueError(f"Ruleset-Ordner fuer '{req.ruleset}' nicht gefunden")
                jobs[job_id]["step"] = "ruleset"
                run_file(s, "ruleset/load_ruleset.cypher", {"dir": rdir, "ruleset": req.ruleset})
            if not req.skipMaterialize:
                jobs[job_id]["step"] = "materialize"
                run_file(s, "sod/materialize_matches.cypher", base)
            jobs[job_id]["step"] = "evaluate"
            run_file(s, "sod/evaluate_sod.cypher", {
                **base,
                "userTypes": list(utp.get("userTypes", [])),
                "excludeLocked": bool(utp.get("excludeLocked", False)),
                "sleepDays": sleep_days,
                "minCriticalityRank": req.minCriticalityRank,
                "sodRules": req.sodRules,
            })
            rec = s.run(
                "MATCH (f:SoDConflict {runId:$r}) "
                "RETURN count(f) AS findings, count(DISTINCT f.ruleId) AS rules, "
                "sum(CASE WHEN f.userSleeping THEN 1 ELSE 0 END) AS sleeping", r=run_id,
            ).single()
        jobs[job_id].update(status="done", step="done",
                            findings=rec["findings"], rules=rec["rules"], sleeping=rec["sleeping"])
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


@app.get("/runs")
def list_runs():
    with driver.session() as s:
        return [jsonable(dict(r["run"])) for r in s.run(
            "MATCH (run:Run) RETURN run ORDER BY run.runId")]


@app.get("/findings")
def findings(runId: str, minRank: int = 0, limit: int = 200):
    with driver.session() as s:
        return [jsonable(dict(r)) for r in s.run(
            "MATCH (u:User)-[:VIOLATES]->(f:SoDConflict {runId:$runId})-[:BASED_ON]->(rule:SoDRule) "
            "WHERE coalesce(f.criticalityRank,0) >= $minRank "
            "RETURN u.id AS user, f.ruleId AS rule, f.criticality AS criticality, "
            "       coalesce(f.userSleeping,false) AS sleeping "
            "ORDER BY coalesce(f.criticalityRank,0) DESC, user LIMIT $limit",
            runId=runId, minRank=minRank, limit=limit)]


@app.post("/imports")
def start_import(req: ImportReq):
    job_id = str(uuid.uuid4())
    jobs[job_id] = {"status": "queued", "kind": "import", "request": req.model_dump()}
    threading.Thread(target=do_import, args=(job_id, req), daemon=True).start()
    return {"jobId": job_id}


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
