#!/usr/bin/env python3
"""EVERY SHOWER IS THE APP'S OWN TILES, AND IT NAMES WHAT IT STANDS FOR (prd §655).

`TileRain` used to have two branches: a roster of source names fell as app
tiles (§619), and an EMPTY roster fell as sixteen coloured circles. §655 deleted
the circles — one surface raining confetti reads as confetti everywhere, and the
one case the circles survived for (a wallet-scoped pull or arrival, raining that
wallet's face colour to say WHICH account, §171/§501) is already said at full
strength by the crown's retint.

**The finding §655 came from is not the confetti, though — it is the ROSTER.**
`ShellChrome.refreshRoster` is stored state and a pulse bump is not a reset, so
eight writers that set the hue and the pulse by hand and never mentioned the
roster were raining WHATEVER THE LAST PULL LEFT. Pull on All, walk into the
Hegotá room, tap top up: Photos and Gmail and Strava fall over a devnet faucet
claim. Nothing about that fails to compile, nothing renders wrong, and no other
check here can see it — it is a correct-looking animation standing for the
wrong set.

So this guards the shape rather than the symptom.

**(1) No confetti in the layer.** `TileRain.swift` must declare no colour
palette for drops, must not set a drop's `backgroundColor`, and its `Drop.tile`
must be non-optional — the three things the berry branch needed. A `tile:
String?` is the tell that a colourless drop is representable again.

**(2) `refreshRoster` is `private(set)`.** The door is the guarantee: if a
writer can assign the roster directly it can also forget to.

**(3) Nobody bumps `refreshPulse` outside `ShellChrome`.** Naming the sources
is the only way to deal a shower, so `chrome.refreshPulse += 1` is a finding
wherever it appears. Comments and strings are stripped first — this file's own
callers document the rule by naming the property it governs, which is the
Obsidian/Cursor lesson this repo has paid for four times.

**(4) `refreshHue` is gone.** A stored value every writer set and no view read
is the fake status §83 bans, and its return would mean the colour path came
back with it.

**(5) `roomRevision` is `private(set)` and nobody bumps it either.** The §655
amendment split the two jobs `refreshPulse` was doing: it dealt the rain AND it
keyed `FeedScreen`'s memoised room head. Six sites bumped it for the second
reason only, so a watch, an unwatch and a key revoke each dealt a shower nobody
asked for — and the unwatch bumped TWICE, so REMOVING an address rained twice,
seconds apart. `refreshRooms()` moves the head and draws nothing.

**(6) No shower stands for nothing on purpose.** `rain(sources: [])` is a
literal empty roster, which deals nothing — reachable honestly (no source
connected) but never worth WRITING, since a caller that knows the set is empty
should not be dealing a shower at all.

**STATED CEILINGS.**

  * It cannot tell whether the seat a caller names is the RIGHT seat. A Frames
    card raining `[HegotaIdentity.source]` compiles, renders, and passes here.
    What it can prove is that some seat was named on purpose.
  * Check 3 is a text match on `refreshPulse` followed by an assignment or
    increment. A writer reaching the property through a computed alias, a
    keypath or a different receiver name is invisible to it.
  * It says nothing about the tiles LOOKING right — `BridgeIcon`'s fallback for
    a seat with no bundled asset is a glyph tile, which is the intent, but only
    a device shows that it reads as one.

`--self-test` runs first and is required, per this repo's rule that a check
which cannot demonstrate it catches anything certifies nothing.
"""
import re
import sys
import pathlib

SOURCES = ["Casberi/Casberi", "Casberi/Shared"]
LAYER = "TileRain.swift"
OWNER = "ShellChrome.swift"


def strip(text):
    """Comments and string literals out — the rule is documented by naming the
    very property it governs, so raw source fires on the prose explaining it."""
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"//[^\n]*", "", text)
    text = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', text)
    return text


