import SwiftUI
import SwiftData

/// Steam's setup — a sign-in on Steam's own store page since prd §1584, the
/// key and profile fields folded under it for anyone who has a key, then the
/// games that landed.
struct SteamScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var keyField = ""
    @State private var profileField = ""
    @State private var syncing = false
    @State private var result: BridgeProof?
    /// The key path, folded under the sign-in (prd §1584).
    @State private var manualPathOpen = false

    /// The credentials door, open (prd §186).

    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?

    var body: some View {
        AccountPage(
            name: "Steam", seatID: "steam", source: "Steam",
            state: AccountPageState.of(name: "Steam", seatID: "steam",
                                       connected: SteamBridge.connected, store: store),
            mode: .signIn,
            keyed: true,
            cardSheet: { id in
                guard id == "webSignIn" else { return AnyView(EmptyView()) }
                return AnyView(WebSessionSignInSheet(seat: .steam, onDone: {
                    Task { await sync(justConnected: true) }
                }))
            },
            tiles: SteamBridge.connected ? [] : [
                AccountTile(id: "signIn", label: String(localized: "Sign in"),
                            glyph: "person.badge.key", act: startSignIn),
            ],
            signIn: startSignIn,
            teardown: { SteamBridge.disconnect() },
            sheet: $sheet,
            act: {
                if SteamBridge.connected {
                    // Whose library this is reading, and what the read is
                    // doing. The two fields are the "Your key" sheet now.
                    profileLine
                    BridgeSyncStatusRows(syncing: syncing,
                                         syncingLine: String(localized: "Reading your games…"),
                                         proof: result)
                } else {
                    if !manualPathOpen {
                        BridgeSyncStatusRows(syncing: syncing,
                                             syncingLine: String(localized: "Reading your games…"),
                                             proof: result)
                    }
                    manualPathToggle
                    if manualPathOpen { setupBlock }
                }
            },
            more: { EmptyView() },
            keySheet: { setupBlock }
        )
        .onAppear {
            profileField = SteamBridge.profile
            if SteamBridge.connected { Task { await sync() } }
        }
    }

    /// Whose library. Steam stores what the person typed, so this page can say
    /// whose games it reads rather than only that a key exists.
    @ViewBuilder private var profileLine: some View {
        if !SteamBridge.profile.isEmpty {
            HStack(spacing: DS.Space.s3) {
                BridgeIcon(name: "Steam", size: DS.Mark.list, circular: false)
                Text(SteamBridge.profile)
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
    }


    /// What's left once "Open steamcommunity.com/dev/apikey and sign in."
    /// became the button that does it.
    ///
    /// "Paste it with your profile name below" went (audit, 2026-07-31) — it
    /// re-typed the two fields under it, placeheld `Profile name or SteamID`
    /// and `Web API key`, which is §220's Kraken finding. The requirement it
    /// was carrying is a real one nothing else on the screen states, so that
    /// half stayed.
    ///
    /// The first line is the one that stops people at the door: Valve gives no
    /// key to a "limited" account (under $5 spent in its store), and a library
    /// of free games is still limited (beta feedback, 2026-09-18: "I DO HAVE
    /// GAMES THERE"). The games page is sign-in walled, so there is no keyless
    /// way round it (measured 2026-09-18: 302 to /login).
    private var steps: [String] = [
        "Steam needs $5 spent — free games don’t count",
        "Any domain works — casberi.app is fine.",
        "Your profile must be public.",
    ]

    @ViewBuilder private var setupBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            // Verb over address, the 2026-08-14 anatomy.
            // Unnumbered — the door did step one (ruling 2026-08-14).
            BridgeSetupCard(steps: steps, numbered: false) {
                DSSlabButton(tile: .getKey, title: "Get your API key",
                             detail: "steamcommunity.com",
                             systemImage: "arrow.up.right",
                             url: URL(string: "https://steamcommunity.com/dev/apikey"))
            }
            // Two inputs, ONE act — so only the second slab wears the
            // verb, and it stays inert until both are filled.
            DSSlabField(placeholder: String(localized: "Profile name or SteamID"),
                        text: $profileField, actionLabel: "", action: connect)
            DSSlabField(placeholder: String(localized: "Web API key"),
                        text: $keyField,
                        actionLabel: SteamBridge.connected ? "Update" : "Connect",
                        secure: true, isArmed: canConnect, action: connect)
            BridgeSyncStatusRows(syncing: syncing, syncingLine: String(localized: "Reading your games…"),
                                 proof: result)
        }
    }


    private func startSignIn() {
        DSHaptic.tap()
        result = nil
        sheet = .card(id: "webSignIn")
    }

    /// The key by hand, one quiet row under the sign-in — TokenSetupScreen's
    /// fold, for the same reason: two full-weight ways in made a wall.
    private var manualPathToggle: some View {
        Button {
            withAnimation(DS.Motion.standard) { manualPathOpen.toggle() }
        } label: {
            HStack(spacing: DS.Space.s2) {
                Text("Prefer a key by hand?")
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
                Image(systemName: "chevron.down")
                    .dsGlyph(.caption)
                    .foregroundStyle(DS.textTertiary)
                    .rotationEffect(.degrees(manualPathOpen ? 180 : 0))
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
    }

    private var canConnect: Bool {
        !profileField.trimmingCharacters(in: .whitespaces).isEmpty
            && !keyField.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func connect() {
        guard canConnect else { return }
        // A key by hand replaces a sign-in: the session reads first.
        WebSession.clear(.steam)
        SteamBridge.profile = profileField.trimmingCharacters(in: .whitespaces)
        TokenVault.set(keyField.trimmingCharacters(in: .whitespaces),
                       for: SteamBridge.tokenKey)
        keyField = ""
        DSHaptic.tap()
        Task { await sync(justConnected: true) }
    }

    private func sync(justConnected: Bool = false) async {
        guard !syncing else { return }
        syncing = true
        let added = await SteamIngest.refresh(context: modelContext)
        syncing = false
        guard let added else {
            // A fresh key that fails doesn't stay (same rule as the token
            // bridges) — no dead connection retrying on every foreground.
            if justConnected, WebSession.signedIn(.steam) {
                // A sign-in whose first read failed takes only its session.
                WebSession.clear(.steam)
                result = .failed(String(localized: "Steam signed you in, but didn't hand over your games — try again in a moment."))
                return
            }
            if justConnected { SteamBridge.disconnect() }
            result = .failed(String(localized: "Couldn't reach Steam — check the key, the profile name, and that the profile is public."))
            return
        }
        result = .landed(added, noun: "games")
        let proof = added > 0
            ? String(localized: "\(added) games in")
            : String(localized: "Synced just now")
        if store.registerConnected(id: "steam", name: "Steam", proof: proof,
                                   can: WebSession.signedIn(.steam)
                                    ? ["Reads what you've played, with your own sign-in.",
                                       "Read-only — never buys, chats or changes anything."]
                                    : ["Reads what you've played.",
                                       "Read-only — public profile data."]) {
            DSHaptic.success()
        }
    }
}
