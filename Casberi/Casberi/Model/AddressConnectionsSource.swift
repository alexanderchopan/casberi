import Foundation
import SwiftData

/// The reading half of the address book's connections card (prd §295) —
/// everything `AddressConnections` deliberately can't hold: `Thing`s, the book,
/// the watch list.
///
/// Split for the reason `WalletFlowSource` is split from `WalletFlow`: the
/// arithmetic's failure mode is a wrong COUNT that renders perfectly, so the
/// arithmetic is compiled as shipped by `scripts/wallet-viz-selftest.sh` and
/// can't be allowed to import anything.
///
/// ## No read here is new
///
/// Every fact comes off things already landed. `AddressActivity.history` walks
/// one address's transactions for the address card; this is the same walk
/// aggregated across the book. Nothing is fetched, nothing is priced, no
/// credit is spent — the card costs one corpus fetch and appears on a screen
/// that is already fetching.
///
/// This is also the ONLY place the card reads a `Thing`. Everything downstream
/// holds value types, so there is no stored property left to read after a
/// delete lands (CLAUDE.md corollaries 1–6).
extension AddressConnections {

    /// Builds the map from the corpus, or nil when the card can't say anything.
    @MainActor
    static func map(context: ModelContext) -> Map? {
        let watched = WalletStore.shared.addresses.map {
            WatchedWallet(key: AddressBook.key(for: $0.address),
                          name: $0.label.isEmpty ? $0.short : $0.label)
        }
        guard watched.count >= minWallets else { return nil }
        return map(edges: edges(in: context), watched: watched)
    }

    /// Every landed transfer that could be a connection, OLDEST FIRST — the
    /// order `map` turns into node order.
    ///
    /// Reads every stored property behind a liveness check, at the boundary,
    /// once (corollary 4: the guarantee is made where the array is built, not
    /// promised to whoever reads it later).
    @MainActor
    static func edges(in context: ModelContext) -> [Edge] {
        let fetched = (try? context.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Wallet" },
            sortBy: [SortDescriptor(\.capturedAt, order: .forward)]))) ?? []

        var out: [Edge] = []
        for thing in fetched.live {
            guard thing.kind == .transaction else { continue }
            // Spam never becomes a connection. An address-poisoning duster who
            // hits four of your wallets from one address would otherwise land
            // himself at the top of this card — on the screen where a person
            // is deciding whether an address is trustworthy, which is the worst
            // place in the app to hand an attacker a claim about you.
            if thing.isFlagged { continue }
            guard let counterparty = thing.counterpartyAddress, !counterparty.isEmpty,
                  let owner = thing.walletAddress, !owner.isEmpty else { continue }
            // Machinery is not a relationship. Uniswap is connected to every
            // wallet anybody owns, and a card that counted it would top out at
            // the same three names for everyone.
            if isMachinery(counterparty) { continue }

            let label = WalletIngest.knownLabel(for: counterparty)
            out.append(Edge(addressKey: AddressBook.key(for: counterparty),
                            addressName: label ?? WalletStore.shortAddress(counterparty),
                            named: label != nil,
                            walletKey: AddressBook.key(for: owner),
                            usd: thing.transferUSD))
        }
        return out
    }

    /// A contract, as far as anything already known can tell.
    ///
    /// Two sources, both already in the tree: the canonical table (routers,
    /// Seaport, the wrapped natives — which nothing may ever have added to the
    /// book), and the book's own chain-read kind, which covers every contract
    /// the table has never heard of.
    ///
    /// `.smartAccount` is deliberately NOT machinery (§294): it has bytecode,
    /// and it is somebody's wallet. Filing a Coinbase Smart Wallet with the
    /// routers is exactly the mislabelling that kind exists to undo.
    @MainActor
    private static func isMachinery(_ address: String) -> Bool {
        if WalletIngest.isKnownContract(address) { return true }
        return AddressBook.shared.entry(for: address)?.kind == .contract
    }

    /// `-connectionsProbe YES` — one line per fact, never joined (the
    /// `-todayProbe` truncation lesson).
    ///
    /// Reports the DECLINE as loudly as the draw, because an empty card has
    /// four causes that render as the same silence: fewer than two wallets
    /// watched, no landed transfers at all, transfers that all reach exactly
    /// one wallet (the honest common case), or an exclusion eating them — and
    /// only the last is a bug. The excluded tallies are what separate them in
    /// one launch.
    @MainActor
    static func probeLines(context: ModelContext) -> [String] {
        let watched = WalletStore.shared.addresses
        var out = ["watched=\(watched.count) (cap \(WalletStore.watchLimit))"]
        guard watched.count >= minWallets else {
            out.append("DECLINED: a connection needs two watched wallets; "
                        + "the card does not render")
            return out
        }

        // Recount the exclusions rather than reading them off `edges`, which
        // has already dropped them — a tally you can't see is the thing this
        // probe exists to make visible.
        let fetched = (try? context.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Wallet" }))) ?? []
        let transactions = fetched.live.filter { $0.kind == .transaction }
        let flagged = transactions.filter(\.isFlagged).count
        let machinery = transactions.filter {
            !$0.isFlagged && ($0.counterpartyAddress.map(isMachinery) ?? false)
        }.count
        let edges = edges(in: context)
        out.append("walletThings=\(transactions.count) edges=\(edges.count) "
                    + "excludedFlagged=\(flagged) excludedMachinery=\(machinery) "
                    + "priced=\(edges.filter { $0.usd != nil }.count)")

        guard let map = map(context: context) else {
            out.append("DECLINED: no map")
            return out
        }
        out.append("connected=\(map.connectedCount) drawn=\(map.nodes.count) "
                    + "hidden=\(map.hiddenCount)")
        out.append("headline: \(headline(count: map.connectedCount))")
        for node in map.nodes {
            out.append("connRow| \(node.name) | transactions=\(node.count) "
                        + "| named=\(node.named ? "YES" : "NO") "
                        + "| wallets=\(node.walletKeys.count)")
        }
        for column in map.columns {
            out.append("connWallet| \(column.name) | "
                        + (column.usd.map { String(format: "$%.2f", $0) } ?? "unpriced"))
        }
        if let note = untouchedNote(map.untouchedWalletNames,
                                    connectedCount: map.connectedCount) {
            out.append("note: \(note)")
        }
        if let target = map.firstUnnamed { out.append("button→ name \(target.name)") }
        return out
    }
}
