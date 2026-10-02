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
form, no `.decimalPad`, no keyboard toolbar and no 232pt budget any more. What
replaces them is the same idea one layout up.

Static text checks; no build, no simulator. `--self-test` first, because a check
that cannot demonstrate it catches anything certifies nothing.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONSOLE = ROOT / "Casberi/Casberi/Screens/DevnetSendConsole.swift"
# The Frames verbs' dispatcher (prd §1039): Send, Top up and Create are the
# room's last tiles, and this file is what each tile runs. It was
# `FramesSendCard.swift`, the Actions block's panel, until the merge.
CARD = ROOT / "Casberi/Casberi/Screens/FramesActs.swift"
FEED = ROOT / "Casberi/Casberi/Screens/FeedScreen.swift"
# The wallet room's half of FeedScreen (prd §718): read as one text with FEED.
FEED_WALLET = ROOT / "Casberi/Casberi/Screens/FeedScreen+WalletRoom.swift"

# **THE MEASURED ALLOWANCE, AND THE DEVICE IT IS MEASURED ON.** 390x844,
# measured off a screenshot of this build rather than estimated: the section
# strip's bottom edge sits at 526pt, so the room leaves 318 to the glass and 304
# after the card's own bottom margin.
#
# **STATED CEILING, MEASURED RATHER THAN REASONED (prd §553 amendment).** None
# of the chrome above scales with screen height, so this allowance shrinks
# one-for-one with the screen. On an iPhone SE (667pt) the same build renders
# the Send tile at y 502-634, leaving **33pt** below it — so the second tile is
# entirely under the fold and the room scrolls, which is §552's own stated
# ceiling arriving one surface later. Verified by installing on an SE simulator
# and reading the pixels, not by arithmetic.
#
# This check therefore asserts the 844 case and CANNOT speak for smaller
# hardware. That is deliberate: a budget that fails on every phone tells you
# nothing on any of them, and the fix for the small ones is a smaller chrome or
# a different surface — never a shorter verb (§552's ruling, unchanged).
ROOM_ALLOWANCE = 304
SMALLEST_MEASURED = ("iPhone SE", 667, 33)
#   one line of price40 (a 40pt face at ~1.18x), rounded UP like every
#   font-derived term — an over-stated term makes the budget stricter than the
#   glass, an under-stated one makes the budget a lie.
VERB_LINE = 48

# **THE AMOUNT SCREEN'S OWN BUDGET (prd §548).** The panel's sum above governs
# the ROOM; this governs the SHEET, and it exists because the Frames devnet
# draws a plan strip there — the only thing on that screen saying the
# transaction has parts.
#
# The screen is a plain `VStack` with NO `ScrollView`, so anything that does not
# fit pushes the commit button off the bottom, drawn correctly and invisible.
# That is the panel bug one surface over, which is what this file was written
# for.
#
# Terms measured on an 844pt phone at sheet-top 124 (§553), so 720 of sheet:
AMOUNT_SCREEN_FIXED = (
    27    # grabber + top padding
    + 44  # back row
    + 76  # face at DS.Face.profile
    + 40  # name + gap
    + 92  # figure line
    + 32  # subline row
    + 232 # keypad, 4 x 58
    + 66  # commit + gap
    + 15  # bottom padding
)
# **THE FLOOR IS THE SMALLEST PHONE THE APP DEPLOYS TO, not the one it was
# designed on.** iOS 18 still runs on a 667pt iPhone SE, where the sheet is
# ~543pt — and slack that exists at 844 is gone by 736. A strip sized against
# the big phone is one that silently disappears on the small one, which is the
# same failure as a card that overflows: it renders perfectly and is not there.
SHEET_ON_SMALLEST = 667 - 124


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


def constant(text: str, name: str):
    m = re.search(r"static let %s(?::\s*CGFloat)?\s*=\s*([A-Za-z0-9_.]+)" % re.escape(name), text)
    if not m:
        return None
    raw = m.group(1)
    scale = {"DS.Space.s1": 4, "DS.Space.s2": 8, "DS.Space.s3": 12,
             "DS.Space.s4": 15, "DS.Space.s6": 24, "DS.Space.s8": 32,
             "DS.Hit.min": 44, "DS.Face.profile": 76, "DS.Face.shelf": 46}
    if raw in scale:
        return scale[raw]
    try:
        return float(raw)
    except ValueError:
        return None


