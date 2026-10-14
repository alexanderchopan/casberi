#!/usr/bin/env python3
"""Self-test for scripts/journeys-report.py — the flags a journeys run raises.

Proves: a first run is the baseline; more taps, more typing and a large slowdown
flag; fewer taps is said; a small slowdown is not; a broken run flags and never
becomes the baseline the next run is compared with; the history keeps every run.
Then each rule is broken in a copy of the report, and the fixture must fail.

Usage: scripts/journeys-selftest.py [--verbose]
"""

import importlib.util
import pathlib
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
REPORT = ROOT / "scripts/journeys-report.py"
VERBOSE = "--verbose" in sys.argv


def load(path):
    spec = importlib.util.spec_from_file_location("journeys_report", path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def row(journey, status="ok", taps=5, typed=0, seconds=10.0, note=""):
    return dict(journey=journey, status=status, taps=taps, typed=typed, seconds=seconds, note=note)


def fixture(m):
    bad = []

    def check(name, cond):
        if not cond:
            bad.append(name)

    with tempfile.TemporaryDirectory() as tmp:
        hist = pathlib.Path(tmp) / "h.csv"

        def run(results):
            lines, rows = m.report(results, m.read_history(hist), "sha1", "ts")
            m.append(hist, rows)
            return "\n".join(lines)

        out = run([row("find", taps=4, typed=4, seconds=8.0)])
        check("a first run is the baseline", "first run" in out)

        out = run([row("find", taps=5, typed=4, seconds=8.5)])
        check("more taps flags", "more taps: 4 → 5" in out and out.startswith("⚠"))
        check("a small slowdown is not flagged", "slower" not in out)

        out = run([row("find", taps=3, typed=6, seconds=8.0)])
        check("fewer taps is said", "fewer taps: 5 → 3" in out)
        check("more typing flags", "more typing: 4 → 6" in out)

        out = run([row("find", taps=3, typed=6, seconds=20.0)])
        check("a large slowdown flags", "slower: 8.0s → 20.0s" in out)

        out = run([row("find", status="broken", taps=1, note="step 2 not found: Search")])
        check("a broken run flags with its note", out.startswith("✗") and "step 2 not found" in out)

        out = run([row("find", taps=2, typed=6, seconds=20.0)])
        check("a broken run never becomes the baseline", "fewer taps: 3 → 2" in out)

        check("the history keeps every run", len(m.read_history(hist)) == 6)

        # A short journey doubling from 2s to 4s is the runner's noise, not a
        # slowdown: the ratio alone would flag it, the floor does not.
        run([row("note", taps=3, seconds=2.0)])
        out = run([row("note", taps=3, seconds=4.0)])
        check("a short journey's small slowdown is under the floor", "slower" not in out)

        targets = {"default_taps": 3, "taps": {"spending": 2}}
        lines, _ = m.report([row("connect", taps=5), row("note", taps=3), row("spending", taps=3),
                             row("find", status="broken", taps=9)], [], "sha", "ts", targets)
        out = "\n".join(lines)
        check("over target is flagged", "over target: 5 taps (target 3)" in out)
        check("at target is not", "note" in out and "over target" not in lines[1])
        check("a journey's own target wins over the default", "over target: 3 taps (target 2)" in lines[2])
        check("over target marks the line", lines[0].startswith("⚠"))
        check("a broken run is not judged against its target", "over target" not in lines[3])
    return bad


MUTATIONS = [
    ("broken becomes baseline", 'if r.get("status") == "ok":', "if True:"),
    ("more taps silent", 'out.append(f"more taps: {bt} → {row[\'taps\']}")', "pass"),
    ("fewer taps silent", 'out.append(f"fewer taps: {bt} → {row[\'taps\']}")', "pass"),
    ("typing silent", 'if row["typed"] > by:', "if False:"),
    ("no slow floor", 'and row["seconds"] - bs > SLOW_FLOOR_S', ""),
    ("no target", 'if target is not None and row["taps"] > int(target):', "if False:"),
    ("default only", '(targets.get("taps") or {}).get(journey, targets.get("default_taps"))', 'targets.get("default_taps")'),
    ("history overwritten", 'with p.open("a", newline="") as f:', 'with p.open("w", newline="") as f:\n        new = True'),
]


def main():
    print("▶ journeys report self-test")
    failures = fixture(load(REPORT))
    for f in failures:
        print(f"  FAIL {f}")
    if VERBOSE and not failures:
        print("  ok   every flag as designed")
    src = REPORT.read_text()
    with tempfile.TemporaryDirectory() as tmp:
        for name, old, new in MUTATIONS:
            if old not in src:
                failures.append(f"mutation '{name}' did not apply")
                print(f"  FAIL mutation '{name}' did not apply — its anchor moved")
                continue
            path = pathlib.Path(tmp) / f"m{len(name)}.py"
            path.write_text(src.replace(old, new, 1))
            if fixture(load(path)):
                if VERBOSE:
                    print(f"  ok   mutation '{name}' is caught")
            else:
                failures.append(name)
                print(f"  FAIL mutation '{name}' passed the fixture — a rule has no check")
    if failures:
        print(f"✗ journeys report self-test: {len(failures)} failure(s)")
        return 1
    print(f"✓ journeys report self-test ({len(MUTATIONS)} mutations caught)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
