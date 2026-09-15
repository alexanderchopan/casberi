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

    # 1. **HOME'S VERBS ARE ROWS (prd §750, 2026-09-15).** Checks 1, 2 and 2b
    #    measured two tiles against the room's 304pt allowance, pinned the verb
    #    to `price40` on a split panel and `stat24` in a menu, and kept the tint
    #    fill off a menu's peers (§553, §559). The tiles are gone: on the user's
    #    screenshot they were the loudest thing in the room and a fourth kind of
    #    container ("these all look like different apps each component"), so
    #    every verb is a `DevnetVerbRow` on the readings' insets. What this
    #    asserts now is that shape — and that neither the tile rung nor the
    #    tile's surface comes back, since a panel that quietly regrows a tile
    #    would render perfectly.
    if "struct DevnetVerbRow" not in c_bare:
        out.append("the devnet verb row is gone — Home's verbs have no shared row to draw through")
    panel = re.search(r"struct DevnetSendPanel: View \{.*?\n\}\n", c_bare, re.S)
    if not panel or "DevnetVerbRow(" not in panel.group(0):
        out.append("DevnetSendPanel no longer draws its verbs as rows — a verb is a tile again (§750)")
    # Scoped to the two verb panels: the send SHEET draws its amount at the
    # crown rung on purpose, and that is a figure, not a verb.
    for name in ("DevnetSendPanel", "DevnetCreatePanel"):
        body = re.search(r"struct %s: View \{.*?\n\}\n" % name, c_bare, re.S)
        if body and (".price40" in body.group(0) or ".stat24" in body.group(0)
                     or "DevnetTileSurface" in c_bare):
            out.append("%s draws a verb on the tile rung or the tile surface again — "
                       "Home is four containers again (§750)" % name)

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

    # 7. BOTH ROOMS' TOP UP CLAIMS IN PLACE, AND THE HAND-OFF STAYS DELETED
    #    (§553b, amended 2026-09-01 — this check used to assert the opposite).
    #    The history is the whole point, because the room was wrong about its
    #    own faucet twice in one day and BOTH times the shape was the same:
    #    absence of a thing where we happened to look, read as absence of the
    #    thing. §553 read "no endpoint in OUR bridge" as "no faucet on the
    #    chain" and shipped vibenet with one verb; its amendment read "no
    #    endpoint in the SERVED HTML" as "no endpoint at all" and shipped a
    #    Safari hand-off. §553b measured the wire — the page is Next.js and its
    #    API client ships in the chunks the page loads — and vibenet claims in
    #    place like Hegotá, so `DevnetSendPanel.TopUp.handsOff` was DELETED
    #    with the hand-off it existed for.
    #
    #    This guard was left behind by that ruling and went red on `main` for
    #    two commits, which is exactly the failure the CI floor exists to make
    #    visible. Amended rather than deleted: a red guard after a refactor is
    #    a ruling to amend. So the rule inverts — vibenet must CLAIM, and the
    #    deleted flag must never come back, which is the drift that would
    #    quietly restore a tile that leaves the app without saying so.
    if "claimFaucet" not in h_bare:
        out.append("Hegota's Top up no longer claims from the faucet — the half is decoration")
    if "claimFaucet" not in v_bare:
        out.append("vibenet's Top up no longer claims from the faucet — §553b measured that endpoint, "
                   "and a half that only opens a page is the hand-off that ruling deleted")
    # Read from the COMMENT-STRIPPED copies, or this fires on the paragraphs in
    # both files that explain the deletion BY NAMING the flag — the Obsidian /
    # Cursor lesson, which this file already pays elsewhere.
    for name, bare in (("DevnetSendConsole", c_bare), ("VibenetSendCard", v_bare)):
        if "handsOff" in bare:
            out.append("%s brought back the handsOff tile — §553b deleted it, and a tile that looks "
                       "like it acts in place and then leaves the app is the promise that ruling closed" % name)

    # 8. NEITHER TOP UP ACTS IN A DEMO. Hegotá's claim and vibenet's hand-off
    #    are different verbs and they must answer a demo tap the SAME way — one
    #    refusing with a sentence while the other opened a live faucet page in
    #    Safari, from a screen whose banner reads "none of this is yours", is
    #    the gap this catches. Demo parity is about the tour being the same
    #    SHAPE as the room, so the half stays and says why rather than
    #    vanishing.
    for name, bare in (("Hegota", h_bare), ("vibenet", v_bare)):
        if "topUp" not in bare and name == "vibenet":
            continue
        if "DemoMode.isActive" not in bare:
            out.append("%s's Top up acts in a demo — the tour reaches something real" % name)

    # 8b. **THE FAUCET LIVES ON HOME, IN ALL THREE ROOMS (prd §594, 2026-09-04).**
    #     Frames deleted its own faucet door on 2026-09-01 ("i don't think we
    #     need to say get test eth here b/c it is on the home screen") and
    #     Hegotá kept drawing one in `HegotaKeySheet` for three more days — the
    #     same verb in two places, in the room next door, with nothing checking.
    #     A ruling that lives in one room's comments is a ruling the next room
    #     misses, so it is mechanical now.
    try:
        keysheet = open("Casberi/Casberi/Screens/HegotaKeySheet.swift").read()
    except OSError:
        keysheet = ""
    if "HegotaSend.claimFaucet" in strip_comments(keysheet):
        out.append(
            "Hegotá's key sheet claims from the faucet again — the room's Home scope has "
            "carried a Top up tile since §553, and two controls for one consequence teach "
            "that neither is the real one (§190, §83)")

    # 9. THE THREE ENDINGS. The hourly refusal is EXPECTED (§525) and must be
    #    said in words rather than reported as a fault.
    if "rateLimited" not in hegota:
        out.append("the faucet's hourly refusal is no longer named — it will read as a failure (§525)")

    return out


