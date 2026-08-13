#!/usr/bin/env python3
"""Casberi accessibility audit (2026-08-13) — the VoiceOver and touch-target
half of the design system.

WHY THIS EXISTS. The systemic accessibility layers in this app are already good
and already mechanical: Dynamic Type rides one ramp (`Shared/Typography.swift`)
with `design-ramp-audit.py` failing the build on a frozen size, Reduce Motion
has `design-motion-audit.py`, Increase Contrast has `ContrastStore` feeding
measured >=4.5:1 token variants, and the honesty law ("a change that rounds to
zero has no direction") means colour is never the only voice for money.

What had NO check was the part that is invisible to every other one: whether a
control announces itself and whether it can be hit. The 2026-08-13 sweep found
three shapes, and the thing they share is that each renders perfectly and works
perfectly for whoever is testing it:

  · SEVEN room heads whose whole face was `contentShape` + `onTapGesture` and
    nothing else. That pair carries no trait and no action, so VoiceOver never
    announced them as activatable and a double-tap did nothing. On four of the
    seven (Peer, Cursor, App Store Connect, Railgun) that was a DEAD END rather
    than an inconvenience: those cards draw `drawn.dropFirst()` on purpose —
    "the lead is already in the headline, and repeating its name directly
    underneath is the card arguing with itself" — so the card's single most
    important destination was reachable by touch and pointer and by nothing
    else.

  · NINE icon buttons under the 44pt floor, in a codebase that had already
    written that rule down in three separate places (`DS.Face.shelf`'s own
    comment, `AgentBar`'s satellite glyph, the catalogue door's 2026-07-26
    lesson). The miss lands on whoever aims least well, which is nobody who
    ships it.

  · TWO icon-only buttons with no label, where VoiceOver falls back to reading
    the SF Symbol's own name.

THREE CHECKS, all static, none needing a build.

  1. AN ICON-ONLY BUTTON IS LABELLED. A `Button` whose label draws an
     `Image(systemName:)` and no words must carry an `accessibilityLabel`.

  2. A WHOLE-FACE TAP TARGET SAYS SO. `contentShape(...)` + `onTapGesture` must
     be joined by `dsTapCard()`, `dsCardLead(...)`, or an explicit
     trait/element/action. The gesture is a complete control for touch and for a
     pointer and carries nothing for anyone else.

  3. AN ICON-ONLY BUTTON IS HITTABLE. Same buttons as check 1, held to
     `DS.Hit.min` — via `dsTapTarget()`, an explicit frame at or above the
     floor, or a named size token that already encodes it.

THE FLOOR IS READ OUT OF `DesignTokens.swift`, never hardcoded here. A lint that
keeps its own copy of the number it is enforcing is one edit away from enforcing
a value the app no longer uses — the same reasoning that makes
`swiftdata-liveness-audit.py` parse `Thing`'s stored properties at run time and
`secret-scan-selftest.py` read its regexes out of the shipped source.

FOUR DELIBERATE NON-CHECKS, so this can't become a lint that cries wolf (the
liveness audit's stated lesson, and `design-motion-audit`'s):

  · It never judges a label's QUALITY. It cannot tell a true sentence from a
    false one, and a check that guesses at wording gets argued with and then
    disabled.
  · It never demands a label on a decorative mark. `BridgeIcon`, `KindGlyph`,
    `CasberiMark` and friends draw identity beside text that already says the
    same thing; labelling them is VoiceOver noise, not access.
  · It never flags a Button that carries WORDS. Its target is as wide as its
    text and its label is its text — both checks are satisfied by construction.
  · It never asks a DRAWING to be labelled. The sweep checked this directly and
    the answer was that the design law already covers it: every informative
    drawing in the app is either labelled (`GnosisPayRoomCard.monthStrip`,
    `SafeRoomCard.ring`) or hidden beside text stating the same fact (the
    Uniswap range bar beside its "Idle 3d" pill, the melt bar beside "N votes
    left", the deposit share beside its printed percent). The lead `ShareBar`s
    are always exactly full — `top` is the lead's own count — so they are scale
    anchors carrying no information, and hiding them is correct. Encoding "a
    drawing must speak" here would fire on all of those and be wrong every time.

Usage:  accessibility-audit.py [--self-test]
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = [
    os.path.join(ROOT, "Casberi", "Casberi"),
    os.path.join(ROOT, "Casberi", "Shared"),
]
TOKENS = os.path.join(ROOT, "Casberi", "Casberi", "Design", "DesignTokens.swift")

# A conscious ruling per entry, never a snooze. "file:symbol — why".
KNOWN_EXEMPT = {
    # Nothing yet. An entry here is a statement that the control is genuinely
    # unreachable-by-design or genuinely decorative, with the reason written out.
}

# Size expressions that already encode the floor, so an explicit number is not
# required. `DS.Face.shelf` states in its own doc that it is "floored by the
# 44pt minimum touch target"; the rest are full-width or parent-sized.
NAMED_SIZES = re.compile(
    r"DS\.Hit\.|DS\.Face\.shelf|DS\.Mark\.tile|DS\.Mark\.hero|faceSize|slotHeight"
    r"|doorSide|\.infinity|maxWidth:|rosterSlotWidth|DS\.Radius\.widget"
)

# What satisfies check 2 — any of these means the tap was declared, not just felt.
TAP_DECLARED = re.compile(
    r"dsTapCard\(|dsCardLead\(|accessibilityAddTraits|accessibilityElement"
    r"|accessibilityAction|accessibilityRepresentation"
)

WORDS = re.compile(r"\bText\(|\bLabel\(|dsText|LocalizedStringKey|String\(localized:")


# --------------------------------------------------------------------------
# Swift-ish scanning. Comments and string bodies are blanked so a rule can
# never be satisfied — or tripped — by prose describing it. Three audits in
# this repo have now been caught by exactly that (Obsidian, Cursor, the
# on-device inference gate), so it is the default here rather than a patch.
# --------------------------------------------------------------------------

def strip_noise(src: str) -> str:
    out, i, n = [], 0, len(src)
    while i < n:
        if src.startswith("//", i):
            j = src.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
        elif src.startswith("/*", i):
            j = src.find("*/", i)
            j = n if j < 0 else j + 2
            out.append(re.sub(r"[^\n]", " ", src[i:j]))
            i = j
        elif src[i] == '"':
            j = i + 1
            while j < n and src[j] != '"' and src[j] != "\n":
                j += 2 if src[j] == "\\" else 1
            # keep the quotes, blank the body: `Text("Open")` still reads as words
            out.append('"' + " " * max(0, j - i - 1) + ('"' if j < n else ""))
            i = min(j + 1, n)
        else:
            out.append(src[i])
            i += 1
    return "".join(out)


def brace_span(src: str, open_idx: int) -> int:
    depth = 0
    for k in range(open_idx, len(src)):
        if src[k] == "{":
            depth += 1
        elif src[k] == "}":
            depth -= 1
            if depth == 0:
                return k + 1
    return len(src)


def modifier_chain(src: str, start: int) -> str:
    """The `.foo(...)` run following a closing brace — a view's own modifiers."""
    k, out = start, []
    while k < len(src):
        m = re.match(r"\s*(\.\w+(\([^()]*(\([^()]*\)[^()]*)*\))?)", src[k:])
        if not m or not m.group(1).strip():
            break
        out.append(m.group(1))
        k += m.end()
    return "".join(out)


