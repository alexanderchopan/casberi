#!/bin/zsh
# Casberi Markets-fold self-test — the ordering and resolution rules behind the
# folded Markets chip (2026-08-10):
#
#   Casberi/Casberi/Model/MarketsRoom.swift
#     — members       (derived from the catalog's own Markets category)
#     — fold          (which chip the market seats collapse into, and WHERE)
#     — chipLabel     (which chip lights while you stand in a folded seat)
#     — scopes        (the switcher's order)
#     — landing       (where the folded chip reopens)
#
# WHY A HARNESS. Every failure here is a SILENT WRONG ANSWER that renders as a
# perfectly good strip — the class this project keeps paying for:
#
#   • the fold landing at the TAIL instead of in the best-ranked member's slot,
#     so a strip you use constantly quietly reorders itself and the one chip
#     whose position you had learned is now somewhere else (the strip's own
#     "position is half the identity of an icon-only chip" ruling, 2026-07-30);
#   • the room label leaking into `FeedFilter.source`, which is the ONE
#     invariant this whole feature rests on — nothing downstream of the strip
#     may ever see the string "Markets";
#   • `chipLabel` returning the raw source, so standing in Kalshi lights no
#     chip at all and the room reads as unfiltered;
#   • the fold firing at ONE member, which replaces a brand mark you recognize
#     with a folder containing that same mark, plus a switcher with one scope;
#   • `scopes` following the caller's set order instead of the catalog's, so
#     the switcher reshuffles between opens over identical data.
#
# None of these can be caught by `xcodebuild`, by the static audits, or by a
# screen sweep: the strip draws beautifully in every one of them.
#
# `MarketsRoom.swift` is compiled WHOLE AND UNMODIFIED — it is Foundation-only
# by design, its ONLY dependency being `BridgeCatalog`, which is stubbed here as
# a small inert fixture. So every ordering this file asserts is the shipped
# code's own, not a copy that can drift from it.
#
# WHAT THE STUB CAN AND CANNOT PROVE. Against a fixture, `members` proves the
# DERIVATION (that it reads the category's groups, and that it spans BOTH
# "Markets" and "NFTs"), never that the real catalog still has a Markets
# category. That half is a drift guard against the real file below — otherwise
# a renamed category would empty `members`, un-fold the strip, and pass this
# harness with every assertion green.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

ROOM="Casberi/Casberi/Model/MarketsRoom.swift"
MAIN="Casberi/Casberi/Shell/MainSurface.swift"
CHIPS="Casberi/Casberi/Shell/SourceChips.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
SWITCHER="Casberi/Casberi/Screens/MarketsVenueSwitcher.swift"
BROWSE="Casberi/Casberi/Screens/PredictionBrowseSection.swift"
ROOT="Casberi/Casberi/Shell/RootShell.swift"
APP="Casberi/Casberi/CasberiApp.swift"
BOOK="Casberi/Casberi/Screens/PredictionRoomBook.swift"
CATALOG="Casberi/Casberi/Model/BridgeCatalog.swift"
for f in "$ROOM" "$MAIN" "$CHIPS" "$FEED" "$SWITCHER" "$BROWSE" "$BOOK" "$CATALOG" "$ROOT" "$APP"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/markets-fold-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# Negative guards read a COMMENT-STRIPPED copy (the Obsidian/Cursor lesson,
# earned twice): this feature's source DOCUMENTS the things it must never do
# ("keeps 'Markets' out of `filter.source`", "UN-GATED from `.all`"), so a guard
# grepping raw source fires against the prose explaining the rule it protects.
strip_comments() {
  python3 - "$1" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
src = re.sub(r'^\s*//.*$', '', src, flags=re.M)
src = re.sub(r'(?<!:)//.*$', '', src, flags=re.M)
print(src)
PY
}
strip_comments "$MAIN"   > "$TMP/main.nc"
strip_comments "$BROWSE" > "$TMP/browse.nc"
strip_comments "$BOOK"   > "$TMP/book.nc"
strip_comments "$ROOT"   > "$TMP/root.nc"
strip_comments "$APP"    > "$TMP/app.nc"

