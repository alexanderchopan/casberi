#!/bin/zsh
# Casberi circle-pack self-test — the geometry under the wallet's holdings map
# and the brief's source mix (prd §917):
#
#   Casberi/Casberi/Design/CirclePack.swift   — `CirclePack.layout(shares:in:gap:floor:)`
#
# WHY A HARNESS. The pack replaced the rank-tiled treemap on exactly the maps
# where the tiling was lying — ETH at 63% and USDC at 27% drew as the same tile
# — so its one claim is that AREA IS THE SHARE. Every failure below renders as a
# perfectly convincing cluster of marks:
#
#   · AREA NOT PROPORTIONAL. `radius = share` instead of `sqrt(share)` draws a
#     63% holding as five times a 27% one, not twice; still a pretty pack.
#   · A CIRCLE UNDER THE FLOOR. A 3% holding at 12pt is a dot nobody can name
#     or tap; the 44pt floor is what lets the pack take a tail without a fold.
#   · OVERLAP, OR A CIRCLE OFF THE BOX. Marks drawn over each other, or a
#     satellite clipped by the well — the room's `.clipped()` cuts it honestly
#     and nothing says a token is missing.
#   · THE WRONG INDEX. The view keys travel (§501) on the caller's ids; an
#     output re-sorted by size moves ETH's circle to USDC's mark.
#   · OFF-CENTRE. A cluster flush against one edge of a 316pt well.
#
# Compiled with `swiftc` from the shipped file — it is Foundation + CoreGraphics
# only, on purpose, so this harness reads the real code and not a copy.
# Mutations at the bottom prove each check fails. Pure, local, deterministic —
# no network, no simulator. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Design/CirclePack.swift"
[[ -f "$SRC" ]] || { echo "✗ $SRC not found"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
import CoreGraphics

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}
func overlapFree(_ cs: [CirclePack.Circle], gap: CGFloat) -> Bool {
    for i in cs.indices { for j in cs.indices where j > i {
        let d = hypot(cs[i].center.x - cs[j].center.x, cs[i].center.y - cs[j].center.y)
        if d < cs[i].radius + cs[j].radius + gap - 0.05 { return false }
    } }
    return true
}
func inside(_ cs: [CirclePack.Circle], _ size: CGSize) -> Bool {
    cs.allSatisfy { c in
        c.center.x - c.radius >= -0.05 && c.center.y - c.radius >= -0.05
        && c.center.x + c.radius <= size.width + 0.05 && c.center.y + c.radius <= size.height + 0.05
    }
}
func centred(_ cs: [CirclePack.Circle], _ size: CGSize) -> Bool {
    let minX = cs.map { $0.center.x - $0.radius }.min()!, maxX = cs.map { $0.center.x + $0.radius }.max()!
    let minY = cs.map { $0.center.y - $0.radius }.min()!, maxY = cs.map { $0.center.y + $0.radius }.max()!
    return abs(minX - (size.width - maxX)) < 0.5 && abs(minY - (size.height - maxY)) < 0.5
}

// The demo wallet: ETH $21K, USDC $9K, DEGEN $2K, SOL $1K in the room's well.
let well = CGSize(width: 334, height: 292)
let demo: [Double] = [21_000, 9_000, 2_000, 1_000]
let a = CirclePack.layout(shares: demo, in: well)
check(a.count == 4, "one circle per share")
check(a == CirclePack.layout(shares: demo, in: well), "deterministic")
check(overlapFree(a, gap: 4), "no two circles overlap, and the gap is kept")
check(inside(a, well), "every circle is inside the box")
check(centred(a, well), "the cluster is centred in the box")
let ratio = (a[0].radius * a[0].radius) / (a[1].radius * a[1].radius)
check(abs(ratio - 21.0 / 9.0) < 0.03, "area is the share: ETH²/USDC² = 21/9 (got \(ratio))")
check(a.allSatisfy { $0.radius * 2 >= CirclePack.floorDiameter - 0.5 }, "no circle under the 44pt floor")
check(a[3].radius * 2 >= 43.5 && a[3].radius <= a[2].radius + 0.01, "SOL at 3% is held at the floor, no bigger than DEGEN")

