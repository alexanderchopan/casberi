#!/usr/bin/env python3
"""Status-ink audit (the HIG sweep, 2026-09-29).

WHY THIS EXISTS. `DS.attention`, `DS.confirm` and `DS.destructive` are Apple's
vivid system hues. Right for a glyph or a fill, wrong for a word: on the light
page system orange and green measure 2.2:1 and red 3.6:1, under the HIG's
4.5:1 for text. 157 status words ("Live", "Under review", every error line) were
drawn in them and were readable only under Increase Contrast. They now take
`DS.attentionInk` / `confirmInk` / `destructiveInk` (DesignTokens.swift), which
pass in both modes. Nothing a build or a screen sweep does can see the
difference: the words render, in the right hue, just too faint to read.

ONE CHECK, static, no build:

    A modifier chain that draws WORDS (`Text(`, `Label(`, `DSProse.text(`,
    `.dsText(`) takes an ink rung, never the hue.

The chain is the run of `.modifier` lines above the colour, back to the view
it starts from, so a word whose colour sits three lines below its `Text(` is
read the same as a one-liner.

WHAT THIS DELIBERATELY DOES NOT CHECK:

  · A chain that also draws a glyph or a shape (`Image(systemName:`,
    `dsGlyph`, `Circle(`…). A glyph answers to 3:1 for non-text, and a mixed
    chain cannot be judged from text; the 18 glyph sites keep the hue.
  · `.tint(DS.destructive)` and `role: .destructive`: the system draws those
    and picks its own text colour.
  · A hue reached through a variable (`let c = DS.attention` … `.foregroundStyle(c)`).
    A text check cannot follow it; none exists today.
"""

import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIRS = ["Casberi/Casberi", "Casberi/Shared", "Casberi/CasberiWidgets"]

# The colour argument, one level of nested parentheses allowed, so a
# conditional (`x ? DS.confirm : DS.textPrimary`) is read as well as a bare hue.
COLOUR_ARG = re.compile(r"\.foreground(?:Style|Color)\(((?:[^()]|\([^()]*\))*)\)")
BARE_HUE = re.compile(r"\bDS\.(attention|confirm|destructive)\b(?!Ink)")
WORDS = re.compile(r"\bText\(|\bLabel\(|\bDSProse\.text\(|\.dsText\(")
GLYPH = re.compile(r"Image\(systemName|\.dsGlyph\(|\bCircle\(|\bCapsule\(|Rectangle\(|ProgressView|Gauge")


def strip_comments(text: str) -> str:
    """Comments out, strings and line breaks kept, so a line number is real
    and the doc comment in DesignTokens.swift naming the hues is not read."""
    out, i, n = [], 0, len(text)
    in_block = in_string = False
    while i < n:
        ch, nxt = text[i], text[i + 1] if i + 1 < n else ""
        if in_block:
            if ch == "*" and nxt == "/":
                in_block = False
                i += 2
                continue
            out.append("\n" if ch == "\n" else "")
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
        if ch == '"':
            in_string = True
        elif ch == "/" and nxt == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        elif ch == "/" and nxt == "*":
            in_block = True
            i += 2
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def chain(lines, i):
    """The line and, when it is a modifier, the modifier run above it back to
    the view it starts from (at most ten lines)."""
    ctx = [lines[i]]
    if lines[i].strip().startswith("."):
        j = i
        while j > 0 and lines[j].strip().startswith(".") and len(ctx) <= 10:
            j -= 1
            ctx.insert(0, lines[j])
    return "\n".join(ctx)


def audit(root: Path):
    findings = []
    for rel in SOURCE_DIRS:
        base = root / rel
        if not base.exists():
            continue
        for path in sorted(base.rglob("*.swift")):
            lines = strip_comments(path.read_text(encoding="utf-8")).split("\n")
            for i, line in enumerate(lines):
                for arg in COLOUR_ARG.finditer(line):
                    for m in BARE_HUE.finditer(arg.group(1)):
                        c = chain(lines, i)
                        if WORDS.search(c) and not GLYPH.search(c):
                            findings.append((path.relative_to(root), i + 1, m.group(1)))
    return findings


