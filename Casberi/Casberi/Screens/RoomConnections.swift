import SwiftUI

/// **THE ACCOUNTS SLOT, ONE TEMPLATE FOR EVERY WALLET-FAMILY ROOM (prd §689).**
///
/// §683 did Home, §686/§687 Activity, §688 Holdings. Accounts was the worst of
/// the four: Hegotá and the Privacy devnet drew their own ROSTER in the slot
/// and then drew the same roster again as the list beneath it — 258pt spent
/// restating the rows a finger's width below, which is §610's defect one scope
/// over. Only vibenet had a real figure, and it is a web of who authorised
/// whom (§491, the user's pick of three drawings).
///
/// **THE CROWN IS THE CONNECTIONS BETWEEN THE ACCOUNTS YOU WATCH** (user,
/// 2026-09-11: *"i was thinking it could be the connections between the
/// followed accounts"*, then *"wallet has connected addresses we used to show
/// this somewhere in a previous version"*). Both right, and the second one is
/// the find: **this is §295 restored.** *"N of your addresses are connected"*
/// — a count and a spine, the connected address on the left, your wallets on
/// the right, one ribbon per landed relationship — lived at the foot of the
/// Wallet manager until the Accounts-door redesign deleted that screen. The
/// MODEL survived: `AddressConnections` is still computed, still probed by
/// `-connectionsProbe`, still reported in the demo census every verify run.
/// Only the drawing died, so the app has been working this reading out and
/// showing it to nobody.
///
/// **`AddressConnections.map(edges:watched:)` is a PURE function**, which is
/// why every room can have it: a room that can name its transfers gets the
/// whole reading — the node cap, the §439 direct-pair links, the untouched
/// wallets — without a line of new analysis.
///
/// **§295's "factual, no analysis" (user, 2026-08-03) still governs**: a
/// bar's length is what moved between that address and your accounts — a
/// measured fact — in the map's own order, never re-ranked. The spine (§923)
/// and its identicon-hued ribbons are gone since prd §936; the tile draws
/// the bar list every other tile draws.
struct RoomConnectionsFigure: View {
    let map: AddressConnections.Map?
    var box: CGFloat = DSRoomChassis.figureSlot
    /// **THE PRESSED BAR.** A connected address's id; while set, the reading
    /// names it and says what moved, and the other bars go quiet.
    @State private var lit: String?

    var body: some View {
        if let map, !map.nodes.isEmpty {
            // **BARS, NOT RIBBONS (prd §936).** One bar per connected
            // address, as long as what moved with your accounts (the count of
            // moves where nothing was priced), in the one accent. The spine's
            // ribbons, faces and identicon hues are deleted: four inventions
            // for "how much with whom" became the bar every other tile draws.
            DSBarFigure(reading: { reading(map) },
                        bars: DSBarList(bars: Self.bars(map), lit: lit) { picked in
                            lit = lit == picked ? nil : picked
                        })
        }
    }

    /// The bars, in the map's own order (§295: factual, and never re-ranked
    /// into "who you deal with most").
    static func bars(_ map: AddressConnections.Map) -> [DSBarList.Bar] {
        let moved: [(node: AddressConnections.Node, usd: Double)] = map.nodes.map { node in
            (node, node.walletKeys.compactMap { map.weights[AddressConnections.Weight.key(node.id, $0)]?.usd }
                .reduce(0, +))
        }
        let priced = moved.contains { $0.usd > 0 }
        let peak = moved.map { priced ? $0.usd : Double($0.node.count) }.max() ?? 1
        return moved.map { entry in
            let value = priced ? entry.usd : Double(entry.node.count)
            return DSBarList.Bar(id: entry.node.id,
                                 label: entry.node.name,
                                 value: priced && entry.usd > 0 ? WalletValue.money(entry.usd)
                                     : Self.moves(entry.node.count),
                                 share: peak > 0 ? value / peak : 0)
        }
    }

