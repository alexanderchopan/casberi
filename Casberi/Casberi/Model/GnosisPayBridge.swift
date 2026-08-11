import Foundation
import SwiftData

/// Gnosis Pay — the Visa card whose spending settles ONCHAIN (2026-07-26, prd
/// §222). A Gnosis Pay account is a Safe on Gnosis Chain carrying a Roles
/// Module; every card purchase settles as a real ERC-20 transfer from that
/// Safe to Gnosis Pay's settlement Safe. That transfer is public, so the seat
/// RIDES the watched wallets exactly like Peer and Privacy Pools: no account,
/// no key, no connect switch — watching the wallet is the consent.
///
/// Honesty boundaries, by ruling (prd §222) — the copy must not overreach:
/// - CAPTURE ONLY. Nothing here spends, tops up, freezes a card, or signs.
/// - NO MERCHANT NAMES. The merchant, MCC and original currency live only
///   behind Gnosis Pay's authenticated API; the chain carries the amount and
///   the moment, nothing more. Rows say what was spent, never where.
/// - NO REFUNDS. Refunds and reversals settle off-chain (measured: zero
///   outbound transfers from the settlement Safe across 40k blocks), so this
///   is a record of card SPENDS, not a balanced ledger. No copy may imply
///   otherwise.
///
/// The API path was deliberately NOT built. It authenticates with SIWE, and
/// Gnosis Pay caps its JWTs at 24h with no refresh — a bridge needing a fresh
/// wallet signature every day. Gnosis Pay permits SIWE fine; Casberi is what
/// forbids it (prd §112: the WalletConnect session stays `methods=0 events=0`,
/// and signatures always happen elsewhere). If merchant names are ever wanted,
/// the §112-sanctioned shape is signing on casberi.app, not in the app.
///
/// MEASURED (2026-07-26, live against Gnosis Chain — do NOT "fix" any of the
/// three traps below without re-measuring; each one fails SILENTLY):
///  1. A ~25s SCAN TIMEOUT THAT RETURNS `[]`, NOT AN ERROR. This is a scan
///     budget, not a block-range cap — the trigger is how much work the node
///     does, and the failure is indistinguishable from "this card was never
///     used". Per-wallet, repeated twice per size: 250k blocks → 74 spends
///     (2.0s), 500k → 91 (3.5s), **750k → 0 (25.5s)** — except one gateway.fm
///     attempt that returned **111** in 18.4s, which is what proves the zero
///     is a lie rather than an answer. 1M and 1.5M → 0 every time, always
///     ~25s. Hence `maxRange` at less than half the last reliable size, and
///     chunking rather than one big call. Do NOT raise it because "500k
///     worked" — 500k worked at 3.5s on an unloaded node, and the budget is
///     spent in seconds, not blocks.
///  2. `fromBlock: 0` LIES, and so does any UNFILTERED read. Asking 0 → head
///     without a wallet topic returned 321 logs spanning only the last ~1000
///     blocks; a 250k unfiltered window returns ~303 of the ~82,000 that are
///     really there. Same class as the Farcaster graph walk that returned
///     "999 people wearing 'that's all'". With the wallet topic set, single
///     calls are EXACT and match a chunked sum at 100k/250k/500k — the
///     `from` filter is what makes this read honest, not just fast.
///  3. DECIMALS DIVERGE. EURe and GBPe are 18, **USDCe is 6**. Hardcoding 18
///     renders every dollar spend as ~$0.000000000001 — the SOL-decimals bug
///     wearing a different coin.
/// Also measured: one settlement Safe serves everyone (417 distinct user
/// Safes spending in a ~2h window), all spends route through one Spender
/// Modifier (`0x5f07734e…3f8a`, selector `0x8a320255`), both hosts below
/// answer batched JSON-RPC (20 blocks in 0.64s), and Gnosis Chain blocks run
/// ~5.16s. `gnosis-rpc.publicnode.com` 403s and `rpc.ankr.com/gnosis` demands
/// auth — hence this host pair, which differs from the siblings' on purpose.
enum GnosisPayBridge {

    /// The `Thing.source` every row here lands under — see
    /// `PeerBridge.sourceName` for why the room reads a constant rather than
    /// spelling its own copy.
    static let sourceName = "Gnosis Pay"

