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
CHECKS_DIR = Path(os.environ.get("CHECKS_DIR", "/app/checks"))
CHECK_AREAS = {"user": ["A", "B", "C", "D", "E"], "role": ["R"]}
CYPHER_DIR = Path(os.environ.get("CYPHER_DIR", "/app/cypher"))
LOAD_DIR = Path(os.environ.get("LOAD_DIR", "/app/load"))
MIGRATIONS_DIR = Path(os.environ.get("MIGRATIONS_DIR", "/app/migrations"))
DATA_DIR = Path(os.environ.get("DATA_DIR", "/app/data/import"))
BACKUP_DIR = Path(os.environ.get("BACKUP_DIR", "/app/backups"))
RUN_BACKUP_DIR = BACKUP_DIR / "runs"
LOG_DIR = Path(os.environ.get("LOG_DIR", "/app/data/logs"))
JOB_ERROR_LOG = LOG_DIR / "job_errors.jsonl"
FRONTEND_DIR = Path(os.environ.get("FRONTEND_DIR", "/app/frontend"))
DEFAULT_LANG = [c.strip() for c in os.environ.get("IMPORT_LANG", "DE,DEU,D").split(",") if c.strip()]

driver = GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USER, NEO4J_PASSWORD))
app = FastAPI(title="IAM SoD Backend", version="0.1.0")
jobs: dict[str, dict] = {}  # jobId -> status


