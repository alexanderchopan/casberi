import SwiftUI

/// GENERATED ART FOR THE DEMO'S NFT SHELF (2026-08-15, prd §387).
///
/// Drawn procedurally from a seed — no asset, no network, no bytes on disk, and
/// **no real NFT**. That last part is the ruling (user: "it can be generated
/// art that is free, not real nfts"): a demo showing real collections would be
/// reproducing somebody else's artwork, and would also imply the demo wallet
/// owns pieces it does not. Generative art is its own genre, so a seeded
/// composition is an honest thing for a demo NFT to be rather than a stand-in
/// for one.
///
/// Deterministic by construction: the same seed always draws the same picture,
/// so the demo shelf looks identical on every open and across every device
/// (`DemoMode.restampIfStale` moves dates, and a shelf that reshuffled its art
/// underneath that would read as pieces arriving and leaving).
///
/// Static — no animation at all, so there is nothing here for the motion law to
/// govern; the shelf's own entrance is the section's `RowEntrance`, like every
/// other card in that room.
struct DemoNFTArt: View {
    let seed: Int

    /// A tiny deterministic generator. Not for anything but pixel positions —
    /// `Math.random()` is unavailable to workflows for the same class of reason
    /// this is seeded: a picture that changes between reads is a picture that
    /// reads as new data arriving.
    private struct Roll {
        private var state: UInt64
        init(_ seed: Int) { state = UInt64(truncatingIfNeeded: seed &* 2_654_435_761 &+ 1) }
        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double((state >> 33) % 10_000) / 10_000
        }
        mutating func pick<T>(_ options: [T]) -> T {
            options[min(Int(next() * Double(options.count)), options.count - 1)]
        }
    }

    /// Fixed hues rather than random ones, so no composition can land on the
    /// muddy or the near-invisible. Picked to sit apart from the app's own
    /// accent, which is blue — a demo tile should not read as chrome.
    private static let palettes: [[String]] = [
        ["#f4a261", "#e76f51", "#264653"],
        ["#8ecae6", "#219ebc", "#023047"],
        ["#cdb4db", "#ffc8dd", "#bde0fe"],
        ["#606c38", "#dda15e", "#283618"],
        ["#e07a5f", "#3d405b", "#f2cc8f"],
        ["#b7e4c7", "#40916c", "#1b4332"],
    ]

    var body: some View {
        var roll = Roll(seed)
        let palette = roll.pick(Self.palettes).map { Color.fixed($0) }
        let shapes = 3 + Int(roll.next() * 4)
        // Captured so the closure below doesn't need a mutating generator.
        let marks: [(x: Double, y: Double, size: Double, hue: Int, round: Bool)] =
            (0..<shapes).map { _ in
                (x: roll.next(), y: roll.next(),
                 size: 0.22 + roll.next() * 0.5,
                 hue: Int(roll.next() * 3),
                 round: roll.next() > 0.45)
            }
        let flip = marks.first?.round ?? true

        return GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                LinearGradient(colors: [palette[0], palette[2]],
                               startPoint: flip ? .topLeading : .bottomLeading,
                               endPoint: flip ? .bottomTrailing : .topTrailing)
                ForEach(marks.indices, id: \.self) { i in
                    let m = marks[i]
                    Group {
                        if m.round {
                            Circle().fill(palette[m.hue % palette.count])
                        } else {
                            RoundedRectangle(cornerRadius: side * 0.06, style: .continuous)
                                .fill(palette[m.hue % palette.count])
                        }
                    }
                    .frame(width: side * m.size, height: side * m.size)
                    .opacity(0.45 + Double(i % 3) * 0.2)
                    .position(x: side * (0.15 + m.x * 0.7),
                              y: side * (0.15 + m.y * 0.7))
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
