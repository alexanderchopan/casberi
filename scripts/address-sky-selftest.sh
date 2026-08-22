#!/bin/zsh
# The sky's layout, proven (prd §435, 2026-08-21).
#
# WHY THIS EXISTS. `AddressSky` decides where every body in the wallet
# manager's map sits, and every way it can be wrong renders as a perfectly
# good-looking picture:
#
#   • a body sitting between two wallets it never transacted with — an
#     invented relationship, drawn as confidently as a real one;
#   • two people stacked on one spot, so a book of six connections shows five;
#   • positions that move between two opens over identical data, which reads
#     as the app being broken (the `agent-panel-selftest` tile-sort lesson);
#   • a group named over a cluster that isn't its own;
#   • a link to a wallet that is no longer watched, keeping a dead watch alive
#     in the picture.
#
# None of that fails a build, a screen sweep or any static audit. So the file
# is compiled WHOLE and UNMODIFIED — it is Foundation-only by design for
# exactly this reason — and fed cases whose answers are known.
#
# It also carries the DRIFT GUARDS for the facts that live in two files: the
# view's face sizes against the layout's own diameters (spelled separately
# because the model cannot name `DS.Face`), and the §295 rulings this pass
# inherits, which are negatives — "no link carries a weight", "no figure
# appears" — and so cannot be proven by any assertion about output.
set -euo pipefail
# THE ZSH TRAP THIS HARNESS PAID FOR: inside a FUNCTION, `$0` expands to the
# function's own name, not the script's path — so the mutation prober below
# re-invoked itself as `probe --run`, which is not a command, and the whole
# self-test printed its header and exited silently having proven nothing. A
# check that cannot fail is exactly what this file exists to prevent, so the
# path is captured once, here, before any function can shadow it. (`:A`
# resolves it absolutely, so the `cd` on the next line cannot strand it.)
SELF="${0:A}"
cd "$(dirname "$SELF")/.."

SRC="Casberi/Casberi/Model/AddressSky.swift"
VIEW="Casberi/Casberi/Screens/AddressSkyView.swift"
SOURCE="Casberi/Casberi/Model/AddressSkySource.swift"
SCREEN="Casberi/Casberi/Screens/WalletScreen.swift"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# ---------------------------------------------------------------- self-test
if [[ "${1:-}" == "--self-test" ]]; then
  print "address-sky-selftest: self-test…"
  # A check that cannot fail proves nothing: demonstrate that the harness
  # catches each shape it exists to catch, on a scratch copy.
  probe() {  # <description> <sed-expression> <expect-fail:yes|no>
    local desc="$1" expr="$2" want="$3"
    local dir=$(mktemp -d)
    cp "$SRC" "$dir/AddressSky.swift"
    sed -i '' "$expr" "$dir/AddressSky.swift"
    if SKY_SRC="$dir/AddressSky.swift" "$SELF" --run >/dev/null 2>&1; then
      [[ "$want" == "no" ]] && print "  ✓ self-test: $desc" || { print "  ✗ self-test: $desc SURVIVED"; rm -rf "$dir"; exit 1; }
    else
      [[ "$want" == "yes" ]] && print "  ✓ self-test: $desc" || { print "  ✗ self-test: $desc broke a clean tree"; rm -rf "$dir"; exit 1; }
    fi
    rm -rf "$dir"
  }
  probe "an unchanged copy passes" "s/__nothing__/__nothing__/" "no"
  probe "the two-wallet floor removed" "s/watched.count >= minWallets/watched.count >= 0/" "yes"
  probe "twins no longer spread apart" "s/static let twinSpread = 0.115/static let twinSpread = 0.0/" "yes"
  # sin(π/2) is 1, so this freezes the cluster ring at the two-twin radius —
  # the n=2 fixture still passes exactly, and only the three- and six-twin
  # spacing assertions can catch it. That is the point: it proves the larger
  # clusters are load-bearing fixtures, not decoration on the pair case.
  probe "the twin ring's radius no longer scales with the cluster" \
    "s/Double.pi \/ Double(max(total, 2))/Double.pi \/ 2/" "yes"
  probe "the inward pull sent to the midpoint" "s/static let inwardPull = 0.62/static let inwardPull = 1.0/" "yes"
  probe "a body reaching one wallet still drawn" "s/guard keys.count >= 2 else { continue }/guard keys.count >= 1 else { continue }/" "yes"
  probe "links to unwatched wallets kept" "s/let keys = node.walletKeys.filter { walletAt\[\$0\] != nil }/let keys = node.walletKeys/" "yes"
  probe "a one-member group named" "s/guard list.count >= 2, let name/guard list.count >= 1, let name/" "yes"
  # REVERSED rather than deleted, and that is not a stylistic choice: Swift
  # seeds Dictionary hashing PER PROCESS, so a `constellations` built straight
  # off a dictionary comes out in a different order every launch — which means
  # the delete-the-sort mutation passed roughly one run in two, by luck. A
  # mutation that only sometimes survives is a defect in the ASSERTION, not
  # noise to re-run through. Reversing the comparator fails every time, and the
  # drift guard below catches the deletion deterministically.
  probe "constellations sorted the wrong way" "s/== .orderedAscending }/== .orderedDescending }/" "yes"
  probe "the ring no longer starts at the top" "s/let angle = -Double.pi \/ 2/let angle = Double.pi \/ 2/" "yes"
  probe "twin signature stops sorting" "s/keys.sorted().joined/keys.joined/" "yes"
  print "address-sky-selftest: self-test OK"