def button_bodies(src: str):
    """Yield (line, body, chain) per Button.

    BODY and CHAIN stay separate, and that separation is load-bearing rather
    than tidiness. Folding them together makes `accessibilityLabel(Text("Watch"))`
    read as the button HAVING WORDS, which skips it as a text button — so every
    correctly-labelled icon button silently escaped the size check, which is the
    entire population the size check exists for. Caught by this audit's own
    self-test before it ever ran (`retriever-selftest`'s lesson: a fixture that
    passes for the wrong reason proves nothing).
    """
    for m in re.finditer(r"\bButton\s*\{", src):
        try:
            o = src.index("{", m.start())
        except ValueError:
            continue
        e = brace_span(src, o)
        body = src[o:e]
        tail = src[e:e + 4000]
        lm = re.match(r"\s*label:\s*\{", tail)
        if lm:
            lo = e + tail.index("{", lm.start())
            e = brace_span(src, lo)
            body = src[lo:e]
        yield src[:m.start()].count("\n") + 1, body, modifier_chain(src, e)


def view_struct_spans(src: str):
    """(start, end) for each `struct X: View` — the scope a card's tap lives in."""
    spans = []
    for m in re.finditer(r"struct\s+\w+\s*:\s*[^{\n]*\bView\b[^{\n]*\{", src):
        o = src.index("{", m.start())
        spans.append((m.start(), brace_span(src, o)))
    return spans


