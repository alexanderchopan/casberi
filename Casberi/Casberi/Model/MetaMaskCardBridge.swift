import Foundation
import SwiftData

/// MetaMask Card — the Mastercard whose spending settles ONCHAIN (2026-09-20).
/// A cardholder grants an allowance to Baanx's "foxConnect" spender on Linea;
/// every purchase is that spender calling `transferFrom`, moving a stablecoin
/// from the person's own wallet to one settlement address. That transfer is
/// public, so the seat RIDES the watched wallets exactly like Gnosis Pay and
/// ether.fi Cash: no account, no key, no connect switch — watching the wallet
/// is the consent.
///
/// This is the THIRD seat on the same shape, and the shape is the reason it is
/// buildable at all: `GnosisPayBridge` proved the pattern, `EtherFiCash`
/// proved it generalised, and everything below that differs from them differs
/// because Linea measured differently, not because it was written fresh.
///
/// Honesty boundaries — the copy must not overreach:
/// - CAPTURE ONLY. Nothing here spends, tops up, freezes a card, changes a
///   spending cap, or signs.
/// - NO MERCHANT NAMES. The merchant, MCC category, fees, the card's last four
///   and the pending/declined/reversed status live only behind Baanx's
///   authenticated API (`GET /v1/card/transactions`, OAuth + PKCE against
///   MetaMask's own client id). The chain carries the amount, the token and
///   the moment, and nothing else. Rows say what was spent, never where.
/// - NO REFUNDS. A refund is a credit on Baanx's books; nothing measured here
///   settles back out of the settlement address to a cardholder. This is a
///   record of card SPENDS, not a balanced ledger.
///
/// The API path was deliberately NOT built, and for a sharper reason than
/// Gnosis Pay's. Gnosis Pay's API wanted a SIWE signature, which prd §112
/// forbids in-app; Baanx's wants MetaMask's own OAuth client id. Reaching it
/// would mean this app presenting itself as MetaMask to Baanx — which is not
/// the §701 shape (a session cookie the person owns, handed over by the person)
/// but impersonation of another app's client. There is no version of that we
/// would ship, so the ceiling above is permanent rather than pending.
///
/// The addresses below are NOT guessed and must not be edited from memory.
/// They come from MetaMask's own repo — `metamask-mobile`,
/// `app/selectors/featureFlagController/card/defaults.ts`, the fallback for
/// the `cardFeature` remote flag — which names the spender per chain and the
/// exact supported-token list. It is a REMOTE flag, so MetaMask can move these
/// without shipping: re-read that file before trusting a stale constant, and
/// treat a seat that suddenly lands nothing as that first.
///
/// MEASURED (2026-09-20, live against Linea — every number below was read, not
/// assumed):
///  1. HOSTS DISAGREE WILDLY, and most of the obvious ones are unusable.
///     `linea.drpc.org` caps `eth_getLogs` at 10k on its free plan and refused
///     every range tried; `linea-rpc.publicnode.com` calls a 2,000-block
///     lookback an "archive request" needing a token; `1rpc.io/linea` caps at
///     **50 blocks**; `linea.blockpi.network` 521s; `blastapi`, `onfinality`
///     and `therpc.io` did not answer at all. The two hosts below are what
///     survived, and they agree exactly (239 / 971 / 1114 logs at 2k / 9k /
///     10k). Do not add a host to this list without running that comparison.
///  2. THE RANGE CEILING IS HONEST HERE, unlike Gnosis Chain's. `rpc.linea.
///     build` caps at 10,000 and ERRORS (`range 20000 exceeds limit of 10000`)
///     rather than returning `[]`; Tenderly has no cap at all and answered
///     100,000 blocks (11,319 logs). So the silent-zero trap that shaped
///     `GnosisPayBridge` does not exist on this chain. `maxRange` sits under
///     the STRICTER host's cap anyway, because a pair that answers different
///     questions is worse than a pair that answers one.
///  3. A FILTERED READ IS EXACT. One call over 9,000 blocks and a three-way
///     chunked sum of the same span both returned 970 — so, as on Gnosis
///     Chain, the `from` topic is what makes this read honest and not merely
///     fast. Never drop it.
///  4. DECIMALS DIVERGE, and were verified on chain rather than trusted from
///     the flag file: USDC/USDT/aUSDC/mUSD/amUSD are 6, **WETH/EURe/GBPe are
///     18**. Every one matched `decimals()`. Hardcoding 18 would render every
///     dollar spend as ~$0.000000000001 — Gnosis Pay's USDCe trap exactly.
///  5. A LINEA BLOCK IS ~8.8s, not the ~2s the chain is usually described
///     with. Measured three ways (200 / 2,000 / 20,000-block spans: 8.54,
///     7.57, 8.93) and again at 60,000 blocks = 6.1 days. Every block-count
///     constant here is derived from that, so re-measure before changing one.
/// Also measured: one settlement address serves every non-US cardholder (444
/// distinct wallets spending in a ~23h window, 973 spends), the US programme
/// uses a second one (36 in the same window), an OR-array in the `to` topic
/// reads both in ONE call and its count equals the two separate reads summed
/// (1,006 = 970 + 36) on both hosts, and both hosts answer batched JSON-RPC
/// (20 blocks in 0.20s / 0.35s).
enum MetaMaskCardBridge {

