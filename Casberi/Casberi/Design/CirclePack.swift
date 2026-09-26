import Foundation
import CoreGraphics

/// **THE CIRCLE PACK'S LAYOUT (prd §917) — pure, Foundation-only, and the
/// half a harness can compile on its own.**
///
/// The wallet's holdings map and the brief's source mix tiled `UnitTreemap`'s
/// rank table, where AREA says "roughly where in the order" and a lightness
/// wash says "how much". On the wallet that wash is four points of lightness
/// apart in dark, so ETH at 63% and USDC at 27% drew as the same tile
/// (2026-09-25, user: "i don't really see a difference"). The rule that now
/// picks a figure is one sentence — **a mark packs, a word tiles**: a cell
/// with a mark of its own on ONE scale becomes a circle whose area IS its
/// share and whose mark IS the label (the Watch honeycomb, App Library); a
/// cell that is a word, or whose amounts are not on one scale (§688's devnet
/// holdings), keeps the table.
///
/// **What the layout promises, each guarded in `scripts/circle-pack-selftest.sh`:**
///
///   · AREA IS THE SHARE. `radius² ∝ share` for every circle the floor did not
///     lift, so a 63% holding is visibly twice a 27% one.
///   · A FLOOR, NOT A FOLD. No circle draws under `floorDiameter` (44pt, the
///     touch target), so a 3% holding is still a mark you can name and tap; the
///     excess comes out of everyone else through the fit scale, never out of the
///     largest alone. Where a treemap needs "N more" at six, the pack takes a
///     tail as small marks.
///   · NO OVERLAP, EVERYTHING INSIDE. Circles are tangent with `gap` between
///     them and the whole cluster is centred in the box.
///   · DETERMINISTIC AND IN INPUT ORDER. The same shares in the same box give
///     the same circles, returned at the caller's indices — the caller's
///     identities key the view (§501's travel), so an output that re-sorted
///     would move the wrong mark.
///
/// **Placement is a greedy compact packing**, not d3's front chain: circles are
/// placed largest first, each at the tangent point against a pair of placed
/// circles that lies closest to the cluster's centre, with the vertical axis
/// weighted by the box's aspect so a wide box grows sideways rather than into a
/// blob the height clips. It is O(n³) per placement and n is at most a dozen.
/// Tangency is preserved under uniform scaling, so the pack is computed once in
/// share space and scaled to fit; the floor is then applied and the pack
/// re-run, three passes, which converges for every real holdings shape.
enum CirclePack {
    struct Circle: Equatable {
        var center: CGPoint
        var radius: CGFloat
    }

    /// The smallest circle drawn: a 44pt touch target.
    static let floorDiameter: CGFloat = 44

    /// Circles for `shares` (any positive magnitudes on one scale — USD, a
    /// count), packed into `size` with `gap` between them, one per input at the
    /// input's index. A non-positive share is treated as the smallest positive
    /// one so it still draws (a held token has a share; a zero here is a
    /// caller's rounding, not an absence). Empty in, empty out.
    static func layout(shares: [Double], in size: CGSize,
                       gap: CGFloat = 4, floor: CGFloat = floorDiameter) -> [Circle] {
        guard !shares.isEmpty, size.width > 0, size.height > 0 else { return [] }
        let positive = shares.filter { $0 > 0 }
        let least = positive.min() ?? 1
        let cleaned = shares.map { $0 > 0 ? $0 : least }
        // Largest first, stable, remembering where each came from.
        let order = cleaned.indices.sorted { a, b in
            cleaned[a] != cleaned[b] ? cleaned[a] > cleaned[b] : a < b
        }
        var radii = order.map { CGFloat(cleaned[$0].squareRoot()) }

        // One circle: as big as the box allows, centred.
        if radii.count == 1 {
            let r = max(min(size.width, size.height) / 2 - gap, floor / 2)
            return [Circle(center: CGPoint(x: size.width / 2, y: size.height / 2), radius: r)]
        }

        let aspect = max(size.width / size.height, 0.25)
        // Fit in share space first: tangency survives a uniform scale.
        var packed = place(radii: radii.map { $0 + gap / 2 }, aspect: aspect, in: size)
        let fit = fitScale(centers: packed, radii: radii.map { $0 + gap / 2 }, in: size)
        radii = radii.map { $0 * fit }
        // Then the floor. A lifted circle is held at the floor exactly, and the
        // room it takes comes out of the circles the floor did not lift, which
        // shrink together so their ratios stay the shares. The lifted set only
        // grows, so this converges; if every circle is at the floor the box
        // cannot hold them at that size and the whole pack shrinks together.
        var lifted = [Bool](repeating: false, count: radii.count)
        for _ in 0..<8 {
            for i in radii.indices where radii[i] < floor / 2 {
                radii[i] = floor / 2
                lifted[i] = true
            }
            packed = place(radii: radii.map { $0 + gap / 2 }, aspect: aspect, in: size)
            let s = fitScale(centers: packed, radii: radii.map { $0 + gap / 2 }, in: size)
            if s >= 1 - 1e-6 { break }
            if lifted.allSatisfy({ $0 }) {
                radii = radii.map { $0 * s }
                break
            }
            for i in radii.indices where !lifted[i] { radii[i] *= s }
        }
        // Final placement at the final radii. The gap is a fixed width, so a
        // pack re-placed after a scale is not exactly the scaled pack; settle
        // the last fraction of a point here rather than trust it.
        for _ in 0..<3 {
            packed = place(radii: radii.map { $0 + gap / 2 }, aspect: aspect, in: size)
            let s = fitScale(centers: packed, radii: radii.map { $0 + gap / 2 }, in: size)
            if s >= 1 - 1e-6 { break }
            radii = radii.map { $0 * s }
        }
        packed = place(radii: radii.map { $0 + gap / 2 }, aspect: aspect, in: size)
        let (minX, minY, maxX, maxY) = bounds(centers: packed, radii: radii)
        let dx = (size.width - (maxX - minX)) / 2 - minX
        let dy = (size.height - (maxY - minY)) / 2 - minY

        var out = [Circle](repeating: Circle(center: .zero, radius: 0), count: shares.count)
        for (rank, original) in order.enumerated() {
            out[original] = Circle(center: CGPoint(x: packed[rank].x + dx, y: packed[rank].y + dy),
                                   radius: radii[rank])
        }
        return out
    }