# --- Fehlerprotokoll (Job-Fehler) -------------------------------------------------------
# Persistiert fehlgeschlagene Jobs ueber Neustarts hinweg (jobs-Dict ist nur In-Memory).
# JSONL unter data/logs (Bind-Mount, ueberlebt Container-Neustart) statt Graph: rein operative
# Nachvollziehbarkeit, keine fachliche Ableitung (AE-10 betrifft die Findings-Schicht, nicht das).
def _log_job_error(job_id: str, message: str) -> None:
    entry = {
        "ts": datetime.datetime.now().isoformat(timespec="seconds"),
        "jobId": job_id,
        "kind": jobs.get(job_id, {}).get("kind"),
        "request": jobs.get(job_id, {}).get("request"),
        "message": message,
    }
    try:
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        with open(JOB_ERROR_LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except OSError:
        pass


@app.middleware("http")
async def no_cache_frontend(request, call_next):
    """Statische UI aendert sich oft (laufende Entwicklung) -> Browser sollen IMMER
    revalidieren (ETag/Last-Modified -> billiges 304 bei unveraendertem Inhalt) statt eine
    alte index.html ungeprueft aus dem Cache zu zeigen."""
    response = await call_next(request)
    if request.url.path == "/" or request.url.path.endswith(".html"):
        response.headers["Cache-Control"] = "no-cache"
    return response


ORG_PROFILES_VENDOR_PATH = CONFIG_DIR / "analysis_profiles.json"
ORG_PROFILES_CUSTOM_PATH = CONFIG_DIR / "analysis_profiles.custom.json"
PROTECTED_ORG_PROFILES = {"standard", "uebergreifend"}


def ensure_custom_org_profiles_file() -> Path:
    if not ORG_PROFILES_CUSTOM_PATH.is_file():
        ORG_PROFILES_CUSTOM_PATH.write_text("[]", encoding="utf-8")
    return ORG_PROFILES_CUSTOM_PATH


def profiles() -> dict:
    """Liest die Vendor-Profile UND merged die Org-Profile-Overlay-Datei
    (analysis_profiles.custom.json, vom Admin-Editor "Org-Varianten" geschrieben) hinein —
    analog zum Ruleset-Overlay-Mechanismus (queries.custom.json/sod_rules.custom.json), aber
    global statt pro Ruleset. Overlay-Namen, die mit einem Vendor-Profil kollidieren, werden
    beim Schreiben verhindert (s. admin_create_org_profile), hier nur defensiv gefiltert."""
    cfg = json.loads(ORG_PROFILES_VENDOR_PATH.read_text(encoding="utf-8"))
    vendor_names = {p["name"] for p in cfg["profiles"]}
    custom = _load_json_list(ORG_PROFILES_CUSTOM_PATH)
    cfg["profiles"] = cfg["profiles"] + [p for p in custom if p["name"] not in vendor_names]
    return cfg


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
    """Vendor-Queries + Overlay, Overlay-Felder gewinnen je id. Gibt (id -> effektive Query,
    Menge der STRUKTURELL eigenen ids) zurueck — 'eigen' heisst hier: komplett neue/abgeleitete
    Query (kein Vendor-Gegenstueck) ODER der Aufbau (authorizations/transactions) wurde
    ueberschrieben. Reine Metadaten-Ergaenzungen (Kurzbezeichnung, Risiko, Controls, ...) auf
    einer bestehenden Vendor-Query zaehlen NICHT als 'eigen' (s. Nutzerfeedback: das ist nur
    eine Info-Ergaenzung, keine inhaltliche Aenderung der Query)."""
    vendor_path, custom_path = _ruleset_paths(ruleset)
    merged = {q["query"]: dict(q) for q in _load_json_list(vendor_path)}
    custom_ids = set()
    for c in _load_json_list(custom_path):
        qid = c["query"]
        if qid not in merged or "authorizations" in c or "transactions" in c:
            custom_ids.add(qid)
        if qid in merged:
            merged[qid] = {**merged[qid], **{k: v for k, v in c.items() if v is not None}}
        else:
            merged[qid] = c
    return merged, custom_ids


def reload_ruleset(ruleset: str):
    rdir = ruleset_dir(ruleset)
    ensure_custom_queries_file(ruleset)    # beide Overlay-Dateien muessen existieren (apoc.load.json)
    ensure_custom_sodrules_file(ruleset)
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
    # Kein asOf mehr hier: der Stichtag ist eine Eigenschaft des Datasets (= Downloaddatum der
    # SAP-Extrakte), keine Lauf-/Filter-Eingabe. Wird ueber _dataset_asof() aufgeloest; Korrektur
    # nur global ueber PUT /datasets/{id}/asof.
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


def _slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def _humanize_profile_name(name: str) -> str:
    """Kurzer, lesbarer Lauf-Titel aus dem Org-Profil-Namen (z. B. 'bukrs-1000-und-2000' ->
    'Bukrs 1000 Und 2000') — analog zu defaultRunTitle() im Frontend (frontend/index.html), damit
    Einzel- und Batch-Laeufe denselben Titel-Stil haben (die volle Beschreibung waere als
    Run-Listen-Label zu lang)."""
    return " ".join(w[:1].upper() + w[1:] for w in re.split(r"[-_]+", name) if w)


def _run_one(s, job_id: str, cfg: dict, *, ruleset: str, dataset: str, user_type_profile: str,
             org_profile: str, sleep_days: int, min_criticality_rank: int, sod_rules: list[str],
             run_id: str, title: str, skip_ruleset_load: bool, skip_materialize: bool,
             skip_explain: bool, step_prefix: str = "") -> dict:
    """Ein einzelner Lauf (Profile aufloesen -> materialize -> evaluate -> optional explain ->
    Ergebnis-Zaehlung). Von do_run() (1 Variante) UND do_run_batch() (mehrere Varianten,
    gemeinsame Session) genutzt — step_prefix erlaubt dem Batch, den Fortschritt je Variante
    anzuzeigen (z. B. "Variante 2/3: uebergreifend - materialize")."""
    utp = next((p for p in cfg["userTypeProfiles"] if p["name"] == user_type_profile), None)
    if not utp:
        raise ValueError(f"userTypeProfile '{user_type_profile}' unbekannt")
    op = next((p for p in cfg["profiles"] if p["name"] == org_profile), None)
    if not op:
        raise ValueError(f"orgProfile '{org_profile}' unbekannt")
    org_mode = op["org"].get("mode", "ignoreOrg")
    org_filters = op["org"].get("filters", {}) if org_mode == "filtered" else {}
    org = {"orgMode": org_mode, "orgFilters": org_filters}

    as_of = _dataset_asof(s, dataset)
    base = {"ruleset": ruleset, "dataset": dataset, "asOf": as_of, "runId": run_id}
    if not skip_ruleset_load:
        rdir = ruleset_dir(ruleset)
        if not rdir:
            raise ValueError(f"Ruleset-Ordner fuer '{ruleset}' nicht gefunden")
        jobs[job_id]["step"] = step_prefix + "ruleset"
        ensure_custom_queries_file(ruleset)    # queries.custom.json muss existieren (apoc.load.json)
        ensure_custom_sodrules_file(ruleset)   # sod_rules.custom.json ebenso
        run_file(s, "ruleset/load_ruleset.cypher", {"dir": rdir, "ruleset": ruleset})
    if not skip_materialize:
        jobs[job_id]["step"] = step_prefix + "materialize"
        run_file(s, "sod/materialize_matches.cypher", {**base, **org})
    jobs[job_id]["step"] = step_prefix + "evaluate"
    run_file(s, "sod/evaluate_sod.cypher", {
        **base, **org,
        "userTypes": list(utp.get("userTypes", [])),
        "excludeLocked": bool(utp.get("excludeLocked", False)),
        "sleepDays": sleep_days,
        "minCriticalityRank": min_criticality_rank,
        "sodRules": sod_rules,
        "title": title,
    })
    if not skip_explain:
        jobs[job_id]["step"] = step_prefix + "explain"
        run_file(s, "sod/explain_sod.cypher", base)
    rec = s.run(
        "MATCH (f:SoDConflict {runId:$r}) "
        "RETURN count(f) AS findings, count(DISTINCT f.ruleId) AS rules, "
        "sum(CASE WHEN f.userSleeping THEN 1 ELSE 0 END) AS sleeping, "
        "sum(CASE WHEN f.conflictType='intra' THEN 1 ELSE 0 END) AS intra", r=run_id,
    ).single()
    return {"runId": run_id, "title": title, "findings": rec["findings"], "rules": rec["rules"],
            "sleeping": rec["sleeping"], "intra": rec["intra"]}


def do_run(job_id: str, req: RunReq):
    try:
        cfg = profiles()
        sleep_days = req.sleepDays if req.sleepDays is not None else int(cfg["sleeping"]["sleepDays"])
        run_id = req.runId or f"{req.ruleset}-{datetime.datetime.now():%Y%m%d%H%M%S}"
        title = req.title or run_id
        jobs[job_id].update(status="running", runId=run_id, step="start")
        with driver.session() as s:
            result = _run_one(s, job_id, cfg, ruleset=req.ruleset, dataset=req.dataset,
                               user_type_profile=req.userTypeProfile, org_profile=req.orgProfile,
                               sleep_days=sleep_days, min_criticality_rank=req.minCriticalityRank,
                               sod_rules=req.sodRules, run_id=run_id, title=title,
                               skip_ruleset_load=req.skipRulesetLoad, skip_materialize=req.skipMaterialize,
                               skip_explain=req.skipExplain)
        jobs[job_id].update(status="done", step="done", **result)
    except Exception as e:  # noqa: BLE001
        jobs[job_id].update(status="error", error=str(e))
        _log_job_error(job_id, str(e))


class RunBatchReq(BaseModel):
    ruleset: str = "kpmg_r3"
    dataset: str
    userTypeProfile: str = "all"
    orgProfiles: list[str]           # >=1 Org-Varianten; je Variante ein eigener Lauf
    sleepDays: int | None = None
    minCriticalityRank: int = 0
    sodRules: list[str] = []
    skipRulesetLoad: bool = True
    skipMaterialize: bool = False
    skipExplain: bool = True


def do_run_batch(job_id: str, req: RunBatchReq):
    try:
        if not req.orgProfiles:
            raise ValueError("orgProfiles darf nicht leer sein")
        cfg = profiles()
        sleep_days = req.sleepDays if req.sleepDays is not None else int(cfg["sleeping"]["sleepDays"])
        ts = f"{datetime.datetime.now():%Y%m%d%H%M%S}"
        jobs[job_id].update(status="running", step="start", runs=[])
        results = []
        n = len(req.orgProfiles)
        with driver.session() as s:
            for i, profile_name in enumerate(req.orgProfiles, start=1):
                op = next((p for p in cfg["profiles"] if p["name"] == profile_name), None)
                if not op:
                    raise ValueError(f"orgProfile '{profile_name}' unbekannt")
                run_id = f"{req.ruleset}-{ts}-{i}-{_slug(profile_name)}"
                title = _humanize_profile_name(profile_name)
                result = _run_one(
                    s, job_id, cfg, ruleset=req.ruleset, dataset=req.dataset,
                    user_type_profile=req.userTypeProfile, org_profile=profile_name,
                    sleep_days=sleep_days, min_criticality_rank=req.minCriticalityRank,
                    sod_rules=req.sodRules, run_id=run_id, title=title,
                    # Ruleset nur einmal laden (idempotent, aber unnoetig fuer jede Variante)
                    skip_ruleset_load=req.skipRulesetLoad or i > 1,
                    skip_materialize=req.skipMaterialize, skip_explain=req.skipExplain,
                    step_prefix=f"Variante {i}/{n} ({profile_name}): ",
                )
                results.append(result)
                jobs[job_id]["runs"] = results
        jobs[job_id].update(status="done", step="done", runs=results)
    except Exception as e:  # noqa: BLE001
        jobs[job_id].update(status="error", error=str(e))
        _log_job_error(job_id, str(e))


class ImportReq(BaseModel):
    dataset: str                    # Ordnername unter data/import/ (= dataset-Id)
    lang: list[str] = []            # Sprach-Schalter (SPRAS/LANGU); leer = Default (IMPORT_LANG)
    skipConvert: bool = False       # .csv liegen schon vor -> Konvertierung ueberspringen
    skipSchema: bool = False        # Migrationen (Constraints/Indizes) ueberspringen
    asOf: str | None = None         # 'YYYY-MM-DD' Stichtag (= Downloaddatum der SAP-Extrakte);
                                     # nur bei Erst-Import wirksam (ON CREATE), Default = heute.
                                     # Spaetere Korrektur ueber PUT /datasets/{id}/asof.


def do_import(job_id: str, req: ImportReq):
    try:
        folder = DATA_DIR / req.dataset
        if not folder.is_dir():
            raise ValueError(f"Import-Ordner fehlt: data/import/{req.dataset}")
        lang = req.lang or DEFAULT_LANG
        as_of = (datetime.date.fromisoformat(req.asOf) if req.asOf
                 else (_infer_dataset_asof(req.dataset) or datetime.date.today()))
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
            # 3. Laden (Reihenfolge = Dateiname), mit dataset + lang + asOf (nur 00_dataset.cypher
            # nutzt asOf, ungenutzte gebundene Parameter in den anderen Loadern sind unschaedlich)
            for f in sorted(LOAD_DIR.glob("*.cypher")):
                jobs[job_id]["step"] = f"load {f.name}"
                run_cypher_path(s, f, {"dataset": req.dataset, "lang": lang, "asOf": as_of})
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
        _log_job_error(job_id, str(e))


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
        _log_job_error(job_id, str(e))


def do_delete_run(job_id: str, run_id: str):
    """Loescht einen einzelnen Auswertungslauf (Run + Findings); Dataset bleibt unberuehrt."""
    try:
        jobs[job_id].update(status="running", step="delete", runId=run_id)
        with driver.session() as s:
            run_file(s, "admin/delete_run.cypher", {"runId": run_id})
        jobs[job_id].update(status="done", step="done")
    except Exception as e:  # noqa: BLE001
        jobs[job_id].update(status="error", error=str(e))
        _log_job_error(job_id, str(e))


def do_clear(job_id: str, dataset: str):
    try:
        jobs[job_id].update(status="running", step="clear", dataset=dataset)
        with driver.session() as s:
            run_file(s, "admin/clear_dataset.cypher", {"dataset": dataset})
            rec = s.run("MATCH (n {dataset:$d}) RETURN count(n) AS remaining", d=dataset).single()
        jobs[job_id].update(status="done", step="done", remaining=rec["remaining"])
    except Exception as e:  # noqa: BLE001
        jobs[job_id].update(status="error", error=str(e))
        _log_job_error(job_id, str(e))


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
        _log_job_error(job_id, str(e))


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
        _log_job_error(job_id, str(e))


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
        _log_job_error(job_id, str(e))


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


def _infer_dataset_asof(dataset: str) -> datetime.date | None:
    """Leitet den Stichtag (= Downloaddatum der SAP-Extrakte) aus den Dateizeitstempeln des
    Import-Ordners ab -- bevorzugt die rohen SE16-.txt-Exporte (alle Tabellen eines Extrakts
    teilen sich praktisch immer denselben Exporttag, da sie in einer Sitzung gezogen werden),
    sonst ersatzweise die konvertierten .csv. None, wenn der Ordner fehlt/leer ist (z. B. der
    Quellordner wurde nach dem Import geloescht) -- dann faellt der Aufrufer auf 'heute' zurueck.
    Nimmt bewusst den FRUEHESTEN Zeitstempel (nicht den spaetesten): einzelne Tabellen koennen
    minimal nacheinander exportiert/konvertiert worden sein, der frueheste liegt am naechsten am
    eigentlichen Download-Zeitpunkt."""
    folder = DATA_DIR / dataset
    if not folder.is_dir():
        return None
    files = list(folder.glob("*.txt")) or list(folder.glob("*.csv"))
    if not files:
        return None
    return datetime.date.fromtimestamp(min(f.stat().st_mtime for f in files))


def _dataset_asof(s, dataset: str):
    """Stichtag des Datasets (= Downloaddatum der SAP-Extrakte, Neo4j-date) -- KEIN Lauf-/Check-
    Parameter mehr, sondern eine Eigenschaft des Datasets selbst (s. load/00_dataset.cypher).
    Legt ihn nach (lazy backfill), falls ein aelterer Import noch keinen hat: bevorzugt aus den
    Dateizeitstempeln des Import-Ordners abgeleitet (_infer_dataset_asof), nur wenn der Ordner
    nicht mehr existiert als letzter Ausweg 'heute'. Aendern danach nur bewusst ueber PUT
    /datasets/{id}/asof (globale Variable), nicht je Lauf/Check."""
    rec = s.run("MATCH (d:Dataset {id:$id}) RETURN d.asOf AS asOf", id=dataset).single()
    if not rec:
        raise HTTPException(404, f"Dataset '{dataset}' nicht gefunden")
    if rec["asOf"] is not None:
        return rec["asOf"]
    inferred = _infer_dataset_asof(dataset) or datetime.date.today()
    rec2 = s.run("MATCH (d:Dataset {id:$id}) SET d.asOf = coalesce(d.asOf, $asOf) "
                 "RETURN d.asOf AS asOf", id=dataset, asOf=inferred).single()
    return rec2["asOf"]


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
        _log_job_error(job_id, str(e))


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
        _log_job_error(job_id, str(e))


def do_upload_import(job_id: str, zip_path: str, dataset: str, lang: list[str], skip_schema: bool,
                      as_of: str | None = None):
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
                                    skipConvert=not has_txt, skipSchema=skip_schema, asOf=as_of))
    except Exception as e:  # noqa: BLE001
        jobs[job_id].update(status="error", error=str(e))
        _log_job_error(job_id, str(e))
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


