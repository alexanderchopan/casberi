import SwiftUI
import SwiftData

/// Wise, connected (2026-09-16, prd §778) — one field, then what you hold.
///
/// Sentry's shape rather than the generic paste screen's: saving the token is
/// not the end of connecting, because every read Wise offers is per-PROFILE
/// and the profile has to be resolved before anything can be asked for. So the
/// save stores the token, asks Wise which profiles it can see, and keeps the
/// personal one — and a token Wise refuses is torn back out rather than left
/// sitting there making the seat read connected (§83).
struct WiseScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store

    @State private var tokenField = ""
    @State private var credentialVersion = 0
    @State private var connecting = false
    @State private var syncing = false
    @State private var result: BridgeProof?
    @State private var doorTapped = false

    @State private var standing: WiseStanding = .empty

    private var bridge: TokenBridge { .wise }

    private var hasKey: Bool {
        _ = credentialVersion
        return WiseAuth.configured
    }

    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?

    var body: some View {
        AccountPage(
            name: "Wise", seatID: bridge.bridgeID, source: WiseShape.source,
            state: AccountPageState.of(name: "Wise", seatID: bridge.bridgeID,
                                       connected: hasKey, store: store),
            mode: .pasteKey,
            keyed: true,
            teardown: {
                WiseAuth.clear()
                credentialVersion += 1
                load()
            },
            sheet: $sheet,
            act: {
                if hasKey { standingBlock } else { keyBlock }
            },
            more: { EmptyView() },
            keySheet: { keyBlock }
        )
        .onAppear {
            load()
            if hasKey { Task { await sync() } }
        }
    }

    // MARK: - Not connected: the token

    @ViewBuilder private var keyBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            BridgeSetupCard(steps: bridge.steps, startingAt: 2,
                            numbered: false) {
                if let url = bridge.setupURL {
                    if doorTapped {
                        DSSlabDoor(title: bridge.doorTitle,
                                   detail: bridge.doorHost,
                                   systemImage: "arrow.up.right", url: url,
                                   onOpen: { doorTapped = true })
                    } else {
                        DSSlabButton(title: bridge.doorTitle,
                                     detail: bridge.doorHost,
                                     systemImage: "arrow.up.right", url: url,
                                     onOpen: { doorTapped = true })
                    }
                }
            }
            DSSlabField(placeholder: bridge.placeholder,
                        text: $tokenField, actionLabel: "Save", secure: true,
                        action: save)
            BridgeSyncStatusRows(syncing: connecting,
                                 syncingLine: String(localized: "Checking the token…"),
                                 proof: result)
        }
    }

    // MARK: - Connected: what's held

    @ViewBuilder private var standingBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if let balances = WiseShape.balanceLine(standing) {
                Text(balances)
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
            } else {
                Text("Reading your account…")
                    .dsText(.body17).foregroundStyle(DS.textTertiary)
            }
            if let name = standing.profileName {
                Text(name)
                    .dsText(.subhead12).foregroundStyle(DS.textSecondary)
            }
            BridgeSyncStatusRows(syncing: syncing,
                                 syncingLine: String(localized: "Reading Wise…"),
                                 proof: result)
            // The ceiling, on the screen rather than only in the code. A bank
            // seat that silently omits card spending is the obvious
            // expectation of it left unmet, which §83 treats as a status
            // claim — see `WiseBridge`'s type doc for why the signed-approval
            // step is deliberately not built rather than half-built.
            DSSlabNote(text: "Card spending stays behind Wise's signed-approval step, so it isn't read here.",
                       plain: true)
        }
    }

    // MARK: - Actions

    private func load() {
        standing = WiseState.standing
    }

    private enum Outcome { case ok(WiseProfile), refused, noProfile, unreachable }

    /// One GET — `/v1/profiles`, the cheapest read Wise has and the only one
    /// that can be made before a profile is known. It is both the token check
    /// and the profile resolve, which is why there is no second request here.
    private func validate(token: String) async -> Outcome {
        let (profiles, status) = await WiseFetch.profilesWithStatus(token: token)
        guard let profiles else { return status == 0 ? .unreachable : .refused }
        guard let chosen = WiseFetch.resolveProfile(profiles) else { return .noProfile }
        return .ok(chosen)
    }

    private func save() {
        let token = tokenField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            result = .failed(String(localized: "Paste the API token from your Wise settings."))
            return
        }
        connecting = true
        result = nil
        // Stored BEFORE the check, App Store Connect's and AWS's reason: the
        // check IS a real authenticated request, so there is nothing to check
        // with until the token is in the vault. Torn back out on failure.
        TokenVault.set(token, for: WiseAuth.tokenVaultKey)

        Task {
            let outcome = await validate(token: token)
            connecting = false
            switch outcome {
            case .ok(let profile):
                WiseAuth.setProfile(id: profile.id, name: profile.name)
                tokenField = ""
                credentialVersion += 1
                // One shape for one event (§608): the profile's name is the
                // detail, not a second sentence.
                result = .connected(profile.name)
                DSHaptic.success()
                WiseWatch.registerBridge(store: store)
                load()
                await sync()
            case .noProfile:
                undo(String(localized: "Wise accepted the token but showed no profile on it."))
            case .refused:
                undo(String(localized: "Wise refused that token. Check it hasn't expired, and that you copied the whole thing."))
            case .unreachable:
                undo(String(localized: "Couldn't reach Wise — check your connection."))
            }
        }
    }

    private func undo(_ message: String) {
        WiseAuth.clear()
        credentialVersion += 1
        result = .failed(message)
    }

    private func sync() async {
        guard !syncing, hasKey else { return }
        syncing = true
        defer { syncing = false }
        let added = await WiseIngest.refresh(context: modelContext)
        load()
        WiseWatch.registerBridge(store: store)
        if let added {
            result = added > 0 ? .landed(added) : bridge.emptyReadNote.map(BridgeProof.says) ?? .upToDate
        } else {
            result = .failed(WiseIngest.lastPassFailure
                             ?? String(localized: "Couldn't reach Wise — check your connection."))
        }
    }
}