def audit_text(name, text):
    out = []
    body = strip(text)

    if name == LAYER:
        # (1) the berry branch's three requirements
        if re.search(r"static\s+let\s+berry\s*:\s*\[Color\]", body):
            out.append(f"{name}: a drop colour palette is back — §655 deleted the confetti branch")
        if re.search(r"\bdot\.backgroundColor\s*=", body):
            out.append(f"{name}: a drop paints a background colour; every drop is a source's tile")
        if re.search(r"\blet\s+tile\s*:\s*String\?", body):
            out.append(f"{name}: Drop.tile is optional again — a colourless drop is representable")

    if name == OWNER:
        # (2) the door is the guarantee
        if not re.search(r"private\(set\)\s+var\s+refreshRoster\b", body):
            out.append(f"{name}: refreshRoster is not private(set) — a writer can bump without naming what falls")
        if not re.search(r"func\s+rain\s*\(\s*sources\s*:", body):
            out.append(f"{name}: rain(sources:) is missing — there is no door left that names the roster")
        if not re.search(r"private\(set\)\s+var\s+roomRevision\b", body):
            out.append(f"{name}: roomRevision is not private(set) — a list change can deal a shower again")
        if not re.search(r"func\s+refreshRooms\s*\(", body):
            out.append(f"{name}: refreshRooms() is missing — a list change has nowhere to go but the rain")
    else:
        # (3) nobody else bumps the pulse, or the revision behind its door
        for m in re.finditer(r"\broomRevision\s*(?:\+=|&\+=|=[^=])", body):
            line = body[:m.start()].count("\n") + 1
            out.append(f"{name}:{line}: bumps roomRevision directly — use chrome.refreshRooms()")
        for m in re.finditer(r"\brefreshPulse\s*(?:\+=|&\+=|=[^=])", body):
            line = body[:m.start()].count("\n") + 1
            out.append(f"{name}:{line}: bumps refreshPulse directly — deal a shower through chrome.rain(sources:)")
        # (3b) or writes the roster behind the door's back
        for m in re.finditer(r"\brefreshRoster\s*=[^=]", body):
            line = body[:m.start()].count("\n") + 1
            out.append(f"{name}:{line}: assigns refreshRoster directly — use chrome.rain(sources:)")

    # (4) the hue is deleted everywhere, this file included
    for m in re.finditer(r"\brefreshHue\b", body):
        line = body[:m.start()].count("\n") + 1
        out.append(f"{name}:{line}: refreshHue is deleted (§655) — a shower's colour is its tiles' own brand")

    # (5) a shower that stands for nothing, written on purpose
    for m in re.finditer(r"\brain\s*\(\s*sources\s*:\s*\[\s*\]\s*\)", body):
        line = body[:m.start()].count("\n") + 1
        out.append(f"{name}:{line}: rain(sources: []) deals nothing — do not deal a shower for no source")

    return out


# ---------------------------------------------------------------- fixtures

CLEAN_LAYER = """
struct TileRain: View {
    let trigger: Int
    var roster: [String] = []
}
fileprivate struct Drop: Identifiable {
    let id: Int
    let tile: String
    let spin: CGFloat
}
"""

BERRY_PALETTE = CLEAN_LAYER + """
    private static let berry: [Color] = [Color.fixed("#0a84ff")]
"""

BERRY_DRAW = CLEAN_LAYER + """
    func deal() { dot.backgroundColor = UIColor(drop.color).cgColor }
"""

OPTIONAL_TILE = """
fileprivate struct Drop: Identifiable {
    let id: Int
    let tile: String?
}
"""

CLEAN_OWNER = """
final class ShellChrome {
    var refreshPulse = 0
    private(set) var refreshRoster: [String] = []
    @MainActor
    func rain(sources: [String]) {
        refreshRoster = sources
        roomRevision &+= 1
        refreshPulse &+= 1
    }
    @MainActor
    func refreshRooms() { roomRevision &+= 1 }
    private(set) var roomRevision = 0
}
"""

OPEN_ROSTER = CLEAN_OWNER.replace("private(set) var refreshRoster", "var refreshRoster")
OPEN_REVISION = CLEAN_OWNER.replace("private(set) var roomRevision", "var roomRevision")
NO_ROOMS_DOOR = CLEAN_OWNER.replace("    @MainActor\n    func refreshRooms() { roomRevision &+= 1 }\n", "")
NO_DOOR = """
final class ShellChrome {
    var refreshPulse = 0
    private(set) var refreshRoster: [String] = []
    @MainActor
    func refreshRooms() { roomRevision &+= 1 }
    private(set) var roomRevision = 0
}
"""

# A list changed and the caller reached past the door to say so.
BARE_REVISION = """
private func onWatched() {
    chrome.roomRevision += 1
}
"""