class DatasetAsOfReq(BaseModel):
    asOf: str   # 'YYYY-MM-DD'


@app.get("/datasets/{datasetId}/asof")
def dataset_asof(datasetId: str):
    """Stichtag des Datasets (= Downloaddatum der SAP-Extrakte) -- globale Eigenschaft, kein
    Lauf-/Check-Filter mehr (s. _dataset_asof()). UI zeigt diesen Wert nur an/erlaubt ihn
    gezielt zu korrigieren (PUT), nicht je Auswertung neu zu waehlen."""
    with driver.session() as s:
        return {"dataset": datasetId, "asOf": jsonable(_dataset_asof(s, datasetId))}


@app.put("/datasets/{datasetId}/asof")
def set_dataset_asof(datasetId: str, req: DatasetAsOfReq):
    """Bewusste Korrektur des Dataset-Stichtags (globale Variable) -- z. B. falls beim Import
    ein falsches Downloaddatum gesetzt wurde. Wirkt auf ALLE folgenden Laeufe/Checks dieses
    Datasets, nicht nur auf den naechsten."""
    as_of = datetime.date.fromisoformat(req.asOf)
    with driver.session() as s:
        rec = s.run("MATCH (d:Dataset {id:$id}) SET d.asOf = $asOf RETURN d.asOf AS asOf",
                    id=datasetId, asOf=as_of).single()
        if not rec:
            raise HTTPException(404, f"Dataset '{datasetId}' nicht gefunden")
    return {"dataset": datasetId, "asOf": jsonable(rec["asOf"])}


