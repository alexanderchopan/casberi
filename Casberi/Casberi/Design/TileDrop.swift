import SwiftUI
import UIKit

/// The onboarding rain's MOTION (2026-09-05, user: "i want raining and
/// bouncing apps but i want it to feel professional") — every connectable
/// seat's tile dropping into the heap `HowItWorksSheet` lays out.
///
/// The pile was never the problem; the fall was, for five reasons that were
/// each one line of the old `rain(_:)`: no gravity (every tile took the same
/// 0.58s over a different distance), a bounce that went the wrong way (a
/// `.spring` on `.position` overshoots PAST the rest point, so tiles sank
/// into the pile and popped back out), tiles that flew diagonally to a
/// pre-assigned slot, tiles that shrank 2× on landing while their tilt grew,
/// and 103 springs interpolated on the main actor during first launch.
///
/// What replaces it, and why each piece is physical rather than decorative:
///
/// - **Gravity.** A tile's fall time is `√(2h/g)`, with `g` chosen per deal so
///   the LONGEST drop takes `longestFall`. Lower rows take longer to arrive,
///   which is what makes a heap read as filling from the bottom without any
///   choreography saying so.
/// - **The bounce goes UP.** Impact, then a rebound to `rebounds[0]` of the
///   drop height, then a second to `rebounds[1]`, each an exact parabola
///   (the timing curves are the cubic-bezier form of `t²`, not CA's stock
///   ease-in). Airtime falls out of the same `g`: a rebound to share `s` of
///   the height is in the air for `2·√s` of the fall time.
/// - **Impact squash.** Scale `1.06 × 0.92` for ninety milliseconds on the
///   first landing, less on the second, anchored at the tile's BOTTOM edge so
///   the compression happens against the surface. This is the one thing that
///   makes a bounce read as weight rather than as an easing curve.
/// - **Vertical.** Start x is rest x plus a drift of a few points. Tilt starts
///   a little past the rest tilt and settles INTO it — it never grows.
/// - **Rest size in flight.** Nothing that falls shrinks when it lands.
/// - **CoreAnimation.** Each tile is a `CALayer` with the brand asset as its
///   `contents` (the symbol fallbacks are rendered once through
///   `ImageRenderer`), driven by two `CAKeyframeAnimation`s the render server
///   plays out of process — `BerryRain`'s lesson (2026-07-28): SwiftUI
///   interpolates on the main actor, and a first launch is exactly when that
///   actor is busiest. The fall stays smooth while the app warms up under it.
///
/// Deterministic end to end: the release schedule and every offset come from
/// the caller's fixed tables, so the same install replays the same fall and
/// the screen sweep sees one design. Reduce Motion: the tiles are simply
/// placed at rest — the pile is the claim, the fall is only how it got there.
struct TileDrop: Equatable {
    /// The catalog offer's name — `BridgeIcon` resolves the asset from it.
    let name: String
    /// Centre at rest, in the host view's coordinate space.
    let rest: CGPoint
    let size: CGFloat
    /// Degrees. The tile falls at `restTilt × 1.6` and settles into this.
    let restTilt: Double
    /// Points. Start x is `rest.x + drift`; the drift is spent by impact.
    let drift: CGFloat
    /// Seconds after arming before this tile lets go.
    let release: Double
    /// Layer order at rest — lower rows in front, so the heap shingles the
    /// way a heap does.
    let depth: Double
}

/// The rain's host: an untouchable overlay that owns the layers and deals the
/// fall once. Mount it over the band the tiles rest in.
struct TileDropLayer: UIViewRepresentable {
    let tiles: [TileDrop]
    /// False: nothing is drawn. True: the deal is placed the first time the
    /// view has a size, and replayed only if the layout moves before the
    /// first release.
    let armed: Bool
    let reduceMotion: Bool

    func makeUIView(context: Context) -> TileDropView { TileDropView() }

    func updateUIView(_ view: TileDropView, context: Context) {
        view.apply(tiles, armed: armed, reduceMotion: reduceMotion)
    }
}

