#!/usr/bin/env python3
"""Design-ramp audit (2026-08-11) — the SIZE half of the design system.

`design-motion-audit.py` made the motion law mechanical for the reason this
file exists too: every other load-bearing rule in this repo is a script, the
design system was memory, and memory lost. This is the same treatment for the
two ramps that carry every screen's proportions.

Two checks, both static, neither needing a build:

  1. **A glyph is sized off the ramp, not frozen.**  `.font(.system(size:))` on
     an `Image(systemName:)` is a FROZEN point size, while every label around it
     goes through `dsText` and grows with the person's text setting. At an
     accessibility size the words grow and the icons beside them do not:
     chevrons shrinking away from their rows, a symbol a third the height of the
     label it belongs to. **Invisible at the default size**, which is exactly how
     ~150 of them accumulated through three separate Dynamic Type passes that
     each fixed the `Text` beside them and left the glyph alone. `dsGlyph`
     (Shared/Typography.swift) is the fix; this keeps it fixed.

  2. **A brand mark is sized off `DS.Mark`, not a literal.**  `BridgeIcon` was
     called at 14 different literal sizes across ~40 sites. Two of them were
     real defects rather than mere untidiness: `ShapedRows.TokenRow` drew its
     thumbnail at `DS.Face.list` (36) and its fallback mark at 38 **in the same
     HStack**, so a row's leading square changed size depending on whether the
     art had loaded; and a bridge's setup header drew at 60 while its CONNECTED
     header drew at 54 — one screen, two states, two sizes. Both render
     perfectly; neither is visible in a screenshot of one state.

Three deliberate NON-checks, so this can't become a lint that cries wolf:

  * A glyph size that is not a literal (`size * 0.5`, a computed constant) is
    left alone — it is already derived from something, and the caller is the
    only one who knows from what.
  * `.font(.system(size:))` on TEXT is not flagged. The type ramp is not
    universal by ruling — `GenRenderer` composes model-authored documents and
    a handful of views size type off their own container — and a check that
    demanded `dsText` everywhere would fire on correct code.
  * Neither check judges WHICH rung was picked. `DS.Mark.hero` on a row would
    look absurd and this would pass it; that is a design review's job, not a
    grep's.

**The seam with `face-ramp-audit.py`, which must not be blurred.** That script
covers ROUND identity marks — a face, a wallet identicon, or an app icon
covering for a missing picture — and says in its own header that a SQUARE
`BridgeIcon` is deliberately out of scope, "a brand mark in a tile, not a
face". That is still true, and it is the gap check 2 fills: the two ramps
answer to different neighbours (`DS.Face` to the text beside the mark,
`DS.Mark` to whether the mark identifies a row, a card or a screen), so they
are separate ramps with separate checks. They agree on their first three rungs
by construction — `DS.Mark.badge`/`.row`/`.list` ARE the `Face` values — because
in a row a mark and a face are interchangeable and must never disagree. Do not
merge the scripts: a single check would have to pick one ramp for a call it
cannot classify, and `circular:` is what classifies it.

`KNOWN_EXEMPT` is a conscious ruling per entry, never a snooze.

Usage:  scripts/design-ramp-audit.py [--self-test]
Exit 0 = clean.
"""

import pathlib
import re
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = [
    ROOT / "Casberi" / "Casberi",
    ROOT / "Casberi" / "Shared",
]

# `.font(.system(size: <literal>))`, optionally with a weight. A non-literal
# size (`size * 0.5`) deliberately does not match — see the header.
GLYPH_FONT = re.compile(r"\.font\(\.system\(size: \d+(?:\.\d+)?(?:, weight: \.\w+)?\)\)")
SYMBOL = re.compile(r"Image\(_?(?:internalS|s)ystemName")
TEXTISH = re.compile(r"\bText\(|\bLabel\(")
MARK_LITERAL = re.compile(r"BridgeIcon\([^)\n]*?\bsize: \d")

# Each entry is a ruling: "this size is not the ramp's to decide."
KNOWN_EXEMPT = {
    # Sized by the 17pt well it overlays, not by anything beside it — the same
    # carve-out `DS.Face` already makes for `SourceChips.iconSize` and the
    # Sources Tray, whose marks are sized by their own grid.
    ("Casberi/Casberi/Screens/ShapedRows.swift", "sourceBadgeView"),
}


def _swift_files(roots):
    for root in roots:
        if root.is_dir():
            yield from sorted(root.rglob("*.swift"))


def _strip_comments(text):
    """Blank out `//` tails and `/* */` blocks, preserving line count.

    Load-bearing, not fussiness: this file's own header documents the rule by
    quoting the very call shapes it forbids, and several sources explain the
    fix by naming the old spelling. A guard grepping raw source fires on the
    prose explaining it — the lesson `obsidian-selftest` and
    `appstoreconnect-selftest` each paid for.
    """
    out, i, n, in_block = [], 0, len(text), False
    for line in text.split("\n"):
        if in_block:
            end = line.find("*/")
            if end < 0:
                out.append("")
                continue
            line, in_block = " " * (end + 2) + line[end + 2:], False
        start = line.find("/*")
        if start >= 0 and (line.find("//") < 0 or line.find("//") > start):
            end = line.find("*/", start + 2)
            if end < 0:
                out.append(line[:start])
                in_block = True
                continue
            line = line[:start] + " " * (end + 2 - start) + line[end + 2:]
        slashes = line.find("//")
        if slashes >= 0:
            line = line[:slashes]
        out.append(line)
    return "\n".join(out)