    private static func moves(_ n: Int) -> String {
        n == 1 ? String(localized: "1 move") : String(localized: "\(String(n)) moves")
    }

    private func reading(_ map: AddressConnections.Map) -> some View {
        if let lit, let node = map.nodes.first(where: { $0.id == lit }) {
            let names = node.walletKeys.compactMap { key in map.columns.first { $0.id == key }?.name }
            return DSFigureReading(number: node.name,
                                   caption: String(localized: "\(Self.moves(node.count)) with \(names.joined(separator: ", "))"))
        }
        // **THE NUMBER COUNTS WHAT IS DRAWN (prd §940).** It was the count of
        // EDGES — "2 connections" over one bar, because one address was tied
        // to two of yours. One bar is one address, so the number is the
        // addresses, and the caption says what they are to you.
        return DSFigureReading(number: String(map.nodes.count),
                               caption: String(localized: "tied to yours"))
    }
}

/// **THE LIST SAYS WHAT EACH ADDRESS IS AND HOW IT RELATES (prd §689, user:
/// "for the list for wallets what should it be, should it really be what each
/// holds b/c we have a holdings slot for that on the rail. it needs to be
/// something else").**
///
/// Right, and both rooms' own scope description said the wrong thing out loud
/// — *"the addresses you watch, and what each holds"*, which is the Holdings
/// chip's sentence. Every other scope has taken a piece: Home the total,
/// Activity what moved, Holdings what is held, Frames and Permissions the
/// mechanics. What is left, and what nothing else can answer, is **what this
/// address IS and how it relates to the others you watch** — which also makes
/// the list the crown's own legend rather than a second copy of it.
extension RoomAccountsRows {
    /// **YOURS, THEN THE ACCOUNTS TIED TO THEM (prd §940).** The followed
    /// rows learn WHO they are tied to, by name, and the accounts tied to them
    /// follow as their own group — one row per bar in the crown, each carrying
    /// that bar's own figure. Same key rule as the map (lowercased hex), so a
    /// tied account that is also followed is never listed twice.
    static func list(_ followed: [Row], map: AddressConnections.Map?) -> [Row] {
        guard let map else { return followed }
        let yours = Set(followed.map(\.key))
        let figures = Dictionary(uniqueKeysWithValues: RoomConnectionsFigure.bars(map).map { ($0.id, $0.value) })
        let named = Dictionary(uniqueKeysWithValues: map.columns.map { ($0.id, $0.name) })
        let own = followed.map { row in
            var row = row
            row.with = map.nodes.filter { $0.walletKeys.contains(row.key) }.map(\.name)
            return row
        }
        let tied = map.nodes.filter { !yours.contains($0.id) }.map { node in
            Row(key: node.id, address: node.address, name: node.name, kind: nil,
                with: node.walletKeys.compactMap { named[$0] }, amount: figures[node.id],
                watched: false, unreached: false)
        }
        return own + tied
    }
}

struct RoomAccountsRows: View {
    struct Row: Identifiable {
        var id: String { key }
        let key: String
        let address: String
        let name: String
        /// What it is — `AddressBook.Kind`'s word, or a room's own.
        let kind: String?
        /// Who it is tied to, by name: the tied accounts for one of yours,
        /// yours for a tied one (prd §940). Empty says nothing at all.
        var with: [String] = []
        /// What moved with a tied account — its bar's own figure. Yours carry
        /// none: Holdings owns what they hold.
        var amount: String? = nil
        /// **Whether YOU follow it (prd §689c, §940).** Yours come first, the
        /// accounts tied to them after, each group under its own name.
        var watched: Bool = true
        /// True when the chain did not answer for it; the row says so instead
        /// of reading as an address with nothing going on (§515a).
        let unreached: Bool
        var onOpen: (() -> Void)? = nil
    }

    let rows: [Row]

