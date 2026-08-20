#!/bin/zsh
# Casberi Circle x402 self-test — verifies the SHIPPED pure logic behind the
# x402 marketplace bridge (2026-08-06):
#
#   Casberi/Casberi/Model/CircleX402Bridge.swift
#     — X402Category        (the seven lanes, and which strings map to them)
#     — X402Ingest.usd      (USDC base units rendered as money)
#     — Provider.priceLine  (the zero-price rule, quirk 4)
#     — Builder             (folding 955 listings down to 22 providers)
#     — summaryLine/tags    (what a landed row actually says)
#
# WHY A HARNESS. Unlike Cursor or Stripe, this bridge IS measurable — the
# directory is keyless and was read end-to-end while it was written. What is
# NOT measurable that way is the arithmetic: a live curl proves the wire shape,
# and proves nothing about whether a $0.0001 call renders as "$0.00" once it
# reaches a row. Every failure here is a SILENT WRONG NUMBER that renders
# perfectly:
#
#   • a fifth of the marketplace missing because the read went back to the
#     API's own `category` filter, which accepts six of the seven values its
#     own data carries (quirk 1 — the defect this bridge is shaped around);
#   • a price of "$0.00" on a paid service, because 37 listings quote a zero
#     and a naive minimum takes it (quirk 4). "From $0.00" reads as free;
#   • sub-cent prices flattened to two decimals, which is the same lie in a
#     different place — QuickNode's entire catalog is $0.0001 a call;
#   • a provider silently never landing because its category is one this build
#     doesn't know (quirk 2), which looks exactly like a company that hasn't
#     listed yet.
#
# `CircleX402Bridge.swift` cannot compile as shipped (it builds `Thing`, a
# SwiftData model, and calls `IngestSupport`'s networking), so the pure
# functions are EXTRACTED from the shipped source by name — never copied into
# this file — so the harness cannot pass against logic the app doesn't run. The
# only transformation is stripping `private `. If an extraction stops matching,
# the compile fails loudly rather than asserting nothing.
#
# Pure, local, deterministic — no network, no key, no simulator. Exit non-zero
# on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