def self_test() -> int:
    good_console = """
struct DevnetSendPanel: View {
    var body: some View {
        DevnetVerbRow(title: t, glyph: g, tint: c, act: a)
    }
}
struct DevnetVerbRow: View { }
struct DevnetKeypad { }
"""
    good_h = 'DemoMode.isActive\nDevnetSendPanel(\nclaimFaucet(\nrateLimited\n'
    # §553b: vibenet claims in place like Hegotá, and carries no handsOff flag.
    good_v = ('DevnetSendPanel(tint: x, topUp: topUp, onSend: y)\n'
              'claimFaucet(\nif DemoMode.isActive { return .init(note: n) }\n')
    good_f = ('VibenetRoom.demoSignableAccount()\n'
              '    func sendHegota(x: String) async -> String? {\n        DemoMode.isActive\n    }\n'
              '    func sendVibenet(x: String) async -> String? {\n        DemoMode.isActive\n    }\n')

    cases = []
    cases.append(("the shipping shape", good_console, good_h, good_v, good_f, False))

    cases.append(("a verb goes back to the tile rung",
                  good_console.replace("DevnetVerbRow(title: t, glyph: g, tint: c, act: a)", "Text(x).dsText(.price40)\n        DevnetVerbRow(title: t, glyph: g, tint: c, act: a)"),
                  good_h, good_v, good_f, True))
    cases.append(("the panel stops drawing rows",
                  good_console.replace("DevnetVerbRow(title: t, glyph: g, tint: c, act: a)", "VStack { }"),
                  good_h, good_v, good_f, True))
    cases.append(("the shared verb row is deleted",
                  good_console.replace("struct DevnetVerbRow: View { }", ""),
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
    # §553b's own three mutations. The first is the regression that ruling
    # exists to prevent: a vibenet half that stops claiming is back to opening
    # a page, which is the hand-off §553b deleted.
    cases.append(("vibenet's Top up stops claiming",
                  good_console, good_h, good_v.replace("claimFaucet(", ""), good_f, True))
    cases.append(("the deleted handsOff tile comes back on the card",
                  good_console, good_h, good_v + '.init(handsOff: true)\n', good_f, True))
    cases.append(("the console grows a handsOff branch again",
                  good_console + "\n    if topUp.handsOff { Image(systemName: a) }\n",
                  good_h, good_v, good_f, True))
    cases.append(("Hegota's Top up stops claiming",
                  good_console, good_h.replace("claimFaucet(", ""), good_v, good_f, True))
    cases.append(("vibenet's Top up acts in a demo",
                  good_console, good_h,
                  'DevnetSendPanel(tint: x, topUp: topUp, onSend: y)\nclaimFaucet(\nopenURL(u)\n',
                  good_f, True))
    cases.append(("the hourly refusal stops being named",
                  good_console, good_h.replace("rateLimited", ""), good_v, good_f, True))
    # A comment naming a banned literal must not fire — these files explain
    # themselves by naming exactly what they must not do.
    cases.append(("a comment naming a banned literal does not fire",
                  good_console + "\n    /// It is not `.decimalPad` any more.\n",
                  good_h, good_v + "\n    /// No `.sheet(` here, deliberately.\n", good_f, False))
    # The §553b half of that rule, and NOT decoration: both real files explain
    # the deletion by naming `handsOff`, so a raw-source check would fire on
    # the prose describing the very thing it is enforcing.
    cases.append(("a comment naming the deleted handsOff flag does not fire",
                  good_console + "\n    /// No outward-arrow branch for a `handsOff` tile any more.\n",
                  good_h,
                  good_v + "\n    /// `DevnetSendPanel.TopUp.handsOff` was deleted by §553b.\n",
                  good_f, False))

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
    for p in (CONSOLE, HEGOTA, VIBENET, FEED, FEED_WALLET):
        if not p.exists():
            print("\033[31m✗ devnet-console audit: %s is missing\033[39m" % p.name)
            return 1
    found = checks(CONSOLE.read_text(), HEGOTA.read_text(), VIBENET.read_text(), FEED.read_text() + FEED_WALLET.read_text())
    if found:
        for f in found:
            print("\033[31m✗ %s\033[39m" % f)
        return 1
    print("\033[32m✓ devnet-console audit: Home's verbs are rows on the readings' insets, "
          "the keypad is ours, the plan strip steps aside, and the faucet claims in place "
          "(prd §750)\033[39m")
    return 0


if __name__ == "__main__":
    sys.exit(main())