def _enclosing(lines, index):
    """The nearest `func`/`var` name above `index` — for a readable finding."""
    for i in range(index, -1, -1):
        m = re.search(r"\b(?:func|var)\s+(\w+)", lines[i])
        if m:
            return m.group(1)
    return "?"


def audit(roots, exempt=KNOWN_EXEMPT):
    findings = []
    for path in _swift_files(roots):
        try:
            rel = str(path.relative_to(ROOT))
        except ValueError:
            rel = str(path)
        lines = _strip_comments(path.read_text(errors="replace")).split("\n")

        for i, line in enumerate(lines):
            # --- Check 1: a frozen glyph size.
            if GLYPH_FONT.search(line):
                # What is being sized? The nearest view named at or above this
                # line, within a short window — a modifier chain is short.
                window = "\n".join(lines[max(0, i - 3):i + 1])
                sym = max(m.end() for m in SYMBOL.finditer(window)) if SYMBOL.search(window) else -1
                txt = max(m.end() for m in TEXTISH.finditer(window)) if TEXTISH.search(window) else -1
                if sym >= 0 and sym > txt:
                    name = _enclosing(lines, i)
                    if (rel, name) not in exempt:
                        findings.append(
                            f"{rel}:{i + 1} {name}: an SF Symbol sized with a frozen "
                            f".font(.system(size:)) — use .dsGlyph(_:) so it scales "
                            f"with the label beside it")

            # --- Check 2: a brand mark at a literal size.
            if MARK_LITERAL.search(line):
                name = _enclosing(lines, i)
                if (rel, name) not in exempt:
                    findings.append(
                        f"{rel}:{i + 1} {name}: BridgeIcon at a literal size — "
                        f"use a DS.Mark rung (inline/badge/row/list/tile/hero)")
    return findings


# --------------------------------------------------------------------------
# Self-test. A check that cannot fail proves nothing, so this demonstrates it
# catches each shape and clears each clean one BEFORE it certifies the tree.
# --------------------------------------------------------------------------

DIRTY_GLYPH = """
import SwiftUI
struct A: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
    }
}
"""

DIRTY_GLYPH_INLINE = """
import SwiftUI
struct A: View {
    var body: some View {
        Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
    }
}
"""

DIRTY_MARK = """
import SwiftUI
struct A: View {
    var body: some View {
        BridgeIcon(name: "Stripe", size: 38)
    }
}
"""

CLEAN = """
import SwiftUI
struct A: View {
    // A glyph used to read .font(.system(size: 13, weight: .semibold)) here,
    // and the mark used to be BridgeIcon(name: n, size: 38).
    var body: some View {
        HStack {
            Image(systemName: "chevron.right").dsGlyph(13)
            BridgeIcon(name: "Stripe", size: DS.Mark.list)
            /* BridgeIcon(name: "Stripe", size: 38) — the old spelling. */
            Text("Hi").font(.system(size: 15, weight: .semibold))
            BridgeIcon(name: "Stripe", size: markSize)
            Image(systemName: "x").font(.system(size: size * 0.5, weight: .bold))
        }
    }
}
"""


def _self_test():
    cases = [
        ("catches a glyph on its own modifier line", DIRTY_GLYPH, 1),
        ("catches a glyph inline on the Image", DIRTY_GLYPH_INLINE, 1),
        ("catches a BridgeIcon literal size", DIRTY_MARK, 1),
        ("passes clean source, and ignores both comment forms, Text, "
         "a named mark size and a computed glyph size", CLEAN, 0),
    ]
    ok = True
    with tempfile.TemporaryDirectory() as tmp:
        for label, body, expected in cases:
            d = pathlib.Path(tmp) / label.split()[1]
            d.mkdir(parents=True, exist_ok=True)
            (d / "Case.swift").write_text(body)
            got = len(audit([d], exempt=set()))
            mark = "✓" if got == expected else "✗"
            if got != expected:
                ok = False
            print(f"  {mark} {label} (expected {expected}, got {got})")

        # The exemption must actually exempt — a snooze that does nothing is
        # worse than none, since it reads as a considered ruling.
        d = pathlib.Path(tmp) / "exempt"
        d.mkdir(parents=True, exist_ok=True)
        f = d / "Case.swift"
        f.write_text(DIRTY_MARK)
        rel = str(f.relative_to(ROOT)) if str(f).startswith(str(ROOT)) else str(f)
        got = len(audit([d], exempt={(rel, "body")}))
        mark = "✓" if got == 0 else "✗"
        if got != 0:
            ok = False
        print(f"  {mark} an exempt entry really clears its finding (expected 0, got {got})")
    return ok


def main():
    if "--self-test" in sys.argv:
        print("design-ramp-audit self-test")
        if not _self_test():
            print("✗ self-test FAILED — the audit does not catch what it claims")
            return 1
        print("  clean")
        return 0

    findings = audit(SOURCES)
    if findings:
        print(f"design-ramp-audit: {len(findings)} finding(s)\n")
        for f in findings:
            print(f"  · {f}")
        print("\nSee DS.Mark (Design/DesignTokens.swift) and dsGlyph "
              "(Shared/Typography.swift).")
        return 1
    print("design-ramp-audit: OK — every glyph scales and every brand mark "
          "is on the DS.Mark ramp.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
