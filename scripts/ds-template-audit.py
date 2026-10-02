#!/usr/bin/env python3
"""Design-template audit (prd §715, 2026-09-13; check C prd §746, 2026-09-15;
check D prd §965, 2026-09-28).

WHY THIS EXISTS. User: "where if anywhere in the app do we have hand rolled
things we should be using templates for" → "do all". The sweep found the
design system mostly honoured and a dozen clusters drawn by hand beside it,
most of them copy-paste twins. §715 extracted what was missing into
`Design/` and moved the call sites. Most of those shapes cannot be told apart
from a legitimate one by text (a chevron row vs a pager), so they are NOT
checked here. These can, objectively:

  A. A plain indeterminate `ProgressView()` outside `Design/` → `DSSpinner`.
     `ProgressView(value:)` is a different control and is not matched.
  B. `.presentationDetents([.medium, .large]` outside `Design/` → the reading
     sheet's chassis, `dsReadSheet(detent:)`.
  C. A CAPSULE DRAWN BEHIND CONTENT outside `Design/` (prd §746). User: "when
     every choice is a capsule, the screen reads as generated" → "most people
     only need two: a pill you tap to choose something, and a pill that just
     shows a fact. Everything else becomes a row." The choice is `Chip`, the
     fact is `DSStamp`, and a verb is `DSDoorRow` / `DSCopyRow` / the row's
     own trailing word (`DSPushRowTrail`). All of those live in `Design/`, so
     a capsule drawn anywhere else is a chip, a badge or a verb pill made by
     hand.

HOW C TELLS A PILL FROM A DRAWING, and what that deliberately does not see.
A capsule is a PILL when it is the ground something else sits on: the shape
argument of `.background(…)`, `.overlay(…)` or `.clipShape(…)` (including
their trailing-closure forms, through `if`/`else` branches). A capsule standing
on its own in a `ZStack`, an `HStack` or a `ForEach` — a progress track, a
waveform bar, a tick, a caret, a skeleton line — is a DRAWING, and is not
matched. `contentShape(Capsule())` and `dsTapTarget(Capsule())` draw nothing
and are not matched. What it cannot see: a capsule handed through a variable
(`AnyShape(Capsule())` stored and used later) and a `RoundedRectangle` whose
radius makes it a pill. Both were measured absent from the tree on the day
this was written; neither is worth a check that would cry wolf on cards.

THE EXEMPTIONS ARE A RATCHET, not a waiver. Each names a file, the number of
pills it may still draw, and why. A file drawing MORE than its allowance fails;
a file whose allowance is spent to zero fails as stale (delete the entry). A
file under its allowance passes with a note to tighten it, because the files
named "owned elsewhere" are being rewritten by other sessions at the same time
and a check that fails the moment they delete a capsule punishes the fix.

  D. A `Button` STYLED `.plain` (prd §965). User: "all the buttons in the rooms
     [should] have some very subtle micro animation when you touch them". The
     app has had two press styles since 2026-08-04 — `PressSpring` (a 0.96 dip
     for a disc, a chip, a face, a tile) and `RowPress` (a 0.99 settle plus a
     dim for a row or a word) — and 190 Buttons wore neither: `.plain` gives
     an instant dim with no motion, so a wallet verb, a GitHub tile, a
     devnet's account row and every door row answered the finger with a
     flicker. A Button carries one of the two now, and `.plain` on a Button is
     a finding. `.plain` on a `ShareLink`, a `Menu`, a `Link` or a
     `NavigationLink` is untouched — `sharelink-style-audit.py` REQUIRES it on
     a share control in a List row (§693), and those controls draw their own
     press. Check D reads `Design/` too, because the templates are where a
     plain Button reaches every screen at once.

HOW D TELLS WHOSE STYLE IT IS. The modifier's expression chain is walked
backwards over balanced braces and parens to its head: `Button {…} label: {…}`,
`Button(action:) {…}` and `Button("x") {…}.dsText(…)` all resolve to `Button`;
`ShareLink {…}`, `content.buttonStyle(.plain)` in a ViewModifier and
`Group {…}.buttonStyle(.plain)` do not. A style handed to a container that
holds Buttons is the stated ceiling — none exists in the tree today.

A fourth check — a copy capsule's "Copied"/"Copy" state pair → `DSCopyCapsule`
— was written and REMOVED on 2026-09-13 when its only match was the reusable
`AddressCopyButton`. `DSCopyCapsule` itself is gone since §746 (`DSCopyRow`).

Scans the app target only: `Design/` is app-only, so a finding in the share
extension or the widgets would be a demand nobody could satisfy.

`--self-test` proves each check fires on a planted file and stays quiet on
the template's own shapes, and that the ratchet fails in both directions.
"""
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = "Casberi/Casberi"