// Input order is preserved: the largest share is NOT at index 0 here.
let shuffled: [Double] = [1_000, 21_000, 9_000, 2_000]
let b = CirclePack.layout(shares: shuffled, in: well)
check(b[1].radius == a[0].radius && b[0].radius == a[3].radius, "circles come back at the caller's indices")

// Thirteen tokens: the tail is small marks, every one inside, none under the floor.
let thirteen: [Double] = [48, 22, 9, 6, 4, 2, 2, 1.5, 1.5, 1, 1, 1, 1]
let c = CirclePack.layout(shares: thirteen, in: well)
check(c.count == 13 && overlapFree(c, gap: 4) && inside(c, well), "thirteen shares pack without overlap or clipping")
check(c.allSatisfy { $0.radius * 2 >= CirclePack.floorDiameter - 0.5 }, "thirteen: none under the floor")

// The brief's source mix: three counts in a 96pt strip.
let strip = CGSize(width: 330, height: 96)
let d = CirclePack.layout(shares: [50, 30, 20], in: strip)
check(overlapFree(d, gap: 4) && inside(d, strip), "three sources fit the 96pt strip")
check(d[0].radius > d[1].radius, "the biggest source is the biggest mark")

// One holding fills the well; none draws nothing.
let one = CirclePack.layout(shares: [100], in: well)
check(one.count == 1 && abs(one[0].radius * 2 - (292 - 8)) < 0.01, "one circle takes the box")
check(CirclePack.layout(shares: [], in: well).isEmpty, "no shares, no circles")

// Twenty equal in a box that cannot hold twenty floors: they shrink together, all inside.
let tight = CGSize(width: 200, height: 100)
let e = CirclePack.layout(shares: Array(repeating: 1, count: 20), in: tight)
check(inside(e, tight) && overlapFree(e, gap: 4), "twenty equal shares still fit when the floor cannot")
check(Set(e.map { Int(($0.radius * 100).rounded()) }).count == 1, "equal shares are equal circles")

// A zero share draws as the least positive one, never as nothing.
let z = CirclePack.layout(shares: [10, 0, 1], in: well)
check(z[1].radius == z[2].radius, "a zero share is drawn like the smallest positive one")

if failures > 0 { print("✗ \(failures) failed"); exit(1) }
print("✓ circle pack")
SWIFT

build_and_run() {  # src
    swiftc -O "$1" "$TMP/main.swift" -o "$TMP/pack" 2>"$TMP/swiftc.log" || {
        echo "✗ swiftc failed:"; cat "$TMP/swiftc.log"; return 2
    }
    "$TMP/pack"
}

echo "── circle-pack self-test ──"
build_and_run "$SRC" || { echo "✗ circle-pack self-test failed"; exit 1; }

# ── Mutations: each must FAIL, and each must have changed the file ─────────
mutate() {  # name, perl expression
    local name="$1" expr="$2"
    cp "$SRC" "$TMP/mut.swift"
    perl -0pi -e "$expr" "$TMP/mut.swift"
    if cmp -s "$SRC" "$TMP/mut.swift"; then
        echo "✗ mutation did not change the file: $name"; exit 1
    fi
    if build_and_run "$TMP/mut.swift" >"$TMP/mut.log" 2>&1; then
        echo "✗ mutation SURVIVED: $name"; cat "$TMP/mut.log"; exit 1
    fi
    echo "  ✓ mutation caught: $name"
}
echo "── mutations ──"
mutate "the floor is gone" 's/static let floorDiameter: CGFloat = 44/static let floorDiameter: CGFloat = 0/'
mutate "radius is the share, not its root" 's/CGFloat\(cleaned\[\$0\]\.squareRoot\(\)\)/CGFloat(cleaned[\$0])/'
mutate "circles may overlap" 's/< r \+ radii\[j\] - 1e-3/< (r + radii[j]) * 0.5/'
mutate "the output is re-sorted by size" 's/out\[original\] = Circle/out[rank] = Circle/'
mutate "the cluster sits flush left" 's/let dx = \(size\.width - \(maxX - minX\)\) \/ 2 - minX/let dx = -minX/'
echo "✓ circle-pack self-test"