@app.get("/users/{userId}")
def user_detail(userId: str, runId: str):
    """Kurzprofil eines Users (Name/Typ/Status) fuer die Kontext-Chips bei nutzerzentrischer
    Auswahl — dataset wird ueber den Lauf aufgeloest."""
    with driver.session() as s:
        run = s.run("MATCH (r:Run {runId:$id}) RETURN r.dataset AS dataset", id=runId).single()
        if not run:
            raise HTTPException(404, f"Lauf '{runId}' nicht gefunden")
        rec = s.run(
            "MATCH (u:User {id:$uid, dataset:$dataset}) "
            "RETURN u.id AS id, coalesce(u.name,'') AS name, "
            "  CASE WHEN 'Dialog' IN labels(u) THEN 'Dialog' WHEN 'System' IN labels(u) THEN 'System' "
            "       WHEN 'Service' IN labels(u) THEN 'Service' WHEN 'Communication' IN labels(u) THEN 'Communication' "
            "       WHEN 'Reference' IN labels(u) THEN 'Reference' ELSE '?' END AS typ, "
            "  CASE WHEN 'Locked' IN labels(u) THEN 'gesperrt' ELSE 'aktiv' END AS status",
            uid=userId, dataset=run["dataset"]).single()
        if not rec:
            raise HTTPException(404, f"User '{userId}' nicht gefunden")
        return dict(rec)


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


# --- Org-Varianten-Editor (Admin) -------------------------------------------------------
# Schreibt NIE in die Vendor-Datei (analysis_profiles.json) — neue/bearbeitete Org-Profile landen
# in einem globalen Overlay (analysis_profiles.custom.json), das profiles() zusaetzlich einliest
# (s. oben). "standard"/"uebergreifend" sind die zwei garantierten Basis-Varianten und bewusst
# geschuetzt (nicht editierbar/loeschbar) — PROTECTED_ORG_PROFILES.
class OrgCriterionReq(BaseModel):
    field: str
    op: str                      # AND | OR | RANGE
    values: list[str] | None = None
    rangeFrom: str | None = None
    rangeTo: str | None = None


class OrgProfileEditReq(BaseModel):
    description: str | None = None
    criteria: list[OrgCriterionReq] = []


class OrgProfileCreateReq(OrgProfileEditReq):
    name: str


def _org_filters_from_criteria(criteria: list[OrgCriterionReq]) -> dict:
    filters: dict = {}
    for c in criteria:
        if c.op == "RANGE":
            filters[c.field] = {"op": "RANGE", "from": c.rangeFrom, "to": c.rangeTo}
        else:
            filters[c.field] = {"op": c.op, "values": c.values or []}
    return filters


@app.get("/admin/org-profiles")
def admin_list_org_profiles():
    """Org-Profile (Vendor + Overlay) fuer die Admin-Seite 'Org-Varianten'; 'protected' markiert
    die zwei garantierten Basis-Varianten (nicht editierbar/loeschbar)."""
    cfg = profiles()
    custom_names = {p["name"] for p in _load_json_list(ORG_PROFILES_CUSTOM_PATH)}
    return [{"name": p["name"], "description": p.get("description", ""), "org": p["org"],
             "protected": p["name"] in PROTECTED_ORG_PROFILES,
             "source": "custom" if p["name"] in custom_names else "vendor"}
            for p in cfg["profiles"]]


@app.get("/admin/org-profiles/org-fields")
def admin_org_fields(dataset: str):
    """Org-Felder eines Datasets, auf die sich ein Kriterium sinnvoll einschraenken laesst —
    speist die Feld-Auswahl beim Anlegen eines Org-Kriteriums. Die OrgField-Registry (aus USORG)
    enthaelt alle 50+ moeglichen Org-Ebenen, viele davon kommen im konkreten Berechtigungskonzept
    aber gar nicht oder nur mit echtem '*' (unbeschraenkt) vor -- ein Kriterium darauf waere nie
    waehlbar (org-field-values liefert dann leer). Deshalb hier vorab filtern auf Felder, bei
    denen mindestens eine Authorization einen konkreten (nicht-'*') Wert traegt."""
    with driver.session() as s:
        rows = s.run(
            "MATCH (of:OrgField {dataset:$d}) "
            "WHERE EXISTS { MATCH (a:Authorization {dataset:$d}) "
            "  WHERE apoc.any.property(a,'f_'+of.field) IS NOT NULL "
            "    AND any(v IN apoc.any.property(a,'f_'+of.field) WHERE v <> '*') } "
            "RETURN of.field AS field ORDER BY of.field", d=dataset)
        return [r["field"] for r in rows]


@app.get("/admin/org-profiles/org-field-values")
def admin_org_field_values(dataset: str, field: str):
    """Tatsaechlich im Dataset vorkommende Werte eines Org-Felds (aus den Authorization-
    Feldwerten) — speist die Werte-Auswahl beim Anlegen eines Org-Kriteriums, statt Freitext."""
    with driver.session() as s:
        rows = s.run(
            "MATCH (a:Authorization {dataset:$d}) "
            "WHERE apoc.any.property(a,'f_'+$field) IS NOT NULL "
            "UNWIND apoc.any.property(a,'f_'+$field) AS v "
            "WITH DISTINCT v WHERE v <> '*' "
            "RETURN v ORDER BY v LIMIT 500", d=dataset, field=field,
        )
        return [r["v"] for r in rows]


@app.post("/admin/org-profiles")
def admin_create_org_profile(req: OrgProfileCreateReq):
    name = req.name
    if not _SAFE_NAME.match(name):
        raise HTTPException(400, "ungueltiger Name (erlaubt: Buchstaben/Ziffern/._-)")
    cfg = profiles()
    if any(p["name"] == name for p in cfg["profiles"]):
        raise HTTPException(409, f"Org-Profil '{name}' existiert bereits")
    if not req.criteria:
        raise HTTPException(400, "mindestens ein Org-Kriterium erforderlich")
    custom_path = ensure_custom_org_profiles_file()
    custom = _load_json_list(custom_path)
    custom.append({"name": name, "description": req.description or "",
                   "org": {"mode": "filtered", "filters": _org_filters_from_criteria(req.criteria)}})
    custom_path.write_text(json.dumps(custom, ensure_ascii=False, indent=2), encoding="utf-8")
    return {"name": name, "saved": True}


@app.put("/admin/org-profiles/{name}")
def admin_update_org_profile(name: str, req: OrgProfileEditReq):
    if name in PROTECTED_ORG_PROFILES:
        raise HTTPException(400, f"Org-Profil '{name}' ist geschuetzt und nicht editierbar")
    custom_path = ensure_custom_org_profiles_file()
    custom = _load_json_list(custom_path)
    entry = next((c for c in custom if c["name"] == name), None)
    if not entry:
        raise HTTPException(404, f"Org-Profil '{name}' nicht gefunden (oder ist ein Vendor-Profil)")
    if not req.criteria:
        raise HTTPException(400, "mindestens ein Org-Kriterium erforderlich")
    entry["description"] = req.description or ""
    entry["org"] = {"mode": "filtered", "filters": _org_filters_from_criteria(req.criteria)}
    custom_path.write_text(json.dumps(custom, ensure_ascii=False, indent=2), encoding="utf-8")
    return {"name": name, "saved": True}


@app.delete("/admin/org-profiles/{name}")
def admin_delete_org_profile(name: str):
    if name in PROTECTED_ORG_PROFILES:
        raise HTTPException(400, f"Org-Profil '{name}' ist geschuetzt und nicht loeschbar")
    custom_path = ensure_custom_org_profiles_file()
    custom = _load_json_list(custom_path)
    remaining = [c for c in custom if c["name"] != name]
    if len(remaining) == len(custom):
        raise HTTPException(404, f"Org-Profil '{name}' nicht gefunden (oder ist ein Vendor-Profil)")
    custom_path.write_text(json.dumps(remaining, ensure_ascii=False, indent=2), encoding="utf-8")
    return {"name": name, "deleted": True}


