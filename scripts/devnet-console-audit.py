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
HEGOTA = ROOT / "Casberi/Casberi/Screens/HegotaSendCard.swift"
VIBENET = ROOT / "Casberi/Casberi/Screens/VibenetSendCard.swift"
FEED = ROOT / "Casberi/Casberi/Screens/FeedScreen.swift"

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

    These files DOCUMENT what they must not do by naming it — `VibenetSendCard`
    explains at length why it has no Top up half, and the console's header
    quotes `.decimalPad` in the paragraph explaining why it is gone. A guard
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
             "DS.Hit.min": 44, "DS.Face.profile": 76, "DS.Face.shelf": 56}
    if raw in scale:
        return scale[raw]
    try:
        return float(raw)
    except ValueError:
        return None


def checks(console: str, hegota: str, vibenet: str, feed: str):
    """Every finding is a sentence about what breaks, not a rule number."""
    out = []
    c_bare = strip_comments(console)
    h_bare = strip_comments(hegota)
    v_bare = strip_comments(vibenet)

    # 1. THE SUM. Two tiles and a gap have to live inside the measured room.
    pad = constant(console, "tilePadding")
    gap = constant(console, "markGap")
    mark = constant(console, "mark")
    tile_gap = constant(console, "tileGap")
    if None in (pad, gap, mark, tile_gap):
        out.append("the panel's geometry constants could not be read — the budget cannot be re-added")
    else:
        tile = 2 * pad + mark + gap + VERB_LINE
        total = 2 * tile + tile_gap
        if total > ROOM_ALLOWANCE:
            out.append(
                "the split panel needs %dpt of a %dpt room (%dpt a tile) — the second verb "
                "falls off the bottom of the screen, drawn correctly and invisible"
                % (total, ROOM_ALLOWANCE, tile))

    # 1b. THE PLAN STRIP STEPS ASIDE RATHER THAN RESERVING SPACE (prd §548).
    #     The amount screen is a plain `VStack` with NO `ScrollView`, so a
    #     reserved height pushes the commit button off the bottom — drawn
    #     correctly and invisible, the panel bug one surface over.
    #
    #     The arithmetic was tried first and refused: using §553's own measured
    #     terms the screen has NEGATIVE slack by 736pt before any strip exists,
    #     and whether that is real depends on how the sheet's top inset scales,
    #     which was measured on an 844 and is not knowable from a static check.
    #     So this asserts the MECHANISM instead of a number it cannot verify.
    if "DevnetSendPlanStrip(" in console and "ViewThatFits" not in console:
        out.append(
            "the plan strip no longer steps aside — on a screen with no ScrollView a "
            "reserved height pushes the commit button off the bottom")

    # 2. THE VERB'S RUNG, asserted APART from the sum. A panel that fits because
    #    its verbs shrank has not been fixed — the 64pt IS the design, and it is
    #    the obvious place to find room the next time something is added here.
    if console.count(".dsText(.price40)") < 2:
        out.append("a verb left the crown rung — a panel that fits by shrinking its words is not this panel")

    # 3. THE KEYPAD IS OURS. §552a swapped it for the system pad on arithmetic
    #    that was correct for a CARD and is meaningless on a sheet; what it cost
    #    was the room's whole visual language.
    if "struct DevnetKeypad" not in console:
        out.append("the custom keypad is gone — the sheet is back on iOS keyboard chrome")
    if ".decimalPad" in c_bare:
        out.append("the system keypad came back on the send sheet, which has the whole screen")

    # 4. NEITHER CARD PRESENTS. A `.sheet` attached to a view inside a `List`
    #    row resolves to the same presenting controller as the screen's own and
    #    half-opens then closes — paid for three times already.
    for name, bare in (("HegotaSendCard", h_bare), ("VibenetSendCard", v_bare)):
        if ".sheet(" in bare:
            out.append("%s presents its own sheet from inside a List row — it will half-open and close" % name)

    # 5. ONE PANEL, BOTH ROOMS. Two hand-rolled copies of a control carrying the
    #    whole budget is how a sum quietly stops being true.
    for name, bare in (("HegotaSendCard", h_bare), ("VibenetSendCard", v_bare)):
        if "DevnetSendPanel" not in bare:
            out.append("%s hand-rolls its own panel instead of using DevnetSendPanel" % name)

    # 6. THE DEMO REACHES IT, AND STOPS WHERE THE MONEY STARTS (prd §552b).
    #    A scope's whole content gated on a device credential is invisible to
    #    every demo check in this repo: they ask about seats, rows, heads and
    #    figures, and this is none of those.
    if "DemoMode.isActive" not in hegota:
        out.append("the Hegota panel cannot be reached in the demo — the room's default scope draws nothing on a tour")
    if "VibenetRoom.demoSignableAccount" not in feed:
        out.append("the vibenet panel cannot be reached in the demo")
    for verb in ("sendHegota", "sendVibenet"):
        m = re.search(r"func %s\b.*?\n    \}" % verb, feed, flags=re.S)
        if not m or "DemoMode.isActive" not in m.group(0):
            out.append("%s would sign and broadcast from a demo" % verb)

    # 7. EACH ROOM'S TOP UP DOES WHAT ITS CHAIN CAN ACTUALLY DO.
    #    Hegotá has an endpoint, so its half CLAIMS in place. vibenet has a
    #    faucet PAGE and no endpoint, so its half HANDS OFF and must say so with
    #    the outward mark — a tile that looks like it acts in place and then
    #    leaves the app is the same broken promise as one that cannot act at all.
    #    The first cut of §553 read "no endpoint in our bridge" as "no faucet on
    #    the chain" and shipped vibenet with one verb; this is that mistake made
    #    mechanical rather than remembered.
    if "claimFaucet" not in h_bare:
        out.append("Hegota's Top up no longer claims from the faucet — the half is decoration")
    if "claimFaucet" in v_bare:
        out.append("vibenet's Top up claims in place — that devnet has no claim endpoint, only a page")
    if "topUp" in v_bare and "handsOff: true" not in v_bare:
        out.append("vibenet's Top up dropped its hand-off mark — it leaves the app and no longer says so")

    # 8. THE THREE ENDINGS. The hourly refusal is EXPECTED (§525) and must be
    #    said in words rather than reported as a fault.
    if "rateLimited" not in hegota:
        out.append("the faucet's hourly refusal is no longer named — it will read as a failure (§525)")

    return out