def checks(console: str, card: str, feed: str):
    """Every finding is a sentence about what breaks, not a rule number."""
    out = []
    c_bare = strip_comments(console)
    k_bare = strip_comments(card)

    # 1. **HOME'S VERBS ARE THE GRID'S LAST TILES (prd §1039, 2026-10-01).**
    #    §750 made them rows in an Actions block, after §553's loud price40
    #    tiles; the merge deleted the block and made each verb a tile in the
    #    room's own grid — the scopes' tile, never lit, last. What this asserts
    #    is that the Frames chrome hands its verbs to the grid and the tap runs
    #    `FramesActs`, and that no verb panel or verb row grows back on Home.
    for name in ("DevnetSendPanel", "DevnetVerbRow", "DevnetCreatePanel"):
        if "struct %s" % name in c_bare:
            out.append("%s is back — Home's verbs are the grid's last tiles, not a block (prd §1039)" % name)
    if "DevnetTileSurface" in c_bare:
        out.append("the loud verb tile's surface is back — a verb is a grid tile (§750, prd §1039)")
    if "verbs: FramesActs.verbs(for:" not in feed:
        out.append("the Frames chrome no longer hands its verbs to the grid — Send, Top up and Create have no tile")

    # 1b. THE PLAN STRIP STEPS ASIDE RATHER THAN RESERVING SPACE (prd §548).
    #     The amount screen is a plain `VStack` with NO `ScrollView`, so a
    #     reserved height pushes the commit button off the bottom — drawn
    #     correctly and invisible, the panel bug one surface over. Whether the
    #     slack is real depends on how the sheet's top inset scales, which is
    #     not knowable from a static check, so this asserts the MECHANISM.
    if "DevnetSendPlanStrip(" in console and "ViewThatFits" not in console:
        out.append(
            "the plan strip no longer steps aside — on a screen with no ScrollView a "
            "reserved height pushes the commit button off the bottom")

    # 3. THE KEYPAD IS OURS. §552a swapped it for the system pad on arithmetic
    #    that was correct for a CARD and is meaningless on a sheet; what it cost
    #    was the room's whole visual language.
    if "struct DevnetKeypad" not in console:
        out.append("the custom keypad is gone — the sheet is back on iOS keyboard chrome")
    if ".decimalPad" in c_bare:
        out.append("the system keypad came back on the send sheet, which has the whole screen")

    # 4. THE CARD DOES NOT PRESENT. A `.sheet` attached to a view inside a
    #    `List` row resolves to the same presenting controller as the screen's
    #    own and half-opens then closes — paid for three times already.
    if ".sheet(" in k_bare:
        out.append("FramesActs presents its own sheet — it will half-open and close inside a List row")

    # 5. ONE DISPATCHER. Each verb tile runs what its row ran; a tap handled
    #    inline in the room is how Send stops selecting the page's account.
    for verb in ("FramesActs.send(", "FramesActs.topUp(", "FramesActs.create("):
        if verb not in feed:
            out.append("the Frames room no longer routes a verb tile through %s" % verb)

    # 6. THE DEMO REACHES IT, AND STOPS WHERE THE MONEY STARTS (prd §552b).
    #    A scope's whole content gated on a device credential is invisible to
    #    every demo check in this repo: they ask about seats, rows, heads and
    #    figures, and this is none of those.
    if "DemoMode.isActive" not in card:
        out.append("the Frames panel cannot be reached in the demo — the room's default scope draws nothing on a tour")
    for verb in ("sendFrames", "sendFramesStitched"):
        m = re.search(r"func %s\b.*?\n    \}" % verb, feed, flags=re.S)
        if not m or "DemoMode.isActive" not in m.group(0):
            out.append("%s would sign and broadcast from a demo" % verb)

    # 7. THE DELETED handsOff TILE STAYS DELETED (§553b). A tile that looks
    #    like it acts in place and then leaves the app without saying so is the
    #    promise that ruling closed; Frames' Top up says it OPENS (`opens`).
    #    Read from the COMMENT-STRIPPED copies, or this fires on the paragraphs
    #    that explain the deletion BY NAMING the flag.
    for name, bare in (("DevnetSendConsole", c_bare), ("FramesActs", k_bare)):
        if "handsOff" in bare:
            out.append("%s brought back the handsOff tile — §553b deleted it" % name)

    # 8. TOP UP DOES NOT ACT IN A DEMO — the tour's account is nobody's, and a
    #    live faucet page for it, from a screen whose banner reads "none of this
    #    is yours", is the gap this catches. The half stays and says why.
    top = re.search(r"func topUp\(.*?\n    \}", card, flags=re.S)
    if not top or "DemoMode.isActive" not in top.group(0):
        out.append("Frames' Top up acts in a demo — the tour reaches something real")

    return out