CHECKS = [
    ("A", re.compile(r"\bProgressView\(\s*\)"),
     "a plain ProgressView() — use DSSpinner(size:onFill:)"),
    ("B", re.compile(r"\.presentationDetents\(\s*\[\s*\.medium\s*,\s*\.large\s*\]"),
     "the reading sheet's detents by hand — use .dsReadSheet(detent:)"),
]

PILL_WHY = ("a capsule drawn behind content — a choice is Chip, a fact is DSStamp, "
            "a verb is a row (DSDoorRow / DSCopyRow / DSPushRowTrail)")

# The modifiers whose shape argument is a GROUND for other content.
PILL_HOSTS = {"background", "overlay", "clipShape"}
CAPSULE_CALL = re.compile(r"\bCapsule\s*\(")
CAPSULE_STYLE = re.compile(r"(?:\bin:\s*|\bclipShape\(\s*|\bbackground\(\s*)\.capsule\b")
FLOW_LINE = re.compile(r"^\s*(?:\}\s*)?(?:if\b|else\b|switch\b|case\b|default\b|guard\b|#if\b|#else\b)")

# ── THE RATCHET (prd §746) ────────────────────────────────────────────────────
# path relative to Casberi/Casberi → (pills it may still draw, why).
EXEMPT = {
    # ── Owned elsewhere on 2026-09-15: left untouched by §746, tightened as
    #    those sessions land.
    "Screens/ShapedRows.swift": (3, "feed rows — being rewritten by another session"),
    "Screens/PrivacyPoolsRoomCard.swift": (1, "a room head — being migrated by another session"),
    "Shell/DockFolderRow.swift": (2, "the dock, a user-protected differentiator: nothing about it changes here"),
    # ── Not a pill, measured one by one.
    "Screens/DevnetSendConsole.swift": (1, "the join bar between two legs, a drawing carried by an overlay"),
    # ── A real pill, kept on a stated reason and OWED.
    "Screens/WalletFeedTiles.swift": (1, "the wallet crown's face chips — a choice, but each carries a face, a value and a delta "
                                         "Chip cannot; owed with the room-head migration"),
    "GenUI/GenRenderer.swift": (3, "a distribution bar's clip is a drawing; the Suggest element's "
                                   "Review word and the approval card's Approve/Deny are model-emitted DISPLAY forms with no "
                                   "action (§717 kept GenUI kinds) — owed: whether an inert verb shape may render at all is a "
                                   "§83 ruling, not a shape swap"),
}

# ── D. A Button pressed by nothing (prd §965) ─────────────────────────────────
PRESS_WHY = ("a Button styled .plain answers the finger with a flicker — a row or a word "
             "takes RowPress(), a disc, chip, face or tile takes PressSpring()")
PLAIN_STYLE = re.compile(r"\.buttonStyle\(\s*\.plain\s*\)")

# The same ratchet as C: path relative to Casberi/Casberi → (plain Buttons it
# may still carry, why). Each is a control whose press is drawn by something
# other than a ButtonStyle, or a surface whose touch handling is measured and
# user-protected.
EXEMPT_PLAIN = {
    "Shell/SourceChips.swift": (1, "the dock chip lifts on the pointer wave and is the travelling fill's "
                                   "source frame (§359); a press dip would move the fill's anchor"),
    "Shell/DockFolderRow.swift": (2, "the dock, a user-protected differentiator: nothing about it changes here"),
    "Shell/TopDoors.swift": (1, "the face door's tap is a highPriorityGesture (the pager pan), so the "
                                "Button's own press never fires — a style there would be dead"),
    "Shell/RoomsTray.swift": (1, "the tray's scrim: a full-screen dismiss, not a control anyone looks at"),
    "Screens/DevnetSendConsole.swift": (1, "the keypad draws its own pressed circle inside the key (§553)"),
}


