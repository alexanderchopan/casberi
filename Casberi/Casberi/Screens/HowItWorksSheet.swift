import SwiftUI

/// "How it works" (2026-07-11) — the one persistent place that explains the
/// model, for a new person after the retiring coach lines are gone. Re-ruled
/// 2026-07-16: the evergreen abstractions ("Keep tabs", "Make it yours") left
/// a real tester not knowing what to do — now it teaches the ONE loop that
/// matters, as four numbered steps: open the catalog → connect → pin → ask. Still no
/// gesture-by-gesture manual; it names the catalog's place and glyph because
/// that door is the whole game. Reached from the Settings tile to revisit any
/// time, and wired into the onboarding tail so a new person meets it once.
///
/// Redesigned 2026-07-16 (user: "more visually stunning, large proportions"):
/// each step is a full-width card wearing its numeral GIANT — SF Rounded
/// heavy, bleeding off the card's top-right corner — with a big glyph chip
/// and the title at the heading-22 tier. The numeral is information (the
/// sequence), not decoration; its hue is the step's identity, same as the
/// glyph chip it echoes. Step 1 carries a settled strip of real app icons,
/// slightly uneven like the onboarding rain — the same brands, come to
/// rest. Cards arrive staggered, the old connect screen's entrance.
///
/// Re-ruled 2026-07-16 (user): the connect screen DIED — this page IS
/// onboarding now, one screen. Its rain moved here: in the onboarding tail
/// the full curated set of app tiles falls down the screen in front of the
/// steps and passes off the bottom — a curtain of everything that can land,
/// while step 1's strip sits below as the rain come to rest. Connecting
/// happens where it always really happened: in the catalog, which the one
/// door forward opens (the arc: apps rain down → the four steps → the
/// catalog where those apps live); from Settings there is no rain and the
/// plain Done remains.
/// Naming (user, 2026-07-16): user-facing copy never says "store" for this
/// surface — it's "the catalog" ("store" reads as a place you pay).
/// Text literals auto-localize (LocalizedStringKey).
struct HowItWorksSheet: View {
    /// Set by the onboarding tail: the CTA that dismisses onboarding INTO    /// the catalog. Nil from Settings — the toolbar Done is the exit there.
    var onOpenCatalog: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var arrived = false
    /// False = the rain waits above the screen · true = it has fallen through.
    @State private var rainFell = false
    /// True once the last tile is past the bottom — the overlay unmounts, so
    /// 31 offscreen icon views don't stay composited under the cover forever.
    @State private var rainDone = false

    private struct Point: Identifiable {
        let glyph: String
        let hue: Color
        let title: LocalizedStringKey
        let line: LocalizedStringKey
        var id: String { glyph }
    }

    // Four numbered steps (ruling 2026-07-16, replacing the four abstract
    // beats): a new person must leave knowing exactly (1) where the catalog is,
    // (2) that connecting fills the feed by itself, (3) what pinning is FOR,
    // (4) that the composer answers questions about what they've saved.
    // Step 1 wears the REAL Apps-door glyph (TopDoors' square.grid.2x2) so
    // they recognize it in the shell later. Step 3's line closes the loop
    // explicitly — "the feed always has everything" — because "keep in sight"
    // phrasing read as if unpinned things vanish (user, 2026-07-16).
    // The titles carry no "1." prefix — the giant numeral IS the number.
    private let points: [Point] = [
        Point(glyph: "square.grid.2x2.fill", hue: .blue,
              title: "Open the catalog",
              line: "Top right of your feed. Apps, people, wallets, stocks — everything you can add lives there."),
        Point(glyph: "checkmark.circle.fill", hue: .green,
              title: "Connect things",
              line: "Everything you connect lands in your feed, automatically."),
        Point(glyph: "pin.fill", hue: .pink,
              title: "Pin your favorites",
              line: "Home is built from what you pin. The feed always has everything."),
        // Wears the composer FAB's real glyph (a plain plus), same reason
        // step 1 wears the catalog's grid.
        Point(glyph: "plus", hue: .purple,
              title: "Ask",
              line: "Tap the + button and ask questions about anything you've saved."),
    ]

    // MARK: - The onboarding rain (moved here 2026-07-16 when the connect
    // screen died). A hand-curated subset of the catalog — every name MUST
    // resolve to a real BridgeCatalog offer (catalog-sync.sh checks this
    // array by name). The last six are Apple's bridges as symbol tiles
    // (their icons are legally unbundlable).
    private static let marqueeApps = ["Wallet", "Farcaster", "Gmail", "GitHub",
                                      "Claude", "GeckoTerminal", "Strava", "Bluesky",
                                      "Shopify", "Notion", "Reddit",
                                      "YouTube", "Todoist", "RSS", "ChatGPT",
                                      "Gemini", "Linear", "Raindrop", "Readwise",
                                      "Tokens", "Venice", "OpenClaw", "Cal.com",
                                      "Bankr", "Stocktwits",
                                      "iCloud Mail", "Apple Music", "Apple Health",
                                      "Reminders", "Calendar", "Photos"]

