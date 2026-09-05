import SwiftUI
import SwiftData

/// THE WATCHED FIVE, AFTER THE PINNED SECTION (2026-08-29, prd §511).
///
/// **What this file replaces.** `WalletRosterSection` drew the five addresses
/// this app reads as a block above the address book — §461 lifted it out of
/// `WalletScreen`, §466 moved it into the book, and 2026-08-27 flattened its
/// raised card because "the screen read as a wallet widget with an address book
/// underneath rather than as an address book". §511 finishes that same move by
/// deleting the block: the five are ordinary rows in the A–Z list now, found
/// through the `Watching` chip, and this file is the two things the block was
/// doing that a row cannot do for itself.
///
/// **Why the block had to go**, in the user's own words: *"if a user can only
/// watch five addresses, why do we even have a watched section in the address
/// book … those addresses can just be in the address book like the rest are and
/// a user can filter."* Three facts back it. The five ALREADY have a permanent
/// home — the face scope rail above every feed — so the block was the third
/// surface for one set. The block made the book two lists, which is the shape
/// §461 exists to prevent and which it accidentally rebuilt one level down. And
/// the bug that started this session was a pure consequence of the split:
/// unwatching DEMOTED a row from the top block into the list below, silently,
/// which is indistinguishable from a delete that failed — so you removed twice,
/// with the same word, to get rid of one address.
///
/// **§461 survives it.** Its ruling is that watching is not an attribute any
/// screen showing people can toggle, and a filter is a property of the LIST
/// while a star is a control on the ROW. No star returns; `AddressBookRow`'s
/// `onToggleWatch` is still passed by nobody, and the harness still says so.

/// Stopping a watch, in ONE place.
///
/// It has two call sites — the book row's swipe and menu, and the address
/// card's overflow menu — and it must never have two implementations, because
/// it does three things a second copy would get subtly differently: it prunes
/// the wallet's landed rows out of the corpus, it decides whether the BOOK
/// entry leaves with the watch, and it owes the person a sentence and an undo
/// for both.
@MainActor
enum WalletUnwatch {

    /// Stop reading an address, and say what happened to it.
    ///
    /// **The fold** (`AddressBookShape.unwatchKeepsEntry`). `WalletStore.add`
    /// files EVERY watched wallet in the book, and for a bare pasted address it
    /// files it under a placeholder it minted itself — so for that wallet the
    /// book entry is not a second fact, it is the residue of the watch. The
    /// residue leaves with it; anything somebody authored stays.
    ///
    /// **The sentence.** Under §511's merged list an unwatch no longer moves
    /// the row anywhere, which removes the demotion this toast originally
    /// existed to explain — but it still deletes landed rows, and in the folded
    /// case it deletes the entry too, so a destructive act with no report and no
    /// way back is not one this app performs.
    ///
    /// **The undo** restores the watch, and through `WalletStore.add`'s own
    /// book write the placeholder entry if we took it — identically, because
    /// the fold only ever takes an entry whose whole content was that
    /// placeholder. It cannot restore the rows `FollowPrune` deleted, so it
    /// re-reads the chain, which is where they came from. Nothing here claims
    /// otherwise.
    static func perform(_ entry: AddressBook.Entry,
                        context: ModelContext,
                        chrome: ShellChrome) {
        let wallet = WalletStore.shared
        guard let i = wallet.addresses.firstIndex(where: {
            wallet.scopeMatches(entry.address, scope: $0.address)
        }) else { return }
        let watch = wallet.addresses[i]
        let gone = watch.address
        let label = watch.label
        let name = entry.name
        // Read BEFORE the removal — after it, the entry's own fields are still
        // there, but reading them first keeps the decision a pure function of
        // what was true when the gesture happened.
        let keepsEntry = AddressBookShape.unwatchKeepsEntry(
            isPlaceholderName: WalletStore.isAutoName(entry.name, for: entry.address),
            groups: entry.groups,
            note: entry.note,
            provenance: entry.provenance,
            networks: entry.networks)
        DSHaptic.tap()
        withAnimation(DS.Motion.standard) {
            wallet.remove(at: IndexSet(integer: i))
            if !keepsEntry { AddressBook.shared.remove(entry.address) }
        }
        FollowPrune.removeWallet(address: gone,
                                 stillWatched: wallet.addresses.map(\.address),
                                 context: context)
        chrome.flash(keepsEntry
                     ? String(localized: "Stopped watching · \(name) is still in your book")
                     : String(localized: "Stopped watching \(name)"),
                     action: .init(label: String(localized: "Undo")) {
                         undo(gone, label: label, context: context)
                     },
                     seconds: 4)
    }

    /// Puts the watch back, and goes and gets what it pruned.
    static func undo(_ address: String, label: String, context: ModelContext) {
        guard WalletStore.shared.add(address, label: label) else { return }
        DSHaptic.success()
        Task { _ = await WalletIngest.refresh(context: context) }
    }
}

/// Whether the chain read is in flight, and what it said — the only part of the
/// old roster block that is not a row.
///
/// It stays a SECTION of the book rather than becoming a row of it: it is a
/// status about the whole roster, it appears and disappears, and a lettered
/// list has nowhere to file a thing with no name. It sits above the letters for
/// the same reason `FeedRoomHealth`'s line sits above a room's head — it says
/// whether what follows is complete.
struct WalletWatchSyncSection: View {
    @Bindable private var wallet = WalletStore.shared
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store

    @State private var syncing = false
    @State private var result: BridgeProof?

    var body: some View {
        Section {
            if syncing || result != nil {
                BridgeSyncStatusRows(syncing: syncing,
                                     syncingLine: String(localized: "Reading onchain activity…"),
                                     proof: result)
                    .listRowInsets(EdgeInsets(top: 0, leading: DS.Space.s4,
                                              bottom: 0, trailing: DS.Space.s4))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .onAppear {
            if !wallet.addresses.isEmpty { sync() }
        }
    }

    /// Moved from `WalletRosterSection`, unchanged.
    private func sync() {
        guard !syncing else { return }
        syncing = true
        Task {
            let added = await WalletIngest.refresh(context: modelContext)
            let totals = await WalletIngest.topHoldingsByWallet()
            syncing = false
            guard let added else {
                result = .failed(String(localized: "Couldn't reach the chain — check your connection."))
                return
            }
            let nothingFound = added == 0 && totals.allSatisfy { $0.totalUSD < 1 }
            if added > 0 {
                result = .says(String(localized: "\(added) new"))
            } else if nothingFound && wallet.addresses.count == 1 {
                result = .says(String(localized: "No activity found on your chains yet — double-check the address, or give it a moment."))
            } else {
                result = .connected(String(localized: "watching for activity."))
            }
            let proof = added > 0
                ? String(localized: "\(added) new")
                : String(localized: "Synced just now")
            if store.registerConnected(id: "wallet", name: "Wallet", proof: proof,
                                       can: ["Reads your wallet's activity.",
                                             "Read-only — never trades or moves funds."]) {
                DSHaptic.success()
            }
        }
    }
}
