import Foundation
import SwiftData

/// ether.fi's unstake queue (2026-07-31) — the ETH you asked for and have to
/// go and COLLECT. Rides the watched wallets like Aave/Morpho/Aerodrome: no
/// account, no key, no connect switch, keyless `eth-mainnet` reads through
/// `WalletApprovals`' shared host pool.
///
/// Unstaking eETH does not return ETH. It burns the eETH and mints a
/// `WithdrawRequestNFT` — a claim ticket that sits in a queue for around ten
/// days, and then becomes claimable and STAYS there, silently, until someone
/// remembers to press a button. Nothing pushes that moment to you. That gap is
/// the whole feature, and it is not hypothetical: three of the first wallets
/// sampled while building this were sitting on finalized, unclaimed requests,
/// one of them for 5.50 ETH (measured 2026-07-31, ids #81111/#81112/#81114).
///
/// The row is a RECONCILING `dueAt` (the `ENSExpiry`/`AerodromeDeFi` shape) —
/// one thing per request, landed while it's still queued and RETITLED in place
/// when it turns claimable, never a second thing for the same request. The
/// queued row carries NO `dueAt` on purpose: ether.fi finalizes in batches at
/// its own pace, so any date this file printed would be invented. `dueAt` is
/// set exactly when the request actually becomes claimable — which is honest
/// (it IS due, now) and is what floats it into "What's coming up?".
///
/// MEASURED (2026-07-31, live against mainnet — every one of these fails
/// silently or wrongly if re-derived from the docs instead):
/// - `claimWithdraw` calls `_burn(tokenId)`, so **holding the NFT is exactly
///   "unclaimed"**. That makes `balanceOf(wallet)` a perfect one-call gate:
///   zero for almost everybody, and nothing else here runs.
/// - The contract is **NOT** `ERC721Enumerable` — `totalSupply()`,
///   `tokenOfOwnerByIndex` and `tokenByIndex` all revert, and
///   `supportsInterface(0x780e9d63)` returns false. There is no way to list a
///   holder's ids from the contract, hence the `Transfer`-log walk below.
/// - **`getClaimableAmount(tokenId)` REVERTS for a request that isn't
///   finalized yet** (custom error `0xd399e3e5`). The queued amount has to
///   come from `getRequest(tokenId).amountOfEEth` instead; calling the
///   claimable read first and treating the revert as "nothing there" would
///   silently hide every pending request.
/// - `isFinalized(id)` is the per-request truth and is NOT simply
///   `id <= lastFinalizedRequestId()` in this file's hands — the contract owns
///   that comparison (plus validity), so it is asked directly.
/// - `rpc.mevblocker.io` (already `eth-mainnet`'s first host here) served a
///   full-history `eth_getLogs` — 3.4M+ blocks, `fromBlock: 0` — in 0.37s,
///   while `ethereum-rpc.publicnode.com` caps at 50k blocks. The host order
///   this inherits is load-bearing, exactly as it is for Privacy Pools.
/// - The proxy first has code at block **18518781** (2023-11-07), so the
///   backward walk has a real floor instead of grinding to genesis.
///
/// Requests are also LOCKED MONEY, in native units, so `WalletComposition`
/// states them in its Locked tray ("2.4 ETH unstaking") — never priced, per
/// that type's rule 2.
enum EtherFiUnstake {

    /// `WithdrawRequestNFT` (proxy). The 2026-06-26 deployment record names an
    /// implementation; this is the address that is actually called.
    private static let withdrawNFT = "0x7d5706f6ef3F89B3951E23e557CDFBC3239D4E2c"
    private static let network = "eth-mainnet"

    /// The proxy's first block with code, binary-searched live. Bounds the
    /// backward `Transfer` walk — without it a wallet holding one ancient
    /// request would walk to genesis, one 900k chunk at a time, forever.
    private static let deployBlock = 18_518_781

    /// `Transfer(address indexed from, address indexed to, uint256 indexed
    /// tokenId)` — all three indexed on ERC-721, so the walk filters
    /// server-side on `to == wallet`.
    private static let transferTopic =
        "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

    /// Backward chunks walked per wallet per pass. A wallet whose requests are
    /// older than this catches up over later passes — `discovered` persists
    /// what each pass found, so the walk never restarts from the head.
    private static let maxChunksPerPass = 3

    /// Requests read per wallet per pass. Every measured holder was in single
    /// digits; a holder past this still gets their newest requests rather than
    /// a silent guess at the rest.
    private static let maxRequestsPerWallet = 12

