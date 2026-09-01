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
    /// **"Try a demo"** now and it lands in a furnished app.
    ///
    /// The article is INDEFINITE (user, 2026-08-29). "The demo" presupposes a
    /// specific artifact the reader is assumed to know about, on the first
    /// screen they have ever seen — the one place nothing can be assumed. The
    /// ambiguity this does NOT resolve is the word "demo" itself, which can
    /// still be read as a canned tour somebody has to sit through rather than
    /// as sample data they can look around in; that was weighed and the
    /// shorter label kept, so if this CTA ever measures as under-tapped, the
    /// lever to try is naming the OUTCOME ("Try it with sample data") rather
    /// than adjusting the article again.
    ///
    /// The reasoning that moved it (2026-08-07): every previous CTA handed
    /// someone a DECISION as their first act — which of forty apps, or which
    /// of three sources — and each of those decisions costs something real (a
    /// permission, an address, a handle) at the exact moment the person still
    /// does not know what the app is. The demo costs nothing and answers that
    /// question directly, so it is the only honest first tap. The fork is not
    /// deleted outright (2026-08-31): the catalogue is its answer,
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
    /// The Casberi mark's own arrival, after the rain has fallen past.
    @State private var markLanded = false
    /// Pushes the fork. Kept as local navigation inside this sheet's own stack
    /// so the greeting stays on the back chevron — a first run should be
    /// reversible.

    private struct Point: Identifiable {
        let glyph: String
        let hue: Color
        let title: LocalizedStringKey
        let line: LocalizedStringKey
        var id: String { glyph }
    }

    // Three numbered steps (user, 2026-07-20, prd §134 — down from four when
    // the app changed under them): a new person must leave knowing exactly
    // (1) that connecting apps — in the catalog — fills the feed by itself,
    // (2) that it is ONE feed the source chips narrow, (3) that the agent's
    // ask bar answers questions about anything they've saved.
    // The old separate "Open the catalog" step folded into step 1: the
    // catalog is WHERE you connect, not its own act. Step 1 wears the REAL
    // Apps-door glyph (TopDoors' square.grid.2x2) so they recognize it in
    // the shell later; step 3 wears the agent bar's sparkles the same way.
    // (History: step 3 was "Pin your favorites" until prd §131 retired
    // pinning on 2026-07-20; the "+ button" wording died when the FAB became
    // the agent's "Ask your things" bar in the same redesign.)
    //
    // **"top left" DELETED from step 1 (2026-08-24)** — the catalogue door
    // moved out of the chip strip's head and into the sources tray, so that
    // sentence sent a brand-new person to an empty corner. Directions in copy
    // are the most perishable thing an onboarding screen can hold: they go
    // stale silently, they go stale on the ONE screen whose whole job is to be
    // believed, and nothing in a build or a screen sweep can see it. So the
    // step names the DOOR (its glyph is right there beside the words, and it
    // is the same mark the shell draws) and never the corner. Steps 2 and 3
    // already worked this way — "the chips up top", "the bar at the bottom" —
    // and both survive because a strip and a bar are regions, not coordinates.
    // The titles carry no "1." prefix — the giant numeral IS the number.
    // TEXT ONLY (user, 2026-08-31: "hyper minimal and bold … it still feels
    // like a lot to read"). Every glyph, strip and subtitle this block ever
    // carried is deleted — three bold lines are the whole explanation, and
    // each one names the region it teaches in its own words.
    private let points: [Point] = [
        Point(glyph: "square.grid.2x2.fill", hue: .blue,
              title: "Connect your apps",
              line: ""),
        Point(glyph: "line.3.horizontal.decrease.circle.fill", hue: .pink,
              title: "One feed, or many",
              line: ""),
        Point(glyph: "sparkles", hue: .purple,
              title: "Ask your agents",
              line: ""),
    ]

    // MARK: - The onboarding rain (moved here 2026-07-16 when the connect
    // screen died). A hand-curated subset of the catalog — every name MUST
    // resolve to a real BridgeCatalog offer (catalog-sync.sh checks this
    // array by name). The last six are Apple's bridges as symbol tiles
    // (their icons are legally unbundlable).
    /// EVERY CONNECTABLE SEAT, derived (user, 2026-08-31: "why not have all
    /// 80+ or so that are in the app?"). There was no good reason — 249 brand
    /// marks are bundled against 103 connectable offers, so the only limit was
    /// that this was a HAND LIST of thirty.
    ///
    /// Deriving it is also what retires the drift: `catalog-sync.sh` had to
    /// check every hand-written name still resolved to a real offer, because a
    /// renamed or retired seat left a dead tile here. A list read from the
    /// catalog cannot go stale.
    ///
    /// Apple's own seats keep their SF-symbol fallback — those icons are not
    /// legally bundlable — which `BridgeIcon` already handles per name.
    private static var marqueeApps: [String] {
        let all = BridgeCatalog.offers.filter(\.connectable).map(\.name)
        // The landers fall LAST, so "the last six" is a curated set rather
        // than whatever sits at the end of the catalog array (user,
        // 2026-08-31: "what if the last six are weird ones"). It would have
        // been — that order is authoring order, and a seat added tomorrow
        // would silently take a landing slot from Photos.
        //
        // These six are the ones somebody recognises without reading: they
        // are what stays on screen, so they have to say "your everyday things
        // land here" at a glance. `catalog-sync.sh` checks each still names a
        // real offer.
        return all.filter { !landers.contains($0) } + landers.filter { all.contains($0) }
    }

    private static let landers = ["Photos", "Calendar", "Gmail",
                                  "GitHub", "Notion", "Wallet"]

    /// Deterministic per-tile jitter — no Math.random in a view body; the
    /// same fall replays identically (and the screen sweep sees one design).
    /// How many of the falling tiles stop on the shelf above the doors.
    private static var landingCount: Int { landers.count }
    private static let landingStride: CGFloat = DS.Mark.tile + DS.Space.s2
    /// Where the rain comes to rest: below the copy, splitting the distance
    /// between the sentence and the doors so neither side holds a void. A
    /// fraction, not a fixed inset, so the balance holds on every phone.
    private static let landingFraction: CGFloat = 0.60
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
                // THE LAST SIX LAND (2026-08-31). Everything else falls past
                // the bottom — that is what makes it a curtain — and the tail
                // of the same fall stops on the shelf above the two doors.
                // They ARRIVE BY FALLING: it is one motion, not a row fading
                // in over a rain still in flight, which is what the deleted
                // `settledPile` was and why it never read as landing.
                let lands = i >= Self.marqueeApps.count - Self.landingCount
                let slot = i - (Self.marqueeApps.count - Self.landingCount)
                // Centred row: each slot is offset from the middle by half
                // the run's width. The `* 0.5` used to sit on the STRIDE,
                // which spaced them at half a tile and piled them up.
                let restX = geo.size.width / 2
                    + (CGFloat(slot) - CGFloat(Self.landingCount - 1) / 2) * Self.landingStride
                let restY = geo.size.height * Self.landingFraction
                BridgeIcon(name: name, size: lands ? DS.Mark.tile : DS.Mark.hero)
                    .rotationEffect(.degrees(rainFell ? tilt * (lands ? 1.6 : 3.4) : tilt * 0.5))
                    .position(x: rainFell && lands ? restX
                                                   : x + Self.jitter[(i + 3) % Self.jitter.count],
                              y: rainFell ? (lands ? restY : geo.size.height + 140) : -120)
                    // The base delay clears the cover's own presentation —
                    // start the rain while the cover is still fading in and
                    // half the fall is spent invisible (measured 2026-07-16).
                    // Reduce Motion (2026-07-21): no fall. The tiles snap to
                    // their off-screen resting place, so the curtain simply
                    // never plays — nothing is lost, because the rain is pure
                    // transition (it ends below the screen either way) and
                    // step 1's settled strip says the same thing standing still.
                    .animation(reduceMotion ? nil
                                            : (lands
                                               ? .spring(duration: 0.62, bounce: 0.28)
                                                   .delay(0.7 + Double(i) * 0.022)
                                               : .easeIn(duration: 0.75)
                                                   .delay(0.7 + Double(i) * 0.022)),
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
                        // "What you can do", not "How it works" (user,
                        // 2026-08-29: "how do we not say 'how it works' twice
                        // … maybe 'what you can do'"). Two reasons, and the
                        // second is the one that generalises.
                        //
                        // (1) It matches what it heads. All three steps are
                        // phrased as things YOU DO — "Connect your apps",
                        // "Ask anything" — so the old label named a mechanism
                        // over content that reads as actions.
                        // (2) It stopped being a heading and became a LABEL.
                        // Once the steps are one block, the header sits
                        // directly on top of the thing it names and the two
                        // say the same word; the Settings row that opens this
                        // sheet said it a third time. One name for the screen,
                        // used in both places (`AccountScreen`'s row moved with
                        // it), rather than a heading echoing its own section.
                        //
                        // The small tension, recorded rather than argued away:
                        // §528 made these read as one SEQUENCE and this labels
                        // them as a list of capabilities. The numerals still
                        // carry the order, so it is a tension and not a
                        // contradiction — and the falling-icon rain gives this
                        // screen an identity the fork can never be mistaken for
                        // in its first seconds regardless.
                        // The LABEL is quiet and the STATEMENTS are the
                        // screen (user, 2026-08-31: "shouldn't they be spread
                        // out more? larger?"). Three 24pt lines in a slab used
                        // a tenth of the screen and read as a list; §532's own
                        // move — extreme proportions, fewer sizes further
                        // apart — runs the hierarchy the other way: a caption
                        // names the screen, and each capability stands at the
                        // head rung with the screen's height divided between
                        // them. The slab is gone; a box around everything on
                        // an otherwise empty screen was holding the lines
                        // together when the whole screen is what holds them.
                        // ONE SCREEN, TWO DOORS (user, 2026-08-31: "we
                        // need to do better and have ONE screen somehow",
                        // then "the fork is already there" — its three arms
                        // are what the CATALOGUE offers, so they belong there
                        // as discover cards and not on a screen of their own).
                        //
                        // What went: the three numbered steps, then the three
                        // bold statements that replaced them, then the fork
                        // this pushed to. Each rewrite made the screen tidier
                        // and none made it SHORTER — it explained the app to
                        // somebody who had not seen it yet, which is work the
                        // demo does in ten seconds and prose never does.
                        //
                        // What stays is the rain (the best thing here, and the
                        // only explanation that needs no reading), one
                        // sentence, and the two things a person can actually
                        // do next.
                        // THE MARK LANDS LAST, ABOVE THE TEXT (user,
                        // 2026-08-31: "the octopus lands last above the text
                        // and fills that void too"). Two voids, two arrivals:
                        // the rain settles UNDER the copy and fills the middle,
                        // this fills the top. It waits for the curtain to
                        // clear so it reads as the one that stayed.
                        CasberiMark(size: 120)
                            .scaleEffect(markLanded ? 1 : 0.7)
                            .opacity(markLanded ? 1 : 0)
                            .animation(reduceMotion ? nil
                                                    : .spring(duration: 0.55, bounce: 0.3)
                                                        .delay(2.4),
                                       value: markLanded)
                            .padding(.bottom, DS.Space.s4)
                            .accessibilityHidden(true)
                        Text("Everything you need, in one place.")
                            .dsText(.heading34)
                            .foregroundStyle(DS.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        // Says what "one feed, or many" never did (user: "isn't
                        // clear that you can view as one feed, or separately as
                        // many"). The agent is named in the same breath rather
                        // than taking a line of its own.
                        Text("Read it all together, or one app at a time. Ask your agents about any of it.")
                            .dsText(.body17)
                            .foregroundStyle(DS.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, DS.Space.s2)
                    }
                    .padding(.top, DS.Space.s2)
                    .arrive(arrived, delay: 0.1)
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
            }
            .safeAreaInset(edge: .bottom) {
                if onStart != nil {
                    VStack(spacing: DS.Space.s1) {
                    Button {
                        DSHaptic.success()
                        enterDemo()
                    } label: {
                        Text("Try a demo")
                            .dsText(.body17)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
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
                    // Straight to the CATALOGUE (2026-08-31). It used to push
                    // a fork asking which of three things to start with —
                    // files, a wallet, or all the apps — and all three are
                    // what the catalogue already lists, so the question was a
                    // screen standing in front of its own answer.
                    Button {
                        DSHaptic.tap()
                        onStart?(.apps)
                    } label: {
                        Text("Connect my apps")
                            .dsText(.callout15)
                            .foregroundStyle(DS.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    }
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.bottom, DS.Space.s2)
                }
            }
        // The rain falls only in the onboarding tail — from Settings this is
        // a reference page, and a second rain would be a fake first time.
        // The rain is no longer torn down: its last six tiles ARE the
        // shelf above the doors, so removing it would remove them.
        .overlay { if onStart != nil { rain } }
        .tint(DS.tint)
        .onAppear {
            if reduceMotion { arrived = true }
            else { withAnimation(DS.Motion.standard) { arrived = true } }
            guard onStart != nil else { return }
            rainFell = true
            markLanded = true
            // Last tile: 0.7 base + 103 × 0.022 stagger + 0.75 fall ≈ 3.7s.
            // The stagger tightened with the count so the curtain still runs
            // about three seconds rather than six.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4.2))
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
                NSLog("howItWorksCTA: fired (%@)", ownThings ? "catalog" : "demo")
                if ownThings { onStart?(.apps) } else { enterDemo() }
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
    /// One step, as a row inside the shared block (prd §528).
    ///
    /// **The giant corner numeral is GONE, and its own doc is why it could
    /// go.** It read: "The numeral is information (the sequence), not
    /// decoration" — true while the steps were three separate cards, where
    /// nothing else said they were ordered. Inside one block, top-to-bottom
    /// says it, so a 148pt numeral bleeding off each card's corner became the
    /// most decorative thing on the screen while still claiming to be
    /// information. The number survives at reading size in the leading slot,
    /// where it does the same job in a tenth of the space — and where it is
    /// also what stops this block being mistaken for the fork's answers.
    ///
    /// That deletion takes three fiddly workarounds with it: the numeral had to
    /// be an `overlay` rather than a ZStack sibling (as a sibling its 148pt set
    /// a height FLOOR on every card, padding cards 2 and 3 with ~200pt of dead
    /// space), the card needed a `clipShape` to crop the bleed, and every title
    /// carried a `.padding(.trailing, DS.Space.s6)` so its last word would not
    /// collide with the numeral. None of it is needed now.
    private func stepRow(_ index: Int, _ point: Point) -> some View {
        Text(point.title)
            .dsText(.heading22)
            .foregroundStyle(DS.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.s3)
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