# --- drift guards -----------------------------------------------------------
# Wiring the compiled functions cannot prove on their own. A perfect `fold` is
# worthless if nothing calls it, and a perfect `chipLabel` is worthless if the
# strip still passes the raw source as its active chip.

grep -q 'MarketsRoom.fold(' "$TMP/main.nc" \
  || { echo "✗ MainSurface no longer folds the chip list — the market seats never collapse"; exit 1; }
grep -q 'active: activeChip' "$TMP/main.nc" \
  || { echo "✗ the strip is passed a raw source again — standing in a folded seat would light NO chip"; exit 1; }

# THE CENTRAL INVARIANT, and the reason this harness earns its slot in
# verify.sh. "Markets" is a chip LABEL; `FeedFilter.source` must always hold a
# real seat. `go(to:)` is the one place a label becomes a source, and it must
# write the RESOLVED value. Writing `filter.source = label` instead would put
# the literal "Markets" into every `@Query` predicate, every `Corpus` check and
# every deep link — a room that renders empty forever with no error anywhere.
grep -q 'filter.source = target' "$TMP/main.nc" \
  || { echo "✗ go(to:) no longer writes the RESOLVED seat — the room label can reach FeedFilter.source"; exit 1; }
grep -q 'MarketsRoom.landing(present:' "$TMP/main.nc" \
  || { echo "✗ the folded chip no longer resolves to a venue — tapping it would route nowhere"; exit 1; }

# THE TWO LEAK SITES, and they are here because both shipped broken in this
# feature's own first cut. `chrome.chipOrder` carries the FOLDED label, and two
# surfaces consumed it and wrote it straight into `FeedFilter.source`:
#
#   • the sources tray (`RootShell`), which is the one screen whose own doc says
#     it "claims to show every source" — fed the folded list it dropped all
#     seven market seats AND grew a "Markets" cell whose tap opened a room whose
#     predicate matches nothing, forever, with the folded chip lit as if it had
#     worked;
#   • Mac's ⌘1–⌘9 (`CasberiApp`), same write, same dead room.
#
# Both are invisible to a build and to every static audit, and the second is
# invisible on iOS entirely.
grep -q 'SourcesTray(labels: chrome.sourceOrder' "$TMP/root.nc" \
  || { echo "✗ the sources tray is back on chipOrder — it would drop every market seat"; \
       echo "  and offer a 'Markets' cell that writes a non-source into FeedFilter.source."; exit 1; }
grep -q 'MarketsRoom.isRoom(label)' "$TMP/app.nc" \
  || { echo "✗ ⌘1–⌘9 no longer resolves the folded label — it would write \"Markets\""; \
       echo "  into FeedFilter.source and open a permanently empty room."; exit 1; }

# The catch-bob and coin-flip key on the chip that is actually SHOWING. Keyed on
# the raw source instead, every arrival celebration for the whole cluster fires
# against a chip that isn't in the strip, and nothing moves — invisible.
grep -q 'chrome.chipCaught(MarketsRoom.chipLabel(' "$TMP/main.nc" \
  || { echo "✗ arrivals no longer bob the folded chip — every market celebration would be silent"; exit 1; }

grep -q 'MarketsRoom.room' "$CHIPS" \
  || { echo "✗ SourceChips has no case for the folded chip — it would render as a missing brand icon"; exit 1; }
grep -q 'MarketsVenueSwitcher(' "$FEED" \
  || { echo "✗ FeedScreen no longer mounts the venue switcher — a folded seat has no way out"; exit 1; }
# PINNED, not a List section — `walletSwitcherBar`'s 2026-07-20 ruling. As a
# section it scrolls away with the room it names, and its glass blurs nothing.
grep -qE 'safeAreaInset\(edge: \.top, spacing: 0\) \{ marketsSwitcher \}' "$FEED" \
  || { echo "✗ the venue switcher is no longer pinned — it would scroll away with the"; \
       echo "  room it scopes, and its glass would have nothing moving behind it."; exit 1; }

# The switcher and the prediction book must not BOTH offer a venue control —
# two capsules over one book, each able to change which venue you're reading,
# with no way to tell from either which one won.
grep -q 'foldedIntoMarkets' "$TMP/book.nc" \
  || { echo "✗ PredictionRoomBook's own switcher no longer stands down under the fold"; exit 1; }