    var body: some View {
        // The groups are named only when there are two (prd §940): a list
        // of yours alone needs no word over it.
        let split = rows.contains { !$0.watched }
        ForEach(rows) { row in
            if split, row.id == rows.first(where: { $0.watched })?.id {
                header(String(localized: "Yours"))
            }
            if split, row.id == rows.first(where: { !$0.watched })?.id {
                header(String(localized: "Tied to yours"))
            }
            if let onOpen = row.onOpen {
                Button {
                    DSHaptic.selection()
                    onOpen()
                } label: { body(row).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
            } else {
                body(row)
            }
        }
    }

    /// The feed's group header, a group named by something other than time
    /// (primary ink, never the day's brand hue — prd §740). Text is a box, so
    /// it stands on the tiles' edge, the line the account menu shares.
    private func header(_ word: String) -> some View {
        Text(word)
            .dsText(.heading24)
            .foregroundStyle(DS.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, DSRoomChassis.inset)
            .padding(.top, DS.Space.s6)
            .padding(.bottom, DS.Space.s1)
            .listRowInsets(EdgeInsets())
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private func body(_ row: Row) -> some View {
        WalletRow(mark: .face(row.address), title: row.name, subtitleText: subtitle(row)) {
            // Only a tied account carries a figure — what moved with it, the
            // bar's own number. The bare count that stood here repeated the
            // line under the name (prd §940).
            if let amount = row.amount {
                Text(amount)
                    .dsText(.price17)
                    .foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
            }
        }
    }

    private func subtitle(_ row: Row) -> Text? {
        var parts: [String] = []
        if let kind = row.kind { parts.append(kind) }
        if row.unreached {
            // An unread address is not an unconnected one (§83, §515a).
            parts.append(String(localized: "couldn't be reached"))
        } else if !row.with.isEmpty {
            let names = ListFormatter.localizedString(byJoining: row.with)
            parts.append(String(localized: "with \(names)"))
        }
        return parts.isEmpty ? nil : Text(parts.joined(separator: " · "))
    }
}

/// **EDGES FROM A ROOM'S OWN MOVES (prd §689).**
///
/// `AddressConnections.map` is a pure function over edges, so a devnet needs
/// only to say who its transfers were with. The Wallet builds its edges from
/// the corpus through `AddressConnectionsSource`; this is the same shape for a
/// room whose transfers are read straight off a chain.
///
/// **Oldest first, which `map` requires and states why**: node order is
/// first-appearance order — "the order you first dealt with them" —
/// deterministic across launches and not a judgment about which address
/// matters. Sorting by count or by value would be the ranking §295 forbids.
enum RoomConnectionsEdges {

    /// One transfer, as a room can describe it without knowing anything about
    /// the address book.
    struct Move {
        /// The watched address this move belongs to.
        let owner: String
        /// Who it was with.
        let counterparty: String
        /// Chain order, oldest smallest. A block number is exactly this.
        let order: UInt64
    }

    static func edges(_ moves: [Move], name: (String) -> String) -> [AddressConnections.Edge] {
        moves
            .filter { !$0.counterparty.isEmpty && !$0.owner.isEmpty }
            // **A MOVE WITH ITSELF IS NOT A CONNECTION.** Some of these chains
            // route a transfer through the sender's own address (a UTXO's
            // change comes straight back), and counting it would make every
            // account connected to itself and to nothing else.
            .filter { $0.counterparty.caseInsensitiveCompare($0.owner) != .orderedSame }
            .sorted { $0.order < $1.order }
            .map { move in
                AddressConnections.Edge(
                    addressKey: move.counterparty.lowercased(),
                    address: move.counterparty,
                    addressName: name(move.counterparty),
                    named: false,
                    walletKey: move.owner.lowercased(),
                    // **NO VALUE, EVER.** These are test chains with no price
                    // — `FramesMoney`'s standing rule — and the spine's own
                    // ruling is that every ribbon weighs the same anyway.
                    usd: nil)
            }
    }
}
