import SwiftUI
import SwiftData

/// Ethrex Privacy, on the account page — chain 8141, the third ethrex devnet
/// (prd §593).
///
/// **ON `AccountPage` SINCE §639 (2026-09-06)**, with its three siblings. What
/// differs between the four devnet seats is the data: the mark, the measured
/// examples and the claim each makes, the sentence. `DevnetAccounts.swift`
/// carries the whole argument.
///
/// **The examples are load-bearing here in a way they are not on the siblings.**
/// This chain holds 14 type-`0x6` transactions across ~14,000 blocks, and only
/// FOUR of them reference a root. So a pasted stranger's address shows a
/// correct blank that reads exactly like a broken feature, and the honest fix
/// is to hand somebody an address that has something to show. Both below are
/// real and were read off `rpc1.privacy.ethrex.xyz` on 2026-09-04.
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
                    examples: PrivacyDevnetExample.all,
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

/// **THE TWO ADDRESSES THAT HAVE SOMETHING TO SHOW (prd §593d).**
///
/// Lifted out of `PrivacyDevnetScreen` because three surfaces need them now —
/// the account page's example rows, the send picker (which otherwise opens on
/// nothing to send TO, the dead end §83 bans wearing a picker's clothes), and
/// the ROOM'S OWN quiet state, which until §593d dead-ended somebody who
/// pasted an address of their own into "Nothing on this chain from the address
/// you watch, yet." with no next step anywhere on screen.
///
/// **Each is here for a DIFFERENT reading and both are MEASURED.** The pool
/// participant is the only one of the two whose transactions reference a root,
/// so watching it is the only way to see the Roots scope at all without waiting
/// for somebody else to use the chain. Read off `rpc1.privacy.ethrex.xyz` on
/// 2026-09-04, and re-confirmed the same day when the root storage derivation
/// was checked against live state.
enum PrivacyDevnetExample {
    static let all: [DevnetExample] = [
        DevnetExample(address: "0x062901d23f7e2d3bf9949c8a8cfd2c7a5ae3f980",
                      title: String(localized: "An address that used the pool"),
                      detail: String(localized: "One-time spend keys, and a proof")),
        DevnetExample(address: "0x248ac8584135c94469a90fbb02ba053b17f1cc60",
                      title: String(localized: "An address that sent early"),
                      detail: String(localized: "The chain's first hour")),
    ]
}