fi

# ------------------------------------------------------------------ harness
SKY="${SKY_SRC:-$SRC}"
cp "$SKY" "$work/AddressSky.swift"

cat > "$work/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { FileHandle.standardError.write("  ✗ \(what)\n".data(using: .utf8)!); failures += 1 }
}
func near(_ a: Double, _ b: Double, _ eps: Double = 0.0001) -> Bool { abs(a - b) < eps }

func wallet(_ n: String) -> AddressSky.Wallet {
    AddressSky.Wallet(key: n, address: "0x\(n)", name: n)
}
func connected(_ n: String, _ reaches: [String],
               groups: [String] = [], isNew: Bool = false) -> AddressSky.Connected {
    AddressSky.Connected(key: n, address: "0x\(n)", name: n,
                         walletKeys: reaches, groups: groups, isNew: isNew)
}

let two = [wallet("A"), wallet("B")]
let three = [wallet("A"), wallet("B"), wallet("C")]

// ---- the floor -----------------------------------------------------------
check(AddressSky.layout(watched: [], connected: [], canWatchMore: true) == nil,
      "no wallets draws no sky")
check(AddressSky.layout(watched: [wallet("A")], connected: [], canWatchMore: true) == nil,
      "one wallet draws no sky — nothing to be connected TO")
check(AddressSky.layout(watched: two, connected: [], canWatchMore: false) != nil,
      "two wallets and no connections still draws — the shape is the reading")

// ---- the ring ------------------------------------------------------------
guard let ring = AddressSky.layout(watched: three, connected: [], canWatchMore: false) else {
    fatalError("ring: no sky")
}
check(ring.watchedBodies.count == 3, "every watched wallet is a body")
check(ring.bodies.allSatisfy { $0.kind != .openSlot }, "a full shelf offers no slot")
// First watched sits at the TOP: y below centre, x on it.
let first = ring.watchedBodies[0]
check(near(first.at.x, 0.5), "the first watched wallet is centred horizontally")
check(first.at.y < 0.5, "the first watched wallet is at the top of the ring")
// Every body is the SAME distance from the centre — a ring, not a scatter.
let radii = ring.watchedBodies.map { (($0.at.x - 0.5) * ($0.at.x - 0.5)
                                    + ($0.at.y - 0.5) * ($0.at.y - 0.5)).squareRoot() }
check(radii.allSatisfy { near($0, AddressSky.ringRadius) }, "every wallet sits on the ring")
// Clockwise: the second body is to the RIGHT of the first.
check(ring.watchedBodies[1].at.x > ring.watchedBodies[0].at.x, "the ring runs clockwise")
// It stays inside the drawing, bodies included.
check(ring.bodies.allSatisfy {
    let r = AddressSky.watchedDiameter / 2
    return $0.at.x - r > 0 && $0.at.x + r < 1 && $0.at.y - r > 0 && $0.at.y + r < 1
}, "no body hangs outside the field")