def _matching_opener(src: str, close: int) -> int:
    """Index of the bracket opening the one at `close`, or -1."""
    depth, i = 0, close
    while i >= 0:
        ch = src[i]
        if ch in ")}]":
            depth += 1
        elif ch in "({[":
            depth -= 1
            if depth == 0:
                return i
        i -= 1
    return -1


def press_host(src: str, pos: int) -> str:
    """The control a `.buttonStyle` at `pos` styles — the head of its chain.

    Walks back over balanced brackets, trailing-closure labels (`label:`) and
    dotted modifiers until it reaches a bare identifier: `Button`, `ShareLink`,
    `Group`, `content`, ... An empty string means the chain could not be read.
    """
    i = pos - 1
    while True:
        while i >= 0 and src[i] in " \t\n":
            i -= 1
        if i < 0:
            return ""
        if src[i] in ")}]":
            opener = _matching_opener(src, i)
            if opener < 0:
                return ""
            i = opener - 1
            continue
        if src[i] == ":":            # `label:` / `action:` — a closure's label
            i -= 1
            name = _ident_before(src, i + 1)
            i -= len(name)
            continue
        name = _ident_before(src, i + 1)
        if not name:
            return ""
        j = i - len(name)            # index before the identifier
        k = j
        while k >= 0 and src[k] in " \t\n":
            k -= 1
        if k >= 0 and src[k] == ".":  # a modifier in the chain, keep walking
            i = k - 1
            continue
        return name


def plain_button_lines(src: str):
    """1-based line numbers of every `.buttonStyle(.plain)` styling a Button."""
    return [src.count("\n", 0, m.start()) + 1
            for m in PLAIN_STYLE.finditer(src)
            if press_host(src, m.start()) == "Button"]


def strip_comments(text: str) -> str:
    """Comments out, strings kept, line breaks preserved."""
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
                out.append(text[i:i + 2])
                i += 2
                continue
            if ch == '"' or ch == "\n":
                in_string = False
            out.append(ch)
            i += 1
            continue
        if ch == '"':
            in_string = True
            out.append(ch)
            i += 1
            continue
        if ch == "/" and nxt == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if ch == "/" and nxt == "*":
            in_block = True
            i += 2
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def _ident_before(src: str, i: int) -> str:
    """The identifier ending just before index i (whitespace skipped)."""
    j = i - 1
    while j >= 0 and src[j] in " \t\n":
        j -= 1
    end = j + 1
    while j >= 0 and (src[j].isalnum() or src[j] == "_"):
        j -= 1
    return src[j + 1:end]


def _callee(src: str, opener: int) -> str:
    """What an unmatched `(` or `{` belongs to: a call name, or "__flow__"."""
    line_start = src.rfind("\n", 0, opener) + 1
    if src[opener] == "{" and FLOW_LINE.match(src[line_start:opener]):
        return "__flow__"
    j = opener - 1
    while j >= 0 and src[j] in " \t\n":
        j -= 1
    if src[opener] == "{" and j >= 0 and src[j] == ")":
        depth = 0
        while j >= 0:  # a trailing closure after an argument list
            if src[j] == ")":
                depth += 1
            elif src[j] == "(":
                depth -= 1
                if depth == 0:
                    break
            j -= 1
        return _ident_before(src, j)
    return _ident_before(src, j + 1)


def pill_host(src: str, pos: int, limit: int = 1500):
    """The ground modifier a capsule at `pos` is drawn into, or None."""
    depth, i, stop = 0, pos - 1, max(0, pos - limit)
    while i >= stop:
        ch = src[i]
        if ch in ")]}":
            depth += 1
        elif ch in "([{":
            if depth:
                depth -= 1
            else:
                name = _callee(src, i)
                if name != "__flow__":
                    return name if name in PILL_HOSTS else None
        i -= 1
    return None


