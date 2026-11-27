#!/usr/bin/env python3
"""EVERY MOVE PAGE IS ONE DECK, ITS BODIES THE TEMPLATE'S (prd §1992).

User, 2026-11-26: "how do we make sure ALL of our move confirmations,
receipts, etc follow same template. it seems like they drift". They did:
each private send drew its own scroll, its own sentence under the lines and
its own fact rows, so one fix (the facts' column, the gap under the lines,
no sentence under a failure) was made three times and still missed Earn,
which had copied the whole deck by hand for its title.

The templates live in `Casberi/Casberi/Screens/MoveDeck.swift`:
`MoveReceiptDeck` (the page: title or `header`, lines, body, foot) and its
bodies `MoveDeckKeys`, `MoveDeckScroll`, `MoveDeckStatus` (which alone
decides whether the sentence shows: never while lines stand over it) and
`MoveDeckFacts`.

Checks, over every Swift file in the app (comments ignored):

  (1) A MOVE PAGE OFF THE DECK. A file that draws Move's keypad
      (`MoveKeypad(`) must compose `MoveReceiptDeck(`.
  (2) A BODY DRAWN BY HAND. In a file that composes `MoveReceiptDeck(`: no
      `ScrollView` (`MoveDeckScroll`), no `MoveFlow {` (`MoveDeckStatus`
      draws the sentence), no `MoveFactRow(` (`MoveDeckFacts`), no fade
      spelled by hand (`contentMargins(.bottom, MoveDeck.fade`).
  (3) A FOOT DRAWN BY HAND. `MoveDeckFoot(` outside the template.

Public Send (`MoveSentence.swift`) is the deck's origin and is allowed by
name, with its reason, as a CEILING and a FLOOR: more is a new page off the
template, fewer is a stale allowance to lower.

**STATED CEILINGS.** It reads text, not types: a page that builds its own
scroll through a helper in another file, or draws its failure line in its
own words, passes. `scripts/move-deck-sweep.sh` shoots every deck in its
states side by side for the eye.
"""

import re
import sys
from pathlib import Path

ROOTS = ("Casberi/Casberi", "Casberi/Shared")
TEMPLATE = "MoveDeck.swift"

# file name → {check: (allowed count, reason)}
ALLOWED = {
    "MoveSentence.swift": {
        "off-deck": (1, "public Send is the deck's origin: its sentence, rows and lists are its own page (prd §1931)"),
        "hand-foot": (2, "public Send's two feet, the deck's own and the order book's (prd §1673)"),
    },
}

BODY = [
    ("scroll", re.compile(r'\bScrollView\b'), "a scroll drawn by hand — `MoveDeckScroll`"),
    ("sentence", re.compile(r'\bMoveFlow\s*\{'), "a sentence drawn by hand — `MoveDeckStatus` draws it, never under the lines"),
    ("fact", re.compile(r'\bMoveFactRow\('), "a fact row drawn by hand — `MoveDeckFacts`"),
    ("fade", re.compile(r'contentMargins\(\.bottom,\s*MoveDeck\.fade'), "the foot's fade spelled by hand — `MoveDeckScroll`"),
]
KEYPAD = re.compile(r'\bMoveKeypad\(')
DECK = re.compile(r'\bMoveReceiptDeck\(')
FOOT = re.compile(r'\bMoveDeckFoot\(')

WHY = {
    "off-deck": "a Move page with keys that is not a `MoveReceiptDeck`",
    "hand-foot": "a deck foot drawn by hand — compose `MoveReceiptDeck`",
    **{k: why for k, _, why in BODY},
}


def code_lines(src: str) -> list[str]:
    out = []
    for line in src.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("//") or stripped.startswith("///"):
            out.append("")
            continue
        cut = line.find(" //")
        out.append(line if cut < 0 or line[:cut].count('"') % 2 else line[:cut])
    return out


def scan(src: str) -> dict[str, list[str]]:
    lines = code_lines(src)
    text = "\n".join(lines)
    hits: dict[str, list[str]] = {k: [] for k in WHY}
    is_deck = bool(DECK.search(text))
    if KEYPAD.search(text) and not is_deck:
        hits["off-deck"].append("MoveKeypad( with no MoveReceiptDeck(")
    for line in lines:
        if FOOT.search(line):
            hits["hand-foot"].append(line.strip())
        if is_deck:
            for key, rx, _ in BODY:
                if rx.search(line):
                    hits[key].append(line.strip())
    return hits