def _load_check_category(cat: str) -> list[dict]:
    path = CHECKS_DIR / f"{cat}.json"
    return json.loads(path.read_text(encoding="utf-8")) if path.is_file() else []


@app.get("/consistency-checks")
def consistency_checks(area: str = Query("user")):
    """Katalog der Konsistenzchecks (Qualitaet/Risiko des geladenen Berechtigungskonzepts,
    ruleset-unabhaengig) -- ein JSON je Kategorie unter checks/, Schema in checks/SCHEMA.md.
    Ausfuehrliche Begruendung je Check steht in KONSISTENZCHECKS.md (Quelle fuer Menschen).
    area='user' (Ribbon "User-spezifisch", Kategorien A-E) oder 'role' ("Rollen-spezifisch", R)."""
    cats = CHECK_AREAS.get(area, CHECK_AREAS["user"])
    catalog = []
    for cat in cats:
        catalog.extend(_load_check_category(cat))
    return catalog


def _find_check(check_id: str) -> dict:
    for cats in CHECK_AREAS.values():
        for cat in cats:
            for c in _load_check_category(cat):
                if c["id"] == check_id:
                    return c
    raise HTTPException(404, f"Check '{check_id}' nicht gefunden")


def run_cypher_path_capturing(session, path: Path, params: dict) -> list[list[dict]]:
    """Wie run_cypher_path, sammelt aber die Zeilen jedes Statements statt sie zu verwerfen --
    Konsistenzcheck-Dateien koennen mehrere ;-getrennte Statements haben (z. B. Zusammenfassung +
    Detailliste, s. sap_all.cypher); jedes Statement liefert ein eigenes Zeilen-Set."""
    return [[jsonable(dict(r)) for r in session.run(stmt, **params)]
            for stmt in split_statements(path.read_text(encoding="utf-8"))]


class ConsistencyRunReq(BaseModel):
    dataset: str
    # Kein asOf mehr hier: Stichtag kommt aus dem Dataset selbst (_dataset_asof()), s. RunReq.
    params: dict[str, int | str] = {}   # nur deklarierte Namen aus check["params"] wirksam (s. u.)


@app.post("/consistency-checks/{checkId}/run")
def run_consistency_check(checkId: str, req: ConsistencyRunReq):
    """Fuehrt die hinterlegte cypherFile eines Checks gegen ein Dataset aus (Stichtag = der
    Dataset-eigene asOf-Wert, s. _dataset_asof()) und gibt die Zeilen je Statement zurueck
    (results[0] = erstes Statement, ... ); nur fuer Checks mit implemented=true und gesetztem
    cypherFile (s. checks/SCHEMA.md). Optionale, vom Check deklarierte Schwellwerte (z. B.
    sleepDays bei B1) kommen aus check["params"] (Default) bzw. req.params (Override) -- nur
    deklarierte Namen werden als Cypher-Parameter durchgereicht."""
    check = _find_check(checkId)
    cypher_file = check.get("cypherFile")
    if not check.get("implemented") or not cypher_file:
        raise HTTPException(409, f"Check '{checkId}' ist noch nicht implementiert (kein Cypher vorhanden).")
    path = CYPHER_DIR / cypher_file.removeprefix("cypher/")
    if not path.is_file():
        raise HTTPException(500, f"Cypher-Datei fuer '{checkId}' fehlt: {cypher_file}")
    extra_params = {}
    for p in check.get("params", []):
        name = p["name"]
        extra_params[name] = req.params.get(name, p.get("default"))
    with driver.session() as s:
        as_of = _dataset_asof(s, req.dataset)
        results = run_cypher_path_capturing(s, path, {"dataset": req.dataset, "asOf": as_of, **extra_params})
    return {"checkId": checkId, "results": results}


# Anforderungstext je Befund fuer den A4-Root-Cause (s. critical_single_auths.cypher /
# critical_single_auths_root_cause.cypher) -- dieselben Kriterien, nur fuer die Anzeige
# aufbereitet (analog zur AuthReq-Anzeige im SoD-Root-Cause). Bei Aenderung der Kriterien dort
# auch hier nachziehen.
_A4_REQUIREMENT_TEXT = {
    "Debug-Replace (S_DEVELOP)": [
        {"field": "ACTVT", "andLogic": True, "values": ["02", "03"]},
        {"field": "OBJTYPE", "andLogic": True, "values": ["DEBUG"]},
    ],
    "Breiter Tabellenzugriff, aendern (S_TABU_DIS)": [
        {"field": "ACTVT", "andLogic": True, "values": ["02"]},
        {"field": "DICBERCLS", "andLogic": False, "values": ["*", "$"]},
    ],
    "Breiter Tabellenzugriff, aendern (S_TABU_NAM)": [
        {"field": "ACTVT", "andLogic": True, "values": ["02"]},
        {"field": "TABLE", "andLogic": True, "values": ["*"]},
    ],
    "Benutzergruppen-Verwaltung (S_USER_GRP)": [
        {"field": "(jede Ausprägung)", "andLogic": False, "values": ["*"]},
    ],
}


class ConsistencyRootCauseReq(BaseModel):
    dataset: str
    user: str


@app.post("/consistency-checks/{checkId}/root-cause")
def consistency_root_cause(checkId: str, req: ConsistencyRootCauseReq):
    """Root-Cause-Drilldown fuer einen einzelnen User innerhalb eines Konsistenzchecks -- zeigt,
    welche Rolle(n)/Profil(e) mit welchen konkreten Authorization-Feldwerten den Befund
    ausloesen. Nur fuer Checks mit gesetztem rootCauseFile (s. checks/SCHEMA.md). Antwortformat
    identisch zum SoD-Root-Cause (GET /root-cause, {blocks:[...]}), damit die UI denselben
    Dialog/dieselbe Render-Funktion wiederverwenden kann."""
    check = _find_check(checkId)
    rc_file = check.get("rootCauseFile")
    if not rc_file:
        raise HTTPException(409, f"Check '{checkId}' hat keinen Root-Cause-Drilldown.")
    path = CYPHER_DIR / rc_file.removeprefix("cypher/")
    if not path.is_file():
        raise HTTPException(500, f"Root-Cause-Cypher fuer '{checkId}' fehlt: {rc_file}")
    with driver.session() as s:
        as_of = _dataset_asof(s, req.dataset)
        stmt = split_statements(path.read_text(encoding="utf-8"))[0]
        rows = [jsonable(dict(r)) for r in s.run(stmt, dataset=req.dataset, asOf=as_of, user=req.user)]
    by_befund: dict[str, dict] = {}
    for r in rows:
        entry = by_befund.setdefault(r["befund"], {"object": r["objekt"], "satisfiedBy": []})
        felder_text = ", ".join(
            f"{k}: {','.join(v) if isinstance(v, list) else v}" for k, v in r["felder"].items())
        entry["satisfiedBy"].append({"actorType": r["akteurTyp"], "actorId": r["akteurId"],
                                      "authValues": [felder_text] if felder_text else []})
    blocks = [{"label": befund, "objects": [{
                  "object": data["object"],
                  "requirement": _A4_REQUIREMENT_TEXT.get(befund, []),
                  "satisfiedBy": data["satisfiedBy"],
               }]} for befund, data in by_befund.items()]
    return {"ruleId": checkId, "blocks": blocks}


