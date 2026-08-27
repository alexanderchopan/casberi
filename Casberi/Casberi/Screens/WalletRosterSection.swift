import SwiftUI
import SwiftData

/// The five addresses this app reads, as a section inside the address book
/// (prd §466, 2026-08-24) — moved WHOLE off `WalletScreen`, unchanged in
/// every rule it carries.
///
/// **Why it moved.** §461 drew the boundary — the setup screen is your five
/// wallets, the book is everyone else — and left the setup screen still
/// doing the everyday work: rename, remove, watch a second address, read the
/// sync status. §466 finishes the same move Vibenet made a few commits
/// earlier: setup is what you do ONCE (the first address, the chains, the
/// promise); the room — and now the book, for the seat that owns a roster —
/// is what you do REPEATEDLY. `WalletScreen` keeps only the first watch.
///
/// **Why it lives in the BOOK and not the feed room.** Wallet has no
/// `onOpen`-forking card the way `VibenetRoomCard` does — its feed room
/// draws a balance card, a treemap, DeFi tiles, none of which have a
/// "managing" mode to grow. The book is where a name is filed, so it is
/// also where the roster that FEEDS the book's names belongs; putting the
/// roster there costs nothing new to route to, since the book door already
/// existed on the rail and on this very section's own foot.
///
/// **Nothing about MEMBERSHIP changed.** Still five, still no star — see
/// `WalletScreen`'s own header doc for why "watched" stays membership of a
/// capped roster rather than an attribute any screen could toggle.
struct WalletRosterSection: View {
    @Bindable private var wallet = WalletStore.shared
    @Bindable private var book = AddressBook.shared
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store

    /// The connect picker route, bubbled from `WalletWatchField` up to
    /// whichever `.sheet(item:)` the host screen already owns.
    var onConnectFound: ([WalletConnectBridge.ConnectedAccount]) -> Void