def hit_floor() -> int:
    """`DS.Hit.min`, read from the token rather than kept as a copy here."""
    try:
        src = open(TOKENS, encoding="utf-8").read()
    except OSError:
        return 44
    m = re.search(r"enum Hit\s*\{[^}]*?static let min:\s*CGFloat\s*=\s*(\d+)", src, re.S)
    return int(m.group(1)) if m else 44


# --------------------------------------------------------------------------
# The checks
# --------------------------------------------------------------------------

def audit_text(path: str, raw: str, floor: int):
    """Returns a list of (check, line, message)."""
    src = strip_noise(raw)
    found = []

    spans = view_struct_spans(src)

    for line, body, chain in button_bodies(src):
        whole = body + chain
        if "Image(systemName:" not in body:
            continue
        if WORDS.search(body):
            continue  # a button with words: labelled and wide by construction
        key = f"{os.path.basename(path)}:{line}"
        if key in KNOWN_EXEMPT:
            continue

        if "accessibilityLabel" not in whole:
            found.append(("unlabelled-icon-button", line,
                          "icon-only Button with no accessibilityLabel — "
                          "VoiceOver falls back to the SF Symbol's name"))

        if "dsTapTarget" not in whole and not NAMED_SIZES.search(whole):
            sizes = [int(x) for x in re.findall(r"\.frame\((?:width|height|minWidth|minHeight):\s*(\d+)", whole)]
            if not any(s >= floor for s in sizes):
                biggest = max(sizes) if sizes else 0
                found.append(("small-tap-target", line,
                              f"icon-only Button's target is {biggest or 'the glyph'}pt, "
                              f"under the {floor}pt floor — add dsTapTarget()"))

    for m in re.finditer(r"\.onTapGesture\s*(\{|\()", src):
        if src[m.end() - 1] == "{":
            e = brace_span(src, m.end() - 1)
        else:
            e = src.find(")", m.end()) + 1
        chain = modifier_chain(src, e)
        enclosing = next((s for s in spans if s[0] < m.start() < s[1]), None)
        # TWO lookups with two different reaches, on purpose.
        #
        # The NEAR one is the immediate chain plus a short lookback, for a trait
        # or element declared right on the gesture's own view. It is clamped to
        # the enclosing `struct … : View` so a neighbouring view's declaration
        # can never satisfy this one — the file-scope decay the liveness audit
        # hit on 2026-08-02, and not theoretical here: this audit's own
        # `DIRTY_LEAD_ELSEWHERE` fixture ran green against a genuinely
        # undeclared card because the struct above it sat inside the window.
        #
        # The WIDE one looks for `dsCardLead` anywhere in the enclosing struct,
        # because that modifier deliberately lives on the HEADLINE rather than
        # on the container (a `Text` is a real accessibility element; a
        # container is not — see its own doc), and in every room head that is
        # fifty lines above the gesture it answers for. Struct-scoped, never
        # file-scoped, for the same reason as above.
        near_floor = max(0, m.start() - 500)
        if enclosing:
            near_floor = max(near_floor, enclosing[0])
        back = src[near_floor:m.start()]
        if "contentShape" not in back:
            continue  # not a whole-face target; a tap on a labelled row is fine
        if TAP_DECLARED.search(chain) or TAP_DECLARED.search(back):
            continue
        if enclosing and "dsCardLead(" in src[enclosing[0]:enclosing[1]]:
            continue
        line = src[:m.start()].count("\n") + 1
        key = f"{os.path.basename(path)}:{line}"
        if key in KNOWN_EXEMPT:
            continue
        found.append(("untraited-tap-target", line,
                      "contentShape + onTapGesture with no trait or action — "
                      "invisible to VoiceOver; add dsTapCard() or dsCardLead()"))

    return found