// ---- the open slot -------------------------------------------------------
guard let withSlot = AddressSky.layout(watched: two, connected: [], canWatchMore: true) else {
    fatalError("slot: no sky")
}
let slots = withSlot.bodies.filter { $0.kind == .openSlot }
check(slots.count == 1, "exactly ONE invitation, never one per free watch")
check(slots.first?.id == AddressSky.openSlotID, "the slot wears its constant id")
check(slots.first?.address.isEmpty == true, "the slot stands for no address")
check(withSlot.bodies.count == 3, "the slot joins the ring rather than sitting beside it")
// Adding the slot RE-SPACES the ring: two wallets alone sit opposite.
let bare = AddressSky.layout(watched: two, connected: [], canWatchMore: false)!
check(bare.watchedBodies[1].at != withSlot.watchedBodies[1].at,
      "the invitation is a ring slot, so joining it re-spaces the sky")

// ---- connected bodies ----------------------------------------------------
guard let sky = AddressSky.layout(watched: three,
                                  connected: [connected("m", ["A", "B"])],
                                  canWatchMore: false) else { fatalError("sky") }
check(sky.connectedBodies.count == 1, "a connection is a body")
check(sky.links.count == 2, "one link per wallet reached, never one per connection")
// It sits BETWEEN the two it reaches: nearer both of them than to the third.
let m = sky.connectedBodies[0].at
func dist(_ a: AddressSky.Point, _ b: AddressSky.Point) -> Double {
    (((a.x - b.x) * (a.x - b.x)) + ((a.y - b.y) * (a.y - b.y))).squareRoot()
}
let a = sky.watchedBodies[0].at, b = sky.watchedBodies[1].at, c = sky.watchedBodies[2].at
check(dist(m, a) < dist(m, c) && dist(m, b) < dist(m, c),
      "a connected body sits nearer the wallets it reaches than the one it doesn't")
check(dist(m, AddressSky.Point(x: 0.5, y: 0.5)) < AddressSky.ringRadius,
      "a connected body sits inside the ring")
// OFF the chord between its own wallets — the assertion `inwardPull` actually
// needs, and the reason the two above are not enough. A body sent all the way
// to the midpoint (pull 1.0) is still nearer both wallets than the third AND
// still inside the ring, so both of those pass while the body sits exactly ON
// the line joining them and swallows its own two links. Standing lesson,
// third instance in this repo: a fixture only tests the rule it names if it
// FAILS that rule and passes every other one.
func offLine(_ p: AddressSky.Point, _ u: AddressSky.Point, _ v: AddressSky.Point) -> Double {
    let dx = v.x - u.x, dy = v.y - u.y
    let len = ((dx * dx) + (dy * dy)).squareRoot()
    guard len > 0 else { return dist(p, u) }
    return abs((p.x - u.x) * dy - (p.y - u.y) * dx) / len
}
check(offLine(m, a, b) > 0.02,
      "a connected body sits OFF the chord between its wallets, so both links stay visible")

// ---- one wallet is not a connection --------------------------------------
let lone = AddressSky.layout(watched: three,
                             connected: [connected("x", ["A"])],
                             canWatchMore: false)!
check(lone.connectedBodies.isEmpty, "reaching ONE wallet is not a connection — nothing is drawn")
check(lone.links.isEmpty, "and it contributes no link")

// ---- an unwatched wallet can't hold anything up --------------------------
let stale = AddressSky.layout(watched: two,
                              connected: [connected("y", ["A", "B", "GONE"])],
                              canWatchMore: false)!
check(stale.links.count == 2, "a link to a wallet we no longer watch is dropped")
let strandedOnly = AddressSky.layout(watched: two,
                                     connected: [connected("z", ["A", "GONE"])],
                                     canWatchMore: false)!
check(strandedOnly.connectedBodies.isEmpty,
      "an address left reaching one watched wallet stops being a connection")

// ---- twins ---------------------------------------------------------------
let twins = AddressSky.layout(watched: two,
                              connected: [connected("p", ["A", "B"]),
                                          connected("q", ["A", "B"])],
                              canWatchMore: false)!
let tp = twins.connectedBodies[0].at, tq = twins.connectedBodies[1].at
check(dist(tp, tq) > 0.05, "two people reaching the same pair do not stack")
check(near(dist(tp, tq), AddressSky.twinSpread, 0.001), "twins spread by exactly one spread")
// Order-insensitive: "A,B" and "B,A" are ONE cluster.
let flipped = AddressSky.layout(watched: two,
                                connected: [connected("p", ["A", "B"]),
                                            connected("q", ["B", "A"])],
                                canWatchMore: false)!