final class TileDropView: UIView {
    /// The longest drop on screen takes this long; every other tile's fall
    /// time follows from the same gravity.
    static let longestFall: Double = 0.55
    /// Rebound heights as a share of each tile's own drop.
    static let rebounds: [Double] = [0.12, 0.03]
    /// Impact squash (x, y) and how long it lasts, first and second landing.
    static let squash: [(x: CGFloat, y: CGFloat, hold: Double)] = [
        (1.06, 0.92, 0.09), (1.03, 0.96, 0.07),
    ]
    /// How far above the screen a tile starts, measured at its bottom edge.
    static let startAbove: CGFloat = 4

    private var dealt: [TileDrop] = []
    private var dealtAt: CFTimeInterval?
    private var firstRelease: Double = 0
    private var animated = true
    private var waiting: (tiles: [TileDrop], animated: Bool)?
    private var tileLayers: [CALayer] = []
    private var imageCache: [String: CGImage] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        // A tile waits above the top edge until it lets go; the host is the
        // whole screen, but clipping keeps the wait invisible however the
        // overlay ends up framed.
        layer.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("TileDropView is code-only") }

    // MARK: - Deal-once

    func apply(_ tiles: [TileDrop], armed: Bool, reduceMotion: Bool) {
        guard armed, !tiles.isEmpty else { return }
        let animated = !reduceMotion
        guard bounds.width > 0, bounds.height > 0 else {
            waiting = (tiles, animated)
            return
        }
        guard dealtAt != nil else {
            deal(tiles, animated: animated)
            return
        }
        guard tiles != dealt else { return }
        // The layout moved. Before the first tile has let go nothing has been
        // seen, so the deal is simply replaced — this is the normal path when
        // the band's anchors travel a frame after the view mounts. After that,
        // the pile re-lays at rest: a rotation or a type-size change mid-fall
        // is rare, and a heap that snaps to its new bed beats one that keeps
        // falling toward the old one.
        if let dealtAt, CACurrentMediaTime() < dealtAt + firstRelease {
            deal(tiles, animated: animated)
        } else {
            deal(tiles, animated: false)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let held = waiting, bounds.width > 0, bounds.height > 0 else { return }
        waiting = nil
        deal(held.tiles, animated: held.animated)
    }

    private func deal(_ tiles: [TileDrop], animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tileLayers.forEach { $0.removeFromSuperlayer() }
        tileLayers.removeAll(keepingCapacity: true)

        let start = CACurrentMediaTime()
        dealt = tiles
        dealtAt = start
        firstRelease = tiles.map(\.release).min() ?? 0
        self.animated = animated

        // One gravity for the whole deal: the longest drop lands in
        // `longestFall`, and every shorter one follows from the same g.
        let longest = tiles.map { $0.rest.y + $0.size / 2 + Self.startAbove }.max() ?? 1
        let g = 2 * Double(max(longest, 1)) / (Self.longestFall * Self.longestFall)

        for tile in tiles {
            let tileLayer = CALayer()
            tileLayer.bounds = CGRect(x: 0, y: 0, width: tile.size, height: tile.size)
            // Anchored at the BOTTOM edge — the squash compresses onto the
            // surface and the tilt pivots on the point that touches it.
            tileLayer.anchorPoint = CGPoint(x: 0.5, y: 1)
            tileLayer.zPosition = tile.depth
            tileLayer.contentsScale = traitCollection.displayScale
            tileLayer.allowsEdgeAntialiasing = true
            configureContents(of: tileLayer, for: tile)

            let restBottom = CGPoint(x: tile.rest.x, y: tile.rest.y + tile.size / 2)
            let restTransform = CATransform3DMakeRotation(
                CGFloat(tile.restTilt * .pi / 180), 0, 0, 1)
            // The model values are the LANDED state, so removing the animation
            // on completion leaves exactly what the fall ended on.
            tileLayer.position = restBottom
            tileLayer.transform = restTransform

            if animated {
                add(fallOf: tile, to: tileLayer, restBottom: restBottom,
                    restTransform: restTransform, g: g, start: start)
            }
            layer.addSublayer(tileLayer)
            tileLayers.append(tileLayer)
        }
        CATransaction.commit()
    }

    // MARK: - The physics

    private func add(fallOf tile: TileDrop, to tileLayer: CALayer,
                     restBottom: CGPoint, restTransform: CATransform3D,
                     g: Double, start: CFTimeInterval) {
        let startBottom = CGPoint(x: tile.rest.x + tile.drift, y: -Self.startAbove)
        let h = Double(restBottom.y - startBottom.y)
        guard h > 0 else { return }
        let fall = (2 * h / g).squareRoot()
        // A rebound to share s of the height is airborne for 2·√s of the fall.
        let air = Self.rebounds.map { 2 * $0.squareRoot() * fall }
        let heights = Self.rebounds.map { CGFloat($0 * h) }
        let duration = fall + air.reduce(0, +)

        // position: down, up, down, up, down — every leg a parabola.
        let t1 = fall
        let t2 = t1 + air[0]
        let t3 = t2 + air[1]
        let position = CAKeyframeAnimation(keyPath: "position")
        position.values = [
            NSValue(cgPoint: startBottom),
            NSValue(cgPoint: restBottom),
            NSValue(cgPoint: CGPoint(x: restBottom.x, y: restBottom.y - heights[0])),
            NSValue(cgPoint: restBottom),
            NSValue(cgPoint: CGPoint(x: restBottom.x, y: restBottom.y - heights[1])),
            NSValue(cgPoint: restBottom),
        ]
        position.keyTimes = [0, t1, t1 + air[0] / 2, t2, t2 + air[1] / 2, t3]
            .map { NSNumber(value: $0 / duration) }
        position.timingFunctions = [
            Self.accelerate, Self.decelerate, Self.accelerate, Self.decelerate, Self.accelerate,
        ]

        // transform: the tilt settles into rest; the squash marks each landing.
        func pose(_ degrees: Double, _ sx: CGFloat = 1, _ sy: CGFloat = 1) -> NSValue {
            let rot = CATransform3DMakeRotation(CGFloat(degrees * .pi / 180), 0, 0, 1)
            return NSValue(caTransform3D: CATransform3DScale(rot, sx, sy, 1))
        }
        let s0 = Self.squash[0], s1 = Self.squash[1]
        let flight = tile.restTilt * 1.6
        let landing = tile.restTilt * 1.2
        let transform = CAKeyframeAnimation(keyPath: "transform")
        transform.values = [
            pose(flight),
            pose(landing, s0.x, s0.y),
            pose(landing),
            pose(tile.restTilt, s1.x, s1.y),
            pose(tile.restTilt),
            NSValue(caTransform3D: restTransform),
        ]
        transform.keyTimes = [
            0, t1, min(t1 + s0.hold, t2), t2, min(t2 + s1.hold, t3), t3,
        ].map { NSNumber(value: $0 / duration) }

        let group = CAAnimationGroup()
        group.animations = [position, transform]
        group.duration = duration
        group.beginTime = start + tile.release
        group.fillMode = .backwards
        tileLayer.add(group, forKey: "drop")
    }

    /// `t²` as a cubic bezier — a falling body, exactly.
    private static let accelerate = CAMediaTimingFunction(controlPoints: 0.333, 0, 0.667, 0.333)
    /// Its mirror: a rising body losing speed to the same gravity.
    private static let decelerate = CAMediaTimingFunction(controlPoints: 0.333, 0.667, 0.667, 1)

    // MARK: - Contents

    /// The brand asset straight into `contents`, clipped to the app-icon
    /// squircle the same way `BridgeIcon` clips it; the symbol fallbacks
    /// (Apple's own seats, whose icons are not bundlable) are rendered once
    /// through `ImageRenderer` and cached for the deal.
    private func configureContents(of tileLayer: CALayer, for tile: TileDrop) {
        guard let image = image(for: tile) else { return }
        tileLayer.contents = image
        tileLayer.contentsGravity = .resizeAspectFill
        tileLayer.cornerRadius = DS.Radius.appIcon(tile.size)
        tileLayer.cornerCurve = .continuous
        tileLayer.masksToBounds = true
    }

    private func image(for tile: TileDrop) -> CGImage? {
        let key = "\(tile.name)@\(tile.size)"
        if let cached = imageCache[key] { return cached }
        let icon = BridgeIcon(name: tile.name, size: tile.size)
        let image: CGImage?
        if let asset = UIImage(named: icon.assetName)?.cgImage {
            image = asset
        } else {
            let renderer = ImageRenderer(content: icon)
            renderer.scale = traitCollection.displayScale
            image = renderer.uiImage?.cgImage
        }
        imageCache[key] = image
        return image
    }
}
