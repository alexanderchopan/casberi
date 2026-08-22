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
  # The twins stop spreading at all — every body in a cluster takes the shared
  # angle and they stack, which is the failure `twinSpread` exists to prevent.
  # The sweep's own mutation: relaxation off, so bodies keep the bearing they
  # asked for and two different pairs land on one spot — the defect the real
  # numbers showed and no per-shape fixture could.
  probe "collisions between different clusters go unresolved" \
    "s/placed\[i\] = max(placed\[i\], placed\[i - 1\] + step)/placed[i] = placed[i]/" "yes"
  probe "the twin spread collapses to nothing" \
    "s/twinSpread \/ (2 \* connectedRadius)/0.0 * connectedRadius/" "yes"
  # THE TWO RINGS, collapsed onto one (prd §437). Every connected body lands on
  # the watched ring, where nothing but an angle keeps it off a wallet's face.
  probe "the connected ring moved onto the watched one" \
    "s/static let connectedRadius = 0.19/static let connectedRadius = 0.33/" "yes"
  # THE CIRCULAR MEAN, replaced by a plain average of angles — the one
  # arithmetic mistake this placement can make that still renders perfectly:
  # a body reaching the ring's last and first wallets lands exactly opposite
  # the pair it reaches, and its links cross a drawing they have no business in.
  probe "the angle between wallets averaged straight instead of around" \
    "s|return atan2(y, x)|return angles.reduce(0, +) / Double(angles.count)|" "yes"
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
  # Re-anchored when `ringPoint(index:of:)` became `ringAngle(index:of:)`
  # (prd §437): the old expression matched nothing, so the probe ran a CLEAN
  # copy and reported it as a surviving mutation. A guarded function that
  # moves takes its guard with it — and a mutation that matches nothing is a
  # check that proves nothing, which is why this harness fails loudly on it.
  probe "the ring no longer starts at the top" \
    "s|return -Double.pi / 2 + (2|return Double.pi / 2 + (2|" "yes"
  # Re-aimed twice (prd §437, then §438 — its first target was deleted with
  # the wallet-set signature, its second became dead code when emptiestBearing
  # took the decision over, and a mutation of dead code is unkillable by
  # definition, which is exactly what the SURVIVED report said). What it
  # defends now is the live rule: a body whose wallets face each other stands
  # in the ring's emptiest gap, never under somebody's face. Breaking the
  # better-candidate comparison makes every candidate lose, so the body lands
  # on the default top bearing — directly inside the first wallet.
  probe "the degenerate body stops seeking the emptiest gap" \
    "s/if gap > bestClearance + 0.0001/if gap > bestClearance + 9.9/" "yes"
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
// AT TWO WALLETS THE CONNECTED SET IS A WHEEL (prd §438): every drawn body
// reaches the same pair by construction and the pair faces each other, so a
// bearing carries no information — the bodies distribute EVENLY around the
// whole connected ring instead of packing at the minimum step, which is what
// drew the reported crescent of touching faces. Two bodies therefore sit
// OPPOSITE each other: a full diameter apart, not one twinSpread.
let twins = AddressSky.layout(watched: two,
                              connected: [connected("p", ["A", "B"]),
                                          connected("q", ["A", "B"])],
                              canWatchMore: false)!
let tp = twins.connectedBodies[0].at, tq = twins.connectedBodies[1].at
check(dist(tp, tq) > 0.05, "two people reaching the same pair do not stack")
check(near(dist(tp, tq), 2 * AddressSky.connectedRadius, 0.001),
      "at two wallets, two connected bodies sit opposite each other")
// Order-insensitive: "A,B" and "B,A" are ONE cluster.
let flipped = AddressSky.layout(watched: two,
                                connected: [connected("p", ["A", "B"]),
                                            connected("q", ["B", "A"])],
                                canWatchMore: false)!
check(dist(flipped.connectedBodies[0].at, flipped.connectedBodies[1].at) > 0.05,
      "the twin cluster is order-insensitive")
