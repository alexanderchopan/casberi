#!/usr/bin/env python3
"""Casberi lead-cycle audit (prd §901, 2026-09-23).

ONE CYCLE, NOT A SWITCH. A feed row's lead turns over to its dock CATEGORY's
glyph and back when the row lands while you look or its title moves in place.
The user's two rules, each of which a later pass could quietly undo while the
build stays green and the row still animates:

  · "it should always be the category not a state b/c then we'd be making up
    new icons or glyphs for a user to learn" — so the glyph the disc turns to
    is read from `CategoryFold.glyph(for:)`, the dock's own table, and from
    nothing else. A tick for "delivered" would compile, look right, and be a
    second vocabulary.
  · "one cycle not a switch" — so the turn comes BACK, and lands with no
    animation at 0 so the next cycle starts where this one did.

WHAT IT CHECKS (each with a mutation in the self-test that must fire):

  A  every `glyph =` in `LeadCycle` is `CategoryFold.glyph(for:)`, resolved
     from `BridgeCatalog.category(forSource:)`; no `Image(systemName:` and no
     literal symbol name anywhere in the file.
  B  the turn comes back: `angle = 360` is animated, then reset to 0 under
     `disablesAnimations`, and `back` is later than `out`.
  C  Reduce Motion is read where the cycle fires (`guard !reduceMotion`).
  D  ONE caller, `BandRow`'s lead in ShapedRows.swift, passing `fact:
     thing.title` and `cyclesOnChange: !moneyColumn` — the ledger keeps §171's
     ripple as its one motion on a retitle. The fold rows never carry it.
     (The Addresses list is the one OTHER door, `faceCycle`, 2026-09-25: a
     contact's face turns when the contact was SAVED after the list's wave —
     `arrival` stands in for the ledger, which never sees a contact. It is
     checked here only through A, B, C and E: same file, same glyph table,
     same clock, same window.)
  E  the landing rule reads the thing's ARRIVAL (`LandingLedger.landedAt(id)`,
     §901b) against the page's wave (`landed > waveAt`) AND a fresh window,
     never `capturedAt` (the thing's OWN date, stamped from upstream by most
     bridges — a forty-minute-old reply that arrived just now read as old and
     never turned); and FeedScreen sets `feedWaveAt` from `shapeWaveAt` on the
     List — without the environment write the rule is nil-guarded and no row
     ever cycles on landing, which renders perfectly.
  F  the change trigger is `.onChange(of: fact)` behind `cyclesOnChange`.
  G  the ledger has ONE door and is installed ONCE: `LandingLedger` observes
     `ModelContext.willSave` and stamps `insertedModelsArray`'s things, and
     `RootShell` calls `LandingLedger.install()` — without the install every
     `landedAt` is nil and no row ever cycles on landing, which also renders
     perfectly. The demo pour suspends it (a poured seed is not a landing).

WHAT IT DOES NOT CHECK: that the animation looks right, or the clock's exact
values beyond their order — those are the device's to judge.

Exit non-zero on a finding.
"""
import re
import sys
from pathlib import Path

CYCLE = "Casberi/Casberi/Design/LeadCycle.swift"
ROWS = "Casberi/Casberi/Screens/ShapedRows.swift"
FEED = "Casberi/Casberi/Screens/FeedScreen.swift"
LEDGER = "Casberi/Casberi/Model/LandingLedger.swift"
ROOT = "Casberi/Casberi/Shell/RootShell.swift"
DEMO = "Casberi/Casberi/Model/DemoMode.swift"


def strip_comments(text: str) -> str:
    """A file's own prose names the shapes it forbids."""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return "\n".join(re.sub(r"//.*$", "", line) for line in text.split("\n"))


