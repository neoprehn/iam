"""SE16-Export-Konverter (Python-Port von load/Convert-Se16Export.ps1).

Wandelt SE16-"unkonvertiert"-Listenexporte (.txt, Windows-1252, pipe-getrennt, fixbreit) in
saubere Tab-getrennte UTF-8-CSV. Sensible Credential-Spalten (Passwort-Hashes/-Codes) werden
HIER verworfen und erreichen die abgeleitete CSV nie (Datenhygiene, Defense-in-Depth).

Bewusst zeilengleich zum PowerShell-Original portiert (gleiche Parsing-/Drop-Regeln), damit der
Import auch ohne Windows/PowerShell im Container reproduzierbar ist (Phase-9-Transportabilitaet).
"""
import json
import fnmatch
from pathlib import Path

DROP_DEFAULT = ["BCODE*", "BCDA*", "OCOD*", "CODV*", "PASSCODE", "PWDSALTEDHASH", "PWDHISTORY"]


def _sensitive(name: str, patterns: list[str]) -> bool:
    up = name.upper()
    return any(fnmatch.fnmatchcase(up, p.upper()) for p in patterns)


def convert_file(in_path: Path, out_path: Path, drop_patterns: list[str], delim: str = "\t") -> dict:
    keep_idx = None
    header: list[str] = []
    dropped: list[str] = []
    rows = 0
    with open(in_path, encoding="cp1252") as r, open(out_path, "w", encoding="utf-8", newline="") as w:
        for raw in r:
            line = raw.rstrip("\r\n")
            if not line.startswith("|"):       # Titel/Info/Trennlinien/Footer ueberspringen
                continue
            parts = line.split("|")[1:-1]       # fuehrendes/abschliessendes Leerfeld weg
            if not parts:
                continue
            if parts[0].strip() == "":          # leere Markierungsspalte (ALV) weg
                parts = parts[1:]
            fields = [p.strip().replace('"', "") for p in parts]  # Padding trimmen, " entfernen
            if keep_idx is None:                # erste |-Zeile = Kopfzeile
                keep_idx = []
                for i, f in enumerate(fields):
                    if _sensitive(f, drop_patterns):
                        dropped.append(f)
                    else:
                        keep_idx.append(i)
                header = [fields[i] for i in keep_idx]
                w.write(delim.join(header) + "\n")
            else:
                kept = [fields[i] if i < len(fields) else "" for i in keep_idx]
                w.write(delim.join(kept) + "\n")
                rows += 1
    return {"table": out_path.stem, "columns": header, "rows": rows, "dropped": dropped}


def convert_folder(folder: Path, required_config: Path | None = None,
                   drop_patterns: list[str] | None = None, skip_required: bool = False) -> dict:
    """Ganzen dataset-Ordner konvertieren. Prueft das Minimalset VOR der Konvertierung."""
    if not folder.is_dir():
        raise FileNotFoundError(f"Import-Ordner fehlt: {folder}")
    drop_patterns = drop_patterns if drop_patterns is not None else DROP_DEFAULT

    required, optional = [], []
    if required_config and required_config.is_file():
        cfg = json.loads(required_config.read_text(encoding="utf-8"))
        required, optional = list(cfg.get("required", [])), list(cfg.get("optional", []))

    if not skip_required and required:
        missing = [t for t in required if not (folder / f"{t}.txt").is_file()]
        if missing:
            raise ValueError("Minimalset unvollstaendig - fehlende Pflicht-Tabellen (.txt): "
                             + ", ".join(missing))

    results = [convert_file(txt, folder / (txt.stem.lower() + ".csv"), drop_patterns)
               for txt in sorted(folder.glob("*.txt"))]
    missing_opt = [t for t in optional if not (folder / f"{t}.txt").is_file()]
    return {"converted": len(results), "tables": results,
            "requiredOk": (not required) or all((folder / f"{t}.txt").is_file() for t in required),
            "missingOptional": missing_opt}
