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
///
/// **It is the ONLY disconnect on a setup screen (prd §608).** Eight screens
/// carried a hand-rolled copy — Dropbox, Files, Obsidian, Steam, Slack,
/// Twitch, the exchanges and every keyed token bridge — and the copies had
/// drifted three ways. They spelled the verb five different ways ("Disconnect",
/// "Disconnect folder", "Disconnect vault", "Remove key", "Remove token");
/// they reached into `store.bridges.removeAll` rather than `store.remove`; and
/// **not one of them offered the purge**, so on those screens the 2026-07-13
/// ruling that delete-THINGS and delete-ACCESS are two verbs was only half
/// available — every copy said "your things stay" as though that were the only
/// outcome. Restating a verb per screen is how a choice goes missing on eight
/// of them and nobody notices.
struct BridgeDisconnectSection: View {
    /// The BridgeStore seat id (what `store.remove` matches).
    let bridgeID: String
    /// The bridge's display name AND its `Thing.source` — the label reads it,
    /// and the purge deletes things whose `source` equals it.
    let name: String
    /// Clears the bridge's underlying store so the seat can't re-register.
    var teardown: () -> Void
    /// A consequence that reaches OUTSIDE this bridge, and nothing else. An
    /// exchange leaving your combined total is one; "your things stay" is not
    /// — the dialog below says that by offering the choice.
    var note: String? = nil

    @Environment(BridgeStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var confirm = false

    var body: some View {
        Section {
            Button(role: .destructive) {
                // No dialog when there is nothing to decide.
                if landedAnything() { confirm = true } else { disconnect(purge: false) }
            } label: {
                Text("Disconnect \(name)")
                    .dsText(.body17)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .dsListCardRow()
            // Keep-or-purge — the same choice the generic detail screen offers,
            // so "stop this source" and "clear what it dropped in my feed" are
            // one gesture apart, not two screens apart. The two buttons SAY the
            // consequence, which is why there is no footer restating it: a
            // sentence explaining a choice the very next tap presents is one
            // more thing to read before the same decision.
            .confirmationDialog("Disconnect \(name)?", isPresented: $confirm,
                                titleVisibility: .visible) {
                Button("Keep its things") { disconnect(purge: false) }
                Button("Remove its things too", role: .destructive) { disconnect(purge: true) }
                Button("Cancel", role: .cancel) {}
            }
        } footer: {
            if let note {
                Text(note)
                    .dsText(.callout15).foregroundStyle(DS.textTertiary)
            }
        }
    }

    /// Whether this bridge has actually dropped anything in the feed. A
    /// balance-only seat (every exchange, §484's rowless nine) lands no
    /// `Thing` at all, so offering "Remove its things too" there is a control
    /// that does nothing — the §83 ban, in a dialog. Counted at TAP time, not
    /// at render: this is a `fetchCount` over the corpus and a setup screen
    /// re-renders on every keystroke.
    private func landedAnything() -> Bool {
        var d = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == name })
        d.fetchLimit = 1
        return ((try? modelContext.fetchCount(d)) ?? 0) > 0
    }

    private func disconnect(purge: Bool) {
        if purge {
            let all = (try? modelContext.fetch(FetchDescriptor<Thing>())) ?? []
            let doomed = all.filter { $0.source == name }
            SpotlightIndex.remove(ids: doomed.map(\.id))
            for thing in doomed { modelContext.delete(thing) }
            modelContext.saveHonestly()
        }
        // Clear the store first so a refresh racing the dismiss can't re-add
        // the seat, then drop the seat itself.
        teardown()
        store.remove(bridgeID)
        DSHaptic.tap()
        dismiss()
    }
}
