#!/usr/bin/env python3
"""THE HERO TILE IS THE ONLY TINTED BLOCK ON ITS SCREEN (prd §563).

`DSActVerb` (prd §559) reads loud for exactly one reason, and it is not the
40pt verb: it is that the fill is the ONLY saturated block on the surface. The
devnet Home panel that set the treatment says so in its own doc — one half is
the venue's colour and one half is `dsWidgetSurface`, and "the colour is the
only thing saying which one the room is for". Add a second tinted tile and the
type stays exactly as big while the surface stops saying anything.

**Mechanical rather than remembered, for this repo's standing reason.** The
rule is invisible to every other check here: two hero tiles compile, render
perfectly, pass the design-motion audit, pass the ramp audit and look — on the
screen that has them — deliberate. Nothing degrades except the thing the
treatment was for, and it degrades on the OTHER screens, which is where nobody
is looking when the second tile is added. §561's finding, one design system
over: "we keep drifting", and the answer here is a script, never a reminder.

Two checks.

**(1) One hero tile per file.** At most one `DSActVerb(` call site. MEASURED
before it was written: all five callers on a healthy tree have exactly one
each, so this fires zero times today and cannot cry wolf. A file wanting two
mutually exclusive tiles (an empty room's two states, say) factors them to one
call site, which is the better code anyway and is what `FeedScreen` does.

**(2) The component is the only hero verb.** A `price40`/`price48` set INSIDE
a `Button` is a hand-rolled tile, and a hand-rolled one silently loses §559's
honesty contract: `.disabled` dims a LABEL, not a fill, so an inert hand-rolled
tile reads live. Measured over the real tree this matches exactly one line —
`DSActVerb`'s own, which is exempt.

"Inside" is BRACE DEPTH, not proximity, and the first cut of this check got
that wrong in the direction that matters. A twelve-line window flagged a card
that draws a button and then a hero FIGURE below it — a false positive on the
commonest layout in the app, and the lint that cries wolf gets turned off
within a week. Its own self-test caught it before it ran once.

**STATED CEILINGS, because a check that oversells itself is worse than none.**

  * The unit is the FILE, not the screen. A file holding two screens could
    legitimately want two tiles, and a screen split across two files could hide
    two. File scope is the same proxy `keychain-audit.py` uses and for the same
    reason: pairing a call with the view it renders into means parsing Swift.
  * Check 2 counts braces on comment- and string-stripped source. It is not a
    Swift parser: a `Button` reached through a helper that returns its label
    from another function is invisible to it, and so is a tile assembled by a
    `ViewModifier`. It catches the shape somebody actually writes when they
    copy a tile instead of importing one.
  * It says nothing about OTHER tinted things. A tint-dim capsule, a chip, an
    accent word or a filled disc are not hero tiles and are not counted; the
    rule is about the 40pt filled block, not about the colour budget at large.

`--self-test` runs first and is required, per this repo's rule that a check
which cannot demonstrate it catches anything certifies nothing.
"""
import re
import sys
import pathlib

SOURCES = ["Casberi/Casberi", "Casberi/CasberiWidgets", "Casberi/Shared"]

# The component itself, and the panel whose PAIR is the identity — its ink half
# is a second tile by design (prd §553), and it is the surface every other
# caller is imitating.
KNOWN_PAIR = {
    "DSActVerb.swift",        # the component; it defines the tile
    "DevnetSendConsole.swift",  # §553's split panel: one tint half, one ink half
    # The wait's console (2026-09-02): Stop and Edit are that same split panel
    # one room over — Stop takes `DS.inkGround`, so exactly ONE block on the
    # surface is saturated and the budget this audit protects is kept. They
    # are a designed pair for the reason §553's are: two answers to one
    # moment, and folding them to a single call site would mean a tile whose
    # verb changes under the thumb.
    "Composer.swift",
}

CALL = re.compile(r"\bDSActVerb\s*\(")
BUTTON = re.compile(r"\bButton\s*[({]")
HERO_TYPE = re.compile(r"dsText\(\.(price40|price48)\)")
STRING = re.compile(r'"(?:\\.|[^"\\])*"')


