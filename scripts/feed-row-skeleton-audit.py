#!/usr/bin/env python3
"""THE FEED ROW SKELETON (prd §586) — one grammar for the surface people read.

The feed is the product, and a reader learns a row shape ONCE. Measured
2026-09-03, the seven row species in `ShapedRows.swift` already agree on a
skeleton, and nothing enforced it:

    HStack(alignment: .top, spacing: DS.Space.s3)
      mark            BridgeIcon at DS.Mark.row, or a thumb standing in for it
      VStack          title at body17, supporting line at subhead13/label12
      trailing        LiveTimeText — the same fact, in the same corner
    .padding(.vertical, DS.Space.s2)

**This audit exists because the agreement was DISCOVERED, not designed.** Five
rows were written months apart and arrived at the same anatomy; a sixth written
tomorrow has nothing to arrive at except whatever its author remembers. That is
the shape of every drift this repo has a ledger entry for, so it becomes a
check rather than a rule somebody re-reads.

**What it deliberately does NOT do.** It never judges the row's CONTENT — which
picture, which supporting line, whether the words are right — and it says
nothing about room heads, setup rows or cards. It asserts three mechanical
facts about the four corners of a feed row.

**The two exemptions are content, not drift.** A watchlist row trails a live
PRICE where the others trail a time, and that is correct: a watched token's row
is about what it costs now, and a timestamp there would report when we last
fetched, which means nothing to the reader. They are held to the rest of the
skeleton.
"""
from __future__ import annotations
import re, sys, pathlib

ROWS = "Casberi/Casberi/Screens/ShapedRows.swift"
# Every directory whose views may animate a figure — checked by `check_rolls`.
ROLL_DIRS = ["Casberi/Casberi/Screens", "Casberi/Casberi/Design",
             "Casberi/Casberi/Shell", "Casberi/Casberi/GenUI"]

# Every row species the feed draws. A new one must be added here WITH a reason
# if it cannot meet the skeleton — the curated-set shape `catalog-sync.sh` uses,
# so the list stays provably complete rather than silently short.
FEED_ROWS = ["BandRow", "ReadingRow", "ExcerptRow", "MediaRow", "MusicRow",
             "TokenRow", "PredictionRow"]

# A row that trails something other than a time, and why.
KNOWN_NO_TIME = {
    "TokenRow": "trails the live price (price16) — a watched token's row is "
                "about what it costs now, and a timestamp would report when we "
                "last fetched",
    "PredictionRow": "trails the market's own standing (price16) for the same "
                     "reason as TokenRow",
}

def body(src: str, name: str) -> str | None:
    # `private struct` counts — `WalletHistoryRow` is one, and requiring a bare
    # `struct` silently reported it MISSING rather than checking it.
    m = re.search(rf'^(?:private |fileprivate |internal |public )?struct {re.escape(name)}: View \{{',
                  src, re.M)
    if not m:
        return None
    depth, i = 0, m.end() - 1
    while i < len(src):
        if src[i] == '{': depth += 1
        elif src[i] == '}':
            depth -= 1
            if depth == 0: return src[m.start():i + 1]
        i += 1
    return None

def strip_comments(src: str) -> str:
    """Character scan — a `//` holding a `/*`, or a path glob, must not open a
    block that swallows the file (the hero-tint-audit lesson, whose stripper
    blanked 7,000 lines and then called the file clean)."""
    out, i, n = [], 0, len(src)
    while i < n:
        if src[i] == '/' and i + 1 < n and src[i+1] == '/':
            while i < n and src[i] != '\n': i += 1
        elif src[i] == '/' and i + 1 < n and src[i+1] == '*':
            i += 2
            while i + 1 < n and not (src[i] == '*' and src[i+1] == '/'): i += 1
            i += 2
        elif src[i] == '"':
            out.append(src[i]); i += 1
            while i < n and src[i] != '"':
                if src[i] == '\\': out.append(src[i]); i += 1
                if i < n: out.append(src[i]); i += 1
            if i < n: out.append(src[i]); i += 1
        else:
            out.append(src[i]); i += 1
    return "".join(out)

