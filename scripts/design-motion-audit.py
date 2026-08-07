#!/usr/bin/env python3
"""Casberi design-motion audit (prd §299, 2026-08-04) — the design system's
first MECHANICAL check.

WHY THIS EXISTS. Every other load-bearing rule in this repo is enforced by a
script that runs in `verify.sh` — SwiftData liveness, keychain policy, network
receipts, the reach registry, the CloudKit schema, the catalog. Each was written
after a rule got re-broken from memory. The DESIGN SYSTEM had none, and it shows
in exactly the way you would predict:

  · fourteen data drawings shipped with no entrance at all, found by reading
    (prd §297/§298), not by any check;
  · `SettleIn` — reached by forty call sites through `settleIn`/`staggerIn`,
    including every feed row and the topic map's cells — ignored Reduce Motion
    from the day it shipped until 2026-08-04, so the single preference the whole
    motion system exists to respect was being ignored by the app's most-used
    entrance;
  · `RowEntrance`, the feed's own row entrance, had the same gap.

None of those is visible in a build, a screenshot or a screen sweep. A missing
entrance renders perfectly. An ignored Reduce Motion renders perfectly for
everyone who doesn't need it — which is everyone testing it.

TWO CHECKS.

  1. APPEAR-TRIGGERED MOTION HONOURS REDUCE MOTION. A `View` struct that starts
     an animation from its own `onAppear` — directly, or through a method it
     calls — must name `accessibilityReduceMotion` somewhere. This is scoped to
     ENTRANCES on purpose: an animation driven by data arriving, a gesture, or a
     value change is a different question with a different answer, and folding
     those in took the finding count from 10 to 27, which is how a lint gets
     turned off within a week (the liveness audit's own stated lesson).

  2. A PROPORTIONAL DRAWING HAS AN ENTRANCE. A `View` struct that sizes a shape
     from data — a width scaled by a value, a `trim` to a computed fraction, or
     a `Chart` — must carry one of the entrance modifiers, or hand the drawing
     to a component that does. "Every visualization should draw itself in some
     way" (user, 2026-08-03) is the rule; this is the form that survives being
     forgotten.

WHAT IT CANNOT SEE, stated so nobody trusts it further than it goes: it is
TEXTUAL and per-struct. It cannot tell a beautiful entrance from an ugly one,
cannot check timing or direction, and cannot follow more than one call hop from
`onAppear`. A struct that names `accessibilityReduceMotion` once and ignores it
everywhere passes check 1 — the same coarseness the liveness audit accepts
within an identifier, and for the same reason: the alternative is control-flow
analysis, and a check that fires on correct code gets deleted.

KNOWN_EXEMPT is the escape hatch. An entry is a conscious ruling, not a snooze.

Self-tests run FIRST and are not decoration: a check that cannot fail proves
nothing, so this demonstrates it catches each shape and clears the clean ones
before it certifies the tree.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = [
    "Casberi/Casberi/Design",
    "Casberi/Casberi/Screens",
    "Casberi/Casberi/GenUI",
    "Casberi/Casberi/Shell",
]

# --- Exemptions -------------------------------------------------------------
# Each entry is a ruling. "<file basename>:<struct>" -> why.
KNOWN_EXEMPT = {
    # RootShell's flagged `withAnimation` is not an entrance: it is the
    # `-openAppsDelay` DEBUG probe hook, which animates a delayed navigation
    # push so a headless recording can film the Apps door opening. It ships in
    # no release build and nobody using Reduce Motion will ever reach it.
    # A conscious ruling, not a snooze.
    "RootShell.swift:RootShell": "the -openAppsDelay probe hook, DEBUG-only",
    # FlowFigure's entrance is real and lives one struct UP: `FigureView` owns
    # the one `grown` clock every panel figure shares (with the Reduce Motion
    # collapse the first check demands) and hands it down as `t`, which
    # FlowFigure applies as `.opacity(t)`. Splitting a second entrance state
    # into the child would put two clocks on one tile — the exact double-deal
    # BerryRain's "ONE gesture deals ONE shower" lesson forbids. The audit
    # can't follow a value across a struct boundary, so: a conscious ruling.
    "AgentPanelGrid.swift:FlowFigure": "entrance is FigureView's shared clock, passed as t",
    # `size * 0.3` on the state badge is a FIXED proportion of the mark's own
    # size parameter, not a magnitude read off data — the same shape
    # `WalletFace`'s identicon blobs already draw (`d * 0.5`, `d * 0.42`),
    # which passes only because an unrelated `.animation(` elsewhere in that
    # struct happens to satisfy `has_entrance`. AssetMark has no such call to
    # borrow. A mark's badge size doesn't communicate anything by growing —
    # it's a fixed dot, always the same fraction of the disc it sits on.
    "AssetMark.swift:AssetMark": "badge size is a fixed proportion of `size`, not data",
}

ENTRANCE_TOKENS = (
    "chartWipe",
    "chartArrival",
    "settleIn",
    "staggerIn",
    "RowEntrance",
    "withAnimation",
    ".animation(",
    "ShareBar(",          # hands its drawing to the shared animated bar
    "MetricDisc(",        # ditto
    "TokenChartPlot(",    # ditto (its caller owns the reveal)
    "breathing()",
    "PredictionOddsBar(",
)

REDUCE_MOTION = "educeMotion"   # matches accessibilityReduceMotion / reduceMotion

# `View` AND `ViewModifier`. The first cut matched `\bView\b` only, which is a
# word boundary and therefore does NOT match `ViewModifier` — so the audit could
# not have caught `SettleIn` or `RowEntrance`, the two bugs that motivated it.
# Every shared entrance in this codebase is a ViewModifier; excluding them left
# the check unable to fail on its own motivating case, which is the one thing a
# check must never be.
STRUCT_RE = re.compile(r"(?:struct|private struct)\s+(\w+)\s*:\s*[^{]*\bView(?:Modifier)?\b[^{]*\{")
# The tail between `)` and `{` is captured so an `async` function can be
# excluded: `onAppear { Task { await sync() } }` is a DATA LOAD whose animation
# fires when the result lands, which is a different question with a different
# answer. Folding those in flagged two setup screens that are behaving
# correctly — and a lint that fires on correct code gets turned off.
FUNC_RE = re.compile(r"func\s+(\w+)\s*\([^)]*\)([^{]*)\{")
ONAPPEAR_BRACE_RE = re.compile(r"\.onAppear\s*\{")
ONAPPEAR_PERFORM_RE = re.compile(r"\.onAppear\(perform:\s*([\w.]+)\s*\)")
# A shape sized from data: a frame width multiplied by something, a trim to a
# non-literal-1 value, or a Swift Charts chart.
DRAWS_RE = [
    re.compile(r"\.frame\(width:[^)]*\*"),
    re.compile(r"\.trim\(from:\s*[^,]+,\s*to:\s*(?!1\))"),
    re.compile(r"\bChart\("),
]


def strip_comments(src: str) -> str:
    """Comments are prose about motion and would match every token."""
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    return re.sub(r"//[^\n]*", "", src)


def block_at(src: str, start: int) -> str:
    """The balanced-brace body beginning just past an opening brace."""
    depth, i = 1, start
    while i < len(src) and depth > 0:
        c = src[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        i += 1
    return src[start:i]


def view_structs(src: str):
    for m in STRUCT_RE.finditer(src):
        yield m.group(1), block_at(src, m.end()), src[: m.start()].count("\n") + 1


def animates_on_appear(body: str) -> bool:
    """Does this struct start an animation from its own onAppear?

    One call hop, deliberately: `onAppear { fire() }` with the animation inside
    `fire()` is the commonest shape in this codebase (it is what `SettleIn`,
    `RowEntrance` and every chart entrance do), and not resolving it would have
    missed the two findings that motivated this audit.
    """
    animating = {
        m.group(1)
        for m in FUNC_RE.finditer(body)
        if "async" not in m.group(2) and "withAnimation" in block_at(body, m.end())
    }
    for m in ONAPPEAR_BRACE_RE.finditer(body):
        inner = block_at(body, m.end())
        if "withAnimation" in inner:
            return True
        if any(re.search(r"\b%s\b" % re.escape(a), inner) for a in animating):
            return True
    for m in ONAPPEAR_PERFORM_RE.finditer(body):
        target = m.group(1).lstrip(".")
        if target in animating:
            return True
    return False


def draws_from_data(body: str) -> bool:
    return any(r.search(body) for r in DRAWS_RE)


def has_entrance(body: str) -> bool:
    return any(t in body for t in ENTRANCE_TOKENS)


def audit_text(src: str, label: str):
    """Both checks over one file's text. Returns a list of findings."""
    src = strip_comments(src)
    out = []
    for name, body, line in view_structs(src):
        key = "%s:%s" % (label, name)
        if key in KNOWN_EXEMPT:
            continue
        if REDUCE_MOTION not in body and animates_on_appear(body):
            out.append((line, name, "entrance animation ignores Reduce Motion"))
        if not has_entrance(body) and draws_from_data(body):
            out.append((line, name, "draws from data with no entrance"))
    return out


