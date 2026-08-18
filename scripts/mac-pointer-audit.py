#!/usr/bin/env python3
"""The Mac pointer vocabulary, made mechanical (2026-08-17).

`Design/MacDelight.swift` defines a CLOSED set of cursor answers — one per
surface class, and a surface wears exactly one:

    row      → dsHover()                 the system highlight, nothing more
    card     → dsHover() + macHoverLift()
    media    → dsHover() + macHoverBloom()
    icon     → dsTooltip("…")
    external → macLinkCursor()

That vocabulary is worth writing down and worthless unless something keeps it.
The three failures below are each invisible from a build and from a screenshot,
which is the bar every check in this repo has to clear:

**A — a doubled motion treatment.** Lift and bloom animate on the same trigger,
so an element wearing both scales AND rises against a doubled shadow. It
compiles, it runs, and it reads as a rendering bug rather than as emphasis —
and it arrives by the most ordinary route there is, someone adding the "media"
treatment to a card that already lifts.

**B — a tooltip that shouts or trails a full stop.** `dsTooltip` is the Mac's
only channel for naming an unlabelled control, and it lands in system chrome
where the design law still holds: sentence case, no ALL-CAPS eyebrows
(build-brief §8). A tooltip reading "OPEN IN PHOTOS." breaks two rules in the
one place no screenshot sweep will ever photograph, because tooltips only exist
under a cursor that a headless run does not have.

**C — the vocabulary bypassed.** `.onHover`, `.pointerStyle(` and `.help(` are
the raw primitives the five modifiers above are built from, and every one of
them lives in `Design/` today. A raw `.help()` outside that folder is the
specific bug `dsTooltip` was written to prevent — on iOS it doubles up the
VoiceOver hint, so the Mac's tooltip silently degrades the phone's
accessibility. A raw `.onHover` outside `Design/` skips the Reduce Motion gate
both modifiers apply, which is the accessibility law failing on a machine where
hover fires constantly.

Scoped to the app target's own sources. Everything is read from a
COMMENT-STRIPPED copy: three of these files DOCUMENT the primitives by naming
them ("rather than a bare `.help()`"), so a guard grepping raw source fires on
the prose explaining it — the lesson `obsidian-selftest` and
`cursor-selftest` each paid for once.

**What it deliberately does NOT check**, so it can't become a lint that cries
wolf: whether a surface wears the RIGHT treatment (a card that should bloom is
a judgement about what the thing is, and nothing static can make it); whether
every icon-only control has a tooltip (SwiftUI label position is not reliably
greppable, and a sweep that guesses would flag every decorative glyph in the
app); and whether a tooltip's words are TRUE, which is the same class of claim
`setup-copy-audit` refuses for the same reason.

Usage:  mac-pointer-audit.py [--self-test]
"""

import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = [ROOT / "Casberi" / "Casberi", ROOT / "Casberi" / "Shared"]

# The one folder allowed to touch the raw primitives — it is where the
# vocabulary is DEFINED. `TokenChartView`'s `onContinuousHover` (the price
# chart's scrub) sits here too and is covered by the same allowance.
VOCAB_HOME = "Design"

# Raw primitives that must be reached through the vocabulary. `onContinuousHover`
# is deliberately absent: it is a different API with a different purpose (a
# continuous position, not an enter/exit), and the one use of it is a figure
# readout in Design/ where it would be allowed anyway.
RAW_PRIMITIVES = [
    (r"\.onHover\b", ".onHover", "macHoverLift()/macHoverBloom() — they carry the Reduce Motion gate"),
    # `pointerStyle` is macOS/visionOS only — absent from the iOS SwiftUI
    # interface Catalyst compiles against, so this one does not fail a build
    # anywhere it could plausibly be written. The guard is kept because the
    # error it produces ("cannot find 'pointerStyle' in scope") reads as a
    # missing import rather than as a platform fact, and the finding here says
    # which it is. See `Design/MacDelight.swift` for the measurement.
    (r"\.pointerStyle\(", ".pointerStyle(",
     "nothing — it is macOS-only and unreachable from Mac Catalyst"),
    (r"\.help\(", ".help(", "dsTooltip() — a raw .help doubles the VoiceOver hint on iOS"),
]

TOOLTIP = re.compile(r'dsTooltip\(\s*"([^"]*)"')
LIFT, BLOOM = "macHoverLift()", "macHoverBloom()"