// Stronger, and the form that actually pins it: flipping the key order must
// produce the SAME PLACES, not merely two places that don't collide.
check(zip(twins.connectedBodies, flipped.connectedBodies).allSatisfy {
    near($0.at.x, $1.at.x) && near($0.at.y, $1.at.y)
}, "flipping the wallet order changes nothing about where anybody lands")
// And the THREE-OR-MORE regime, where a bearing IS a fact and the minimal
// separation is the behaviour: two bodies reaching the same pair among three
// wallets sit exactly one twinSpread apart — with a FLOOR, because under the
// spread-to-zero mutations near(x, 0) is satisfied by two stacked bodies and
// the fixture must fail them, not bless them.
let trio = AddressSky.layout(watched: three,
                             connected: [connected("p3", ["A", "B"]),
                                         connected("q3", ["A", "B"])],
                             canWatchMore: false)!
let t3p = trio.connectedBodies[0].at, t3q = trio.connectedBodies[1].at
check(near(dist(t3p, t3q), AddressSky.twinSpread, 0.002) && dist(t3p, t3q) > 0.05,
      "at three wallets, same-pair twins sit exactly one spread apart")
// Three bodies over two wallets are the wheel at n=3: evenly spaced, a third
// of a turn apart (chord 2·r·sin 60°), with the FIRST body standing exactly
// where a lone one would — the wheel starts at the same emptiest gap a single
// body is sent to, so growing from one to three moves nothing about where the
// picture begins.
let trips = AddressSky.layout(watched: two,
                              connected: [connected("p", ["A", "B"]),
                                          connected("q", ["A", "B"]),
                                          connected("r", ["A", "B"])],
                              canWatchMore: false)!
let solo = AddressSky.layout(watched: two,
                             connected: [connected("q", ["A", "B"])],
                             canWatchMore: false)!
let tripPts = trips.connectedBodies.map(\.at)
check(near(tripPts[0].x, solo.connectedBodies[0].at.x)
      && near(tripPts[0].y, solo.connectedBodies[0].at.y),
      "the wheel starts where a lone body stands")
let third = 2 * AddressSky.connectedRadius * sin(Double.pi / 3)
check(near(dist(tripPts[0], tripPts[1]), third, 0.002)
      && near(dist(tripPts[1], tripPts[2]), third, 0.002)
      && near(dist(tripPts[0], tripPts[2]), third, 0.002),
      "three bodies over two wallets sit a third of a turn apart")
// Every body still sits on the connected ring — the arc cannot drift off it.
check(tripPts.allSatisfy {
    near(dist($0, AddressSky.Point(x: 0.5, y: 0.5)), AddressSky.connectedRadius, 0.0001)
}, "a spread twin stays on the connected ring")
// Two wallets sit exactly opposite, so their angles cancel — the degenerate
// case the circular mean would return atan2(0, 0) on.
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

// ---- the two rings, and the crossing link (prd §437, 2026-08-22) ---------
// The reading this pass exists for. A connected body used to be pulled toward
// the centre from the midpoint of the wallets it reached, which put every one
// at a different distance from the middle and — for two wallets facing each
// other — exactly ON it. Now it sits on its OWN ring at the angle between
// them, and the link is a straight line from that ring to the outer one.

// (1) Every connected body is on the connected ring, whatever it reaches.
let ringed = AddressSky.layout(
    watched: three,
    connected: [connected("m", ["A", "B"]), connected("n", ["B", "C"]),
                connected("o", ["A", "C"]), connected("p", ["A", "B", "C"])],
    canWatchMore: false)!
check(ringed.connectedBodies.allSatisfy {
    near(dist($0.at, AddressSky.Point(x: 0.5, y: 0.5)), AddressSky.connectedRadius, 0.0001)
}, "every connected body sits on the connected ring")

// (2) A connected body and a watched one can NEVER stack, however close their
// angles run — the guarantee the two radii buy, which no arrangement of twin
// spreading could ever make on one ring. Proven at the worst case the layout
// allows rather than on a friendly fixture: a body reaching three wallets sits
// at the mean of all three, which for an evenly-spaced ring cancels to the
// degenerate case and lands it on the same bearing as a wallet.
let radialGap = AddressSky.ringRadius - AddressSky.connectedRadius
check(radialGap > (AddressSky.watchedDiameter + AddressSky.connectedDiameter) / 2,
      "the two rings are further apart than two faces are wide")