    @State private var renamingID: WalletStore.WatchedAddress.ID?
    @State private var renameDraft = ""
    @State private var syncing = false
    @State private var result: String?
    @State private var resultIsError = false

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                // **THE WATCH FIELD AND ITS CONNECT ROW LEFT THIS SECTION**
                // (user ruling, 2026-08-27, on a device: *"this looks like
                // crap there should only be one address field and one connect
                // wallet app button"*).
                //
                // They were right and the duplication was structural rather
                // than accidental: this section carried a field that WATCHES
                // and a connect row, and the book below it carried a field
                // that SEARCHES-and-names and a connect row of its own — so an
                // address book showed two near-identical fields and two
                // identical buttons, four hundred points apart, differing only
                // in a verb nobody can see. One screen gets one of each; the
                // book's own omnibox is the survivor because SEARCH is the
                // thing this screen cannot do without, and the watch verb
                // moved onto the preview of the address it would watch
                // (`AddressBookScreen.addressPreview`), which is the one place
                // it can say WHICH address it is about to start reading.
                //
                // This section is now purely the list: who you watch, and
                // whether the read is in flight.
                if syncing || result != nil {
                    BridgeSyncStatusRows(syncing: syncing,
                                         syncingLine: String(localized: "Reading onchain activity…"),
                                         result: result, resultIsError: resultIsError)
                }
                ForEach(Array(watchedEntries.enumerated()), id: \.element.id) { index, entry in
                    rosterRow(entry, row: index)
                }
            }
        } header: {
            if !watchedEntries.isEmpty || wallet.canWatchMore {
                // "WATCHING", not "Your wallets" (user ruling, 2026-08-27, on
                // a device: *"we could have a section called 'watching' or
                // something that pins them to the top but it would still be in
                // the address book category"*). The old name described a
                // separate thing sitting above the book; this one describes a
                // SECTION of it — the same word §448 used before §461 lifted
                // the roster out, and the same word the letter headings below
                // it are, so the screen reads as one list with a pinned top.
                // "Wallets you watch", not the bare "Watching" (user,
                // 2026-08-27: *"we can say Wallet: Watching or something so
                // its clear"*) — in a book that now holds keys, contacts and
                // social people, a lone participle no longer says WHAT is
                // being watched. The phrase is the house grammar ("Who you
                // save most", "What you hold"), not a colon header.
                sectionHeader(String(localized: "Wallets you watch"),
                              trailing: String(localized: "\(wallet.addresses.count) of \(WalletStore.watchLimit)"),
                              busy: syncing)
            }
        }
        // ONE LIST, NO CARD (same ruling). This section alone kept the inset-
        // grouped List's default card background while every other section in
        // the book clears it — so your own wallets sat in a raised slab and
        // everybody else sat on the page, and the screen read as a wallet
        // widget with an address book underneath rather than as an address
        // book. Matching the book's own row insets is what makes the faces
        // line up down one column with the rows below.
        .listRowInsets(EdgeInsets(top: 0, leading: DS.Space.s4,
                                  bottom: 0, trailing: DS.Space.s4))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .alert("Name this wallet",
               isPresented: Binding(get: { renamingID != nil },
                                    set: { if !$0 { renamingID = nil } })) {
            TextField("Name (e.g. Main, Cold)", text: $renameDraft)
            Button("Save") {
                if let id = renamingID,
                   let address = wallet.addresses.first(where: { $0.id == id })?.address {
                    wallet.rename(id, to: renameDraft)
                    CounterpartyRetitle.applyCurrentName(for: address, in: modelContext)
                    DSHaptic.success()
                }
                renamingID = nil
            }
            Button("Cancel", role: .cancel) { renamingID = nil }
        } message: {
            Text("A blank name shows the address instead.")
        }
        .onAppear {
            if !wallet.addresses.isEmpty { sync() }
        }
    }

    // MARK: - Rows (moved from `WalletScreen`, unchanged)

    /// DEDUPED BY ENTRY (prd §448): two watches can resolve to one book
    /// entry, and `AddressBook.Entry.id` is the address's own key.
    private var watchedEntries: [AddressBook.Entry] {
        var seen: Set<String> = []
        return wallet.addresses.compactMap { addr in
            let entry = book.entry(for: addr.address)
                ?? AddressBook.Entry(address: addr.address,
                                     name: wallet.displayName(for: addr),
                                     addedAt: .now)
            return seen.insert(entry.id).inserted ? entry : nil
        }
    }

    private func rosterRow(_ entry: AddressBook.Entry, row: Int) -> some View {
        let colliding = book.collidingKeys.contains(entry.id)
        return Button {
            DSHaptic.selection()
            beginRename(entry)
        } label: {
            AddressBookRow(entry: entry,
                           activity: nil,
                           watched: true,
                           colliding: colliding)
        }
        .buttonStyle(.plain)
        .settleIn(delay: Double(min(row, 4)) * 0.02)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: DS.Space.s4,
                                  bottom: 0, trailing: DS.Space.s4))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                remove(entry)
            } label: {
                Label("Remove", systemImage: "minus.circle")
            }
        }
        .contextMenu {
            Button {
                DSHaptic.tap()
                beginRename(entry)
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                DSPasteboard.copySensitive(entry.address)
                DSHaptic.success()
            } label: {
                Label("Copy Address", systemImage: "doc.on.doc")
            }
            Button(role: .destructive) {
                remove(entry)
            } label: {
                Label("Remove", systemImage: "minus.circle")
            }
        }
    }

    private func beginRename(_ entry: AddressBook.Entry) {
        guard let watch = wallet.addresses.first(where: {
            wallet.scopeMatches(entry.address, scope: $0.address)
        }) else { return }
        renameDraft = WalletStore.isAutoName(watch.label, for: watch.address) ? "" : watch.label
        renamingID = watch.id
    }

    /// Stop reading an address. Its NAME stays in the book.
    private func remove(_ entry: AddressBook.Entry) {
        guard let i = wallet.addresses.firstIndex(where: {
            wallet.scopeMatches(entry.address, scope: $0.address)
        }) else { return }
        let gone = wallet.addresses[i].address
        DSHaptic.tap()
        withAnimation(DS.Motion.standard) {
            wallet.remove(at: IndexSet(integer: i))
        }
        FollowPrune.removeWallet(address: gone,
                                 stillWatched: wallet.addresses.map(\.address),
                                 context: modelContext)
    }

    // MARK: - Reading the chain (moved from `WalletScreen`, unchanged)

    private func sync() {
        guard !syncing else { return }
        syncing = true
        Task {
            let added = await WalletIngest.refresh(context: modelContext)
            let totals = await WalletIngest.topHoldingsByWallet()
            syncing = false
            guard let added else {
                result = String(localized: "Couldn't reach the chain — check your connection.")
                resultIsError = true
                return
            }
            resultIsError = false
            let nothingFound = added == 0 && totals.allSatisfy { $0.totalUSD < 1 }
            if added > 0 {
                result = String(localized: "\(added) new")
            } else if nothingFound && wallet.addresses.count == 1 {
                result = String(localized: "No activity found on your chains yet — double-check the address, or give it a moment.")
            } else {
                result = String(localized: "Connected — watching for activity.")
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

    private func sectionHeader(_ title: String, trailing: String? = nil,
                               busy: Bool = false) -> some View {
        HStack(spacing: DS.Space.s2) {
            Text(title)
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(DS.textSecondary)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                    .monospacedDigit()
            }
            if busy {
                ProgressView().controlSize(.mini)
            }
        }
    }
}
