import Foundation

/// WHICH OF YOUR ADDRESSES ARE CONNECTED — the address book's own summary
/// (2026-08-03, prd §295, ruled from `design/wallet-viz/wallet-ties-mocks.html`).
///
/// The book is a flat list that has never said how any two of its entries
/// relate. This counts the ones that do, and draws them: the address on one
/// side, your wallets on the other, one ribbon per real relationship.
///
/// ## Connected means they transacted
///
/// An edge exists ONLY where a transfer between those two addresses actually
/// landed. A shared counterparty — "these two both dealt with someone else" —
/// is deliberately NOT an edge: that is an inference, and this card makes none.
/// The user ruling that shaped the whole file (2026-08-03): *limit the
/// analysis, it should be factual.* So there is no ranking, no superlative, no
/// reading of what a connection implies. Counts and totals are stated and never
/// compared, and the order is the order you first dealt with each address.
///
/// ## Why the bar is TWO of your wallets
///
/// Every counterparty in the book reaches at least one of your wallets by
/// definition — that is how it got into the corpus. Counting those would print
/// the book's own length back at you wearing a new word. An address that
/// reaches two or more is the fact the book cannot already show.
///
/// ## Ribbons carry no weight
///
/// Every ribbon draws the same. A connection either exists or it doesn't, and
/// scaling one by volume would be the card making a point about which
/// relationship matters — exactly the analysis this card was told not to do.
/// The amounts are still stated, per wallet, in words.
///
/// PURE AND FOUNDATION-ONLY, like `WalletFlow` and for the same reason: the
/// failure mode here is a WRONG COUNT, which renders perfectly and looks right.
/// `scripts/wallet-viz-selftest.sh` compiles this file AS SHIPPED and feeds it
/// cases whose answers are known. The `Thing`- and book-reading half lives in
/// `AddressConnectionsSource.swift` and is not compiled there.
enum AddressConnections {

    /// One landed relationship between an address and one of your watched
    /// wallets. The adapter builds these while the models are live; from here
    /// on nothing touches SwiftData, which is what keeps this card immune to
    /// the liveness crash class (CLAUDE.md corollaries 1–6) rather than merely
    /// guarded against it.
    struct Edge: Equatable {
        /// The other address, folded to the book's key (lowercased hex on EVM,
        /// case preserved on Solana — `AddressBook.key(for:)` owns that rule).
        let addressKey: String
        /// What to call it: your name for it, a known handle, else the short
        /// form. Never a raw full hash — the title rule every wallet surface
        /// already keeps.
        let addressName: String
        /// False when `addressName` is only the shortened address, i.e. nobody
        /// has ever named this. Drives the card's one action.
        let named: Bool
        /// Which of your wallets this side is.
        let walletKey: String
        /// USD at the time it moved, straight from the transfer. Optional
        /// rather than defaulted to zero: an unpriced move is unknown, and a
        /// zero would understate a wallet's total while pretending to be a
        /// measurement.
        let usd: Double?
    }

    /// One of your watched wallets, as the adapter hands it in.
    struct WatchedWallet: Equatable {
        let key: String
        let name: String
    }

    /// A connected address — one row on the left of the spine.
    struct Node: Identifiable, Equatable {
        let id: String
        let name: String
        /// How many transactions there were, across every wallet it reaches.
        let count: Int
        let named: Bool
        /// Which of your wallets it reaches, in your own watch order. Two or
        /// more, always — that is what makes it a node.
        let walletKeys: [String]
    }

    /// One of your wallets — one row on the right of the spine. Only wallets a
    /// connected address actually reaches appear.
    struct Column: Identifiable, Equatable {
        let id: String
        let name: String
        /// What moved between this wallet and the connected addresses. Nil
        /// when nothing on this side could be priced — stated as nothing
        /// rather than as `$0`, which is a different claim.
        let usd: Double?
    }

    /// The whole reading.
    struct Map: Equatable {
        /// The connected addresses that are DRAWN — capped at `nodeLimit`.
        let nodes: [Node]
        let columns: [Column]
        /// How many connected addresses there are in total, drawn or not. This
        /// is the headline's number: the count states the truth even when the
        /// picture is capped.
        let connectedCount: Int
        /// Your watched wallets that no connected address reaches, by name.
        /// Named rather than drawn as empty nodes — an absence reads better as
        /// a sentence.
        let untouchedWalletNames: [String]

        /// True when there is nothing connected. Not the same as the map being
        /// nil: nil means the card cannot say anything at all (fewer than two
        /// wallets watched), this means it can and the answer is none.
        var isEmpty: Bool { connectedCount == 0 }

        /// How many connected addresses are counted but not drawn. Stated by
        /// the card — the no-silent-caps rule.
        var hiddenCount: Int { max(0, connectedCount - nodes.count) }

        /// The first unnamed connected address, which is the card's one action.
        /// First rather than "the busiest": picking by size would be a ranking.
        var firstUnnamed: Node? { nodes.first { !$0.named } }
    }

    /// A connection needs two of your wallets to exist at all, so a person
    /// watching one gets no card rather than an empty one.
    static let minWallets = 2