check(ringed.connectedBodies.allSatisfy { body in
    ringed.bodies.filter { $0.kind != .connected }
        .allSatisfy { dist(body.at, $0.at) > (AddressSky.watchedDiameter + AddressSky.connectedDiameter) / 2 }
}, "no connected body can land on a watched face")

// (3) THE CROSSING. Two wallets far apart on the ring must produce a link that
// passes through the middle of the drawing — not an arc hugging its rim. With
// three wallets, the two that A-and-C's body reaches are 240° apart, so its
// two links together span the ring. Measured as: the link's own closest
// approach to the centre is well inside the connected ring.
func closestToCentre(_ link: AddressSky.Link) -> Double {
    let c = AddressSky.Point(x: 0.5, y: 0.5)
    let dx = link.to.x - link.from.x, dy = link.to.y - link.from.y
    let len2 = dx * dx + dy * dy
    guard len2 > 0 else { return dist(link.from, c) }
    var t = ((c.x - link.from.x) * dx + (c.y - link.from.y) * dy) / len2
    t = max(0, min(1, t))
    return dist(AddressSky.Point(x: link.from.x + dx * t, y: link.from.y + dy * t), c)
}
let wide = AddressSky.layout(watched: three,
                             connected: [connected("o", ["A", "C"])],
                             canWatchMore: false)!
check(wide.links.allSatisfy { closestToCentre($0) < AddressSky.connectedRadius },
      "a link between far-apart wallets passes through the middle")
// And the converse, which is what makes the one above a real test rather than
// a property of every link: a body whose wallets are NEIGHBOURS draws short
// links that stay out near the rim. Four wallets put A and B one step apart.
let four = [AddressSky.Wallet(key: "A", address: "0xA", name: "A"),
            AddressSky.Wallet(key: "B", address: "0xB", name: "B"),
            AddressSky.Wallet(key: "C", address: "0xC", name: "C"),
            AddressSky.Wallet(key: "D", address: "0xD", name: "D")]
let near2 = AddressSky.layout(watched: four,
                              connected: [connected("q", ["A", "B"])],
                              canWatchMore: false)!
check(near2.links.allSatisfy { closestToCentre($0) > AddressSky.connectedRadius * 0.5 },
      "a link between neighbouring wallets stays out of the middle")

// (3b) The DEGENERATE bearing at four wallets — where it still runs now that
// the two-wallet sky is a wheel and never calls the mean at all (prd §438).
// A body reaching two OPPOSITE wallets of four has both arcs equal: the
// vectors cancel, the fallback fires, and it must be a function of the SET —
// the same body spelled "W0 and W2" and "W2 and W0" is one relationship and
// lands in one place. This fixture is what keeps the arrival-order mutation
// killable; the two-wallet fixture that used to cover it no longer reaches
// the code.
let anti = AddressSky.layout(watched: four,
                             connected: [connected("g", ["A", "C"])],
                             canWatchMore: false)!
let antiFlipped = AddressSky.layout(watched: four,
                                    connected: [connected("g", ["C", "A"])],
                                    canWatchMore: false)!
check(near(anti.connectedBodies[0].at.x, antiFlipped.connectedBodies[0].at.x)
      && near(anti.connectedBodies[0].at.y, antiFlipped.connectedBodies[0].at.y),
      "a body reaching opposite wallets lands in one place however its keys are spelled")
// And it stands in an EMPTY gap — never radially under a wallet, which is
// where the default bearing puts it if the gap search stops working. At the
// emptiest gap of four wallets the nearest face is ~0.23 away; directly under
// one it is exactly the radial 0.14.
check(anti.watchedBodies.allSatisfy { dist(anti.connectedBodies[0].at, $0.at) > 0.16 },
      "a body reaching opposite wallets stands clear of every face, in the ring's emptiest gap")

// (4) The circular mean, at the wrap. A body reaching the LAST wallet on the
// ring and the FIRST must sit between them across the top, not on the far
// side: a plain average of angles would put it exactly opposite, which is the
// one arithmetic mistake this placement can make and which renders perfectly.
let wrapped = AddressSky.layout(watched: four,
                                connected: [connected("w", ["A", "D"])],
                                canWatchMore: false)!