def strip_comments(text: str) -> str:
    """Blank out // and /* */ comments, keeping line numbers intact.

    String literals are respected, so a tooltip reading "https://…" is not
    mistaken for the start of a comment — which would blank the rest of a real
    line and hide a genuine finding underneath it.
    """
    out, i, n = [], 0, len(text)
    in_str = in_line = in_block = False
    while i < n:
        c, nxt = text[i], text[i + 1] if i + 1 < n else ""
        if in_line:
            if c == "\n":
                in_line = False
                out.append(c)
            else:
                out.append(" ")
        elif in_block:
            if c == "*" and nxt == "/":
                in_block = False
                out.append("  ")
                i += 2
                continue
            out.append("\n" if c == "\n" else " ")
        elif in_str:
            out.append(c)
            if c == "\\":
                if i + 1 < n:
                    out.append(text[i + 1])
                    i += 2
                    continue
            elif c == '"':
                in_str = False
        else:
            if c == "/" and nxt == "/":
                in_line = True
                out.append("  ")
                i += 2
                continue
            if c == "/" and nxt == "*":
                in_block = True
                out.append("  ")
                i += 2
                continue
            if c == '"':
                in_str = True
            out.append(c)
        i += 1
    return "".join(out)


def chain_bounds(lines, i):
    """The modifier chain containing line `i`.

    A SwiftUI chain is a run of lines whose continuations begin with `.`, so
    the chain starts at the last line that does NOT, and ends at the last
    continuation after it. Checking a fixed ±N window instead would join two
    adjacent chains and report a lift and a bloom on two different views as one
    doubled element.
    """
    start = i
    while start > 0 and lines[start].lstrip().startswith("."):
        start -= 1
    end = i
    while end + 1 < len(lines) and lines[end + 1].lstrip().startswith("."):
        end += 1
    return start, end


def swift_files(roots):
    for root in roots:
        if root.exists():
            yield from sorted(root.rglob("*.swift"))


def audit(roots):
    findings = []
    for path in swift_files(roots):
        raw = path.read_text(encoding="utf-8", errors="replace")
        code = strip_comments(raw)
        lines = code.splitlines()
        # Repo-relative where possible; self-test fixtures live in a temp dir
        # outside ROOT, and a harness that crashes on its own inputs is a
        # check that can never prove it catches anything.
        try:
            rel = path.relative_to(ROOT)
        except ValueError:
            rel = path.name

        # A — one motion treatment per element.
        for i, line in enumerate(lines):
            if LIFT not in line:
                continue
            lo, hi = chain_bounds(lines, i)
            if any(BLOOM in lines[j] for j in range(lo, hi + 1)):
                findings.append(
                    f"{rel}:{i + 1} wears BOTH {LIFT} and {BLOOM} on one element "
                    f"— pick the surface class (card lifts, media blooms)"
                )

        # B — tooltip copy obeys the design law.
        for i, line in enumerate(lines):
            for text in TOOLTIP.findall(line):
                if not text.strip():
                    findings.append(f"{rel}:{i + 1} empty dsTooltip — an icon with a blank name")
                    continue
                letters = [c for c in text if c.isalpha()]
                if len(letters) >= 2 and text == text.upper():
                    findings.append(
                        f'{rel}:{i + 1} ALL-CAPS dsTooltip "{text}" — sentence case (build-brief §8)'
                    )
                if text.rstrip().endswith("."):
                    findings.append(
                        f'{rel}:{i + 1} dsTooltip "{text}" ends with a full stop — it is a name, not a sentence'
                    )

        # C — the vocabulary is not bypassed.
        if path.parent.name == VOCAB_HOME:
            continue
        for pattern, shown, instead in RAW_PRIMITIVES:
            for i, line in enumerate(lines):
                if re.search(pattern, line):
                    findings.append(f"{rel}:{i + 1} raw {shown} outside Design/ — use {instead}")
    return findings


# ── Self-test ──────────────────────────────────────────────────────────────
# A check that cannot demonstrate it catches anything certifies nothing. Each
# fixture is one of the three real shapes, plus the two false positives this
# audit's own first cut would have produced (a primitive named in a comment,
# and two separate views each wearing one treatment).

CLEAN = '''
struct Row: View {
    var body: some View {
        // A bare .onHover here would be prose, not code.
        Text("hi")
            .dsHover()
            .macHoverLift()
            .dsTooltip("Open in Photos")
        Image(systemName: "star")
            .dsHover()
            .macHoverBloom()
    }
}
'''

DIRTY_DOUBLED = '''
struct Row: View {
    var body: some View {
        Text("hi")
            .macHoverLift()
            .macHoverBloom()
    }
}
'''