def walk():
    for root in SOURCES:
        for dp, _, fns in os.walk(root):
            for fn in sorted(fns):
                if fn.endswith(".swift"):
                    yield os.path.join(dp, fn)


# --------------------------------------------------------------------------
# Self-test — REQUIRED by verify.sh of every discovered audit. A check that
# cannot demonstrate it catches anything certifies nothing.
# --------------------------------------------------------------------------

DIRTY_UNLABELLED = """
struct A: View {
    var body: some View {
        Button { close() } label: {
            Image(systemName: "xmark")
                .dsGlyph(15)
                .frame(width: 44, height: 44)
        }
    }
}
"""

DIRTY_SMALL = """
struct B: View {
    var body: some View {
        Button { go() } label: {
            Image(systemName: "star")
                .frame(width: 32, height: 32)
        }
        .accessibilityLabel(Text("Watch"))
    }
}
"""

DIRTY_TAP = """
struct C: View {
    var body: some View {
        card
            .contentShape(Rectangle())
            .onTapGesture { open() }
    }
}
"""

CLEAN = """
struct D: View {
    var body: some View {
        Button { close() } label: {
            Image(systemName: "xmark")
                .frame(width: 32, height: 32)
                .dsTapTarget(Circle())
        }
        .accessibilityLabel(Text("Close"))

        Button { go() } label: {
            Image(systemName: "star")
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(Text("Watch"))

        Button { pick() } label: {
            Image(systemName: "plus")
            Text("Add a wallet")
        }

        card
            .contentShape(Rectangle())
            .onTapGesture { open() }
            .dsTapCard()

        headline
            .contentShape(Rectangle())
            .onTapGesture { open() }
            .dsCardLead(Text("Opens this rail")) { open() }
    }
}
"""

# The shape the seven room heads actually ship: the container's gesture stays
# bare and the HEADLINE carries the verb, because a `Text` is a real
# accessibility element and a container is not.
#
# The filler is NOT padding for its own sake. In the real cards the headline sits
# ~50 lines above the container's gesture, so this fixture must be far enough
# apart that the NEAR lookback cannot reach it — otherwise it passes on the
# wrong lookup and the struct-scoped one is never exercised at all.
CLEAN_CARD_LEAD = """
struct F: View {
    var body: some View {
        VStack {
            Text(Room.headline(room))
                .dsCardLead(Text("Opens this rail")) { open() }

            Text(Room.note(room))
                .dsText(.subhead13)
                .foregroundStyle(DS.textSecondary)
                .padding(.top, DS.Space.s1)
            Text(Room.second(room))
                .dsText(.subhead13)
                .foregroundStyle(DS.textSecondary)
                .padding(.top, DS.Space.s1)
            Text(Room.third(room))
                .dsText(.subhead13)
                .foregroundStyle(DS.textSecondary)
                .padding(.top, DS.Space.s1)
            Text(Room.fourth(room))
                .dsText(.subhead13)
                .foregroundStyle(DS.textSecondary)
                .padding(.top, DS.Space.s1)
            Text(Room.fifth(room))
                .dsText(.subhead13)
                .foregroundStyle(DS.textSecondary)
                .padding(.top, DS.Space.s1)
            rows
        }
        .contentShape(Rectangle())
        .onTapGesture { open() }
    }
}
"""

