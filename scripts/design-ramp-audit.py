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

  3. **Text is set off the type ramp, not off a literal.**  Added by prd §506
     (2026-08-28),
     and until then this file said in as many words that text was NOT checked.
     That carve-out was written for `GenRenderer`, which composes model-authored
     documents — but it exempted the whole tree, and what accumulated under it
     was not GenRenderer: the Settings colophon drew `.system(size: 17,
     weight: .semibold)` over `.footnote` under a doc comment claiming it was
     "set in the app's own ramp", and the widget's posts lead drew a frozen 17
     rounded while every tile beside it went through `dsText`. Both are
     invisible at the default text size and neither grows with it, which is the
     entire job of the ramp. A LITERAL size on `Text`/`Label`, or one of
     SwiftUI's semantic styles (`.font(.footnote)`), is a finding; a computed
     size still is not (check 1's rule, unchanged).

  4. **A weight override actually overrides something.**  `.dsText(.x)` then
     `.fontWeight(.y)` is the app's own idiom and correct — size from the ramp,
     weight as emphasis (`heading17`'s doc rules it, and 250-odd call sites use
     it). What is not correct is restating the rung's OWN weight:
     `.dsText(.price16).fontWeight(.bold)` when `price16` is already bold. It
     renders identically, so nothing can see it, and each one is an author who
     did not know what the rung carried — the exact reading-drift a named ramp
     exists to prevent. The rung→weight table is parsed out of
     `Shared/Typography.swift` at run time, so this check can never disagree
     with the ramp it guards.

Four deliberate NON-checks, so this can't become a lint that cries wolf:

  * A glyph size that is not a literal (`size * 0.5`, a computed constant) is
    left alone — it is already derived from something, and the caller is the
    only one who knows from what.
  * Check 3 flags a literal font only when TEXT is unambiguously its subject
    (a `Text(`/`Label(` nearer than any `Image(systemName:)` in the same short
    chain). A `.font()` on a container, or one this cannot attribute, is left
    alone — a check that guessed would fire on correct code, which is what the
    old blanket carve-out was overreacting to.
  * Neither ramp check judges WHICH rung was picked. `DS.Mark.hero` on a row
    would look absurd and this would pass it; that is a design review's job,
    not a grep's. **Nor is a rung's CALLER BUDGET checkable, and that was
    measured rather than assumed** (2026-08-28): `price48` documents itself as
    "one per surface" and `heading28` as "a sentence, never a figure", and both
    rules were re-derived that day from thirteen and seven call sites that had
    quietly outgrown a prose "one caller, deliberately". A count per FILE is the
    only thing a grep could enforce and it is wrong in both directions —
    `HegotaRoomCard` correctly takes `price48` four times because it holds four
    cards, while two crowns on ONE card is the real defect and lives in the same
    file either way. Better to say so than to ship an exemption list that is a
    snooze wearing a registry's clothes.

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
    # The widget extension joined 2026-08-14 (prd §382) and had NEVER been in
    # any audit's scope — not this one, not the motion law, not the liveness
    # rules. It was one file for a year, so nobody noticed the gap; it is six
    # now, it draws `Thing`s and money, and its labels already go through
    # `dsText`. A tile's glyphs must grow with its labels for the same reason a
    # row's do, and a widget is if anything WORSE to get wrong: it cannot be
    # scrolled, so a symbol a third the height of the word beside it is the
    # whole tile.
    ROOT / "Casberi" / "CasberiWidgets",
]

# `.font(.system(size: <literal>))`, optionally with a weight. A non-literal
# size (`size * 0.5`) deliberately does not match — see the header.
GLYPH_FONT = re.compile(
    r"\.font\(\.system\(size: (\d+(?:\.\d+)?)(?:, weight: \.\w+)?"
    r"(?:, design: \.\w+)?\)\)")
SYMBOL = re.compile(r"Image\(_?(?:internalS|s)ystemName")
TEXTISH = re.compile(r"\bText\(|\bLabel\(")
MARK_LITERAL = re.compile(r"BridgeIcon\([^)\n]*?\bsize: \d")

# SwiftUI's own semantic styles. Every one of them is a size and a weight this
# app did not choose, on a curve the ramp does not control.
SEMANTIC_FONT = re.compile(
    r"\.font\(\.(largeTitle|title|title2|title3|headline|subheadline|body"
    r"|callout|footnote|caption|caption2)\)")

