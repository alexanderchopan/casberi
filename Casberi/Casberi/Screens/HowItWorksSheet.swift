import SwiftUI

/// "How it works" (2026-07-11) — the one persistent place that explains the
/// model, for a new person after the retiring coach lines are gone. Re-ruled
/// 2026-07-16: the evergreen abstractions ("Keep tabs", "Make it yours") left
/// a real tester not knowing what to do — now it teaches the ONE loop that
/// matters, as four numbered steps: open the store → connect → pin → ask. Still no
/// gesture-by-gesture manual; it names the store's place and glyph because
/// that door is the whole game. Reached from the Settings tile to revisit any
/// time, and wired into the onboarding tail so a new person meets it once.
///
/// Redesigned 2026-07-16 (user: "more visually stunning, large proportions"):
/// each step is a full-width card wearing its numeral GIANT — SF Rounded
/// heavy, bleeding off the card's top-right corner — with a big glyph chip
/// and the title at the heading-22 tier. The numeral is information (the
/// sequence), not decoration; its hue is the step's identity, same as the
/// glyph chip it echoes. Step 1 carries a settled strip of real app icons,
/// slightly uneven like the onboarding rain they just watched land — the
/// same brands, come to rest. Cards arrive staggered, the connect screen's
/// entrance. In the onboarding tail the page ends at a "Browse the store"
/// door that lands IN the store (the arc: apps rain down → the four steps →
/// the store where those apps live); from Settings it keeps the plain Done.
/// Text literals auto-localize (LocalizedStringKey).
struct HowItWorksSheet: View {
    /// Set by the onboarding tail: the CTA that dismisses onboarding INTO
    /// the store. Nil from Settings — the toolbar Done is the exit there.
    var onOpenStore: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var arrived = false

    private struct Point: Identifiable {
        let glyph: String
        let hue: Color
        let title: LocalizedStringKey
        let line: LocalizedStringKey
        var id: String { glyph }
    }

    // Four numbered steps (ruling 2026-07-16, replacing the four abstract
    // beats): a new person must leave knowing exactly (1) where the store is,
    // (2) that connecting fills the feed by itself, (3) what pinning is FOR,
    // (4) that the composer answers questions about what they've saved.
    // Step 1 wears the REAL Apps-door glyph (TopDoors' square.grid.2x2) so
    // they recognize it in the shell later. Step 3's line closes the loop
    // explicitly — "the feed always has everything" — because "keep in sight"
    // phrasing read as if unpinned things vanish (user, 2026-07-16).
    // The titles carry no "1." prefix — the giant numeral IS the number.
    private let points: [Point] = [
        Point(glyph: "square.grid.2x2.fill", hue: .blue,
              title: "Open the store",
              line: "Top right of your feed. Apps, people, wallets, stocks — everything you can add lives there."),
        Point(glyph: "checkmark.circle.fill", hue: .green,
              title: "Connect things",
              line: "Everything you connect lands in your feed, automatically."),
        Point(glyph: "pin.fill", hue: .pink,
              title: "Pin your favorites",
              line: "Home is built from what you pin. The feed always has everything."),
        // Wears the composer FAB's real glyph (a plain plus), same reason
        // step 1 wears the store's grid.
        Point(glyph: "plus", hue: .purple,
              title: "Ask",
              line: "Tap the + button and ask questions about anything you've saved."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    // The header is the display tier — same 34-heavy SF
                    // Rounded as the connect screen's title, so the two
                    // onboarding beats read as one voice.
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        Text("How it works")
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundStyle(DS.textPrimary)
                            .minimumScaleFactor(0.8)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Everything you care about, from every app, in one place that's yours.")
                            .dsText(.body17)
                            .foregroundStyle(DS.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, DS.Space.s2)
                    .arrive(arrived, delay: 0.1)

                    ForEach(Array(points.enumerated()), id: \.element.id) { i, point in
                        stepCard(i, point)
                            .arrive(arrived, delay: 0.25 + Double(i) * 0.12)
                    }
                }
                .padding(.horizontal, DS.Space.s4)
                .padding(.bottom, DS.Space.s8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .dsPageBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // From Settings the sheet keeps its plain exit; in the
                // onboarding tail the store CTA below is the only door
                // forward (one door, the connect screen's rule).
                if onOpenStore == nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .tint(DS.tint)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let onOpenStore {
                    Button {
                        DSHaptic.success()
                        onOpenStore()
                    } label: {
                        Text("Browse the store")
                            .dsText(.body17)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(.plain)
                    // Floating chrome — glass is the floating layer's law.
                    .dsGlassProminent(tint: DS.tint, cornerRadius: DS.Radius.pill)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.bottom, DS.Space.s2)
                }
            }
        }
        .tint(DS.tint)
        .onAppear { withAnimation(DS.Motion.standard) { arrived = true } }
        #if DEBUG
        // `-howItWorksCTA <s>` fires the onboarding-tail CTA after a delay —
        // the store landing verifies headlessly (the `-demoPick` pattern).
        .onAppear {
            let delay = UserDefaults.standard.double(forKey: "howItWorksCTA")
            guard delay > 0, let onOpenStore else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                NSLog("howItWorksCTA: fired")
                onOpenStore()
            }
        }
        #endif
    }

    // MARK: - One step, writ large

    /// A full-width card: the numeral huge and bleeding off the top-right
    /// corner (clipped by the card), the glyph in a big tinted chip, the
    /// title at heading-22. The numeral duplicates the reading order for
    /// sighted users only, so it hides from accessibility.
    private func stepCard(_ index: Int, _ point: Point) -> some View {
        ZStack(alignment: .topTrailing) {
            Text(verbatim: "\(index + 1)")
                .font(.system(size: 148, weight: .heavy, design: .rounded))
                .foregroundStyle(point.hue.opacity(0.16))
                .offset(x: DS.Space.s3, y: -DS.Space.s8 - DS.Space.s3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                Image(systemName: point.glyph)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(point.hue)
                    .frame(width: 58, height: 58)
                    .background(point.hue.opacity(0.16),
                                in: RoundedRectangle(cornerRadius: DS.Radius.control,
                                                     style: .continuous))
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text(point.title)
                        .dsText(.heading22)
                        .foregroundStyle(DS.textPrimary)
                    Text(point.line)
                        .dsText(.body17)
                        .foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if index == 0 { storeStrip }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.s6)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
        .dsWidgetSurface()
    }

    /// The onboarding rain, settled: a row of the same real brands, each
    /// resting slightly uneven — the connect screen's jitter, come to rest.
    /// Illustration by identity (real icons), never a control.
    private static let stripApps = ["Photos", "Calendar", "Gmail",
                                    "GitHub", "Farcaster", "Wallet"]
    private static let stripTilt: [Double] = [-3, 2, -2, 3, -3, 2]

    private var storeStrip: some View {
        HStack(spacing: DS.Space.s2) {
            ForEach(Array(Self.stripApps.enumerated()), id: \.element) { i, name in
                BridgeIcon(name: name, size: 40)
                    .rotationEffect(.degrees(Self.stripTilt[i % Self.stripTilt.count]))
            }
        }
        .padding(.top, DS.Space.s1)
        .accessibilityHidden(true)
    }
}

private extension View {
    /// The steps' entrance — the connect screen's arrive, same curve.
    func arrive(_ on: Bool, delay: Double) -> some View {
        opacity(on ? 1 : 0)
            .offset(y: on ? 0 : 10)
            .animation(DS.Motion.standard.delay(delay), value: on)
    }
}
