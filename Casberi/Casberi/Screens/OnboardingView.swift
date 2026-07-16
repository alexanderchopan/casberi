import SwiftUI
import SwiftData

/// Onboarding, screen 1 — Connect (re-ruled 2026-07-07): connections are
/// REAL. A mini store of the three bridges that work today — Photos,
/// Calendar, Reminders — each Connect runs the real flow (the permission
/// dialog IS the in-context ask). Sample things seed only for the showcase
/// apps that can't connect yet; real sources bring real things from minute
/// one, so the dissolve never has to touch them.
struct OnboardingView: View {
    /// The shell's bridge store — passed in because presented covers don't
    /// inherit `.environment` values applied inside RootShell's body.
    let store: BridgeStore
    /// Called with the connected set — the caller seeds showcase samples
    /// and reveals the shell in demo mode.
    var onContinue: (Set<String>) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var connected: Set<String> = []
    @State private var arrived = false
    /// The cover can't see the shell's toast — this screen speaks for itself.
    @State private var toast: String?

    /// The mini store: exactly the bridges that connect for real today.
    private var offers: [BridgeCatalog.Offer] {
        // Three bridges sit out of minute zero — each reads as "this app wants
        // my sensitive data" before any trust exists. Apple Health (ruling
        // 2026-07-07: health is sensitive before trust). Contacts (ruling
        // 2026-07-12: an address-book ask on onboarding reads as harvesting
        // your info). Strava rides the same Health permission (2026-07-14),
        // so it waits with Health. All wait in the store.
        let heldBack: Set<String> = ["Apple Health", "Contacts", "Strava"]
        return BridgeCatalog.offers.filter {
            $0.connectable && !$0.needsSetup && !heldBack.contains($0.name)
        }
    }

    /// What a filled slot says — plain, true, present tense.
    private func fillLine(_ name: String) -> String {
        switch name {
        case "Photos":       "Your screenshots, flowing in"
        case "Calendar":     "Your events are in"
        case "Reminders":    "Your lists are in"
        case "Apple Health": "Your workouts are in"
        default:             "\(name) is in"
        }
    }

    /// The glass (ruling 2026-07-07, amended same day: no pour): sixteen
    /// BIG cubes fall the full height one after another, bounce, and stack
    /// bottom-up until they fill the BOTTOM HALF of the screen — ice filling
    /// a glass — and they STAY there, full size, while the feed card lives
    /// in the top half. Wallet and Farcaster lead the fall.
    /// Every connectable catalog app joins the pile (showcase-only apps like
    /// Spotify and X sit it out). The first 24 carry brand art or a brand
    /// squircle; the LAST SIX are Apple's bridges as their symbol tiles (their icons
    /// are legally unbundlable) — they land last, as the pile's TOP ROW,
    /// right under the three Connect rows they're kin to.
    private let marqueeApps = ["Wallet", "Farcaster", "Gmail", "GitHub",
                               "Claude", "GeckoTerminal", "Strava", "Bluesky",
                               "Shopify", "Notion", "Reddit",
                               "YouTube", "Todoist", "RSS", "ChatGPT",
                               "Gemini", "Linear", "Raindrop", "Readwise",
                               "Tokens", "Venice", "OpenClaw", "Cal.com",
                               "Bankr", "Stocktwits",
                               "iCloud Mail", "Apple Music", "Apple Health",
                               "Reminders", "Calendar", "Photos"]
    // 25 non-Apple cubes (a full 5×5 grid) then the six Apple tiles as the
    // top row — Stocktwits (2026-07-15) completed the bottom grid's last row.
    // The grid is FULL: a 26th cube lands on the Apple row (cubeTarget puts
    // index 25 at row 5), so a new tile SWAPS one out rather than appending.
    // Bankr took Calendly's cube (2026-07-16) — Cal.com already carries
    // scheduling here, and the pile is a curated subset, never the catalog.
    private static let appleRowStart = 25
    /// False = above the screen · true = settled in the glass.
    @State private var cubesLanded = false

