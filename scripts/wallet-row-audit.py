#!/usr/bin/env python3
"""Wallet row audit (prd §1482, 2026-10-23).

WHY THIS EXISTS. The user, for the third time: *"i swear the spacing of text
is different on each screen in wallet. like your account is more spacing than
home and so on. it's fucking annoying we have tried this more than once to
fix."* Measured, it was true four ways at once — a push row with no floor
(30pt tall with no line, 47 with one), the feed row's 52, a hand-drawn row's
55 (8pt padding, a 1pt gap) and Your account's 68 (a 60pt frame plus air) —
and the groups drawn inside ONE list row ended 15pt from the trailing edge
where every other row ended 27. Two earlier passes fixed the rows they looked
at; nothing held the rest to them, so the next row written drifted again.

THE RULE (prd §1482): every list row on every Wallet page stands in one
anatomy — title `body17` over its line `subhead12`, 2pt apart; a head no
shorter than `DSFeed.headHeight` (44); `FeedScreen.rowAir` (4) above and
below; `DSRoomChassis.rowInset` both sides. Spelled once: a row of its own is
`.walletListRow()`, a stack of rows in one list row is `.walletStackRow()`
with each row wearing `.walletRowPitch()`.

SIX CHECKS, static, no build, over the Wallet's row files (`FILES`):

  A. No hand-written list-row insets that name a vertical air, a mark inset
     or a trailing `s4` — those are the three ways the pitch and the column
     drifted. `EdgeInsets()` (a box row) passes.
  B. No `.frame(minHeight: <literal>)` but 44 — the 60 and 52 that Your
     account and its menu rows wore. 44 is `DS.Hit.min`, a verb's height
     inside a row, and stays.
  C. No `.padding(.vertical, s1|s2)` on a view that draws a `body17` title in
     the lines above it — a row's air is `walletRowPitch()` or the list's.
  D. No title stack at a 1pt gap: `VStack(alignment: .leading, spacing: 1)`.
  E. `DSPushRowLabel` keeps the 44pt head and the 2pt gap — the template half
     of the rule, since every door on Home is one.
  F. `WalletCardStyle.rowInsets` opens and closes on `FeedScreen.rowAir`, and
     `stackInsets` on 0 — the constants every modifier reads.

WHAT THIS DELIBERATELY DOES NOT CHECK, so it stays honest about its reach:

  · A row in a SHEET (the Tokens tray) keeps its own horizontal padding; its
    pitch and gap are checked, its edges are the tray's.
  · Whether a row is drawn through a template at all. A hand-drawn `HStack`
    at the right numbers passes; the one-anatomy rule (§744) is
    `feed-row-skeleton-audit.py`'s, not this file's.
  · Rows outside `FILES`. The Wallet's rows live in these files today; a new
    Wallet file is added here by hand, and `harness-exists-audit.py` does not
    know to ask. Stated rather than hidden.
"""

import re
import shutil
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = "Casberi/Casberi"

FILES = [
    "Screens/FeedScreen+WalletHome.swift",
    "Screens/FeedScreen+WalletPages.swift",
    "Screens/FeedScreen+WalletSecurity.swift",
    "Screens/FeedScreen+WalletRoom.swift",
    "Screens/FeedScreen+WalletNeeds.swift",
    "Screens/FeedScreen+Spending.swift",
    "Screens/FeedScreen+Subscriptions.swift",
    "Screens/MoveSecurity.swift",
    "Screens/WalletRow.swift",
    "Screens/WalletTokens.swift",
    "Screens/WalletActingPartiesRows.swift",
    "Screens/WalletApprovalExposureCard.swift",
    "Screens/WalletNFTRows.swift",
    "Screens/WalletPerpsCard.swift",
    "Screens/WalletLiquidityCard.swift",
    "Screens/WalletAztecStakingCard.swift",
    "Screens/WalletZFiOrdersCard.swift",
]
PUSH_ROW = "Design/DSPushRow.swift"
CARD_STYLE = "Screens/WalletFeedTiles.swift"