# The shape the amendment blesses: a list change draws nothing.
ROOMS_CALLER = """
private func unwatch() {
    chrome.refreshRooms()
    Task { chrome.refreshRooms() }
}
"""

CLEAN_CALLER = """
private func pour() {
    chrome.rain(sources: [HegotaIdentity.source])
}
"""

BARE_BUMP = """
private func pour() {
    chrome.refreshHue = Self.mark
    chrome.refreshPulse &+= 1
}
"""

ROSTER_WRITE = """
private func pour() {
    chrome.refreshRoster = []
    chrome.refreshPulse += 1
}
"""

EMPTY_RAIN = """
private func pour() { chrome.rain(sources: []) }
"""

# The Obsidian/Cursor lesson: a caller's own doc names the property it must not
# touch, and a raw grep fires on the prose explaining the rule.
COMMENTED_CALLER = """
/// It rained in the wallet's own colour through `chrome.refreshHue` and bumped
/// `chrome.refreshPulse += 1` by hand until §655; both are gone.
private func pour() {
    chrome.rain(sources: ["Wallet"])
}
"""

STRINGED_CALLER = """
private func log() {
    NSLog("refreshHue and refreshPulse += 1 are gone")
    chrome.rain(sources: ["Wallet"])
}
"""

# A read is not a write — the shower's own mount reads the pulse every body pass.
READER = """
.overlay { TileRain(trigger: chrome.refreshPulse, roster: chrome.refreshRoster) }
"""


def self_test():
    cases = [
        ("passes the shipped one-branch layer", LAYER, CLEAN_LAYER, 0),
        ("flags  a drop colour palette", LAYER, BERRY_PALETTE, 1),
        ("flags  a drop painting a background", LAYER, BERRY_DRAW, 1),
        ("flags  an optional Drop.tile", LAYER, OPTIONAL_TILE, 1),
        ("passes the shipped chrome", OWNER, CLEAN_OWNER, 0),
        ("flags  a publicly writable roster", OWNER, OPEN_ROSTER, 1),
        ("flags  a chrome with no rain door", OWNER, NO_DOOR, 1),
        ("flags  a publicly writable roomRevision", OWNER, OPEN_REVISION, 1),
        ("flags  a chrome with no refreshRooms door", OWNER, NO_ROOMS_DOOR, 1),
        ("flags  a caller bumping roomRevision directly", "A.swift", BARE_REVISION, 1),
        ("passes a list change dealt through refreshRooms", "A.swift", ROOMS_CALLER, 0),
        ("passes a caller naming its seat", "A.swift", CLEAN_CALLER, 0),
        ("flags  a bare pulse bump AND its hue", "A.swift", BARE_BUMP, 2),
        ("flags  a direct roster write and its bump", "A.swift", ROSTER_WRITE, 2),
        ("flags  a shower dealt for no source", "A.swift", EMPTY_RAIN, 1),
        ("passes a caller documenting the deleted names", "A.swift", COMMENTED_CALLER, 0),
        ("passes the deleted names inside a string", "A.swift", STRINGED_CALLER, 0),
        ("passes a READ of the pulse and the roster", "A.swift", READER, 0),
        ("passes an empty file", "A.swift", "", 0),
    ]
    ok = True
    for label, name, text, want in cases:
        got = len(audit_text(name, text))
        mark = "ok  " if got == want else "FAIL"
        if got != want:
            ok = False
            for f in audit_text(name, text):
                print(f"       · {f}")
        print(f"  {mark} {label} (expected {want}, got {got})")
    return ok


def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    if "--self-test" in sys.argv:
        print("rain-tiles-audit self-test")
        if not self_test():
            print("SELF-TEST FAILED")
            return 1
        print("  self-test passed")

    findings, scanned = [], 0
    for src in SOURCES:
        base = root / src
        if not base.exists():
            continue
        for path in sorted(base.rglob("*.swift")):
            scanned += 1
            findings.extend(audit_text(path.name,
                                       path.read_text(encoding="utf-8", errors="replace")))

    if findings:
        print(f"rain-tiles-audit: {len(findings)} finding(s) in {scanned} files")
        for f in findings:
            print(f"  ✗ {f}")
        return 1
    print(f"rain-tiles-audit: clean ({scanned} files) — every shower is tiles and names its sources")
    return 0


if __name__ == "__main__":
    sys.exit(main())
