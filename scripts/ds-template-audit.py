#!/usr/bin/env python3
"""Design-template audit (prd §715, 2026-09-13; check C prd §746, 2026-09-15).

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
    "Screens/VibenetRoomCard.swift": (3, "a room head — being migrated by another session"),
    "Shell/DockFolderRow.swift": (2, "the dock, a user-protected differentiator: nothing about it changes here"),
    # ── Not a pill, measured one by one.
    "Screens/AddressIndexBar.swift": (1, "the A–Z scrub's track, drawn only while a finger is on it — an indicator"),
    "Screens/AgentPanelGrid.swift": (1, "a cluster label's legibility plate over a map figure (§715: stamps over artwork)"),
    "Screens/DevnetSendConsole.swift": (1, "the join bar between two legs, a drawing carried by an overlay"),
    "Screens/PrivacyDevnetFigures.swift": (2, "the figure's own encodings: an aged proof's outlined tick and the sponsor mark its legend names"),
    # ── A real pill, kept on a stated reason and OWED.
    "Screens/WalletFeedTiles.swift": (1, "the wallet crown's face chips — a choice, but each carries a face, a value and a delta "
                                         "Chip cannot; owed with the room-head migration"),
    "GenUI/GenRenderer.swift": (3, "a distribution bar's clip is a drawing; the Suggest element's "
                                   "Review word and the approval card's Approve/Deny are model-emitted DISPLAY forms with no "
                                   "action (§717 kept GenUI kinds) — owed: whether an inert verb shape may render at all is a "
                                   "§83 ruling, not a shape swap"),
}


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


def scan(root: Path, exempt=None):
    exempt = EXEMPT if exempt is None else exempt
    findings, notes = [], []
    app = root / APP
    for path in sorted(app.rglob("*.swift")):
        rel = path.relative_to(app)
        if rel.parts and rel.parts[0] == "Design":
            continue
        src = strip_comments(path.read_text(encoding="utf-8"))
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

    def run(planted, exempt=None):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for rel, body in planted.items():
                p = root / APP / rel
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text(body)
            return scan(root, exempt or {})

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
