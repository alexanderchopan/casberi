import SwiftUI
import UIKit

/// The swipe's table as a sheet of frosted glass over the brand pink (prd
/// §898b, user: "ok, ship C"). `DS.brandGround` stays the ONE colour; this is
/// the light on it. One static picture per window size, rendered once off
/// main and cached, drawn by `SwipeGround` on the turn's ramp — never a live
/// material, because a `Material` blurs what is BEHIND it and behind the
/// shell's coat there is nothing but the page, so glass there reads as a grey
/// slab (mocked, declined). A texture fill is what a swipe pays per frame.
///
/// **One light, and every layer answers to it.** High and to the left, soft,
/// the room's light on the sheet. The earlier boards were random pools and
/// diagonal streaks laid on a colour (user: "those look vibecoded"); nothing
/// here is random.
///
/// - **Fall-off** across the sheet from that corner: a 10% lift of white at
///   the top left through nothing at 42%, then a 16% dip of black by the
///   bottom right.
/// - **One window reflection**: a wide soft ellipse near the top, 11% white
///   at its centre. One, because a room has one window.
/// - **Corners darker** where the glass is thickest: a 90pt inset shade at
///   18% on all four edges.
/// - **Milk**: a uniform 7% scatter of `#f2eef0`. A finish, not the effect;
///   the light does the glass work so the hue survives. (25% over a darker
///   base was the runner-up: more visible frost, a step toward mauve, and
///   the dock's capsule stopped reading as its own layer.)
/// - **Grain**: a 64pt tile of noise, soft-light at 5%. Frost, not noise.
///
/// The card's shadow widens to match (`MainSurface`, the lift block): frost
/// scatters light, and the wider shadow is the physical tell that the sheet
/// is frost and not paint.
///
/// **Ink.** White measures 5.7:1 at the brightest point (under the window,
/// where the status bar's clock sits), 9.6:1 on the plain sheet and 11.0:1 at
/// the darkest corner. AA everywhere; under Increase Contrast the window and
/// the lift are halved so the brightest point clears 7:1 without a second
/// ink (`brandGroundInk` stays white in both themes, §898).
///
/// Rendered at scale 2, not the device's 3: the layers are smooth gradients
/// and a tile, so 2 is indistinguishable and the bitmap is half the memory
/// (the `UIGraphicsImageRenderer` scale gotcha, read the other way).
enum BrandSheet {
    /// The base under the light: `DS.brandGround`'s value, read through the
    /// token so the colour has one spelling.
    private static func base() -> UIColor? {
        DS.brandGround.map { UIColor($0) }
    }

    @MainActor private static var cache: [String: UIImage] = [:]

    /// The sheet for a window of `size`, from the cache when it has one.
    @MainActor
    static func cached(for size: CGSize, moreContrast: Bool) -> UIImage? {
        cache[key(size, moreContrast)]
    }

    /// Renders off main and stores the result; `SwipeGround` awaits this
    /// from its `.task`, never from a body pass.
    @MainActor
    static func prepare(for size: CGSize, moreContrast: Bool) async {
        let k = key(size, moreContrast)
        if cache[k] != nil { return }
        guard size.width >= 1, size.height >= 1, let base = base() else { return }
        let image = await Task.detached(priority: .utility) {
            render(size: size, base: base, moreContrast: moreContrast)
        }.value
        cache[k] = image
    }

    private static func key(_ size: CGSize, _ moreContrast: Bool) -> String {
        "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))\(moreContrast ? "+" : "")"
    }

    // MARK: - The drawing

    /// CSS's `linear-gradient(160deg, …)`: 0° points up, 90° right; the
    /// line runs through the centre and is long enough that the first and
    /// last stops sit exactly on the corners it leans toward.
    private static func gradientLine(angleDegrees: Double, in rect: CGRect) -> (CGPoint, CGPoint) {
        let a = angleDegrees * .pi / 180
        let dir = CGVector(dx: sin(a), dy: -cos(a))
        let length = abs(rect.width * dir.dx) + abs(rect.height * dir.dy)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        return (CGPoint(x: c.x - dir.dx * length / 2, y: c.y - dir.dy * length / 2),
                CGPoint(x: c.x + dir.dx * length / 2, y: c.y + dir.dy * length / 2))
    }