INSETS = re.compile(r"\.listRowInsets\(\s*(?:EdgeInsets|\.init)\(([^()]*(?:\([^()]*\)[^()]*)*)\)\)")
DRIFT_INSET = re.compile(r"rowAir|DS\.Space\.s[12]\b|rowInset\(forMark|trailing:\s*DS\.Space\.s4")
MIN_HEIGHT = re.compile(r"\.frame\(minHeight:\s*(\d+)\b")
ROW_AIR = re.compile(r"\.padding\(\.vertical,\s*DS\.Space\.s[12]\)")
ONE_PT = re.compile(r"VStack\(alignment:\s*\.leading,\s*spacing:\s*1\)")


def strip_comments(text: str) -> str:
    """Comments out, strings kept, line breaks kept (the repo's rules name
    the symbols they govern, so a raw scan fires on its own prose)."""
    out, i, n = [], 0, len(text)
    in_block = in_string = False
    while i < n:
        ch, nxt = text[i], text[i + 1] if i + 1 < n else ""
        if in_block:
            if ch == "*" and nxt == "/":
                in_block = False
                i += 2
                continue
            out.append(ch if ch == "\n" else " ")
            i += 1
            continue
        if in_string:
            if ch == "\\":
                out.append("  ")
                i += 2
                continue
            if ch == '"':
                in_string = False
            out.append(ch)
            i += 1
            continue
        if ch == "/" and nxt == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if ch == "/" and nxt == "*":
            in_block = True
            i += 2
            continue
        if ch == '"':
            in_string = True
        out.append(ch)
        i += 1
    return "".join(out)


def line_of(text: str, pos: int) -> int:
    return text.count("\n", 0, pos) + 1


def check(root: Path) -> list:
    problems = []
    for rel in FILES:
        path = root / SRC / rel
        if not path.exists():
            problems.append(f"{rel}: listed in FILES but missing — remove the entry or restore the file")
            continue
        text = strip_comments(path.read_text())
        lines = text.split("\n")
        for m in INSETS.finditer(text):
            if DRIFT_INSET.search(m.group(1)):
                problems.append(f"{rel}:{line_of(text, m.start())}: A hand-written row insets — use .walletListRow() / .walletStackRow()")
        for m in MIN_HEIGHT.finditer(text):
            if m.group(1) != "44":
                problems.append(f"{rel}:{line_of(text, m.start())}: B .frame(minHeight: {m.group(1)}) — a row's head is DSFeed.headHeight (walletRowPitch())")
        for m in ROW_AIR.finditer(text):
            ln = line_of(text, m.start())
            above = "\n".join(lines[max(0, ln - 24):ln])
            if ".dsText(.body17)" in above:
                problems.append(f"{rel}:{ln}: C a row padded by hand — its air is walletRowPitch() or the list's")
        for m in ONE_PT.finditer(text):
            problems.append(f"{rel}:{line_of(text, m.start())}: D a title stack at a 1pt gap — the gap is 2")
    push = strip_comments((root / SRC / PUSH_ROW).read_text())
    label = push.split("struct DSPushRowTrail")[0]
    if ".frame(minHeight: DSFeed.headHeight)" not in label:
        problems.append(f"{PUSH_ROW}: E DSPushRowLabel lost its 44pt head (DSFeed.headHeight)")
    if "VStack(alignment: .leading, spacing: 2)" not in label:
        problems.append(f"{PUSH_ROW}: E DSPushRowLabel's title stack is not at the 2pt gap")
    style = strip_comments((root / SRC / CARD_STYLE).read_text())
    rows = re.search(r"static var rowInsets: EdgeInsets \{\s*EdgeInsets\(top: FeedScreen\.rowAir, leading: DSRoomChassis\.rowInset,\s*bottom: FeedScreen\.rowAir, trailing: DSRoomChassis\.rowInset\)", style)
    stack = re.search(r"static var stackInsets: EdgeInsets \{\s*EdgeInsets\(top: 0, leading: DSRoomChassis\.rowInset, bottom: 0, trailing: DSRoomChassis\.rowInset\)", style)
    if not rows:
        problems.append(f"{CARD_STYLE}: F WalletCardStyle.rowInsets is not rowAir / rowInset on every side")
    if not stack:
        problems.append(f"{CARD_STYLE}: F WalletCardStyle.stackInsets is not 0 / rowInset")
    return problems


