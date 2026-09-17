import SwiftUI
import SwiftData

/// Privy's account page (prd §803c). Privy Home lists every app a person has
/// made a wallet in through Privy; this seat signs in on Privy's own page
/// (`PrivyLoginSheet`), keeps the session on this device, and reads that list.
/// What is IN each wallet is read from the chain by the Wallet seat's own
/// holdings read, not from Privy.
///
/// What lands: one row per app, dated the day its wallet was made. Read-only —
/// Privy Home's Export keys and Add funds are not here, and nothing on this
/// page can change anything at Privy.
struct PrivyScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var connected = PrivyHomeAuth.connected
    @State private var syncing = false
    @State private var result: BridgeProof?
    @State private var sheet: AccountPageSheet?

    var body: some View {
        AccountPage(
            name: "Privy", seatID: PrivyHomeFeed.seatID, source: PrivyHomeFeed.source,
            state: AccountPageState.of(name: "Privy", seatID: PrivyHomeFeed.seatID,
                                       connected: connected, store: store),
            mode: .signIn,
            cardSheet: { _ in
                AnyView(PrivyLoginSheet(onCaptured: {
                    connected = true
                    Task { await confirm() }
                }))
            },
            teardown: {
                PrivyHomeAuth.clear()
                PrivyHomeStore.shared.forget()
            },
            sheet: $sheet,
            act: {
                if connected { connectedBlock } else { connectBlock }
            },
            more: { EmptyView() },
            keySheet: { EmptyView() }
        )
        .onAppear {
            connected = PrivyHomeAuth.connected
            if connected, BridgeRefresh.dueForHeal("privy.home") {
                Task { await sync() }
            }
        }
    }

    @ViewBuilder private var connectBlock: some View {
        DSSlabButton(title: "Connect Privy",
                     systemImage: "person.badge.key",
                     action: { DSHaptic.tap(); result = nil; sheet = .card(id: "privyHome") })
        BridgeSyncStatusRows(syncing: syncing,
                             syncingLine: String(localized: "Reading your Privy apps…"),
                             proof: result)
    }

    @ViewBuilder private var connectedBlock: some View {
        HStack(spacing: DS.Space.s3) {
            Image(systemName: "square.stack.3d.up")
                .dsGlyph(.body, weight: .medium)
                .foregroundStyle(DS.tint)
            Text(signedInLine)
                .dsText(.body17).foregroundStyle(DS.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        BridgeSyncStatusRows(syncing: syncing,
                             syncingLine: String(localized: "Reading your Privy apps…"),
                             proof: result,
                             retry: { Task { await sync() } })
        DSSlabNote(text: "Every app you made a wallet in lands in your feed. Balances are read from the chain, not from Privy.",
                   plain: true)
    }

    private var signedInLine: String {
        let room = PrivyHomeStore.shared.room
        guard room.appCount > 0 else { return String(localized: "Signed in") }
        return room.fundedCount > 0
            ? String(localized: "\(room.appCount) apps · \(room.fundedCount) funded")
            : String(localized: "\(room.appCount) apps")
    }

    private static let canLines = ["Reads which apps made you a wallet, with your own sign-in.",
                                   "Read-only — can't export keys, add funds or change anything."]

    private func register(proof: String) {
        store.registerConnected(id: PrivyHomeFeed.seatID, name: "Privy", proof: proof,
                                can: Self.canLines)
    }

    /// Registered on the SESSION (§703's lesson), then synced.
    private func confirm() async {
        DSHaptic.success()
        register(proof: String(localized: "Signed in"))
        await sync()
    }

    private func sync() async {
        guard !syncing else { return }
        syncing = true
        let added = await PrivyHomeLive.refresh(context: modelContext)
        syncing = false
        connected = PrivyHomeAuth.connected
        guard let added else {
            switch PrivyHomeLive.lastFailure {
            case .some(.refused):
                result = .failed(String(localized: "Privy signed this app out — tap Connect to sign in again."))
            case .some(.throttled):
                result = .says(String(localized: "Privy is busy right now — your apps will arrive shortly."))
            case .some(.drifted):
                result = .failed(String(localized: "Privy answered in a shape Casberi doesn't read yet."))
            default:
                result = .failed(String(localized: "Couldn't reach Privy — try again in a moment."))
            }
            return
        }
        result = added > 0 ? .landed(added) : .upToDate
        register(proof: added > 0
                 ? String(localized: "\(added) new")
                 : String(localized: "Synced just now"))
    }
}
