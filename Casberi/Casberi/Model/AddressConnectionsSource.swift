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
        map(things: AddressActivity.relevant(in: context))
    }

    /// The same map from things ALREADY FETCHED (2026-08-22, prd §441).
    ///
    /// The manager opens by building this map and an activity summary, and
    /// both walked their own corpus fetch — two fetches, back to back, on the
    /// main actor, in `onAppear`, over overlapping predicates. `AddressActivity`
    /// fetches Wallet + Peer + Privacy Pools and this needs Wallet, a strict
    /// subset, so one walk answers both.
    ///
    /// The array is `.live` at its boundary by `relevant(in:)`'s own contract
    /// (corollary 4), which is why this may read stored properties without
    /// re-filtering.
    @MainActor
    static func map(things: [Thing]) -> Map? {
        let watched = WalletStore.shared.addresses.map {
            WatchedWallet(key: AddressBook.key(for: $0.address),
                          name: $0.label.isEmpty ? $0.short : $0.label)
        }
        guard watched.count >= minWallets else { return nil }
        return map(edges: edges(from: things), watched: watched)
    }

    /// Every landed transfer that could be a connection, OLDEST FIRST — the
    /// order `map` turns into node order.
    ///
    /// Reads every stored property behind a liveness check, at the boundary,
    /// once (corollary 4: the guarantee is made where the array is built, not
    /// promised to whoever reads it later).
    @MainActor
    static func edges(in context: ModelContext) -> [Edge] {
        edges(from: AddressActivity.relevant(in: context))
    }

    /// The same edges from things already fetched — see `map(things:)`.
    ///
    /// **Sorted here rather than trusted from the caller.** `AddressActivity`
    /// hands its array back NEWEST first (its own readings want that) and node
    /// order in the map is FIRST-DEALT order, which §295 rules is the one
    /// ordering this card may have. Taking the caller's order would silently
    /// reverse the spine — a card that renders perfectly and lists the newest
    /// relationship as the oldest.
    @MainActor
    static func edges(from things: [Thing]) -> [Edge] {
        var out: [Edge] = []
        for thing in things.sorted(by: { $0.capturedAt < $1.capturedAt }) {
            guard thing.source == "Wallet" else { continue }
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
                            // The landed spelling, unfolded — the door opens
                            // the address card with it, which prints it in full
                            // and compares it against look-alikes.
                            address: counterparty,
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
        // WHAT THE SCREEN DRAWS, not a sentence it no longer has. §448 cut
        // `headline`/`subhead` — the card counts its own rows — so the card is
        // gated on `connectedCount > 0` and a zero states itself in one line
        // instead. That comparison is mirrored here deliberately: the numbers
        // above cannot say by themselves whether a card is on screen, which is
        // the question this probe exists to answer.
        out.append(map.connectedCount > 0
                    ? "card: YES"
                    : "card: NO — the screen states \"No shared addresses yet.\"")
        for node in map.nodes {
            out.append("connRow| \(node.name) | transactions=\(node.count) "
                        + "| named=\(node.named ? "YES" : "NO") "
                        + "| wallets=\(node.walletKeys.count) "
                        // The door's destination. Printed because a node whose
                        // address never landed opens the wrong card silently.
                        + "| opens=\(node.address)")
        }
        // The undrawn tail, by name. `hiddenCount` alone cannot say whether the
        // cap is hiding a stranger you should name or six shops you already
        // know, and the newest connections are always the ones behind it.
        for name in map.hiddenNames {
            out.append("connHidden| \(name)")
        }
        for column in map.columns {
            out.append("connWallet| \(column.name) | "
                        + (column.usd.map { String(format: "$%.2f", $0) } ?? "unpriced"))
        }
        // §439's pairs — the reading the whole feature was asked for by name,
        // so its absence from this dump would be the probe missing the one
        // line the report was about.
        for link in map.walletLinks {
            out.append("connYours| \(link.a) <-> \(link.b)")
        }
        if let note = untouchedNote(map.untouchedWalletNames,
                                    connectedCount: map.connectedCount) {
            out.append("note: \(note)")
        }
        if let note = hiddenNote(hidden: map.hiddenCount, names: map.hiddenNames) {
            out.append("note: \(note)")
        }
        // Says whether the target is one of the DRAWN rows, because the bug
        // this replaced was exactly a target that existed and was unreachable.
        if let target = map.firstUnnamed {
            let drawn = map.nodes.contains { $0.id == target.id }
            out.append("button→ name \(target.name) (drawn=\(drawn ? "YES" : "NO"))")
        }
        return out
    }
}

/// What's new on the spine since you last looked (2026-08-22, prd §441).
///
/// **The one part of the sky that worked, kept.** §435 had `AddressSkySource`
/// hold a seen-set so a new link could draw itself LAST and dashed — the map
/// seen GROWING rather than arriving already grown. The sky went; this did not
/// deserve to go with it.
///
/// **UserDefaults, not a `Thing` field**, for the reason §435 gave and which is
/// unchanged: "have you looked at this" is a fact about THIS DEVICE'S SCREEN,
/// and seeing a connection on the iPhone must not make it old on the Mac. It is
/// also not worth a CloudKit Production deploy.
///
/// **First sight seeds SILENTLY.** A book with a year of history would
/// otherwise announce every relationship in it as today's news — the
/// Hyperliquid 2026-07-30 bug, which this project has now re-earned in enough
/// rooms that seeding-on-first-sight is the default assumption for any
/// what's-new ledger.
///
/// Held OUTSIDE `AddressConnections.Node` deliberately: that type is compiled
/// as shipped by `wallet-viz-selftest.sh` against fixtures that construct it
/// directly, and a field only a screen reads would make every one of those
/// fixtures carry a value the arithmetic never touches.
enum AddressConnectionsSeen {
    private static let key = "wallet.connections.seen.v1"
    private static let seededKey = "wallet.connections.seeded.v1"
    /// Bounded, because a book can gain connections forever and this is a
    /// cleartext preference. Far above any real book; the cap exists so the
    /// list cannot grow without limit, not because anyone will reach it.
    private static let cap = 400

    private static var seen: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
        set {
            UserDefaults.standard.set(Array(newValue.prefix(cap)), forKey: key)
        }
    }

    /// The connected addresses this device has never drawn.
    ///
    /// Returns EMPTY on first sight and records everything, so a corpus that
    /// predates the feature is never narrated as news.
    @MainActor
    static func unseen(in map: AddressConnections.Map?) -> Set<String> {
        guard let map else { return [] }
        // Over EVERY connection, not the drawn prefix: an address behind the
        // display cap that later rises into view has already been seen, and
        // re-dashing it would announce a relationship formed months ago.
        let all = Set(map.nodes.map(\.id)).union(map.hiddenNames.map { $0 })
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: seededKey) else {
            defaults.set(true, forKey: seededKey)
            seen = all
            return []
        }
        return all.subtracting(seen)
    }

    /// Marks what is on screen as seen — called once the card has actually
    /// BEEN drawn.
    ///
    /// Flagging at build time would make a new connection new for exactly as
    /// long as it took to compose the view and never let it draw itself as new
    /// at all (§435's own lesson, kept verbatim).
    @MainActor
    static func markSeen(_ ids: some Sequence<String>) {
        seen = seen.union(ids)
    }
}