# `.dsText(.rung)` and a plain (non-conditional) weight override. A ternary
# weight is emphasis and never matches, which is the point.
DSTEXT_RUNG = re.compile(r"\.dsText\(\.(\w+)\)")
PLAIN_WEIGHT = re.compile(r"\.fontWeight\(\.(\w+)\)")
RAMP_RUNG = re.compile(
    r"static let (\w+)\s*=\s*DSTextStyle\(size: [^)]*?weight: \.(\w+)")

TYPOGRAPHY = ROOT / "Casberi" / "Shared" / "Typography.swift"


def ramp_weights(path=TYPOGRAPHY):
    """rung name → its own weight, read out of the ramp itself.

    Parsed rather than copied so check 4 can never disagree with the file it
    guards: retune a rung's weight and the redundant overrides it creates are
    findings the same day, with no list here to remember to edit.
    """
    try:
        text = path.read_text(errors="replace")
    except OSError:
        return {}
    return {m.group(1): m.group(2) for m in RAMP_RUNG.finditer(text)}


# Each entry is a ruling: "this size is not the ramp's to decide."
KNOWN_EXEMPT = {
    # Sized by the 17pt well it overlays, not by anything beside it — the same
    # carve-out `DS.Face` already makes for `SourceChips.iconSize` and the
    # Sources Tray, whose marks are sized by their own grid.
    ("Casberi/Casberi/Screens/ShapedRows.swift", "sourceBadgeView"),
}