class ConsistencyGraphReq(BaseModel):
    dataset: str


@app.post("/consistency-checks/{checkId}/graph")
def consistency_graph(checkId: str, req: ConsistencyGraphReq):
    """Graph-Ansicht eines Konsistenzchecks (Pilot fuer die Tabelle/Graph-Umschaltung, s.
    ROADMAP.md) -- nur fuer Checks mit gesetztem graphFile (s. checks/SCHEMA.md). Erwartet feste
    Spalten user/userType/userStatus/pathType/role/profile (role nullable bei direkter Zuweisung)
    und baut daraus generisch Cytoscape-Knoten/Kanten; dieselbe Spaltenform ist auf weitere
    User->(Rolle->)Profil-Checks uebertragbar, ohne den Konvertierungscode zu duplizieren."""
    check = _find_check(checkId)
    graph_file = check.get("graphFile")
    if not graph_file:
        raise HTTPException(409, f"Check '{checkId}' hat keine Graph-Ansicht.")
    path = CYPHER_DIR / graph_file.removeprefix("cypher/")
    if not path.is_file():
        raise HTTPException(500, f"Graph-Cypher fuer '{checkId}' fehlt: {graph_file}")
    with driver.session() as s:
        as_of = _dataset_asof(s, req.dataset)
        stmt = split_statements(path.read_text(encoding="utf-8"))[0]
        rows = [jsonable(dict(r)) for r in s.run(stmt, dataset=req.dataset, asOf=as_of)]
    nodes: dict[str, dict] = {}
    edges: dict[str, dict] = {}
    def add_node(node_id: str, label: str, kind: str, **extra):
        nodes.setdefault(node_id, {"data": {"id": node_id, "label": label, "kind": kind, **extra}})
    def add_edge(src: str, tgt: str, label: str):
        edges.setdefault(f"{src}->{tgt}", {"data": {"id": f"{src}->{tgt}", "source": src, "target": tgt, "label": label}})
    for r in rows:
        u_id, p_id = f"u:{r['user']}", f"p:{r['profile']}"
        add_node(u_id, r["user"], "User", userType=r["userType"], userStatus=r["userStatus"])
        add_node(p_id, r["profile"], "Profile")
        if r.get("role"):
            r_id = f"r:{r['role']}"
            add_node(r_id, r["role"], "Role")
            add_edge(u_id, r_id, "ASSIGNED_TO")
            add_edge(r_id, p_id, "HAS_PROFILE")
        else:
            add_edge(u_id, p_id, "HAS_PROFILE")
    return {"checkId": checkId, "elements": list(nodes.values()) + list(edges.values())}


@app.get("/admin/job-errors")
def admin_job_errors(limit: int = Query(200, ge=1, le=2000)):
    """Persistentes Fehlerprotokoll (Job-Fehler) ueber Container-Neustarts hinweg, neueste zuerst."""
    if not JOB_ERROR_LOG.is_file():
        return []
    entries = []
    for line in JOB_ERROR_LOG.read_text(encoding="utf-8").splitlines():
        try:
            entries.append(json.loads(line))
        except ValueError:
            continue
    return list(reversed(entries))[:limit]


@app.get("/admin/rulesets/{ruleset}/queries")
def admin_list_queries(ruleset: str):
    """Alle Queries eines Rulesets (Vendor + Overlay effektiv gemerged) fuer das Query
    Management; 'custom' markiert eigene Edits/abgeleitete Queries."""
    merged, custom_ids = _merged_queries(ruleset)
    return [{"id": qid, "description": q.get("description", ""),
             "shortDescription": q.get("shortDescription", ""), "criticality": q.get("criticality"),
             "module": q.get("module"), "queryType": q.get("queryType"),
             "disregardTcode": bool(q.get("disregardTcode", False)), "custom": qid in custom_ids}
            for qid, q in sorted(merged.items())]


@app.get("/admin/rulesets/{ruleset}/queries/{queryId}")
def admin_get_query(ruleset: str, queryId: str):
    """Eine Query vollstaendig (inkl. authorizations/transactions, read-only) fuer den
    'Aufbau'-Tab im Query Management."""
    merged, custom_ids = _merged_queries(ruleset)
    q = merged.get(queryId)
    if not q:
        raise HTTPException(404, f"Query '{queryId}' nicht gefunden")
    return {**q, "custom": queryId in custom_ids}


@app.get("/admin/rulesets/{ruleset}/overlay/download")
def admin_download_overlay(ruleset: str):
    """Overlay-Datei (queries.custom.json) eines Rulesets als Download — Sicherung der eigenen
    Anpassungen/abgeleiteten Queries, getrennt von den Quelldaten-/Lauf-Backups."""
    custom_path = ensure_custom_queries_file(ruleset)
    return FileResponse(custom_path, filename=f"{ruleset}__queries.custom.json", media_type="application/json")


class QueryEditReq(BaseModel):
    description: str | None = None
    shortDescription: str | None = None
    criticality: str | None = None
    module: str | None = None
    queryType: str | None = None
    disregardTcode: bool | None = None
    risk: str | None = None
    controls: str | None = None


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
    risk: str | None = None
    controls: str | None = None


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
    for field in ("description", "shortDescription", "criticality", "module", "queryType",
                  "disregardTcode", "risk", "controls"):
        v = getattr(req, field)
        if v is not None:
            new_q[field] = v
    custom_path = ensure_custom_queries_file(ruleset)
    custom = _load_json_list(custom_path)
    custom.append(new_q)
    custom_path.write_text(json.dumps(custom, ensure_ascii=False, indent=2), encoding="utf-8")
    reload_ruleset(ruleset)
    return {"query": req.newId, "derivedFrom": req.fromId}


# --- SoD-Regel-Editor (Query Management, Modus "SoD") ----------------------------------
# Analog zum Einzelfilter-Editor oben, aber ohne Struktur-Edits/Ableiten: SoD-Regeln haben keine
# eigene Authorizations/TCodes, nur Metadaten (Kurz-/Langbezeichnung, Kritikalitaet, Risiko,
# Controls) plus die read-only Klausel-/Variablen-Struktur (clauses/variables/expression) fuer den
# Aufbau-Tab. Overlay sod_rules.custom.json analog zu queries.custom.json.
def _sodrule_paths(ruleset: str) -> tuple[Path, Path]:
    rdir = ruleset_dir(ruleset)
    if not rdir:
        raise HTTPException(404, f"Ruleset '{ruleset}' nicht gefunden")
    base = RULES_DIR / rdir
    return base / "sod_rules.json", base / "sod_rules.custom.json"


def ensure_custom_sodrules_file(ruleset: str) -> Path:
    _, custom_path = _sodrule_paths(ruleset)
    if not custom_path.is_file():
        custom_path.write_text("[]", encoding="utf-8")
    return custom_path