check(dist(flipped.connectedBodies[0].at, flipped.connectedBodies[1].at) > 0.05,
      "the twin cluster is order-insensitive")
// Three twins ring their shared midpoint: the cluster's CENTROID is the
// point a lone body would take (a regular ring's centroid is its centre),
// and every pair sits exactly one spread apart — for a triangle every pair
// is a neighbouring chord.
let trips = AddressSky.layout(watched: two,
                              connected: [connected("p", ["A", "B"]),
                                          connected("q", ["A", "B"]),
                                          connected("r", ["A", "B"])],
                              canWatchMore: false)!
let solo = AddressSky.layout(watched: two,
                             connected: [connected("q", ["A", "B"])],
                             canWatchMore: false)!
let tripPts = trips.connectedBodies.map(\.at)
check(near(tripPts.map(\.x).reduce(0, +) / 3, solo.connectedBodies[0].at.x)
      && near(tripPts.map(\.y).reduce(0, +) / 3, solo.connectedBodies[0].at.y),
      "a twin cluster is centred on the shared midpoint")
check((0..<3).allSatisfy { i in (0..<3).allSatisfy { j in
    i == j || near(dist(tripPts[i], tripPts[j]), AddressSky.twinSpread, 0.001)
} }, "three twins each sit one spread from both others")
// Two wallets sit exactly opposite, so their midpoint IS the centre — the
// degenerate case the perpendicular would divide by zero on.
check(trips.connectedBodies.allSatisfy { $0.at.x.isFinite && $0.at.y.isFinite },
      "an on-centre midpoint spreads rather than producing NaN")

// ---- the chain bug (2026-08-22, prd §436) --------------------------------
// SIX twins over TWO wallets — the sky's first real drawing, and the shape
// the straight-line spread was never checked at. At the minimum wallet count
// every connected address reaches the same pair BY CONSTRUCTION, so the
// whole drawn set (`AddressConnections.nodeLimit` is 6) is one cluster; the
// old perpendicular chain spanned 0.575 of the field and ran clean through
// both watched faces (measured against the old arithmetic: wallet clearance
// 0.063 where face-to-face needs 0.135, extent 0.358 past the 0.33 ring).
// Every assertion here FAILS the chain and passes the ring — the standing
// fixture rule, applied to the bug that motivated the fix.
let six = AddressSky.layout(
    watched: two,
    connected: (0..<6).map { connected("t\($0)", ["A", "B"]) },
    canWatchMore: true)!
check(six.connectedBodies.count == 6, "all six twins are drawn")
let sixPts = six.connectedBodies.map(\.at)
check((0..<6).allSatisfy { i in (0..<6).allSatisfy { j in
    i == j || dist(sixPts[i], sixPts[j]) > AddressSky.twinSpread - 0.001
} }, "no pair of six twins crowds below one spread")
check(sixPts.allSatisfy {
    dist($0, AddressSky.Point(x: 0.5, y: 0.5))
        + AddressSky.connectedDiameter / 2 < AddressSky.ringRadius
}, "the cluster stays inside the watched ring, bodies included")
// Face to face, against every ring body — wallets AND the open slot. The
// chain's endpoints landed on both wallets' faces; that is the screenshot.
let ringFaces = six.bodies.filter { $0.kind != .connected }
let faceClearance = (AddressSky.watchedDiameter + AddressSky.connectedDiameter) / 2
check(sixPts.allSatisfy { p in
    ringFaces.allSatisfy { dist(p, $0.at) > faceClearance }
}, "no twin lands on a watched face or the open slot")

// ---- determinism ---------------------------------------------------------
// CEILING, stated so nobody trusts this further than it goes: both calls run in
// ONE process, and Swift's Dictionary hash seed is fixed for a process's life.
// So this proves the layout has no clock, no counter and no mutable state — it
// canNOT prove that dictionary iteration order never leaks into the output,
// because within one process that order is stable. The guard on the
// constellation sort is what covers that half.
let nodes = [connected("m", ["A", "B"], groups: ["Family"]),
             connected("n", ["B", "C"], groups: ["Family"]),
             connected("o", ["A", "C"])]
let once = AddressSky.layout(watched: three, connected: nodes, canWatchMore: true)!
let twice = AddressSky.layout(watched: three, connected: nodes, canWatchMore: true)!
check(once == twice, "the same input lays out identically — no physics, no randomness")

