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
/// No key, no account: the LEZ sequencer answers anyone, and a node's read
/// API has no auth layer. A PRIVATE id is refused by name — its state is
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
            teardown: { LogosStore.shared.disconnect() },
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
        .onAppear {
            countWeek()
            if logos.connected { Task { await sync() } }
        }
        .onChange(of: logos.accounts) { _, _ in countWeek() }
    }

    /// The page's one sentence: the exposure while a network node is set;
    /// the reset, while an account reads empty in the month after one (prd
    /// §1035) — the only thing that explains an empty account; the devnets'
    /// test-coin line otherwise.
    private var sentence: String {
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
                id: id, title: LogosWire.short(id),
                subline: logos.isSystem(id)
                    ? String(localized: "Network account · moved only by the network")
                    : AccountPageShape.subline(nouns: String(localized: "Activity"),
                                               weekCount: counted.week),
                weekCount: counted.week, hasNew: counted.new,
                isYou: false, avatarURL: nil)
            row.faceAddress = id
            return row
        }
    }

    /// Your node, when one is watched: its sync state, height, peers,
    /// vouchers and mining, read on every pass.
    private var nodeRow: [AccountPageShape.Row] {
        guard logos.node != nil else { return [] }
        let counted = weekly[Self.nodeRowID] ?? (week: 0, new: false)
        return [AccountPageShape.Row(
            id: Self.nodeRowID, title: String(localized: "Your node"),
            subline: LogosWire.nodeLine(logos.nodeSnapshot),
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
                        isArmed: LogosWire.arms(LogosWire.entry(field)),
                        // The paste FILLS the field, as on every devnet page;
                        // the armed verb then does what it does for typing.
                        paste: { pasted in
                            field = pasted
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
        }
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
    /// Sixty-four hex characters that are not a point on the curve: no LEZ
    /// key or id, and the one measured case was a chat address (prd §1034).
    private static let notKey = String(localized: "That isn't an LEZ account or key. It may be a Logos chat address.")

    // MARK: - Actions

    private func watch() {
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
            logos.useNode(base)
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
                          "Read-only — no key, and nothing it could send."])
            } else {
                lastResult = .failed(String(localized: "Couldn't reach the Logos testnet — check your connection."))
            }
            countWeek()
        } while syncPending && logos.connected
    }
}
