import Foundation
import SwiftUI

/// THE NFT SHELF'S TWO READS AND ITS STORE (2026-08-15, prd §387).
///
/// The pure half is `WalletNFTPicks.swift`; this file is everything that
/// touches the network, UserDefaults or the main actor.
///
/// ## The cost shape, which is the whole reason this feature could come back
///
/// §72/§124a's shelf was cut on 2026-07-19 in the commit whose message reads
/// "Alchemy went pay-as-you-go and hit quota, so cut its two biggest credit
/// sinks on the wallet path" — `getNFTsForOwner`, fanned per wallet × per chain
/// on every foreground, for a strip nobody used. Two things make the revival
/// cheaper than the thing that was cut, and both are structural rather than
/// tuned:
///
/// 1. **Detection is a read we already make.** `getContractsForOwner` has fired
///    on every wallet refresh since 2026-07-15 as the NFT spam allowlist, and
///    it returns collection name, artwork and held count in the SAME bytes the
///    allowlist throws away. `collections(for:)` and
///    `WalletIngest.ownedNFTContracts` are now one cached read with two
///    projections, so opening the picker costs nothing.
/// 2. **Display is bounded by a choice.** `getNFTsForOwner` is asked only for
///    picked contracts, only on chains that have a pick, only when the Wallet
///    room actually renders, and behind a window. Nothing picked means the read
///    never happens at all — which for most wallets is the permanent state.
///
/// So the marginal cost of this feature over the current tree is: zero for
/// anyone who never picks, and one narrow windowed read per wallet-room open
/// for anyone who does.
///
/// ## §216 applies and it lands on the same side as everything else here
///
/// Both reads report a STATE — which collections you hold, and which pieces are
/// in them — so both may be windowed. Neither is news. Contrast the keyless
/// event sweeps inside `WalletIngest.refresh` (a Peer fill, a Privacy Pools
/// clear), which §216 forbids windowing. Nothing in this file rides `refresh`.
///
/// ## UNMEASURED
///
/// Every field map here is doc-derived: no key on this host reaches
/// `*.g.alchemy.com`, and the shelf has never been drawn against a live wallet.
/// Every parse is optional-chained and every failure returns empty rather than
/// a wrong shelf, so it fails safe — but check `-nftCollectionsProbe` and
/// `-nftShelfProbe` against a real wallet before trusting a number on screen.
enum WalletNFTShelf {
    /// The EVM chains asked for collections, kept in ONE place now that two
    /// features read them.
    ///
    /// **Robinhood is included (2026-08-15, user's ruling).** The old allowlist
    /// asked five chains and skipped it on a guess — "Robinhood's NFT API may
    /// 404" — which meant a Robinhood collection could never be picked and,
    /// more quietly, was never spam-filtered either. Including it costs nothing
    /// when the guess is right: `fetchCollections` returns nil on a 404, the key
    /// stays absent, and `ownedNFTContracts` fails OPEN exactly as it did while
    /// the chain was omitted. If the guess is wrong, the chain works. An
    /// unverified 404 is not a reason to make a chain unreachable — it is a
    /// reason to let the read say so.
    ///
    /// Alchemy's NFT API is EVM-only, so a Solana-only wallet contributes no
    /// collections; the picker says so in words rather than showing an empty
    /// grid.
    static let networks = ["eth-mainnet", "base-mainnet", "arb-mainnet",
                           "opt-mainnet", "matic-mainnet", "robinhood-mainnet"]

    /// Alchemy network id → OpenSea's own chain path, for a piece's door.
    ///
    /// **Robinhood is deliberately absent**: OpenSea does not list that chain,
    /// so there is no door to open. A piece there draws as a picture with no
    /// tap rather than a link to an OpenSea page that would 404 — §83, and the
    /// §275 lesson specifically (a verb that looks live and lands nowhere is
    /// worse than no verb).
    private static let openSeaPath: [String: String] = [
        "eth-mainnet": "ethereum", "base-mainnet": "base",
        "arb-mainnet": "arbitrum", "opt-mainnet": "optimism",
        "matic-mainnet": "matic",
    ]