    /// Which watched wallets actually hold an unstake request — the catalog
    /// seat's gate. A seat reading "ether.fi · watching 3 wallets" for someone
    /// who has never unstaked is fake status (the `GnosisPayBridge` rule).
    static let evidence = WalletSeatEvidence("etherfi.unstake.accounts")

    static func accounts() -> [String] { evidence.addresses }

    // MARK: - State

    private static func idsKey(_ address: String) -> String {
        "etherfi.unstake.ids.\(address.lowercased())"
    }
    private static func floorKey(_ address: String) -> String {
        "etherfi.unstake.floor.\(address.lowercased())"
    }

    /// Wallet unwatch takes the discovered-id cache, the walk floor and the
    /// seat mark with it — called from `WalletStore` beside the siblings'.
    static func clearState(address: String) {
        let a = address.lowercased()
        UserDefaults.standard.removeObject(forKey: idsKey(a))
        UserDefaults.standard.removeObject(forKey: floorKey(a))
        evidence.forget(a)
    }

    // MARK: - Book (live state)

    struct Request: Equatable, Sendable {
        let owner: String
        let tokenId: Int
        /// eETH committed to the queue, from `getRequest`. Present for a
        /// queued AND a claimable request.
        let amount: Double
        /// What `getClaimableAmount` says, once the request is finalized —
        /// nil while it is still queued (that read reverts, see the header).
        let claimable: Double?
        let isFinalized: Bool
    }

    struct Book: Equatable, Sendable {
        var requests: [Request] = []
        var isEmpty: Bool { requests.isEmpty }
        var claimable: [Request] { requests.filter(\.isFinalized) }
        var queued: [Request] { requests.filter { !$0.isFinalized } }
    }

    private static let cache = CoalescingCache<Book>()

    static func book(addresses: [String]) async -> Book? {
        guard !addresses.isEmpty else { return Book() }
        let key = addresses.map { $0.lowercased() }.sorted().joined(separator: ",")
        return await cache.value(key: key, ttl: 60) {
            await fetchBook(addresses: addresses)
        }
    }

    private static func fetchBook(addresses: [String]) async -> Book? {
        guard let head = await blockNumber() else { return nil }
        var book = Book()
        var reached = false

        for address in addresses {
            guard let count = await balanceOf(address) else { continue }
            reached = true
            // The gate. Almost every wallet stops here having spent exactly
            // one `eth_call`, and no log walk happens at all.
            guard count > 0 else {
                UserDefaults.standard.removeObject(forKey: idsKey(address))
                continue
            }
            let ids = await discoverIDs(address: address, want: count, head: head)
            for tokenId in ids.prefix(maxRequestsPerWallet) {
                guard let request = await fetchRequest(tokenId: tokenId, owner: address) else { continue }
                book.requests.append(request)
            }
        }
        return reached ? book : nil
    }

    /// The ids this wallet still holds. Cached ids are re-verified by
    /// `ownerOf` (a claim burns the token, and the ticket is transferable), a
    /// short forward scan catches newly minted ones, and only a wallet still
    /// short of `want` walks further back — bounded per pass and floored at
    /// the deploy block.
    private static func discoverIDs(address: String, want: Int, head: Int) async -> [Int] {
        let defaults = UserDefaults.standard
        let known = Set((defaults.array(forKey: idsKey(address)) as? [Int]) ?? [])
        // A cached id whose owner is no longer this wallet has been claimed or
        // moved on. Dropping it here is what stops a claimed request being
        // re-read (and re-titled) forever.
        var owned: Set<Int> = []
        for tokenId in known.sorted(by: >) {
            if await ownerOf(tokenId) == address.lowercased() { owned.insert(tokenId) }
        }

        let floor = (defaults.object(forKey: floorKey(address)) as? Int) ?? head
        var chunks = 0
        let range = WalletApprovals.maxLogRange(forNetwork: network) ?? 900_000

        // Forward first: anything minted since the last walk. Cheap, and it is
        // the only part that runs for an up-to-date wallet.
        if floor < head {
            for id in await transfersTo(address, from: floor, to: head) { owned.insert(id) }
        }
        var walkTo = min(floor, head)
        // …then backward, only while still short of what `balanceOf` promises.
        while owned.count < want, walkTo > deployBlock, chunks < maxChunksPerPass {
            let from = max(deployBlock, walkTo - range)
            for id in await transfersTo(address, from: from, to: walkTo) {
                if await ownerOf(id) == address.lowercased() { owned.insert(id) }
            }
            walkTo = from
            chunks += 1
            if from == deployBlock { break }
        }

        // Only advance the head-side mark once the backward walk is done, or a
        // wallet mid-walk would forget the range it still owes itself.
        if owned.count >= want || walkTo <= deployBlock {
            defaults.set(head, forKey: floorKey(address))
        }
        defaults.set(Array(owned).sorted(by: >), forKey: idsKey(address))
        return Array(owned).sorted(by: >)
    }

