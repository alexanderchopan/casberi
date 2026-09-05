#!/usr/bin/env python3
"""Primary-verb audit (prd §613, 2026-09-05).

WHY THIS EXISTS. §190 made the slab the app's one shape for a manage page's
controls, and `setup-copy-audit.py`/`connect-shape-audit.py` made that family's
WORDS and ARRANGEMENT mechanical. Nothing made the VERB mechanical. So the one
control every one of those screens is FOR — the filled block you tap to commit
— stayed hand-rollable, and four of them were hand-rolled: a tint-filled
`Capsule` with centered bold text on the token sheet (whose own comment called
it "the one verb", which is what `DSSlabButton` IS), and three glass pills on
the bridge detail screen. Each rendered perfectly. Each was a different height,
a different radius and a different material from the slab beside it, which is
exactly the collage §190 was written to end, re-accumulating one screen at a
time because the rule lived in a doc comment.

The user's words for it, which are the whole spec: *"this is a component we
need to not hand roll things."*

ONE CHECK, static, no build:

    A Button whose label paints a FULL-WIDTH solid fill and holds a verb must
    be drawn by a component — `DSSlabButton`, `DSActVerb`, `DevnetSendPanel`
    or `DevnetCreatePanel`.

"Full-width" is the whole of what keeps this from crying wolf, and it was
MEASURED rather than guessed. Dropping it takes the finding count on a clean
tree from 0 to 14, every one of them correct: a "Watch" chip on an address row,
"Max" on the send sheet's amount field, "Approve" on a feed row, a toast's
inline action, a scanner overlay's "Cancel". A chip is a filled control too and
is emphatically NOT this species — the species is a block that spans its
surface and says what the surface is for. So the rule reads the width, which is
the one property that separates them without needing to know what a screen
means.

FOUR DELIBERATE EXEMPTIONS, each a real boundary rather than a snooze:

  · `GenUI/` — model-authored documents. `GenRenderer` composes what the model
    asked for and its controls are the document's, not a screen's; the ramp
    audit carved it out for the same reason and this follows that ruling rather
    than inventing a second answer.
  · `CasberiWidgets/` — a different TARGET. `Design/` is app-only, so a widget
    physically cannot call these components; a finding there would be a demand
    nobody can satisfy.
  · `SummonPrototype.swift` — a prototype, not a shipped surface.
  · A button inside a `safeAreaInset` — FLOATING CHROME, where §8 puts glass and
    the slab law does not reach. This is what keeps the onboarding greeting's
    "Try a demo" (a pinned bottom CTA in glass, deliberate) from being reported
    as a hand-rolled slab.

WHAT THIS DELIBERATELY DOES NOT CHECK, so it stays honest about its reach:

  · Whether the verb's WORDS are right — `setup-copy-audit.py` owns copy, and a
    text check cannot tell a true sentence from a false one.
  · Whether a screen has the RIGHT NUMBER of primaries. `connect-shape-audit.py`
    already recorded why: counting filled slabs reports seven screens on a clean
    tree, because an import page legitimately carries a download door AND a
    commit. §190's sentence is about weight, not arithmetic.
  · A fill built at runtime from a venue's own hue (`tint` as a passed-in
    property). Those exist — `DevnetSendPanel` takes one — and they are
    components already; a hand-rolled one would be missed. Stated rather than
    papered over.

`--self-test` proves the check catches each shape and passes the clean one
before it certifies the tree (the liveness-audit contract).
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = [
    os.path.join(ROOT, "Casberi", "Casberi", "Screens"),
    os.path.join(ROOT, "Casberi", "Casberi", "Shell"),
    os.path.join(ROOT, "Casberi", "Casberi", "Design"),
]

COMPONENTS = ("DSSlabButton", "DSActVerb", "DevnetSendPanel", "DevnetCreatePanel")

EXEMPT_FILES = {
    # A prototype surface, not a shipped screen.
    "SummonPrototype.swift",
    # The components themselves: they ARE the hand-rolled fill, once, on
    # purpose. Excluding them by name rather than by a "does it define the
    # component" heuristic, which would also excuse any file that merely
    # mentions one.
    "DSSlab.swift",
    "DSActVerb.swift",
    "DevnetSendConsole.swift",
}

# A solid, non-decorative fill — the materials a primary verb is painted in.
#
# **`.borderedProminent` IS ONE, and leaving it out was this audit's real gap.**
# Its first cut looked only for fills WE paint, so a full-width centered blue
# button drawn by SwiftUI's OWN prominent style — `VibenetAccountSheet`'s note
# "Save" — passed clean while being exactly the species. Asked whether every
# centered blue button was gone, the answer was no, and this is why. A native
# style is the same block with the same problem and one fewer line of evidence.
FILL = re.compile(
    r"\.background\(\s*(?:AnyShapeStyle\(\s*)?(?:DS\.tint|DS\.confirm|DS\.destructive)\b"
    r"|\.dsGlassProminent\("
    r"|\.buttonStyle\(\s*\.borderedProminent\s*\)"
    r"|(?:Capsule|RoundedRectangle)\([^)]*\)\s*\.fill\(\s*(?:AnyShapeStyle\(\s*)?DS\.tint\b"
)
FULL_WIDTH = re.compile(r"maxWidth:\s*\.infinity")
HAS_LABEL = re.compile(r"\bText\(|\.dsText\(")
BUTTON = re.compile(r"\bButton\s*[{(]")
# Floating chrome: §8 puts glass on the floating layer, where the slab law does
# not reach. Detected on the ENCLOSING lines, not the button's own.
FLOATING = re.compile(r"safeAreaInset\(|\.overlay\(alignment:\s*\.bottom")

FLOAT_LOOKBACK = 30  # lines above a button, for the floating-chrome test


def button_extent(text, start):
    """The source of ONE button expression, brace-matched.

    **A FIXED LINE WINDOW IS WRONG HERE, and it produced a false positive on
    this audit's first real run**: a bare `Button("Done") { dismiss() }` in a
    toolbar was reported as a hand-rolled filled verb, because thirteen lines
    below it — inside a DIFFERENT button — sat the fill and the
    `maxWidth: .infinity` the check looks for. A window cannot tell whose
    modifier it is reading. So the extent is the button's own braces plus the
    modifier lines chained onto it, and nothing after.

    String literals are skipped so a brace inside one cannot unbalance the
    walk; interpolation is not parsed, which is stated rather than pretended —
    a `\\(` inside a string keeps its own braces balanced in practice.
    """
    i, n = start, len(text)
    depth = 0
    opened = False
    while i < n:
        c = text[i]
        if c == '"':                      # skip a string literal
            i += 1
            while i < n and text[i] != '"':
                i += 2 if text[i] == "\\" else 1
            i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if c in "{(":
            depth += 1
            opened = True
        elif c in ")}":
            depth -= 1
            if opened and depth <= 0:
                i += 1
                break
        i += 1
    # A trailing `} label: { … }` reopens; keep going while it does.
    while i < n:
        rest = text[i:]
        m = re.match(r"\s*(?:label|action)\s*:\s*\{", rest)
        if not m:
            break
        j = i + m.end() - 1
        depth = 0
        while j < n:
            c = text[j]
            if c == '"':
                j += 1
                while j < n and text[j] != '"':
                    j += 2 if text[j] == "\\" else 1
                j += 1
                continue
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    j += 1
                    break
            j += 1
        i = j
    # Modifiers chained onto the button belong to it.
    while True:
        m = re.match(r"\s*\.[A-Za-z]", text[i:])
        if not m:
            break
        nl = text.find("\n", i)
        if nl == -1:
            i = n
            break
        i = nl + 1
    return text[start:i]


def findings_in(text, filename="<memory>"):
    """Every hand-rolled full-width filled verb in one file's source."""
    out = []
    if os.path.basename(filename) in EXEMPT_FILES:
        return out
    lines = text.split("\n")
    for m in BUTTON.finditer(text):
        ln = text[: m.start()].count("\n")
        window = button_extent(text, m.start())
        if not FILL.search(window):
            continue
        if not FULL_WIDTH.search(window):
            continue          # a chip, not a block — measured, see the header
        if not HAS_LABEL.search(window):
            continue          # a filled shape with no words is a figure
        if any(c in window for c in COMPONENTS):
            continue          # already the component
        above = "\n".join(lines[max(0, ln - FLOAT_LOOKBACK) : ln])
        if FLOATING.search(above):
            continue          # floating chrome — glass is correct there
        label = re.search(r"Text\(\s*([^\n]{0,48})", window)
        out.append((ln + 1, (label.group(1) if label else "?").strip()))
    return out