def check(src: str) -> list[str]:
    bad = []
    for name in FEED_ROWS:
        b = body(src, name)
        if b is None:
            bad.append(f"{name}: not found in ShapedRows.swift — the feed-row "
                       f"list is stale, so this audit is covering less than it claims")
            continue
        b = strip_comments(b)
        if ".dsText(.body17)" not in b:
            bad.append(f"{name}: the title is not at body17 — the feed's own reading rung")
        if "DS.Space.s2" not in b:
            bad.append(f"{name}: no vertical rhythm (DS.Space.s2) — rows would sit at two heights")
        if "LiveTimeText" not in b and name not in KNOWN_NO_TIME:
            bad.append(f"{name}: nothing in the trailing slot — every feed row "
                       f"says WHEN there, or is named in KNOWN_NO_TIME with why")
    for name in KNOWN_NO_TIME:
        b = body(src, name)
        if b and "LiveTimeText" in strip_comments(b):
            bad.append(f"{name}: is exempted from the trailing time but draws one — "
                       f"remove the exemption, it is now a snooze")
    return bad

# Every surface that draws a SIGNED AMOUNT in a row, and the file it lives in.
# A row that moves money states the figure in its trailing slot at one rung —
# see `check_money`.
MONEY_ROWS = {
    "BandRow": "Casberi/Casberi/Screens/ShapedRows.swift",
    "WalletHistoryRow": "Casberi/Casberi/Screens/WalletHistoryScreen.swift",
    "HegotaMoveRow": "Casberi/Casberi/Screens/HegotaRoomCard.swift",
    "FramesMoveRow": "Casberi/Casberi/Screens/FramesRoomCard.swift",
}

# An activity row with no amount, and why. `VibenetEventRow` draws EVENTS — a
# key added, an account created — not transfers, so it has no figure to state.
# The same shape as `KNOWN_NO_TIME` above: content, not drift.
KNOWN_NO_AMOUNT = {
    "VibenetEventRow": "draws events (a key added, an account created), not "
                       "transfers — there is no amount to state",
}


def check_money(files: "dict[str, str]") -> "list[str]":
    """ONE RUNG FOR A SIGNED AMOUNT IN A ROW (prd §587).

    Measured when this landed: four activity surfaces drew the same fact three
    ways — `price16` in the Wallet room, `subhead13` on Hegota, `callout15` on
    Frames, and buried INSIDE the title sentence on Wallet's own pushed history
    screen. A reader crossing from a room to its "See activity" screen met the
    same transaction in a different grammar.

    `price16` is the app's row-money rung and the one the most-drawn surface
    already used, so the others came to it.
    """
    bad = []
    for name, path in MONEY_ROWS.items():
        try:
            src = pathlib.Path(path).read_text()
        except OSError:
            bad.append(f"{name}: {path} not found — the money-row list is stale")
            continue
        b = body(src, name)
        if b is None:
            bad.append(f"{name}: not found in {path} — the money-row list is stale")
            continue
        b = strip_comments(b)
        if ".dsText(.price16)" not in b:
            bad.append(f"{name}: a signed amount is not at price16 — four activity "
                       f"surfaces state this fact and they share one rung")
        if "monospacedDigit" not in b:
            bad.append(f"{name}: the amount is not tabular")
    return bad


def check_rolls(files: "list[tuple[str, str]]") -> "list[str]":
    """A NUMBER THAT ROLLS MUST BE TABULAR (prd §586).

    `.numericText()` morphs one digit into the next, and proportional digits
    are different widths — so every frame of that morph is a different length
    and the line reflows while it animates. It is worst exactly where the
    feature is most used: a voice timer counting seconds, a chart price under
    a dragging finger, the trailing time on every feed row.

    Measured when this landed: 20 rolling figures, 8 paired and 12 not — no
    convention either way, which is why it becomes a check rather than a note.
    """
    bad = []
    for name, src in files:
        lines = strip_comments(src).split("\n")
        for i, l in enumerate(lines):
            if "contentTransition(" not in l or "numericText" not in l:
                continue
            near = "\n".join(lines[max(0, i - 10):i + 4])
            if "monospacedDigit" not in near:
                bad.append(f"{name}:{i + 1}: a figure rolls without tabular digits — "
                           f"the line reflows mid-animation")
    return bad


