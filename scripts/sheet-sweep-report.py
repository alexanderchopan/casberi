#!/usr/bin/env python3
"""The sheet sweep's report (prd §1308): one line per sheet that did not open
or did not close, then the count. Read by `journeys.sh sheets` and printed into
the nightly's report by `nightly-mac.sh`.

A sheet in the manifest with no row is reported too: the sweep died before it
(a crash takes the run with it), which is the worst result, not a missing one.

Usage: scripts/sheet-sweep-report.py <sheets.tsv> <sheet-sweep.json> [ids]
  ids: the comma list the run was narrowed to (JOURNEYS_SHEETS), if any.
Exit 0 when a report was written.
"""

import json
import sys


def read(tsv):
    rows = {}
    for line in open(tsv, encoding="utf-8"):
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 5:
            continue
        sid, opened, swipe, control, seconds = parts[:5]
        rows[sid] = dict(opened=opened, swipe=swipe, control=control,
                         seconds=seconds, note=parts[5] if len(parts) > 5 else "")
    return rows


def report(rows, manifest, only=()):
    entries = [e["id"] for e in manifest.get("entries", []) if not only or e["id"] in only]
    exempt = sum(len(x.get("covers", [])) for x in manifest.get("exempt", []))
    lines, bad = [], 0
    for sid in entries:
        r = rows.get(sid)
        if r is None:
            bad += 1
            lines.append(f"✗ {sid}: no row — the sweep stopped before it (a crash?)")
            continue
        fails = [k for k in ("opened", "swipe", "control") if r[k] == "fail"]
        if fails:
            bad += 1
            what = {"opened": "did not open", "swipe": "pull down did not close it",
                    "control": "its control did not close it"}
            lines.append(f"✗ {sid}: {', '.join(what[f] for f in fails)} — {r['note']}")
    good = len(entries) - bad
    both = sum(1 for s in entries if rows.get(s, {}).get("swipe") == "ok"
               and rows.get(s, {}).get("control") == "ok")
    lines.append(f"{good} of {len(entries)} sheets open and close ({both} checked both ways); "
                 f"{exempt} exempt, not swept")
    return lines, bad


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    rows = read(sys.argv[1])
    manifest = json.load(open(sys.argv[2], encoding="utf-8"))
    only = {s for s in (sys.argv[3] if len(sys.argv) > 3 else "").split(",") if s}
    lines, _ = report(rows, manifest, only)
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