def audit(files: dict[str, str]) -> list[str]:
    findings = []
    seen = set()
    for path, src in files.items():
        name = Path(path).name
        if name == TEMPLATE:
            continue
        allowed = ALLOWED.get(name, {})
        if allowed:
            seen.add(name)
        for check, found in scan(src).items():
            limit, reason = allowed.get(check, (0, ""))
            if len(found) > limit:
                findings.append(f"{path}: {len(found)} × {WHY[check]} (allowed {limit}"
                                f"{' — ' + reason if reason else ''}): {'; '.join(found[:3])}")
            elif len(found) < limit:
                findings.append(f"{path}: {len(found)} {check}, allowance says {limit} — lower it in move-deck-audit.py")
    for name in ALLOWED:
        if name not in seen:
            findings.append(f"{name}: on the allowance list but not in the tree — remove the row")
    return findings


def self_test() -> bool:
    ok = True

    def expect(label, cond):
        nonlocal ok
        print(f"  {'✓' if cond else '✗'} {label}")
        ok = ok and cond

    base = {
        "Casberi/Casberi/Screens/MoveDeck.swift":
            "struct MoveReceiptDeck {}\nScrollView { }\nMoveFlow { s }\nMoveFactRow(name: n)\nMoveDeckFoot(back: b)\n",
        "Casberi/Casberi/Screens/MoveSentence.swift":
            "MoveKeypad(text: $t)\nMoveDeckFoot(back: a)\nMoveDeckFoot(back: b)\nScrollView { }\n",
        "Casberi/Casberi/Screens/MovePrivate.swift":
            "MoveReceiptDeck(title: t, back: b, lines: { }, content: {\n MoveDeckKeys { MoveKeypad(text: $a) }\n"
            " MoveDeckScroll { r }\n MoveDeckStatus(linesStand: x, sentence: { s }) { l }\n"
            "}, word: { w })\n// was ScrollView { MoveFlow { sentence } }\n",
        "Casberi/Casberi/Screens/Elsewhere.swift": "ScrollView { MoveFlow { s } }\n",
    }
    expect("a clean tree has no findings", audit(base) == [])

    def one(code: str, check: str, name: str = "MoveNew.swift") -> bool:
        tree = dict(base)
        tree[f"Casberi/Casberi/Screens/{name}"] = code
        f = audit(tree)
        return len(f) == 1 and name in f[0] and WHY[check].split(" — ")[0] in f[0]

    deck = "MoveReceiptDeck(title: t, back: b, lines: { }, content: {\n"
    expect("a page with keys off the deck is caught", one("VStack { MoveKeypad(text: $a) }\n", "off-deck"))
    expect("a scroll in a deck page is caught", one(deck + "ScrollView { x }\n})\n", "scroll"))
    expect("a sentence in a deck page is caught", one(deck + "MoveFlow { sentence }\n})\n", "sentence"))
    expect("a fact row in a deck page is caught", one(deck + "MoveFactRow(name: n, value: v)\n})\n", "fact"))
    expect("a hand fade in a deck page is caught",
           one(deck + "x.contentMargins(.bottom, MoveDeck.fade, for: .scrollContent)\n})\n", "fade"))
    expect("a hand foot anywhere is caught", one("MoveDeckFoot(back: b) { w }\n", "hand-foot"))
    expect("a comment is not code", audit({**base, "Casberi/Casberi/Screens/C.swift":
                                           deck + "// ScrollView { MoveFlow { s } }\nlet x = 1 // MoveFactRow(\n})\n"}) == [])

    grown = dict(base)
    grown["Casberi/Casberi/Screens/MoveSentence.swift"] += "MoveDeckFoot(back: c)\n"
    expect("an allowance that grew is a finding", any("MoveSentence" in x for x in audit(grown)))
    stale = dict(base)
    stale["Casberi/Casberi/Screens/MoveSentence.swift"] = "MoveKeypad(text: $t)\nMoveDeckFoot(back: a)\n"
    expect("a stale allowance is a finding", any("lower it" in x for x in audit(stale)))
    gone = dict(base)
    del gone["Casberi/Casberi/Screens/MoveSentence.swift"]
    expect("an allowance for a missing file is a finding", any("not in the tree" in x for x in audit(gone)))
    return ok


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    print("move-deck-audit self-test")
    if not self_test():
        print("SELF-TEST FAILED")
        return 1
    if "--self-test" in sys.argv:
        print("  self-test passed")
        return 0
    files = {}
    for r in ROOTS:
        for p in sorted((root / r).rglob("*.swift")):
            files[str(p.relative_to(root))] = p.read_text(encoding="utf-8", errors="replace")
    findings = audit(files)
    if findings:
        print(f"move-deck-audit: {len(findings)} finding(s)")
        for f in findings:
            print(f"  ✗ {f}")
        return 1
    decks = sum(1 for s in files.values() if DECK.search(s))
    print(f"move-deck-audit: clean — {decks} deck pages, every body the template's")
    return 0


if __name__ == "__main__":
    sys.exit(main())
