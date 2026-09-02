#!/usr/bin/env python3
"""WHERE THE MIDDLE TIER IS, AND WHAT EACH SITE IS DOING (prd §564).

The house style is TWO TIERS: one thing enormous, everything else quiet. The
ramp today is three — 29 sites at the head rungs, ~114 in the middle
(`heading22`/`stat24`/`price16`), ~1,300 small — and the middle is where the
style stops being itself.

This is the CHEAP INSTRUMENT, not a fix and not a gate. It prints every
middle-tier site with the text it sets and the shape of the file it sits in, so
a sweep can be judged site by site instead of run blind. Several of these rungs
are SETTLED — §551 measured `stat24` for the room chassis, §451 made a head
card's lead a note at `heading22`, §560 settled `DSSheetHead` at `heading34`
and the receipt's party at `heading22` — so a blanket edit would reverse
rulings that have measurements behind them. The census exists to tell those
apart from the sites nobody ever ruled on.

Usage:
    scripts/support/ramp-census.py            # the whole census, grouped
    scripts/support/ramp-census.py --summary  # counts per rung per file kind
    scripts/support/ramp-census.py --flat     # surfaces with NO rung above body17

**`--flat` is the mode that found something.** The middle tier turned out to be
mostly SETTLED — 26 of the 114 are a room head card's lead at `heading22`,
which §451 ruled deliberately — so "delete the middle tier" would have reversed
rulings rather than found faults. What is a real fault is a surface with no
crown AT ALL: everything in the bottom two tiers, so nothing on it is the
subject. `NetworkReachScreen` was the sharpest case (prd §564) — the app's
central privacy claim set at `subhead13`, above a list of sixty services each
of whose NAME was drawn larger than the claim.

Most flat surfaces are correctly flat and the tool does not pretend otherwise:
a ROW is quiet ground by design (`ShapedRows`), a connect screen is §190 slabs,
and a directory is a list. Read the output, do not sweep it.
"""
import re
import sys
import pathlib
import collections

MIDDLE = ("heading22", "stat24", "price16")
HEAD = ("price48", "price40", "heading34")
SOURCES = ["Casberi/Casberi/Screens", "Casberi/Casberi/Design",
           "Casberi/Casberi/Shell", "Casberi/CasberiWidgets"]

CALL = re.compile(r"dsText\(\.(\w+)\)")
# The Text(...) this modifier is attached to — usually the line above.
TEXT = re.compile(r'Text\((?:verbatim:\s*)?(.{0,60})')


def kind_of(name):
    if name.endswith("RoomCard.swift"):
        return "room head card"
    if name.endswith("Sheet.swift") or name.endswith("SheetViews.swift"):
        return "sheet"
    if name.endswith("Card.swift"):
        return "card"
    if name.endswith("Screen.swift"):
        return "screen"
    if name.startswith("DS"):
        return "design component"
    return "other"


def census(root):
    rows = []
    for src in SOURCES:
        base = root / src
        if not base.exists():
            continue
        for path in sorted(base.rglob("*.swift")):
            lines = path.read_text(encoding="utf-8", errors="replace").split("\n")
            for i, line in enumerate(lines):
                m = CALL.search(line)
                if not m or m.group(1) not in MIDDLE:
                    continue
                # what text is being set: look back up to 3 lines for a Text(
                subject = ""
                for j in range(i, max(-1, i - 4), -1):
                    t = TEXT.search(lines[j])
                    if t:
                        subject = t.group(1).strip().rstrip(")").strip()
                        break
                rows.append({
                    "rung": m.group(1),
                    "file": path.name,
                    "kind": kind_of(path.name),
                    "line": i + 1,
                    "subject": subject[:56],
                })
    return rows


ORDER = ["price48", "heading34", "price40", "stat24", "heading22",
         "reading20", "price16", "body17", "callout15", "subhead13",
         "label12", "label11"]
RANK = {r: i for i, r in enumerate(ORDER)}
BIG = set(HEAD) | set(MIDDLE)


def flat(root, floor=4):
    """Surfaces with `floor`+ text sites and nothing above `body17`."""
    out = []
    for src in SOURCES:
        base = root / src
        if not base.exists():
            continue
        for path in sorted(base.rglob("*.swift")):
            text = path.read_text(encoding="utf-8", errors="replace")
            rungs = [r for r in CALL.findall(text) if r in RANK]
            if len(rungs) < floor:
                continue
            biggest = min(rungs, key=lambda r: RANK[r])
            if biggest in BIG:
                continue
            out.append((len(rungs), biggest, path.name, kind_of(path.name)))
    out.sort(reverse=True)
    return out


def main():
    root = pathlib.Path(__file__).resolve().parent.parent.parent
    if "--flat" in sys.argv:
        rows = flat(root)
        print(f"{len(rows)} surfaces with 4+ text sites and NO rung above body17.")
        print("A row, a connect slab and a directory are CORRECTLY flat — read, do not sweep.\n")
        for n, biggest, name, kind in rows:
            print(f"  {n:>3} sites  biggest={biggest:<11} {name:<36} {kind}")
        return 0
    rows = census(root)
    if "--summary" in sys.argv:
        by_kind = collections.Counter((r["kind"], r["rung"]) for r in rows)
        print(f"{len(rows)} middle-tier sites\n")
        for (kind, rung), n in sorted(by_kind.items(), key=lambda x: -x[1]):
            print(f"  {n:>4}  {rung:<10} {kind}")
        print()
        by_file = collections.Counter(r["file"] for r in rows)
        print("  heaviest files:")
        for f, n in by_file.most_common(12):
            print(f"  {n:>4}  {f}")
        return 0
    by_kind = collections.defaultdict(list)
    for r in rows:
        by_kind[r["kind"]].append(r)
    for kind in sorted(by_kind):
        print(f"\n=== {kind} ({len(by_kind[kind])}) ===")
        for r in sorted(by_kind[kind], key=lambda x: (x["file"], x["line"])):
            print(f"  {r['rung']:<10} {r['file']}:{r['line']:<5} {r['subject']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
