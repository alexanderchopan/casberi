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
        BridgeCatalog.offers.filter { $0.connectable && !$0.needsSetup }
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

    /// The marquee (T2 ruling 2026-07-07): the catalog RAINS ACROSS THE TOP
    /// before anything else — the drop acts out the headline. Zerion and
    /// Farcaster lead; the row runs off both edges to say "more".
    private let marqueeApps = ["Zerion", "Farcaster", "Gmail", "GitHub",
                               "Claude", "Spotify", "Strava", "Bluesky",
                               "Telegram", "Slack", "X", "Notion", "Reddit",
                               "YouTube", "Todoist", "RSS"]
    @State private var rained = false

    var body: some View {
        ZStack(alignment: .bottom) {
            DS.page.ignoresSafeArea()

            VStack(alignment: .leading, spacing: DS.Space.s4) {
                marquee
                    .padding(.top, DS.Space.s2)

                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text("Your apps, one feed.")
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(DS.textPrimary)
                    Text("All of this lands here. Start with four.")
                        .dsText(.body17)
                        .foregroundStyle(DS.textSecondary)
                }
                .padding(.horizontal, DS.Space.s4)
                .arrive(arrived, delay: 0.35)

                feedPreviewCard
                    .arrive(arrived, delay: 0.5)

                Spacer(minLength: 84)
            }

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

    private var marquee: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s2) {
                ForEach(Array(marqueeApps.enumerated()), id: \.element) { i, name in
                    BridgeIcon(name: name, size: 38)
                        .opacity(rained ? 1 : 0)
                        .offset(y: rained
                                ? Self.jitter[i % Self.jitter.count]
                                : -140)
                        .animation(.spring(duration: 0.5, bounce: 0.45)
                                    .delay(0.05 + Double(i) * 0.045),
                                   value: rained)
                }
            }
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, 6)   // room for the jitter
        }
        .scrollClipDisabled()   // the fall crosses the top edge
        .onAppear { rained = true }
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
