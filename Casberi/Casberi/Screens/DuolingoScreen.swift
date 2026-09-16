import SwiftUI
import SwiftData

/// Duolingo's setup (prd §776). Like Spotify, TikTok and Instagram, this seat
/// does NOT use a developer API — Duolingo publishes none for a person's own
/// practice history. It signs in as the person through Duolingo's own web page
/// inside a `WKWebView` (`DuolingoLiveLoginSheet`), keeps the session cookie
/// that leaves, and reads the web app's own endpoints as them. No client id,
/// no key, no server, and the session lives only on this device.
///
/// What lands: one thing per day you practised. Read-only — it can never start
/// a lesson, spend a gem, or change anything.
struct DuolingoScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var connected = DuolingoLiveAuth.connected
    @State private var syncing = false
    @State private var checking = false
    @State private var result: BridgeProof?
    @State private var streak = 0

    /// The page's one presentation (`AccountPage.sheet`) — the login sheet
    /// rides it through `.card`, so this screen never carries a second
    /// `.sheet` of its own (the rule `FeedScreen` paid for).
    @State private var sheet: AccountPageSheet?

    var body: some View {
        AccountPage(
            name: "Duolingo", seatID: "duolingo", source: "Duolingo",
            state: AccountPageState.of(name: "Duolingo", seatID: "duolingo",
                                       connected: connected, store: store),
            mode: .signIn,
            cardSheet: { _ in
                AnyView(DuolingoLiveLoginSheet(onCaptured: {
                    connected = true
                    Task { await confirm() }
                }))
            },
            teardown: { DuolingoLiveAuth.clear() },
            sheet: $sheet,
            act: {
                if connected { connectedBlock } else { connectBlock }
            },
            more: { EmptyView() },
            keySheet: { EmptyView() }
        )
        .onAppear {
            connected = DuolingoLiveAuth.connected
            // The sweep's throttle, shared: opening the page counts as the
            // ten-minute read rather than adding one.
            if connected, BridgeRefresh.dueForHeal("duolingo.live") {
                Task { await sync() }
            }
        }
    }

    @ViewBuilder private var connectBlock: some View {
        if checking {
            HStack(spacing: DS.Space.s2) {
                DSSpinner()
                Text("Reading your Duolingo…")
                    .dsText(.body17).foregroundStyle(DS.textTertiary)
            }
            .padding(.vertical, DS.Space.s1)
        } else {
            DSSlabButton(title: "Connect Duolingo",
                         systemImage: "person.badge.key",
                         action: { DSHaptic.tap(); result = nil; sheet = .card(id: "duolingoLive") })
        }
        BridgeSyncStatusRows(syncing: syncing,
                             syncingLine: String(localized: "Reading your Duolingo…"),
                             proof: result)
    }

    @ViewBuilder private var connectedBlock: some View {
        HStack(spacing: DS.Space.s3) {
            Image(systemName: "flame.fill")
                .dsGlyph(.body, weight: .medium)
                .foregroundStyle(DS.tint)
            Text(signedInLine)
                .dsText(.body17).foregroundStyle(DS.textPrimary)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        BridgeSyncStatusRows(syncing: syncing || checking,
                             syncingLine: String(localized: "Reading your Duolingo…"),
                             proof: result,
                             retry: { Task { await sync() } })
        DSSlabNote(text: "Every day you practise lands in your feed.", plain: true)
    }

    /// The streak is a FACT the profile read already returned, so it is said
    /// where it is true and nowhere else — never computed from the landed
    /// rows, which hold only a fortnight.
    private var signedInLine: String {
        let who = DuolingoLiveAuth.who
        switch (who, streak > 0) {
        case (let who?, true): return String(localized: "\(who) — \(streak) day streak")
        case (let who?, false): return String(localized: "Signed in as \(who)")
        case (nil, true): return String(localized: "Signed in — \(streak) day streak")
        case (nil, false): return String(localized: "Signed in")
        }
    }

    /// What this seat can do, said once — the catalogue reads it on connect
    /// and on every later sync.
    private static let canLines = ["Reads the days you practised, with your own sign-in.",
                                   "Read-only — never starts a lesson or changes anything."]

    private func register(proof: String) {
        store.registerConnected(id: "duolingo", name: "Duolingo", proof: proof,
                                can: Self.canLines)
    }

    /// The sign-in landed. Prove the session actually reads something before
    /// claiming it, then sync — Spotify's §703 lesson: the seat is registered
    /// the moment the SESSION is proven, not at the end of a first sync that
    /// can legitimately land nothing (a fortnight with no practice in it).
    private func confirm() async {
        checking = true
        result = nil
        let (profile, failure) = await DuolingoLive.profile()
        checking = false
        connected = DuolingoLiveAuth.connected
        if let failure {
            // Only a REFUSAL is a verdict on the sign-in; everything else is
            // Duolingo having a bad minute, and throwing the credential away
            // for one costs the person the whole web sign-in again (§711).
            if case .refused = failure {
                DuolingoLiveAuth.clear()
                connected = false
                result = .failed(String(localized: "Duolingo didn't accept that sign-in — tap Connect to try again."))
            } else {
                register(proof: String(localized: "Signed in"))
                result = .says(String(localized: "Signed in — couldn't reach Duolingo just now, it'll retry on its own."))
            }
            return
        }
        streak = profile?.streak ?? 0
        DSHaptic.success()
        register(proof: String(localized: "Signed in"))
        await sync()
    }

    private func sync() async {
        guard !syncing else { return }
        syncing = true
        let added = await DuolingoLive.refresh(context: modelContext)
        syncing = false
        connected = DuolingoLiveAuth.connected
        guard let added else {
            switch DuolingoLive.lastFailure {
            case .some(.throttled):
                result = .says(String(localized: "Duolingo is busy right now — your days will arrive shortly."))
            case .some(.refused):
                result = .failed(String(localized: "Duolingo signed this app out — tap Connect to sign in again."))
            default:
                result = .failed(String(localized: "Couldn't reach Duolingo — try again in a moment."))
            }
            return
        }
        result = added > 0 ? .landed(added) : .upToDate
        register(proof: added > 0
                 ? String(localized: "\(added) new")
                 : String(localized: "Synced just now"))
    }
}