def pill_lines(src: str):
    """1-based line numbers of every capsule drawn as a ground."""
    lines = []
    for m in CAPSULE_CALL.finditer(src):
        if pill_host(src, m.start()):
            lines.append(src.count("\n", 0, m.start()) + 1)
    for m in CAPSULE_STYLE.finditer(src):
        lines.append(src.count("\n", 0, m.start()) + 1)
    return sorted(lines)


def scan(root: Path, exempt=None, exempt_plain=None):
    exempt = EXEMPT if exempt is None else exempt
    exempt_plain = EXEMPT_PLAIN if exempt_plain is None else exempt_plain
    findings, notes = [], []
    app = root / APP
    for path in sorted(app.rglob("*.swift")):
        rel = path.relative_to(app)
        src = strip_comments(path.read_text(encoding="utf-8"))
        # D reads Design/ too: a plain Button in a template reaches every screen.
        key = rel.as_posix()
        plain = plain_button_lines(src)
        allowed, reason = exempt_plain.get(key, (0, ""))
        if key in exempt_plain and not plain:
            findings.append(("D", f"{APP}/{key}",
                             "stale exemption — this file styles no Button .plain now; delete its entry"))
        elif len(plain) > allowed:
            for no in plain:
                findings.append(("D", f"{APP}/{key}:{no}",
                                 PRESS_WHY + (f" (allowance {allowed}: {reason})" if key in exempt_plain else "")))
        elif key in exempt_plain and len(plain) < allowed:
            notes.append(f"  note: {APP}/{key} styles {len(plain)} of its {allowed} plain — tighten the allowance")
        if rel.parts and rel.parts[0] == "Design":
            continue
        for no, line in enumerate(src.split("\n"), 1):
            for tag, rx, why in CHECKS:
                if rx.search(line):
                    findings.append((tag, f"{APP}/{rel}:{no}", why))
        key = rel.as_posix()
        pills = pill_lines(src)
        allowed, reason = exempt.get(key, (0, ""))
        if key in exempt and not pills:
            findings.append(("C", f"{APP}/{key}",
                             "stale exemption — this file draws no pill now; delete its entry"))
        elif len(pills) > allowed:
            for no in pills:
                findings.append(("C", f"{APP}/{key}:{no}",
                                 PILL_WHY + (f" (allowance {allowed}: {reason})" if key in exempt else "")))
        elif key in exempt and len(pills) < allowed:
            notes.append(f"  note: {APP}/{key} draws {len(pills)} of its {allowed} — tighten the allowance")
    return findings, notes