def _merged_sodrules(ruleset: str) -> tuple[dict[str, dict], set[str]]:
    """Vendor-SoD-Regeln + Overlay, Overlay-Felder gewinnen je id — analog zu _merged_queries.
    'eigen' heisst: neue Regel (kein Vendor-Gegenstueck) oder clauses/variables wurden
    ueberschrieben; reine Metadaten-Edits zaehlen nicht."""
    vendor_path, custom_path = _sodrule_paths(ruleset)
    merged = {r["sodRule"]: dict(r) for r in _load_json_list(vendor_path)}
    custom_ids = set()
    for c in _load_json_list(custom_path):
        rid = c["sodRule"]
        if rid not in merged or "clauses" in c or "variables" in c:
            custom_ids.add(rid)
        if rid in merged:
            merged[rid] = {**merged[rid], **{k: v for k, v in c.items() if v is not None}}
        else:
            merged[rid] = c
    return merged, custom_ids


@app.get("/admin/rulesets/{ruleset}/sodrules")
def admin_list_sodrules(ruleset: str):
    """Alle SoD-Regeln eines Rulesets (Vendor + Overlay gemerged) fuer das Query Management
    (Modus 'SoD'); 'custom' markiert eigene Edits."""
    merged, custom_ids = _merged_sodrules(ruleset)
    return [{"id": rid, "description": r.get("description", ""),
             "shortDescription": r.get("shortDescription", ""), "criticality": r.get("criticality"),
             "reasonCode": r.get("reasonCode"), "custom": rid in custom_ids}
            for rid, r in sorted(merged.items())]


@app.get("/admin/rulesets/{ruleset}/sodrules/{ruleId}")
def admin_get_sodrule(ruleset: str, ruleId: str):
    """Eine SoD-Regel vollstaendig (inkl. clauses/variables/expression, read-only) fuer den
    'Aufbau'-Tab im Query Management."""
    merged, custom_ids = _merged_sodrules(ruleset)
    r = merged.get(ruleId)
    if not r:
        raise HTTPException(404, f"SoD-Regel '{ruleId}' nicht gefunden")
    return {**r, "custom": ruleId in custom_ids}


@app.get("/admin/rulesets/{ruleset}/sodrules/overlay/download")
def admin_download_sodrule_overlay(ruleset: str):
    """Overlay-Datei (sod_rules.custom.json) eines Rulesets als Download."""
    custom_path = ensure_custom_sodrules_file(ruleset)
    return FileResponse(custom_path, filename=f"{ruleset}__sod_rules.custom.json", media_type="application/json")


class SodRuleEditReq(BaseModel):
    description: str | None = None
    shortDescription: str | None = None
    criticality: str | None = None
    risk: str | None = None
    controls: str | None = None


@app.put("/admin/rulesets/{ruleset}/sodrules/{ruleId}")
def admin_update_sodrule(ruleset: str, ruleId: str, req: SodRuleEditReq):
    """Bearbeitet Metadaten einer SoD-Regel als Overlay-Eintrag (sod_rules.custom.json) — Vendor-
    Datei bleibt unberuehrt. Ladet das Ruleset danach sofort neu (Edit wirkt ohne extra Schritt)."""
    merged, _ = _merged_sodrules(ruleset)
    if ruleId not in merged:
        raise HTTPException(404, f"SoD-Regel '{ruleId}' nicht gefunden")
    custom_path = ensure_custom_sodrules_file(ruleset)
    custom = _load_json_list(custom_path)
    entry = next((c for c in custom if c["sodRule"] == ruleId), None)
    fields = {k: v for k, v in req.model_dump().items() if v is not None}
    if entry:
        entry.update(fields)
    else:
        custom.append({"sodRule": ruleId, **fields})
    custom_path.write_text(json.dumps(custom, ensure_ascii=False, indent=2), encoding="utf-8")
    reload_ruleset(ruleset)
    return {"sodRule": ruleId, "saved": fields}


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


_SATISFIED_BY_CYPHER = (
    "MATCH (u:User {id:$user, dataset:$dataset}) "
    "OPTIONAL MATCH (u)-[g:ASSIGNED_TO]->(roleActor:Role) "
    "  WHERE (g.validFrom IS NULL OR g.validFrom<=$asOf) AND (g.validTo IS NULL OR $asOf<=g.validTo) "
    "OPTIONAL MATCH (u)-[:HAS_PROFILE]->(profActor:Profile) "
    "WITH u, [x IN collect(DISTINCT roleActor) WHERE x IS NOT NULL] "
    "   + [x IN collect(DISTINCT profActor) WHERE x IS NOT NULL] AS actors "
    "UNWIND actors AS actor "
    "MATCH (actor)-[:CONTAINS|HAS_PROFILE*0..4]->()-[:HAS_AUTH]->(a:Authorization {dataset:$dataset, object:$object}) "
    "WHERE all(r IN $reqs WHERE "
    "  r.field IN $orgFields "
    "  OR ( apoc.any.property(a,'f_'+r.field) IS NOT NULL "
    "       AND ( '*' IN apoc.any.property(a,'f_'+r.field) "
    "             OR CASE WHEN r.andLogic "
    "                  THEN all(v IN r.values WHERE v IN apoc.any.property(a,'f_'+r.field) "
    "                         OR any(rg IN apoc.any.property(a,'f_'+r.field) WHERE rg CONTAINS '..' AND split(rg,'..')[0]<=v AND v<=split(rg,'..')[1])) "
    "                  ELSE any(v IN r.values WHERE v IN apoc.any.property(a,'f_'+r.field) "
    "                         OR any(rg IN apoc.any.property(a,'f_'+r.field) WHERE rg CONTAINS '..' AND split(rg,'..')[0]<=v AND v<=split(rg,'..')[1])) "
    "                END ) ) ) "
    "RETURN DISTINCT labels(actor)[0] AS actorType, actor.id AS actorId, "
    # "technisch" = ein generiertes Profil (PFCG-Artefakt einer Rolle), keine eigenstaendig
    # gepflegte Berechtigung -- redundant zur ohnehin angezeigten Rolle. Bewusst NICHT auf die
    # Rollen DIESES Users beschraenkt (erste Version tat das und uebersah "verwaiste" generierte
    # Profile, deren erzeugende Rolle im Extrakt nicht mehr existiert, z. B. geloescht/umbenannt
    # -- Nutzer-Beispiel T-EC37002026): EXISTS { (:Role)-[:HAS_PROFILE]->(actor) } prueft, ob
    # IRGENDEINE Rolle dieses Profil erzeugt (im Graphen unabhaengig vom betrachteten User/
    # Zeitpunkt) -- Stichprobe sachsenenergie: erfasst 3737/3829 T-*-Profile strukturell sowie
    # 1171 generierte Profile ohne "T-"-Praefix. Der Praefix-Fallback faengt die restlichen
    # verwaisten T-*-Profile (92 von 3829) ab, deren erzeugende Rolle fehlt.
    "  (labels(actor)[0] = 'Profile' AND ( "
    "    EXISTS { MATCH (:Role)-[:HAS_PROFILE]->(actor) } OR actor.id STARTS WITH 'T-' "
    "  )) AS technical, "
    "  [k IN keys(a) WHERE k STARTS WITH 'f_' | {field: substring(k,2), values: apoc.any.property(a,k)}] AS authFields "
    "ORDER BY actorType, actorId"
)