# --- Self-test --------------------------------------------------------------

CLEAN_GUARDED = """
struct Good: View {
    @Environment(\\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false
    var body: some View {
        Text("hi").opacity(on ? 1 : 0)
            .onAppear { guard !reduceMotion else { on = true; return }
                        withAnimation(.easeOut) { on = true } }
    }
}
"""

BAD_DIRECT = """
struct Bad: View {
    @State private var on = false
    var body: some View {
        Text("hi").opacity(on ? 1 : 0)
            .onAppear { withAnimation(.easeOut) { on = true } }
    }
}
"""

BAD_ONE_HOP = """
struct BadHop: View {
    @State private var on = false
    var body: some View { Text("hi").onAppear { fire() } }
    private func fire() { withAnimation(.easeOut) { on = true } }
}
"""

BAD_PERFORM = """
struct BadPerform: View {
    @State private var on = false
    var body: some View { Text("hi").onAppear(perform: fire) }
    private func fire() { withAnimation(.easeOut) { on = true } }
}
"""

BAD_NO_ENTRANCE = """
struct Bar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { geo in
            Capsule().frame(width: geo.size.width * fraction)
        }
    }
}
"""

CLEAN_DELEGATED = """
struct Delegates: View {
    let fraction: Double
    let reduceMotion: Bool
    var body: some View { ShareBar(fraction: fraction, reduceMotion: reduceMotion) }
}
"""