    /// The `Thing.source` every row here lands under. Its own room, like
    /// ether.fi Cash and unlike the retired DeFi seats: this is a card, not a
    /// wallet reading, and prd §515 forbids a seat whose rows land under
    /// another seat's source.
    static let source = "MetaMask Card"

    /// The pair that survived trap 1. Tenderly is already this app's fallback
    /// shape on Optimism (`EtherFiCash`), so it is a known quantity rather
    /// than a host picked for having answered once.
    private static let rpcs = ["https://rpc.linea.build",
                               "https://linea.gateway.tenderly.co"]

    /// Under `rpc.linea.build`'s measured 10,000 cap, so BOTH hosts answer the
    /// same question (trap 2). Raising this past 10,000 would silently make
    /// the pair asymmetric — Tenderly would serve it, the primary would error,
    /// and which one you got would depend on which answered first.
    private static let maxRange = 9_000

    /// Blocks scanned per pass. 7 × 9,000 = 63,000, just over the backfill, so
    /// a first sight completes in one pass; a wallet further behind catches up
    /// over several, because `scanned` persists even when the head isn't
    /// reached.
    private static let maxChunks = 7

    /// First sight looks back ~6 days (measured: 60,000 blocks = 6.1 days),
    /// not to the deploy block — Gnosis Pay's reasoning, and the same number
    /// by coincidence of block time rather than by copying: a card is spent
    /// often enough that a long backfill would bury the feed on the day
    /// someone watches their wallet.
    private static let backfillBlocks = 60_000

    /// Where a swipe's money lands. `to == settlement` is what separates a
    /// card spend from the person's own outbound transfer, and both `from` and
    /// `to` are indexed on ERC-20 `Transfer`, so this filters server-side with
    /// no false positives to clean up afterwards.
    ///
    /// TWO addresses, because MetaMask runs two card programmes — the global
    /// one and a separate US one, each behind its own foxConnect spender
    /// (`0x9dd23A4a…` and `0xA90b298d…` respectively). Both are read in one
    /// call via an OR-array in the topic (measured: 1,006 = 970 + 36). A
    /// person holds one card or the other, never both, so this costs nothing
    /// and removes a whole class of "the seat works except in America".
    static let settlements = ["0x8dfe562cbb4e93d5029f39da26bb6b501a8d1d3e",
                              "0x2baa8380b362682bd373448f2f99842ed9aca24a"]

    /// `Transfer(address indexed from, address indexed to, uint256 value)`.
    private static let transferTopic =
        "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

    struct Spendable {
        let symbol: String
        let decimals: Int
        /// The ISO code the amount is really denominated in, so a spend reads
        /// "€42.50" rather than a ticker nobody outside crypto knows.
        ///
        /// NIL FOR WETH, and that is the honesty rule rather than an omission
        /// (prd §83). The other seven tokens here are fiat stablecoins, so the
        /// token amount IS the money and rendering it as money is true. Ether
        /// is not: turning 0.0031 WETH into a dollar figure needs a price at
        /// the moment of the swipe, which the chain does not carry and this
        /// pass does not fetch. So a WETH spend shows the token amount and
        /// sets no `priceValue` — a row that says nothing about dollars rather
        /// than one that says something false about them.
        let currency: String?
    }