def self_test() -> None:
    good = ("struct ARow: View {\n  var body: some View {\n"
            "    Text(x).dsText(.body17)\n    LiveTimeText(date: d)\n"
            "  }.padding(.vertical, DS.Space.s2)\n}\n")
    cases = [
        ("a clean row passes", good.replace("ARow", "BandRow"), False),
        ("a title off the reading rung is flagged",
         good.replace("ARow", "BandRow").replace("body17", "heading22"), True),
        ("a row with no trailing time is flagged",
         good.replace("ARow", "BandRow").replace("    LiveTimeText(date: d)\n", ""), True),
        ("a row with no vertical rhythm is flagged",
         good.replace("ARow", "BandRow").replace("DS.Space.s2", "12"), True),
        ("a missing row species is flagged, not skipped", "", True),
        ("an exempt row keeps the rest of the skeleton",
         good.replace("ARow", "TokenRow").replace("    LiveTimeText(date: d)\n", ""), False),
        ("an exemption that no longer applies is flagged",
         good.replace("ARow", "TokenRow"), True),
        ("a commented-out time does not satisfy the check",
         good.replace("ARow", "BandRow").replace("LiveTimeText(date: d)", "// LiveTimeText"), True),
    ]
    for label, src, should_fail in cases:
        # only the row under test is present; the others are absent by design,
        # so compare against the findings for THAT row alone
        name = re.search(r'struct (\w+):', src).group(1) if src else None
        found = [f for f in check(src) if name and f.startswith(name)]
        failed = bool(found) if name else bool(check(src))
        if failed != should_fail:
            print(f"  ✗ self-test: {label}"); sys.exit(1)
        print(f"  ok   {label}")
    rolls = [
        ("a roll with tabular digits passes",
         "Text(n).monospacedDigit()\n.contentTransition(.numericText())", False),
        ("a roll without them is flagged",
         "Text(n)\n.contentTransition(.numericText())", True),
        ("a COMMENTED tabular modifier does not satisfy it",
         "Text(n)\n// .monospacedDigit()\n.contentTransition(.numericText())", True),
        ("a plain figure that never rolls is left alone",
         "Text(n).dsText(.body17)", False),
    ]
    for label, src, should_fail in rolls:
        if bool(check_rolls([("t.swift", src)])) != should_fail:
            print(f"  ✗ self-test: {label}"); sys.exit(1)
        print(f"  ok   {label}")
    import tempfile, os
    money = [
        ("a signed amount at the shared rung passes",
         "struct BandRow: View {\n .dsText(.price16)\n .monospacedDigit()\n}\n", False),
        ("an amount off the shared rung is flagged",
         "struct BandRow: View {\n .dsText(.subhead13)\n .monospacedDigit()\n}\n", True),
        ("a non-tabular amount is flagged",
         "struct BandRow: View {\n .dsText(.price16)\n}\n", True),
        ("a COMMENTED rung does not satisfy it",
         "struct BandRow: View {\n // .dsText(.price16)\n .monospacedDigit()\n}\n", True),
        ("a renamed money row is flagged, not skipped",
         "struct BandRowX: View {\n .dsText(.price16)\n .monospacedDigit()\n}\n", True),
    ]
    with tempfile.TemporaryDirectory() as td:
        for label, src, should_fail in money:
            f = os.path.join(td, "t.swift")
            pathlib.Path(f).write_text(src)
            found = [x for x in check_money({"BandRow": f}) if x.startswith("BandRow")]
            saved = dict(MONEY_ROWS); MONEY_ROWS.clear(); MONEY_ROWS["BandRow"] = f
            found = [x for x in check_money({}) if x.startswith("BandRow")]
            MONEY_ROWS.clear(); MONEY_ROWS.update(saved)
            if bool(found) != should_fail:
                print(f"  ✗ self-test: {label}"); sys.exit(1)
            print(f"  ok   {label}")

if __name__ == "__main__":
    if "--self-test" in sys.argv:
        self_test(); sys.exit(0)
    self_test()
    src = pathlib.Path(ROWS).read_text()
    files = []
    for d in ROLL_DIRS:
        for f in sorted(pathlib.Path(d).glob("*.swift")):
            files.append((str(f), f.read_text()))
    bad = check(src) + check_rolls(files) + check_money({})
    if bad:
        for b in bad: print(f"✗ {b}")
        sys.exit(1)
    rolls = sum(s.count("numericText") for _, s in files)
    print(f"✓ feed row skeleton: {len(FEED_ROWS)} row species, "
          f"{len(KNOWN_NO_TIME)} trailing a price with a reason; "
          f"{rolls} rolling figures, all tabular; "
          f"{len(MONEY_ROWS)} money rows at one rung, "
          f"{len(KNOWN_NO_AMOUNT)} stating no amount with a reason")