SELF_TEST = """
struct Card: View {
    var body: some View {
        VStack {
            Text("Live").dsText(.label12).foregroundStyle(DS.confirmInk)
            Text(errorText)
                .dsText(.label12)
                .foregroundStyle(DS.destructiveInk)
            Image(systemName: "checkmark.circle.fill")
                .dsGlyph(.subhead)
                .foregroundStyle(DS.confirm)
            // A comment naming .foregroundStyle(DS.attention) on Text( is not code.
            Circle().fill(DS.attention)
        }
    }
}
"""


def self_test() -> int:
    failures = []
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        f = root / "Casberi/Casberi/Screens/Card.swift"
        f.parent.mkdir(parents=True)

        def run(body):
            f.write_text(body, encoding="utf-8")
            return audit(root)

        got = run(SELF_TEST)
        if got:
            failures.append(f"the clean fixture was flagged: {got}")

        # MUTATION 1: a one-line word back on the hue fires.
        if [h for *_, h in run(SELF_TEST.replace("DS.confirmInk", "DS.confirm"))] != ["confirm"]:
            failures.append("a one-line Text on DS.confirm was not reported")

        # MUTATION 2: the colour three lines below its Text( fires too.
        got = run(SELF_TEST.replace("DS.destructiveInk", "DS.destructive"))
        if [(ln, h) for _, ln, h in got] != [(8, "destructive")]:
            failures.append(f"a multi-line chain on DS.destructive was not reported at its line: {got}")

        # MUTATION 3: foregroundColor, the older spelling, is the same defect.
        mutated = SELF_TEST.replace(".foregroundStyle(DS.confirmInk)", ".foregroundColor(DS.attention)")
        if [h for *_, h in run(mutated)] != ["attention"]:
            failures.append("foregroundColor(DS.attention) on a word was not reported")

        # MUTATION 4: a DSProse line is words.
        mutated = SELF_TEST.replace('Text("Live")', 'DSProse.text("Live")').replace("DS.confirmInk", "DS.confirm")
        if len(run(mutated)) != 1:
            failures.append("DSProse.text on the hue was not reported")

        # MUTATION 5: the glyph chain keeps its hue — never reported.
        if any(ln == 11 for _, ln, _ in run(SELF_TEST)):
            failures.append("a glyph on DS.confirm was reported")

        # MUTATION 7: a conditional colour on a word fires — the shape the
        # first pass missed (`overdue ? DS.destructive : DS.textPrimary`).
        mutated = SELF_TEST.replace(".foregroundStyle(DS.destructiveInk)",
                                    ".foregroundStyle(late ? DS.destructive : DS.textPrimary)")
        if [h for *_, h in run(mutated)] != ["destructive"]:
            failures.append("a conditional DS.destructive on a word was not reported")

        # MUTATION 8: and its ink form passes.
        mutated = SELF_TEST.replace(".foregroundStyle(DS.destructiveInk)",
                                    ".foregroundStyle(late ? DS.destructiveInk : DS.textPrimary)")
        if run(mutated):
            failures.append("a conditional DS.destructiveInk was reported")

        # MUTATION 6: the comment is stripped — take stripping away and it must
        # be what fires, proving the fixture's comment is a live trap.
        global strip_comments
        kept = strip_comments
        strip_comments = lambda t: t
        if not run(SELF_TEST):
            failures.append("the comment trap is dead: an unstripped comment was not read")
        strip_comments = kept

    if failures:
        for x in failures:
            print(f"self-test FAILED: {x}", file=sys.stderr)
        return 1
    print("status ink audit self-test: ok (8 mutations)")
    return 0


def main() -> int:
    if "--self-test" in sys.argv[1:]:
        return self_test()
    findings = audit(ROOT)
    if not findings:
        print("status ink audit: ok")
        return 0
    print("A status word is drawn in the vivid hue instead of its ink:\n")
    for rel, ln, hue in findings:
        print(f"  {rel}:{ln}: DS.{hue} → DS.{hue}Ink")
    print("\nOn the light page the hue is 2.2:1 (orange, green) or 3.6:1 (red), under")
    print("the HIG's 4.5:1 for text. A glyph or fill keeps the hue; a word takes the ink.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
