#!/usr/bin/env python3
"""Read one journeys run, compare it with the last good run of each journey,
append it to the history, and print the report. Called by scripts/journeys.sh.

WHY THIS EXISTS (2026-10-14). The passes measure whether the app breaks, and
`perf.sh` how fast it launches; nothing measured how much a person has to DO
to get a job done. A journey (`CasberiUITests/JourneyTests.swift`) is one job
walked with real taps from where a person starts. This turns each walk into
numbers that trend: taps, characters typed, swipes, Backs, seconds.

WHAT EACH NUMBER IS.
  taps     — every tap the walk makes, field focus included. The headline: it
             does not move with a slow machine.
  typed    — characters typed.
  scrolls  — swipes the walk took to bring a step's target on screen. A tap
             count misses a target buried under a long list (owner,
             2026-10-14: "lets do the scroll and back counts next").
  backs    — Back or close taps the job makes the person take (a subset of
             taps): a wrong turn the design forces.
  seconds  — wall clock from launch-landed to the last step. Includes waits for
             animations and the test runner's own queries (~0.3–0.5s a step), so
             it moves with the machine; only a large move is flagged.

FLAGS, each against the LAST OK RUN of the same journey (a broken run never
becomes the baseline):
  broken        — a step was not found; the journey failed where it says.
  more taps     — taps went up. A design change that costs the person a tap.
  fewer taps    — taps went down. Said, so a good change is on the record.
  more typing   — typed went up.
  more scrolls  — scrolls went up; fewer is said.
  more backs    — backs went up; fewer is said.
                  A baseline from before these were counted (a history row
                  with them blank) flags neither.
  slower        — seconds rose by more than SLOW_RATIO and by SLOW_FLOOR_S.
  over target   — taps above the owner's target (`journeys-targets.json`,
                  3 for every journey since 2026-10-14). Said EVERY run, not
                  only when it changes: the gap is the work.
It REPORTS and never gates, like perf.sh: exit 0 unless its input is missing.

THE CATALOGUE SWEEP (prd §1306, `--catalog catalog.tsv [targets.json]`): one
row per app — app, ask (field | the tile pressed | none | broken), taps from
Sources, scrolls, seconds, what opened, note. Flagged: over the tap target,
no first step found, or a step broken (the row's note says which). A summary
counts the asks; nothing is appended to the history.

Input  results.tsv: journey \\t ok|broken \\t taps \\t typed \\t seconds \\t scrolls \\t backs \\t note
       (the older six-column form, without scrolls and backs, still reads)
History CSV: ts,sha,journey,status,taps,typed,scrolls,backs,seconds,note
       (an older history without scrolls and backs is rewritten with them blank)
Usage: journeys-report.py <results.tsv> <history.csv> <sha> [targets.json]
"""

import csv
import datetime
import pathlib
import sys

SLOW_RATIO = 1.5
SLOW_FLOOR_S = 3.0
FIELDS = ["ts", "sha", "journey", "status", "taps", "typed", "scrolls", "backs", "seconds", "note"]


def read_results(path):
    rows = []
    for line in pathlib.Path(path).read_text().splitlines():
        parts = line.split("\t")
        if len(parts) < 5 or not parts[0].strip():
            continue
        # Eight columns since scrolls and backs were counted; six before.
        counted = len(parts) >= 7 and parts[5].strip().isdigit() and parts[6].strip().isdigit()
        scrolls, backs = (int(parts[5]), int(parts[6])) if counted else (None, None)
        rest = parts[7:] if counted else parts[5:]
        note = rest[0] if rest else ""
        rows.append(dict(journey=parts[0], status=parts[1], taps=int(parts[2]),
                         typed=int(parts[3]), seconds=float(parts[4]),
                         scrolls=scrolls, backs=backs, note=note))
    return rows


def read_history(path):
    p = pathlib.Path(path)
    if not p.exists():
        return []
    with p.open() as f:
        return list(csv.DictReader(f))


def baselines(history):
    """The last OK row of each journey."""
    base = {}
    for r in history:
        if r.get("status") == "ok":
            base[r["journey"]] = r
    return base


def target_of(targets, journey):
    if not targets:
        return None
    return (targets.get("taps") or {}).get(journey, targets.get("default_taps"))


def flags(row, base, target=None):
    out = []
    if row["status"] != "ok":
        out.append(f"broken: {row['note'] or 'a step was not found'}")
        return out
    if target is not None and row["taps"] > int(target):
        out.append(f"over target: {row['taps']} taps (target {target})")
    if base is None:
        out.append("first run: this is the baseline")
        return out
    bt, by, bs = int(base["taps"]), int(base["typed"]), float(base["seconds"])
    if row["taps"] > bt:
        out.append(f"more taps: {bt} → {row['taps']}")
    elif row["taps"] < bt:
        out.append(f"fewer taps: {bt} → {row['taps']}")
    if row["typed"] > by:
        out.append(f"more typing: {by} → {row['typed']} characters")
    for key, word in (("scrolls", "scrolls"), ("backs", "backs")):
        now, was = row.get(key), measured(base.get(key))
        if now is None or was is None:
            continue
        if now > was:
            out.append(f"more {word}: {was} → {now}")
        elif now < was:
            out.append(f"fewer {word}: {was} → {now}")
    if row["seconds"] > bs * SLOW_RATIO and row["seconds"] - bs > SLOW_FLOOR_S:
        out.append(f"slower: {bs:.1f}s → {row['seconds']:.1f}s")
    return out