// ---- constellations ------------------------------------------------------
check(once.constellations.count == 1, "a group with two drawn members is named")
check(once.constellations[0].name == "Family", "and named with its own spelling")
check(once.constellations[0].drawn == 2, "and states how many of it are drawn")
// The label sits between its own members, not at the centre of the sky.
let famA = once.connectedBodies.first { $0.id == "m" }!.at
let famB = once.connectedBodies.first { $0.id == "n" }!.at
check(near(once.constellations[0].at.x, (famA.x + famB.x) / 2)
      && near(once.constellations[0].at.y, (famA.y + famB.y) / 2),
      "a constellation is named where its members actually sit")
// One member is a caption, not a constellation.
let lonely = AddressSky.layout(watched: three,
                               connected: [connected("m", ["A", "B"], groups: ["Solo"])],
                               canWatchMore: false)!
check(lonely.constellations.isEmpty, "a group with one drawn member gets no label")
// Case-folded, exactly as the book folds a group.
let folded = AddressSky.layout(watched: three,
                               connected: [connected("m", ["A", "B"], groups: ["family"]),
                                           connected("n", ["B", "C"], groups: ["Family"])],
                               canWatchMore: false)!
check(folded.constellations.count == 1, "“family” and “Family” are ONE constellation")
check(folded.constellations[0].name == "family", "the first spelling seen wins")
// Alphabetical, so two groups can never swap between passes.
let manyGroups = AddressSky.layout(
    watched: three,
    connected: [connected("m", ["A", "B"], groups: ["Zed"]),
                connected("n", ["B", "C"], groups: ["Zed"]),
                connected("o", ["A", "C"], groups: ["Alpha"]),
                connected("p", ["A", "B"], groups: ["Alpha"])],
    canWatchMore: false)!
check(manyGroups.constellations.map(\.name) == ["Alpha", "Zed"],
      "constellations are alphabetical, so two can never swap between passes")
// A blank group name is not a group.
let blank = AddressSky.layout(watched: three,
                              connected: [connected("m", ["A", "B"], groups: ["  "]),
                                          connected("n", ["B", "C"], groups: ["  "])],
                              canWatchMore: false)!
check(blank.constellations.isEmpty, "a blank group name is not a constellation")

// ---- new since the last look ---------------------------------------------
let fresh = AddressSky.layout(watched: two,
                              connected: [connected("m", ["A", "B"], isNew: true)],
                              canWatchMore: false)!
check(fresh.hasNew, "a new connection is flagged on its links")
check(fresh.links.allSatisfy(\.isNew), "every leg of a new connection is new")
check(!once.hasNew, "a settled sky claims nothing is new")
// New changes WHEN it draws, never WHERE — the position is the graph's.
let settledSame = AddressSky.layout(watched: two,
                                    connected: [connected("m", ["A", "B"], isNew: false)],
                                    canWatchMore: false)!
check(fresh.connectedBodies[0].at == settledSame.connectedBodies[0].at,
      "being new moves nothing — it is a drawing order, not a ranking")

// ---- links carry no weight -----------------------------------------------
// There is no field to carry one, which is the strongest form of this check:
// `Link` holds two points, an id and `isNew`. If a weight is ever added this
// assertion is the place it must be argued.
check(MemoryLayout<AddressSky.Link>.size > 0, "Link exists")
let manyEdges = AddressSky.layout(watched: two,
                                  connected: [connected("m", ["A", "B"])],
                                  canWatchMore: false)!
check(manyEdges.links.count == 2 && Set(manyEdges.links.map(\.id)).count == 2,
      "links are identified per wallet reached, uniquely")

if failures > 0 {
    FileHandle.standardError.write("address-sky: \(failures) failure(s)\n".data(using: .utf8)!)
    exit(1)
}
print("address-sky: all assertions pass")
SWIFT

swiftc -O -o "$work/sky" "$work/AddressSky.swift" "$work/main.swift" 2>"$work/build.log" || {
  print "address-sky-selftest: COMPILE FAILED"; cat "$work/build.log"; exit 1
}
"$work/sky"