# The twin price must NOT be gated on the merged scope again. §298's comparison
# was reachable only from `.all`, which the fold retires — re-gating it would
# make the one reading an aggregate produces silently disappear.
grep -qE 'scope == \.all \? await PredictionDisagreement' "$TMP/browse.nc" \
  && { echo "✗ the twin read is gated on .all again — the fold retires that scope, so"; \
       echo "  cross-venue disagreement would vanish from every room."; exit 1; }
grep -qE 'guard bothConnected else' "$TMP/browse.nc" \
  || { echo "✗ the twin read no longer keys on both venues being connected"; exit 1; }
# …and it must CLEAR stale prices when it stops being possible, or a
# disconnected venue's numbers sit on the cards claiming to be current.
grep -qE 'twinPrices = \[:\]' "$TMP/browse.nc" \
  || { echo "✗ twin prices are never cleared — a disconnected venue's numbers would persist"; exit 1; }
# A Polymarket card showing Kalshi's price under a Polymarket mark is the §83
# fake status, in the one place on the card where the whole point is which
# exchange said what.
grep -q 'twinVenue' "$TMP/browse.nc" \
  || { echo "✗ the twin bar no longer names whose price it is — it would wear the wrong mark"; exit 1; }
# `KalshiWatch.book` is a SUBSTRING scan of the whole query, not a search, so a
# per-row `book(p.title)` can never match a full Polymarket question. The first
# cut of findReverse did exactly that and was six awaits that always answered [].
grep -qE 'KalshiWatch\.book\(\s*""' "Casberi/Casberi/Model/PredictionDisagreement.swift" \
  || { echo "✗ findReverse no longer reads Kalshi's book once with an empty query —"; \
       echo "  a per-row title query hits a substring scan and matches nothing, ever."; exit 1; }
# The twin read must stay AFTER the book is committed, or six sequential
# searches hold the skeleton up on every room load.
python3 - "$TMP/browse.nc" <<'PY2'
import sys
src = open(sys.argv[1]).read()
try:
    loaded = src.index("loaded = true")
except ValueError:
    sys.exit("✗ `loaded = true` not found in PredictionBrowseSection")
twin = src.find("PredictionDisagreement.find")
if twin < 0:
    sys.exit("✗ the twin read is gone from PredictionBrowseSection")
if twin < loaded:
    sys.exit("✗ the twin read runs BEFORE the book is committed — six sequential\n"
             "  searches would hold the skeleton up on every room load.")
PY2

# THE REAL CATALOG still answers. The stub below proves the derivation; only
# this proves the derivation still finds anything. A renamed category empties
# `members`, un-folds the strip permanently, and breaks nothing loudly.
python3 - "$CATALOG" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r'\("Markets",\s*"[^"]+",\s*\[([^\]]*)\]\)', src)
if not m:
    sys.exit('✗ BridgeCatalog.categories no longer has a "Markets" category —\n'
             '  MarketsRoom.members would be EMPTY and the fold would never happen.')
groups = re.findall(r'"([^"]+)"', m.group(1))
if not groups:
    sys.exit("✗ the Markets category names no groups — members would be empty.")
n = sum(len(re.findall(r'group:\s*"%s"' % re.escape(g), src)) for g in groups)
if n < 2:
    sys.exit(f"✗ only {n} offer(s) sit in the Markets category's groups {groups} —\n"
             "  below MarketsRoom.foldFloor, so the fold could never happen.")
print(f"  ✓ real catalog: Markets category spans {groups}, {n} offers")
PY

# --- the fixture catalog ----------------------------------------------------
# Deliberately spans BOTH groups the real category names, plus non-members on
# either side, so `members` has something real to get wrong.
cat > "$TMP/stub.swift" <<'SWIFT'
import Foundation

enum BridgeCatalog {
    struct Offer { let name: String; let group: String }
    static let categories: [(name: String, exemplar: String, groups: Set<String>)] = [
        ("Wallet",  "Wallet", ["Wallet"]),
        ("Markets", "Kalshi", ["Markets", "NFTs"]),
    ]
    static let offers: [Offer] = [
        Offer(name: "Wallet",     group: "Wallet"),
        Offer(name: "Tokens",     group: "Markets"),
        Offer(name: "Kalshi",     group: "Markets"),
        Offer(name: "Polymarket", group: "Markets"),
        Offer(name: "Stocktwits", group: "Markets"),
        Offer(name: "OpenSea",    group: "NFTs"),
        Offer(name: "Photos",     group: "Photos"),
    ]
}
SWIFT