    /// How many connected addresses are drawn before the rest become a line of
    /// text. A spine of twenty is not a picture of anything.
    static let nodeLimit = 6

    /// Builds the map, or nil when the card can't say anything.
    ///
    /// `edges` must arrive OLDEST FIRST: node order is first-appearance order,
    /// which is "the order you first dealt with them" — deterministic across
    /// launches, and not a judgment about which address matters. Sorting by
    /// count or by dollars would be the ranking the ruling forbids.
    ///
    /// Totals and the untouched-wallet list are computed over EVERY connected
    /// address, not just the drawn ones: a display cap must not change what a
    /// number means.
    static func map(edges: [Edge], watched: [WatchedWallet]) -> Map? {
        guard watched.count >= minWallets else { return nil }
        let watchedKeys = Set(watched.map(\.key))

        // Group by address, keeping first-appearance order.
        var order: [String] = []
        var byAddress: [String: (name: String, named: Bool, count: Int, wallets: [String])] = [:]
        for edge in edges {
            // An edge to a wallet we no longer watch is history about a watch
            // that ended — it can't contribute to a count phrased "your
            // wallets", and leaving it in would keep an unwatched wallet alive
            // in the picture.
            guard watchedKeys.contains(edge.walletKey) else { continue }
            // A transfer between an address and itself is not a relationship.
            guard edge.addressKey != edge.walletKey else { continue }
            if byAddress[edge.addressKey] == nil {
                order.append(edge.addressKey)
                byAddress[edge.addressKey] = (edge.addressName, edge.named, 0, [])
            }
            var entry = byAddress[edge.addressKey]!
            entry.count += 1
            if !entry.wallets.contains(edge.walletKey) { entry.wallets.append(edge.walletKey) }
            // The first spelling seen wins, so a name can't flicker between
            // passes when one transfer resolved it and another didn't.
            if !entry.named, edge.named {
                entry.name = edge.addressName
                entry.named = true
            }
            byAddress[edge.addressKey] = entry
        }

        // Connected = reaches two or more of your wallets. See the type doc for
        // why one doesn't count.
        var connected: [Node] = []
        for key in order {
            guard let entry = byAddress[key], entry.wallets.count >= 2 else { continue }
            connected.append(Node(id: key, name: entry.name, count: entry.count,
                                  named: entry.named,
                                  // Rendered in YOUR watch order, not the order
                                  // the transfers happened to land in, so two
                                  // nodes' ribbons never cross for no reason.
                                  walletKeys: watched.map(\.key).filter { entry.wallets.contains($0) }))
        }

        guard !connected.isEmpty else {
            return Map(nodes: [], columns: [], connectedCount: 0,
                       untouchedWalletNames: watched.map(\.name))
        }

        let connectedKeys = Set(connected.map(\.id))
        let touched = Set(connected.flatMap(\.walletKeys))

        // Per-wallet totals, over every connected address.
        var totals: [String: Double] = [:]
        for edge in edges where connectedKeys.contains(edge.addressKey) {
            guard let usd = edge.usd, usd > 0, usd.isFinite else { continue }
            totals[edge.walletKey, default: 0] += usd
        }

        let columns = watched.filter { touched.contains($0.key) }
            .map { Column(id: $0.key, name: $0.name, usd: totals[$0.key]) }
        let untouched = watched.filter { !touched.contains($0.key) }.map(\.name)

        return Map(nodes: Array(connected.prefix(nodeLimit)),
                   columns: columns,
                   connectedCount: connected.count,
                   untouchedWalletNames: untouched)
    }

    // MARK: - The card's words

    /// "3 of your addresses are connected." The whole finding, as a sentence.
    static func headline(count: Int) -> String {
        switch count {
        case 0:  return String(localized: "None of your addresses are connected")
        case 1:  return String(localized: "1 of your addresses is connected")
        default: return String(localized: "\(count) of your addresses are connected")
        }
    }

    /// What "connected" means, said once, underneath. Nil at zero — the
    /// headline is already the whole answer there, and a definition beneath it
    /// would be explaining a negative.
    static func subhead(count: Int) -> String? {
        switch count {
        case 0:  return nil
        case 1:  return String(localized: "It has transacted with more than one of your wallets.")
        default: return String(localized: "Each has transacted with more than one of your wallets.")
        }
    }

    /// "and 2 more" — the drawn-vs-counted gap, never silent.
    static func hiddenNote(_ hidden: Int) -> String? {
        guard hidden > 0 else { return nil }
        return hidden == 1
            ? String(localized: "1 more isn't drawn.")
            : String(localized: "\(hidden) more aren't drawn.")
    }

    /// The wallets nothing connected reaches, as a sentence rather than empty
    /// nodes. Nil when every watched wallet is reached, and nil when NONE is —
    /// at zero connections the headline already said so, and listing all five
    /// wallets under it is the same fact twice.
    static func untouchedNote(_ names: [String], connectedCount: Int) -> String? {
        guard connectedCount > 0, !names.isEmpty else { return nil }
        if names.count == 1 {
            return String(localized: "Nothing connected reaches \(names[0]).")
        }
        return String(localized: "Nothing connected reaches \(names.joined(separator: ", ")).")
    }
}