    /// How long a collection or piece read stays good for.
    ///
    /// Longer than `HoldingsCache`'s ten minutes on purpose: a portfolio's
    /// VALUE moves every block, while the set of collections a wallet holds
    /// changes when somebody buys something. Fifteen minutes is the window the
    /// original shelf's own cache used, kept for the same reason.
    static let window: TimeInterval = 15 * 60

    // MARK: - Detection (the read we already pay for)

    /// One (address, chain) pair's collections, or nil when the read FAILED.
    ///
    /// The nil is load-bearing and is why this returns an optional rather than
    /// an empty array: `WalletIngest.ownedNFTContracts` treats a missing key as
    /// "couldn't read" and fails OPEN, so an NFT on an unread chain is never
    /// dropped from the feed as spam. Collapsing a failure into `[]` would turn
    /// a flaky network into a silent spam filter.
    private actor CollectionCache {
        static let shared = CollectionCache()
        private var entries: [String: (at: Date, cols: [NFTCollection])] = [:]
        /// In-flight reads, so a foreground refresh and a picker opening in the
        /// same moment make one request rather than two.
        private var inFlight: [String: Task<[NFTCollection]?, Never>] = [:]

        func collections(address: String, network: String) async -> [NFTCollection]? {
            let key = WalletNFTShelf.ownerKey(address: address, network: network)
            if let hit = entries[key], hit.at.timeIntervalSinceNow > -window { return hit.cols }
            if let running = inFlight[key] { return await running.value }
            let task = Task { await WalletNFTShelf.fetchCollections(address: address, network: network) }
            inFlight[key] = task
            let result = await task.value
            inFlight[key] = nil
            // A failed read is never remembered — the `HoldingsCache` rule, so a
            // rate-limited miss can't pin an empty picker for fifteen minutes.
            if let result { entries[key] = (.now, result) }
            return result
        }

        func invalidate() {
            entries = [:]
        }
    }

    static func invalidateCache() async { await CollectionCache.shared.invalidate() }

    /// The key both projections of this read are filed under: "address|network".
    ///
    /// Address first, matching the shape `WalletIngest.ownedNFTContracts` has
    /// used since 2026-07-15 — its callers key on it, so keeping the order is
    /// what lets the allowlist become a projection of this read rather than a
    /// second one. Deliberately NOT `NFTPickKey`, which files a COLLECTION
    /// (network|contract); the two look alike and mean different things.
    static func ownerKey(address: String, network: String) -> String {
        "\(address.lowercased())|\(network)"
    }

    /// Every collection the given RESOLVED hex addresses hold, keyed
    /// "address|network" — the picker's list and the spam allowlist's source.
    ///
    /// A missing key means that (address, chain) could not be read. Present but
    /// empty means it was read and holds nothing, which is the common and
    /// correct answer for most wallets on most chains.
    static func collections(addresses: [String]) async -> [String: [NFTCollection]] {
        // THE DEMO REACHES NOTHING. The seeded wallet address is invented, so a
        // live read would spend two real requests per chain to be told an
        // address nobody owns holds nothing — and would then paint that
        // "nothing" as the honest answer for a room whose whole point is that
        // it looks furnished. Empty rather than a failure: a missing key means
        // "couldn't read" to `ownedNFTContracts`, and the demo's feed must not
        // inherit a spam filter that fails open on a read that never happened.
        if await DemoMode.isActive { return [:] }
        let evm = addresses.filter { ENS.isHexAddress($0) }
        guard !evm.isEmpty else { return [:] }
        let jobs = evm.flatMap { a in networks.map { (a, $0) } }
        let results = await IngestSupport.boundedGather(jobs, maxConcurrent: 4) { job in
            let (address, network) = job
            return (ownerKey(address: address, network: network),
                    await CollectionCache.shared.collections(address: address, network: network))
        }
        var out: [String: [NFTCollection]] = [:]
        for (key, cols) in results {
            guard let cols else { continue }   // failed read → key absent → callers fail open
            out[key] = cols
        }
        return out
    }