CLEAN = """
struct Fine: View {
    var body: some View {
        DSSlabButton(title: "Connect", systemImage: "link") { go() }
        Button { chip() } label: {
            Text("Max").dsText(.label12).foregroundStyle(.white)
                .padding(.horizontal, 8)
                .background(DS.tint, in: Capsule())
        }
    }
}
"""

DIRTY_CAPSULE = """
struct Bad: View {
    var body: some View {
        Button { go() } label: {
            Text("Shield 0.10 ETH")
                .dsText(.body17).fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(DS.tint, in: Capsule(style: .continuous))
        }
    }
}
"""

DIRTY_GLASS = """
struct Bad2: View {
    var body: some View {
        Button { go() } label: {
            Text("Reconnect")
                .dsText(.body17).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(minHeight: 44)
                .dsGlassProminent(tint: DS.tint, cornerRadius: DS.Radius.pill)
        }
    }
}
"""

FLOATING_OK = """
struct Floating: View {
    var body: some View {
        Color.clear
            .safeAreaInset(edge: .bottom) {
                Button { enterDemo() } label: {
                    Text("Try a demo")
                        .dsText(.body17).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(minHeight: 48)
                        .dsGlassProminent(tint: DS.tint, cornerRadius: DS.Radius.pill)
                }
            }
    }
}
"""