def _query_objects(s, ruleset: str, dataset: str, as_of, user: str, org_fields: list[str], query_id: str) -> list[dict]:
    """Objekt-/TCode-Aufschluesselung einer einzelnen Query fuer einen User (Kernlogik von
    Root-Cause) — wiederverwendet sowohl fuer den Einzelfilter- als auch den SoD-Regel-Aufruf."""
    qrec = s.run(
        "MATCH (q:Query {id:$qid, ruleset:$ruleset}) "
        "OPTIONAL MATCH (q)-[:REQUIRES]->(ar:AuthReq) "
        "RETURN q.tcodes AS tcodes, q.disregardTcode AS disregardTcode, "
        "  collect(CASE WHEN ar IS NULL THEN null ELSE "
        "    {object:ar.object, field:ar.field, andLogic:ar.andLogic, values:ar.values} END) AS reqs",
        qid=query_id, ruleset=ruleset).single()
    if qrec is None:
        raise HTTPException(404, f"Query '{query_id}' nicht gefunden")
    reqs = [r for r in qrec["reqs"] if r is not None]

    def satisfied_by(obj: str, obj_reqs: list[dict]) -> list[dict]:
        rows = s.run(_SATISFIED_BY_CYPHER, user=user, dataset=dataset, asOf=as_of,
                     object=obj, reqs=obj_reqs, orgFields=org_fields)
        return [{"actorType": r["actorType"], "actorId": r["actorId"], "technical": r["technical"],
                 "authValues": [f"{f['field']}={','.join(f['values'])}" for f in r["authFields"]]}
                for r in rows]

    objects = sorted({r["object"] for r in reqs})
    result_objects = [{"object": obj, "requirement": [r for r in reqs if r["object"] == obj],
                        "satisfiedBy": satisfied_by(obj, [r for r in reqs if r["object"] == obj])}
                       for obj in objects]

    tcodes = qrec["tcodes"] or []
    disregard = bool(qrec["disregardTcode"])
    blocks = []
    if not disregard and tcodes and "*" not in tcodes:
        tcode_req = [{"field": "TCD", "andLogic": False, "values": tcodes}]
        blocks.append({"object": "S_TCODE (TCode-Prüfung)", "requirement": tcode_req,
                        "satisfiedBy": satisfied_by("S_TCODE", tcode_req)})
    blocks += result_objects
    return blocks


@app.get("/root-cause")
def root_cause(runId: str, user: str, query: str | None = None, rule: str | None = None):
    """Root-Cause-Erklaerung fuer einen User: entweder fuer eine einzelne Query (Einzelfilter) oder
    fuer eine SoD-Regel (alle Klauseln, je die vom User tatsaechlich gematchte(n) Query(s)). Pro
    Berechtigungsobjekt (+ TCode-Pruefung als eigener Pseudo-Block) wird gezeigt, WELCHE Anforderung
    galt und welche Rolle(n)/Profil(e) sie mit welcher konkreten Authorization erfuellen — macht
    sichtbar, wenn unterschiedliche Objekte/Klauseln durch unterschiedliche Rollen gedeckt werden
    (AE-03/AE-09), nicht nur 'welche Rolle' wie die Evidenz (VIA_ROLE/VIA_PROFILE, AE-11)."""
    if not query and not rule:
        raise HTTPException(400, "entweder 'query' oder 'rule' angeben")
    with driver.session() as s:
        run = s.run("MATCH (r:Run {runId:$id}) RETURN r.ruleset AS ruleset, r.dataset AS dataset, "
                    "r.asOf AS asOf", id=runId).single()
        if not run:
            raise HTTPException(404, f"Lauf '{runId}' nicht gefunden")
        ruleset, dataset, as_of = run["ruleset"], run["dataset"], run["asOf"]
        org_fields = [r["field"] for r in s.run(
            "MATCH (of:OrgField {dataset:$d}) RETURN of.field AS field", d=dataset)]

        if query:
            blocks = [{"label": f"Query {query}",
                       "objects": _query_objects(s, ruleset, dataset, as_of, user, org_fields, query)}]
        else:
            clauses = s.run(
                "MATCH (rule:SoDRule {id:$rid, ruleset:$ruleset})-[:HAS_CLAUSE]->(cl:Clause)-[:NEEDS]->(q:Query) "
                "RETURN cl.idx AS idx, collect(q.id) AS qids ORDER BY idx",
                rid=rule, ruleset=ruleset)
            blocks = []
            for c in clauses:
                idx, qids = c["idx"], c["qids"]
                matched = [r["qid"] for r in s.run(
                    "MATCH (u:User {id:$user})-[:MATCHES {runId:$runId}]->(q:Query) "
                    "WHERE q.id IN $qids RETURN q.id AS qid", user=user, runId=runId, qids=qids)]
                if not matched:
                    blocks.append({"label": f"Klausel {idx + 1}", "objects": [],
                                   "note": "keine gematchte Query in dieser Klausel gefunden"})
                    continue
                for qid in matched:
                    blocks.append({"label": f"Klausel {idx + 1} · Query {qid}",
                                   "objects": _query_objects(s, ruleset, dataset, as_of, user, org_fields, qid)})
            if not blocks:
                raise HTTPException(404, f"SoD-Regel '{rule}' nicht gefunden")

        return {"queryId": query, "ruleId": rule, "user": user, "blocks": blocks}


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
                        lang: str = Form(""), skipSchema: bool = Form(False),
                        asOf: str = Form("")):
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
    threading.Thread(target=do_upload_import, args=(job_id, str(tmp), ds, langs, skipSchema, asOf or None),
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


@app.post("/runs/batch")
def start_run_batch(req: RunBatchReq):
    """Mehrere Org-Varianten in einem Schritt anlegen — je Variante ein eigener (:Run) mit dem
    Variantennamen als Titel (s. ROADMAP.md, 'Multi-Varianten-Laeufe'). Ein Job, sequenziell
    abgearbeitet (gemeinsame Neo4j-Session, kein paralleles Schreiben auf dasselbe Dataset)."""
    job_id = str(uuid.uuid4())
    jobs[job_id] = {"status": "queued", "kind": "run_batch", "request": req.model_dump()}
    threading.Thread(target=do_run_batch, args=(job_id, req), daemon=True).start()
    return {"jobId": job_id}


@app.get("/jobs/{job_id}")
def job_status(job_id: str):
    if job_id not in jobs:
        raise HTTPException(404, "unbekannte Job-Id")
    return jobs[job_id]


# Minimale UI (Phase 9, Bau-Schritt 2): statische Single-Page, vom Backend ausgeliefert.
# Bewusst leichtgewichtig (kein Node/React-Build, ein Container) — das gebrandete Frontend mit
# Cytoscape.js-Graph bleibt der spaetere "Fancy"-Schritt. MUSS nach allen API-Routen gemountet
# werden, damit "/" die UI liefert, ohne /health, /runs, ... zu ueberdecken.
if FRONTEND_DIR.exists():
    app.mount("/", StaticFiles(directory=str(FRONTEND_DIR), html=True), name="ui")