def self_test() -> int:
    good_console = """
struct DevnetKeypad { }
"""
    good_k = ('enum FramesActs {\n'
              '    static func topUp(account: String?) {\n        guard !DemoMode.isActive else { return }\n    }\n')
    good_f = ('    func sendFrames(x: String) async -> String? {\n        DemoMode.isActive\n    }\n'
              '    func sendFramesStitched(x: String) async -> String? {\n        DemoMode.isActive\n    }\n'
              '    verbs: FramesActs.verbs(for: account),\n'
              '    FramesActs.send(account: a) {}\n    FramesActs.topUp(account: a) {}\n'
              '    FramesActs.create(store: s)\n')

    cases = []
    cases.append(("the shipping shape", good_console, good_k, good_f, False))
    cases.append(("the verb panel grows back on Home",
                  good_console + "struct DevnetSendPanel: View { }\n", good_k, good_f, True))
    cases.append(("a verb row grows back on Home",
                  good_console + "struct DevnetVerbRow: View { }\n", good_k, good_f, True))
    cases.append(("the loud verb tile's surface comes back",
                  good_console + "DevnetTileSurface()\n", good_k, good_f, True))
    cases.append(("the chrome stops handing over its verbs",
                  good_console, good_k, good_f.replace("verbs: FramesActs.verbs(for:", "verbs: ["), True))
    cases.append(("the system keypad comes back",
                  good_console.replace("struct DevnetKeypad { }", "keyboardType(.decimalPad)"),
                  good_k, good_f, True))
    cases.append(("the card presents its own sheet from a List row",
                  good_console, good_k + '.sheet(isPresented: $x)', good_f, True))
    cases.append(("a verb tile handled inline instead of through FramesActs",
                  good_console, good_k, good_f.replace("FramesActs.topUp(account: a) {}", "openURL(u)"), True))
    cases.append(("the console cannot be reached in the demo",
                  good_console, good_k.replace("DemoMode.isActive", "true"), good_f, True))
    cases.append(("send would broadcast from a demo",
                  good_console, good_k,
                  good_f.replace("    func sendFrames(x: String) async -> String? {\n        DemoMode.isActive\n    }",
                                 "    func sendFrames(x: String) async -> String? {\n        go()\n    }"), True))
    cases.append(("the deleted handsOff tile comes back on the card",
                  good_console, good_k + '.init(handsOff: true)\n', good_f, True))
    cases.append(("the console grows a handsOff branch again",
                  good_console + "\n    if topUp.handsOff { Image(systemName: a) }\n", good_k, good_f, True))
    cases.append(("Top up acts in a demo",
                  good_console,
                  'enum FramesActs {\n    static func topUp(account: String?) {\n        openURL(u)\n    }\nDemoMode.isActive\n',
                  good_f, True))
    # A comment naming a banned literal must not fire — these files explain
    # themselves by naming exactly what they must not do.
    cases.append(("a comment naming a banned literal does not fire",
                  good_console + "\n    /// It is not `.decimalPad` any more.\n",
                  good_k + "\n    /// No `.sheet(` here, deliberately.\n", good_f, False))
    cases.append(("a comment naming the deleted handsOff flag does not fire",
                  good_console + "\n    /// No outward-arrow branch for a `handsOff` tile any more.\n",
                  good_k + "\n    /// `DevnetSendPanel.TopUp.handsOff` was deleted by §553b.\n",
                  good_f, False))

    failed = 0
    for name, c, k, f, should_fire in cases:
        fired = bool(checks(c, k, f))
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
    for p in (CONSOLE, CARD, FEED, FEED_WALLET):
        if not p.exists():
            print("\033[31m✗ devnet-console audit: %s is missing\033[39m" % p.name)
            return 1
    feed = "".join(p.read_text() for p in [FEED] + sorted(FEED.parent.glob("FeedScreen+*.swift")))
    found = checks(CONSOLE.read_text(), CARD.read_text(), feed)
    if found:
        for f in found:
            print("\033[31m✗ %s\033[39m" % f)
        return 1
    print("\033[32m✓ devnet-console audit: Home's verbs are the grid's last tiles, "
          "the keypad is ours, the plan strip steps aside, and nothing acts in a demo "
          "(prd §1039)\033[39m")
    return 0


if __name__ == "__main__":
    sys.exit(main())
