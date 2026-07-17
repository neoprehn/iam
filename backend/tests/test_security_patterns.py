import ast
import subprocess
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _qualified_name(node: ast.AST) -> str | None:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        base = _qualified_name(node.value)
        return f"{base}.{node.attr}" if base else node.attr
    return None


def _scan_file(path: Path) -> list[str]:
    source = path.read_text(encoding="utf-8")
    tree = ast.parse(source, filename=str(path))
    findings: list[str] = []

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue

        fn = _qualified_name(node.func)
        if not fn:
            continue

        if fn in {"eval", "exec", "compile"}:
            findings.append(f"{path}:{node.lineno} uses {fn}()")

        if fn in {
            "os.system",
            "os.popen",
            "os.spawnl",
            "os.spawnle",
            "os.spawnlp",
            "os.spawnlpe",
            "os.spawnv",
            "os.spawnve",
            "os.spawnvp",
            "os.spawnvpe",
        }:
            findings.append(f"{path}:{node.lineno} uses {fn}()")

        if fn in {
            "subprocess.run",
            "subprocess.call",
            "subprocess.check_call",
            "subprocess.check_output",
            "subprocess.Popen",
        }:
            for kw in node.keywords:
                if kw.arg == "shell" and isinstance(kw.value, ast.Constant) and kw.value.value is True:
                    findings.append(f"{path}:{node.lineno} uses {fn}(..., shell=True)")

        if fn in {"pickle.load", "pickle.loads", "marshal.loads"}:
            findings.append(f"{path}:{node.lineno} uses unsafe deserialization via {fn}()")

    return findings


class TestSecurityPatterns(unittest.TestCase):
    def test_no_unsafe_execution_patterns(self) -> None:
        py_files = [
            p for p in ROOT.rglob("*.py")
            if "tests" not in p.parts
        ]
        findings: list[str] = []
        for path in py_files:
            findings.extend(_scan_file(path))

        self.assertFalse(
            findings,
            "Unsafe patterns found in backend Python code:\n" + "\n".join(findings),
        )

    def test_bandit_security_scan(self) -> None:
        cfg = ROOT / "bandit.yaml"
        result = subprocess.run(
            [
                sys.executable,
                "-m",
                "bandit",
                "-q",
                "-r",
                str(ROOT),
                "-c",
                str(cfg),
                "-lll",
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            detail = (result.stdout or "") + ("\n" + result.stderr if result.stderr else "")
            self.fail("Bandit security scan failed:\n" + detail.strip())


if __name__ == "__main__":
    unittest.main()