    /// Deterministic per-tile jitter — no Math.random in a view body; the
    /// same fall replays identically (and the screen sweep sees one design).
    private static let jitter: [CGFloat] = [-4, 3, -2, 5, -5, 2, -3, 4]

    /// The curtain: every marquee tile falls from above the screen, tumbles,
    /// and passes off the bottom — rain, not ice; nothing rests over the
    /// steps (the strip in step 1 is the rain come to rest). Gravity is an
    /// ease-IN: tiles accelerate, they don't glide. Never hit-testable.
    private var rain: some View {
        GeometryReader { geo in
            ForEach(Array(Self.marqueeApps.enumerated()), id: \.element) { i, name in
                // Golden-ratio spread — deterministic, evenly scattered
                // columns without a visible grid.
                let frac = (Double(i) * 0.381966).truncatingRemainder(dividingBy: 1)
                let x = DS.Space.s4 + CGFloat(frac) * (geo.size.width - DS.Space.s4 * 2)
                let tilt = Double(Self.jitter[i % Self.jitter.count])
                BridgeIcon(name: name, size: 64)
                    .rotationEffect(.degrees(rainFell ? tilt * 3.4 : tilt * 0.5))
                    .position(x: x + Self.jitter[(i + 3) % Self.jitter.count],
                              y: rainFell ? geo.size.height + 140 : -120)
                    // The base delay clears the cover's own presentation —
                    // start the rain while the cover is still fading in and
                    // half the fall is spent invisible (measured 2026-07-16).
                    .animation(.easeIn(duration: 0.75)
                                .delay(0.7 + Double(i) * 0.055),
                               value: rainFell)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    // The header is the display tier — 34-heavy SF Rounded,
                    // the Home cover's voice; this is the first screen a
                    // new person meets.
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
                // onboarding tail the catalog CTA below is the only door
                // forward (one door, the connect screen's rule).
                if onOpenCatalog == nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .tint(DS.tint)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let onOpenCatalog {
                    Button {
                        DSHaptic.success()
                        onOpenCatalog()
                    } label: {
                        Text("Browse the catalog")
                            .dsText(.body17)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            // Floating chrome — glass is the floating layer's
                            // law. The glass lives INSIDE the label so the
                            // Button owns the whole hit region: interactive
                            // glass (iOS 26 `.interactive()`) applied OUTSIDE a
                            // button intercepts touches for its own press
                            // deformation and intermittently eats the tap —
                            // the user saw it as "takes several taps"
                            // (2026-07-17). Matches BridgeDetailScreen's
                            // Reconnect button, the pattern that works.
                            .dsGlassProminent(tint: DS.tint, cornerRadius: DS.Radius.pill)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.bottom, DS.Space.s2)
                }
            }
        }
        // The rain falls only in the onboarding tail — from Settings this is
        // a reference page, and a second rain would be a fake first time.
        .overlay { if onOpenCatalog != nil && !rainDone { rain } }
        .tint(DS.tint)
        .onAppear {
            withAnimation(DS.Motion.standard) { arrived = true }
            guard onOpenCatalog != nil else { return }
            rainFell = true
            // Last tile: 0.7 base + 30 × 0.055 stagger + 0.75 fall ≈ 3.1s.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3.6))
                rainDone = true
            }
        }
        #if DEBUG
        // `-howItWorksCTA <s>` fires the onboarding-tail CTA after a delay —
        // the catalog landing verifies headlessly (the `-demoPick` pattern).
        .onAppear {
            let delay = UserDefaults.standard.double(forKey: "howItWorksCTA")
            guard delay > 0, let onOpenCatalog else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                NSLog("howItWorksCTA: fired")
                onOpenCatalog()
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
                if index == 0 { catalogStrip }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.s6)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
        .dsWidgetSurface()
    }

    /// The onboarding rain, settled: a row of the same real brands, each
    /// resting slightly uneven — the rain's own jitter, come to rest.
    /// Illustration by identity (real icons), never a control.
    private static let stripApps = ["Photos", "Calendar", "Gmail",
                                    "GitHub", "Farcaster", "Wallet"]
    private static let stripTilt: [Double] = [-3, 2, -2, 3, -3, 2]

    private var catalogStrip: some View {
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
    /// The steps' entrance — sections fade up in order, one curve.
    func arrive(_ on: Bool, delay: Double) -> some View {
        opacity(on ? 1 : 0)
            .offset(y: on ? 0 : 10)
            .animation(DS.Motion.standard.delay(delay), value: on)
    }
}