FIGURE_OK = """
struct Figure: View {
    var body: some View {
        Button { pick() } label: {
            Rectangle().fill(DS.tint)
                .frame(maxWidth: .infinity, minHeight: 6)
        }
    }
}
"""


# The false positive this audit shipped with for one run, pinned. A bare
# toolbar button, then a filled one below it: a fixed line window blames the
# first for the second's fill.
NEIGHBOUR_OK = """
struct Neighbour: View {
    var body: some View {
        VStack {
            Button("Done") { dismiss() }
                .tint(DS.tint)
            DSSlabButton(title: "Connect", systemImage: "link") { go() }
                .frame(maxWidth: .infinity)
                .background(DS.tint, in: Capsule())
        }
    }
}
"""


# The gap this audit shipped with, pinned: SwiftUI's own prominent style is a
# full-width centered blue button too, and the first cut could not see it.
DIRTY_NATIVE = """
struct BadNative: View {
    var body: some View {
        Button {
            save()
        } label: {
            Text(String(localized: "Save"))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Self.mark)
    }
}
"""

# A prominent style on a CHIP is still not this species — width decides.
NATIVE_CHIP_OK = """
struct Chip: View {
    var body: some View {
        Button { go() } label: { Text("Add") }
            .buttonStyle(.borderedProminent)
    }
}
"""


def self_test():
    cases = [
        ("clean tree passes", CLEAN, 0),
        ("a bare button is not blamed for its neighbour's fill", NEIGHBOUR_OK, 0),
        ("catches a native .borderedProminent block", DIRTY_NATIVE, 1),
        ("a prominent CHIP is not a block", NATIVE_CHIP_OK, 0),
        ("catches a hand-rolled tint capsule", DIRTY_CAPSULE, 1),
        ("catches a hand-rolled glass pill", DIRTY_GLASS, 1),
        ("floating chrome is not a slab", FLOATING_OK, 0),
        ("a wordless figure is not a verb", FIGURE_OK, 0),
        ("a chip is not a block", CLEAN, 0),
    ]
    ok = True
    for name, src, want in cases:
        got = len(findings_in(src))
        mark = "✓" if got == want else "✗"
        if got != want:
            ok = False
        print(f"  {mark} {name} (expected {want}, got {got})")
    # The exemption must actually exempt, and only by NAME.
    if findings_in(DIRTY_CAPSULE, "SummonPrototype.swift"):
        print("  ✗ file exemption does not exempt")
        ok = False
    else:
        print("  ✓ file exemption exempts by name")
    if not findings_in(DIRTY_CAPSULE, "SomeScreen.swift"):
        print("  ✗ exemption leaks to every file")
        ok = False
    else:
        print("  ✓ exemption does not leak")
    return ok


def main():
    if "--self-test" in sys.argv:
        print("primary-verb-audit --self-test")
        if not self_test():
            print("primary-verb-audit: SELF-TEST FAILED")
            return 1
        print("primary-verb-audit: self-test OK")
        if len(sys.argv) > 2:
            return 0

    if not self_test_quiet():
        print("primary-verb-audit: SELF-TEST FAILED — not certifying the tree")
        return 1

    findings, scanned = [], 0
    for root in SOURCES:
        for dirpath, _, names in os.walk(root):
            for n in sorted(names):
                if not n.endswith(".swift"):
                    continue
                p = os.path.join(dirpath, n)
                scanned += 1
                with open(p, encoding="utf-8") as fh:
                    text = fh.read()
                for ln, label in findings_in(text, p):
                    findings.append((os.path.relpath(p, ROOT), ln, label))

    if findings:
        print("primary-verb-audit: a screen's filled verb is hand-rolled — "
              "use DSSlabButton / DSActVerb (prd §613)")
        for path, ln, label in findings:
            print(f"  {path}:{ln}  {label}")
        return 1
    print(f"primary-verb-audit: OK — {scanned} files; every full-width filled "
          f"verb is drawn by a component.")
    return 0


def self_test_quiet():
    import io
    import contextlib
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        return self_test()


if __name__ == "__main__":
    sys.exit(main())
