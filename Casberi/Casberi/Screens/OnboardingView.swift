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
        // Apple Health sits out of minute zero (ruling 2026-07-07: health
        // reads as sensitive before trust exists) — it waits in the store.
        BridgeCatalog.offers.filter {
            $0.connectable && !$0.needsSetup && $0.name != "Apple Health"
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

    /// The glass (ruling 2026-07-07, supersedes the shelf rain): sixteen
    /// BIG cubes fall the full height one after another, bounce, and stack
    /// bottom-up until they fill the screen — ice filling a glass. Then the
    /// glass pours: the cubes shrink into the shelf above the CTA and the
    /// feed card arrives. Zerion and Farcaster lead the pour.
    private let marqueeApps = ["Zerion", "Farcaster", "Gmail", "GitHub",
                               "Claude", "Spotify", "Strava", "Bluesky",
                               "Telegram", "Slack", "X", "Notion", "Reddit",
                               "YouTube", "Todoist", "RSS"]
    /// 0 = above the screen · 1 = the glass fills · 2 = the shelf.
    @State private var cubePhase = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            DS.page.ignoresSafeArea()

            VStack(alignment: .leading, spacing: DS.Space.s4) {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text("Your apps, one feed.")
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(DS.textPrimary)
                    Text("All of this lands here. Start with three.")
                        .dsText(.body17)
                        .foregroundStyle(DS.textSecondary)
                }
                .padding(.horizontal, DS.Space.s4)
                .arrive(arrived, delay: 0.35)

                feedPreviewCard
                    .arrive(cubePhase >= 2, delay: 0.1)

                Spacer(minLength: 168)   // floor above the shelf + CTA stack
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
            cubePhase = 1
            // The glass is full once the last cube settles — then it pours.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                cubePhase = 2
            }
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
            Text(allConnected ? "YOUR FEED · FLOWING" : "YOUR FEED")
                .dsText(.label12).kerning(1)
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
        .background(DS.surfaceSheet,
                    in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
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
                    Text(offer.tagline)
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

    /// Where cube `i` rests in each phase — the glass stacks bottom-up in
    /// four columns of near-touching 84pt cubes; the shelf is two tight rows
    /// of 32pt above the CTA.
    private func cubeTarget(_ i: Int, in size: CGSize) -> CGPoint {
        if cubePhase >= 2 {
            let col = CGFloat(i % 8), row = CGFloat(i / 8)
            let rowWidth = 8 * 32 + 7 * DS.Space.s2
            let x = (size.width - rowWidth) / 2 + col * (32 + DS.Space.s2) + 16
            return CGPoint(x: x, y: size.height - 148 + row * 40)
        }
        let col = CGFloat(i % 4), row = CGFloat(i / 4)
        let cell = (size.width - DS.Space.s4 * 2) / 4
        let x = DS.Space.s4 + cell * col + cell / 2
            + Self.jitter[i % Self.jitter.count] * 0.8
        let y = size.height - 190 - row * (cell - 6)
            + Self.jitter[(i + 5) % Self.jitter.count]
        return CGPoint(x: x, y: y)
    }

    private var cubes: some View {
        GeometryReader { geo in
            ForEach(Array(marqueeApps.enumerated()), id: \.element) { i, name in
                let rest = cubeTarget(i, in: geo.size)
                BridgeIcon(name: name, size: 84)
                    .rotationEffect(.degrees(cubePhase == 1
                        ? Double(Self.jitter[i % Self.jitter.count]) * 0.9 : 0))
                    .scaleEffect(cubePhase >= 2 ? 32.0 / 84.0 : 1)
                    .position(x: rest.x, y: cubePhase == 0 ? -120 : rest.y)
                    .animation(cubePhase <= 1
                        ? .spring(duration: 0.85, bounce: 0.52)
                            .delay(0.1 + Double(i) * 0.11)
                        : .spring(duration: 0.7, bounce: 0.24)
                            .delay(Double(i) * 0.015),
                        value: cubePhase)
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

    private var cta: some View {
        Button {
            guard !connected.isEmpty else { return }
            DSHaptic.success()
            onContinue(connected)
        } label: {
            Text(connected.isEmpty
                 ? "Connect one to continue"
                 : (allConnected ? "See your feed" : "Continue"))
                .dsText(.body17)
                .foregroundStyle(connected.isEmpty ? DS.textTertiary : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(connected.isEmpty ? AnyShapeStyle(DS.gray200) : AnyShapeStyle(DS.tint),
                            in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(connected.isEmpty)
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