def self_test() -> int:
    ok = True

    def run(planted, exempt=None, exempt_plain=None):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for rel, body in planted.items():
                p = root / APP / rel
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text(body)
            return scan(root, exempt or {}, exempt_plain or {})

    # A and B, as before.
    got, _ = run({
        "Screens/Bad.swift": (
            'struct Bad: View { var body: some View { VStack {\n'
            '  ProgressView()\n'
            '}.presentationDetents([.medium, .large]) } }\n'),
        "Screens/Good.swift": (
            '// ProgressView() and .presentationDetents([.medium, .large]) in a comment\n'
            'struct Good: View { var body: some View { VStack {\n'
            '  DSSpinner()\n  ProgressView(value: 0.5)\n'
            '}.dsReadSheet().presentationDetents([.large]) } }\n'),
        "Design/DSSpinner.swift": 'struct DSSpinner { var body: some View { ProgressView() } }\n',
    })
    tags = sorted(t for t, _, _ in got)
    files = {loc.split(":")[0] for _, loc, _ in got}
    case = tags == ["A", "B"] and files == {f"{APP}/Screens/Bad.swift"}
    print(f"  {'ok  ' if case else 'FAIL'} A/B fire on the planted file only ({tags})")
    ok &= case

    # C — every spelling of a hand-drawn pill fires.
    dirty = (
        'struct Pills: View { var body: some View { VStack {\n'
        '  Text("a").background(DS.fillFaint, in: Capsule(style: .continuous))\n'   # 2
        '  Text("b").background(\n'
        '      Capsule().fill(DS.tint))\n'                                           # 4
        '  Text("c").overlay(Capsule().strokeBorder(DS.tint, lineWidth: 1))\n'       # 5
        '  Text("d").background {\n'
        '      if on {\n'
        '          Capsule().fill(DS.textPrimary)\n'                                 # 8
        '      } else {\n'
        '          Capsule().fill(DS.fillFaint)\n'                                   # 10
        '      }\n'
        '  }\n'
        '  Text("e").overlay(alignment: .top) { Capsule().fill(.red) }\n'           # 13
        '  Text("f").clipShape(.capsule)\n'                                          # 14
        '} } }\n')
    got, _ = run({"Screens/Pills.swift": dirty})
    lines = sorted(int(loc.rsplit(":", 1)[1]) for t, loc, _ in got if t == "C")
    case = lines == [2, 4, 5, 8, 10, 13, 14]
    print(f"  {'ok  ' if case else 'FAIL'} C fires on every spelling of a drawn pill ({lines})")
    ok &= case

    # C — THE DISCRIMINATING ONE: drawings, hit shapes, comments and Design/.
    clean = (
        '// .background(DS.fillFaint, in: Capsule()) in a comment\n'
        'struct Drawings: View { var body: some View { VStack {\n'
        '  ZStack(alignment: .leading) {\n'
        '      Capsule().fill(DS.fillFaint)\n'
        '      Capsule().fill(DS.tint).frame(width: 40)\n'
        '  }\n'
        '  HStack { ForEach(bars, id: \\.self) { h in Capsule().fill(DS.tint).frame(width: 3, height: h) } }\n'
        '  Button { go() } label: { Text("Go").contentShape(Capsule()) }\n'
        '  Text("x").dsTapTarget(Capsule(style: .continuous))\n'
        '  Circle().fill(DS.tint).background(DS.fillFaint, in: RoundedRectangle(cornerRadius: 8))\n'
        '} } }\n')
    got, _ = run({
        "Screens/Drawings.swift": clean,
        "Design/DSChip.swift": 'struct Chip: View { var body: some View { Text("x").background(DS.fillFaint, in: Capsule()) } }\n',
    })
    case = not got
    print(f"  {'ok  ' if case else 'FAIL'} C stays quiet on tracks, bars, hit shapes, comments and Design/ ({got})")
    ok &= case

    # C — the ratchet, both directions.
    one = 'struct One: View { var body: some View { Text("a").background(.red, in: Capsule()) } }\n'
    two = one + 'struct Two: View { var body: some View { Text("b").overlay(Capsule().stroke(.red)) } }\n'
    none = 'struct None: View { var body: some View { Text("a") } }\n'
    within, _ = run({"Screens/Owned.swift": one}, {"Screens/Owned.swift": (1, "owned")})
    over, _ = run({"Screens/Owned.swift": two}, {"Screens/Owned.swift": (1, "owned")})
    stale, _ = run({"Screens/Owned.swift": none}, {"Screens/Owned.swift": (1, "owned")})
    under, notes = run({"Screens/Owned.swift": one}, {"Screens/Owned.swift": (2, "owned")})
    case = (not within and len(over) == 2 and len(stale) == 1
            and "stale" in stale[0][2] and not under and len(notes) == 1)
    print(f"  {'ok  ' if case else 'FAIL'} C's ratchet: within passes, over fails, stale fails, under notes")
    ok &= case

    # D — every spelling of a Button styled .plain fires, in Screens/ AND Design/.
    dirty_plain = (
        'struct Plain: View { var body: some View { VStack {\n'
        '  Button { go() } label: {\n'
        '      Text("a").contentShape(Rectangle())\n'
        '  }\n'
        '  .buttonStyle(.plain)\n'                                                  # 5
        '  Button(role: .destructive, action: act) { Text("b") }\n'
        '      .buttonStyle(.plain)\n'                                              # 7
        '  Button("c") { go() }\n'
        '      .dsText(.body17)\n'
        '      .foregroundStyle(DS.tint)\n'
        '      .buttonStyle(.plain)\n'                                              # 11
        '  if let act { Button(action: act) { row } .buttonStyle( .plain ) }\n'      # 12
        '} } }\n')
    got, _ = run({"Screens/Plain.swift": dirty_plain,
                  "Design/DSPlain.swift": 'struct DSPlain: View { var body: some View { Button { go() } label: { Text("x") }.buttonStyle(.plain) } }\n'})
    lines = sorted(int(loc.rsplit(":", 1)[1]) for t, loc, _ in got if t == "D" and "Screens" in loc)
    design = [loc for t, loc, _ in got if t == "D" and "Design" in loc]
    case = lines == [5, 7, 11, 12] and len(design) == 1
    print(f"  {'ok  ' if case else 'FAIL'} D fires on every spelling of a plain Button, Design/ included ({lines}, {len(design)})")
    ok &= case

    # D — THE DISCRIMINATING ONE: the two press styles, the controls that draw
    # their own press, a style handed to `content`, and a comment.
    clean_plain = (
        '// Button { } label: { }.buttonStyle(.plain) in a comment\n'
        'struct Pressed: View { var body: some View { VStack {\n'
        '  Button { go() } label: { Text("a") }.buttonStyle(RowPress())\n'
        '  Button { go() } label: { Chip(text: "b") }.buttonStyle(PressSpring())\n'
        '  ShareLink(item: url) { Text("c") }.buttonStyle(.plain)\n'
        '  Menu { Button("d") { go() } } label: { Text("d") }.buttonStyle(.plain)\n'
        '  Link("e", destination: url).buttonStyle(.plain)\n'
        '  NavigationLink(value: node) { Text("f") }.buttonStyle(.plain)\n'
        '} } }\n'
        'struct Ground: ViewModifier {\n'
        '  func body(content: Content) -> some View { content.buttonStyle(.plain) }\n'
        '}\n')
    got, _ = run({"Screens/Pressed.swift": clean_plain})
    case = not [f for f in got if f[0] == "D"]
    print(f"  {'ok  ' if case else 'FAIL'} D stays quiet on the press styles, ShareLink/Menu/Link, content and comments ({got})")
    ok &= case

    # D — the ratchet, both directions.
    one_plain = 'struct One: View { var body: some View { Button { go() } label: { Text("a") }.buttonStyle(.plain) } }\n'
    two_plain = one_plain + 'struct Two: View { var body: some View { Button("b") { go() }.buttonStyle(.plain) } }\n'
    within, _ = run({"Shell/Dock.swift": one_plain}, exempt_plain={"Shell/Dock.swift": (1, "the dock")})
    over, _ = run({"Shell/Dock.swift": two_plain}, exempt_plain={"Shell/Dock.swift": (1, "the dock")})
    stale, _ = run({"Shell/Dock.swift": none}, exempt_plain={"Shell/Dock.swift": (1, "the dock")})
    under, notes = run({"Shell/Dock.swift": one_plain}, exempt_plain={"Shell/Dock.swift": (2, "the dock")})
    case = (not within and len(over) == 2 and len(stale) == 1
            and "stale" in stale[0][2] and not under and len(notes) == 1)
    print(f"  {'ok  ' if case else 'FAIL'} D's ratchet: within passes, over fails, stale fails, under notes")
    ok &= case

    print(f"ds-template-audit self-test: {'OK' if ok else 'FAIL'}")
    return 0 if ok else 1


def main() -> int:
    if "--self-test" in sys.argv:
        return self_test()
    if "--list-pills" in sys.argv:
        _, _ = None, None
        app = ROOT / APP
        for path in sorted(app.rglob("*.swift")):
            rel = path.relative_to(app)
            if rel.parts and rel.parts[0] == "Design":
                continue
            pills = pill_lines(strip_comments(path.read_text(encoding="utf-8")))
            if pills:
                print(f"{rel.as_posix()}\t{len(pills)}\t{pills}")
        return 0
    findings, notes = scan(ROOT)
    for tag, loc, why in findings:
        print(f"  [{tag}] {loc}: {why}")
    for note in notes:
        print(note)
    if findings:
        print(f"ds-template-audit: FAIL ({len(findings)} hand-rolled template sites)")
        return 1
    print("ds-template-audit: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