    private static let rpcs = ["https://rpc.gnosischain.com",
                               "https://rpc.gnosis.gateway.fm"]

    /// Well under the measured cliff (500k answered, 1M silently returned
    /// nothing). The margin is the point: the ceiling is a property of the
    /// hosts, not of us, and it moved once already.
    private static let maxRange = 250_000
    /// Blocks scanned per pass. A wallet further behind catches up over
    /// several passes — `scanned` persists even when the head isn't reached.
    private static let maxChunks = 4

    /// First sight looks back ~6 days, not to the deploy block. Two reasons,
    /// both deliberate: trap 2 makes a full-history walk impossible to ask
    /// for honestly, and a card is spent often enough (91 spends in 29 days
    /// on the measured wallet) that a long backfill would bury the feed on
    /// the day someone watches their wallet.
    private static let backfillBlocks = 100_000

    /// Gnosis Pay's settlement Safe — one address for every cardholder, so
    /// `to == settlement` is what separates a card spend from the person's
    /// own outbound transfer. Both `from` and `to` are indexed on ERC-20
    /// `Transfer`, so this filters server-side with zero false positives.
    static let settlement = "0x4822521e6135cd2599199c83ea35179229a172ee"

    /// `Transfer(address indexed from, address indexed to, uint256 value)`.
    private static let transferTopic =
        "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

    struct Spendable {
        let symbol: String
        let decimals: Int
        /// The ISO code the amount is really denominated in, so a spend reads
        /// "€42.50" rather than a token ticker nobody outside crypto knows.
        let currency: String
    }

    /// The only tokens a Gnosis Card Safe can spend. Keyed by lowercased
    /// contract address (the log's own `address` field).
    static let spendable: [String: Spendable] = [
        "0x420ca0f9b9b604ce0fd9c18ef134c705e5fa3430":
            Spendable(symbol: "EURe", decimals: 18, currency: "EUR"),
        "0x5cb9073902f2035222b9749f8fb0c9bfe5527108":
            Spendable(symbol: "GBPe", decimals: 18, currency: "GBP"),
        "0x2a22f9c3b484c3629090feed35f17ff8f88f76f0":
            Spendable(symbol: "USDCe", decimals: 6, currency: "USD"),
    ]

    // MARK: - The seat (automatic — rides the watched wallets)

    private static func cursorKey(_ address: String) -> String {
        "gnosispay.cursor.\(address.lowercased())"
    }

    /// Which watched wallets have actually spent on a Gnosis Pay card.
    ///
    /// DIVERGES from Peer and Privacy Pools on purpose: those seats light up
    /// for any watched wallet, because their read is meaningful for any
    /// address. A Gnosis Pay card is not — most wallets have no card at all,
    /// and a seat reading "Gnosis Pay · watching 3 wallets" for someone who
    /// has never held one is a fake status, which the honesty rule forbids.
    /// So the seat appears only once a spend has actually been seen.
    /// This bridge invented the evidence-mark shape on 2026-07-26; it was
    /// generalised into `WalletSeatEvidence` on 2026-07-30 when Morpho,
    /// Hyperliquid, Aerodrome and Uniswap gained seats of their own and Peer
    /// and Privacy Pools were converted to the same rule. Same key, same
    /// on-disk format — nothing to migrate.
    static let evidence = WalletSeatEvidence("gnosispay.accounts")

    static func accounts() -> [String] { evidence.addresses }

    /// Wallet unwatch takes this seat's cursor and its card-account mark with
    /// it — called from WalletStore beside the siblings'.
    static func clearState(address: String) {
        let a = address.lowercased()
        UserDefaults.standard.removeObject(forKey: cursorKey(a))
        evidence.forget(a)
    }

    // MARK: - Sync

    @MainActor private static var running = false

    /// Reads new card spends for the given (resolved, hex) addresses and
    /// lands them — called inside `WalletIngest.refresh`'s pass beside
    /// `PeerBridge.sync`, under that pass's running guard. Returns the landed
    /// count, nil when Gnosis Chain couldn't be reached at all.
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
            // LANDED. Keying it on new things loses the seat forever for
            // anyone who unwatches and re-watches: `clearState` drops the
            // mark, the re-scan finds the same spends, dedupe removes every
            // one, nothing lands — and the seat never comes back. A log that
            // passed this filter (from == wallet, to == settlement, on a
            // spendable token) IS a card spend by construction.
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

