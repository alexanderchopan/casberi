import SwiftUI

/// "How it works" (2026-07-11) — the one persistent place that explains the
/// model, for a new person after the retiring coach lines are gone. Re-ruled
/// 2026-07-16: the evergreen abstractions ("Keep tabs", "Make it yours") left
/// a real tester not knowing what to do — now it teaches the ONE loop that
/// matters, as three numbered steps: connect → one feed → ask. Still no
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
/// door forward opens (the arc: apps rain down → the three steps → the
/// catalog where those apps live); from Settings there is no rain and the
/// plain Done remains.
/// Naming (user, 2026-07-16): user-facing copy never says "store" for this
/// surface — it's "the catalog" ("store" reads as a place you pay).
/// Text literals auto-localize (LocalizedStringKey).
struct HowItWorksSheet: View {
    /// Set by the onboarding tail; nil from Settings, where the toolbar Done
    /// is the exit and there is no rain. Non-nil means "this is someone's first
    /// run", which is what gates the rain, the CTA, and the fork below.
    ///
    /// The CTA used to be "Browse the catalog" and land in a wall of ~40 apps
    /// (prd §217, 2026-07-25), then "Try it" landing on the fork. It is
    /// **"Try the demo"** now and it lands in a furnished app.
    ///
    /// The reasoning that moved it (2026-08-07): every previous CTA handed
    /// someone a DECISION as their first act — which of forty apps, or which
    /// of three sources — and each of those decisions costs something real (a
    /// permission, an address, a handle) at the exact moment the person still
    /// does not know what the app is. The demo costs nothing and answers that
    /// question directly, so it is the only honest first tap. The fork is not
    /// deleted, it MOVED: leaving the demo lands on it (`HomeRoute.startHere`),
    /// where "which of your own sources?" is a question the person now has.
    ///
    /// The secondary link below the CTA is the other half of that ruling —
    /// someone who already knows they want this must not be made to sit
    /// through a demo first. Primary/secondary rather than two equal buttons,
    /// because the fork's own "pick-one, not do-any" grammar applies here too.
    ///
    /// A non-nil node is where to land after the cover lifts; nil means the
    /// feed, which is right whenever the tap already produced something to see.
    var onStart: ((HomeRoute.Node?) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var enteringDemo = false
    @State private var arrived = false
    /// False = the rain waits above the screen · true = it has fallen through.
    @State private var rainFell = false
    /// True once the last tile is past the bottom — the overlay unmounts, so
    /// 31 offscreen icon views don't stay composited under the cover forever.
    @State private var rainDone = false
    /// Pushes the fork. Kept as local navigation inside this sheet's own stack
    /// so the greeting stays on the back chevron — a first run should be
    /// reversible.
    @State private var showStart = false

    private struct Point: Identifiable {
        let glyph: String
        let hue: Color
        let title: LocalizedStringKey
        let line: LocalizedStringKey
        var id: String { glyph }
    }

    // Three numbered steps (user, 2026-07-20, prd §134 — down from four when
    // the app changed under them): a new person must leave knowing exactly
    // (1) that connecting apps — in the catalog, top left — fills the feed
    // by itself, (2) that it is ONE feed the source chips narrow, (3) that
    // the agent's ask bar answers questions about anything they've saved.
    // The old separate "Open the catalog" step folded into step 1: the
    // catalog is WHERE you connect, not its own act. Step 1 wears the REAL
    // Apps-door glyph (TopDoors' square.grid.2x2) so they recognize it in
    // the shell later; step 3 wears the agent bar's sparkles the same way.
    // (History: step 3 was "Pin your favorites" until prd §131 retired
    // pinning on 2026-07-20; the "+ button" wording died when the FAB became
    // the agent's "Ask your things" bar in the same redesign.)
    // The titles carry no "1." prefix — the giant numeral IS the number.
    private let points: [Point] = [
        Point(glyph: "square.grid.2x2.fill", hue: .blue,
              title: "Connect your apps",
              line: "Everything you connect lands here on its own — the catalog is top left."),
        Point(glyph: "line.3.horizontal.decrease.circle.fill", hue: .pink,
              title: "One feed, or one app",
              line: "Narrow it to one app with the chips up top."),
        // Wears the agent bar's own seat — the ask bar sits at the bottom of
        // every feed, the same reason step 1 wears the catalog's grid.
        Point(glyph: "sparkles", hue: .purple,
              title: "Ask anything",
              line: "Ask the bar at the bottom about anything you've saved."),
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
                                      "Tokens", "Venice", "Cal.com",
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
                BridgeIcon(name: name, size: DS.Mark.hero)
                    .rotationEffect(.degrees(rainFell ? tilt * 3.4 : tilt * 0.5))
                    .position(x: x + Self.jitter[(i + 3) % Self.jitter.count],
                              y: rainFell ? geo.size.height + 140 : -120)
                    // The base delay clears the cover's own presentation —
                    // start the rain while the cover is still fading in and
                    // half the fall is spent invisible (measured 2026-07-16).
                    // Reduce Motion (2026-07-21): no fall. The tiles snap to
                    // their off-screen resting place, so the curtain simply
                    // never plays — nothing is lost, because the rain is pure
                    // transition (it ends below the screen either way) and
                    // step 1's settled strip says the same thing standing still.
                    .animation(reduceMotion ? nil
                                            : .easeIn(duration: 0.75)
                                                .delay(0.7 + Double(i) * 0.055),
                               value: rainFell)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        // 31 brand tiles with no informational role — VoiceOver would read the
        // whole catalog aloud before reaching the first step.
        .accessibilityHidden(true)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    // The header is the display tier — 34-heavy SF Rounded,
                    // the Home cover's voice; this is the first screen a
                    // new person meets.
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        Text("How it works")
                            .dsText(.heading34).fontWeight(.heavy)
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
                            .arrive(arrived, delay: 0.25 + Double(i) * 0.1)
                    }
                }
                .padding(.horizontal, DS.Space.s4)
                .padding(.bottom, DS.Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .dsAdaptiveContentWidth()
            .dsPageBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // From Settings the sheet keeps its plain exit; in the
                // onboarding tail the catalog CTA below is the only door
                // forward (one door, the connect screen's rule).
                if onStart == nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .tint(DS.tint)
                    }
                }
            }
            .navigationDestination(isPresented: $showStart) {
                if let onStart { StartHereScreen(onStart: onStart) }
            }
            .safeAreaInset(edge: .bottom) {
                if onStart != nil {
                    VStack(spacing: DS.Space.s1) {
                    Button {
                        DSHaptic.success()
                        enterDemo()
                    } label: {
                        Text("Try the demo")
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
                    .disabled(enteringDemo)

                    // The door for someone who already knows. Text, not a
                    // second button: two equal buttons is a decision, and the
                    // whole point of the change above is that the first tap
                    // shouldn't be one.
                    Button {
                        DSHaptic.tap()
                        showStart = true
                    } label: {
                        Text("Start with my own things")
                            .dsText(.callout15)
                            .foregroundStyle(DS.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    }
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.bottom, DS.Space.s2)
                }
            }
        }
        // The rain falls only in the onboarding tail — from Settings this is
        // a reference page, and a second rain would be a fake first time.
        .overlay { if onStart != nil && !rainDone { rain } }
        .tint(DS.tint)
        .onAppear {
            if reduceMotion { arrived = true }
            else { withAnimation(DS.Motion.standard) { arrived = true } }
            guard onStart != nil else { return }
            rainFell = true
            // Last tile: 0.7 base + 30 × 0.055 stagger + 0.75 fall ≈ 3.1s.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3.6))
                rainDone = true
            }
        }
        #if DEBUG
        // `-howItWorksCTA <s>` fires the onboarding-tail CTA after a delay.
        // It now enters the DEMO rather than pushing the fork — pass
        // `-startPick <arm>` with `-demoCTA NO` to walk the own-things route.
        .onAppear {
            let delay = UserDefaults.standard.double(forKey: "howItWorksCTA")
            guard delay > 0, onStart != nil else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                let ownThings = UserDefaults.standard.object(forKey: "demoCTA") != nil
                    && !UserDefaults.standard.bool(forKey: "demoCTA")
                NSLog("howItWorksCTA: fired (%@)", ownThings ? "fork" : "demo")
                if ownThings { showStart = true } else { enterDemo() }
            }
        }
        #endif
    }

    /// Claim the demo, then lift the cover IMMEDIATELY.
    ///
    /// The rows are deliberately not landed here — `DemoMode.begin` only marks
    /// the mode and the seats, and `RootShell` pours the rows once this cover
    /// is out of the way. Seeding first would hand someone a finished feed,
    /// which reads as a screenshot; pouring after lets them watch it fill,
    /// which is the whole argument for the demo existing.
    private func enterDemo() {
        guard !enteringDemo, let onStart else { return }
        enteringDemo = true
        DemoMode.begin(store: store)
        onStart(nil)
    }

    // MARK: - One step, writ large

    /// A full-width card: the numeral huge and bleeding off the top-right
    /// corner (clipped by the card), the glyph in a big tinted chip, the
    /// title at heading-22. The numeral duplicates the reading order for
    /// sighted users only, so it hides from accessibility.
    private func stepCard(_ index: Int, _ point: Point) -> some View {
        // The numeral is an OVERLAY, not a ZStack sibling (2026-07-25). At
        // `flourish148` it is 148pt tall, so as a sibling it set a FLOOR on
        // every card's height — invisible while the cards were tall, but the
        // moment the glyph moved beside the words (below) cards 2 and 3 had
        // less content than the numeral and got padded out with ~200pt of dead
        // space each. An overlay sizes to its parent and never expands it, so
        // the numeral can stay huge while each card hugs its own words.
        contentStack(index, point)
            .overlay(alignment: .topTrailing) {
                Text(verbatim: "\(index + 1)")
                    .dsText(.flourish148)
                    .foregroundStyle(point.hue.opacity(0.16))
                    .offset(x: DS.Space.s3, y: -DS.Space.s8 - DS.Space.s3)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
            .dsWidgetSurface()
    }

    /// The card's words and glyph — split out so the numeral above can overlay
    /// it without either one sizing the other.
    private func contentStack(_ index: Int, _ point: Point) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
                // Glyph BESIDE the words, not stacked above them (2026-07-25).
                // Stacked, three cards plus the header ran ~200pt past the fold
                // on a 17 Pro — step 3's title sat behind the CTA and its line
                // ran off the bottom (user: "user doesn't have to scroll to see
                // all the content"). Going horizontal reclaims the glyph's own
                // height on every card. Type is UNTOUCHED: §206 raised the
                // reading scale on purpose, and shrinking it back here to win
                // space would undo a ruling to fix a layout problem.
                HStack(alignment: .top, spacing: DS.Space.s3) {
                    Image(systemName: point.glyph)
                        .dsGlyph(23)
                        .foregroundStyle(point.hue)
                        .frame(width: 50, height: 50)
                        .background(point.hue.opacity(0.16),
                                    in: RoundedRectangle(cornerRadius: DS.Radius.control,
                                                         style: .continuous))
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        Text(point.title)
                            .dsText(.heading22)
                            .foregroundStyle(DS.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(point.line)
                            .dsText(.body17)
                            .foregroundStyle(DS.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Clears the giant numeral in the corner — without this the
                    // title's last word collides with it on the narrower column.
                    .padding(.trailing, DS.Space.s6)
                }
                if index == 0 { catalogStrip }
            }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.s4)
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
                BridgeIcon(name: name, size: DS.Mark.list)
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
        modifier(ArriveEntrance(on: on, delay: delay))
    }
}

/// A ViewModifier rather than a bare `View` extension so it can read the
/// environment: under Reduce Motion the rise is dropped and the section is
/// simply present (no fade-from-offset, which is the part that reads as
/// movement).
private struct ArriveEntrance: ViewModifier {
    let on: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(on || reduceMotion ? 1 : 0)
            .offset(y: on || reduceMotion ? 0 : 10)
            .animation(reduceMotion ? nil : DS.Motion.standard.delay(delay), value: on)
    }
}