def audit(cycle: str, rows: str, feed: str, ledger: str = "", root: str = "",
          demo: str = "") -> list:
    out = []
    c = strip_comments(cycle)
    r = strip_comments(rows)
    f = strip_comments(feed)
    l = strip_comments(ledger)
    s = strip_comments(root)
    d = strip_comments(demo)

    # A — the glyph is the dock category's, from the dock's table, and nothing else.
    assigns = re.findall(r"\bglyph\s*=\s*([^\n]+)", c)
    if not assigns:
        out.append("A: LeadCycle never assigns its glyph")
    for a in assigns:
        if "CategoryFold.glyph(for:" not in a:
            out.append(f"A: a glyph assigned from something other than CategoryFold.glyph(for:) — `{a.strip()}`")
    if "BridgeCatalog.category(forSource:" not in c:
        out.append("A: the category is not resolved through BridgeCatalog.category(forSource:)")
    if re.search(r"Image\(systemName:", c):
        out.append("A: LeadCycle draws an Image(systemName:) of its own — the flipped face is DSGlyphLead")
    if re.search(r"glyph\s*=\s*\"", c) or re.search(r"glyph:\s*\"", c):
        out.append("A: a literal glyph name in LeadCycle — a symbol the dock does not wear")

    # B — it comes back, and lands still.
    if not re.search(r"withAnimation\([^)]*\)\s*\{\s*angle\s*=\s*360\s*\}", c):
        out.append("B: the turn never comes back (no animated `angle = 360`)")
    if not re.search(r"disablesAnimations\s*=\s*true[\s\S]{0,200}angle\s*=\s*0", c):
        out.append("B: the landed turn is not reset to 0 under disablesAnimations")
    m_out = re.search(r"static let out:\s*TimeInterval\s*=\s*([\d.]+)", c)
    m_back = re.search(r"static let back:\s*TimeInterval\s*=\s*([\d.]+)", c)
    if not (m_out and m_back):
        out.append("B: the clock's `out`/`back` constants are missing")
    elif float(m_back.group(1)) <= float(m_out.group(1)):
        out.append("B: `back` is not later than `out` — the glyph would never be held")

    # C — Reduce Motion where it fires.
    if "accessibilityReduceMotion" not in c:
        out.append("C: LeadCycle does not read accessibilityReduceMotion")
    if not re.search(r"guard\s+!reduceMotion", c):
        out.append("C: the cycle fires without guarding on reduceMotion")

    # D — one caller, BandRow's lead, with the ledger opted out of change.
    calls = re.findall(r"\.leadCycle\(([^)]*(?:\n[^)]*)*)\)", r)
    if len(calls) != 1:
        out.append(f"D: expected ONE .leadCycle( caller in ShapedRows.swift (BandRow's lead), found {len(calls)}")
    for call in calls:
        flat = " ".join(call.split())
        if "fact: thing.title" not in flat:
            out.append("D: the cycle's fact is not the row's title")
        if "id: thing.id" not in flat or "capturedAt" in flat:
            out.append("D: the caller does not hand the cycle the thing's id for its arrival (§901b) — `capturedAt` is the thing's own date")
        if "cyclesOnChange: !moneyColumn" not in flat:
            out.append("D: the ledger's rows are not opted out of the change cycle (§171's ripple is their motion)")
    for fold in re.findall(r"struct (?:BundleRow|StripRow): View \{[\s\S]*?\n\}", r):
        if ".leadCycle(" in fold:
            out.append("D: a fold's lead carries the cycle")

    # E — the landing rule: the ARRIVAL against the wave, and a fresh window.
    if not re.search(r"landed\s*=\s*(?:arrival\s*\?\?\s*)?LandingLedger\.landedAt\(id\)", c):
        out.append("E: the landing is not read from LandingLedger.landedAt(id) — the thing's arrival (§901b)")
    if "capturedAt" in c:
        out.append("E: LeadCycle reads capturedAt — the thing's OWN date, not its arrival; a forty-minute-old reply landing now never turns")
    if not re.search(r"landed\s*>\s*waveAt", c):
        out.append("E: the landing rule does not compare the arrival against the page's wave")
    if "freshWindow" not in c or not re.search(r"now\s*-\s*landed\s*<\s*Self\.freshWindow", c):
        out.append("E: the landing rule has no fresh window — a row met by scrolling would cycle")
    if not re.search(r"\.environment\(\\\.feedWaveAt,\s*shapeWaveAt\)", f):
        out.append("E: FeedScreen never sets feedWaveAt from shapeWaveAt — no row can cycle on landing")
    # E, the arrival door (2026-09-25): a stamped arrival goes THROUGH the
    # same guard as the ledger's — the only returns in `landedWhileLooking`
    # are the guard's `false` and the wave-and-window comparison. An early
    # `return true` on `arrival` would cycle a row saved yesterday on every
    # mount, and the regex above would still find the guard line.
    body = re.search(r"var landedWhileLooking: Bool \{([\s\S]*?)\n    \}", c)
    if body:
        for ret in re.findall(r"\breturn\b\s*([^\n;}]*)", body.group(1)):
            r = ret.strip()
            if not (r.startswith("false") or r.startswith("landed > waveAt")):
                out.append(f"E: landedWhileLooking returns `{r}` — an arrival that bypasses the wave and the fresh window")

    # F — the change trigger.
    if not re.search(r"\.onChange\(of:\s*fact\)\s*\{\s*if\s+cyclesOnChange", c):
        out.append("F: the change trigger is not `.onChange(of: fact) { if cyclesOnChange …`")

    # G — the ledger's one door, installed once, suspended by the pour.
    if "ModelContext.willSave" not in l:
        out.append("G: LandingLedger does not observe ModelContext.willSave — nothing stamps an arrival")
    if "insertedModelsArray" not in l:
        out.append("G: LandingLedger does not read the saving context's insertedModelsArray")
    if not re.search(r"guard\s+!suspended", l):
        out.append("G: LandingLedger records while suspended — the demo pour would turn every lead")
    installs = re.findall(r"LandingLedger\.install\(\)", s)
    if len(installs) != 1:
        out.append(f"G: expected ONE LandingLedger.install() in RootShell.swift, found {len(installs)} — with none every landedAt is nil and no row cycles on landing")
    if not re.search(r"LandingLedger\.suspended\s*=\s*true", d):
        out.append("G: the demo pour does not suspend LandingLedger — a poured seed is not a landing")
    return out


