import SwiftUI

/// **THE CIRCLE PACK (prd §917): each item is one circle whose AREA is its
/// share and whose MARK is its label.**
///
/// The Watch honeycomb and App Library move applied to a figure: an icon is
/// its own label, so there is no cell, no name and no magnitude wash — the
/// mark fills the circle and the circle's size says how much. `CirclePack`
/// owns the geometry (pure, harnessed); this owns what every treemap in the
/// app already speaks and the pack must speak too, or the two rooms feel
/// like different apps:
///
///   · THE ENTRANCE — biggest first, `settleIn` at the treemap's 60ms beat.
///   · THE TRAVEL (§501) — keyed by the caller's identity, so the same
///     holdings re-measured under one account MOVE to their new sizes and
///     places rather than cutting. Reduce Motion stills both.
///   · THE PRESS — `DSTileButtonStyle`, exactly as a cell pressed.
///   · THE READOUT — a Mac hover names what a small mark cannot.
///
/// **Which figure a caller gets is not this view's choice.** A mark packs, a
/// word tiles: the wallet's holdings and the sources have marks on one scale
/// and come here; the themes, the OCR terms, the receipts' hosts and the
/// devnets' unpriced holdings keep `UnitTreemap`. Nothing here draws a
/// figure or a word inside the circle — the rows under the map carry both
/// (§491), and Hide balances (§374) leaves a pack of shares unmoved.
/// One circle's facts. File-scope rather than nested, so a caller names it
/// without spelling the view's mark type.
struct DSCirclePackItem: Identifiable, Equatable {
    /// Stable across a re-measure — a token's symbol, a source's name.
    let id: String
    /// Any positive magnitude on one scale (USD, a count).
    let share: Double
    /// What VoiceOver says for the circle: the name and its share.
    let label: String
}

struct DSCirclePack<Mark: View>: View {
    typealias Item = DSCirclePackItem

    let items: [Item]
    var gap: CGFloat = DS.Space.s1
    /// The mark for an item at the circle's DIAMETER. The caller decides
    /// whether that is a bundled brand mark, an app icon or a monogram.
    @ViewBuilder var mark: (Item, CGFloat) -> Mark
    var action: ((Item) -> Void)? = nil
    var readout: ((Item) -> String?)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Repeated ids are disambiguated by index rather than trusted: a
    /// duplicated `ForEach` id silently drops a circle (`UnitTreemap.keys`'s
    /// own rule).
    private var keyed: [(key: String, item: Item)] {
        var seen: Set<String> = []
        return items.enumerated().map { i, item in
            (seen.insert(item.id).inserted ? item.id : "\(item.id)#\(i)", item)
        }
    }

    /// Entrance order: the biggest circle settles first.
    private var ranks: [Int] {
        let order = items.indices.sorted { a, b in
            items[a].share != items[b].share ? items[a].share > items[b].share : a < b
        }
        var rank = [Int](repeating: 0, count: items.count)
        for (r, i) in order.enumerated() { rank[i] = r }
        return rank
    }

    /// The travel key: any change of set or share moves the circles.
    private var travelKey: [String] {
        items.map { "\($0.id):\($0.share)" }
    }

    var body: some View {
        GeometryReader { geo in
            let circles = CirclePack.layout(shares: items.map(\.share), in: geo.size, gap: gap)
            let ranks = ranks
            ZStack(alignment: .topLeading) {
                ForEach(Array(keyed.enumerated()), id: \.element.key) { i, pair in
                    let c = circles[i]
                    circle(pair.item, diameter: c.radius * 2)
                        .frame(width: c.radius * 2, height: c.radius * 2)
                        .position(c.center)
                        .settleIn(delay: Double(ranks[i]) * 0.06)
                        .dsReadout(readout?(pair.item))
                }
            }
            .animation(reduceMotion ? nil : DS.Motion.standard, value: travelKey)
        }
    }

    @ViewBuilder
    private func circle(_ item: Item, diameter: CGFloat) -> some View {
        if let action {
            Button {
                DSHaptic.selection()
                action(item)
            } label: {
                mark(item, diameter)
                    .contentShape(Circle())
            }
            .buttonStyle(DSTileButtonStyle())
            .accessibilityLabel(item.label)
        } else {
            mark(item, diameter)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.label)
        }
    }
}