def strip_comments(text):
    """Comments DOCUMENT this rule by naming the thing it forbids — this file's
    own callers explain why they have one tile — so a raw grep scores prose as
    code. The Obsidian/Cursor lesson, which this repo has now paid for nine
    times.

    **A CHARACTER SCANNER, and the naive line version is why.** The first cut
    handled `/*` before `//`, so a LINE comment containing a path glob —
    `FeedScreen.swift` has ``// `scripts/output/*/perf.txt` `` at line 10161 —
    opened a block comment that never closed and blanked the remaining 7,000
    lines. The audit then reported that file clean because it could no longer
    see a single call site in it, which is the exact false green this repo
    writes mutation proofs to catch: it was caught by mutating the real tree,
    not by reading. Line count is preserved so findings still cite real lines.

    Ceilings: nested block comments (legal in Swift, vanishingly rare here) end
    at the first close marker, and a Swift multi-line string delimiter is
    scanned as three ordinary quotes. Neither shape appears in the files this
    audit reads.
    """
    out = []
    i = 0
    n = len(text)
    in_block = False
    in_string = False
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if in_block:
            if c == "*" and nxt == "/":
                in_block = False
                i += 2
                continue
            out.append("\n" if c == "\n" else " ")
            i += 1
            continue
        if in_string:
            out.append(c)
            if c == "\\" and nxt:
                out.append(nxt)
                i += 2
                continue
            if c == '"' or c == "\n":
                in_string = False
            i += 1
            continue
        if c == '"':
            in_string = True
            out.append(c)
            i += 1
            continue
        if c == "/" and nxt == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if c == "/" and nxt == "*":
            in_block = True
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def audit_text(name, text):
    """Findings for one file's source. Returns a list of strings."""
    findings = []
    lines = strip_comments(text).split("\n")
    if name in KNOWN_PAIR:
        return findings

    sites = [i + 1 for i, l in enumerate(lines) if CALL.search(l)]
    if len(sites) > 1:
        where = ", ".join(f"line {n}" for n in sites)
        findings.append(
            f"{name}: {len(sites)} DSActVerb tiles ({where}). "
            "A hero tile is loud because it is the only tinted block on its "
            "screen; a second one costs the first its meaning. Factor mutually "
            "exclusive tiles to one call site, or add the file to KNOWN_PAIR "
            "with the reason its two tiles are a designed pair."
        )

    for i, line in enumerate(lines):
        m = BUTTON.search(line)
        if not m:
            continue
        # Walk forward at the Button's own brace depth. A `Button { … } label:
        # { … }` that opens and closes on one line never reaches depth > 0 past
        # that line, so a hero figure drawn BELOW it is correctly not its.
        depth = 0
        started = False
        for j in range(i, len(lines)):
            body = STRING.sub('""', lines[j])
            if j == i:
                body = body[m.start():]
            if started and HERO_TYPE.search(lines[j]) and depth > 0:
                findings.append(
                    f"{name}: line {j + 1} sets a hero rung inside the Button "
                    f"opened on line {i + 1}. Use DSActVerb — a hand-rolled "
                    "tile paints its own background, and `.disabled` dims a "
                    "label rather than a fill, so an inert one reads live "
                    "(prd §83)."
                )
                break
            for ch in body:
                if ch == "{":
                    depth += 1
                    started = True
                elif ch == "}":
                    depth -= 1
            if started and depth <= 0:
                break
    return findings


CLEAN = """
struct A: View {
    var body: some View {
        DSActVerb(title: "Send") { go() }
    }
}
"""

TWO_TILES = """
struct A: View {
    var body: some View {
        VStack {
            DSActVerb(title: "Send") { go() }
            DSActVerb(title: "Top up") { top() }
        }
    }
}
"""

COMMENTED = """
struct A: View {
    // Two of these would be wrong: DSActVerb(title: "x") twice on one screen
    /* DSActVerb(title: "y") */
    var body: some View { DSActVerb(title: "Send") { go() } }
}
"""

HAND_ROLLED = """
struct A: View {
    var body: some View {
        Button {
            go()
        } label: {
            Text("Send").dsText(.price40)
        }
    }
}
"""

FAR_AWAY = """
struct A: View {
    var body: some View {
        Button { go() } label: { Text("x") }
        Text(total).dsText(.price40)
    }
}
"""


NESTED = """
struct A: View {
    var body: some View {
        Button {
            go()
        } label: {
            VStack {
                HStack {
                    Text("Send").dsText(.price48)
                }
            }
        }
    }
}
"""


# The exact shape that blanked 7,000 lines of FeedScreen.swift: a path glob
# inside a LINE comment, which a naive stripper reads as an open block.
GLOB_IN_LINE_COMMENT = """
struct A: View {
    // see `scripts/output/*/perf.txt` for why
    var body: some View {
        VStack {
            DSActVerb(title: "Send") { go() }
            DSActVerb(title: "Top up") { top() }
        }
    }
}
"""


def self_test():
    cases = [
        ("passes a file with one tile", "A.swift", CLEAN, 0),
        ("flags  two tiles in one file", "A.swift", TWO_TILES, 1),
        ("passes two tiles in a KNOWN_PAIR file",
         "DevnetSendConsole.swift", TWO_TILES, 0),
        ("passes a tile named only in comments", "A.swift", COMMENTED, 0),
        ("flags  a hand-rolled hero verb in a Button", "A.swift", HAND_ROLLED, 1),
        ("passes the component's own hand-rolled tile",
         "DSActVerb.swift", HAND_ROLLED, 0),
        ("passes a hero figure BELOW a closed Button", "A.swift", FAR_AWAY, 0),
        ("flags  a hero rung nested deep inside a Button", "A.swift", NESTED, 1),
        ("flags  two tiles below a glob in a line comment",
         "A.swift", GLOB_IN_LINE_COMMENT, 1),
        ("passes an empty file", "A.swift", "", 0),
    ]
    ok = True
    for label, name, text, want in cases:
        got = len(audit_text(name, text))
        mark = "ok  " if got == want else "FAIL"
        if got != want:
            ok = False
        print(f"  {mark} {label} (expected {want}, got {got})")
    # The count check must be able to fail on a file that also passes check 2.
    got = len(audit_text("A.swift", TWO_TILES + FAR_AWAY))
    if got != 1:
        print(f"  FAIL two tiles alongside a legitimate hero figure (got {got})")
        ok = False
    else:
        print("  ok   two tiles alongside a legitimate hero figure")
    return ok


def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    if "--self-test" in sys.argv:
        print("hero-tint-audit self-test")
        if not self_test():
            print("SELF-TEST FAILED")
            return 1
        print("  self-test passed")
        if len(sys.argv) > 1 and sys.argv[1] == "--self-test" and len(sys.argv) == 2:
            pass

    findings = []
    scanned = 0
    for src in SOURCES:
        base = root / src
        if not base.exists():
            continue
        for path in sorted(base.rglob("*.swift")):
            scanned += 1
            text = path.read_text(encoding="utf-8", errors="replace")
            findings.extend(audit_text(path.name, text))

    if findings:
        print(f"hero-tint-audit: {len(findings)} finding(s) in {scanned} files")
        for f in findings:
            print(f"  ✗ {f}")
        return 1
    print(f"hero-tint-audit: clean ({scanned} files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
