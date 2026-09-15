#!/usr/bin/env python3
"""THE DAY DIVIDER WEARS THE BRAND HUE, AND NOTHING ELSE DOES (prd §740).

The user asked for the feed cover's title in the brand pink. Mocked up it
fails twice — ~1.8:1 on a `deckFill` ground, and a coloured figure on the
money and clock faces reads as direction (§363) — so the hue landed on the
DAY DIVIDER instead: the one line in a feed the app writes rather than a
source, which is what makes it identity under §8 rather than decoration.

**Why a script and not a memory.** Every failure this catches renders as a
perfectly ordinary feed. A header that slid back to `DS.textPrimary` looks
like the build from two weeks ago. A new room that forgets `dated: false`
puts the brand hue on "Your wallets", which looks deliberate. A second
spelling of `#FF2D87` looks identical until somebody tunes one of them. None
of it breaks a build, trips the ramp audit, or shows up in a screen sweep,
because nothing is wrong on the screen you are looking at.

Four checks.

**(1) Both day headers take `DS.brandInk`.** `FeedScreen` draws day labels at
exactly two sites (`bundledSections` and `daySection`); both must reach
`brandInk`, and neither may fall back to `DS.textPrimary` on the label itself.

**(2) The flag exists and defaults true.** `groupedSections` and `daySection`
both declare `dated: Bool = true`. The default is what makes a new
chronological room correct without its author doing anything; losing the
default silently turns every divider back to primary.

**(3) The named-group callers still opt out.** Nine call sites group by
something other than time. The count is a FLOOR, not an equality: adding a
tenth non-dated room is fine and must not fail the build. Dropping below nine
means one stopped opting out, which puts the brand hue on a label like
"Not active".

**(4) One spelling of the hex.** `#FF2D87` lives in `DesignTokens.swift` and
nowhere else. `CasberiMark` reads `DS.brand`.

**STATED CEILINGS, because a check that oversells itself is worse than none.**

  • It cannot see COLOUR. `brandInk` resolving to the wrong pink, or the
    Increase Contrast variants being wrong, is invisible here — those are
    measured numbers in the token's own doc and a device check.
  • It cannot tell a dated label from a named one. Check 3 counts opt-outs;
    it does not know whether a given room SHOULD have opted out. A room that
    groups by repository and forgets the flag passes this audit and is wrong
    on screen.
  • It does not stop `brandInk` spreading. Check 4 pins the hex, not the
    token's call sites, so a future surface may take the ink — deliberately,
    with a ruling, which is the process this file cannot enforce.
"""

import re
import sys
from pathlib import Path

FEED = "Casberi/Casberi/Screens/FeedScreen.swift"
TOKENS = "Casberi/Casberi/Design/DesignTokens.swift"
BRAND_HEX = "FF2D87"
MIN_OPT_OUTS = 9


def strip_comments(text: str) -> str:
    """Line and block comments out, so a doc comment can never satisfy a
    shape assertion — the failure mode that makes grep-based drift guards
    useless once somebody writes a comment quoting the rule."""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return "\n".join(re.sub(r"//.*$", "", line) for line in text.splitlines())


def audit(feed: str, tokens: str, mark: str) -> list:
    out = []
    code = strip_comments(feed)

    # (1) both day headers take the brand ink
    hits = len(re.findall(r"\.foregroundStyle\((?:dated \? )?DS\.brandInk", code))
    if hits < 2:
        out.append(
            f"only {hits} of 2 day headers take DS.brandInk — a divider slid "
            "back to the primary ramp (prd §740)"
        )

    # (2) the flag exists on both builders, defaulting true
    for fn in ("groupedSections", "daySection"):
        body = re.search(
            rf"private func {fn}\(.*?\) -> some View", code, flags=re.S
        )
        if not body:
            out.append(f"{fn} not found — this audit is reading the wrong file")
        elif "dated: Bool = true" not in body.group(0):
            out.append(
                f"{fn} lost `dated: Bool = true` — without the default a new "
                "chronological room draws a primary-ramp divider (prd §740)"
            )

    # (3) the named-group callers still opt out
    opts = len(re.findall(r"dated: false", code))
    if opts < MIN_OPT_OUTS:
        out.append(
            f"{opts} `dated: false` call sites, expected at least "
            f"{MIN_OPT_OUTS} — a group named by something other than time is "
            "wearing the brand hue (prd §740)"
        )

    # (4) one spelling of the hex
    if BRAND_HEX.lower() not in tokens.lower():
        out.append(f"#{BRAND_HEX} is not in DesignTokens.swift — DS.brand is the one spelling")
    if BRAND_HEX.lower() in strip_comments(mark).lower():
        out.append(
            f"CasberiMark re-spells #{BRAND_HEX} — it reads DS.brand, so the "
            "mark and the dividers cannot drift to two pinks (prd §740)"
        )
    return out