let wp = wrapped.connectedBodies[0].at
let wa = wrapped.watchedBodies[0].at, wd = wrapped.watchedBodies[3].at
let wb = wrapped.watchedBodies[1].at, wc = wrapped.watchedBodies[2].at
check(dist(wp, wa) < dist(wp, wb) && dist(wp, wa) < dist(wp, wc)
      && dist(wp, wd) < dist(wp, wb) && dist(wp, wd) < dist(wp, wc),
      "a body reaching the ring's last and first wallets sits between them, not opposite")

// ---- THE SWEEP: no two bodies overlap, in any shape the layout allows -----
//
// The assertion that was missing, and the reason it was missing is worth more
// than the assertion. Every fixture above poses ONE shape and checks it; the
// spreading was written per-cluster, so it was proven on clusters. Bodies that
// collide WITHOUT sharing a cluster — two different pairs of wallets whose
// bearings happen to coincide, or merely to land a fraction apart — were
// invisible to every one of them. Drawing the real numbers found two people on
// one spot (prd §437); this walks every shape instead of trusting a fixture to
// have been the representative one.
func sweep() -> (body: Double, ring: Double) {
    var worstBody = 9.0, worstRing = 9.0
    for n in 2...5 {
        let ws = (0..<n).map { AddressSky.Wallet(key: "W\($0)", address: "0xW\($0)", name: "w\($0)") }
        for slot in [true, false] {
            var conns: [AddressSky.Connected] = []
            var i = 0
            for a in 0..<n {
                for b in (a + 1)..<n {
                    conns.append(connected("c\(i)", ["W\(a)", "W\(b)"])); i += 1
                }
            }
            // A body reaching THREE wallets takes the mean of all three, which
            // on an even ring cancels — the degenerate bearing, in the middle
            // of a crowd.
            if n >= 3 { conns.append(connected("t", (0..<3).map { "W\($0)" })) }
            guard let s = AddressSky.layout(watched: ws, connected: conns,
                                            canWatchMore: slot) else { continue }
            let cb = s.connectedBodies
            for x in 0..<cb.count {
                for y in (x + 1)..<cb.count { worstBody = min(worstBody, dist(cb[x].at, cb[y].at)) }
            }
            for c in cb {
                for r in s.bodies where r.kind != .connected {
                    worstRing = min(worstRing, dist(c.at, r.at))
                }
            }
        }
    }
    // And the cap's own worst case: every drawn body in ONE cluster.
    let sixAll = AddressSky.layout(
        watched: two, connected: (0..<6).map { connected("s\($0)", ["A", "B"]) },
        canWatchMore: true)!
    let sb = sixAll.connectedBodies
    for x in 0..<sb.count {
        for y in (x + 1)..<sb.count { worstBody = min(worstBody, dist(sb[x].at, sb[y].at)) }
    }
    for c in sb {
        for r in sixAll.bodies where r.kind != .connected {
            worstRing = min(worstRing, dist(c.at, r.at))
        }
    }
    return (worstBody, worstRing)
}
let swept = sweep()
check(swept.body >= AddressSky.connectedDiameter,
      "in every shape, no two connected bodies overlap")
check(swept.ring >= (AddressSky.watchedDiameter + AddressSky.connectedDiameter) / 2,
      "in every shape, no connected body overlaps a ring body")

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

# THE FIELD (prd §437). The layout's diameters are the `DS.Face` ramp divided
# by the field the view is actually given — `WalletScreen.skyHeight` minus
# `AddressSkyView`'s inset on each side. Four numbers in three files, and no
# one of them can state the relationship, which is how 0.165/0.105 came to
# describe a 340pt field while the screen handed the drawing 280: every
# clearance assertion in this harness passed, in units a fifth too generous,
# and the faces overlapped on the real screen. Checked to 3%, since the ramp
# will not divide evenly into a round height.
guard "the layout's diameters are the face ramp over the field the screen gives it" \
  "python3 - <<'EOF'
