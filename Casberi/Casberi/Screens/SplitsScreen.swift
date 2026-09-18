import SwiftUI
import SwiftData

/// Splits, connected (2026-09-18, prd §820) — one field, then what the team
/// holds.
///
/// Wise's shape rather than the generic paste screen's: saving the key is not
/// the end of connecting, because the key's SCOPE has to be read first. The
/// save asks Splits what the pasted key is (`/v1/auth/whoami`) and stores it
/// only if its scopes are Read and nothing else — a Write or Owner key is
/// never kept, because this page promises that nothing here can propose a
/// transaction, and a key that could would make that promise ours to keep
/// rather than Splits'. A refused Replace leaves the working key in place.
struct SplitsScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store

    @State private var tokenField = ""
    @State private var credentialVersion = 0
    @State private var connecting = false
    @State private var syncing = false
    @State private var result: BridgeProof?
    @State private var doorTapped = false

    @State private var standing: SplitsStanding = .empty

    private var bridge: TokenBridge { .splits }

    private var hasKey: Bool {
        _ = credentialVersion
        return SplitsAuth.configured
    }

    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?

    private var mask: String? { BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil }

    var body: some View {
        AccountPage(
            name: "Splits", seatID: bridge.bridgeID, source: SplitsShape.source,
            state: AccountPageState.of(name: "Splits", seatID: bridge.bridgeID,
                                       connected: hasKey, store: store),
            mode: .pasteKey,
            keyed: true,
            teardown: {
                SplitsAuth.clear()
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

    // MARK: - Not connected: the key

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
                                 syncingLine: String(localized: "Checking the key…"),
                                 proof: result)
        }
    }

    // MARK: - Connected: what's held

    @ViewBuilder private var standingBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if let total = standing.totalUSD {
                Text(verbatim: mask ?? PrivyHomeFeed.usd(total))
                    .dsText(.price40).monospacedDigit()
                    .foregroundStyle(DS.textPrimary)
            } else if standing.lastRead == nil {
                Text("Reading your team…")
                    .dsText(.body17).foregroundStyle(DS.textTertiary)
            }
            if let org = standing.orgName {
                Text(verbatim: org)
                    .dsText(.subhead12).foregroundStyle(DS.textSecondary)
            }
            ForEach(standing.accounts, id: \.address) { account in
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: account.name ?? WalletStore.shortAddress(account.address))
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                    Spacer(minLength: DS.Space.s2)
                    if let usd = account.usd {
                        Text(verbatim: mask ?? PrivyHomeFeed.usd(usd))
                            .dsText(.price17).monospacedDigit()
                            .foregroundStyle(DS.textPrimary)
                    }
                }
            }
            if let failed = standing.failedReads, failed > 0 {
                Text(failed == 1 ? "1 account couldn't be read, so it's not in the total"
                                 : "\(failed) accounts couldn't be read, so they're not in the total")
                    .dsText(.subhead12).foregroundStyle(DS.attention)
            }
            if standing.unread > 0 {
                Text("\(standing.unread) more accounts not read")
                    .dsText(.subhead12).foregroundStyle(DS.textSecondary)
            }
            // §780b: a body this seat could not read is said, with its field
            // names, rather than reported as synced.
            ForEach(standing.unreadable, id: \.self) { line in
                Text(verbatim: line)
                    .dsText(.subhead12).foregroundStyle(DS.attention)
            }
            BridgeSyncStatusRows(syncing: syncing,
                                 syncingLine: String(localized: "Reading Splits…"),
                                 proof: result)
        }
    }

    // MARK: - Actions

    private func load() {
        standing = SplitsState.standing
    }

    private enum Outcome { case ok(String?), notReadOnly, refused, unreachable }

    /// One GET — `/v1/auth/whoami`, which is both the key check and the
    /// scope read, so there is no second request here.
    private func validate(token: String) async -> Outcome {
        let (who, status) = await SplitsFetch.whoami(token: token)
        guard let who else { return status == 0 ? .unreachable : .refused }
        guard SplitsShape.isReadOnly(who.scopes) else { return .notReadOnly }
        return .ok(who.orgName)
    }

    private func save() {
        let token = tokenField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            result = .failed(String(localized: "Paste the API key from your Splits settings."))
            return
        }
        connecting = true
        result = nil
        // Validated BEFORE it is stored: a Replace that fails must leave the
        // key that was working in place, never disconnect the seat.
        let previous = SplitsAuth.storedToken

        Task {
            let outcome = await validate(token: token)
            connecting = false
            switch outcome {
            case .ok(let org):
                // A different key may be a different team: nothing read with
                // the old one carries over.
                if previous != token { SplitsState.clear() }
                TokenVault.set(token, for: SplitsAuth.tokenVaultKey)
                tokenField = ""
                credentialVersion += 1
                result = .connected(org)
                DSHaptic.success()
                SplitsWatch.registerBridge(store: store)
                load()
                await sync()
            case .notReadOnly:
                undo(String(localized: "That key can do more than read. Create one with the Read scope only."))
            case .refused:
                undo(String(localized: "Splits refused that key. Check you copied the whole thing."))
            case .unreachable:
                undo(String(localized: "Couldn't reach Splits — check your connection."))
            }
        }
    }

    /// Nothing was stored, so there is nothing to tear out: a first connect
    /// stays unconnected and a Replace keeps the key that was working.
    private func undo(_ message: String) {
        result = .failed(message)
    }

    private func sync() async {
        guard !syncing, hasKey else { return }
        syncing = true
        defer { syncing = false }
        let added = await SplitsIngest.refresh(context: modelContext)
        load()
        SplitsWatch.registerBridge(store: store)
        if let added {
            result = added > 0 ? .landed(added) : bridge.emptyReadNote.map(BridgeProof.says) ?? .upToDate
        } else {
            result = .failed(SplitsIngest.lastPassFailure
                             ?? String(localized: "Couldn't reach Splits — check your connection."))
        }
    }
}