# --- the driver -------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") }
    else { print("  ✗ \(label)"); failures += 1 }
}

let M = MarketsRoom.memberSet

// --- members: the derivation -----------------------------------------------
// Spans BOTH groups the category names. A `$0.group == "Markets"` shortcut
// would drop OpenSea and pass every other assertion in this file.
check("members spans both category groups",
      MarketsRoom.members == ["Tokens", "Kalshi", "Polymarket", "Stocktwits", "OpenSea"])
check("a non-member is not a member", !MarketsRoom.isMember("Photos"))
check("the room label is not itself a member", !MarketsRoom.isMember(MarketsRoom.room))

// --- fold: the floor --------------------------------------------------------
check("no fold with zero members present",
      MarketsRoom.fold(["All", "Photos", "Wallet"], members: M) == ["All", "Photos", "Wallet"])
// ONE member keeps its own chip: folding it would swap a brand mark for a
// folder holding that same mark, and hand it a switcher with one scope.
check("no fold with one member present",
      MarketsRoom.fold(["All", "Kalshi", "Photos"], members: M) == ["All", "Kalshi", "Photos"])

// --- fold: the position ruling ----------------------------------------------
// The folded chip inherits the slot of the BEST-RANKED member it replaces, so
// ChipMemory's learning still decides where the cluster sits. Appending to the
// tail is the mutation this pins.
check("folds into the first member's slot",
      MarketsRoom.fold(["All", "Photos", "Kalshi", "Wallet", "Tokens"], members: M)
        == ["All", "Photos", "Markets", "Wallet"])
check("non-members keep their relative order",
      MarketsRoom.fold(["Kalshi", "Photos", "Tokens", "Wallet"], members: M)
        == ["Markets", "Photos", "Wallet"])
check("the room is inserted exactly ONCE for five members",
      MarketsRoom.fold(["All", "Tokens", "Kalshi", "Polymarket", "Stocktwits", "OpenSea"], members: M)
        == ["All", "Markets"])
check("every member is removed",
      MarketsRoom.fold(["All", "Tokens", "Photos", "OpenSea"], members: M)
        .allSatisfy { !M.contains($0) })
check("folding is idempotent",
      MarketsRoom.fold(MarketsRoom.fold(["All", "Tokens", "Kalshi"], members: M), members: M)
        == ["All", "Markets"])

// --- chipLabel: which chip lights -------------------------------------------
let folded = MarketsRoom.fold(["All", "Tokens", "Kalshi", "Photos"], members: M)
check("a folded member lights the room chip",
      MarketsRoom.chipLabel(for: "Kalshi", folded: folded) == MarketsRoom.room)
check("a non-member lights itself",
      MarketsRoom.chipLabel(for: "Photos", folded: folded) == "Photos")
// UNFOLDED, a member must light ITSELF — returning the room label here would
// point at a chip that isn't in the strip, which reads as no filter at all.
check("an unfolded member lights itself",
      MarketsRoom.chipLabel(for: "Kalshi", folded: ["All", "Kalshi", "Photos"]) == "Kalshi")

// --- scopes: the switcher's order -------------------------------------------
// CATALOG order, never the caller's. A switcher that reorders itself between
// opens over identical data reads as broken — the strip's own ruling, one
// level down. The reversed input is the point.
check("scopes follow catalog order, not the caller's",
      MarketsRoom.scopes(present: ["OpenSea", "Kalshi", "Tokens"]) == ["Tokens", "Kalshi", "OpenSea"])
check("scopes exclude absent members",
      !MarketsRoom.scopes(present: ["Tokens", "Kalshi"]).contains("OpenSea"))
check("scopes exclude non-members",
      MarketsRoom.scopes(present: ["Tokens", "Photos"]) == ["Tokens"])

// --- landing: where the chip reopens ----------------------------------------
let key = "markets.lastVenue"
UserDefaults.standard.removeObject(forKey: key)
check("with no memory, lands on the first present venue",
      MarketsRoom.landing(present: ["Kalshi", "Tokens"]) == "Kalshi")
