import SwiftUI
import SwiftData

/// Ethrex Privacy, on the account page — chain 8141, the third ethrex devnet
/// (prd §593).
///
/// **ON `AccountPage` SINCE §639 (2026-09-06)**, with its three siblings. What
/// differs between the four devnet seats is the data: the mark and the
/// sentence. `DevnetAccounts.swift` carries the whole argument. The measured
/// example addresses are deleted (prd §990, user: "we don't want that").
///
/// **THE SEAT MAKES A KEY AND SENDS SINCE §593c, AND THE ACTS ARE NOT HERE.**
/// The acts live in the ROOM, on Home, because §594's line is that an act which
/// WRITES to the chain moves to Home and an act that changes WHAT YOU ARE
/// LOOKING AT stays with the view. Watching an address changes the roster, not
/// the chain, so it stays here.
struct PrivacyDevnetScreen: View {
    @Environment(BridgeStore.self) private var store
    @Environment(\.modelContext) private var modelContext

    @Bindable private var watch = PrivacyDevnetWatch.shared

    /// The read that follows a watch, reported here (prd §618).
    @State private var reader = DevnetReader(name: PrivacyDevnetIdentity.source) {
        guard !DemoMode.isActive else { return true }
        let before = PrivacyDevnetLiveState.shared.readAt
        await PrivacyDevnetLiveState.shared.refresh()
        return PrivacyDevnetLiveState.shared.readAt != before
    }

    /// The page's one bar (§639 amendment).
    @State private var typed = ""
    @State private var sheet: AccountPageSheet?
    @State private var roster = DevnetRosterReader(seatID: PrivacyDevnetIdentity.seatID,
                                                   source: PrivacyDevnetIdentity.source)

    private static let mark = DS.brandHue(for: PrivacyDevnetIdentity.source) ?? DS.tint

    private var connected: Bool { watch.connected }

    var body: some View {
        AccountPage(
            name: PrivacyDevnetIdentity.source, seatID: PrivacyDevnetIdentity.seatID,
            source: PrivacyDevnetIdentity.source,
            state: AccountPageState.of(name: PrivacyDevnetIdentity.source,
                                       seatID: PrivacyDevnetIdentity.seatID,
                                       connected: connected, store: store),
            mode: .noAccount,
            rows: roster.rows,
            query: typed,
            onRemoveRow: unwatch,
            teardown: { PrivacyDevnetBridge.disconnect(store: store) },
            sheet: $sheet,
            act: {
                DevnetAccountsAct(
                    watch: watch,
                    tint: Self.mark,
                    peek: { await DevnetPeek.read($0, via: PrivacyDevnetRPC.call(method:params:)) },
                    reader: reader,
                    register: { PrivacyDevnetBridge.registerBridge(store: store) },
                    typed: $typed,
                    onWatched: { _ in readRows() })
            },
            more: {
                // The seat's one §315 gray sentence, and it is spent on the
                // thing somebody would otherwise assume. "Privacy devnet"
                // invites the reading that watching here is private; it is
                // not, and the chain itself is the reason rather than any
                // choice of ours.
                DSSlabNote(text: String(localized: "Addresses on this chain are public — watching one is a read, and it hides nothing about you. Test ETH has no value, and the network may be reset without notice."), plain: true)
                DevnetExplorerRow(url: PrivacyDevnetIdentity.explorer, plain: true)
            },
            keySheet: { EmptyView() }
        )
        .onAppear { readRows() }
        .onChange(of: watch.addresses) { _, _ in readRows() }
    }

    private func readRows() {
        Task {
            await roster.refresh(watch: watch, context: modelContext,
                                 peek: { await DevnetPeek.read($0, via: PrivacyDevnetRPC.call(method:params:)) })
        }
    }

    /// ONE verb, "Remove" (§639), replacing `DevnetWatchingSection`'s own.
    private func unwatch(_ address: String) {
        watch.remove(address)
        roster.forget(address)
        PrivacyDevnetBridge.registerBridge(store: store)
        readRows()
    }

    // NO ROUTE ON A WATCH (prd §618) — the Activity row is the way on, and the
    // read reports here.
}