    /// The only tokens a MetaMask Card can spend on Linea, keyed by lowercased
    /// contract address (the log's own `address` field). This IS the `address`
    /// filter for the read, so an unlisted token cannot land as a spend — and
    /// that is deliberate: the settlement address is the card's, but a token
    /// outside the card's own list arriving there is something this seat has
    /// not measured and must not name.
    ///
    /// Decimals verified against each contract's `decimals()`, not copied from
    /// the flag file (trap 4). `aUSDC` and `amUSD` answer `symbol()` as
    /// `aLinUSDC` and `aLinmUSD` on chain; the shorter names are MetaMask's
    /// own, which is what the cardholder saw when they enabled the token.
    static let spendable: [String: Spendable] = [
        "0x176211869ca2b568f2a7d4ee941e073a821ee1ff":
            Spendable(symbol: "USDC", decimals: 6, currency: "USD"),
        "0xa219439258ca9da29e9cc4ce5596924745e12b93":
            Spendable(symbol: "USDT", decimals: 6, currency: "USD"),
        "0xaca92e438df0b2401ff60da7e4337b687a2435da":
            Spendable(symbol: "mUSD", decimals: 6, currency: "USD"),
        "0x374d7860c4f2f604de0191298dd393703cce84f3":
            Spendable(symbol: "aUSDC", decimals: 6, currency: "USD"),
        "0x61b19879f4033c2b5682a969cccc9141e022823c":
            Spendable(symbol: "amUSD", decimals: 6, currency: "USD"),
        "0x3ff47c5bf409c86533fe1f4907524d304062428d":
            Spendable(symbol: "EURe", decimals: 18, currency: "EUR"),
        "0x3bce82cf1a2bc357f956dd494713fe11dc54780f":
            Spendable(symbol: "GBPe", decimals: 18, currency: "GBP"),
        "0xe5d7c2a44ffddf6b295a15c148167daaaf5cf34f":
            Spendable(symbol: "WETH", decimals: 18, currency: nil),
    ]

    // MARK: - The seat (automatic — rides the watched wallets)

    private static func cursorKey(_ address: String) -> String {
        "metamaskcard.cursor.\(address.lowercased())"
    }

    /// Which watched wallets have actually spent on a MetaMask Card.
    ///
    /// Same rule as Gnosis Pay and ether.fi Cash: most wallets hold no card,
    /// and a seat reading "MetaMask Card · watching 3 wallets" for someone who
    /// has never held one is a fake status, which the honesty rule forbids. So
    /// the seat appears only once a spend has actually been seen.
    static let evidence = WalletSeatEvidence("metamaskcard.accounts")

    static func accounts() -> [String] { evidence.addresses }

    /// Wallet unwatch takes this seat's cursor and its card-account mark with
    /// it — called from WalletStore beside the siblings'. A stale mark would
    /// keep the seat lit for a card whose wallet is gone.
    static func clearState(address: String) {
        let a = address.lowercased()
        UserDefaults.standard.removeObject(forKey: cursorKey(a))
        evidence.forget(a)
    }

    // MARK: - Sync

    @MainActor private static var running = false

    /// Reads new card spends for the given (resolved, hex) addresses and lands
    /// them — called inside `WalletIngest.refresh`'s pass beside
    /// `GnosisPayBridge.sync`, under that pass's running guard. Returns the
    /// landed count, nil when Linea couldn't be reached at all.
    @MainActor
    static func sync(context: ModelContext, addresses: [String],
                     existing: Set<String>) async -> Int? {
        guard !running else { return 0 }
        running = true
        defer { running = false }
        return await syncLocked(context: context, addresses: addresses,
                                existing: existing)
    }

    @MainActor
    private static func syncLocked(context: ModelContext, addresses: [String],
                                   existing: Set<String>) async -> Int? {
        guard !addresses.isEmpty else { return 0 }
        guard let latest = await blockNumber() else { return nil }
        let defaults = UserDefaults.standard
        var added = 0

        for address in addresses {
            let key = cursorKey(address)
            let cursor = (defaults.object(forKey: key) as? Int)
                ?? max(0, latest - backfillBlocks) - 1
            guard latest > cursor else { continue }
            var from = cursor + 1
            let budget = maxRange * maxChunks
            if latest - from >= budget { from = latest - budget + 1 }
            var scanned = from - 1
            var logs: [[String: Any]] = []
            while scanned < latest {
                let to = min(scanned + maxRange, latest)
                guard let chunk = await fetchSpends(wallet: address,
                                                    from: scanned + 1, to: to)
                else { break }   // transient — keep the cursor, retry next pass
                logs += chunk
                scanned = to
            }
            guard scanned > cursor else { continue }

            // The card-account mark keys on spends FOUND, not on things
            // LANDED — Gnosis Pay's rule, and for its reason: keying it on new
            // things loses the seat forever for anyone who unwatches and
            // re-watches, because `clearState` drops the mark, the re-scan
            // finds the same spends, dedupe removes every one, nothing lands,
            // and the seat never comes back. A log that passed this filter
            // (from == wallet, to == a settlement, on a card token) IS a card
            // spend by construction.
            if !logs.isEmpty { evidence.remember(address) }

            let landed = await things(from: logs, wallet: address, existing: existing)
            if !landed.isEmpty {
                for thing in landed {
                    context.insert(thing)
                    SpotlightIndex.index([thing])
                }
                // Land and SAVE before advancing (the WalletApprovals rule) —
                // a cursor that runs ahead of a failed save loses the spends
                // it skipped, permanently.
                guard context.saveHonestly() else { continue }
                added += landed.count
            }
            defaults.set(scanned, forKey: key)
        }
        return added
    }

