import SwiftUI

/// A watched wallet's face (2026-07-15) — the identity mark that ends "three
/// watched wallets, three identical blue icons". An ENS avatar when the
/// address published one (resolved and cached in WalletStore, read here by
/// hex address); otherwise a deterministic identicon seeded from the address,
/// so the SAME wallet always wears the SAME face and two wallets never collide.
/// Read-only public data, like everything the wallet shows.
///
/// The identicon is drawn in the app's own idiom — a soft seeded gradient with
/// two berry blobs floating over it — never a scannable QR-ish grid (that reads
/// as data, not identity). No image is ever hot-linked without a fallback: a
/// slow or broken avatar shows the identicon underneath until (if) it loads.
struct WalletFace: View {
    /// The stored hex address — the stable identity (labels are free text).
    let address: String
    var size: CGFloat = 36

    private var avatarURL: URL? {
        WalletStore.shared.avatarURL(for: address).flatMap(URL.init(string:))
    }

    var body: some View {
        identicon
            .overlay {
                if let avatarURL {
                    AsyncImage(url: avatarURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                                .transition(.opacity)
                        }   // failure/empty: the identicon shows through
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.appIcon(size),
                                        style: .continuous))
    }

    // MARK: - Identicon

    /// A seeded LCG off the address bytes — the same seed→same face rule the
    /// berry rain uses, so a wallet's identicon is stable across launches and
    /// screens without persisting anything.
    private var rng: (base: Double, alt: Double, b1: CGSize, b2: CGSize) {
        var state: UInt64 = 1
        for byte in address.lowercased().utf8 {
            state = state &* 31 &+ UInt64(byte)
        }
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            // >> 32 leaves a full 32-bit value (max UInt32.max), so the ratio
            // spans the whole [0, 1] — >> 33 would halve it, penning every hue
            // into the red→cyan half and both blobs into one quadrant.
            return Double(state >> 32) / Double(UInt32.max)
        }
        let base = next()                 // primary hue 0…1
        let alt = (base + 0.12 + next() * 0.18).truncatingRemainder(dividingBy: 1)
        return (base, alt,
                CGSize(width: next() - 0.5, height: next() - 0.5),
                CGSize(width: next() - 0.5, height: next() - 0.5))
    }

    /// The wallet's signature hue — the identicon's base hue, exposed so the
    /// combined sheet can draw each wallet's value line in the same color as
    /// its face (identity carried across surfaces). Folds and advances the
    /// seed exactly as `rng`'s first draw, so line and face always agree.
    static func tint(for address: String) -> Color {
        var state: UInt64 = 1
        for byte in address.lowercased().utf8 { state = state &* 31 &+ UInt64(byte) }
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let hue = Double(state >> 32) / Double(UInt32.max)   // full [0,1] — matches rng
        return Color(hue: hue, saturation: 0.68, brightness: 0.78)
    }

    private var identicon: some View {
        let seed = rng
        // Two hues a short arc apart — vivid but never garish (fixed S/B in
        // the berry register). Light/dark both read: the fill is mid-bright,
        // the blobs a touch lighter, so the mark holds on either page.
        let c1 = Color(hue: seed.base, saturation: 0.62, brightness: 0.82)
        let c2 = Color(hue: seed.alt, saturation: 0.70, brightness: 0.72)
        return LinearGradient(colors: [c1, c2],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                GeometryReader { geo in
                    let d = geo.size.width
                    Circle().fill(.white.opacity(0.22))
                        .frame(width: d * 0.5, height: d * 0.5)
                        .offset(x: seed.b1.width * d * 0.6, y: seed.b1.height * d * 0.6)
                    Circle().fill(.black.opacity(0.12))
                        .frame(width: d * 0.42, height: d * 0.42)
                        .offset(x: seed.b2.width * d * 0.7, y: seed.b2.height * d * 0.7)
                }
                .blur(radius: size * 0.06)
            }
    }
}