DIRTY_SHOUT = '''
struct Row: View {
    var body: some View { Text("hi").dsTooltip("OPEN IN PHOTOS") }
}
'''

DIRTY_STOP = '''
struct Row: View {
    var body: some View { Text("hi").dsTooltip("Open in Photos.") }
}
'''

DIRTY_EMPTY = '''
struct Row: View {
    var body: some View { Text("hi").dsTooltip("") }
}
'''

DIRTY_RAW_HELP = '''
struct Row: View {
    var body: some View { Text("hi").help("Open in Photos") }
}
'''

DIRTY_RAW_HOVER = '''
struct Row: View {
    var body: some View { Text("hi").onHover { _ in } }
}
'''

DIRTY_RAW_POINTER = '''
struct Row: View {
    var body: some View { Text("hi").pointerStyle(.link) }
}
'''


def self_test():
    cases = [
        ("clean tree", CLEAN, "Screens", 0, None),
        ("doubled lift+bloom", DIRTY_DOUBLED, "Screens", 1, "BOTH"),
        ("ALL-CAPS tooltip", DIRTY_SHOUT, "Screens", 1, "ALL-CAPS"),
        ("tooltip full stop", DIRTY_STOP, "Screens", 1, "full stop"),
        ("empty tooltip", DIRTY_EMPTY, "Screens", 1, "empty"),
        ("raw .help", DIRTY_RAW_HELP, "Screens", 1, "raw .help("),
        ("raw .onHover", DIRTY_RAW_HOVER, "Screens", 1, "raw .onHover"),
        ("raw .pointerStyle", DIRTY_RAW_POINTER, "Screens", 1, "raw .pointerStyle("),
        # The vocabulary's own home is allowed the primitives it defines.
        ("primitives in Design/", DIRTY_RAW_HOVER, "Design", 0, None),
        ("pointerStyle in Design/", DIRTY_RAW_POINTER, "Design", 0, None),
    ]
    failed = 0
    with tempfile.TemporaryDirectory() as tmp:
        for name, body, folder, want, needle in cases:
            d = Path(tmp) / name.replace(" ", "_") / folder
            d.mkdir(parents=True)
            (d / "Fixture.swift").write_text(body)
            got = audit([d.parent])
            if len(got) != want or (needle and not any(needle in g for g in got)):
                print(f"  ✗ {name}: expected {want} finding(s)"
                      f"{f' naming {needle!r}' if needle else ''}, got {got}")
                failed += 1
            else:
                print(f"  ✓ {name}")

    # Mutation: two SEPARATE views, one lift and one bloom, must stay clean —
    # this is the false positive a fixed ±N line window produces, and the
    # reason `chain_bounds` walks the chain instead.
    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp) / "Screens"
        d.mkdir(parents=True)
        (d / "Two.swift").write_text('''
struct Two: View {
    var body: some View {
        Text("a")
            .macHoverLift()
        Text("b")
            .macHoverBloom()
    }
}
''')
        got = audit([d.parent])
        if got:
            print(f"  ✗ two separate views flagged as doubled: {got}")
            failed += 1
        else:
            print("  ✓ two separate views stay clean")

    # Mutation: a primitive named only in a COMMENT must not fire. This is the
    # exact false positive the shipped tree would produce — `Glass.swift`
    # explains itself by naming `.help()`.
    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp) / "Screens"
        d.mkdir(parents=True)
        (d / "Prose.swift").write_text('''
struct Prose: View {
    /// Uses dsTooltip rather than a bare .help() so iOS keeps one hint.
    // .onHover and .pointerStyle(.link) are named here as prose only.
    var body: some View { Text("hi").dsTooltip("Open") }
}
''')
        got = audit([d.parent])
        if got:
            print(f"  ✗ primitives in comments flagged: {got}")
            failed += 1
        else:
            print("  ✓ primitives named in comments stay clean")

    return failed


def main():
    if "--self-test" in sys.argv:
        print("mac-pointer-audit self-test")
        failed = self_test()
        if failed:
            print(f"\n✗ {failed} self-test case(s) failed")
            return 1
        print("\n✓ self-test passed")
        return 0

    findings = audit(SOURCES)
    if findings:
        print("✗ Mac pointer vocabulary:")
        for f in findings:
            print(f"  {f}")
        print(f"\n{len(findings)} finding(s) — see Design/MacDelight.swift for the vocabulary")
        return 1
    print("✓ Mac pointer vocabulary: one treatment per surface, tooltips in sentence case, "
          "no raw primitives outside Design/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