    /// `-metamaskCardProbe <blocksBack|YES>` — runs the sweep over the watched
    /// wallets headlessly. A numeric spec rewinds every cursor that many blocks
    /// below the head first, so real past spends land without waiting for
    /// someone to buy something. Pair with `-walletAddress <a cardholder>`.
    @MainActor
    static func probe(context: ModelContext, blocksBack: Int?) async -> Int? {
        for _ in 0..<60 where running {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        guard !running else { return 0 }
        running = true
        defer { running = false }
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched)
            .filter { ENS.isHexAddress($0) }
        if let back = blocksBack, let latest = await blockNumber() {
            for address in addresses {
                UserDefaults.standard.set(max(0, latest - back) - 1,
                                          forKey: cursorKey(address))
            }
        }
        let n = await syncLocked(
            context: context, addresses: addresses,
            existing: IngestSupport.existingSourceRefs(context, source: source))
        dumpRows(context: context)
        return n
    }

    /// One NSLog PER ROW, never one joined message — the log reader truncates a
    /// long multi-line NSLog mid-document (the `-todayProbe` lesson). A count
    /// alone can't tell a correct amount from one off by 12 decimal places,
    /// which is exactly trap 4, so the probe has to show the money it wrote.
    @MainActor
    private static func dumpRows(context: ModelContext) {
        let name = source
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == name },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.fetchLimit = 12
        let rows = (try? context.fetch(descriptor)) ?? []
        NSLog("[Casberi] metamaskCardRows: %d in corpus (newest %d shown)",
              (try? context.fetchCount(FetchDescriptor<Thing>(
                  predicate: #Predicate { $0.source == name }))) ?? rows.count,
              rows.count)
        let stamp = ISO8601DateFormatter()
        for row in rows where row.isLive {
            NSLog("[Casberi] metamaskCardRow| %@ | %@ | %@ %@ | %@",
                  stamp.string(from: row.capturedAt),
                  row.title,
                  row.priceValue.map { String(format: "%.2f", $0) } ?? "—",
                  row.priceCurrency ?? "—",
                  row.content)
        }
    }

    /// The probe's status line — which watched wallets are card accounts.
    static func accountSummary() -> String {
        let known = accounts()
        guard !known.isEmpty else { return "no card accounts seen" }
        return "\(known.count) card account\(known.count == 1 ? "" : "s"): "
            + known.map { WalletStore.shortAddress($0) }.joined(separator: ", ")
    }

    // MARK: - Landing spends

    private struct Spend {
        let token: Spendable
        let raw: Double
        let block: Int
        let txHash: String
        let logIndex: Int
    }

    @MainActor
    private static func things(from logs: [[String: Any]], wallet: String,
                               existing: Set<String>) async -> [Thing] {
        var spends: [Spend] = []
        for log in logs {
            guard (log["removed"] as? Bool) != true,
                  let contract = (log["address"] as? String)?.lowercased(),
                  let token = spendable[contract],
                  let txHash = log["transactionHash"] as? String,
                  let blockHex = log["blockNumber"] as? String,
                  let indexHex = log["logIndex"] as? String,
                  let data = log["data"] as? String
            else { continue }
            spends.append(Spend(token: token,
                                raw: WalletIngest.hexToDouble(data),
                                block: WalletIngest.hexToInt(blockHex),
                                txHash: txHash,
                                logIndex: WalletIngest.hexToInt(indexHex)))
        }
        guard !spends.isEmpty else { return [] }

        // NO `suffix(N)` cap here — Gnosis Pay's divergence, for its reason.
        // The sibling wallet paths cap to the newest 10 and advance the cursor
        // past the rest, which is fine when the event is rare. Card spends are
        // not rare, so capping would silently discard most of a person's
        // history the cursor then skips forever. The 6-day backfill window is
        // what bounds the first landing instead.
        let times = await blockTimes(blocks: spends.map(\.block))
        var out: [Thing] = []
        var seen = Set<String>()

        for spend in spends {
            let ref = "metamaskcard:spend:\(spend.txHash.lowercased()):\(spend.logIndex)"
            guard !existing.contains(ref), seen.insert(ref).inserted else { continue }

            let amount = spend.raw / pow(10, Double(spend.token.decimals))
            let tokenAmount = "\(WalletIngest.format(amount)) \(spend.token.symbol)"
            // The fiat rendering is the honest one for the seven stablecoins —
            // a card spend in USDC was a dollar spend. WETH has no currency,
            // so it keeps the token amount and claims nothing about money.
            let money = spend.token.currency
                .flatMap { PriceFormat.string(amount, currency: $0) } ?? tokenAmount
            let thing = Thing(
                kind: .transaction,
                title: String(localized: "Spent \(money) with MetaMask Card"),
                content: "https://lineascan.build/tx/\(spend.txHash)",
                source: source,
                capturedAt: times[spend.block] ?? .now,
                sourceRef: ref)
            thing.walletAddress = wallet
            thing.transferAmount = tokenAmount
            thing.transferDirection = "sent"
            // Set BOTH or NEITHER. Without them an amount can never be
            // re-formatted or compared — but a WETH spend has no currency to
            // set, and a `priceValue` with no `priceCurrency` reads as dollars
            // everywhere downstream.
            if let currency = spend.token.currency {
                thing.priceValue = amount
                thing.priceCurrency = currency
            }
            out.append(thing)
        }
        return out
    }

    // MARK: - RPC reads (Linea public hosts, first that answers wins)

    private static func call(method: String, params: [Any]) async -> Any? {
        let body: [String: Any] = ["id": 1, "jsonrpc": "2.0",
                                   "method": method, "params": params]
        for rpc in rpcs {
            if let root = await IngestSupport.postJSON(rpc, body: body) as? [String: Any],
               let result = root["result"], !(result is NSNull) {
                return result
            }
        }
        return nil
    }

    private static func blockNumber() async -> Int? {
        guard let hex = await call(method: "eth_blockNumber", params: []) as? String
        else { return nil }
        return WalletIngest.hexToInt(hex)
    }

    /// Settlement transfers out of this wallet — every card token and BOTH
    /// programmes in one call, filtered server-side on both indexed topics.
    /// Do NOT split this per token or per settlement address; the token list is
    /// the `address` filter, the two settlements are an OR-array in the `to`
    /// topic, and one call is the whole read (measured: the OR count equals
    /// the two separate reads summed).
    private static func fetchSpends(wallet: String, from: Int,
                                    to: Int) async -> [[String: Any]]? {
        guard to - from <= maxRange else { return nil }   // trap 2, structurally
        let params: [String: Any] = [
            "fromBlock": hex(from), "toBlock": hex(to),
            "address": Array(spendable.keys),
            "topics": [transferTopic, topic(wallet), settlements.map(topic)],
        ]
        return await call(method: "eth_getLogs", params: [params]) as? [[String: Any]]
    }

    /// Block timestamps, BATCHED — one HTTP request for every block in the
    /// pass (measured: 20 blocks in 0.20s and 0.35s on the two hosts). A
    /// per-block call would be one round trip per card spend, which for a
    /// 6-day backfill is dozens.
    private static func blockTimes(blocks: [Int]) async -> [Int: Date] {
        let wanted = Array(Set(blocks)).sorted(by: >)
        guard !wanted.isEmpty else { return [:] }
        var out: [Int: Date] = [:]
        for slice in stride(from: 0, to: wanted.count, by: 50).map({
            Array(wanted[$0..<min($0 + 50, wanted.count)])
        }) {
            let body: [[String: Any]] = slice.enumerated().map { i, block in
                ["id": i, "jsonrpc": "2.0", "method": "eth_getBlockByNumber",
                 "params": [hex(block), false]]
            }
            var rows: [[String: Any]]?
            for rpc in rpcs {
                if let r = await IngestSupport.postJSONArray(rpc, body: body) {
                    rows = r
                    break
                }
            }
            // The batch answers in whatever order it likes, so read the block
            // number off each RESULT rather than trusting position.
            for row in rows ?? [] {
                guard let result = row["result"] as? [String: Any],
                      let numberHex = result["number"] as? String,
                      let ts = result["timestamp"] as? String else { continue }
                out[WalletIngest.hexToInt(numberHex)] =
                    Date(timeIntervalSince1970: WalletIngest.hexToDouble(ts))
            }
        }
        return out
    }

    /// An address as a 32-byte indexed log topic.
    private static func topic(_ address: String) -> String {
        "0x000000000000000000000000" + address.dropFirst(2).lowercased()
    }

    private static func hex(_ n: Int) -> String { "0x" + String(n, radix: 16) }
}