    /// `-gnosisPayProbe <blocksBack|YES>` — runs the sweep over the watched
    /// wallets headlessly. A numeric spec rewinds every cursor that many
    /// blocks below the head first, so real past spends land without waiting
    /// for someone to buy something. Pair with `-walletAddress <a card Safe>`.
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
            existing: IngestSupport.existingSourceRefs(context, source: "Gnosis Pay"))
        dumpRows(context: context)
        return n
    }

    /// One NSLog PER ROW, never one joined message — the log reader truncates
    /// a long multi-line NSLog mid-document (the `-todayProbe` lesson). A
    /// count alone can't tell a correct amount from one off by 12 decimal
    /// places, which is exactly the USDCe trap, so the probe has to show the
    /// money it actually wrote.
    @MainActor
    private static func dumpRows(context: ModelContext) {
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Gnosis Pay" },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.fetchLimit = 12
        let rows = (try? context.fetch(descriptor)) ?? []
        NSLog("[Casberi] gnosisPayRows: %d in corpus (newest %d shown)",
              (try? context.fetchCount(FetchDescriptor<Thing>(
                  predicate: #Predicate { $0.source == "Gnosis Pay" }))) ?? rows.count,
              rows.count)
        let stamp = ISO8601DateFormatter()
        for row in rows where row.isLive {
            NSLog("[Casberi] gnosisPayRow| %@ | %@ | %@ %@ | %@",
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

        // NO `suffix(N)` cap here — another deliberate divergence from the
        // sibling wallet paths. They cap to the newest 10 and advance the
        // cursor past the rest, which is fine when the event is rare. Card
        // spends are not rare, so capping would silently discard most of a
        // person's history the cursor then skips forever. The 6-day backfill
        // window is what bounds the first landing instead.
        let times = await blockTimes(blocks: spends.map(\.block))
        var out: [Thing] = []
        var seen = Set<String>()

        for spend in spends {
            let ref = "gnosispay:spend:\(spend.txHash.lowercased()):\(spend.logIndex)"
            guard !existing.contains(ref), seen.insert(ref).inserted else { continue }

            let amount = spend.raw / pow(10, Double(spend.token.decimals))
            // The fiat rendering is the honest one — these are euro/pound/
            // dollar stablecoins, and a card spend was a euro spend. The
            // token symbol stays on `transferAmount` for anyone who wants it.
            let money = PriceFormat.string(amount, currency: spend.token.currency)
                ?? "\(WalletIngest.format(amount)) \(spend.token.symbol)"
            let thing = Thing(
                kind: .transaction,
                title: String(localized: "Spent \(money) with Gnosis Pay"),
                content: "https://gnosisscan.io/tx/\(spend.txHash)",
                source: "Gnosis Pay",
                capturedAt: times[spend.block] ?? .now,
                sourceRef: ref)
            thing.walletAddress = wallet
            thing.transferAmount = "\(WalletIngest.format(amount)) \(spend.token.symbol)"
            thing.transferDirection = "sent"
            // Set BOTH, unlike the Privacy.com bridge which leaves them nil —
            // without these an amount can never be re-formatted or compared.
            thing.priceValue = amount
            thing.priceCurrency = spend.token.currency
            out.append(thing)
        }
        return out
    }

    // MARK: - RPC reads (Gnosis Chain public hosts, first that answers wins)

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

    /// Settlement transfers out of this wallet — every spendable token in one
    /// call, filtered server-side on both indexed topics. Do NOT split this
    /// per token; the token list is the `address` filter and one call is the
    /// whole read.
    private static func fetchSpends(wallet: String, from: Int,
                                    to: Int) async -> [[String: Any]]? {
        guard to - from <= maxRange else { return nil }   // trap 1, structurally
        let params: [String: Any] = [
            "fromBlock": hex(from), "toBlock": hex(to),
            "address": Array(spendable.keys),
            "topics": [transferTopic, topic(wallet), topic(settlement)],
        ]
        return await call(method: "eth_getLogs", params: [params]) as? [[String: Any]]
    }

    /// Block timestamps, BATCHED — one HTTP request for every block in the
    /// pass (measured: 20 blocks in 0.64s on both hosts). A per-block call
    /// would be one round trip per card spend, which for a 6-day backfill is
    /// dozens.
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
