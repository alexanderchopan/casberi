#!/usr/bin/env python3
"""The devnet Home surface — a split panel and a sheet (prd §553, 2026-09-01).

**WHY THIS IS A SCRIPT AND NOT A NOTE.** The failure is invisible. A card that
overflows its room renders perfectly: every element drawn correctly, in the
right order, and the ones past the fold simply continue below it. No warning, no
clipping, no log line — the build is green, every other audit is green, and the
screen sweep photographs a Send button that is off the screen and certifies it.
That is exactly what §552 shipped, and its replacement overflowed the same way
on its FIRST run of this build (174pt a tile against a 146pt allowance, which
put "Top up" off the bottom).

§552/§552a's checks are gone with the console they guarded — there is no inline
form, no `.decimalPad`, no keyboard toolbar and no 232pt budget any more. The
panel and amount-screen budgets that replaced them went with Hegotá Frames
(prd §1206), whose verbs and plan strip they measured; what stays is the send
sheet's grammar, which Logos uses (prd §1084).

Static text checks; no build, no simulator. `--self-test` first, because a check
that cannot demonstrate it catches anything certifies nothing.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONSOLE = ROOT / "Casberi/Casberi/Screens/DevnetSendConsole.swift"
FEED = ROOT / "Casberi/Casberi/Screens/FeedScreen.swift"

# The sends the sheet runs (prd §1084). Hegotá Frames' two (`sendFrames`,
# `sendFramesStitched`) and its verb dispatcher `FramesActs` went with the seat
# (prd §1206), and with them the panel and amount-screen budgets this file
# summed: the plan strip they measured was Frames' alone. What is left is the
# sheet's own grammar and the one money rule.
SENDS = ("sendLogos",)


def strip_comments(text: str) -> str:
    """Negative checks read a COMMENT-STRIPPED copy.

    These files DOCUMENT what they must not do by naming it — the console's
    header quotes `.decimalPad` in the paragraph explaining why it is gone. A guard
    grepping raw source fires on the prose explaining the rule. (The
    Obsidian/Cursor lesson, ninth instance.)
    """
    out = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    out = re.sub(r"^\s*///.*$", "", out, flags=re.M)
    out = re.sub(r"^\s*//.*$", "", out, flags=re.M)
    out = re.sub(r'"[^"\n]*"', '""', out)
    return out


def checks(console: str, feed: str):
    """Every finding is a sentence about what breaks, not a rule number."""
    out = []
    c_bare = strip_comments(console)

    # 1. **THE VERBS ARE ROWS, AND NOT ON HOME (prd §1108, 2026-10-04).**
    #    §750 made them rows in an Actions block, after §553's loud price40
    #    tiles; the merge (§1039) made each a tile in the room's grid, and
    #    §1108 made them rows. No verb block grows back in the sheet's file.
    for name in ("DevnetSendPanel", "DevnetVerbRow", "DevnetCreatePanel"):
        if "struct %s" % name in c_bare:
            out.append("%s is back — the verbs are Holdings' rows and the menu's, not a block (prd §1108)" % name)
    if "DevnetTileSurface" in c_bare:
        out.append("the loud verb tile's surface is back — a verb is a row (§750, prd §1108)")

    # 2. THE KEYPAD IS OURS. §552a swapped it for the system pad on arithmetic
    #    that was correct for a CARD and is meaningless on a sheet; what it cost
    #    was the room's whole visual language.
    if "struct DevnetKeypad" not in console:
        out.append("the custom keypad is gone — the sheet is back on iOS keyboard chrome")
    if ".decimalPad" in c_bare:
        out.append("the system keypad came back on the send sheet, which has the whole screen")

    # 3. THE SHEET DOES NOT PRESENT. A `.sheet` attached to a view inside a
    #    `List` row resolves to the same presenting controller as the screen's
    #    own and half-opens then closes — paid for three times already.
    if ".sheet(" in c_bare:
        out.append("the send sheet presents a sheet of its own — it will half-open and close")

    # 4. THE DEMO STOPS WHERE THE MONEY STARTS (prd §552b). Every send the sheet
    #    runs refuses in a demo: the tour's account is nobody's.
    for verb in SENDS:
        m = re.search(r"func %s\b.*?\n    \}" % verb, feed, flags=re.S)
        if not m or "DemoMode.isActive" not in m.group(0):
            out.append("%s would sign and broadcast from a demo" % verb)

    # 5. THE DELETED handsOff TILE STAYS DELETED (§553b). Read from the
    #    COMMENT-STRIPPED copy, or this fires on prose naming the flag.
    if "handsOff" in c_bare:
        out.append("DevnetSendConsole brought back the handsOff tile — §553b deleted it")

    return out


def self_test() -> int:
    good_console = """
struct DevnetKeypad { }
"""
    good_f = ('    func sendLogos(to: String, amount: String) async -> String? {\n'
              '        guard !DemoMode.isActive else { return nil }\n    }\n')

    cases = []
    cases.append(("the shipping shape", good_console, good_f, False))
    cases.append(("the verb panel grows back on Home",
                  good_console + "struct DevnetSendPanel: View { }\n", good_f, True))
    cases.append(("a verb row grows back on Home",
                  good_console + "struct DevnetVerbRow: View { }\n", good_f, True))
    cases.append(("the loud verb tile's surface comes back",
                  good_console + "DevnetTileSurface()\n", good_f, True))
    cases.append(("the system keypad comes back",
                  good_console.replace("struct DevnetKeypad { }", "keyboardType(.decimalPad)"),
                  good_f, True))
    cases.append(("the sheet presents its own sheet",
                  good_console + '.sheet(isPresented: $x)\n', good_f, True))
    cases.append(("send would broadcast from a demo",
                  good_console, good_f.replace("guard !DemoMode.isActive else { return nil }", "go()"), True))
    cases.append(("the send is gone and nothing says so",
                  good_console, "", True))
    cases.append(("the console grows a handsOff branch again",
                  good_console + "\n    if topUp.handsOff { Image(systemName: a) }\n", good_f, True))
    # A comment naming a banned literal must not fire — these files explain
    # themselves by naming exactly what they must not do.
    cases.append(("a comment naming a banned literal does not fire",
                  good_console + "\n    /// It is not `.decimalPad` any more, and no `.sheet(` here.\n"
                  + "    /// `DevnetSendPanel.TopUp.handsOff` was deleted by §553b.\n", good_f, False))

    failed = 0
    for name, c, f, should_fire in cases:
        fired = bool(checks(c, f))
        ok = fired == should_fire
        print(("  \033[32m✓\033[39m " if ok else "  \033[31m✗\033[39m ") + name)
        if not ok:
            failed += 1
    return failed


def main() -> int:
    if "--self-test" in sys.argv:
        return 1 if self_test() else 0
    if self_test():
        print("\033[31m✗ devnet-console audit: its own self-test failed\033[39m")
        return 1
    for p in (CONSOLE, FEED):
        if not p.exists():
            print("\033[31m✗ devnet-console audit: %s is missing\033[39m" % p.name)
            return 1
    feed = "".join(p.read_text() for p in [FEED] + sorted(FEED.parent.glob("FeedScreen+*.swift")))
    found = checks(CONSOLE.read_text(), feed)
    if found:
        for f in found:
            print("\033[31m✗ %s\033[39m" % f)
        return 1
    print("\033[32m✓ devnet-console audit: the verbs are rows, the keypad is ours, "
          "and nothing sends in a demo (prd §1108, §1206)\033[39m")
    return 0


if __name__ == "__main__":
    sys.exit(main())
