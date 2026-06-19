"""IAM SoD Backend (Phase 9, Bau-Schritt 1) — Runner-as-API.

Orchestriert die vorhandenen cypher/-Dateien ueber den Neo4j-Treiber (apoc.cypher.runFile),
loest Profile aus config/analysis_profiles.json auf und faehrt Materialisierung+Auswertung als
asynchronen Job. Plattformunabhaengig im Container; ersetzt die PowerShell-Runner durch HTTP.
Bewusst MVP: In-Memory-Jobs (Single-Instance), Findings bleiben im Graph (kein eigener Store).
"""
import os
import json
import uuid
import datetime
import threading
from pathlib import Path

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from neo4j import GraphDatabase

NEO4J_URI = os.environ.get("NEO4J_URI", "bolt://neo4j:7687")
NEO4J_USER = os.environ.get("NEO4J_USER", "neo4j")
NEO4J_PASSWORD = os.environ["NEO4J_PASSWORD"]
CONFIG_DIR = Path(os.environ.get("CONFIG_DIR", "/app/config"))
RULES_DIR = Path(os.environ.get("RULES_DIR", "/app/rules"))
CYPHER_DIR = Path(os.environ.get("CYPHER_DIR", "/app/cypher"))

driver = GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USER, NEO4J_PASSWORD))
app = FastAPI(title="IAM SoD Backend", version="0.1.0")
jobs: dict[str, dict] = {}  # jobId -> status


def profiles() -> dict:
    return json.loads((CONFIG_DIR / "analysis_profiles.json").read_text(encoding="utf-8"))


def ruleset_dir(ruleset: str):
    if not RULES_DIR.exists():
        return None
    for d in RULES_DIR.iterdir():
        rj = d / "ruleset.json"
        if rj.is_file() and json.loads(rj.read_text(encoding="utf-8")).get("ruleset") == ruleset:
            return d.name
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


def run_file(session, rel_path: str, params: dict):
    text = (CYPHER_DIR / rel_path).read_text(encoding="utf-8")
    for stmt in split_statements(text):
        session.run(stmt, **params).consume()


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


@app.get("/health")
def health():
    with driver.session() as s:
        s.run("RETURN 1").consume()
    return {"status": "ok"}


@app.get("/datasets")
def datasets():
    with driver.session() as s:
        return [r["id"] for r in s.run("MATCH (d:Dataset) RETURN d.id AS id ORDER BY id")]


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


@app.post("/runs")
def start_run(req: RunReq):
    job_id = str(uuid.uuid4())
    jobs[job_id] = {"status": "queued", "request": req.model_dump()}
    threading.Thread(target=do_run, args=(job_id, req), daemon=True).start()
    return {"jobId": job_id}


@app.get("/jobs/{job_id}")
def job_status(job_id: str):
    if job_id not in jobs:
        raise HTTPException(404, "unbekannte Job-Id")
    return jobs[job_id]