    var body: some View {
        ZStack(alignment: .bottom) {
            DS.page.ignoresSafeArea()

            VStack(alignment: .leading, spacing: DS.Space.s4) {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text("Your apps, one feed.")
                        // SF Rounded — the display tier (2026-07-09), matching
                        // the Home cover title and the heading ramp.
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(DS.textPrimary)
                        // First-run copy must never truncate — a longer
                        // translation (ja) wrapped instead of ellipsizing
                        // mid-word without this (design audit fix).
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("All of this lands here. Start with three.")
                        .dsText(.body17)
                        .foregroundStyle(DS.textSecondary)
                }
                .padding(.horizontal, DS.Space.s4)
                .arrive(arrived, delay: 0.35)

                feedPreviewCard
                    .arrive(arrived, delay: 0.5)

                // The pile owns the bottom as a self-scaling overlay, so this
                // column just pins its content to the top and lets the rest
                // breathe. A fixed 430pt MINIMUM used to force the column taller
                // than an iPhone SE screen (667pt) — shoving the heading off the
                // top and crowding the CTA against the pile. minLength 0 lets
                // short screens use only the height they have; tall phones are
                // unchanged (their spacer was already well over 430).
                Spacer(minLength: 0)
            }
            .padding(.top, DS.Space.s4)

            cubes

            VStack(spacing: DS.Space.s2) {
                if let toast {
                    Text(toast)
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textPrimary)
                        .padding(.horizontal, DS.Space.s4)
                        .frame(height: 32)
                        .background(DS.surfaceSheet, in: Capsule(style: .continuous))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                cta
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.bottom, DS.Space.s4)
        }
        .dsColorScheme()
        .onAppear {
            withAnimation(DS.Motion.standard) { arrived = true }
            cubesLanded = true
        }
        #if DEBUG
        // `-demoPick "Photos,Calendar"` marks and continues (no real
        // connects) — screenshots of screen 2 without a hand on the sim.
        .onAppear {
            if let names = UserDefaults.standard.string(forKey: "demoPick") {
                let set = Set(names.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                })
                guard !set.isEmpty else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    onContinue(set)
                }
            }
        }
        #endif
    }

    // MARK: - H3: the feed-preview card (2026-07-07) — the card IS the
    // store: four slots, each fills IN PLACE the moment its app connects.
    // The hero is a reward the person builds with their own taps.

    private var allConnected: Bool { connected.count == offers.count }

    private var feedPreviewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(allConnected ? "Your feed · flowing" : "Your feed")
                .dsText(.label12)
                .foregroundStyle(allConnected ? DS.confirm : DS.textSecondary)
                .padding(.horizontal, DS.Space.s4)
                .padding(.top, DS.Space.s3)
                .padding(.bottom, DS.Space.s1)
                .contentTransition(.opacity)
            ForEach(Array(offers.enumerated()), id: \.element.name) { i, offer in
                slotRow(offer)

            }
        }
        .padding(.bottom, DS.Space.s1)
        .dsWidgetSurface()
        .padding(.horizontal, DS.Space.s4)
    }

    /// One slot: waiting, it's a quiet ask with a Connect capsule; connected,
    /// it springs into a filled feed row. Height holds — rhythm law.
    private func slotRow(_ offer: BridgeCatalog.Offer) -> some View {
        let isOn = connected.contains(offer.name)
        return HStack(spacing: DS.Space.s3) {
            BridgeIcon(name: offer.name, size: 36)
                .saturation(isOn ? 1 : 0)
                .opacity(isOn ? 1 : 0.45)
                .scaleEffect(isOn ? 1 : 0.92)
            VStack(alignment: .leading, spacing: 1) {
                if isOn {
                    Text(fillLine(offer.name))
                        .dsText(.body17).fontWeight(.semibold)
                        .foregroundStyle(DS.textPrimary)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Text("just now")
                        .dsText(.subhead13)
                        .foregroundStyle(DS.confirm)
                        .transition(.opacity)
                } else {
                    Text(offer.name)
                        .dsText(.body17).fontWeight(.semibold)
                        .foregroundStyle(DS.textPrimary)
                    Text(LocalizedStringKey(offer.tagline))
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            Spacer(minLength: 0)
            if isOn {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(DS.confirm)
                    .transition(.scale.combined(with: .opacity))
            } else {
                connectCapsule(offer)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s2 + 2)
    }

    // MARK: - T2: the marquee (the rain lands FIRST, across the top)

    /// Deterministic per-icon jitter — the landed row sits slightly uneven,
    /// like things that actually fell.
    private static let jitter: [CGFloat] = [-4, 3, -2, 5, -5, 2, -3, 4]

    /// Where cube `i` rests: five columns stacking bottom-up, rows and
    /// columns overlapping like real ice. The six Apple tiles land last as
    /// a tighter six-across TOP ROW, touching the card they're kin to.
    /// Row step and base tightened (2026-07-13 polish): at 62pt rows from a
    /// −138 base the pile's TOP ROW crossed into the connect card and sat on
    /// the Apple Music row's Connect button — the ice must fill the glass,
    /// never the drink. The pile still packs bottom-up, just denser.
    /// The row step is tuned for tall phones. On short screens (iPhone SE,
    /// 667pt) the fixed 52pt step let the pile's TOP ROW rise into the connect
    /// card once the layout stopped overflowing — the "ice must fill the glass,
    /// never the drink" line above. Compress the step proportionally so the pile
    /// tucks under the card. 812pt (iPhone 12/13 mini) and up keep the full 52pt
    /// step, so every current non-SE phone renders the moment unchanged; the
    /// base (bottom margin) stays fixed so the pile still bottoms out the same.
    private static func rowStep(for height: CGFloat) -> CGFloat {
        52 * min(1, max(0.6, (height - 200) / 612))
    }

    private func cubeTarget(_ i: Int, in size: CGSize) -> CGPoint {
        let step = Self.rowStep(for: size.height)
        if i >= Self.appleRowStart {
            let col = CGFloat(i - Self.appleRowStart)
            let cell = (size.width - DS.Space.s4 * 2) / 6
            let x = DS.Space.s4 + cell * col + cell / 2
                + Self.jitter[i % Self.jitter.count] * 0.8
            let y = size.height - 104 - 5 * step
                + Self.jitter[(i + 5) % Self.jitter.count]
            return CGPoint(x: x, y: y)
        }
        let col = CGFloat(i % 5), row = CGFloat(i / 5)
        let cell = (size.width - DS.Space.s4 * 2) / 5
        let x = DS.Space.s4 + cell * col + cell / 2
            + Self.jitter[i % Self.jitter.count] * 0.8
        let y = size.height - 104 - row * step
            + Self.jitter[(i + 5) % Self.jitter.count]
        return CGPoint(x: x, y: y)
    }

    private var cubes: some View {
        GeometryReader { geo in
            ForEach(Array(marqueeApps.enumerated()), id: \.element) { i, name in
                let rest = cubeTarget(i, in: geo.size)
                BridgeIcon(name: name, size: 74)
                    .rotationEffect(.degrees(cubesLanded
                        ? Double(Self.jitter[i % Self.jitter.count]) * 0.9 : 0))
                    .position(x: rest.x, y: cubesLanded ? rest.y : -120)
                    .animation(.spring(duration: 0.85, bounce: 0.52)
                                .delay(0.1 + Double(i) * 0.075),
                               value: cubesLanded)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Connect runs the REAL flow — the iOS permission ask fires right here,
    /// in context, one app at a time.
    private func connectCapsule(_ offer: BridgeCatalog.Offer,
                                onWhiteField: Bool = false) -> some View {
        let isOn = connected.contains(offer.name)
        return Button {
            guard !isOn else { return }
            DSHaptic.tap()
            // The slot fills only when the permission ask actually lands —
            // a denied dialog must not paint a green check (honesty rule).
            BridgeConnect.connect(offer, store: store, context: modelContext) { ok in
                guard ok else {
                    flash("\(offer.name) needs permission — try again anytime")
                    return
                }
                withAnimation(.spring(duration: 0.4, bounce: 0.45)) {
                    _ = connected.insert(offer.name)
                }
                DSHaptic.success()
                flash("\(offer.name) connected")
            }
        } label: {
            HStack(spacing: DS.Space.s1) {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
                Text(isOn ? "Connected" : "Connect")
                    .dsText(.label12)
            }
            .foregroundStyle(isOn ? .black : (onWhiteField ? DS.tint : .white))
            .padding(.horizontal, DS.Space.s4)
            .frame(minHeight: 32)
            .background(isOn ? AnyShapeStyle(DS.confirm)
                             : (onWhiteField ? AnyShapeStyle(.white) : AnyShapeStyle(DS.tint)),
                        in: Capsule(style: .continuous))
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(isOn ? "\(offer.name) connected" : "Connect \(offer.name)")
    }

    /// The screen's own toast — shown above the CTA for a beat.
    private func flash(_ text: String) {
        withAnimation(DS.Motion.standard) { toast = text }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1600))
            withAnimation(DS.Motion.standard) {
                if toast == text { toast = nil }
            }
        }
    }

    // MARK: - CTA (the only onboarding chrome on the page)

    /// The one door forward — ALWAYS tappable (ruling 2026-07-15, revised):
    /// the earlier design gated this button until a bridge connected and hid
    /// the escape in a faint "Not now" link. But each Connect runs a real iOS
    /// permission ask, and iOS shows that dialog only ONCE — so anyone who
    /// declined (or just wouldn't grant at minute zero) hit a dead grey
    /// "Connect one to continue" with the only way out a whisper-grey link on
    /// the ice pile, and read it as "I can't get past onboarding." Now the
    /// primary never dead-ends: empty it reads "Skip for now" and advances
    /// with nothing connected; the moment anything connects it turns to the
    /// blue "Continue" / "See your feed". The grey-vs-blue tint carries the
    /// connect nudge; the button is never disabled, so nobody is stranded.
    private var cta: some View {
        Button {
            DSHaptic.success()
            onContinue(connected)
        } label: {
            Text(connected.isEmpty
                 ? "Skip for now"
                 : (allConnected ? "See your feed" : "Continue"))
                .dsText(.body17)
                .foregroundStyle(connected.isEmpty ? DS.textSecondary : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
        }
        .buttonStyle(.plain)
        // Floating chrome over the icon pile — it wears glass (the law's
        // floating layer), the falling brands refracting through it.
        .dsGlassProminent(tint: connected.isEmpty ? DS.gray200 : DS.tint,
                          cornerRadius: DS.Radius.pill)
    }
}

private extension View {
    /// The Connect screen's one entrance: sections fade up in order.
    func arrive(_ on: Bool, delay: Double) -> some View {
        opacity(on ? 1 : 0)
            .offset(y: on ? 0 : 10)
            .animation(DS.Motion.standard.delay(delay), value: on)
    }
}