import re, sys
sky = open('$SRC').read(); view = open('$VIEW').read(); screen = open('$SCREEN').read()
tok = open('Casberi/Casberi/Design/DesignTokens.swift').read()
def f(t, p): return float(re.search(p, t).group(1))
height = f(screen, r'private var skyHeight: CGFloat \{ ([0-9.]+) \}')
inset  = f(view,   r'private let inset: CGFloat = ([0-9.]+)')
field  = height - inset * 2
shelf  = f(tok, r'static let shelf: CGFloat = ([0-9.]+)')
lst    = f(tok, r'static let list: CGFloat = ([0-9.]+)')
w      = f(sky, r'static let watchedDiameter = ([0-9.]+)')
c      = f(sky, r'static let connectedDiameter = ([0-9.]+)')
bad = [n for n, got, want in (('watched', w, shelf/field), ('connected', c, lst/field))
       if abs(got - want) / want > 0.03]
sys.exit(1 if bad else 0)
EOF"

# The two clearances that field buys, asserted where the numbers live rather
# than only inside a fixture: a body can sit directly under a wallet (a mean
# angle landing on a third wallet's bearing), and twins sit one spread apart.
guard "the rings clear a face radially" \
  "python3 -c \"import re,sys; t=open('$SRC').read(); g=lambda p: float(re.search(p,t).group(1)); sys.exit(0 if g(r'ringRadius = ([0-9.]+)') - g(r'connectedRadius = ([0-9.]+)') >= (g(r'watchedDiameter = ([0-9.]+)') + g(r'connectedDiameter = ([0-9.]+)'))/2 else 1)\""
guard "one twin spread clears two connected faces" \
  "python3 -c \"import re,sys; t=open('$SRC').read(); g=lambda p: float(re.search(p,t).group(1)); sys.exit(0 if g(r'twinSpread = ([0-9.]+)') >= g(r'connectedDiameter = ([0-9.]+)') else 1)\""

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

# The shelf is the fallback at ONE watched wallet, so it cannot be deleted.
guard "the manager still falls back to the shelf" \
  "grep -q 'rosterSection' '$SCREEN'"

# ---- prd §437, 2026-08-22 -------------------------------------------------

# LINKS ARE STRAIGHT. The bow toward the centre is what made every connection
# read as an arc hugging the interior; a curve creeping back turns the
# crossing assertions above into statements about a line the view no longer
# draws. Comment-stripped, because the source explains the change by naming
# the call it used to make.
guard "no link is drawn as a curve" \
  "! strip '$VIEW' | grep -qE 'addQuadCurve|addCurve|addArc'"

# ZERO WATCHED gets the sky's own empty state, not the shelf's row of five
# dashed cap slots. Both halves are checked — the view has to exist, and the
# screen has to reach it on exactly the empty case — because either one alone
# is satisfied by a view nothing renders.
guard "the empty sky view exists" \
  "grep -q 'struct AddressSkyEmptyView' '$VIEW'"
# Comment-stripped: the screen EXPLAINS this branch by naming the view, so a
# raw grep is satisfied by the paragraph above the code (the Obsidian/Cursor
# lesson, eighth instance) — it would keep passing over a deleted branch.
#
# A HERE-STRING, never `strip … | grep -q …`, and that is not style: this
# script runs under `pipefail`, `grep -q` exits the instant it matches, and the
# `sed` still writing a 1,900-line file takes SIGPIPE and exits 141 — which
# pipefail then makes the pipeline's status. So the piped spelling FAILS on a
# perfectly good tree, which is how it was caught here (CLAUDE.md records the
# same race costing `ondevice-selftest` a guard that silently matched nothing).
# The negative guards above are safe only because their grep never matches and
# so never closes the pipe early.
guard "the manager reaches it on an empty roster" \
  "grep -q 'wallet.addresses.isEmpty' <<< \"\$(strip '$SCREEN')\" && grep -q 'AddressSkyEmptyView' <<< \"\$(strip '$SCREEN')\""
# It draws no identicon: there is no address yet, and a face over one nobody
# has entered is the invented identity §83 bans.
guard "the empty sky draws no face" \
  "! strip '$VIEW' | sed -n '/struct AddressSkyEmptyView/,\$p' | grep -q 'WalletFace'"

if (( fail )); then
  print "address-sky-selftest: DRIFT"
  exit 1
fi
print "address-sky-selftest: OK — layout proven, guards hold."
exit 0