X402="Casberi/Casberi/Model/CircleX402Bridge.swift"
ROOM="Casberi/Casberi/Model/X402Room.swift"
FACES="Casberi/Casberi/Model/X402Faces.swift"
TREEMAP="Casberi/Casberi/Design/UnitTreemap.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
CONTENT="Casberi/Casberi/Screens/ThingContent.swift"
SUPPORT="Casberi/Casberi/Model/IngestSupport.swift"
THING="Casberi/Shared/Thing.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
REFRESH="Casberi/Casberi/Model/BridgeRefresh.swift"
SCREEN="Casberi/Casberi/Screens/CircleX402Screen.swift"
GENUI="Casberi/Casberi/GenUI/GenRenderer.swift"
for f in "$X402" "$ROOM" "$FACES" "$TREEMAP" "$FEED" "$CONTENT" "$SUPPORT" "$THING" "$REACH" "$REFRESH" "$SCREEN" "$GENUI"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- drift guards -----------------------------------------------------------
# Wiring facts the extracted functions can't prove on their own. A perfect
# `usd` is worthless if nothing calls `X402Ingest.refresh`.
#
# Every negative guard below greps a COMMENT-STRIPPED copy, and that is this
# harness's own first finding rather than a precaution: the quirk-1 guard fired
# on the first run against a perfectly correct bridge, because the file's own
# header explains the defect by NAMING it ("rejects `category=DATA_ENRICHMENT`
# with a 400"). A guard that a file's documentation can trip is a guard that
# gets deleted the week after it lands — the setup-copy audit learned the same
# lesson when it started reading copy quoted in comments.
TMP=$(mktemp -d /tmp/x402-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
CODE="$TMP/code.swift"
# Drops whole-line `//` and `///` comments only. A trailing comment after real
# code survives on purpose: erasing it would need a string-literal-aware parser,
# and leaving it can only ever make a negative guard STRICTER, never blinder.
sed -E '/^[[:space:]]*\/\//d' "$X402" > "$CODE"

# THE QUIRK-1 GUARD, and the reason this harness earns its place in verify.sh.
# Circle's own filter rejects `category=DATA_ENRICHMENT` with a 400 naming its
# six legal options, while 185 of the 955 listings (19%) are stamped exactly
# that. Anyone "optimising" the walk into a per-lane server-side query would
# empty a fifth of the marketplace with no error anywhere — and the room would
# look completely healthy. The read must stay unfiltered.
grep -q 'category=' "$CODE" \
  && { echo "✗ the walk now passes a server-side ?category= filter."; \
       echo "  Circle's filter accepts SIX values; its data carries SEVEN"; \
       echo "  (DATA_ENRICHMENT, 19% of the catalog). Filtering server-side"; \
       echo "  silently drops that lane. Filter on device — see quirk 1."; exit 1; }

# THE CONDUCT GUARD. x402 is a PAYMENT protocol — every listing in this
# directory exists to be bought, and each carries a `payTo` address and a
# price. The catalog copy promises Casberi "never pays for a call, and there's
# no path here that could". That promise is kept only by this file issuing
# exactly one verb against exactly one path. Prose is what CLAUDE.md calls
# memory, and memory lost.
for verb in '"POST"' '"DELETE"' '"PATCH"' '"PUT"' 'httpMethod' 'postJSON' 'deleteJSON'; do
  grep -q "$verb" "$CODE" \
    && { echo "✗ CircleX402Bridge.swift now contains a WRITE ($verb) — the catalog's"; \
         echo "  'never pays for a call' promise is now a lie."; \
         echo "  Change that copy in the same commit, or drop the write."; exit 1; }
done
# …and the positive half: the only transport it may use.
grep -qE 'IngestSupport\.getJSON\(' "$CODE" \
  || { echo "✗ CircleX402Bridge.swift no longer reads through IngestSupport's GET funnel"; exit 1; }
# A payTo address is the one field in the payload that could only ever be used
# to send money. It must never be read, stored, or landed.
grep -q 'payTo' "$CODE" \
  && { echo "✗ the bridge now reads payTo — the one field that exists only to be paid"; exit 1; }

grep -q 'api.circle.com' "$REACH" \
  || { echo "✗ api.circle.com is not in the reach registry — the privacy screen is wrong"; exit 1; }
grep -q 'X402Ingest.refresh' "$REFRESH" \
  || { echo "✗ the foreground sweep no longer refreshes x402 — the bridge lands nothing"; exit 1; }
# Quirk 3: `lastUpdated` is bulk-restamped and cannot date an arrival, so a row
# is stamped when it reached the feed. Reading the API's own field would
# backdate every row to whenever Circle last reindexed.
grep -q 'capturedAt: .now' "$CODE" \
  || { echo "✗ rows no longer stamp .now — lastUpdated is bulk-restamped (quirk 3)"; exit 1; }
grep -q 'lastUpdated' "$CODE" \
  && { echo "✗ the bridge now reads lastUpdated — it records Circle's reindex, not an arrival"; exit 1; }
# 500 is a 400, not a clamp.
grep -qE 'static let pageSize = (200|1[0-9]{2}|[1-9][0-9]?)$' "$CODE" \
  || { echo "✗ pageSize is missing or above the API's max of 200 (500 is a 400, not a clamp)"; exit 1; }
# Quirk 2: an unmapped category must not remove a provider from the feed.
grep -q 'allCategoriesUnknown' "$CODE" \
  || { echo "✗ the lane filter no longer admits an unmapped category — providers would vanish"; exit 1; }
# The truncation must be COUNTED, never silent (§307).
grep -q 'truncated' "$CODE" \
  || { echo "✗ the walk no longer reports truncation — a grown directory would read as complete"; exit 1; }
# The screen's "watch every lane" button must stay gated, or it is a control
# that does nothing once every lane is on (the honesty rule's dead control).
grep -q 'if !watchingEverything' "$SCREEN" \
  || { echo "✗ the 'watch every lane' button is no longer gated — it becomes a dead control"; exit 1; }

# --- the room's wiring (2026-08-06) -----------------------------------------
# The head and the row shape are what make this a room rather than a list, and
# every one of these is a silent regression: the feed keeps rendering, just
# worse, exactly as it did before the shape existed.

grep -q 'case X402Ingest.source:     self = .x402' "$FEED" \
  || { echo "✗ the feed no longer shapes the x402 room — it falls back to plain BandRows"; exit 1; }
grep -q 'X402RoomSource.compose' "$FEED" \
  || { echo "✗ the room head is no longer resolved — the ranking has nowhere to live"; exit 1; }
grep -q 'X402RoomCard' "$FEED" \
  || { echo "✗ the room head is resolved but never drawn"; exit 1; }
# THE DEAD-CODE GUARD. The first attempt at this feature put the branch in
# `ThingContent`'s `default:` case — but these rows are `.link`, which has its
# own case, so it could never be reached. Build green, grep guard green, feature
# doing nothing. So the guard checks the ROUTE, not the words: the seller card
# must be constructed, and the source must NOT reappear in the default branch.
grep -q 'X402SellerContent(thing: thing)' "$CONTENT" \
  || { echo "✗ the sheet no longer draws the seller's catalog"; exit 1; }
content_code="$TMP/content.swift"
sed -E '/^[[:space:]]*\/\//d' "$CONTENT" > "$content_code"
awk '/default:/{f=1} f&&/X402Ingest.source/{found=1} END{exit found?1:0}' "$content_code" \
  || { echo "✗ x402 is back in ThingContent's default: branch — its rows are .link,"; \
       echo "  so that branch is unreachable for them and the feature would be dead code."; exit 1; }
grep -q 'X402Faces.heal' "$REFRESH" \
  || { echo "✗ the faces pass is never run — every row keeps the same glyph"; exit 1; }

# LANES, NOT DAYS. Every seller lands on the walk that first sees it, so the
# whole room shares one timestamp: day-grouping yields ONE section holding
# every row, which is a grouping that does no work. This reverts silently —
# the feed still renders, just back to a single undifferentiated pile — so
# both halves are guarded: the lane grouping is called, and the chronological
# one is not. The window ENDS AT THE NEXT `case`, never at a named one: it
# used to close on `case .tokens:`, so a room inserted between the two (the
# Walletbeat room, 2026-08-20) put ITS legitimate `chronoGroups` inside x402's
# window and failed a check about a room it does not touch. A guard that fires
# on its neighbour's correct code gets turned off within a week.
grep -q 'groupedSections(x402Lanes(visible)' "$FEED" \
  || { echo "✗ the x402 room no longer groups by lane — it falls back to one 'Today' pile"; exit 1; }
feed_code="$TMP/feed.swift"
sed -E '/^[[:space:]]*\/\//d' "$FEED" > "$feed_code"
awk '/case \.x402:/{f=1; next} f&&/^[[:space:]]*case \./{f=0} f&&/chronoDays|chronoGroups/{print; found=1} END{exit found?1:0}' "$feed_code" \
  || { echo "✗ the x402 room went back to chronological grouping — every row shares one"; \
       echo "  timestamp, so that is a single section with no information in it."; exit 1; }
# The lane's biggest seller leads it. Without this each shelf is an
# undifferentiated run with nothing to read down from.
grep -q 'CircleX402Row(thing: thing, lead: index == 0)' "$FEED" \
  || { echo "✗ the lane leader no longer leads — shelves lose their landmark"; exit 1; }

# THE LANE STRIP (2026-08-06). §269 killed a chip that APPEARED as a
# consequence of agent state; this is a control you operate, and the difference
# is that it is always present and always lists every lane. Both halves are
# guarded: the strip is drawn, and it SCOPES THE HEAD as well as the rows —
# a card describing 22 companies over two filtered rows is two surfaces
# disagreeing on one screen.
grep -q 'x402LaneStrip' "$FEED" \
  || { echo "✗ the lane strip is gone — three lanes become unreachable again"; exit 1; }
grep -q 'X402RoomSource.compose(things: visible, lane: x402Lane)' "$FEED" \
  || { echo "✗ the head no longer narrows with the strip — it would describe a"; \
       echo "  marketplace the person just filtered away."; exit 1; }
grep -q 'shape == .x402 ? x402Scoped(allVisible) : allVisible' "$FEED" \
  || { echo "✗ the strip no longer scopes the room"; exit 1; }
# Reused verbatim from the prediction strip; a second visual language for the
# same job is the drift the design system exists to prevent.
grep -q 'Capsule().fill(isOn ? DS.tint : DS.fillFaint)' "$FEED" \
  || { echo "✗ the lane chip drifted off PredictionBrowseSection.viewChip's styling"; exit 1; }

# THE FACES GUARD, and the strongest of this group. `X402Faces` reads a
# company's own marketing page. Circle's directory is the authority on who these
# companies ARE; their `<title>` is SEO ("Alchemy | The Web3 Development
# Platform"). §245 made this exact ruling for Instagram's imported rows. The
# pass must stamp the picture and nothing else.
faces_code="$TMP/faces.swift"
sed -E '/^[[:space:]]*\/\//d' "$FACES" > "$faces_code"
grep -qE '\.title[[:space:]]*=' "$faces_code" \
  && { echo "✗ X402Faces now writes a title — a seller's SEO slogan would overwrite"; \
       echo "  the name Circle's directory gave it (the §245 ruling)."; exit 1; }
grep -q 'previewImageURL = image' "$faces_code" \
  || { echo "✗ X402Faces no longer stamps the picture — the pass does nothing"; exit 1; }
# Its hosts come from Circle's directory, so no static registry can declare
# them; the call must name its own service or every seller's domain reads as an
# undisclosed reach on the receipts screen.
grep -q 'NetworkLedger.shared.record(request, as: X402Ingest.source)' "$faces_code" \
  || { echo "✗ the faces fetch no longer names its service — its hosts read as undisclosed"; exit 1; }

# The model/view constant pair. `X402Room.drawnCap` must leave room for the
# folded tail inside `UnitTreemap.maxCells`, and the two are spelled in separate
# files because the model is Foundation-only and cannot see the view. Set them
# equal and the tail is silently clipped — a dropped seller looking exactly like
# a marketplace that had five (§300's own failure).
# THE TREEMAP'S ONE CLAIM. `UnitTreemap` is rank-ordered, not
# area-proportional (§300), so the only thing a reader may infer from a tile's
# size is its RANK. A table where area rises with rank breaks exactly that, and
# it shipped: the six-cell layout gave rank 3 one unit and ranks 4–5 two each,
# so the third-biggest term drew smaller than the fifth. User-reported against
# the X room's map, 2026-08-06. Checked here for EVERY cell count, and the
# tiling is verified to fill all twelve units with no overlap — a layout that
# ranks correctly but leaves a hole is just a different bug.
python3 - "$TREEMAP" <<'PY' || exit 1
import re, sys
src = open(sys.argv[1]).read()
body = src[src.index("static func frames"):]
body = body[:body.index("static var maxCells")]
bad = 0
for m in re.finditer(r'case ([0-9, ]+):\s*return \[(.*?)\]\n', body, re.S):
    labels = [int(x) for x in m.group(1).replace(" ", "").split(",") if x]
    frames = [tuple(int(v) for v in f.split(","))
              for f in re.findall(r'\(([^)]*)\)', m.group(2))]
    areas = [w * h for _, _, w, h in frames]
    n = max(labels)
    if any(areas[i] < areas[i + 1] for i in range(len(areas) - 1)):
        print(f"  ✗ frames({n}): area RISES with rank {areas} — a smaller value would draw bigger")
        bad = 1
    grid = {}
    for (x, y, w, h) in frames:
        for dx in range(w):
            for dy in range(h):
                cell = (x + dx, y + dy)
                if cell in grid:
                    print(f"  ✗ frames({n}): cells overlap at {cell}"); bad = 1
                grid[cell] = 1
    if len(grid) != 12:
        print(f"  ✗ frames({n}): tiles {len(grid)} of 12 units — the board has a hole"); bad = 1
# `default:` is the six-cell table and carries no `case` label.
m = re.search(r'default:\s*return \[(.*?)\]\n', body, re.S)
frames = [tuple(int(v) for v in f.split(",")) for f in re.findall(r'\(([^)]*)\)', m.group(1))]
areas = [w * h for _, _, w, h in frames]
if any(areas[i] < areas[i + 1] for i in range(len(areas) - 1)):
    print(f"  ✗ frames(6): area RISES with rank {areas} — rank 3 would draw smaller than rank 5"); bad = 1
grid = {}
for (x, y, w, h) in frames:
    for dx in range(w):
        for dy in range(h):
            if (x + dx, y + dy) in grid:
                print(f"  ✗ frames(6): cells overlap at {(x+dx, y+dy)}"); bad = 1
            grid[(x + dx, y + dy)] = 1
if len(grid) != 12:
    print(f"  ✗ frames(6): tiles {len(grid)} of 12 units — the board has a hole"); bad = 1
sys.exit(bad)
PY

# ONE TABLE, and only one. The check above proves `UnitTreemap.frames` ranks
# correctly and proves NOTHING about a second copy of it elsewhere — which is
# not hypothetical: `GenTagMap` (the wallet's holdings map, the themes lede)
# carried its own private 4×3 table from the day the shared one was extracted,
# so the 2026-08-06 correction reached the receipts / x402 / topic maps and
# left the holdings map drawing rank 3 SMALLER than ranks 4 and 5 (fixed
# 2026-08-07). Two tables is the whole failure: each is internally consistent,
# each renders perfectly, and the disagreement is only visible to someone
# holding both maps side by side — which is exactly what `UnitTreemap`'s doc
# says can never be allowed to happen. So the guard is not "both tables must
# rank correctly", it is "there is one table". A tiling literal anywhere else
# in the app fails the build, and names itself.
grep -q 'UnitTreemap<EmptyView>.frames(items.count)' "$GENUI" \
  || { echo "✗ GenTagMap no longer reads UnitTreemap's table — the holdings map"; \
       echo "  can drift from the receipts / x402 / topic maps again."; exit 1; }
python3 - "$TREEMAP" <<'PY' || exit 1
import os, re, sys
owner = os.path.abspath(sys.argv[1])
# A 4×3 tiling table: an array literal of four-int tuples that all fit the unit
# grid and cover a real part of it. Bounded below at 2 tuples and 6 units so an
# ordinary array of small quadruples somewhere else can't read as a treemap.
lit = re.compile(r'\[\s*(\((?:\s*\d+\s*,){3}\s*\d+\s*\)(?:\s*,\s*)?)+\]')
bad = 0
for root, dirs, files in os.walk("Casberi"):
    dirs[:] = [d for d in dirs if d not in (".build", "build")]
    for name in files:
        if not name.endswith(".swift"): continue
        path = os.path.join(root, name)
        if os.path.abspath(path) == owner: continue
        for i, line in enumerate(open(path, errors="replace"), 1):
            if line.lstrip().startswith("//"): continue
            for m in lit.finditer(line):
                t = [tuple(int(v) for v in f.split(","))
                     for f in re.findall(r'\(([^)]*)\)', m.group(0))]
                if len(t) < 2: continue
                if not all(x + w <= 4 and y + h <= 3 for x, y, w, h in t): continue
                if not 6 <= sum(w * h for _, _, w, h in t) <= 12: continue
                print(f"  ✗ {path}:{i} carries its own 4×3 treemap table")
                print(f"    {m.group(0)}")
                print("    Call UnitTreemap.frames(_:) instead — a second table is how the")
                print("    holdings map and the receipts map came to disagree about rank 3.")
                bad = 1
sys.exit(bad)
PY

drawn=$(grep -oE 'static let drawnCap = [0-9]+' "$ROOM" | grep -oE '[0-9]+')
maxc=$(grep -oE 'static var maxCells: Int \{ [0-9]+ \}' "$TREEMAP" | grep -oE '[0-9]+')
[[ -n "$drawn" && -n "$maxc" ]] \
  || { echo "✗ couldn't read drawnCap / maxCells — the tail-fits guard is blind"; exit 1; }
(( drawn < maxc )) \
  || { echo "✗ X402Room.drawnCap ($drawn) leaves no cell for the folded tail"; \
       echo "  inside UnitTreemap.maxCells ($maxc) — the tail would be clipped away."; exit 1; }

# --- extract the shipped functions -----------------------------------------
extract() {  # $1 = source bridge file, $2 = output path
python3 - "$1" "$SUPPORT" "$THING" "$ROOM" "$2" <<'PY'
import sys
x402, support, thing, room, out = sys.argv[1:6]

def grab(path, signature):
    """The whole declaration whose line contains `signature`, brace-matched
    from the shipped source. Never a copy."""
    src = open(path).read()
    i = src.find(signature)
    if i < 0:
        sys.exit(f"✗ extraction failed: {signature!r} not found in {path}")
    start = src.rfind("\n", 0, i) + 1
    j = src.index("{", i)
    depth, k = 0, j
    while k < len(src):
        if src[k] == "{": depth += 1
        elif src[k] == "}":
            depth -= 1
            if depth == 0: break
        k += 1
    return src[start:k+1].replace("private ", "")

def grabline(path, signature):
    """A single-line declaration. Needed for brace-less constants: `grab`
    matches from the next `{`, so on `static let detailCap = 12` it would
    swallow the whole FOLLOWING function — the trap the X harness recorded."""
    for line in open(path).read().splitlines():
        if signature in line:
            return line.replace("private ", "")
    sys.exit(f"✗ extraction failed: {signature!r} not found in {path}")

pieces = [
    "import Foundation\n",
    grab(x402, "enum X402Category"),
    "",
    grab(x402, "enum X402State"),
    "",
    grab(x402, "enum X402Networks"),
    "",
    grab(thing, "extension Array where Element == String"),
    "",
    "enum IngestSupport {",
    grab(support, "static func titleLine"),
    "}\n",
    "enum X402Ingest {",
    grabline(x402, "static let detailCap"),
    grab(x402, "static func median"),
    grab(x402, "struct Provider {"),
    grab(x402, "struct Builder {"),
    grab(x402, "static func usd"),
    grab(x402, "static func headline"),
    grab(x402, "static func summaryLine"),
    grab(x402, "static func retrievalText"),
    grab(x402, "static func tags(for"),
    "}\n",
    # X402Room is Foundation-only BY DESIGN so it compiles whole and
    # unmodified — no extraction, no transformation, nothing that could
    # diverge from what ships.
    open(room).read(),
]
open(out, "w").write("\n".join(pieces))
PY
}
extract "$X402" "$TMP/extracted.swift"

# --- the driver -------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}

/// Builds a provider the way `walk()` does — by absorbing raw listing
/// dictionaries — so the tests exercise the real folding path, not a
/// hand-built struct that could drift from it.
func fold(name: String = "Acme", detail: String? = "Does things",
          website: String? = "https://acme.example",
          category: String = "FINANCIAL_ANALYSIS",
          tags: [String] = ["x402", "crypto"],
          amounts: [[Any]] = [["20000"]]) -> X402Ingest.Provider {
    var b = X402Ingest.Builder(name: name, slug: name.lowercased())
    var unknown = Set<String>()
    for accepts in amounts {
        var provider: [String: Any] = ["name": name, "category": category, "tags": tags]
        if let detail { provider["description"] = detail }
        if let website { provider["website"] = website }
        let item: [String: Any] = [
            "accepts": accepts.map { ["amount": $0] },
            "metadata": ["description": "an endpoint"],
        ]
        b.absorb(provider: provider, item: item, unknown: &unknown)
    }
    return b.provider
}

print("usd — USDC base units are 6 decimals, and sub-cent prices are REAL")
// QuickNode's entire measured catalog is 100 base units a call. At two decimal
// places that whole company reads as free.
check("100 → $0.0001",          X402Ingest.usd(100) == "$0.0001")
check("20000 → $0.02",          X402Ingest.usd(20000) == "$0.02")
check("3500000 → $3.50",        X402Ingest.usd(3500000) == "$3.50")
check("10000000 → $10.00",      X402Ingest.usd(10000000) == "$10.00")
check("10000 → $0.01 (the boundary)", X402Ingest.usd(10000) == "$0.01")
check("1 → $0.0000 is never produced for a real price", X402Ingest.usd(100) != "$0.00")
// Found by DRAWING the room, not by reading the code: AIsa API's cheapest call
// really is ONE base unit — a millionth of a dollar — and at four decimals the
// marketplace's own floor rendered "from $0.0000 a call". A real, payable price
// displayed as free is quirk 4's failure wearing a different mask.
check("1 base unit → $0.000001, not $0.0000", X402Ingest.usd(1) == "$0.000001")
check("99 base units keep their value",       X402Ingest.usd(99) == "$0.000099")
check("the 4-decimal tier still holds",       X402Ingest.usd(100) == "$0.0001")
check("no real price ever renders as zeroes",
      ![1, 9, 50, 99, 100, 1_000, 10_000].map(X402Ingest.usd)
        .contains { Double($0.dropFirst()) == 0 })

print("priceLine — a zero quote is a FACT, never the minimum (quirk 4)")
// 37 of the 955 measured listings quote 0 — free operations sitting beside
// paid ones. A naive min() reports "$0.0000" for four of the biggest sellers.
let mixed = fold(amounts: [["0"], ["20000"], ["350000"]])
check("a zero doesn't become the floor", mixed.minPrice == 20000)
check("the ceiling is still the dearest", mixed.maxPrice == 350000)
check("free is recorded separately",      mixed.hasFree == true)
check("the line says both",  mixed.priceLine == "some free, then $0.02–$0.35 a call")
let paid = fold(amounts: [["20000"], ["20000"]])
check("one price reads flat, not as a range", paid.priceLine == "$0.02 a call")
check("nothing free is claimed",             paid.hasFree == false)
let freeOnly = fold(amounts: [["0"], ["0"]])
check("all-zero reads 'free'",  freeOnly.priceLine == "free")
check("all-zero has no minimum", freeOnly.minPrice == nil)
let unpriced = fold(amounts: [[]])
check("no quote at all → no price line", unpriced.priceLine == nil)
check("an unpriced provider says nothing about money",
      X402Ingest.summaryLine(unpriced) == "1 service")

print("amount parsing — the wire sends strings, and garbage is not zero")
check("a string amount parses",  fold(amounts: [["20000"]]).minPrice == 20000)
check("an Int amount parses",    fold(amounts: [[20000]]).minPrice == 20000)
check("garbage is skipped, not read as 0", fold(amounts: [["nope"], ["20000"]]).minPrice == 20000)

print("X402Category — the seventh lane is the whole point (quirk 1)")
check("FINANCIAL_ANALYSIS maps",  X402Category.from("FINANCIAL_ANALYSIS") == .financial)
// The lane Circle's own filter refuses to serve. 185 measured listings.
check("DATA_ENRICHMENT maps",     X402Category.from("DATA_ENRICHMENT") == .enrichment)
check("PREDICTION_MARKETS maps",  X402Category.from("PREDICTION_MARKETS") == .prediction)
check("CREATIVE maps",            X402Category.from("CREATIVE") == .creative)
check("lowercase maps",           X402Category.from("creative") == .creative)
check("all seven measured lanes are present", X402Category.allCases.count == 7)
check("an unknown lane maps to nil", X402Category.from("QUANTUM_ASTROLOGY") == nil)

print("an unmapped category must not delete a provider from the feed (quirk 2)")
let alien = fold(category: "QUANTUM_ASTROLOGY")
check("its lanes read as unknown", alien.allCategoriesUnknown == true)
check("a known lane does not",     fold().allCategoriesUnknown == false)
// Falling out of the picker must never mean falling out of the feed — the
// §307 silent-drop lesson. `refresh` admits this provider on that flag alone.
check("a provider in a KNOWN lane still reports its lane",
      fold().known.map(\.display) == ["Financial analysis"])

print("the website is third-party data before it is a tappable link")
check("https is kept",       fold(website: "https://acme.example").website == "https://acme.example")
check("http is refused",     fold(website: "http://acme.example").website == nil)
check("javascript: is refused", fold(website: "javascript:alert(1)").website == nil)
check("a hostless URL is refused", fold(website: "https:///nope").website == nil)
check("a dotless host is refused", fold(website: "https://localhost").website == nil)
check("missing is nil, not a crash", fold(website: nil).website == nil)

print("headline & clamp — a provider's blurb is third-party text")
check("name and blurb join", X402Ingest.headline(fold()) == "Acme · Does things")
check("no blurb → bare name", X402Ingest.headline(fold(detail: nil)) == "Acme")
let long = fold(name: "Acme", detail: String(repeating: "long ", count: 40))
check("the title clamps to the corpus's one-line invariant",
      IngestSupport.titleLine(X402Ingest.headline(long)).count == 81)

print("summaryLine — what the row says it sells")
check("plural services", X402Ingest.summaryLine(fold(amounts: [["20000"], ["20000"]]))
        == "2 services · $0.02 a call")
check("one service is singular", X402Ingest.summaryLine(fold(amounts: [["20000"]]))
        == "1 service · $0.02 a call")

print("tags & retrieval text")
let tags = X402Ingest.tags(for: fold())
check("x402 leads",           tags.first == "x402")
check("the lane rides along", tags.contains("Financial analysis"))
check("no duplicates",        tags.count == Set(tags.map { $0.lowercased() }).count)
// Retrieval-only by the 2026-07-15 ruling — it exists so a search for a word
// the title never says still reaches the row.
check("the provider's own tags are searchable",
      X402Ingest.retrievalText(fold()).contains("crypto"))
check("retrieval text stays inside the embedding window",
      X402Ingest.retrievalText(fold(tags: (0..<400).map { "tag\($0)" })).count <= 800)

// MARK: - The room head

func sellers(_ pairs: [(String, Int)], free: Bool = false,
             low: Int? = 20000, high: Int? = 350000) -> [X402State.Seller] {
    pairs.map { X402State.Seller(slug: $0.0.lowercased(), name: $0.0, services: $0.1,
                                 minPrice: low, maxPrice: high, hasFree: free,
                                 lanes: ["Financial analysis"]) }
}

print("X402Room.compose — the ranking the feed itself cannot carry")
// Every row in this room shares one timestamp, so newest-first ranks nothing.
check("one seller is no comparison → nil",
      X402Room.compose(sellers: sellers([("Solo", 9)]), listings: 9) == nil)
check("none → nil", X402Room.compose(sellers: [], listings: 0) == nil)
let two = X402Room.compose(sellers: sellers([("Small", 2), ("Big", 40)]), listings: 42)
check("two sellers draw two cells", two?.cells.count == 2)
check("biggest leads", two?.cells.first?.label == "Big")
check("no tail when everything fits", two?.cells.contains { $0.isTail } == false)

// The fold. 7 sellers → 5 drawn + 1 named tail = 6, which is exactly
// UnitTreemap's ceiling. A silently dropped seller looks like a smaller
// marketplace (§300).
let many = X402Room.compose(
    sellers: sellers([("A", 100), ("B", 90), ("C", 80), ("D", 70),
                      ("E", 60), ("F", 50), ("G", 40)]), listings: 490, typical: 20000)
check("seven sellers fold to six cells", many?.cells.count == 6)
check("the last cell is the tail", many?.cells.last?.isTail == true)
check("the tail NAMES what it hides", many?.cells.last?.label == "2 more")
check("the tail sums the folded", many?.cells.last?.services == 90)
check("the tail is never a seller id", many?.cells.last?.id == X402Room.Cell.tailID)
check("every seller is still counted", many?.sellers == 7)
let one = X402Room.compose(
    sellers: sellers([("A", 5), ("B", 4), ("C", 3), ("D", 2), ("E", 1), ("F", 1)]), listings: 16)
check("a tail of one is singular", one?.cells.last?.label == "1 more")

print("headline & note — the size, and the price of entry")
check("sellers is the headline unit",
      X402Room.headline(many!) == "7 companies are selling to agents")
check("the listing count is the walk's own total, not the sum of cells",
      many?.listings == 490)
check("note says size then TYPICAL price, never the floor",
      X402Room.note(many!, money: X402Ingest.usd) == "490 services · typically $0.02 a call")
// The §83 rule in the one room where money is the point.
let freeish = X402Room.compose(sellers: sellers([("A", 3), ("B", 2)], free: true),
                               listings: 5, typical: 20000)
check("a free operation never becomes the advertised price",
      X402Room.note(freeish!, money: X402Ingest.usd) == "5 services · some free · typically $0.02 a call")
let allFree = X402Room.compose(
    sellers: sellers([("A", 3), ("B", 2)], free: true, low: nil, high: nil), listings: 5)
check("nothing priced reads 'free'",
      X402Room.note(allFree!, money: X402Ingest.usd) == "5 services · free")
let quiet = X402Room.compose(
    sellers: sellers([("A", 3), ("B", 2)], low: nil, high: nil), listings: 0)
check("it says nothing it doesn't know",
      X402Room.note(quiet!, money: X402Ingest.usd) == "")
// THE RULING (user, 2026-08-06: "do median"). One dust-priced endpoint must
// not set the headline. Measured on the live directory: the floor is
// $0.000001 (AIsa quotes ONE base unit) while the median call is $0.01 —
// four orders of magnitude apart, and only one of them describes a price
// anybody meets.
check("a dust endpoint does NOT set the headline",
      X402Room.compose(sellers: [
        X402State.Seller(slug: "a", name: "A", services: 2, minPrice: 1,
                         maxPrice: 9000, hasFree: false, lanes: []),
        X402State.Seller(slug: "b", name: "B", services: 1, minPrice: 100,
                         maxPrice: 500, hasFree: false, lanes: []),
      ], listings: 3, typical: 10000).map { X402Room.note($0, money: X402Ingest.usd) }
      == "3 services · typically $0.01 a call")

print("median — the typical call, never the mean")
// Measured across 885 priced listings: median $0.01, mean $0.15. The mean is
// dragged 15x by a handful of $8–$10 calls and describes no real listing.
check("odd count takes the middle",   X402Ingest.median([100, 20000, 9_000_000]) == 20000)
check("even count averages the two",  X402Ingest.median([10000, 20000]) == 15000)
check("a fat tail cannot drag it",    X402Ingest.median([10000, 10000, 10000, 10_000_000]) == 10000)
check("free listings are excluded, not counted as zero",
      X402Ingest.median([0, 0, 0, 10000, 20000]) == 15000)
check("nothing priced → nil",         X402Ingest.median([]) == nil)
check("all free → nil",               X402Ingest.median([0, 0]) == nil)

print("chains — testnets are not where money settles")
check("Base is named",       X402Networks.named(["eip155:8453"]).names == ["Base"])
// §250's ruling: pretend money filed beside real money is fake status.
check("Base Sepolia is excluded", X402Networks.named(["eip155:84532"]).names == [])
check("Polygon Amoy is excluded", X402Networks.named(["eip155:80002"]).names == [])
// THE DISCRIMINATING CHECK, and the two above are not it. A testnet id isn't
// in the names table either way, so `.names == []` passes even with the filter
// deleted — the mutation SURVIVED against those two alone (the retriever
// harness's "right result for the wrong reason" lesson). The filter's real
// effect is that a testnet contributes NOTHING: not a name, and not an
// unknown-chain count that would make the sheet say "and 1 more".
check("a testnet is not even counted as an unknown chain",
      X402Networks.named(["eip155:84532", "eip155:80002"]).unknown == 0)
check("a testnet beside a real chain leaves it alone",
      X402Networks.named(["eip155:8453", "eip155:84532"]) == (["Base"], 0))
check("commonest chain leads",
      X402Networks.named(["eip155:137", "eip155:8453", "eip155:8453"]).names == ["Base", "Polygon"])
// §307: an id we can't name is COUNTED, never dropped.
check("an unknown chain is counted", X402Networks.named(["eip155:424242"]).unknown == 1)
check("an unknown chain is not named", X402Networks.named(["eip155:424242"]).names == [])
check("one chain reads plainly",  X402Networks.line(["Base"]) == "Base")
check("two chains read 'and'",    X402Networks.line(["Base", "Polygon"]) == "Base and Polygon")
check("three list out",           X402Networks.line(["Base", "Polygon", "Sei"]) == "Base, Polygon and Sei")
check("past three folds",
      X402Networks.line(["Base", "Polygon", "Sei", "Solana", "Optimism"]) == "Base, Polygon and Sei and 2 more")
check("unknowns join the fold",   X402Networks.line(["Base"], unknown: 2) == "Base and 2 more")
check("no chains → nothing said",  X402Networks.line([]) == nil)

print("the lane strip — the head narrows with the rows")
let laneRoom = X402Room.compose(sellers: sellers([("BlockRun.AI", 138), ("AIsa API", 94)]),
                                listings: 232, typical: 20000, lane: "Prediction markets")
// A head still saying "22 companies" over two filtered rows is two surfaces
// disagreeing on one screen.
check("the headline names the lane",
      X402Room.headline(laneRoom!) == "2 companies in prediction markets")
check("the lane is lowercased at the join, not shouted",
      X402Room.headline(laneRoom!).contains("in prediction markets"))
check("one seller in a lane still reads as a sentence",
      X402Room.compose(sellers: sellers([("A", 3), ("B", 1)]), listings: 4,
                       lane: "Creative").map(X402Room.headline) == "2 companies in creative")
check("unscoped keeps the marketplace headline",
      X402Room.headline(many!) == "7 companies are selling to agents")
check("the scoped note counts only the lane",
      X402Room.note(laneRoom!, money: X402Ingest.usd) == "232 services · typically $0.02 a call")

print("share — area is service count, and only service count")
check("the biggest tile is fully washed",
      X402Room.share(many!.cells[0], in: many!) == 1.0)
check("half the leader washes half",
      X402Room.compose(sellers: sellers([("Big", 100), ("Half", 50)]), listings: 150)
        .map { X402Room.share($0.cells[1], in: $0) } == 0.5)

print(failures == 0 ? "\nx402-selftest: OK" : "\nx402-selftest: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

run_harness() {  # $1 = dir holding extracted.swift + main.swift
  swiftc -O -o "$1/harness" "$1/extracted.swift" "$1/main.swift" 2>&1
}

if ! out=$(run_harness "$TMP"); then
  echo "✗ harness failed to compile against the shipped source:"
  echo "$out"
  exit 1
fi
"$TMP/harness" || exit 1

# --- mutation pass ----------------------------------------------------------
# A check that cannot fail proves nothing. Each mutation is a real defect this
# bridge could ship; the harness must reject every one.
echo
echo "mutation pass — each of these must be CAUGHT"
mutate() {  # $1 = label, $2 = sed program, $3 = file to mutate (default: the bridge)
  local dir="$TMP/mut" target="${3:-$X402}"
  rm -rf "$dir"; mkdir -p "$dir"
  cp "$X402" "$dir/src.swift"; cp "$ROOM" "$dir/room.swift"
  local out="$dir/src.swift"; [[ "$target" == "$ROOM" ]] && out="$dir/room.swift"
  sed "$2" "$target" > "$out"
  if ! cmp -s "$out" "$target"; then :; else
    echo "  ✗ $1 — mutation matched nothing (the harness is testing stale code)"; return 1
  fi
  ROOM="$dir/room.swift" extract "$dir/src.swift" "$dir/extracted.swift"
  cp "$TMP/main.swift" "$dir/main.swift"
  if ! run_harness "$dir" >/dev/null 2>&1; then
    echo "  ✓ $1 (rejected at compile)"; return 0
  fi
  if "$dir/harness" >/dev/null 2>&1; then
    echo "  ✗ $1 — SURVIVED"; return 1
  fi
  echo "  ✓ $1"
}

bad=0
# The sub-cent lie: every price rendered at two decimals.
mutate "usd flattens sub-cent prices to \$0.00" 's/value >= 0\.01/value >= 0.0/' || bad=1
# The third tier, and the one no code review noticed was missing: AIsa API's
# cheapest call is ONE base unit, which at four decimals renders "$0.0000" —
# a real, payable price shown as free. Found by drawing the room.
mutate "usd drops the tier a real listing needs" 's/%\.6f/%.4f/' || bad=1
# Quirk 4 undone: a zero quote becomes the advertised minimum.
mutate "a zero quote is taken as the price floor" 's/if amount == 0 { hasFree = true; freeHere = true; continue }/if amount == 0 { hasFree = true; freeHere = true }/' || bad=1
# The median must ignore free listings, or 70 zeroes drag the typical price
# toward a number nobody pays.
mutate "free listings drag the median down" 's/let sorted = prices.filter { \$0 > 0 }.sorted()/let sorted = prices.sorted()/' || bad=1
# §250's ruling: pretend money must not be filed beside real money.
mutate "testnets count as places money settles" 's/for id in raw where !testnets.contains(id)/for id in raw/' || bad=1
# Quirk 1 undone at the data layer: the seventh lane stops resolving.
mutate "DATA_ENRICHMENT stops mapping to a lane" 's/case enrichment     = "DATA_ENRICHMENT"/case enrichment     = "DATA_ENRICHMENT_X"/' || bad=1
# Quirk 2 undone: an unmapped lane silently removes a provider.
mutate "an unmapped lane no longer admits a provider" 's/var allCategoriesUnknown: Bool { known.isEmpty }/var allCategoriesUnknown: Bool { false }/' || bad=1
# A directory-supplied link is attacker-influenced text.
mutate "a non-https website becomes a tappable link" 's/url.scheme?.lowercased() == "https"/url.scheme != nil/' || bad=1
# The range collapses to a single number, so a $10 ceiling reads as $0.02.
mutate "the price ceiling stops tracking the dearest call" 's/maxPrice = max(maxPrice ?? amount, amount)/maxPrice = minPrice/' || bad=1

# --- the room head ----------------------------------------------------------
# A lone seller drawn as a treemap is one square saying "all of it" — a drawing
# with no information in it.
mutate "a single seller draws a head anyway" 's/guard ranked.count >= 2 else { return nil }/guard ranked.count >= 1 else { return nil }/' "$ROOM" || bad=1
# The fold overflows UnitTreemap and the tail is clipped — sellers vanish.
mutate "drawnCap leaves no room for the tail" 's/static let drawnCap = 5/static let drawnCap = 6/' "$ROOM" || bad=1
# Smallest-first: the map would rank backwards while looking perfectly fine.
mutate "the ranking inverts" 's/($0.services, $1.name) > ($1.services, $0.name)/($0.services, $1.name) < ($1.services, $0.name)/' "$ROOM" || bad=1
# "from $0.00" on a marketplace that charges — §83 where money is the point.
mutate "a free operation becomes the advertised floor" 's/room.hasFree$/false/' "$ROOM" || bad=1
# Wash by share-of-total rather than share-of-leader: every tile pales and the
# map stops reading at all.
mutate "the wash denominator changes" 's/let top = room.cells.map(\\.services).max() ?? 0/let top = room.cells.map(\\.services).reduce(0, +)/' "$ROOM" || bad=1

echo
if (( bad )); then echo "x402-selftest: mutation pass FAILED"; exit 1; fi
echo "x402-selftest: OK — shipped logic verified, 14 mutations caught."
