#!/usr/bin/env python3
"""THE FEED ROW SKELETON (prd §586, §744) — one anatomy for the surface people read.

**Since §744 the skeleton is a TEMPLATE, `Design/DSFeedRow.swift`, and this
audit asserts that every feed row composes it.** The five-row agreement below
was what §586 found; §744 found the other fifteen rows it never listed (a 36pt
token disc, a 38pt L2BEAT mark, a 44pt album lead, a 56pt reading thumb, a post
whose name was 13pt) and put all of them through one view. The template owns the
lead size, the name rung and the rhythm, so those are checked ONCE, on the
template; each row is checked for composing it and for saying when.

The feed is the product, and a reader learns a row shape ONCE. Measured
2026-09-03, the seven row species in `ShapedRows.swift` already agree on a
skeleton, and nothing enforced it:

    HStack(alignment: .top, spacing: DS.Space.s3)
      mark            BridgeIcon at DS.Mark.row, or a thumb standing in for it
      VStack          title at body17, supporting line at subhead12/label12
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
TEMPLATE = "Casberi/Casberi/Design/DSFeedRow.swift"
FEEDSCREEN = "Casberi/Casberi/Screens/FeedScreen.swift"
# Every directory whose views may animate a figure — checked by `check_rolls`.
ROLL_DIRS = ["Casberi/Casberi/Screens", "Casberi/Casberi/Design",
             "Casberi/Casberi/Shell", "Casberi/Casberi/GenUI"]

# Every row species the feed draws, and the file it lives in. `check_complete`
# proves this list against what `FeedScreen`'s row builders actually construct,
# so a new species cannot land without being named here.
FEED_ROWS = {
    "BandRow": ROWS, "ReadingRow": ROWS, "ExcerptRow": ROWS, "MediaRow": ROWS,
    "MusicRow": ROWS, "TokenRow": ROWS, "BundleRow": ROWS, "StripRow": ROWS,
    "PostCard": ROWS, "SocialThreadCard": ROWS, "AppReviewRow": ROWS,
    "TakeawayCard": ROWS,
    "CursorRow": "Casberi/Casberi/Screens/CursorRow.swift",
    "WalletbeatWalletRow": "Casberi/Casberi/Screens/WalletbeatRow.swift",
    "WalletbeatNewsRow": "Casberi/Casberi/Screens/WalletbeatRow.swift",
    "L2beatChainRow": "Casberi/Casberi/Screens/L2beatRow.swift",
    "L2beatNewsRow": "Casberi/Casberi/Screens/L2beatRow.swift",
}

# Constructed by a row builder but NOT a feed row, and why.
NOT_ROWS = {
    "ApprovalCard": "a consent card: two buttons that sign or refuse, which a "
                    "row's single tap-to-open cannot carry (prd §83)",
    "VibenetEventRow": "composes DSFeedRow in VibenetRoomCard.swift, checked by "
                       "name below",
}

# A row that trails something other than a time, and why.
KNOWN_NO_TIME = {
    "TokenRow": "trails the live price (price17) — a watched token's row is "
                "about what it costs now, and a timestamp would report when we "
                "last fetched",
    "WalletbeatWalletRow": "a watched wallet's standing rating trails its stage — "
                           "a rating is not an event, so it has no when",
    "L2beatChainRow": "a watched chain's standing assessment trails its stage — "
                      "an assessment is not an event, so it has no when",
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

def check(src: str, only: "str | None" = None) -> list[str]:
    """Each row composes the template and says when. `src` is one file's text;
    rows that live in another file are skipped unless `only` names them."""
    bad = []
    for name, path in FEED_ROWS.items():
        if only is not None and name != only:
            continue
        b = body(src, name)
        if b is None:
            bad.append(f"{name}: not found in {path} — the feed-row list is stale, "
                       f"so this audit is covering less than it claims")
            continue
        b = strip_comments(b)
        if "DSFeedRow(" not in b:
            bad.append(f"{name}: does not compose DSFeedRow — a row that draws its "
                       f"own HStack picks its own lead, name rung and edge (prd §744)")
        if "LiveTimeText" not in b and name not in KNOWN_NO_TIME:
            bad.append(f"{name}: nothing in the trailing slot — every feed row "
                       f"says WHEN there, or is named in KNOWN_NO_TIME with why")
    for name in KNOWN_NO_TIME:
        if only is not None and name != only:
            continue
        b = body(src, name)
        if b and "LiveTimeText" in strip_comments(b):
            bad.append(f"{name}: is exempted from the trailing time but draws one — "
                       f"remove the exemption, it is now a snooze")
    return bad


def check_template(src: str) -> list[str]:
    """The anatomy lives in ONE place; these are its load-bearing facts."""
    b = strip_comments(src)
    bad = []
    for needle, why in [
        (".dsText(.body17)", "the name is not at body17 — the feed's own reading rung"),
        ("DS.Space.s2", "no vertical rhythm (DS.Space.s2) — rows would sit at two heights"),
        ("DS.Mark.row", "the lead is not the 26pt row mark — the column loses its one edge"),
        (".frame(width: Self.leadSize, height: Self.leadSize)",
         "the lead is not framed — a 28pt face or a 38pt mark would push the column right"),
        (".dsText(.body17)", "the line is not at body17"),
    ]:
        if needle not in b:
            bad.append(f"DSFeedRow: {why}")
    if "AnyView" in b:
        bad.append("DSFeedRow: erases through AnyView — the template draws for every "
                   "visible row, and depth is the first-frame stack overflow")
    return bad


def check_complete(feedscreen: str) -> list[str]:
    """Every species a row builder constructs is a listed row or a reasoned
    non-row — so the list above cannot silently fall short."""
    src = strip_comments(feedscreen)
    built = set()
    for fn in ("private func shapedRow(", "private func socialRow("):
        i = src.find(fn)
        if i < 0:
            return [f"FeedScreen: `{fn}` is gone — completeness cannot be proven"]
        j = src.find("\n    private ", i + 1)
        j2 = src.find("\n    func ", i + 1)
        end = min(x for x in (j, j2, len(src)) if x > 0)
        built |= set(re.findall(r'\b([A-Z]\w*(?:Row|Card))\(', src[i:end]))
    built -= {"DSFeedRow", "WalletRow"}
    bad = []
    for name in sorted(built):
        if name not in FEED_ROWS and name not in NOT_ROWS:
            bad.append(f"{name}: a row builder constructs it and it is neither a "
                       f"listed feed row nor a reasoned non-row")
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
    ways — `price17` in the Wallet room, `subhead12` on Hegota, `body17` on
    Frames, and buried INSIDE the title sentence on Wallet's own pushed history
    screen. A reader crossing from a room to its "See activity" screen met the
    same transaction in a different grammar.

    `price17` is the app's row-money rung and the one the most-drawn surface
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
        if ".dsText(.price17)" not in b:
            bad.append(f"{name}: a signed amount is not at price17 — four activity "
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
            "    DSFeedRow(name: x) { m } trailing: {\n    LiveTimeText(date: d)\n"
            "  } }\n}\n")
    cases = [
        ("a row composing the template passes", good.replace("ARow", "BandRow"), False),
        ("a row drawing its own HStack is flagged",
         good.replace("ARow", "BandRow").replace("DSFeedRow(name: x)", "HStack"), True),
        ("a row with no trailing time is flagged",
         good.replace("ARow", "BandRow").replace("    LiveTimeText(date: d)\n", ""), True),
        ("a missing row species is flagged, not skipped", "struct Other: View {}\n", True),
        ("an exempt row keeps the template",
         good.replace("ARow", "TokenRow").replace("    LiveTimeText(date: d)\n", ""), False),
        ("an exemption that no longer applies is flagged",
         good.replace("ARow", "TokenRow"), True),
        ("a commented-out template does not satisfy the check",
         good.replace("ARow", "BandRow").replace("DSFeedRow(name: x)", "// DSFeedRow(name: x)\n HStack"), True),
    ]
    for label, src, should_fail in cases:
        name = "BandRow" if "BandRow" in src or "Other" in src else "TokenRow"
        failed = bool(check(src, only=name))
        if failed != should_fail:
            print(f"  ✗ self-test: {label}"); sys.exit(1)
        print(f"  ok   {label}")
    tmpl = ("struct DSFeedRow { .dsText(.body17) DS.Space.s2 DS.Mark.row "
            ".frame(width: Self.leadSize, height: Self.leadSize) .dsText(.body17) }")
    for label, src, should_fail in [
        ("the template's facts pass", tmpl, False),
        ("a template whose lead is unframed is flagged",
         tmpl.replace(".frame(width: Self.leadSize, height: Self.leadSize)", ""), True),
        ("a template off the reading rung is flagged", tmpl.replace("body17", "heading24"), True),
        ("a template erasing through AnyView is flagged", tmpl + " AnyView(", True),
    ]:
        if bool(check_template(src)) != should_fail:
            print(f"  ✗ self-test: {label}"); sys.exit(1)
        print(f"  ok   {label}")
    fs = ("    private func shapedRow(_ t: Thing) {\n  BandRow(thing: t)\n  NEWROW\n}\n"
          "    private func socialRow(_ t: Thing) {\n  PostCard(thing: t)\n}\n"
          "    private func other() {}\n")
    for label, src, should_fail in [
        ("every constructed row is listed", fs.replace("NEWROW", ""), False),
        ("an unlisted row species is flagged", fs.replace("NEWROW", "ShinyRow(thing: t)"), True),
        ("a reasoned non-row passes", fs.replace("NEWROW", "ApprovalCard(thing: t)"), False),
        ("a vanished builder is flagged", "nothing here", True),
    ]:
        if bool(check_complete(src)) != should_fail:
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
         "struct BandRow: View {\n .dsText(.price17)\n .monospacedDigit()\n}\n", False),
        ("an amount off the shared rung is flagged",
         "struct BandRow: View {\n .dsText(.subhead12)\n .monospacedDigit()\n}\n", True),
        ("a non-tabular amount is flagged",
         "struct BandRow: View {\n .dsText(.price17)\n}\n", True),
        ("a COMMENTED rung does not satisfy it",
         "struct BandRow: View {\n // .dsText(.price17)\n .monospacedDigit()\n}\n", True),
        ("a renamed money row is flagged, not skipped",
         "struct BandRowX: View {\n .dsText(.price17)\n .monospacedDigit()\n}\n", True),
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
    bad = []
    by_file: "dict[str, str]" = {}
    for name, path in FEED_ROWS.items():
        src = by_file.setdefault(path, pathlib.Path(path).read_text())
        bad += check(src, only=name)
    vib = pathlib.Path("Casberi/Casberi/Screens/VibenetRoomCard.swift").read_text()
    vb = body(vib, "VibenetEventRow")
    if vb is None or "DSFeedRow(" not in strip_comments(vb):
        bad.append("VibenetEventRow: does not compose DSFeedRow (prd §744)")
    bad += check_template(pathlib.Path(TEMPLATE).read_text())
    bad += check_complete(pathlib.Path(FEEDSCREEN).read_text())
    files = []
    for d in ROLL_DIRS:
        for f in sorted(pathlib.Path(d).glob("*.swift")):
            files.append((str(f), f.read_text()))
    bad += check_rolls(files) + check_money({})
    if bad:
        for b in bad: print(f"✗ {b}")
        sys.exit(1)
    rolls = sum(s.count("numericText") for _, s in files)
    print(f"✓ feed row skeleton: {len(FEED_ROWS) + 1} row species compose DSFeedRow, "
          f"{len(KNOWN_NO_TIME)} trailing something other than a time with a reason; "
          f"{rolls} rolling figures, all tabular; "
          f"{len(MONEY_ROWS)} money rows at one rung, "
          f"{len(KNOWN_NO_AMOUNT)} stating no amount with a reason")