    // MARK: - Placement

    /// Centres for `radii` (already largest first), tangent-packed around the
    /// origin, in whichever of the two seed orientations fits the box better.
    ///
    /// The second circle seeds the cluster's long axis — beside the first or
    /// below it — and the greedy growth after that follows the seed, so a
    /// wallet map in a box taller than wide (the room's well after the lead
    /// inset) packed sideways and left a third of the well empty (measured
    /// 2026-09-25: 261×171 in 265×292). Both seeds are placed and the one
    /// whose bounding box scales larger into `size` wins; ties keep sideways.
    private static func place(radii: [CGFloat], aspect: CGFloat, in size: CGSize) -> [CGPoint] {
        let beside = place(radii: radii, aspect: aspect, seedBelow: false)
        guard radii.count > 2 else { return beside }
        let below = place(radii: radii, aspect: aspect, seedBelow: true)
        let sBeside = fitScale(centers: beside, radii: radii, in: size)
        let sBelow = fitScale(centers: below, radii: radii, in: size)
        return sBelow > sBeside + 1e-6 ? below : beside
    }

    /// One seed orientation. Two placed circles always have a free tangent
    /// point for a third, so the fallback (to the right of everything) is
    /// never reached for real input; it exists so the function is total.
    private static func place(radii: [CGFloat], aspect: CGFloat, seedBelow: Bool) -> [CGPoint] {
        var centers: [CGPoint] = []
        for (i, r) in radii.enumerated() {
            if i == 0 { centers.append(.zero); continue }
            if i == 1 {
                centers.append(seedBelow ? CGPoint(x: 0, y: radii[0] + r)
                                         : CGPoint(x: radii[0] + r, y: 0))
                continue
            }
            // The cluster's centre, weighted so a wide box prefers sideways.
            let (minX, minY, maxX, maxY) = bounds(centers: centers, radii: Array(radii[0..<i]))
            let target = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
            var best: CGPoint? = nil
            var bestScore = CGFloat.infinity
            for a in 0..<i {
                for b in (a + 1)..<i {
                    for p in tangents(a: centers[a], ra: radii[a], b: centers[b], rb: radii[b], rc: r) {
                        guard clear(p, r, among: centers, radii: radii) else { continue }
                        let dx = p.x - target.x, dy = (p.y - target.y) * aspect
                        let score = dx * dx + dy * dy
                        // Strictly less, so ties keep the first pair found —
                        // which is what makes the same input place the same way.
                        if score < bestScore - 1e-9 { bestScore = score; best = p }
                    }
                }
            }
            if let best { centers.append(best) } else {
                centers.append(CGPoint(x: maxX + r, y: 0))
            }
        }
        return centers
    }

    /// The two points where a circle of radius `rc` is tangent to both `a` and
    /// `b`, or none where they are too far apart for it to touch both.
    private static func tangents(a: CGPoint, ra: CGFloat, b: CGPoint, rb: CGFloat, rc: CGFloat) -> [CGPoint] {
        let dx = b.x - a.x, dy = b.y - a.y
        let d = (dx * dx + dy * dy).squareRoot()
        guard d > 0, d <= ra + rb + 2 * rc + 1e-6 else { return [] }
        let r1 = ra + rc, r2 = rb + rc
        let x = (d * d + r1 * r1 - r2 * r2) / (2 * d)
        let h2 = r1 * r1 - x * x
        guard h2 >= -1e-6 else { return [] }
        let h = max(h2, 0).squareRoot()
        let ux = dx / d, uy = dy / d
        let base = CGPoint(x: a.x + ux * x, y: a.y + uy * x)
        return [CGPoint(x: base.x - uy * h, y: base.y + ux * h),
                CGPoint(x: base.x + uy * h, y: base.y - ux * h)]
    }

    /// True when a circle at `p` with radius `r` overlaps none already placed.
    private static func clear(_ p: CGPoint, _ r: CGFloat, among centers: [CGPoint], radii: [CGFloat]) -> Bool {
        for (j, c) in centers.enumerated() {
            let dx = p.x - c.x, dy = p.y - c.y
            if (dx * dx + dy * dy).squareRoot() < r + radii[j] - 1e-3 { return false }
        }
        return true
    }

    // MARK: - Fit

    private static func bounds(centers: [CGPoint], radii: [CGFloat]) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        for (c, r) in zip(centers, radii) {
            minX = min(minX, c.x - r); maxX = max(maxX, c.x + r)
            minY = min(minY, c.y - r); maxY = max(maxY, c.y + r)
        }
        return (minX, minY, maxX, maxY)
    }

    /// The uniform scale that fits the cluster (radii inflated by the gap)
    /// inside `size`.
    private static func fitScale(centers: [CGPoint], radii: [CGFloat], in size: CGSize) -> CGFloat {
        let (minX, minY, maxX, maxY) = bounds(centers: centers, radii: radii)
        let w = maxX - minX, h = maxY - minY
        guard w > 0, h > 0 else { return 1 }
        return min(size.width / w, size.height / h)
    }
}