GOOD_CYCLE = """
struct LeadCycle: ViewModifier {
    static let out: TimeInterval = 0.3
    static let back: TimeInterval = 1.2
    static let freshWindow: TimeInterval = 20
    @Environment(\\.feedWaveAt) private var waveAt
    @Environment(\\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle: Double = 0
    @State private var glyph: String?
    func body(content: Content) -> some View {
        ZStack {
            content
            if let glyph { DSGlyphLead(glyph: glyph) }
        }
        .onAppear { if landedWhileLooking { fire() } }
        .onChange(of: fact) { if cyclesOnChange { fire() } }
    }
    private var landedWhileLooking: Bool {
        guard let waveAt, let landed = LandingLedger.landedAt(id) else { return false }
        return landed > waveAt && now - landed < Self.freshWindow
    }
    private func fire() {
        guard !reduceMotion, !cycling else { return }
        guard let category = BridgeCatalog.category(forSource: source) else { return }
        glyph = CategoryFold.glyph(for: category)
        withAnimation(DS.Motion.standard.delay(delay + Self.out)) { angle = 180 }
        Task { @MainActor in
            withAnimation(DS.Motion.standard) { angle = 360 }
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                angle = 0
            }
        }
    }
}
"""
GOOD_ROWS = """
struct BandRow: View {
    var body: some View {
        DSFeedRow(name: titleText) {
            leaderView
                .overlay(alignment: .bottomTrailing) { flag }
                .leadCycle(source: thing.source, id: thing.id,
                           fact: thing.title, index: rippleIndex,
                           cyclesOnChange: !moneyColumn)
        }
    }
}
struct BundleRow: View { var body: some View { BridgeIcon(name: source, size: DS.Mark.row) }
}
"""
GOOD_FEED = """
        List { rows }
        .listStyle(.plain)
        .environment(\\.feedWaveAt, shapeWaveAt)
"""
GOOD_LEDGER = """
enum LandingLedger {
    static func install() {
        observer = NotificationCenter.default.addObserver(forName: ModelContext.willSave, object: nil, queue: nil) { note in
            guard let context = note.object as? ModelContext else { return }
            record(context.insertedModelsArray.compactMap { ($0 as? Thing)?.id })
        }
    }
    static func record(_ ids: [UUID]) {
        guard !suspended else { return }
        for id in ids { landings[id] = now }
    }
}
"""
GOOD_ROOT = """
        SaveCoalescer.holdForHand = { await GestureGate.idle() }
        LandingLedger.install()
"""
GOOD_DEMO = """
        pouring = true
        LandingLedger.suspended = true
        defer { LandingLedger.suspended = false }
"""


