import SwiftUI
import SwiftData

/// Logos, connected (prd §988, §989). The devnet page's grammar (Frames,
/// Hegotá, vibenet): ONE field, the watched roster, the one sentence about
/// what test coins are, and the explorer's door.
///
/// **One field takes both things Logos can watch** — a public LEZ account id
/// or your own node's address — and tells them apart (`LogosWire.entry`), so
/// the page keeps the template's single entry well (§708) instead of growing a
/// second for the node.
///
/// **No balances on the roster.** Money lives in the room, as on every wallet
/// and devnet page; the roster says which accounts and what arrived this week.
///
/// The watch needs no key and no account: the LEZ sequencer answers anyone,
/// and a node's read API has no auth layer. Sending (prd §1084) is the room's
/// Create and Send, with this phone's own key (`LogosKey`). A PRIVATE id is refused by name — its state is
/// encrypted to its owner and the sequencer answers it as an empty public
/// account, which a watch would draw as a confident zero.
struct LogosScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Bindable private var logos = LogosStore.shared
    @State private var field = ""
    @State private var syncing = false
    @State private var syncPending = false
    @State private var lastResult: BridgeProof?
    @FocusState private var fieldFocused: Bool
    @State private var sheet: AccountPageSheet?
    @State private var weekly: [String: (week: Int, new: Bool)] = [:]
    /// The account being named (prd §1091), and the name as typed.
    @State private var namingID: String?
    @State private var nameDraft = ""
    /// A Logos Observer pairing waiting for consent (2026-10-03): pasted into
    /// the field, or handed in by the system camera as a link.
    @State private var pairOffer: PairOffer?
    private struct PairOffer: Identifiable { let id = UUID(); let offer: LogosObserverWire.Offer }

    /// The roster row's id for the node. Node refs are `logos:node:<kind>:…`,
    /// so `countWeek`'s `:<id>:` match finds them by it.
    private static let nodeRowID = "node"

    var body: some View {
        AccountPage(
            name: "Logos", seatID: "logos", source: "Logos",
            state: AccountPageState.of(name: "Logos", seatID: "logos",
                                       connected: logos.connected, store: store),
            mode: .noAccount,
            rows: rows,
            query: field,
            onRemoveRow: unwatch,
            // NAME AN ACCOUNT (prd §1091, a Logos user: "giving a name to my
            // LEZ wallets as its about to get real messy"). The address book
            // is the app's one naming authority — the Wallet's and Frames'
            // names live there, Solana's base58 included — so a name given
            // here is the name everywhere the id is drawn. The node row has
            // no id to name.
            rowMenu: { id in
                AnyView(Group {
                    if id != Self.nodeRowID {
                        Button {
                            nameDraft = AddressBook.shared.name(for: id) ?? ""
                            namingID = id
                        } label: {
                            Label(AddressBook.shared.name(for: id) == nil ? "Name" : "Rename",
                                  systemImage: "pencil")
                        }
                    }
                })
            },
            teardown: {
                LogosStore.shared.disconnect()
                Task { await LogosObserver.shared.forget() }
            },
            sheet: $sheet,
            act: { addBlock },
            more: {
                // THE ONE GRAY SENTENCE (§748), the devnets' own: what changes
                // what somebody would do is that nothing here is money and
                // the network forgets. A node reached over a network takes the
                // slot instead, because that exposure is the fact that
                // matters more the moment it exists.
                DSFootnote(prose: sentence)
                    .padding(.vertical, DS.Space.s3)
                DevnetExplorerRow(url: LogosIngest.explorer, plain: true)
            },
            keySheet: { EmptyView() }
        )
        .alert("Name this account",
               isPresented: Binding(get: { namingID != nil }, set: { if !$0 { namingID = nil } })) {
            TextField("Name (e.g. Trading)", text: $nameDraft)
            Button("Save") {
                if let id = namingID { AddressBook.shared.setName(nameDraft, for: id) }
                namingID = nil
            }
            Button("Cancel", role: .cancel) { namingID = nil }
        } message: {
            Text("Blank shows the id instead.")
        }
        .sheet(item: $pairOffer) { box in
            LogosObserverPairTray(offer: box.offer) {
                lastResult = .says(String(localized: "Paired with \(box.offer.name)."))
                Task { await sync() }
            }
        }
        .onAppear {
            countWeek()
            takePendingOffer()
            if logos.connected { Task { await sync() } }
        }
        .onChange(of: logos.accounts) { _, _ in countWeek() }
        .onChange(of: LogosObserver.shared.pendingOffer) { _, _ in takePendingOffer() }
    }

    /// The page's one sentence: the exposure while a network node is set;
    /// the reset, while an account reads empty in the month after one (prd
    /// §1035) — the only thing that explains an empty account; the devnets'
    /// test-coin line otherwise.
    private var sentence: String {
        if LogosObserver.shared.serves(logos.node) {
            return String(localized: "Your network can see that you're reaching your node, but not what it reports.")
        }
        if let node = logos.node, !LogosWire.isLoopback(node) {
            return String(localized: "A node reached over a network answers anyone on it, writes included.")
        }
        if logos.showsResetNote(), let start = logos.chainStart {
            let day = start.formatted(.dateTime.month(.abbreviated).day())
            return String(localized: "The testnet was reset on \(day), so accounts from before then are empty.")
        }
        return String(localized: "Test coins have no value, and the testnet may be reset without notice.")
    }

    // MARK: - The roster

    /// The accounts, then your node — the room's order, Accounts before Node.
    private var rows: [AccountPageShape.Row] {
        accountRows + nodeRow
    }

    /// One row per watched account: its short id and what landed this week,
    /// wearing its own face (prd §690) like a wallet row.
    private var accountRows: [AccountPageShape.Row] {
        logos.accounts.map { id in
            // `AccountWeek` keys its counts lowercased; base58 is case-sensitive,
            // but two ids differing only in case are not a real collision here.
            let counted = weekly[id.lowercased()] ?? (week: 0, new: false)
            // A network account (prd §1035) says what it is: it never lands
            // a row, so "Activity · 0" would read as a quiet wallet.
            var row = AccountPageShape.Row(
                id: id, title: LogosRoom.name(for: id),
                subline: Self.withID(id, logos.isSystem(id)
                    ? String(localized: "Network account · moved only by the network")
                    : AccountPageShape.subline(nouns: String(localized: "Activity"),
                                               weekCount: counted.week)),
                weekCount: counted.week, hasNew: counted.new,
                isYou: false, avatarURL: nil)
            row.faceAddress = id
            return row
        }
    }

    /// A NAMED account keeps its address in sight (prd §1091, "Name and
    /// Address"): the short id leads its line. An unnamed one already wears
    /// the id as its title.
    static func withID(_ id: String, _ line: String) -> String {
        AddressBook.shared.name(for: id) == nil ? line : "\(LogosWire.short(id)) · \(line)"
    }

    /// Your node, when one is watched: its sync state, height, peers,
    /// vouchers and mining, read on every pass.
    private var nodeRow: [AccountPageShape.Row] {
        guard logos.node != nil else { return [] }
        let counted = weekly[Self.nodeRowID] ?? (week: 0, new: false)
        return [AccountPageShape.Row(
            id: Self.nodeRowID, title: String(localized: "Your node"),
            subline: LogosObserver.shared.paired.map {
                String(localized: "Through \($0.name) · \(LogosWire.nodeLine(logos.nodeSnapshot))")
            } ?? LogosWire.nodeLine(logos.nodeSnapshot),
            weekCount: counted.week, hasNew: counted.new,
            isYou: false, avatarURL: nil)]
    }

    private func countWeek() {
        let watched = logos.accounts + (logos.node != nil ? [Self.nodeRowID] : [])
        weekly = AccountWeek.counts(source: "Logos", seatID: "logos",
                                    context: modelContext) { thing in
            guard let ref = thing.sourceRef else { return nil }
            return watched.first { ref.contains(":\($0):") }
        }
    }

    @ViewBuilder private var addBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            DSSlabField(placeholder: Self.placeholder,
                        text: $field,
                        actionLabel: String(localized: "Watch"),
                        keyboard: .URL,
                        focus: $fieldFocused,
                        isArmed: LogosWire.arms(LogosWire.entry(field))
                            || LogosObserverWire.offer(field) != nil,
                        // The paste FILLS the field, as on every devnet page;
                        // the armed verb then does what it does for typing.
                        paste: { pasted in
                            field = pasted
                            if LogosObserverWire.offer(pasted) != nil { return }
                            switch LogosWire.entry(pasted) {
                            case .invalid: lastResult = .failed(Self.malformed)
                            case .notKey:  lastResult = .failed(Self.notKey)
                            default:       break
                            }
                        },
                        action: watch)
            BridgeSyncStatusRows(syncing: syncing,
                                 syncingLine: String(localized: "Reading the testnet…"),
                                 proof: lastResult)
            if !LogosObserver.shared.serves(logos.node) { observerCard }
        }
    }

    /// How to read your node safely (prd §1095): through the Logos Observer,
    /// paired by its QR. Typing the Observer's address does not pair it — a
    /// tester did, and the room said "Not answering" — so the page says how.
    private var observerCard: some View {
        BridgeSetupCard(steps: Self.observerSteps, startingAt: 2, numbered: false) {
            DSSlabButton(title: String(localized: "Get Logos Observer"),
                         detail: "github.com/0xterricola/logos-observer",
                         systemImage: "arrow.up.right", url: Self.observerRepo)
        }
        .padding(.top, DS.Space.s2)
    }

    private static let observerRepo = URL(string: "https://github.com/0xterricola/logos-observer")

    private static var observerSteps: [String] {
        #if targetEnvironment(macCatalyst)
        [String(localized: "Run it beside your node."),
         String(localized: "Run v2_pair_cli.py for a pairing link."),
         String(localized: "Paste the link in the field above.")]
        #else
        [String(localized: "Run it beside your node."),
         String(localized: "Run v2_pair_cli.py for a pairing QR."),
         String(localized: "Scan the QR with the Camera app.")]
        #endif
    }

    /// On a Mac running Basecamp the node answers at its default, so the
    /// field names it; on a phone a node is never local, so it does not.
    private static var placeholder: String {
        #if targetEnvironment(macCatalyst)
        String(localized: "LEZ account id, or 127.0.0.1:8080")
        #else
        String(localized: "LEZ account id, or your node's address")
        #endif
    }

    private static let malformed = String(localized: "That isn't an LEZ account id or a node address.")
    private static let observerWatched = String(localized: "Your node's address is a Logos Observer. Remove it and pair with its QR, as below.")
    private static let observerAddress = String(localized: "That's a Logos Observer. Pair it with its QR, as below.")
    /// Sixty-four hex characters that are not a point on the curve: no LEZ
    /// key or id, and the one measured case was a chat address (prd §1034).
    private static let notKey = String(localized: "That isn't an LEZ account or key. It may be a Logos chat address.")

    // MARK: - Actions

    private func watch() {
        // An Observer's pairing link (2026-10-03) is not an account or an
        // address: it opens the consent tray, and nothing is sent until Pair.
        if let offer = LogosObserverWire.offer(field) {
            field = ""
            fieldFocused = false
            pairOffer = PairOffer(offer: offer)
            return
        }
        var note: String?
        switch LogosWire.entry(field) {
        case .invalid:
            lastResult = .failed(Self.malformed)
            return
        case .notKey:
            lastResult = .failed(Self.notKey)
            return
        case .key(let id):
            // A public key, as Logos's command-line wallet prints it: watch
            // its account, and say so, since the roster shows the account's
            // id rather than what was pasted (prd §1034).
            guard logos.add(id) == .added else {
                lastResult = .says(String(localized: "Already watching that key's account."))
                field = ""
                return
            }
            note = String(localized: "That's a public key. Watching its account, \(LogosWire.short(id)).")
        case .privateAccount:
            // Not a typo: a real account this door cannot read.
            lastResult = .says(String(localized: "A private account is readable only with its owner's consent."))
            return
        case .node(let base):
            guard base != logos.node else {
                lastResult = .says(String(localized: "Already watching that node."))
                field = ""
                return
            }
            // An Observer's address is not a node's: it answers only a device
            // paired by its QR, so it is never watched as one.
            let typed = field
            field = ""
            fieldFocused = false
            Task {
                if await LogosObserver.answersAsObserver(base) {
                    lastResult = .failed(Self.observerAddress)
                    field = typed
                    return
                }
                logos.useNode(base)
                DSHaptic.tap()
                await sync()
            }
            return
        case .account(let id):
            guard logos.add(id) == .added else {
                lastResult = .says(String(localized: "Already watching that account."))
                field = ""
                return
            }
        }
        field = ""
        fieldFocused = false
        DSHaptic.tap()
        Task {
            await sync()
            if let note { lastResult = .says(note) }
        }
    }

    private func unwatch(_ id: String) {
        if id == Self.nodeRowID {
            if LogosObserver.shared.serves(logos.node) {
                Task { await LogosObserver.shared.forget() }
            }
            logos.useNode(nil)
            FollowPrune.remove(source: "Logos", context: modelContext) {
                $0.sourceRef?.hasPrefix("logos:node:") == true
            }
            lastResult = .says(String(localized: "Stopped watching your node."))
        } else {
            logos.remove(id)
            // Its rows leave with it (prd §286); every ref carries the id.
            FollowPrune.remove(source: "Logos", context: modelContext) {
                $0.sourceRef?.contains(":\(id):") == true
            }
            lastResult = .says(String(localized: "Stopped watching \(LogosWire.short(id))."))
        }
        DSHaptic.tap()
        countWeek()
        Task { await sync() }
    }

    private func sync() async {
        guard logos.connected else {
            store.remove("logos")
            return
        }
        if syncing { syncPending = true; return }
        syncing = true
        defer { syncing = false }
        repeat {
            syncPending = false
            let outcome = await LogosIngest.refresh(context: modelContext)
            guard logos.connected else { store.remove("logos"); return }
            if let outcome {
                lastResult = outcome.stalled
                    ? .says(String(localized: "The testnet changed its block format, so activity is paused. Balances still update."))
                    : outcome.skipped > 0
                        ? .says(String(localized: "Skipped \(outcome.skipped) blocks from while you were away."))
                    : outcome.added > 0 ? .landed(outcome.added) : .upToDate
                let proof = outcome.added > 0
                    ? String(localized: "\(outcome.added) in")
                    : String(localized: "Synced just now")
                store.registerConnected(
                    id: "logos", name: "Logos", proof: proof,
                    can: ["Reads the balance and activity of the public LEZ accounts you watch, on the Logos testnet.",
                          "Reads your own node's sync state, peers, mining and reward vouchers, at the address you give it.",
                          "Sends test coins from an account made on this phone, signed with a key that never leaves it."])
            } else {
                lastResult = .failed(String(localized: "Couldn't reach the Logos testnet — check your connection."))
            }
            if let notice = LogosObserver.shared.notice { lastResult = .failed(notice) }
            // A node address that never answers may be an Observer watched as
            // a node (the 2026-10-04 tester): say so rather than "Not answering".
            if let base = logos.node, !LogosObserver.shared.serves(base),
               logos.nodeSnapshot?.reachable == false,
               await LogosObserver.answersAsObserver(base) {
                lastResult = .failed(Self.observerWatched)
            }
            countWeek()
        } while syncPending && logos.connected
    }

    /// An offer handed in by link waits on `LogosObserver` until this page
    /// can raise its consent tray.
    private func takePendingOffer() {
        guard let offer = LogosObserver.shared.pendingOffer else { return }
        LogosObserver.shared.pendingOffer = nil
        pairOffer = PairOffer(offer: offer)
    }
}
