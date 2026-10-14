"""Coverage numbers for CI, with no third-party service involved.

    coverage_report.py collect OUT.json     # read this run's coverage data
    coverage_report.py comment HEAD.json BASE.json   # print a PR comment

`collect` reads `.coverage` in backend/ and mcp_server/ (via `coverage json`)
and frontend/coverage/lcov.info, and writes {"backend": 100.0, ...}. A
component whose data is missing is left out. `comment` compares two such files;
BASE.json may not exist (e.g. no run on main has finished yet).
"""

import json
import subprocess
import sys
from pathlib import Path

MARKER = "<!-- coverage-report -->"
NAMES = {"backend": "Backend", "mcp_server": "MCP server", "frontend": "Frontend"}


def python_percent(package: str) -> float | None:
    if not Path(package, ".coverage").exists():
        return None
    out = Path(package, "coverage.json")
    subprocess.run(
        ["uv", "run", "coverage", "json", "-o", "coverage.json"],
        cwd=package,
        check=True,
        capture_output=True,
    )
    return float(json.loads(out.read_text())["totals"]["percent_covered"])


def frontend_percent() -> float | None:
    lcov = Path("frontend/coverage/lcov.info")
    if not lcov.exists():
        return None
    found = hit = 0
    for line in lcov.read_text().splitlines():
        if line.startswith("LF:"):
            found += int(line[3:])
        elif line.startswith("LH:"):
            hit += int(line[3:])
    return 100 * hit / found if found else None


def collect(out: str) -> None:
    values = {
        "backend": python_percent("backend"),
        "mcp_server": python_percent("mcp_server"),
        "frontend": frontend_percent(),
    }
    Path(out).write_text(json.dumps({k: v for k, v in values.items() if v is not None}))


def comment(head_path: str, base_path: str) -> None:
    head = json.loads(Path(head_path).read_text())
    base_file = Path(base_path)
    base = json.loads(base_file.read_text()) if base_file.exists() else {}
    rows = []
    for key, name in NAMES.items():
        if key not in head:
            continue
        now, before = head[key], base.get(key)
        if before is None:
            rows.append(f"| {name} | {now:.2f}% | n/a | n/a |")
            continue
        delta = now - before
        if abs(delta) < 0.005:
            verdict = "unchanged"
        else:
            verdict = f"{'📈 +' if delta > 0 else '📉 '}{delta:.2f} pp"
        rows.append(f"| {name} | {now:.2f}% | {before:.2f}% | {verdict} |")
    print(MARKER)
    print("### Coverage\n")
    print("| | This PR | `main` | Change |\n|---|---|---|---|")
    print("\n".join(rows))
    if not base:
        print("\n_No coverage from `main` to compare against yet._")


if __name__ == "__main__":
    match sys.argv[1:]:
        case ["collect", out]:
            collect(out)
        case ["comment", head, base]:
            comment(head, base)
        case _:
            sys.exit(__doc__)
