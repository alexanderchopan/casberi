#!/usr/bin/env python3
"""The devnet send console fits on the screen — as a sum, not as a memory.

WHY THIS EXISTS (prd §548, 2026-09-01).

Reported as *"the new send module is good, but how can we improve it? It needs
to fit all on the screen so user doesn't have to scroll"*, and the diagnosis is
arithmetic rather than taste. Measured off a 3× screenshot of the shipping
build (iPhone 16 Pro Max, 440×956pt), the room's chrome above the card comes to
545pt — safe area, source chips, venue rail, `DSRoomChassis.visualSlot` (210)
and the fused rail slab (111) — and the card came to 601. Everything from the
keypad's fourth row down was below the fold: the `. 0 ⌫` row, the Send button
and the footnote under it, on the one surface in this app whose entire content
is a control you are meant to complete in one go.

The user ruled the chrome untouchable — *"we can't make the slot shorter
because it needs to be that same size on all the other screens and wallets"* —
so the console is what gives, and once its height is a budget somebody has to
keep it.

**THE FAILURE IS INVISIBLE, which is the only reason this is a script.** A card
that overflows its room renders perfectly: every element is drawn, correctly,
in the right order, and the ones past the fold simply continue below it. No
warning, no clipping, no log line. A build is green, every static audit is
green, and the screen sweep photographs a console whose button is off screen
and certifies it. The one thing that can see it is a sum, and a sum in a
comment is a sum nobody re-adds.

FIVE CHECKS.

  1. THE SUM IS UNDER THE BUDGET. `DevnetConsole.height <= .budget`, evaluated
     from the constants in the source, at iOS spacing. The budget is the
     SMALLEST phone's allowance, not the largest — §548's first pass budgeted
     against a 956pt device and landed a console that fitted exactly one screen
     size.
  2. THE RECIPIENT ROW HOLDS THE HIT FLOOR. `recipientRow` is `DS.Hit.min`,
     checked SEPARATELY from the sum on purpose: it is the one remaining block
     that could be shaved to buy a few points, and it is a control.
  3. THE VIEWS READ THE CONSTANTS. A sum is only true if the glass agrees with
     it, so the recipient row's frame and the verb's padding must come from
     `DevnetConsole` and not from literals.
  4. NEITHER CARD HAND-ROLLS THE VERB. Both used to spell the same button out,
     identically — and a second copy of a control carrying 42 of the budget's
     points is how the sum quietly stops being true. One `DevnetSendVerb`.
  5. NEITHER FORM REGROWS A HEAD. The 46pt card head is what §548 spent to make
     the console fit; a head above the form is the whole saving back. Checked
     against the FORM only — the sent state keeps its head, and should.
  6. THE KEYBOARD HAS A WAY DOWN (§548a). `.decimalPad` HAS NO RETURN KEY, so a
     field raised without a keyboard toolbar cannot be dismissed from the
     keyboard at all, and a tap outside is unreliable inside a scrolling
     `List` — leaving a pad somebody cannot put away, over the Send button it
     is covering. Both cards must carry `devnetAmountToolbar`, and the figure
     must actually ask for the decimal pad: a plain keyboard over an amount
     field is a letter keyboard on a money control.
  7. THE DEMO CAN REACH IT, AND CANNOT SEND FROM IT (§548b). Both halves, and
     both are load-bearing in opposite directions. The gate must answer in a
     demo — the vibenet card wanted an account naming THIS PHONE's key and the
     Hegotá card wanted a key in this phone's defaults, so the room's DEFAULT
     scope drew nothing in the tour that is the first tap of onboarding, from
     the day each console shipped. And `send()` must refuse in a demo before it
     touches a key: a real signature raises Face ID and a real broadcast puts a
     transaction on a public devnet, from a screen whose own banner says none of
     this is yours.

     **This is the check no other one in the repo can stand in for.** The demo
     audits ask whether a SEAT is furnished (`demo-selftest` D/E/G/M), whether a
     source has rows, whether a room HEAD composes (`verify.sh`'s room-head
     coverage) and which figure kinds draw — all of which passed over an empty
     Home for months, because this is a SCOPE'S CONTENT gated on a device
     credential, which is none of those things.
  8. THE KEYPAD DOES NOT COME BACK.
  9. NEITHER HOME EVER DRAWS NOTHING (§548d). Each card must carry a no-key
     branch, because Home's entire content IS the console: gate it on a
     credential and a phone without one gets a blank scope with no words and no
     door — which is what made the console impossible to find on a fresh
     simulator, and is indistinguishable from a bug. 176pt is the whole §548a saving and it is
     the obvious thing to restore the next time this screen is redesigned on a
     Pro Max. If it does come back, it comes back with a new budget and a new
     ruling, not quietly.

WHAT IT DELIBERATELY DOES NOT DO (a lint that cries wolf gets turned off within
a week):

  • It does not certify text metrics. `figureLine`/`verbLine`/`sublineRow` are
    a face's drawn height rounded UP, which makes the budget stricter than the
    glass; whether Figtree draws 40pt in 47 or 49 is a device question. What
    this catches is a STRUCTURAL addition — another row, a wider gap, a second
    button — which is how the 601pt card got to 601 in the first place.
  • It says nothing about Dynamic Type. Every term scales, so at an
    accessibility size the console is taller than any budget; that is true of
    every fixed-height surface in this app and is not this check's question.
  • It says nothing about smaller phones. The chrome is ~545pt on every iPhone
    because none of its four terms scales with screen height, so the room
    leaves 307pt on an 852pt device and the console does not fit there. That
    ceiling is stated in `DevnetConsole`'s own header rather than hidden here,
    because the only remaining slack is in the chrome and §548 rules it out.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONSOLE = "Casberi/Casberi/Screens/DevnetSendConsole.swift"
CARDS = ["Casberi/Casberi/Screens/VibenetSendCard.swift",
         "Casberi/Casberi/Screens/HegotaSendCard.swift"]

# iOS spacing, the platform the budget is measured on. Mac Catalyst is tighter
# on s2–s4 (DS.Space's own note), so a sum that fits here fits there.
TOKENS = {"DS.Space.s1": 4.0, "DS.Space.s2": 10.0, "DS.Space.s3": 14.0,
          "DS.Space.s4": 18.0, "DS.Space.s6": 24.0, "DS.Hit.min": 44.0}

CONST = re.compile(r"static let (\w+)(?::\s*CGFloat)?\s*=\s*([A-Za-z0-9_.]+)\s*$", re.M)

# Check 3: what each view must read from the budget rather than spell itself.
# The pair is (the constant, a phrase proving it is used where it must be).
WIRED = [
    ("recipientRow", r"\.frame\(height:\s*DevnetConsole\.recipientRow\)"),
    ("verbPad", r"\.padding\(\.vertical,\s*DevnetConsole\.verbPad\)"),
    ("figureGap", r"VStack\(spacing:\s*DevnetConsole\.figureGap\)"),
]

# Check 5: a head is a `heading17`/`heading22` title inside the FORM. The sent
# state's head is fine and is named so it is skipped rather than exempted by a
# looser pattern.
HEAD_TIER = re.compile(r"\.dsText\(\.heading(?:17|22|28|34)\)")


def strip_comments(text: str) -> str:
    """Every file here documents this rule by naming what it must not do."""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return "\n".join(re.sub(r"//.*$", "", line) for line in text.splitlines())


def constants(code: str) -> dict[str, float]:
    out: dict[str, float] = {}
    for name, raw in CONST.findall(code):
        if raw in TOKENS:
            out[name] = TOKENS[raw]
        else:
            try:
                out[name] = float(raw)
            except ValueError:
                pass
    return out


def form_body(code: str) -> str:
    """The `form` computed property, up to the next `private var`/`func`."""
    m = re.search(r"private var form: some View \{", code)
    if not m:
        return ""
    rest = code[m.end():]
    stop = re.search(r"\n    (?:private |static |@|/// )?(?:var|func) ", rest)
    return rest[:stop.start()] if stop else rest


def send_body(code: str) -> str:
    """The `send` method, up to the next declaration at the same indent."""
    m = re.search(r"private func send\(\) \{", code)
    if not m:
        return ""
    rest = code[m.end():]
    stop = re.search(r"\n    (?:private |static |@|/// )?(?:var|func) ", rest)
    return rest[:stop.start()] if stop else rest


def audit(console: str, cards: dict[str, str]) -> list[str]:
    code = strip_comments(console)
    c = constants(code)
    out: list[str] = []

    need = ["cardPadding", "blockGap", "recipientRow", "figureLine", "figureGap",
            "sublineRow", "verbLine", "verbPad", "budget"]
    missing = [n for n in need if n not in c]
    if missing:
        return [f"DevnetConsole is missing {', '.join(missing)} — the budget "
                f"cannot be summed, so nothing below is certified"]

    height = (2 * c["cardPadding"] + c["recipientRow"] + 2 * c["blockGap"]
              + c["figureLine"] + c["figureGap"] + c["sublineRow"]
              + c["verbLine"] + 2 * c["verbPad"])

    # 1
    if height > c["budget"]:
        out.append(f"the console sums to {height:g}pt against a budget of "
                   f"{c['budget']:g} — it is {height - c['budget']:g}pt past "
                   f"the bottom of the room it draws in (prd §548)")
    # 2
    if c["recipientRow"] < 44:
        out.append(f"recipientRow is {c['recipientRow']:g} — below the 44pt "
                   f"hit floor. A control is not where the height comes from.")
    # 8 (console half) and 6
    if ".keyboardType(.decimalPad)" not in code:
        out.append("the amount field does not ask for the decimal pad — a "
                   "letter keyboard over a money control (§548a)")
    if "DevnetSendKeypad" in code:
        out.append("the custom keypad is back — 176pt, and the whole of "
                   "§548a's saving. It returns with a new budget or not at all")
    # 3
    for name, pattern in WIRED:
        if not re.search(pattern, code):
            out.append(f"nothing reads DevnetConsole.{name} — the sum says one "
                       f"thing and the glass draws another")
    for path, text in cards.items():
        body = form_body(strip_comments(text))
        if not body:
            out.append(f"{path}: no `form` — check 4 and 5 certify nothing here")
            continue
        # 4
        if "DevnetSendVerb" not in body:
            out.append(f"{path}: the form hand-rolls its send button — use "
                       f"DevnetSendVerb, or its 42pt leaves the sum")
        # 5
        if HEAD_TIER.search(body):
            out.append(f"{path}: the form grew a head back — that is the 46pt "
                       f"§548 spent to make the console fit")
        if re.search(r"VStack\(spacing: DS\.Space\.", body):
            out.append(f"{path}: the form spaces its blocks with a raw token — "
                       f"use DevnetConsole.blockGap, which the sum is built on")
        # 6 (card half)
        if "devnetAmountToolbar" not in body:
            out.append(f"{path}: the amount field has no keyboard toolbar — "
                       f".decimalPad has no return key, so nothing dismisses it")
        # 7 — both halves, against the WHOLE card rather than the form
        card = strip_comments(text)
        if "DemoMode.isActive" not in card:
            out.append(f"{path}: the console is invisible in the demo — its "
                       f"gate wants a device credential a tour cannot have, so "
                       f"the room's default scope draws nothing there (§548b)")
        send = send_body(card)
        if send and "DemoMode.isActive" not in send:
            out.append(f"{path}: send() does not refuse in the demo — a tour "
                       f"would raise Face ID and broadcast to a public devnet")
    return out


# ── fixtures ────────────────────────────────────────────────────────────
CLEAN_CONSOLE = """
enum DevnetConsole {
    static let cardPadding = DS.Space.s4
    static let blockGap = DS.Space.s3
    static let recipientRow = DS.Hit.min
    static let figureLine: CGFloat = 48
    static let figureGap = DS.Space.s1
    static let sublineRow: CGFloat = 22
    static let verbLine: CGFloat = 22
    static let verbPad = DS.Space.s3
    static let budget: CGFloat = 266
}
struct DevnetSendFigure: View {
    var body: some View {
        VStack(spacing: DevnetConsole.figureGap) {
            TextField("", text: $amount).keyboardType(.decimalPad)
        }
    }
}
struct DevnetSendToRow: View {
    var body: some View { h.frame(height: DevnetConsole.recipientRow) }
}
struct DevnetSendVerb: View {
    var body: some View { l.padding(.vertical, DevnetConsole.verbPad) }
}
"""
CLEAN_CARD = """
struct A: View {
    private var form: some View {
        VStack(spacing: DevnetConsole.blockGap) {
            DevnetSendToRow(from: a, address: b, name: c, preview: d, onTap: {})
            DevnetSendFigure(amount: $amount, focus: $amountFocused, tint: t, dim: e) { u } subline: { v }
            DevnetSendVerb(title: sendLabel, armed: canSend, busy: busy, tint: t) { send() }
        }
        .devnetAmountToolbar($amountFocused)
    }
    private var sentHead: some View { Text("Sent").dsText(.heading17) }
    private var sender: String? { Key.address() ?? (DemoMode.isActive ? Fixture.demo : nil) }
    private func send() {
        guard !DemoMode.isActive else { errorText = "Nothing is sent in the demo."; return }
        Task { try await Bridge.send() }
    }
    private var recipientName: String? { nil }
}
"""


def swap(text: str, old: str, new: str) -> str:
    assert old in text, old
    return text.replace(old, new)


def self_test() -> int:
    cases: list[tuple[str, str, dict[str, str], bool]] = [
        ("the shipping shape", CLEAN_CONSOLE, {"a.swift": CLEAN_CARD}, False),
        ("a fifth block pushes the sum past the budget",
         swap(CLEAN_CONSOLE, "static let figureLine: CGFloat = 48",
              "static let figureLine: CGFloat = 120"),
         {"a.swift": CLEAN_CARD}, True),
        ("the recipient row shrunk below the hit floor — even though the sum then fits",
         swap(CLEAN_CONSOLE, "static let recipientRow = DS.Hit.min",
              "static let recipientRow: CGFloat = 36"),
         {"a.swift": CLEAN_CARD}, True),
        ("the custom keypad comes back",
         swap(CLEAN_CONSOLE, "struct DevnetSendFigure: View {",
              "struct DevnetSendKeypad: View { var body: some View { k } }\nstruct DevnetSendFigure: View {"),
         {"a.swift": CLEAN_CARD}, True),
        ("the field asks for a letter keyboard over a money control",
         swap(CLEAN_CONSOLE, ".keyboardType(.decimalPad)", ".keyboardType(.default)"),
         {"a.swift": CLEAN_CARD}, True),
        ("a card raises the pad with no way to dismiss it",
         CLEAN_CONSOLE,
         {"a.swift": swap(CLEAN_CARD, "        .devnetAmountToolbar($amountFocused)\n", "")}, True),
        ("the row spells its own height",
         swap(CLEAN_CONSOLE, ".frame(height: DevnetConsole.recipientRow)",
              ".frame(minHeight: 44)"),
         {"a.swift": CLEAN_CARD}, True),
        ("a card hand-rolls the send button",
         CLEAN_CONSOLE,
         {"a.swift": swap(CLEAN_CARD,
                          "DevnetSendVerb(title: sendLabel, armed: canSend, busy: busy, tint: t) { send() }",
                          "Button { send() } label: { Text(sendLabel) }")}, True),
        ("a form regrows a head",
         CLEAN_CONSOLE,
         {"a.swift": swap(CLEAN_CARD, "            DevnetSendVerb",
                          "            Text(\"Send\").dsText(.heading17)\n            DevnetSendVerb")}, True),
        # DISCRIMINATING, and it has to be: the previous cut of this case was
        # the clean fixture again, which proves nothing. The head is moved
        # ABOVE the form here, so a whole-file grep for `.heading17` WOULD
        # flag it and only the form-scoped read does not.
        ("the SENT state's head is not the form's head",
         CLEAN_CONSOLE,
         {"a.swift": swap(CLEAN_CARD, "    private var form: some View {",
                          "    private var sentHead2: some View { Text(\"Sent\").dsText(.heading22) }\n    private var form: some View {")},
         False),
        ("the console cannot be reached in the demo",
         CLEAN_CONSOLE,
         {"a.swift": swap(CLEAN_CARD,
                          "    private var sender: String? { Key.address() ?? (DemoMode.isActive ? Fixture.demo : nil) }\n",
                          "    private var sender: String? { Key.address() }\n")
                     .replace('guard !DemoMode.isActive else { errorText = "Nothing is sent in the demo."; return }\n        ', "")}, True),
        ("send() would sign and broadcast from a demo",
         CLEAN_CONSOLE,
         {"a.swift": swap(CLEAN_CARD,
                          '        guard !DemoMode.isActive else { errorText = "Nothing is sent in the demo."; return }\n', "")}, True),
        ("a form spaces its blocks with a raw token",
         CLEAN_CONSOLE,
         {"a.swift": swap(CLEAN_CARD, "VStack(spacing: DevnetConsole.blockGap)",
                          "VStack(spacing: DS.Space.s4)")}, True),
        ("a comment naming a banned literal does not fire",
         CLEAN_CONSOLE,
         {"a.swift": swap(CLEAN_CARD, "private var form: some View {",
                          "// never .dsText(.heading17) here, and never a DevnetSendKeypad\n    private var form: some View {")}, False),
        ("a console with no budget at all certifies nothing",
         swap(CLEAN_CONSOLE, "static let budget: CGFloat = 266", ""),
         {"a.swift": CLEAN_CARD}, True),
    ]
    ok = True
    for name, console, cards, should_flag in cases:
        hits = audit(console, cards)
        if bool(hits) == should_flag:
            print(f"  ✓ {name}")
        else:
            print(f"  ✗ {name} — expected {'a finding' if should_flag else 'clean'}, "
                  f"got {hits or '(nothing)'}")
            ok = False
    return 0 if ok else 1


def main() -> int:
    if "--self-test" in sys.argv:
        print("devnet-console audit: self-test")
        return self_test()
    if self_test() != 0:
        print("devnet-console audit: SELF-TEST FAILED — not certifying the tree")
        return 1

    console_path = ROOT / CONSOLE
    if not console_path.exists():
        print(f"devnet-console audit: FAILED — {CONSOLE} is gone")
        return 1
    console = console_path.read_text(encoding="utf-8")
    cards = {c: (ROOT / c).read_text(encoding="utf-8") for c in CARDS
             if (ROOT / c).exists()}
    missing = [c for c in CARDS if c not in cards]
    if missing:
        print(f"devnet-console audit: FAILED — missing {', '.join(missing)}")
        return 1

    findings = audit(console, cards)
    if findings:
        print("devnet-console audit: FAILED")
        for f in findings:
            print(f"  {f}")
        return 1

    c = constants(strip_comments(console))
    height = (2 * c["cardPadding"] + c["recipientRow"] + 2 * c["blockGap"]
              + c["figureLine"] + c["figureGap"] + c["sublineRow"]
              + c["verbLine"] + 2 * c["verbPad"])
    print(f"✓ devnet-console audit: the console sums to {height:g}pt of a "
          f"{c['budget']:g}pt budget (the smallest phone's allowance)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