    private static func render(size: CGSize, base: UIColor, moreContrast: Bool) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let rect = CGRect(origin: .zero, size: size)
        let lift = moreContrast ? 0.5 : 1.0
        let space = CGColorSpaceCreateDeviceRGB()
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext

            // The pink.
            cg.setFillColor(base.cgColor)
            cg.fill(rect)

            // Fall-off from the light's corner.
            if let fall = CGGradient(colorsSpace: space,
                                     colors: [UIColor(white: 1, alpha: 0.10 * lift).cgColor,
                                              UIColor(white: 1, alpha: 0).cgColor,
                                              UIColor(white: 0, alpha: 0).cgColor,
                                              UIColor(white: 0, alpha: 0.16).cgColor] as CFArray,
                                     locations: [0, 0.42, 0.60, 1]) {
                let (from, to) = gradientLine(angleDegrees: 160, in: rect)
                cg.drawLinearGradient(fall, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }

            // One window reflection: an ellipse 62% wide and 30% tall,
            // centred at (22%, 9%). Core Graphics radials are circles, so
            // the context is squashed for the one draw.
            if let window = CGGradient(colorsSpace: space,
                                       colors: [UIColor(white: 1, alpha: 0.11 * lift).cgColor,
                                                UIColor(white: 1, alpha: 0).cgColor] as CFArray,
                                       locations: [0, 0.70]) {
                let rx = size.width * 0.62, ry = size.height * 0.30
                let centre = CGPoint(x: size.width * 0.22, y: size.height * 0.09)
                cg.saveGState()
                cg.translateBy(x: centre.x, y: centre.y)
                cg.scaleBy(x: 1, y: ry / rx)
                cg.drawRadialGradient(window, startCenter: .zero, startRadius: 0,
                                      endCenter: .zero, endRadius: rx, options: [])
                cg.restoreGState()
            }

            // Corners darker: a 90pt shade in from each edge.
            if let edge = CGGradient(colorsSpace: space,
                                     colors: [UIColor(white: 0, alpha: 0.18).cgColor,
                                              UIColor(white: 0, alpha: 0).cgColor] as CFArray,
                                     locations: [0, 1]) {
                let depth: CGFloat = 90
                cg.drawLinearGradient(edge, start: CGPoint(x: 0, y: rect.midY), end: CGPoint(x: depth, y: rect.midY), options: [])
                cg.drawLinearGradient(edge, start: CGPoint(x: rect.maxX, y: rect.midY), end: CGPoint(x: rect.maxX - depth, y: rect.midY), options: [])
                cg.drawLinearGradient(edge, start: CGPoint(x: rect.midX, y: 0), end: CGPoint(x: rect.midX, y: depth), options: [])
                cg.drawLinearGradient(edge, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.maxY - depth), options: [])
            }

            // Milk.
            cg.setFillColor(UIColor(red: 242 / 255, green: 238 / 255, blue: 240 / 255, alpha: 0.07).cgColor)
            cg.fill(rect)

            // Grain, tiled, soft-light.
            if let tile = grainTile() {
                cg.saveGState()
                cg.setBlendMode(.softLight)
                cg.setAlpha(0.05)
                cg.draw(tile, in: CGRect(x: 0, y: 0, width: 64, height: 64), byTiling: true)
                cg.restoreGState()
            }
        }
    }

    /// 64×64 grey noise, seeded, so every render of the sheet is the same
    /// picture (a sheet that re-grains between sizes would shimmer on
    /// rotation).
    private static func grainTile() -> CGImage? {
        let side = 64
        var seed: UInt32 = 0x9E37_79B9
        var bytes = [UInt8](repeating: 0, count: side * side)
        for i in 0..<bytes.count {
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
            bytes[i] = UInt8(truncatingIfNeeded: seed)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: side,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