# `--run` is the mutation prober's entry point: assertions only, no guards.
#
# Spelled as an `if` rather than `[[ … ]] && exit 0`, which is the OTHER zsh
# trap this harness paid for: on the path where the test is FALSE the whole
# `&&` list returns 1, and that became the script's own exit status — so
# `--self-test` printed every ✓ and then reported FAILURE to `verify.sh`. A
# check that reports the wrong verdict is worse than one that cannot fail.
if [[ "${1:-}" == "--run" ]]; then
  exit 0
fi

# ------------------------------------------------------------- drift guards
#
# Facts that live in two files, or negatives no assertion can reach. Read from
# a COMMENT-STRIPPED copy where the source documents a rule by naming what it
# must not do — the Obsidian/Cursor lesson, seventh instance.
strip() { sed -E 's://.*$::' "$1" | sed -E '/^[[:space:]]*\/\/\//d'; }

fail=0
guard() {  # <description> <test-command...>
  if eval "${@:2}" >/dev/null 2>&1; then print "  ✓ $1"; else print "  ✗ $1"; fail=1; fi
}

# The view's face sizes against the layout's own diameters. They are spelled
# separately because `AddressSky` is Foundation-only and cannot name `DS.Face`;
# this is the only thing keeping them in step. Same arrangement as
# `NetworkReceiptsInsight`/`UnitTreemap`'s cell cap.
guard "the view draws bodies on the DS.Face ramp, watched a rung above the rest" \
  "grep -q 'let size: CGFloat = body.kind == .watched ? DS.Face.shelf : DS.Face.list' \"\$VIEW\""
guard "the layout's watched diameter is the larger of the two" \
  "python3 -c \"import re,sys; t=open('$SRC').read(); w=float(re.search(r'watchedDiameter = ([0-9.]+)',t).group(1)); c=float(re.search(r'connectedDiameter = ([0-9.]+)',t).group(1)); sys.exit(0 if w>c else 1)\""

# §295's rulings, as negatives. A weighted or hued link would render perfectly.
guard "no link is stroked with a computed width" \
  "! strip '$VIEW' | grep -qE 'lineWidth: *[a-z_]'"
guard "no link reads a count, total or amount" \
  "! strip '$VIEW' | grep -qE '\.(count|usd|total|amount)\b.*(stroke|opacity|lineWidth)'"

# The user ruling this pass was built under (2026-08-21): NO FIGURES on the
# manager. `WalletValue.money`/`exactMoney` is the app's only money formatter,
# so its absence from these three files is the check.
guard "the sky view prints no money" \
  "! strip '$VIEW' | grep -qE 'WalletValue\.(money|exactMoney)|BalancePrivacy'"
guard "the layout knows nothing about money" \
  "! strip '$SRC' | grep -qiE 'usd|price|balance|value'"
guard "the wallet manager prints no money" \
  "! strip '$SCREEN' | grep -qE 'WalletValue\.(money|exactMoney)'"

# The sky and the spine must read ONE definition of "connected", or a map and
# a card start disagreeing about the same book.
guard "the sky reads AddressConnections rather than re-deriving connections" \
  "grep -q 'AddressConnections.map(context:' '$SOURCE'"
# The sort itself, as a grep — see the mutation note above. This is the check
# that catches DELETION; the assertion catches inversion.
guard "constellations are sorted before they are returned" \
  "grep -q 'localizedStandardCompare(\$1.name) == .orderedAscending' \"$SRC\""
guard "the deleted spine card has not come back" \
  "[[ ! -f Casberi/Casberi/Screens/AddressConnectionsCard.swift ]]"

# First sight must seed silently, or a year of history announces itself as
# today's news — the Hyperliquid 2026-07-30 bug in a new room.
guard "first sight seeds the seen-set silently" \
  "grep -q 'if firstSight { markSeen(' '$SOURCE'"
guard "a first-sight connection is never flagged new" \
  "grep -q 'isNew: !firstSight && !alreadySeen.contains' '$SOURCE'"

# Reduce Motion must land the finished picture, not a slower one.
guard "Reduce Motion finishes both trims immediately" \
  "grep -q 'guard !reduceMotion else { drawn = 1; newDrawn = 1; return }' '$VIEW'"

# The shelf is the fallback below two wallets, so it cannot be deleted.
guard "the manager still falls back to the shelf" \
  "grep -q 'rosterSection' '$SCREEN'"

if (( fail )); then
  print "address-sky-selftest: DRIFT"
  exit 1
fi
print "address-sky-selftest: OK — layout proven, guards hold."
exit 0