def self_test() -> bool:
    GOOD = dict(cycle=GOOD_CYCLE, rows=GOOD_ROWS, feed=GOOD_FEED,
                ledger=GOOD_LEDGER, root=GOOD_ROOT, demo=GOOD_DEMO)
    cases = [
        ("healthy tree is clean", GOOD_CYCLE, GOOD_ROWS, GOOD_FEED, 0),
        ("A: a state glyph — the tick for delivered",
         GOOD_CYCLE.replace('glyph = CategoryFold.glyph(for: category)', 'glyph = "checkmark"'), GOOD_ROWS, GOOD_FEED, 1),
        ("A: a glyph table of its own beside the dock's",
         GOOD_CYCLE.replace('glyph = CategoryFold.glyph(for: category)', 'glyph = LeadGlyphs.table[category]'), GOOD_ROWS, GOOD_FEED, 1),
        ("A: the category resolved by hand, not the catalog",
         GOOD_CYCLE.replace('BridgeCatalog.category(forSource: source)', 'myCategory(source)'), GOOD_ROWS, GOOD_FEED, 1),
        ("A: the flipped face drawn by hand",
         GOOD_CYCLE.replace('DSGlyphLead(glyph: glyph)', 'Image(systemName: glyph)'), GOOD_ROWS, GOOD_FEED, 1),
        ("B: a switch — the turn never comes back",
         GOOD_CYCLE.replace('withAnimation(DS.Motion.standard) { angle = 360 }', ''), GOOD_ROWS, GOOD_FEED, 1),
        ("B: the reset animates (a third visible turn)",
         GOOD_CYCLE.replace('still.disablesAnimations = true', ''), GOOD_ROWS, GOOD_FEED, 1),
        ("B: back before out",
         GOOD_CYCLE.replace('static let back: TimeInterval = 1.2', 'static let back: TimeInterval = 0.2'), GOOD_ROWS, GOOD_FEED, 1),
        ("C: Reduce Motion no longer guards the fire",
         GOOD_CYCLE.replace('guard !reduceMotion, !cycling', 'guard !cycling'), GOOD_ROWS, GOOD_FEED, 1),
        ("D: the ledger's rows cycle on a retitle too",
         GOOD_CYCLE, GOOD_ROWS.replace('cyclesOnChange: !moneyColumn', 'cyclesOnChange: true'), GOOD_FEED, 1),
        ("D: a second caller on the fold's lead",
         GOOD_CYCLE, GOOD_ROWS.replace('BridgeIcon(name: source, size: DS.Mark.row) }', 'BridgeIcon(name: source, size: DS.Mark.row).leadCycle(source: source, capturedAt: .now, fact: name) }'), GOOD_FEED, 1),
        ("D: the caller deleted",
         GOOD_CYCLE, re.sub(r"\.leadCycle\([\s\S]*?cyclesOnChange: !moneyColumn\)", "", GOOD_ROWS), GOOD_FEED, 1),
        ("D: the fact is not the title",
         GOOD_CYCLE, GOOD_ROWS.replace('fact: thing.title', 'fact: thing.source'), GOOD_FEED, 1),
        ("healthy tree with the arrival door (faceCycle) is clean",
         GOOD_CYCLE.replace('let landed = LandingLedger.landedAt(id)', 'let landed = arrival ?? LandingLedger.landedAt(id)'), GOOD_ROWS, GOOD_FEED, 0),
        ("E: an arrival bypasses the wave — a row saved yesterday cycles every mount",
         GOOD_CYCLE.replace('guard let waveAt, let landed = LandingLedger.landedAt(id) else { return false }', 'if let arrival { return true }\n        guard let waveAt, let landed = arrival ?? LandingLedger.landedAt(id) else { return false }'), GOOD_ROWS, GOOD_FEED, 1),
        ("E: the fresh window dropped — a scrolled-to row cycles",
         GOOD_CYCLE.replace('return landed > waveAt && now - landed < Self.freshWindow', 'return landed > waveAt'), GOOD_ROWS, GOOD_FEED, 1),
        ("E: the landing read off the thing's own date again (§901b)",
         GOOD_CYCLE.replace('guard let waveAt, let landed = LandingLedger.landedAt(id) else { return false }', 'guard let waveAt else { return false }\n        let landed = capturedAt.timeIntervalSinceReferenceDate'), GOOD_ROWS, GOOD_FEED, 1),
        ("D: the caller hands the cycle capturedAt instead of the id",
         GOOD_CYCLE, GOOD_ROWS.replace('id: thing.id', 'capturedAt: thing.capturedAt'), GOOD_FEED, 1),
        ("E: the wave never set on the List",
         GOOD_CYCLE, GOOD_ROWS, GOOD_FEED.replace('.environment(\\.feedWaveAt, shapeWaveAt)', ''), 1),
        ("F: the change trigger lost its opt-out",
         GOOD_CYCLE.replace('.onChange(of: fact) { if cyclesOnChange { fire() } }', '.onChange(of: fact) { fire() }'), GOOD_ROWS, GOOD_FEED, 1),
        ("a comment quoting the rule does not satisfy it",
         GOOD_CYCLE.replace('glyph = CategoryFold.glyph(for: category)', '// glyph = CategoryFold.glyph(for: category)\n        glyph = "checkmark"'), GOOD_ROWS, GOOD_FEED, 1),
    ]
    cases = [dict(GOOD, cycle=cy, rows=ro, feed=fe) | {"name": n, "want": w} for n, cy, ro, fe, w in cases]
    cases += [
        dict(GOOD, name="G: the ledger never installed — every arrival nil, nothing turns", want=1,
             root=GOOD_ROOT.replace('LandingLedger.install()', '')),
        dict(GOOD, name="G: the ledger installed twice", want=1,
             root=GOOD_ROOT + '        LandingLedger.install()\n'),
        dict(GOOD, name="G: the ledger observes nothing", want=1,
             ledger=GOOD_LEDGER.replace('ModelContext.willSave', 'ModelContext.didSave')),
        dict(GOOD, name="G: the ledger stamps something other than the inserted models", want=1,
             ledger=GOOD_LEDGER.replace('context.insertedModelsArray', 'context.changedModelsArray')),
        dict(GOOD, name="G: the pour no longer suspends the ledger", want=1,
             demo=GOOD_DEMO.replace('LandingLedger.suspended = true', '')),
        dict(GOOD, name="G: the ledger ignores its suspension", want=1,
             ledger=GOOD_LEDGER.replace('guard !suspended else { return }', '')),
        dict(GOOD, name="a comment naming the install does not satisfy it", want=1,
             root=GOOD_ROOT.replace('LandingLedger.install()', '// LandingLedger.install()')),
    ]
    ok = True
    for case in cases:
        name, want = case["name"], case["want"]
        inputs = {k: case[k] for k in GOOD}
        if want and inputs == GOOD:
            print(f"  FAIL {name}: the mutation changed nothing")
            ok = False
            continue
        got = len(audit(**inputs))
        verdict = "ok  " if (got >= want if want else got == 0) else "FAIL"
        if verdict == "FAIL":
            ok = False
        print(f"  {verdict} {name} ({got} finding(s))")
    return ok


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    print("lead-cycle-audit self-test")
    if not self_test():
        print("SELF-TEST FAILED")
        return 1
    if "--self-test" in sys.argv:
        print("  self-test passed")
        return 0
    read = lambda p: (root / p).read_text(encoding="utf-8", errors="replace")
    findings = audit(read(CYCLE), read(ROWS), read(FEED), read(LEDGER), read(ROOT), read(DEMO))
    if findings:
        print(f"lead-cycle-audit: {len(findings)} finding(s)")
        for f in findings:
            print(f"  ✗ {f}")
        return 1
    print("lead-cycle-audit: clean — the lead turns to its dock category's glyph and back, once")
    return 0


if __name__ == "__main__":
    sys.exit(main())