def self_test() -> bool:
    """Every check gets a mutation that MUST fire and a healthy control that
    must not. A check that cannot demonstrate it catches anything certifies
    nothing."""
    good_feed = """
    private func groupedSections(_ groups: [(String, [Thing])],
                                 nextEventID: UUID?,
                                 dated: Bool = true,
                                 cover: UUID? = nil) -> some View {
        daySection(label, rows, dated: dated, cover: cover)
    }
    private func daySection(_ label: String, _ rows: [Thing],
                            coarse: Bool = false,
                            dated: Bool = true,
                            cover: UUID? = nil) -> some View {
        Text(label).foregroundStyle(dated ? DS.brandInk : DS.textPrimary)
    }
    func bundled() -> some View { Text(label).foregroundStyle(DS.brandInk) }
    """ + "\n".join(f"    call{i}(dated: false)" for i in range(MIN_OPT_OUTS))
    good_tokens = 'static let brand = Color.fixed("#FF2D87")'
    good_mark = "static let pink = DS.brand"

    cases = [
        ("healthy tree is clean", good_feed, good_tokens, good_mark, 0),
        (
            "a header slid back to the primary ramp",
            good_feed.replace("Text(label).foregroundStyle(DS.brandInk)",
                              "Text(label).foregroundStyle(DS.textPrimary)"),
            good_tokens, good_mark, 1,
        ),
        (
            "the dated flag lost its default",
            good_feed.replace("dated: Bool = true,\n                            cover",
                              "dated: Bool,\n                            cover"),
            good_tokens, good_mark, 1,
        ),
        (
            "a named-group caller stopped opting out",
            good_feed.replace("call0(dated: false)", "call0()"),
            good_tokens, good_mark, 1,
        ),
        (
            "the mark re-spells the hex",
            good_feed, good_tokens,
            'static let pink = Color(hex: "#FF2D87")', 1,
        ),
        (
            "a comment quoting the rule does not satisfy it",
            good_feed.replace("Text(label).foregroundStyle(DS.brandInk)",
                              "// .foregroundStyle(DS.brandInk)\n    Text(label)"),
            good_tokens, good_mark, 1,
        ),
    ]
    ok = True
    for name, feed, tokens, mark, want in cases:
        got = len(audit(feed, tokens, mark))
        verdict = "ok  " if (got >= want if want else got == 0) else "FAIL"
        if verdict == "FAIL":
            ok = False
        print(f"  {verdict} {name} ({got} finding(s))")
    return ok


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    if "--self-test" in sys.argv:
        print("day-divider-audit self-test")
        if not self_test():
            print("SELF-TEST FAILED")
            return 1
        print("  self-test passed")
        return 0

    print("day-divider-audit self-test")
    if not self_test():
        print("SELF-TEST FAILED")
        return 1

    feed = (root / FEED).read_text(encoding="utf-8", errors="replace")
    tokens = (root / TOKENS).read_text(encoding="utf-8", errors="replace")
    mark = (root / "Casberi/Casberi/Design/CasberiMark.swift").read_text(
        encoding="utf-8", errors="replace"
    )
    findings = audit(feed, tokens, mark)
    if findings:
        print(f"day-divider-audit: {len(findings)} finding(s)")
        for f in findings:
            print(f"  ✗ {f}")
        return 1
    print("day-divider-audit: clean — both dividers on DS.brandInk, "
          f"{len(re.findall(r'dated: false', strip_comments(feed)))} named groups opted out")
    return 0


if __name__ == "__main__":
    sys.exit(main())
