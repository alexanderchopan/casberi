import SwiftUI
import SwiftData

/// The uniform "Disconnect" control for a connected bridge's own screen — the
/// source-level counterpart to the item-level swipe-to-remove each screen
/// already has (delete an address / a feed / a token). Before this, the live
/// bridges with dedicated screens (Wallet, RSS, Tokens, Mail, the handle
/// bridges) could only shed their ITEMS, never the source itself: deleting
/// every item left the seat "connected" and the next foreground re-synced it.
/// So a person could connect a source but never cleanly stop it — an honesty
/// gap. This is the same keep-or-purge choice the generic BridgeDetailScreen
/// already offers, factored into one component so every screen reads alike.
///
/// `teardown` clears the bridge's OWN stored state (addresses / feeds / handle
/// / app password). It is REQUIRED, not optional: `BridgeRefresh` keys each
/// bridge off its store (`!WalletStore.addresses.isEmpty`, `provider.connected`,
/// …), so removing only the seat would let the next foreground refresh register
/// it right back — the disconnect wouldn't stick.
struct BridgeDisconnectSection: View {
    /// The BridgeStore seat id (what `store.remove` matches).
    let bridgeID: String
    /// The bridge's display name AND its `Thing.source` — the label reads it,
    /// and the purge deletes things whose `source` equals it.
    let name: String
    /// Clears the bridge's underlying store so the seat can't re-register.
    var teardown: () -> Void

    @Environment(BridgeStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var confirm = false

    var body: some View {
        Section {
            Button(role: .destructive) { confirm = true } label: {
                Text("Disconnect \(name)")
                    .dsText(.body17)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .dsListCardRow()
            // Keep-or-purge — the same choice the generic detail screen offers,
            // so "stop this source" and "clear what it dropped in my feed" are
            // one gesture apart, not two screens apart.
            .confirmationDialog("Disconnect \(name)?", isPresented: $confirm,
                                titleVisibility: .visible) {
                Button("Keep its things") { disconnect(purge: false) }
                Button("Remove its things too", role: .destructive) { disconnect(purge: true) }
                Button("Cancel", role: .cancel) {}
            }
        } footer: {
            Text("Stops new \(name) things from landing. What already landed stays yours unless you remove it.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
    }

    private func disconnect(purge: Bool) {
        if purge {
            let all = (try? modelContext.fetch(FetchDescriptor<Thing>())) ?? []
            let doomed = all.filter { $0.source == name }
            SpotlightIndex.remove(ids: doomed.map(\.id))
            for thing in doomed { modelContext.delete(thing) }
            try? modelContext.save()
        }
        // Clear the store first so a refresh racing the dismiss can't re-add
        // the seat, then drop the seat itself.
        teardown()
        store.remove(bridgeID)
        DSHaptic.tap()
        dismiss()
    }
}
