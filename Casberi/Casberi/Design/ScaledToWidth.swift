import SwiftUI

/// **A LINE THAT SHRINKS EVENLY TO FIT (prd §1558)** — its content drawn at
/// its own size, and scaled down as one piece when the width offered is less,
/// from the leading edge. No rung of its own and no step between rungs: the
/// words keep the rung they were set in, a little smaller only where the
/// phone is narrow. Never a scroll, never a clip (user: "no scrolling", "we
/// don't want to hand roll sizes").
///
/// The last fit in a `ViewThatFits`, after the gaps have narrowed: it always
/// fits, so anything after it never draws.
struct ScaledToWidth<Content: View>: View {
    @ViewBuilder var content: Content
    /// The content's own size, measured before the scale (a scale does not
    /// change layout, so this never feeds back on itself).
    @State private var natural: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let scale = natural.width > 0 ? min(1, geo.size.width / natural.width) : 1
            content
                .fixedSize()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { natural = $0 }
                .scaleEffect(scale, anchor: .leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: natural.height > 0 ? natural.height : nil)
    }
}