# ...and the same exemption must NOT leak across struct boundaries. Struct G is
# declared correctly; struct H is not, and lives in the same file.
DIRTY_LEAD_ELSEWHERE = """
struct G: View {
    var body: some View {
        Text(Room.headline(room))
            .dsCardLead(Text("Opens this rail")) { open() }
    }
}

struct H: View {
    var body: some View {
        card
            .contentShape(Rectangle())
            .onTapGesture { open() }
    }
}
"""

# The prose trap, earned three times in this repo already: a file that DOCUMENTS
# the rule by naming the very thing it forbids must not trip its own check.
CLEAN_PROSE = """
struct E: View {
    /// Never write `.contentShape(Rectangle())` then `.onTapGesture { }` with
    /// no trait — and never leave an `Image(systemName:)` Button unlabelled.
    var body: some View {
        Button { go() } label: {
            Image(systemName: "star")
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(Text("Watch"))
    }
}
"""


def self_test() -> bool:
    floor = 44
    cases = [
        ("dirty: unlabelled icon button", DIRTY_UNLABELLED, {"unlabelled-icon-button"}),
        ("dirty: sub-floor target", DIRTY_SMALL, {"small-tap-target"}),
        ("dirty: untraited whole-face tap", DIRTY_TAP, {"untraited-tap-target"}),
        ("dirty: card lead in a DIFFERENT struct", DIRTY_LEAD_ELSEWHERE, {"untraited-tap-target"}),
        ("clean: all three shapes done right", CLEAN, set()),
        ("clean: headline carries the card's verb", CLEAN_CARD_LEAD, set()),
        ("clean: prose naming the forbidden shapes", CLEAN_PROSE, set()),
    ]
    ok = True
    for name, text, expected in cases:
        kinds = {k for k, _, _ in audit_text("fixture.swift", text, floor)}
        if kinds != expected:
            print(f"  SELF-TEST FAIL  {name}: expected {expected or '{}'}, got {kinds or '{}'}")
            ok = False
        else:
            print(f"  ok  {name}")

    # The floor is read, not assumed: prove the parse finds a real number.
    parsed = hit_floor()
    if parsed != 44:
        print(f"  SELF-TEST FAIL  DS.Hit.min parsed as {parsed}, expected 44")
        ok = False
    else:
        print("  ok  DS.Hit.min read out of DesignTokens.swift")

    # And prove the floor is load-bearing rather than decorative: at a floor of
    # 24 the 32pt button is fine, so a passing fixture must be able to flip.
    kinds = {k for k, _, _ in audit_text("fixture.swift", DIRTY_SMALL, 24)}
    if "small-tap-target" in kinds:
        print("  SELF-TEST FAIL  floor is ignored — 32pt flagged against a 24pt floor")
        ok = False
    else:
        print("  ok  the floor actually drives the size check")

    return ok


def main() -> int:
    if "--self-test" in sys.argv:
        print("accessibility-audit self-test")
        good = self_test()
        print("SELF-TEST PASS" if good else "SELF-TEST FAIL")
        return 0 if good else 1

    floor = hit_floor()
    findings = []
    for path in walk():
        raw = open(path, encoding="utf-8", errors="replace").read()
        for kind, line, msg in audit_text(path, raw, floor):
            findings.append((os.path.relpath(path, ROOT), line, kind, msg))

    if not findings:
        print(f"accessibility audit: clean ({floor}pt floor)")
        return 0

    print(f"accessibility audit: {len(findings)} finding(s), {floor}pt floor\n")
    for path, line, kind, msg in sorted(findings):
        print(f"  {path}:{line}")
        print(f"      [{kind}] {msg}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
