#!/usr/bin/env python3
"""EVERY TOKEN LIST IN MOVE IS `MoveTokenGrid` (prd §1910, user 2026-11-19:
"make it consistent", "it shouldn't be hand rolled on any screen in move").

A token and its network are one pick, drawn one way: each place under its
title, each token Home's own row (`TokenRowLabel`, prd §1917; tiles at
Home's app-icon size until then) (`Screens/MoveDeck.swift`). Before this,
Send's With drew tiles, Swap's For and Buy's card list drew rows, Earn drew
tiles with no network titles, and the private screens drew rows of their own,
so a token looked different on every verb. Every one of them renders, so
nothing but a check sees a new hand-drawn list.

Two checks over Move's screens (`Screens/Move*.swift`, `Shell/Move*.swift`),
comments ignored, `MoveDeck.swift` (the template) excepted:

  (1) A TOKEN TILE BY HAND. `MoveRowMark(token: …, size: <a tile's size>)`
      (`DSHomeCircleMetrics.face`, `DS.Face.seat`) is a token face at Home's
      size outside the grid. Build a `MoveTokenChoice` instead.
  (2) A TOKEN ROW BY HAND. `AssetMark(name:` is a token's art drawn into a
      row of the screen's own; `MoveRowMark` (in `MoveBack.swift`) and the
      grid are the two doors to it.

The allowance below is per file, with its reason, and is a CEILING and a
FLOOR: more is a new hand-drawn list, fewer is a stale allowance to lower.

**STATED CEILINGS.** It reads one call at a time: a tile whose face is a
`View` built elsewhere and handed in passes, as does a list of tokens drawn as
plain words with no mark. Rows that are not tokens (people, merchants,
networks, sums) are not its business.
"""

import re
import sys
from pathlib import Path

ROOT = Path("Casberi/Casberi")
TEMPLATE = "MoveDeck.swift"
MARK_HOME = "MoveBack.swift"

ALLOWED = {
    "MoveSentence.swift": {
        "tile": (2, "personTile and merchantTile draw a NAME's lettered mark when a person or a shop has no face; neither is a token"),
    },
    "MovePrivate.swift": {
        "row": (1, "`amounts` lists SUMS of a token (0.01 ETH, 10 USDC): an amount row, not a token pick"),
    },
}

TILE = re.compile(r'MoveRowMark\(\s*token:[^)]*size:\s*(?:DSHomeCircleMetrics\.face|DS\.Face\.seat)\b')
ROW = re.compile(r'\bAssetMark\(\s*name:')


def strip_comments(src: str) -> str:
    src = re.sub(r'/\*.*?\*/', lambda m: '\n' * m.group(0).count('\n'), src, flags=re.S)
    out = []
    for line in src.split('\n'):
        i = line.find('//')
        while i != -1 and line[:i].count('"') % 2 == 1:
            i = line.find('//', i + 2)
        out.append(line if i == -1 else line[:i])
    return '\n'.join(out)


def scan(name: str, src: str) -> dict:
    text = strip_comments(src)
    found = {"tile": [], "row": []}
    if name == TEMPLATE:
        return found
    for m in TILE.finditer(text):
        found["tile"].append(text.count('\n', 0, m.start()) + 1)
    if name != MARK_HOME:
        for m in ROW.finditer(text):
            found["row"].append(text.count('\n', 0, m.start()) + 1)
    return found


def judge(name: str, found: dict) -> list:
    failures = []
    for check, lines in found.items():
        allowed, reason = ALLOWED.get(name, {}).get(check, (0, ""))
        if len(lines) > allowed:
            what = "a token tile drawn by hand" if check == "tile" else "a token row drawn by hand"
            failures.append(f"{name}: {len(lines)} × {what} (allowed {allowed}) at lines {lines} — "
                            f"build MoveTokenChoice rows into MoveTokenGrid (prd §1910)")
        elif len(lines) < allowed:
            failures.append(f"{name}: {check} allowance is {allowed} but {len(lines)} remain — lower it ({reason})")
    return failures


def files():
    for d in ("Screens", "Shell"):
        yield from sorted((ROOT / d).glob("Move*.swift"))


def self_test() -> int:
    ok = True

    def expect(label, cond):
        nonlocal ok
        print(("  ✓ " if cond else "  ✗ ") + label)
        ok = ok and cond

    tile = 'MoveDeckTile(title: s) { MoveRowMark(token: s, network: b, size: DSHomeCircleMetrics.face) }'
    expect("a hand-drawn token tile is caught", len(scan("MoveSwap.swift", tile)["tile"]) == 1)
    expect("…at the seat size too", len(scan("MoveSwap.swift", 'MoveRowMark(token: s, size: DS.Face.seat)')["tile"]) == 1)
    expect("the template itself is not a finding", scan(TEMPLATE, tile)["tile"] == [])
    expect("a row's small mark is not a tile", scan("MoveSwap.swift", 'MoveRowMark(token: s, network: b)')["tile"] == [])
    expect("a hand-drawn token row is caught", len(scan("MoveSwap.swift", 'HStack { AssetMark(name: h.symbol, size: 30) }')["row"]) == 1)
    expect("MoveRowMark's own home draws AssetMark", scan(MARK_HOME, 'AssetMark(name: token, size: size)')["row"] == [])
    expect("a commented call is not a finding", scan("MoveSwap.swift", '// AssetMark(name: x)\n/* ' + tile + ' */')
           == {"tile": [], "row": []})
    expect("an allowance is a ceiling", judge("MovePrivate.swift", {"tile": [], "row": [3, 9]}) != [])
    expect("an allowance is a floor", judge("MovePrivate.swift", {"tile": [], "row": []}) != [])
    expect("exactly the allowance passes", judge("MovePrivate.swift", {"tile": [], "row": [3]}) == [])
    print("move-token-grid-audit self-test " + ("passed" if ok else "FAILED"))
    return 0 if ok else 1


def main() -> int:
    if "--self-test" in sys.argv:
        return self_test()
    failures, seen = [], 0
    for path in files():
        seen += 1
        failures += judge(path.name, scan(path.name, path.read_text(encoding="utf-8")))
    for name in ALLOWED:
        if not any(p.name == name for p in files()):
            failures.append(f"{name}: allowed but not found — drop its allowance")
    if failures:
        print("move-token-grid-audit: FAILURES\n")
        for f in failures:
            print("  ✗ " + f)
        return 1
    print(f"move-token-grid-audit: OK — {seen} Move files, every token list is MoveTokenGrid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