    /// One watched entry's collections, in picker order.
    ///
    /// Takes the entry's own address string (what the person typed — an ENS
    /// name, a hex address) and resolves it here, so callers never have to hold
    /// both forms. Empty for a Solana-only or unresolvable entry.
    @MainActor
    static func collections(for watched: String) async -> [NFTCollection] {
        let resolved = await WalletIngest.resolvedAddresses([watched])
        let byKey = await collections(addresses: resolved)
        return NFTCollectionOrder.sorted(byKey.values.flatMap { $0 })
    }

    /// Alchemy's `getContractsForOwner`, parsed for everything the response
    /// already carries. nil on any failure to reach or parse the envelope.
    ///
    /// Pages up to ~500 contracts, the original allowlist's bound — enough for a
    /// real collector, and a ceiling rather than unbounded paging on a wallet
    /// somebody dusted ten thousand times.
    private static func fetchCollections(address: String, network: String) async -> [NFTCollection]? {
        var out: [NFTCollection] = []
        var pageKey: String?
        var reached = false
        for _ in 0..<5 {
            var url = "https://\(network).g.alchemy.com/nft/v3/\(IngestSupport.alchemyKey)"
                + "/getContractsForOwner?owner=\(address)&pageSize=100"
            if let pageKey, let enc = pageKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                url += "&pageKey=\(enc)"
            }
            guard let root = await IngestSupport.getJSON(url) as? [String: Any],
                  let contracts = root["contracts"] as? [[String: Any]] else { break }
            reached = true
            for c in contracts {
                guard let addr = c["address"] as? String else { continue }
                let openSea = c["openSeaMetadata"] as? [String: Any]
                let image = c["image"] as? [String: Any]
                // The collection's own name, then the contract's, then the
                // address. Never blank: a nameless row is unpickable, since
                // there is nothing to recognise it by.
                let name = [(openSea?["collectionName"] as? String),
                            (c["name"] as? String),
                            (c["symbol"] as? String)]
                    .compactMap { $0 }
                    .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
                    ?? shortAddress(addr)
                let art = IngestSupport.imageURL(
                    (image?["thumbnailUrl"] as? String)
                        ?? (image?["cachedUrl"] as? String)
                        ?? (openSea?["imageUrl"] as? String))
                // See `NFTCountField` — measured, and every part of it earned:
                // distinct pieces rather than summed ERC-1155 quantities, read
                // out of a STRING, with an implausible value treated as unknown.
                let count = NFTCountField.count(distinct: c["numDistinctTokensOwned"],
                                                total: c["totalBalance"])
                out.append(NFTCollection(network: network,
                                         contract: addr.lowercased(),
                                         name: name,
                                         imageURL: art,
                                         count: count,
                                         isSpam: (c["isSpam"] as? Bool) == true))
            }
            guard let next = root["pageKey"] as? String, !next.isEmpty else { break }
            pageKey = next
        }
        return reached ? out : nil
    }

    private static func shortAddress(_ a: String) -> String {
        a.count > 10 ? "\(a.prefix(6))…\(a.suffix(4))" : a
    }

    // MARK: - The shelf's own narrow read

    /// One piece on the shelf. A door, not a `Thing` — nothing here lands in
    /// the corpus, which is §72's original ruling and is why this whole file
    /// needs no CloudKit deploy and raises no SwiftData liveness question.
    struct NFTPiece: Identifiable, Sendable, Equatable {
        let contract: String
        let tokenId: String
        let name: String
        let collection: String
        let imageURL: String
        let chainPath: String

        /// Empty when the chain has no OpenSea listing (Robinhood) — the piece
        /// still draws, it just has no door.
        var id: String { "\(chainPath.isEmpty ? network : chainPath):\(contract):\(tokenId)" }
        /// The Alchemy network id, so a doorless piece still knows where it is.
        let network: String
        /// Set ONLY for the demo's own pieces, which are drawn procedurally by
        /// `DemoNFTArt` instead of loaded from a URL — generated art, never a
        /// real collection's work (prd §387). nil for everything real.
        var demoSeed: Int? = nil
        var openSeaURL: URL? {
            guard !chainPath.isEmpty else { return nil }
            return URL(string: "https://opensea.io/assets/\(chainPath)/\(contract)/\(tokenId)")
        }
    }

    /// Alchemy caps `contractAddresses[]` at 45 per request, so a wallet with
    /// more picks than that on one chain is read in chunks rather than silently
    /// truncated (§307's rule: a refusal is counted, never quiet).
    private static let contractsPerRequest = 45

    /// How many pieces the shelf draws per wallet. A strip, not a gallery — the
    /// room's job is to say what you hold, and "and 40 more" is a door.
    static let pieceCap = 24

    private actor PieceCache {
        static let shared = PieceCache()
        private var entries: [String: (at: Date, pieces: [NFTPiece])] = [:]

        func pieces(key: String, read: () async -> [NFTPiece]?) async -> [NFTPiece] {
            if let hit = entries[key], hit.at.timeIntervalSinceNow > -window { return hit.pieces }
            guard let fresh = await read() else { return entries[key]?.pieces ?? [] }
            entries[key] = (.now, fresh)
            return fresh
        }

        func invalidate() { entries = [:] }
    }

    static func invalidatePieces() async { await PieceCache.shared.invalidate() }

    /// The pieces to draw for one watched wallet, or empty when it has no picks.
    ///
    /// The cache key carries the PICK SIGNATURE, not just the wallet — picking a
    /// new collection must not be served the previous set from the window, which
    /// would make the tap look broken for up to fifteen minutes.
    @MainActor
    /// The demo's own shelf — eight generated pieces across two invented
    /// collections (prd §387).
    ///
    /// **It reaches nothing**: no request, no asset, no URL. `DemoNFTArt` draws
    /// each one from its seed, so the demo shows what the feature LOOKS like
    /// without reproducing anybody's artwork or implying the seeded wallet owns
    /// real pieces.
    ///
    /// No door (`chainPath` empty), because these are not on OpenSea or
    /// anywhere else — a tile that opened a 404 would be the §275 dead verb in
    /// the one place somebody is deciding whether to trust the app.
    static let demoCollections = ["Field Notes", "Long Exposure"]

    static func demoPieces() -> [NFTPiece] {
        (0..<8).map { i in
            NFTPiece(contract: "0xdem0", tokenId: "\(i + 1)",
                     name: "\(demoCollections[i % 2]) #\(101 + i * 7)",
                     collection: demoCollections[i % 2],
                     imageURL: "", chainPath: "", network: "demo",
                     demoSeed: i)
        }
    }

    @MainActor
    static func pieces(for watched: String, book: NFTPickBook) async -> [NFTPiece] {
        // The demo SHOWS the shelf (so the feature is discoverable on a tour)
        // while still reaching nothing. Deliberately independent of the pick
        // book: the demo has no picker, so there is nothing for a pick to mean.
        if DemoMode.isActive { return demoPieces() }
        let nets = book.networks(wallet: watched)
        guard !nets.isEmpty else { return [] }
        guard let hex = (await WalletIngest.resolvedAddresses([watched]))
            .first(where: { ENS.isHexAddress($0) }) else { return [] }
        let signature = nets.map { "\($0):\(book.contracts(wallet: watched, network: $0).joined(separator: ","))" }
            .joined(separator: ";")
        let key = "\(hex.lowercased())|\(signature)"
        return await PieceCache.shared.pieces(key: key) {
            var out: [NFTPiece] = []
            var reachedAny = false
            for network in nets {
                let contracts = book.contracts(wallet: watched, network: network)
                for chunk in stride(from: 0, to: contracts.count, by: contractsPerRequest) {
                    let slice = Array(contracts[chunk..<min(chunk + contractsPerRequest, contracts.count)])
                    guard let got = await fetchPieces(address: hex, network: network, contracts: slice)
                    else { continue }
                    reachedAny = true
                    out += got
                }
            }
            // A pass that reached NOTHING returns nil so the cache serves the
            // last good shelf rather than blanking it — a wallet's pieces don't
            // vanish because one request timed out.
            return reachedAny ? Array(out.prefix(pieceCap)) : nil
        }
    }

    /// `getNFTsForOwner`, narrowed to picked contracts.
    ///
    /// Deliberately does NOT pass `excludeFilters[]=SPAM`, which the old shelf
    /// did: these contracts were named by the person, and honouring the vendor's
    /// spam guess over an explicit pick would empty a shelf somebody built on
    /// purpose, with nothing on screen to say why. A pick overrides the guess.
    private static func fetchPieces(address: String, network: String,
                                    contracts: [String]) async -> [NFTPiece]? {
        guard !contracts.isEmpty else { return [] }
        let filters = contracts
            .map { "&contractAddresses%5B%5D=\($0)" }
            .joined()
        let url = "https://\(network).g.alchemy.com/nft/v3/\(IngestSupport.alchemyKey)"
            + "/getNFTsForOwner?owner=\(address)&withMetadata=true"
            + "&pageSize=\(pieceCap)\(filters)"
        guard let root = await IngestSupport.getJSON(url) as? [String: Any],
              let owned = root["ownedNfts"] as? [[String: Any]] else { return nil }
        // Empty rather than defaulting to "ethereum": a wrong door is worse
        // than none, and this chain's pieces are not on OpenSea at all.
        let path = openSeaPath[network] ?? ""
        var out: [NFTPiece] = []
        for n in owned {
            guard let contract = n["contract"] as? [String: Any],
                  let contractAddr = contract["address"] as? String,
                  let tokenId = n["tokenId"] as? String,
                  let image = n["image"] as? [String: Any],
                  // A piece with no artwork is skipped: a shelf of grey squares
                  // says nothing, and the shelf's whole job is to be looked at.
                  let art = IngestSupport.imageURL(
                    (image["thumbnailUrl"] as? String) ?? (image["cachedUrl"] as? String))
            else { continue }
            let collection = ((contract["openSeaMetadata"] as? [String: Any])?["collectionName"] as? String)
                ?? (contract["name"] as? String) ?? ""
            let shortId = tokenId.count > 8 ? "\(tokenId.prefix(6))…" : tokenId
            let name = (n["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (collection.isEmpty ? "#\(shortId)" : "\(collection) #\(shortId)")
            out.append(NFTPiece(contract: contractAddr.lowercased(), tokenId: tokenId,
                                name: name, collection: collection,
                                imageURL: art, chainPath: path, network: network))
        }
        return out
    }
}

/// The picks, persisted.
///
/// One `NFTPickBook` behind an `ObservableObject`, so a tap in the picker
/// repaints the shelf without either side reaching for the other. UserDefaults
/// rather than a `Thing` field: a pick is a preference about how a room draws,
/// not something that happened — and a new stored property on `Thing` is a
/// CloudKit Production deploy (see the schema rule) for a fact that is
/// re-derivable from a tap.
@MainActor
final class WalletNFTStore: ObservableObject {
    static let shared = WalletNFTStore()

    private static let key = "wallet.nftPicks"

    @Published private(set) var book: NFTPickBook

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(NFTPickBook.self, from: data) {
            book = decoded
        } else {
            book = NFTPickBook()
        }
    }

    @discardableResult
    func toggle(wallet: String, collection: String) -> Bool {
        let on = book.toggle(wallet: wallet, collection: collection)
        persist()
        return on
    }

    func clear(wallet: String) {
        book.clear(wallet: wallet)
        persist()
    }

    /// Drops picks for wallets that are no longer watched. Called when the
    /// watch list changes, so an unwatch really forgets.
    func retain(wallets: [String]) {
        let before = book
        book.retain(wallets: wallets)
        if book != before { persist() }
    }

    func isPicked(wallet: String, collection: String) -> Bool {
        book.isPicked(wallet: wallet, collection: collection)
    }

    func hasPicks(wallet: String) -> Bool { book.hasPicks(wallet: wallet) }

    private func persist() {
        // Unpicking the last collection leaves NOTHING behind, rather than an
        // empty book — this is a preference somebody turned off, and a stored
        // `{}` is residue that outlives the decision.
        guard !book.isEmpty else {
            UserDefaults.standard.removeObject(forKey: Self.key)
            return
        }
        if let data = try? JSONEncoder().encode(book) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