# Check 3's own rulings, keyed by (file, enclosing symbol, SIZE). The size is in
# the key deliberately: `body` is the commonest name in the tree, so a 2-tuple
# here would exempt every literal font in a 5,000-line file rather than the one
# that earned it.
KNOWN_TEXT_EXEMPT = {
    # 74pt is a MONUMENT — the day brief's one figure, a rung the reading ramp
    # deliberately does not carry. The call site says so at length and says
    # nothing else may borrow it without that comment moving too; this entry is
    # the mechanical half of that sentence, since comments are stripped before
    # any check runs.
    ("Casberi/Casberi/GenUI/GenRenderer.swift", "body", 74.0),
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


def audit(roots, exempt=KNOWN_EXEMPT, text_exempt=KNOWN_TEXT_EXEMPT,
          weights=None):
    findings = []
    weights = ramp_weights() if weights is None else weights
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

                elif txt >= 0 and txt > sym:
                    # --- Check 3a: TEXT at a frozen literal size.
                    name = _enclosing(lines, i)
                    size = float(GLYPH_FONT.search(line).group(1))
                    if (rel, name, size) not in text_exempt:
                        findings.append(
                            f"{rel}:{i + 1} {name}: text set at a frozen "
                            f"{size:g}pt — use .dsText(_:) so it scales with "
                            f"the person's text size")

            # --- Check 3b: one of SwiftUI's own semantic styles.
            if SEMANTIC_FONT.search(line):
                name = _enclosing(lines, i)
                findings.append(
                    f"{rel}:{i + 1} {name}: "
                    f"{SEMANTIC_FONT.search(line).group(0)} — a size and weight "
                    f"the app did not choose; use a .dsText(_:) rung")

            # --- Check 4: a weight override restating the rung's own weight.
            rung = DSTEXT_RUNG.search(line)
            if rung and rung.group(1) in weights:
                own = weights[rung.group(1)]
                # The rest of this line, then the chain continuing below it. A
                # following line only counts while it is still a modifier —
                # once the chain ends, a `.fontWeight` belongs to another view.
                tail = line[rung.end():]
                chain = [tail]
                for j in range(i + 1, min(i + 4, len(lines))):
                    nxt = lines[j].strip()
                    if not nxt.startswith(".") or ".dsText(" in nxt:
                        break
                    chain.append(nxt)
                for seg in chain:
                    hit = PLAIN_WEIGHT.search(seg)
                    if hit and hit.group(1) == own:
                        findings.append(
                            f"{rel}:{i + 1} {_enclosing(lines, i)}: "
                            f".dsText(.{rung.group(1)}).fontWeight(.{own}) — "
                            f"the rung is already .{own}, so this overrides "
                            f"nothing")
                        break

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

DIRTY_TEXT = """
import SwiftUI
struct A: View {
    var body: some View {
        Text("casberi")
            .font(.system(size: 17, weight: .semibold))
    }
}
"""

DIRTY_SEMANTIC = """
import SwiftUI
struct A: View {
    var body: some View {
        Text(buildLine).font(.footnote)
    }
}
"""

DIRTY_WEIGHT_INLINE = """
import SwiftUI
struct A: View {
    var body: some View {
        Text("Hi").dsText(.price16).fontWeight(.bold)
    }
}
"""

DIRTY_WEIGHT_CHAINED = """
import SwiftUI
struct A: View {
    var body: some View {
        Text("Hi")
            .dsText(.label12)
            .fontWeight(.medium)
            .foregroundStyle(DS.textPrimary)
    }
}
"""

CLEAN = """
import SwiftUI
struct A: View {
    // A glyph used to read .font(.system(size: 13, weight: .semibold)) here,
    // the mark used to be BridgeIcon(name: n, size: 38), the colophon used to
    // be .font(.system(size: 17, weight: .semibold)) over .font(.footnote),
    // and this line used to read .dsText(.price16).fontWeight(.bold).
    var body: some View {
        HStack {
            Image(systemName: "chevron.right").dsGlyph(13)
            BridgeIcon(name: "Stripe", size: DS.Mark.list)
            /* BridgeIcon(name: "Stripe", size: 38) — the old spelling. */
            BridgeIcon(name: "Stripe", size: markSize)
            Image(systemName: "x").font(.system(size: size * 0.5, weight: .bold))
            Text("Hi").dsText(.price16)
            Text("Emphasis").dsText(.label12).fontWeight(.semibold)
            Text("Conditional").dsText(.price16).fontWeight(on ? .bold : .regular)
            Text("Derived").font(.system(size: side * 0.4, weight: .bold))
            Text("Ramp").font(DSTextStyle.body17.scaledFont)
        }
        VStack {
            Text("Chain ended").dsText(.price16)
        }
        .fontWeight(.bold)
    }
}
"""


def _self_test():
    cases = [
        ("catches a glyph on its own modifier line", DIRTY_GLYPH, 1),
        ("catches a glyph inline on the Image", DIRTY_GLYPH_INLINE, 1),
        ("catches a BridgeIcon literal size", DIRTY_MARK, 1),
        ("catches text at a frozen literal size", DIRTY_TEXT, 1),
        ("catches a semantic system style", DIRTY_SEMANTIC, 1),
        ("catches a redundant weight override, inline", DIRTY_WEIGHT_INLINE, 1),
        ("catches a redundant weight override, down a chain",
         DIRTY_WEIGHT_CHAINED, 1),
        ("passes clean source, and ignores both comment forms, a named mark "
         "size, a computed size on either a glyph or Text, a real emphasis "
         "override, a conditional weight, a ramp-derived font, and a weight "
         "past the end of the chain", CLEAN, 0),
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

        # ...and the same for check 3's own set, which is keyed on the SIZE too.
        d = pathlib.Path(tmp) / "textexempt"
        d.mkdir(parents=True, exist_ok=True)
        f = d / "Case.swift"
        f.write_text(DIRTY_TEXT)
        rel = str(f.relative_to(ROOT)) if str(f).startswith(str(ROOT)) else str(f)
        got = len(audit([d], text_exempt={(rel, "body", 17.0)}))
        mark = "✓" if got == 0 else "✗"
        if got != 0:
            ok = False
        print(f"  {mark} a text exemption really clears its finding "
              f"(expected 0, got {got})")
        # ...and is narrow: the same symbol at another size is still a finding,
        # which is the whole reason the size is in the key.
        got = len(audit([d], text_exempt={(rel, "body", 74.0)}))
        mark = "✓" if got == 1 else "✗"
        if got != 1:
            ok = False
        print(f"  {mark} a text exemption is scoped to its own size "
              f"(expected 1, got {got})")

    # Check 4 is only ever as good as its table, and an empty table is a check
    # that silently passes everything — the failure mode this repo calls a false
    # green. So the parse is asserted against the real ramp, not trusted.
    w = ramp_weights()
    for rung, weight in (("price16", "bold"), ("label12", "medium"),
                         ("body17", "regular"), ("heading17", "semibold")):
        got = w.get(rung)
        mark = "✓" if got == weight else "✗"
        if got != weight:
            ok = False
        print(f"  {mark} the ramp parse reads {rung} as .{weight} (got .{got})")
    if len(w) < 20:
        ok = False
        print(f"  ✗ the ramp parse found only {len(w)} rungs — expected the "
              f"whole ramp")
    else:
        print(f"  ✓ the ramp parse found all {len(w)} rungs")
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
    print("design-ramp-audit: OK — every glyph scales, every brand mark is on "
          "the DS.Mark ramp, every label is on the type ramp, and no weight "
          "override restates its own rung.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
