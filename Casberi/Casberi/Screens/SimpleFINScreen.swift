import SwiftUI
import SwiftData

/// SimpleFIN, connected (2026-11-02, prd §1663) — one field, then the accounts
/// it reads.
///
/// Wise's shape: saving is not the end of connecting. A Setup Token is spent
/// the moment it is claimed, so the save claims it, checks the Access URL it
/// got back with one read, and keeps the URL only then — and a token the
/// bridge refuses says why in the bridge's own terms (`SimpleFINConnect`).
struct SimpleFINScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store

    @State private var tokenField = ""
    @State private var credentialVersion = 0
    @State private var connecting = false
    @State private var syncing = false
    @State private var result: BridgeProof?
    @State private var doorTapped = false

    @State private var standing: SimpleFINStanding = .empty

    private var bridge: TokenBridge { .simplefin }

    private var hasKey: Bool {
        _ = credentialVersion
        return SimpleFINAuth.configured
    }

    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?

    var body: some View {
        AccountPage(
            name: "SimpleFIN", seatID: bridge.bridgeID, source: SimpleFINShape.source,
            state: AccountPageState.of(name: "SimpleFIN", seatID: bridge.bridgeID,
                                       connected: hasKey, store: store),
            mode: .pasteKey,
            keyed: true,
            teardown: {
                SimpleFINAuth.clear()
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
                        DSSlabButton(tile: .getKey, title: bridge.doorTitle,
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
                                 syncingLine: String(localized: "Claiming the token…"),
                                 proof: result)
        }
    }

    // MARK: - Connected: the accounts

    @ViewBuilder private var standingBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if standing.accounts.isEmpty {
                Text("Reading your accounts…")
                    .dsText(.body17).foregroundStyle(DS.textTertiary)
            } else {
                ForEach(standing.accounts, id: \.id) { account in
                    HStack(spacing: DS.Space.s3) {
                        BankMark(connID: account.connID, size: DS.Face.row)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name)
                                .dsText(.body17).foregroundStyle(DS.textPrimary)
                            if let institution = account.institution {
                                Text(institution)
                                    .dsText(.subhead12).foregroundStyle(DS.textSecondary)
                            }
                        }
                    }
                }
            }
            // What the bridge said about the read, as it said it — the
            // protocol asks that these reach the person (a bank needing a
            // sign-in again is one).
            ForEach(standing.messages, id: \.self) { message in
                Text(message)
                    .dsText(.subhead12).foregroundStyle(DS.attentionInk)
            }
            BridgeSyncStatusRows(syncing: syncing,
                                 syncingLine: String(localized: "Reading SimpleFIN…"),
                                 proof: result)
        }
    }

    // MARK: - Actions

    private func load() {
        standing = SimpleFINState.standing
    }

    private func save() {
        let pasted = tokenField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pasted.isEmpty else {
            result = .failed(String(localized: "Paste the Setup Token from SimpleFIN Bridge."))
            return
        }
        connecting = true
        result = nil
        Task {
            let outcome = await SimpleFINConnect.connect(pasted)
            connecting = false
            if let sentence = SimpleFINConnect.sentence(outcome) {
                result = .failed(sentence)
                return
            }
            tokenField = ""
            credentialVersion += 1
            result = .connected(nil)
            DSHaptic.success()
            SimpleFINWatch.registerBridge(store: store)
            await sync(force: true)
        }
    }

    /// A page visit reads only when the bridge's rate allows; the first read
    /// after a connect is the one forced read.
    private func sync(force: Bool = false) async {
        guard !syncing, hasKey else { return }
        syncing = true
        defer { syncing = false }
        let added = await SimpleFINIngest.refresh(context: modelContext, force: force)
        load()
        SimpleFINWatch.registerBridge(store: store)
        // A visit inside the hour reads nothing (0), and must not draw "Up to
        // date" over the last read's failure (§83).
        if let added, added == 0, let failure = SimpleFINIngest.lastPassFailure {
            result = .failed(failure)
        } else if let added {
            result = added > 0 ? .landed(added) : .upToDate
        } else {
            result = .failed(SimpleFINIngest.lastPassFailure
                             ?? String(localized: "Couldn't reach SimpleFIN — check your connection."))
        }
    }
}
