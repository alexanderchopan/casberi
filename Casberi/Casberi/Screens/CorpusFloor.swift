import SwiftUI

/// The bottom of the corpus — the mark drawing itself over the floor's line
/// (prd §866).
///
/// The line is §218's and unchanged: the real date of the oldest thing kept,
/// a FACT rather than a compliment, which is why this is a place the app can
/// afford a flourish at all. Reaching it is the one arrival in the feed that
/// is entirely the person's doing — they scrolled the whole way — and it is
/// the only moment in the app where there is nothing below, so nothing is
/// competing with it and nothing is delayed by it.
///
/// **The mark draws, then settles.** The outline strokes on over `draw`, and
/// then the real mark fades up through it. Both halves are needed: an outline
/// octopus is not the app's mark, it is a drawing of it — the settle is what
/// makes the thing that arrives the same mark that sits in the dock. This is
/// the gesture prd §5 specified for the quiet element in 2026-07-06;
/// `CasberiMarkShape` was built for it and has had no caller since that screen
/// was cut, so this is the shape finally getting the moment it was drawn for.
///
/// It cannot fire wrongly — there is no claim in it — and it cannot fire twice
/// on one arrival. Scroll away far enough for the row to be torn down and
/// coming back draws it again, which is correct: it marks arriving, and you
/// arrived again.
struct CorpusFloor: View {
    let oldest: Date

    @State private var drawn = false
    @State private var settled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// prd §5's own number, kept: slow enough to read as drawing rather than
    /// appearing, and this is the one place in the app with nothing waiting
    /// behind it.
    private static let draw: Double = 0.9
    private static let settle: Double = 0.25

    /// `Mark.tile` — the rung for "the mark IS the item's identity, not a
    /// label on it", which is exactly what it is here.
    private static let size = DS.Mark.tile

    var body: some View {
        VStack(spacing: DS.Space.s3) {
            ZStack {
                CasberiMarkShape()
                    .trim(from: 0, to: drawn ? 1 : 0)
                    // The mark's own hue, not `brandInk`: §742 softens the
                    // hue for TYPE, and this is the mark itself, drawn at the
                    // size and colour it wears everywhere else.
                    .stroke(DS.brand,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    // Out as the solid one comes in, so the outline is never
                    // left printed under the fill.
                    .opacity(settled ? 0 : 1)
                CasberiMark(size: Self.size)
                    .opacity(settled ? 1 : 0)
            }
            .frame(width: Self.size, height: Self.size)
            .accessibilityHidden(true)

            Text("This is where it starts · \(oldest.formatted(.dateTime.month(.abbreviated).day()))")
                .dsText(.subhead12)
                .foregroundStyle(DS.textTertiary)
                .accessibilityLabel("The oldest thing you kept is from \(oldest.formatted(.dateTime.month(.wide).day().year()))")
        }
        .frame(maxWidth: .infinity)
        .onAppear(perform: arrive)
    }

    private func arrive() {
        // Reduce Motion takes the final frame, `ChartEntrance`'s rule: the
        // mark is still there, it simply does not perform.
        guard !reduceMotion else { drawn = true; settled = true; return }
        guard !drawn else { return }
        withAnimation(.easeOut(duration: Self.draw)) { drawn = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.draw))
            withAnimation(.easeIn(duration: Self.settle)) { settled = true }
        }
    }
}