    private static func fetchRequest(tokenId: Int, owner: String) async -> Request? {
        guard let requestHex = await ethCall(
            data: selector("getRequest(uint256)") + padUint(tokenId)),
            let amountWord = word(requestHex, 0), let validWord = word(requestHex, 2)
        else { return nil }
        // `isValid` false means the request was invalidated (blacklist path) —
        // it is not money anyone is waiting on, so it never becomes a row.
        guard WalletIngest.hexToInt("0x" + validWord) != 0 else { return nil }
        // `amountOfEEth` is a uint96 in the struct's first word.
        let amount = WalletIngest.hexToDouble("0x" + amountWord) / 1e18
        guard amount > 0 else { return nil }

        var finalized = false
        if let hex = await ethCall(data: selector("isFinalized(uint256)") + padUint(tokenId)),
           let w = word(hex, 0) {
            finalized = WalletIngest.hexToInt("0x" + w) != 0
        }
        // Only ask once finalized — this reverts otherwise (see the header).
        var claimable: Double? = nil
        if finalized,
           let hex = await ethCall(data: selector("getClaimableAmount(uint256)") + padUint(tokenId)),
           let w = word(hex, 0) {
            let value = WalletIngest.hexToDouble("0x" + w) / 1e18
            if value > 0 { claimable = value }
        }
        return Request(owner: owner.lowercased(), tokenId: tokenId, amount: amount,
                       claimable: claimable, isFinalized: finalized)
    }

    // MARK: - Events

