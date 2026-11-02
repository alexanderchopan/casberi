import SwiftUI

/// A cover's colour for a sheet's ground (prd §1650): the song's and the
/// episode's sheets stand on it, as Apple Music's album page does.
@MainActor
enum ArtGround {
    /// The art's average, deep enough that white words stand on it at 4.5:1
    /// or better: the hue kept, the saturation capped, the brightness fixed
    /// low. A colourless cover (a grey average) gives nil and the ink stays.
    static func color(from image: UIImage) -> Color? {
        guard let average = RemoteImageLoader.averageColor(of: image) else { return nil }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard average.getHue(&h, saturation: &s, brightness: &b, alpha: &a), s > 0.08 else { return nil }
        return deepened(hue: h, saturation: s)
    }

    /// A MARK's colour for a money sheet's ground (prd §1655): a logo, an
    /// avatar or an app icon is flat colour over black or white, so its
    /// average is a colour it does not have (Netflix's black icon read
    /// maroon, §1649 item 2). The neutral pixels are set aside and the
    /// largest hue among the rest is the colour; a mark that is mostly
    /// neutral gives nil and the ink stays.
    static func markColor(from image: UIImage) -> Color? {
        guard let cg = image.cgImage else { return nil }
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: &pixels, width: side, height: side,
                                  bitsPerComponent: 8, bytesPerRow: side * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        let bins = 12
        var weight = [CGFloat](repeating: 0, count: bins)
        var x = [CGFloat](repeating: 0, count: bins)
        var y = x, sat = x
        var opaque = 0, neutral = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = CGFloat(pixels[i + 3]) / 255
            guard alpha > 0.5 else { continue }
            opaque += 1
            let colour = UIColor(red: CGFloat(pixels[i]) / 255 / alpha,
                                 green: CGFloat(pixels[i + 1]) / 255 / alpha,
                                 blue: CGFloat(pixels[i + 2]) / 255 / alpha, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            guard colour.getHue(&h, saturation: &s, brightness: &b, alpha: &a),
                  s >= 0.25, b >= 0.2 else { neutral += 1; continue }
            let bin = min(bins - 1, Int(h * CGFloat(bins)))
            let w = s * b
            weight[bin] += w
            x[bin] += cos(h * 2 * .pi) * w
            y[bin] += sin(h * 2 * .pi) * w
            sat[bin] += s * w
        }
        guard opaque > 0, CGFloat(neutral) / CGFloat(opaque) <= 0.6,
              let top = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[top] > 0
        else { return nil }
        var hue = atan2(y[top], x[top]) / (2 * .pi)
        if hue < 0 { hue += 1 }
        return deepened(hue: hue, saturation: sat[top] / weight[top])
    }

    /// The hue kept, the saturation capped, the brightness fixed low: white
    /// words stand on it at 4.5:1 or better.
    private static func deepened(hue: CGFloat, saturation: CGFloat) -> Color {
        Color(UIColor(hue: hue, saturation: min(saturation, 0.62), brightness: 0.3, alpha: 1))
    }
}

/// A page that knows its ground hands it up to the sheet that paints it
/// (the subscription page, prd §1655): the page sits inside the scroll,
/// the ground belongs behind it.
struct ArtGroundPreference: PreferenceKey {
    static var defaultValue: Color? { nil }
    static func reduce(value: inout Color?, nextValue: () -> Color?) {
        value = value ?? nextValue()
    }
}

/// A sheet on its cover's colour: the ground behind everything, dark words
/// on it in either theme, cleared when the sheet walks to another thing.
struct ArtGroundStage<ID: Equatable>: ViewModifier {
    @Binding var ground: Color?
    let id: ID

    func body(content: Content) -> some View {
        content
            .background { (ground ?? .clear).ignoresSafeArea() }
            .transformEnvironment(\.colorScheme) { if ground != nil { $0 = .dark } }
            .onChange(of: id) { _, _ in ground = nil }
    }
}

extension View {
    func artGround<ID: Equatable>(_ ground: Binding<Color?>, resetOn id: ID) -> some View {
        modifier(ArtGroundStage(ground: ground, id: id))
    }
}

/// The picture behind a money face, the one its view draws (prd §1655): an
/// app's bundled art, a token's mark, a person's avatar. Nil where the face
/// is drawn, not pictured (a glyph, a monogram, an identicon, your own
/// face): those keep the ink.
@MainActor
enum FaceArt {
    static func app(_ name: String) -> UIImage? {
        BridgeIconArt.image(BridgeIconArt.assetName(for: name))
    }

    /// `AssetMark`'s rungs: the bundled mark, then the book's picture.
    static func asset(_ name: String) async -> UIImage? {
        if let own = BrandMark.image(for: name) { return own }
        guard !DemoMode.isActive, let url = TokenIconBook.url(for: name) else { return nil }
        return await picture(url)
    }

    /// `WalletFace`'s picture: the avatar the address set, never yours.
    static func address(_ address: String) async -> UIImage? {
        guard !YourAccountDemo.isYours(address), let url = WalletFace.avatar(for: address)
        else { return nil }
        return await picture(url)
    }

    static func picture(_ url: String) async -> UIImage? {
        if case .image(let art, _) = await RemoteImageLoader.load(urlString: url, targetSide: 120) {
            return art
        }
        return nil
    }
}
