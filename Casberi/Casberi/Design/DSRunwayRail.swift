import SwiftUI

/// One axis for a whole card, revealed left to right — time, moving, in the
/// direction the deadlines approach.
///
/// **Four rooms drew this and each drew it themselves.** Stripe's, Polar's and
/// Dodo Payments' rails were byte-identical but for the type name they called
/// `position` on; Cloudflare's was the same plus a gridline and a tap. Each
/// re-declared `dot`, `leadDot` and `tickRoom` at the same three values, and
/// each re-derived the same centring. A fifth room copying the fourth is how
/// this file's constants would have gone on multiplying.
///
/// Marks are placed against the axis width MINUS one mark, so the furthest sits
/// inside the rail instead of hanging off its end; each is centred by nesting
/// it in a full-size frame rather than by a half-difference computed per shape.
///
/// **Sized from data, so it arrives** (design-motion law) and stands still
/// under Reduce Motion.
///
/// **Hidden from VoiceOver, deliberately**: every mark on this axis is a row
/// below it, and those rows carry the name, the kind and the days. A spoken
/// rail would be the same facts a second time, in a worse order (the
/// `ShareBar`/`UniswapRangeBar` rule). Contrast `WalletFlowBand`, whose diagram
/// is the ONLY statement of its facts and so gets a sentence. On a card with no
/// rows the headline already says the whole finding, so an empty spoken axis
/// would add nothing but confusion.
struct DSRunwayRail: View {

    /// One thing on the axis. `position` is already 0…1 — the caller places it
    /// through its own room's `position(days:span:)`, so the room's selftest
    /// keeps asserting the placement it ships with.
    struct Mark: Identifiable {
        let id: String
        let position: Double
        /// The nearest one, drawn larger and in the room's own hue. Exactly one
        /// mark should carry it.
        var lead: Bool = false

        init(id: String, position: Double, lead: Bool = false) {
            self.id = id
            self.position = position
            self.lead = lead
        }
    }

    let marks: [Mark]
    /// The right-hand tick. The caller passes its own room's `spanLabel`, so an
    /// axis can never be labelled with a length it isn't.
    let spanLabel: String
    /// The lead mark's fill — the room's own brand hue.
    let leadFill: Color
    let reduceMotion: Bool
    /// Gridline positions, 0…1, strictly inside the rail. Empty for the rooms
    /// that draw none.
    var gridlines: [Double] = []
    /// A pick hands back the mark's id. Nil leaves the rail inert — most of
    /// these rails have their rows directly below and need no second door.
    var onPick: ((String) -> Void)? = nil

    private static let dot: CGFloat = 11
    private static let leadDot: CGFloat = 15
    private static let tickRoom: CGFloat = 18
    /// A finger's reach. `nearestMark`'s 22pt rule, widened a touch because
    /// these dots sit sparser than chart marks. A miss does nothing.
    private static let reach: CGFloat = 30

    var body: some View {
        GeometryReader { geo in
            let travel = max(geo.size.width - Self.leadDot, 1)
            ZStack(alignment: .topLeading) {
                mark(Capsule(), width: geo.size.width, height: 2,
                     fill: DS.fillLine, at: 0, travel: 0)

                ForEach(Array(gridlines.enumerated()), id: \.offset) { _, at in
                    mark(Capsule(), width: 2, height: 8, fill: DS.fillStrong,
                         at: at, travel: travel)
                }

                ForEach(marks) { item in
                    let size = item.lead ? Self.leadDot : Self.dot
                    mark(Circle(), width: size, height: size,
                         fill: item.lead ? leadFill : DS.fillStrong,
                         at: item.position, travel: travel)
                }
            }
            .frame(height: Self.leadDot)
            .overlay(alignment: .bottomLeading) { tick(String(localized: "Today")) }
            .overlay(alignment: .bottomTrailing) { tick(spanLabel) }
            .modifier(RailPick(marks: marks, travel: travel,
                               leadDot: Self.leadDot, reach: Self.reach,
                               onPick: onPick))
        }
        .frame(height: Self.leadDot + Self.tickRoom)
        .chartWipe(reduceMotion: reduceMotion)
        .accessibilityHidden(true)
    }

    /// One thing on the axis, centred on the track at `position`.
    private func mark<S: Shape>(_ shape: S, width: CGFloat, height: CGFloat,
                                fill: Color, at position: Double,
                                travel: CGFloat) -> some View {
        shape
            .fill(fill)
            .frame(width: width, height: height)
            .frame(width: max(width, Self.leadDot), height: Self.leadDot)
            .offset(x: position * travel)
    }

    private func tick(_ text: String) -> some View {
        Text(text)
            .dsText(.label11)
            .foregroundStyle(DS.textTertiary)
            .monospacedDigit()
            .offset(y: Self.tickRoom)
    }
}

/// The dot press (prd §384): nearest mark within a finger's reach wins.
///
/// A MODIFIER rather than an inline `.gesture`, so a rail with no handler
/// attaches no gesture at all — an always-on `contentShape(Rectangle())` over
/// an inert rail would swallow taps meant for whatever sits behind it.
private struct RailPick: ViewModifier {
    let marks: [DSRunwayRail.Mark]
    let travel: CGFloat
    let leadDot: CGFloat
    let reach: CGFloat
    let onPick: ((String) -> Void)?

    func body(content: Content) -> some View {
        if let onPick {
            content
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { value in
                    let distance = { (m: DSRunwayRail.Mark) -> CGFloat in
                        abs(m.position * travel + leadDot / 2 - value.location.x)
                    }
                    guard let hit = marks.min(by: { distance($0) < distance($1) }),
                          distance(hit) <= reach else { return }
                    DSHaptic.selection()
                    onPick(hit.id)
                })
        } else {
            content
        }
    }
}