check("with nothing present, lands nowhere", MarketsRoom.landing(present: []) == nil)
MarketsRoom.remember("Polymarket")
check("remembers a member", UserDefaults.standard.string(forKey: key) == "Polymarket")
check("reopens where you left off",
      MarketsRoom.landing(present: ["Tokens", "Polymarket"]) == "Polymarket")
// A remembered venue that has since disappeared (disconnected, last row
// deleted) must NOT be handed back — that is a room with no door.
check("a remembered venue that vanished falls back",
      MarketsRoom.landing(present: ["Tokens", "Kalshi"]) == "Tokens")
MarketsRoom.remember("Photos")
check("refuses to remember a non-member",
      UserDefaults.standard.string(forKey: key) == "Polymarket")
UserDefaults.standard.removeObject(forKey: key)

print(failures == 0 ? "markets-fold-selftest: OK" : "markets-fold-selftest: \(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
SWIFT

echo "markets-fold-selftest: compiling MarketsRoom.swift as shipped…"
swiftc -O -o "$TMP/run" "$ROOM" "$TMP/stub.swift" "$TMP/main.swift" 2>&1 | grep -v '^ *$' || true
[[ -x "$TMP/run" ]] || { echo "✗ compile failed — MarketsRoom.swift no longer builds Foundation-only"; exit 1; }
"$TMP/run" || exit 1

# --- mutation pass ----------------------------------------------------------
# Each mutation is a plausible edit that must be CAUGHT. A check that cannot
# fail proves nothing (the `--self-test` doctrine used by every audit here).
mutate() {
  local label="$1" expr="$2"
  python3 - "$ROOM" "$TMP/mutated.swift" "$expr" <<'PY'
import sys, re
src = open(sys.argv[1]).read()
old, new = sys.argv[3].split("|||")
if old not in src:
    sys.exit(f"✗ mutation anchor not found: {old!r} — this harness is testing stale code")
open(sys.argv[2], "w").write(src.replace(old, new, 1))
PY
  if swiftc -O -o "$TMP/mrun" "$TMP/mutated.swift" "$TMP/stub.swift" "$TMP/main.swift" 2>/dev/null \
     && "$TMP/mrun" >/dev/null 2>&1; then
    echo "  ✗ mutation SURVIVED: $label"
    return 1
  fi
  echo "  ✓ mutation caught: $label"
}

echo "markets-fold-selftest: mutation pass…"
mfail=0
mutate "fold appends to the tail instead of the member's slot" \
  'if !placed { folded.append(room); placed = true }|||continue' || mfail=1
# …and the other half of that ruling: a tail append that still inserts once.
mutate "fold inserts the room once, at the END" \
  'var folded: [String] = []
        var placed = false
        for label in ordered {
            guard members.contains(label) else { folded.append(label); continue }
            if !placed { folded.append(room); placed = true }
        }
        return folded|||var folded = ordered.filter { !members.contains($0) }
        folded.append(room)
        return folded' || mfail=1
mutate "fold inserts the room once per member" \
  'if !placed { folded.append(room); placed = true }|||folded.append(room)' || mfail=1
mutate "the fold floor drops to one seat" \
  'static let foldFloor = 2|||static let foldFloor = 1' || mfail=1
mutate "chipLabel returns the raw source while folded" \
  'folded.contains(room) && isMember(source) ? room : source|||source' || mfail=1
mutate "members reads only the first group" \
  'BridgeCatalog.offers.filter { groups.contains($0.group) }|||BridgeCatalog.offers.filter { $0.group == room }' || mfail=1
mutate "scopes follows the caller's order" \
  'members.filter { present.contains($0) }|||Array(present)' || mfail=1
mutate "landing ignores whether the remembered venue is still present" \
  'present.contains(last) { return last }|||!last.isEmpty { return last }' || mfail=1
mutate "remember accepts a non-member" \
  'guard isMember(source),|||guard true,' || mfail=1

[[ $mfail -eq 0 ]] || { echo "markets-fold-selftest: a mutation SURVIVED — a check above proves nothing"; exit 1; }
echo "markets-fold-selftest: OK — fold order, resolution and switcher order all pinned."