# One mutation per check, each on a line the clean tree holds.
MUTATIONS = [
    ("A", "Screens/FeedScreen+WalletPages.swift", ".walletListRow()",
     ".listRowInsets(EdgeInsets(top: Self.rowAir, leading: DSRoomChassis.rowInset, bottom: Self.rowAir, trailing: DSRoomChassis.rowInset))"),
    ("A", "Screens/FeedScreen+WalletRoom.swift", ".walletStackRow()",
     ".listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.rowInset(forMark: DS.Face.list), bottom: 0, trailing: DS.Space.s4))"),
    ("B", "Screens/MoveSecurity.swift", ".walletRowPitch()", ".frame(minHeight: 60).padding(.vertical, DS.Space.s1)"),
    ("C", "Screens/WalletRow.swift", ".walletRowPitch()", ".padding(.vertical, DS.Space.s2)"),
    ("D", "Screens/WalletRow.swift", "VStack(alignment: .leading, spacing: 2) {\n                Text(title)",
     "VStack(alignment: .leading, spacing: 1) {\n                Text(title)"),
    ("E", PUSH_ROW, ".frame(minHeight: DSFeed.headHeight)", ""),
    ("E", PUSH_ROW, "VStack(alignment: .leading, spacing: 2) {\n                title", "VStack(alignment: .leading, spacing: 1) {\n                title"),
    ("F", CARD_STYLE, "EdgeInsets(top: FeedScreen.rowAir, leading: DSRoomChassis.rowInset,\n                   bottom: FeedScreen.rowAir, trailing: DSRoomChassis.rowInset)",
     "EdgeInsets(top: DS.Space.s3, leading: DSRoomChassis.rowInset,\n                   bottom: 0, trailing: DSRoomChassis.rowInset)"),
]


def self_test() -> int:
    clean = check(ROOT)
    if clean:
        print("self-test: the clean tree does not pass, so no mutation can be judged:")
        print("\n".join("  " + p for p in clean))
        return 1
    failures = 0
    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp)
        for rel in FILES + [PUSH_ROW, CARD_STYLE]:
            dst = base / SRC / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(ROOT / SRC / rel, dst)
        for i, (letter, rel, old, new) in enumerate(MUTATIONS, 1):
            path = base / SRC / rel
            original = path.read_text()
            if old not in original:
                print(f"  mutation {i} ({letter}) DEAD: anchor not in {rel} — the applier drifted, not the check")
                failures += 1
                continue
            path.write_text(original.replace(old, new, 1))
            found = [p for p in check(base) if f": {letter} " in p or f" {letter} " in p]
            path.write_text(original)
            if found:
                print(f"  mutation {i} ({letter}) caught: {found[0]}")
            else:
                print(f"  mutation {i} ({letter}) SURVIVED — {rel}: {old[:50]!r} → {new[:50]!r}")
                failures += 1
    print(f"self-test: {len(MUTATIONS) - failures}/{len(MUTATIONS)} mutations caught")
    return 1 if failures else 0


def main(argv) -> int:
    if "--self-test" in argv:
        return self_test()
    problems = check(ROOT)
    if problems:
        print("wallet-row-audit: a Wallet row stands off the one pitch (prd §1482):")
        print("\n".join("  " + p for p in problems))
        return 1
    print(f"✓ wallet-row-audit: {len(FILES)} files at one row pitch (prd §1482)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