def measured(value):
    """A history cell as a count, or None when the run predates counting it."""
    if value is None or str(value).strip() == "":
        return None
    return int(value)


def report(results, history, sha, ts, targets=None):
    base = baselines(history)
    lines, new_rows = [], []
    for r in results:
        b = base.get(r["journey"])
        f = flags(r, b, target_of(targets, r["journey"]))
        mark = "✗" if r["status"] != "ok" else ("⚠" if any(x.startswith(("more", "slower", "over")) for x in f) else "✓")
        counts = "" if r.get("scrolls") is None else f"scrolls={r['scrolls']:<2} backs={r.get('backs') or 0:<2} "
        lines.append(f"{mark} {r['journey']:<20} taps={r['taps']:<3} typed={r['typed']:<3} {counts}"
                     f"{r['seconds']:6.1f}s" + (f"   {'; '.join(f)}" if f else ""))
        blank = lambda v: "" if v is None else v
        new_rows.append(dict(ts=ts, sha=sha, journey=r["journey"], status=r["status"],
                             taps=r["taps"], typed=r["typed"], scrolls=blank(r.get("scrolls")),
                             backs=blank(r.get("backs")), seconds=f"{r['seconds']:.1f}",
                             note=r["note"]))
    return lines, new_rows


def append(history_path, rows):
    p = pathlib.Path(history_path)
    new = not p.exists()
    p.parent.mkdir(parents=True, exist_ok=True)
    # A history written before scrolls and backs were counted has the old
    # header: rewrite it once with the new columns, its rows kept, blank there.
    if not new:
        with p.open() as f:
            header = next(csv.reader(f), [])
        if header != FIELDS:
            old = read_history(p)
            with p.open("w", newline="") as f:
                w = csv.DictWriter(f, fieldnames=FIELDS, extrasaction="ignore", restval="")
                w.writeheader()
                for r in old:
                    w.writerow(r)
    with p.open("a", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        if new:
            w.writeheader()
        for r in rows:
            w.writerow(r)


def read_catalog(path):
    rows = []
    for line in pathlib.Path(path).read_text().splitlines():
        parts = line.split("\t")
        if len(parts) < 5 or not parts[0].strip():
            continue
        parts += [""] * (7 - len(parts))
        rows.append(dict(app=parts[0], ask=parts[1], taps=int(parts[2]), scrolls=int(parts[3]),
                         seconds=float(parts[4]), opened=parts[5], note=parts[6]))
    return rows


def catalog_report(rows, target=3):
    """The sweep's lines: a summary, then each app that needs a look."""
    flagged = []
    for r in rows:
        why = []
        if r["note"] or r["ask"] == "broken":
            why.append(f"broken: {r['note'] or 'a step was not found'}")
        elif r["ask"] == "none":
            why.append("no first step found")
        elif r["taps"] > target:
            why.append(f"over target: {r['taps']} taps (target {target})")
        if why:
            flagged.append(f"⚠ {r['app']:<24} {r['ask']:<10} taps={r['taps']:<2} " + "; ".join(why))
    kinds = {}
    for r in rows:
        kinds[r["ask"]] = kinds.get(r["ask"], 0) + 1
    summary = (f"catalogue: {len(rows)} apps · {len(flagged)} need a look · asks: "
               + ", ".join(f"{k} {n}" for k, n in sorted(kinds.items(), key=lambda kv: -kv[1])))
    return [summary] + flagged


def main(argv):
    if argv and argv[0] == "--catalog":
        if len(argv) < 2 or not pathlib.Path(argv[1]).exists():
            print("✗ no catalogue results — read the run's xcodebuild.log")
            return 1
        target = 3
        if len(argv) > 2 and pathlib.Path(argv[2]).exists():
            import json
            target = int(json.loads(pathlib.Path(argv[2]).read_text()).get("default_taps", 3))
        print("\n".join(catalog_report(read_catalog(argv[1]), target)))
        return 0
    if len(argv) not in (3, 4):
        print(__doc__.strip().splitlines()[-1])
        return 2
    results_path, history_path, sha = argv[:3]
    targets = None
    if len(argv) == 4 and pathlib.Path(argv[3]).exists():
        import json
        targets = json.loads(pathlib.Path(argv[3]).read_text())
    if not pathlib.Path(results_path).exists():
        print(f"✗ no results at {results_path} — the test run wrote nothing; read its xcodebuild.log")
        return 1
    results = read_results(results_path)
    if not results:
        print("✗ the results file is empty — no journey reached its end or its first step")
        return 1
    ts = datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
    lines, rows = report(results, read_history(history_path), sha, ts, targets)
    print("\n".join(lines))
    append(history_path, rows)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
