import SwiftUI

/// The All feed's day name and its one clause (prd §767).
///
/// "Today" at 24pt with "mostly Work" stacked under it was the tallest object
/// between two runs of rows, and the loudest type on the feed. A room's divider
/// already set its clause (the count) on the name's baseline; this is that
/// shape, falling back to the stack only when the clause is too long to share
/// the line.
///
/// The name wears the brand ink (prd §740, §742: the day is the app's own
/// voice). The tail cools one weight step (prd §254): size and weight are the
/// only hierarchy this app has, and a size step down would land on the row
/// titles beneath it.
///
/// **It is also felt (prd §866.)** Passing under the finger, a divider ticks
/// once — see `FeedSeam` for the two disciplines that keep that a texture
/// rather than a rattle. It rides THIS view rather than the day headers in
/// general, which scopes it to the All feed by construction: `bundledSections`
/// is the only caller, and `daySection`'s own header (a raw HStack, and often
/// a named group rather than a day) is untouched. A seam you can feel should
/// be a seam in TIME, and this is the divider that only ever names one.
struct FeedDayDivider<Clause: View>: View {
    let label: String
    var weight: Font.Weight = .bold
    /// Whether the label names a DATE (prd §740). "Since you left" names a
    /// span measured from you, not a day, so it wears the primary ink and the
    /// day names inside it keep the pink (prd §880) — `daySection`'s own
    /// `dated:` rule, the one the rooms' named groups already follow.
    var dated: Bool = true
    @ViewBuilder var clause: Clause

    /// The seam this divider IS, felt as it passes (prd §866) — see
    /// `FeedSeam`. Held by `@State` so its identity survives every render;
    /// nothing is written to the VIEW, so a crossing costs no re-render.
    @State private var tracker = FeedSeam.Tracker()

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                name
                clause
            }
            VStack(alignment: .leading, spacing: 1) {
                name
                clause
            }
        }
        // ONE COMPARISON PER GEOMETRY CHANGE, and the action fires only when
        // the answer changes sides (prd §661: row bodies stay cheap while
        // scrolling). The value is a three-state, not a Bool, so the dead
        // band around the line can swallow a parked divider's jitter —
        // `FeedSeam.side` carries that reasoning.
        //
        // `.scrollView` space, so the line is the top of the feed's own
        // viewport: the seam is felt when the day it names becomes the day
        // you are in, which is the same instant the header would leave the
        // screen. Measuring against `.global` would put the line under the
        // status bar instead, a place nothing on this screen means.
        .onGeometryChange(for: Int.self) { proxy in
            FeedSeam.side(ofTop: proxy.frame(in: .scrollView).minY)
        } action: { _, now in
            FeedSeam.observe(side: now, in: tracker)
        }
    }

    private var name: some View {
        Text(label)
            .dsText(.heading24)
            .fontWeight(weight)
            .foregroundStyle(dated ? DS.brandInk : DS.textPrimary)
    }
}
