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
/// ## A node is a door (2026-08-20)
///
/// Tapping a connected address opens the book's own address card — the same
/// screen its row on the book opens, showing the same `AddressActivity`
/// history this card counted. It stays inside the factual ruling because a
/// door asserts nothing: it goes where the card is already pointing. It also
/// gives an already-NAMED node somewhere to go, which the naming button below
/// (which skips them by definition) never could.
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
        /// The address as it actually LANDED, unfolded — carried beside the key
        /// because a node is a DOOR now (2026-08-20). The address card it opens
        /// prints this string in full, warns about look-alikes against it and
        /// builds its explorer link from it, so handing that screen the folded
        /// form would strip the EIP-55 checksum from the one surface whose
        /// whole job is telling two similar addresses apart. The key remains
        /// the identity; this is only ever displayed and passed onward.
        let address: String
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
        /// The unfolded address behind `id`, for the door. See `Edge.address`.
        let address: String
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

    /// TWO OF YOUR OWN WALLETS THAT HAVE DEALT WITH EACH OTHER DIRECTLY
    /// (prd §439).
    ///
    /// The reading this whole feature is named for and never had. Everything
    /// above is a SHARED COUNTERPARTY — "you both dealt with somebody else" —
    /// which is an inference about two wallets made through a third party. The
    /// plainest fact of all is the one it skipped: did money move between
    /// these two wallets, directly? It is in the same landed transfers the
    /// rest of this file reads, and nothing was looking for it, so somebody
    /// watching exactly two wallets that pay each other every week saw an
    /// empty picture and asked, correctly, what the diagram was even for.
    ///
    /// Ordered by the watch order, so a pair is one link and never two.
    struct WalletLink: Identifiable, Equatable {
        var id: String { "\(a)|\(b)" }
        let a: String
        let b: String
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
        /// The connected addresses that are COUNTED but not drawn, in the same
        /// first-dealt order the drawn ones are in (2026-08-20).
        ///
        /// They are named rather than only tallied because `nodeLimit` cuts by
        /// first-appearance order, which means the undrawn set is by
        /// construction the NEWEST connections — a relationship formed today
        /// can never enter the picture, and "2 more aren't drawn" was its only
        /// trace. Naming is what the card already does for an absence it can't
        /// draw (`untouchedWalletNames`), and it ranks nothing: the order is
        /// the order the drawing is in.
        let hiddenNames: [String]
        /// The first unnamed CONNECTED address — over every connection, drawn
        /// or not. Stored rather than computed off `nodes` (2026-08-20): it
        /// used to scan the drawn prefix alone, so once the six drawn addresses
        /// were all named the card's ONE action vanished while an unnamed
        /// connection sat undrawn behind the cap. A display cap is not an
        /// accounting rule, and it is not an action rule either.
        let firstUnnamed: Node?
        /// Pairs of YOUR wallets that have transacted with each other (§439).
        let walletLinks: [WalletLink]

        /// True when there is nothing connected. Not the same as the map being
        /// nil: nil means the card cannot say anything at all (fewer than two
        /// wallets watched), this means it can and the answer is none.
        var isEmpty: Bool { connectedCount == 0 && walletLinks.isEmpty }

        /// How many connected addresses are counted but not drawn. Stated by
        /// the card — the no-silent-caps rule. Derived from the COUNT rather
        /// than from `hiddenNames.count` so it stays an accounting statement:
        /// the two must agree, and the harness asserts they do.
        var hiddenCount: Int { max(0, connectedCount - nodes.count) }
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
        var byAddress: [String: (address: String, name: String, named: Bool,
                                 count: Int, wallets: [String])] = [:]
        // Your own wallets dealing with each other, collected as they go by
        // (§439). An edge whose COUNTERPARTY is itself a watched wallet is not
        // a third party at all — it is the two of them, and it belongs on the
        // ring between them rather than as a body floating off it.
        var linkedPairs: Set<String> = []
        var walletLinks: [WalletLink] = []
        let watchOrder = watched.map(\.key)

        for edge in edges {
            // An edge to a wallet we no longer watch is history about a watch
            // that ended — it can't contribute to a count phrased "your
            // wallets", and leaving it in would keep an unwatched wallet alive
            // in the picture.
            guard watchedKeys.contains(edge.walletKey) else { continue }
            // A transfer between an address and itself is not a relationship.
            guard edge.addressKey != edge.walletKey else { continue }

            // TWO OF YOURS. Recorded as a link and then dropped, so it can
            // never also become a `Node`: a watched wallet reaching two others
            // used to satisfy the connected test and be drawn a SECOND time on
            // the inner ring, wearing the same id as its own body on the outer
            // one — one wallet, two faces, and a duplicate key inside the
            // view's `ForEach`, which is the reused-id trap this project has a
            // crash class for. Found by asking what a direct link would do
            // (§439).
            if watchedKeys.contains(edge.addressKey) {
                // Ordered by the watch order so A-then-B and B-then-A are the
                // same link, recorded once.
                let ia = watchOrder.firstIndex(of: edge.addressKey) ?? 0
                let ib = watchOrder.firstIndex(of: edge.walletKey) ?? 0
                let pair = ia <= ib
                    ? WalletLink(a: edge.addressKey, b: edge.walletKey)
                    : WalletLink(a: edge.walletKey, b: edge.addressKey)
                if linkedPairs.insert(pair.id).inserted { walletLinks.append(pair) }
                continue
            }

            if byAddress[edge.addressKey] == nil {
                order.append(edge.addressKey)
                // The first SPELLING wins for the same reason the first name
                // does: a door that opens a differently-cased address between
                // two passes over identical data reads as broken.
                byAddress[edge.addressKey] = (edge.address, edge.addressName,
                                              edge.named, 0, [])
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
            connected.append(Node(id: key, address: entry.address,
                                  name: entry.name, count: entry.count,
                                  named: entry.named,
                                  // Rendered in YOUR watch order, not the order
                                  // the transfers happened to land in, so two
                                  // nodes' ribbons never cross for no reason.
                                  walletKeys: watched.map(\.key).filter { entry.wallets.contains($0) }))
        }

        guard !connected.isEmpty else {
            return Map(nodes: [], columns: [], connectedCount: 0,
                       untouchedWalletNames: watched.map(\.name),
                       hiddenNames: [], firstUnnamed: nil,
                       walletLinks: walletLinks)
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

        let drawn = Array(connected.prefix(nodeLimit))
        return Map(nodes: drawn,
                   columns: columns,
                   connectedCount: connected.count,
                   untouchedWalletNames: untouched,
                   hiddenNames: connected.dropFirst(drawn.count).map(\.name),
                   // Over every connection, never the drawn prefix — see the
                   // property's own doc for the action that used to disappear.
                   firstUnnamed: connected.first { !$0.named },
                   walletLinks: walletLinks)
    }

    // MARK: - The card's words

    // `headline` / `subhead` retired here 2026-08-22 (prd §448). The card
    // draws one row per connected address, so a sentence counting them was
    // the drawing read out loud — and `subhead` re-defined the word
    // "connected" under a section header that already carries it. The ZERO
    // case survives where it belongs: `WalletScreen.spineSection` draws no
    // card at all and states it in one tertiary line, which is §295's "none
    // IS an answer" without a card wrapped around the answer. `connectedCount`
    // stays — the notes below and the screen's own gate read it.

    /// How many undrawn connections are NAMED before the sentence gives up and
    /// counts the rest. Three, because a fourth name turns a caveat into a
    /// paragraph — and the count in front of them is the truth either way.
    static let hiddenNameLimit = 3

    /// The drawn-vs-counted gap, never silent — and named where it can be
    /// (2026-08-20). `hidden` always leads, so the sentence states the whole
    /// truth even when the list is trimmed to `hiddenNameLimit`.
    ///
    /// Order is `hiddenNames`' own, which is the drawing's own: naming is not
    /// ranking. Falls back to the bare count when nothing could be named,
    /// which keeps the note honest rather than absent.
    static func hiddenNote(hidden: Int, names: [String]) -> String? {
        guard hidden > 0 else { return nil }
        let shown = Array(names.prefix(hiddenNameLimit))
        guard !shown.isEmpty else {
            return hidden == 1
                ? String(localized: "1 more isn't drawn.")
                : String(localized: "\(hidden) more aren't drawn.")
        }
        let list = shown.joined(separator: ", ")
        let rest = hidden - shown.count
        if rest > 0 {
            return String(localized: "\(hidden) more aren't drawn: \(list) and \(rest) others.")
        }
        return hidden == 1
            ? String(localized: "1 more isn't drawn: \(list).")
            : String(localized: "\(hidden) more aren't drawn: \(list).")
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