    /// Lands (or reconciles) one row per outstanding unstake request. Returns
    /// the landed count, nil when mainnet couldn't be reached at all.
    @MainActor
    static func syncEvents(context: ModelContext, addresses: [String],
                           existing: Set<String>) async -> Int? {
        guard !addresses.isEmpty else { return 0 }
        guard let book = await book(addresses: addresses) else { return nil }
        var added = 0

        for request in book.requests {
            // Stamped off the book, so it costs nothing extra, and never
            // unstamped on an empty read (`WalletSeatEvidence`'s
            // stamp-never-unstamp rule).
            evidence.remember(request.owner)

            let ref = "etherfi:unstake:\(request.owner):\(request.tokenId)"
            let ready = request.claimable ?? request.amount
            let fresh = request.isFinalized
                ? String(localized: "Your \(WalletIngest.format(ready)) ETH from ether.fi is ready to claim")
                : String(localized: "\(WalletIngest.format(request.amount)) ETH is unstaking from ether.fi — still in the queue")
            // A request becomes claimable exactly once, so the date is stamped
            // the first time this pass sees it finalized and then left alone —
            // re-stamping it every pass would keep resetting "when".
            let due: Date? = request.isFinalized ? .now : nil

            if existing.contains(ref) {
                guard let landed = try? context.fetch(FetchDescriptor<Thing>(
                    predicate: #Predicate { $0.sourceRef == ref })).first else { continue }
                if landed.title != fresh { landed.title = fresh }
                if request.isFinalized, landed.dueAt == nil { landed.dueAt = due }
                continue
            }
            let thing = Thing(kind: .link, title: fresh,
                              content: "https://app.ether.fi/withdraw",
                              source: "Wallet", capturedAt: .now, sourceRef: ref)
            thing.dueAt = due
            thing.walletAddress = request.owner
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }
        if added > 0 { _ = context.saveHonestly() }
        return added
    }

    // MARK: - RPC + ABI helpers

    private static func ethCall(data: String) async -> String? {
        await WalletApprovals.rpcRead(network: network, method: "eth_call",
                                      params: [["to": withdrawNFT, "data": data], "latest"]) as? String
    }

    private static func blockNumber() async -> Int? {
        guard let hex = await WalletApprovals.rpcRead(
            network: network, method: "eth_blockNumber", params: []) as? String
        else { return nil }
        return WalletIngest.hexToInt(hex)
    }

    private static func balanceOf(_ address: String) async -> Int? {
        guard let hex = await ethCall(
            data: selector("balanceOf(address)") + padAddress(address)),
            let w = word(hex, 0) else { return nil }
        return WalletIngest.hexToInt("0x" + w)
    }

    /// nil when the token has been burned (claimed) — `ownerOf` reverts, which
    /// surfaces here as a missing result rather than an address.
    private static func ownerOf(_ tokenId: Int) async -> String? {
        guard let hex = await ethCall(
            data: selector("ownerOf(uint256)") + padUint(tokenId)),
            let w = word(hex, 0), w.count == 64 else { return nil }
        let address = "0x" + String(w.suffix(40))
        return address == "0x" + String(repeating: "0", count: 40) ? nil : address
    }

    /// Request ids transferred TO this wallet in a block range — mints
    /// included, since a mint is `Transfer(0x0, requester, tokenId)`.
    private static func transfersTo(_ address: String, from: Int, to: Int) async -> [Int] {
        guard to >= from else { return [] }
        let params: [String: Any] = [
            "fromBlock": "0x" + String(from, radix: 16),
            "toBlock": "0x" + String(to, radix: 16),
            "address": withdrawNFT,
            "topics": [transferTopic, NSNull(), topic(address)],
        ]
        guard let logs = await WalletApprovals.rpcRead(
            network: network, method: "eth_getLogs", params: [params]) as? [[String: Any]]
        else { return [] }
        return logs.compactMap { log in
            guard (log["removed"] as? Bool) != true,
                  let topics = log["topics"] as? [String], topics.count >= 4 else { return nil }
            return WalletIngest.hexToInt(topics[3])
        }
    }

    private static func topic(_ address: String) -> String {
        "0x000000000000000000000000" + address.dropFirst(2).lowercased()
    }

    private static func selector(_ signature: String) -> String {
        Keccak256.hexString(Array(Keccak256.hash(Array(signature.utf8)).prefix(4)))
    }

    private static func padAddress(_ address: String) -> String {
        let hex = address.hasPrefix("0x") ? String(address.dropFirst(2)) : address
        return String(repeating: "0", count: max(0, 64 - hex.count)) + hex.lowercased()
    }

    private static func padUint(_ n: Int) -> String {
        let hex = String(n, radix: 16)
        return String(repeating: "0", count: max(0, 64 - hex.count)) + hex
    }

    private static func word(_ hex: String, _ n: Int) -> String? {
        let s = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        let start = n * 64, end = start + 64
        guard s.count >= end else { return nil }
        let i0 = s.index(s.startIndex, offsetBy: start)
        let i1 = s.index(s.startIndex, offsetBy: end)
        return String(s[i0..<i1]).lowercased()
    }

    #if DEBUG
    /// `-etherfiUnstakeProbe YES` — NSLogs each watched wallet's outstanding
    /// unstake requests (amount, queued vs claimable) or the honest miss, then
    /// runs the sync. ONE LINE PER REQUEST — a joined NSLog truncates past its
    /// length limit and hides later rows (the `-todayProbe` lesson). The
    /// queued/claimable split is printed because a count alone cannot tell
    /// "nothing is claimable yet" from "the finalized read didn't run", and
    /// that distinction IS this feature.
    @MainActor
    static func probe(context: ModelContext) async -> [String] {
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched).filter { ENS.isHexAddress($0) }
        guard !addresses.isEmpty else { return ["no EVM wallets watched"] }
        guard let book = await book(addresses: addresses) else { return ["book UNREACHABLE"] }
        var lines: [String] = []
        if book.isEmpty { lines.append("no unstake requests (a real empty queue, not a miss)") }
        for request in book.requests {
            let state = request.isFinalized
                ? "CLAIMABLE \(WalletIngest.format(request.claimable ?? request.amount)) ETH"
                : "queued"
            lines.append("\(WalletStore.shortAddress(request.owner)) #\(request.tokenId): \(WalletIngest.format(request.amount)) eETH — \(state)")
        }
        lines.append("queued=\(book.queued.count) claimable=\(book.claimable.count)")
        let landed = await syncEvents(context: context, addresses: addresses,
                                      existing: IngestSupport.existingSourceRefs(context, source: "Wallet"))
        lines.append("sync: \(landed.map(String.init) ?? "FAILED") landed")
        return lines
    }
    #endif
}