CLEAN_STATIC_SHAPE = """
struct Glyph: View {
    var body: some View {
        Circle().frame(width: 24, height: 24)
    }
}
"""

# An interaction-driven animation is NOT an entrance and must not be flagged —
# this is the case that took the count from 10 to 27 when folded in.
CLEAN_INTERACTION_ONLY = """
struct Tappable: View {
    @State private var open = false
    var body: some View {
        Button("go") { withAnimation { open.toggle() } }
    }
}
"""

# Comments talking about motion must not clear a struct that has none.
BAD_COMMENT_ONLY = """
struct Commented: View {
    let fraction: Double
    // We deliberately use withAnimation and settleIn elsewhere in the app.
    var body: some View {
        GeometryReader { geo in Rectangle().frame(width: geo.size.width * fraction) }
    }
}
"""


# The shape of every shared entrance in this app, and the one the first cut of
# this audit was structurally unable to see.
BAD_VIEWMODIFIER = """
struct Entrance: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content.opacity(on ? 1 : 0).onAppear { reveal() }
    }
    private func reveal() { withAnimation(.easeOut) { on = true } }
}
"""


# An async load whose animation fires when the RESULT lands is not an entrance.
CLEAN_ASYNC_LOAD = """
struct Loader: View {
    @State private var rows: [Int] = []
    var body: some View { Text("x").onAppear { Task { await sync() } } }
    private func sync() async {
        let fetched = await get()
        withAnimation { rows = fetched }
    }
}
"""


def self_test() -> bool:
    cases = [
        ("a guarded entrance passes", CLEAN_GUARDED, 0),
        ("an unguarded ViewModifier entrance is caught", BAD_VIEWMODIFIER, 1),
        ("an async data load is not an entrance", CLEAN_ASYNC_LOAD, 0),
        ("an unguarded entrance is caught", BAD_DIRECT, 1),
        ("an entrance one call hop away is caught", BAD_ONE_HOP, 1),
        ("onAppear(perform:) is caught", BAD_PERFORM, 1),
        ("a proportional bar with no entrance is caught", BAD_NO_ENTRANCE, 1),
        ("a drawing delegated to a shared component passes", CLEAN_DELEGATED, 0),
        ("a fixed-size shape is not a drawing", CLEAN_STATIC_SHAPE, 0),
        ("interaction-only animation is not an entrance", CLEAN_INTERACTION_ONLY, 0),
        ("a comment naming the modifiers doesn't clear the struct", BAD_COMMENT_ONLY, 1),
    ]
    ok = True
    print("Self-test")
    for name, src, expected in cases:
        found = len(audit_text(src, "selftest.swift"))
        if found == expected:
            print("  ✓ %s" % name)
        else:
            print("  ✗ %s (expected %d finding(s), got %d)" % (name, expected, found))
            ok = False
    return ok


def main() -> int:
    if not self_test():
        print("\ndesign-motion-audit: ✗ self-test failed — the audit itself is broken")
        return 1

    findings = []
    for root in SOURCES:
        for path in sorted((ROOT / root).rglob("*.swift")):
            rel = path.relative_to(ROOT)
            for line, name, why in audit_text(path.read_text(), path.name):
                findings.append((str(rel), line, name, why))

    print("")
    if not findings:
        print("design-motion-audit: OK — every entrance honours Reduce Motion "
              "and every data drawing has one.")
        return 0

    print("design-motion-audit: %d finding(s)\n" % len(findings))
    for rel, line, name, why in findings:
        print("  %s:%d  %s — %s" % (rel, line, name, why))
    print("\nFix, or add \"<file>:<struct>\" to KNOWN_EXEMPT with a reason.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
