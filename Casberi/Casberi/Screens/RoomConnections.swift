import SwiftUI

/// **WHAT MOVED WITH A TIED ACCOUNT (prd §940, §948).** The bars crown that
/// drew this (`RoomConnectionsFigure`) is deleted — every room's Accounts crown
/// is its accounts face by face now — and this is the one number of it the
/// list still states: dollars when any tie carries a price, else how many
/// moves, in the map's own order (§295: factual, never re-ranked).
enum RoomConnectionsFigures {
    static func values(_ map: AddressConnections.Map) -> [String: String] {
        let moved: [(node: AddressConnections.Node, usd: Double)] = map.nodes.map { node in
            (node, node.walletKeys.compactMap { map.weights[AddressConnections.Weight.key(node.id, $0)]?.usd }
                .reduce(0, +))
        }
        let priced = moved.contains { $0.usd > 0 }
        var out: [String: String] = [:]
        for entry in moved {
            out[entry.node.id] = priced && entry.usd > 0 ? WalletValue.money(entry.usd)
                : (entry.node.count == 1 ? String(localized: "1 move")
                                         : String(localized: "\(String(entry.node.count)) moves"))
        }
        return out
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
    ///
    /// `scope` is one of yours (the face or the menu picked it, prd §941):
    /// the list narrows to that account and the accounts tied to IT. It is a
    /// row KEY, never lowercased here: a Solana address is case-sensitive.
    static func list(_ followed: [Row], map: AddressConnections.Map?, scope: String? = nil) -> [Row] {
        let shown = scope.map { key in followed.filter { $0.key == key } } ?? followed
        guard let map else { return shown }
        let yours = Set(followed.map(\.key))
        let figures = RoomConnectionsFigures.values(map)
        let named = Dictionary(uniqueKeysWithValues: map.columns.map { ($0.id, $0.name) })
        let own = shown.map { row in
            var row = row
            row.with = map.nodes.filter { $0.walletKeys.contains(row.key) }.map(\.name)
            return row
        }
        let tied = map.nodes.filter { node in
            !yours.contains(node.id) && scope.map { node.walletKeys.contains($0) } ?? true
        }.map { node in
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
        // "Yours" over your accounts in every room (prd §954, reversing
        // §940's "only when there are two"): the Wallet named its group and
        // Privacy did not, so the same list read as two different screens.
        let split = rows.contains { !$0.watched }
        let shared = Self.sharedWith(rows)
        ForEach(rows) { row in
            if row.id == rows.first(where: { $0.watched })?.id {
                header(String(localized: "Yours"))
            }
            if split, row.id == rows.first(where: { !$0.watched })?.id {
                header(String(localized: "Tied to yours"))
            }
            Group {
                if let onOpen = row.onOpen {
                    Button {
                        DSHaptic.selection()
                        onOpen()
                    } label: { body(row, drop: shared).contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                } else {
                    body(row, drop: shared)
                }
            }
            // The rows' column in every room (prd §954): the Wallet's list sat
            // on the List's default inset, 10pt left of every other list.
            .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.rowInset(forMark: DS.Face.list),
                                      bottom: 0, trailing: DS.Space.s4))
        }
    }

    /// The group header on the tiles' edge wherever the list is mounted (prd
    /// §954): as its own List row it takes the rows' inset and steps back from
    /// it; inside a room's stacked list it is already in that column and
    /// steps back the same. `DSGroupHeader` assumes the first and lands 27pt
    /// in on Privacy, whose list is one stacked row.
    private func header(_ word: String) -> some View {
        Text(word)
            .dsText(.heading24)
            .foregroundStyle(DS.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, DSRoomChassis.inset - DSRoomChassis.rowInset(forMark: DS.Face.list))
            .padding(.top, DS.Space.s6)
            .padding(.bottom, DS.Space.s1)
            .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.rowInset(forMark: DS.Face.list),
                                      bottom: 0, trailing: DS.Space.s4))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityAddTraits(.isHeader)
    }

    /// **A LINE EVERY ROW SHARES SAYS NOTHING** (prd §954, the §951 subtext
    /// rule). When every one of your accounts dealt with the same one party,
    /// "with …be02" under each is the "Tied to yours" row said again; the line
    /// stays where it tells rows apart ("with Sam" under two of five).
    static func sharedWith(_ rows: [Row]) -> [String]? {
        let yours = rows.filter(\.watched)
        guard yours.count > 1, let first = yours.first?.with, !first.isEmpty,
              yours.allSatisfy({ $0.with == first }) else { return nil }
        return first
    }

    @ViewBuilder private func body(_ row: Row, drop shared: [String]?) -> some View {
        WalletRow(mark: .face(row.address), title: row.name,
                  subtitleText: subtitle(row, dropping: row.watched ? shared : nil)) {
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

    private func subtitle(_ row: Row, dropping shared: [String]?) -> Text? {
        var parts: [String] = []
        if let kind = row.kind { parts.append(kind) }
        if row.unreached {
            // An unread address is not an unconnected one (§83, §515a).
            parts.append(String(localized: "couldn't be reached"))
        } else if !row.with.isEmpty, row.with != shared {
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