def self_test() -> int:
    good_console = """
    static let tilePadding = DS.Space.s3
    static let markGap = DS.Space.s2
    static let mark: CGFloat = 36
    static let tileGap = DS.Space.s3
    struct DevnetKeypad { }
    Text(x).dsText(.price40)
    Text(y).dsText(.price40)
    """
    good_h = 'DemoMode.isActive\nDevnetSendPanel(\nclaimFaucet(\nrateLimited\n'
    good_v = 'DevnetSendPanel(tint: x, topUp: topUp, onSend: y)\n.init(handsOff: true)\n'
    good_f = ('VibenetRoom.demoSignableAccount()\n'
              '    func sendHegota(x: String) async -> String? {\n        DemoMode.isActive\n    }\n'
              '    func sendVibenet(x: String) async -> String? {\n        DemoMode.isActive\n    }\n')

    cases = []
    cases.append(("the shipping shape", good_console, good_h, good_v, good_f, False))

    fat = good_console.replace("DS.Space.s3\n    static let markGap", "DS.Space.s6\n    static let markGap")
    fat = fat.replace("static let mark: CGFloat = 36", "static let mark: CGFloat = DS.Hit.min")
    cases.append(("a tile fattened until the second verb falls off the screen",
                  fat, good_h, good_v, good_f, True))

    cases.append(("the verb drops below the crown rung",
                  good_console.replace("Text(y).dsText(.price40)", "Text(y).dsText(.stat24)"),
                  good_h, good_v, good_f, True))
    cases.append(("the system keypad comes back",
                  good_console.replace("struct DevnetKeypad { }", "keyboardType(.decimalPad)"),
                  good_h, good_v, good_f, True))
    cases.append(("a card presents its own sheet from a List row",
                  good_console, good_h + '.sheet(isPresented: $x)', good_v, good_f, True))
    cases.append(("a card hand-rolls its own panel",
                  good_console, good_h.replace("DevnetSendPanel(", "VStack {"), good_v, good_f, True))
    cases.append(("the console cannot be reached in the demo",
                  good_console, good_h.replace("DemoMode.isActive", ""), good_v, good_f, True))
    cases.append(("send() would broadcast from a demo",
                  good_console, good_h, good_v,
                  good_f.replace("    func sendHegota(x: String) async -> String? {\n        DemoMode.isActive\n    }",
                                 "    func sendHegota(x: String) async -> String? {\n        go()\n    }"), True))
    cases.append(("vibenet's hand-off loses its outward mark",
                  good_console, good_h,
                  'DevnetSendPanel(tint: x, topUp: topUp, onSend: z)\n.init(action: y)\n', good_f, True))
    cases.append(("vibenet tries to claim from an endpoint it does not have",
                  good_console, good_h, good_v + 'claimFaucet(\n', good_f, True))
    cases.append(("Hegota's Top up stops claiming",
                  good_console, good_h.replace("claimFaucet(", ""), good_v, good_f, True))
    cases.append(("the hourly refusal stops being named",
                  good_console, good_h.replace("rateLimited", ""), good_v, good_f, True))
    # A comment naming a banned literal must not fire — these files explain
    # themselves by naming exactly what they must not do.
    cases.append(("a comment naming a banned literal does not fire",
                  good_console + "\n    /// It is not `.decimalPad` any more.\n",
                  good_h, good_v + "\n    /// No `.sheet(` here, deliberately.\n", good_f, False))

    failed = 0
    for name, c, h, v, f, should_fire in cases:
        fired = bool(checks(c, h, v, f))
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
    for p in (CONSOLE, HEGOTA, VIBENET, FEED):
        if not p.exists():
            print("\033[31m✗ devnet-console audit: %s is missing\033[39m" % p.name)
            return 1
    found = checks(CONSOLE.read_text(), HEGOTA.read_text(), VIBENET.read_text(), FEED.read_text())
    if found:
        for f in found:
            print("\033[31m✗ %s\033[39m" % f)
        return 1
    console = CONSOLE.read_text()
    tile = (2 * constant(console, "tilePadding") + constant(console, "mark")
            + constant(console, "markGap") + VERB_LINE)
    total = 2 * tile + constant(console, "tileGap")
    dev, h, left = SMALLEST_MEASURED
    print("\033[32m✓ devnet-console audit: the split panel sums to %dpt of a %dpt room "
          "(390x844; on a %s at %dpt only %dpt is left below the first tile — measured, "
          "and the room scrolls there)\033[39m" % (total, ROOM_ALLOWANCE, dev, h, left))
    return 0


if __name__ == "__main__":
    sys.exit(main())
