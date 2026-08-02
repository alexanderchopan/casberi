import Foundation
import SwiftData

/// Bitcoin (2026-07-27) — the third address family the Wallet seat reads,
/// beside EVM and Solana. An address is watched the same way (the paste
/// field in `WalletScreen`, gated on `BitcoinAddress.isAddress`), but the
/// read is its own arm: Bitcoin has no EVM-style RPC, no account model, and
/// no approval/DeFi surface at all — UTXOs and a public REST API (Esplora),
/// not JSON-RPC.
///
/// Keyless, via Esplora's own shape — mempool.space first, blockstream.info
/// second (measured 2026-07-27: identical JSON on `/address/<addr>`,
/// `/address/<addr>/txs`, `/tx/<txid>/status`, and `/fee-estimates`; only
/// `/v1/fees/recommended` is a mempool.space-only extension, which is why
/// the fee read below uses the shared `/fee-estimates` endpoint instead —
/// blockstream.info 404s the other one). `/blocks/tip/height` answers a bare
/// integer body, not a JSON object, so it can't ride `IngestSupport.getJSON`
/// (`JSONSerialization` refuses a top-level scalar with no `.fragmentsAllowed`
/// option — confirmed empirically, not assumed) — `rawInt` below is the one
/// place this file talks to `URLSession` directly, mirroring `LinkTitle`'s
/// same non-JSON-body pattern.
///
/// **What this bridge does NOT claim.** No merchant names (nothing to read —
/// a UTXO carries no counterparty identity at all, only addresses and
/// amounts). No Lightning: a Lightning address is LNURL-pay, and payments
/// over it are not publicly readable — there is nothing here to watch, so
/// the catalog copy says so rather than offering a dead field. No approvals,
/// no DeFi positions: Bitcoin has no approval surface and no Peer/0xBow/
/// Gnosis Pay analog to read.
///
/// **MEASURED 2026-07-27, don't "fix" without re-measuring:** (1) a busy
/// address's `/utxo` call 400s outright once it holds more than 500 UTXOs
/// ("Too many unspent transaction outputs… contact support") — `getJSON`
/// already returns nil on a non-200, so this fails open (no consolidation
/// insight lands) rather than crashing or lying about a count it can't read;
/// (2) `/address/<addr>/txs` (the default, no pagination cursor) returns the
/// **50 most recent** confirmed + mempool transactions, newest first — a
/// heavily used address can carry thousands, and walking full history would
/// bury the feed the same way an unbounded EVM backfill would (the GnosisPay
/// lesson, generalized); this bridge deliberately reads ONLY that bounded
/// recent page, every pass, and relies on ref-dedupe rather than a block-
/// style cursor, since Esplora has no cheap "since" filter to walk forward
/// from and a personal wallet's real gap between refreshes is a handful of
/// transactions, well inside one page; (3) JSON amounts (`value` on a vout,
/// `funded_txo_sum`/`spent_txo_sum`) are plain integers, satoshis, no string
/// wrapping — unlike the EVM legs' hex-encoded values elsewhere in this app.
enum BitcoinBridge {

    private static let hosts = ["https://mempool.space/api", "https://blockstream.info/api"]
    /// The public web explorer a landed thing's content links to — same host
    /// as the primary API, a plain `/tx/<txid>` permalink. Internal (not
    /// private) because `WalletIngest.chainName(forContent:)` matches on it
    /// to name the chain a landed transfer belongs to — kept as ONE constant
    /// so a chain can't reach the feed without also naming itself, the same
    /// anti-drift rule that function's own doc states.
    static let explorer = "https://mempool.space/tx/"

    /// The confirmation depth a receipt counts as SETTLED, not just seen —
    /// the number miners and exchanges both treat as final for a sizeable
    /// payment, and the one worth a distinct alert (item 2): "arrived" and
    /// "settled" are two different moments here, a day or more apart for a
    /// slow block, unlike every EVM/Solana transfer this app reads, which is
    /// either happened or not.
    static let settledConfirmations = 6

    // MARK: - Price (DeFiLlama, keyless, already used as the wallet's SPL
    // pricing backstop — `coingecko:bitcoin` is its own coin id, same host).

    static func priceUSD() async -> Double? {
        guard let root = await IngestSupport.getJSON(
            "https://coins.llama.fi/prices/current/coingecko:bitcoin") as? [String: Any],
              let coins = root["coins"] as? [String: Any],
              let btc = coins["coingecko:bitcoin"] as? [String: Any],
              let price = btc["price"] as? Double, price.isFinite, price > 0
        else { return nil }
        return price
    }

    // MARK: - Balance (folds into the combined USD total, `WalletIngest.holdings`)

    struct Stats {
        let fundedSats: Int
        let spentSats: Int
        let txCount: Int
        var balanceSats: Int { fundedSats - spentSats }
    }

    private static func addressStats(_ address: String) async -> Stats? {
        for host in hosts {
            guard let root = await IngestSupport.getJSON("\(host)/address/\(address)") as? [String: Any],
                  let chain = root["chain_stats"] as? [String: Any],
                  let funded = chain["funded_txo_sum"] as? Int,
                  let spent = chain["spent_txo_sum"] as? Int,
                  let txCount = chain["tx_count"] as? Int
            else { continue }
            let mempool = root["mempool_stats"] as? [String: Any]
            let mFunded = (mempool?["funded_txo_sum"] as? Int) ?? 0
            let mSpent = (mempool?["spent_txo_sum"] as? Int) ?? 0
            let mCount = (mempool?["tx_count"] as? Int) ?? 0
            return Stats(fundedSats: funded + mFunded, spentSats: spent + mSpent,
                        txCount: txCount + mCount)
        }
        return nil
    }

    /// The combined USD value of every watched Bitcoin address — folded into
    /// `bySymbol["BTC"]` the same way `SolanaStaking.stakedUSD` folds a stake
    /// balance in under `"SOL"`: a native holding with no ERC-20-shaped
    /// "token" object behind it. nil only when NEITHER the price nor any
    /// address could be read — a single unreachable address among several
    /// still counts the rest, matching every other multi-address fold here.
    static func balanceUSD(addresses: [String]) async -> Double? {
        guard !addresses.isEmpty, let price = await priceUSD() else { return nil }
        var totalSats = 0
        var reachedAny = false
        for address in addresses {
            guard let stats = await addressStats(address) else { continue }
            reachedAny = true
            totalSats += stats.balanceSats
        }
        guard reachedAny else { return nil }
        return Double(totalSats) / 100_000_000 * price
    }

    // MARK: - Activity sync

    @MainActor private static var running = false

    /// Reads the recent page of each watched address's activity and lands
    /// new sends/receives, then walks the pending-confirmation watchlist for
    /// any that just crossed into settled. Returns the landed count, nil
    /// when nothing could be reached at all.
    ///
    /// Takes the pass's `existing` refs set like every sibling arm — and
    /// unlike them, actually DEPENDS on it. Peer/Gnosis Pay/Privacy Pools
    /// dedupe cross-pass through their own persistent block cursors and
    /// treat that set as a same-pass safety net their differently-sourced
    /// refs could never match anyway (see `PeerBridge.sync`'s doc). This arm
    /// has no cursor — it re-reads the same bounded recent page every pass
    /// BY DESIGN (see the header) — so ref-dedupe is the real mechanism. It
    /// works because Bitcoin things land under `source: "Wallet"`, the same
    /// source the caller scoped that set to.
    @MainActor
    static func sync(context: ModelContext, addresses: [String],
                     existing: Set<String>) async -> Int? {
        guard !addresses.isEmpty else { return 0 }
        guard !running else { return 0 }
        running = true
        defer { running = false }
        return await syncLocked(context: context, addresses: addresses, existing: existing)
    }

    @MainActor
    private static func syncLocked(context: ModelContext, addresses: [String],
                                   existing: Set<String>) async -> Int? {
        guard let tip = await tipHeight() else { return nil }
        let price = await priceUSD()   // nil is fine — things still land, just unpriced
        var added = 0
        var reachedAny = false

        for address in addresses {
            guard let txs = await fetchTxs(address) else { continue }
            reachedAny = true
            var landed: [Thing] = []
            var freshlyPending: [String] = []

            for tx in txs {
                guard let txid = tx["txid"] as? String else { continue }
                let ref = activityRef(address: address, txid: txid)
                guard !existing.contains(ref), let net = netSats(tx: tx, address: address),
                      net != 0
                else { continue }
                let status = tx["status"] as? [String: Any]
                let confirmed = (status?["confirmed"] as? Bool) ?? false
                let blockHeight = status?["block_height"] as? Int
                let when: Date = (status?["block_time"] as? Double)
                    .map { Date(timeIntervalSince1970: $0) } ?? .now
                let amount = formatAmount(sats: abs(net))
                let received = net > 0
                let title = received
                    ? String(localized: "Received \(amount)")
                    : String(localized: "Sent \(amount)")
                let thing = Thing(kind: .transaction, title: title,
                                  content: explorer + txid, source: "Wallet",
                                  capturedAt: when, sourceRef: ref)
                thing.walletAddress = address
                thing.transferDirection = received ? "received" : "sent"
                thing.transferAmount = amount
                // The block as provenance (2026-07-27). A block is a NAMED
                // moment on Bitcoin — numbered, ~10 minutes wide, permanent —
                // in a way it simply isn't on a 2-second Base chain, where a
                // height is noise. It rides `transferVenue`, the same
                // un-renameable "where it happened" slot Solana's program
                // name uses, so `ThingStage` renders it with no new UI:
                // "Bitcoin · Block 959,701". An unconfirmed tx has no block
                // yet and honestly says so rather than showing a guess.
                thing.transferVenue = blockHeight.map {
                    String(localized: "Block \($0.formatted(.number.grouping(.automatic)))")
                } ?? String(localized: "In the mempool")
                if let price {
                    thing.priceValue = Double(abs(net)) / 100_000_000 * price
                    thing.priceCurrency = "USD"
                }
                landed.append(thing)

                // Only a tx that ISN'T already settled at first sight joins
                // the watchlist — deep history (thousands of confirmations)
                // needs no alert; only a receipt genuinely fresh right now
                // does. Mirrors PrivacyPoolsBridge's "a months-old approved
                // backfill never fakes a 'cleared!' moment" rule.
                let confirmations = confirmed ? max(0, tip - (blockHeight ?? tip) + 1) : 0
                if confirmations < settledConfirmations {
                    freshlyPending.append(txid)
                }
            }

            if !landed.isEmpty {
                for thing in landed {
                    context.insert(thing)
                    SpotlightIndex.index([thing])
                }
                guard context.saveHonestly() else { continue }
                added += landed.count
            }
            if !freshlyPending.isEmpty { addPending(address: address, txids: freshlyPending) }

            // The UTXO set — ONE fetch serving both the standing vintage and
            // the one-shot consolidation nudge. Skipped entirely in the
            // steady state: the pile of pieces can only change when a
            // transaction moves, so it's re-read when something landed this
            // pass, when nothing is cached yet, or while the nudge is still
            // unanswered. A quiet address costs zero requests here.
            let needsUTXOs = !landed.isEmpty
                || vintage(for: address) == nil
                || !existing.contains(consolidationRef(address))
            let utxoSet = needsUTXOs ? await utxos(address) : nil
            if let utxoSet { cacheVintage(address: address, utxos: utxoSet) }
            if let stats = await addressStats(address) {
                UserDefaults.standard.set(stats.balanceSats,
                                          forKey: "bitcoin.balance.\(address.lowercased())")
            }

            added += await landInsights(context: context, address: address,
                                        txs: txs, utxos: utxoSet, existing: existing)
        }

        added += await settlePending(context: context, tip: tip)
        added += await landHalving(context: context, tip: tip)
        return reachedAny ? added : nil
    }

    /// One vout/vin walk: the net satoshi change to `address` in this
    /// transaction — positive received, negative sent (spend amount plus
    /// the fee, the same net-effect-on-balance reading a bank statement
    /// gives). Zero for a pure self-consolidation (every input and output
    /// belongs to the same address) — nothing to report, so the caller skips
    /// it, matching how a same-asset self-route is dropped on the EVM side.
    private static func netSats(tx: [String: Any], address: String) -> Int? {
        guard let vin = tx["vin"] as? [[String: Any]],
              let vout = tx["vout"] as? [[String: Any]] else { return nil }
        var net = 0
        for out in vout {
            guard sameAddress((out["scriptpubkey_address"] as? String) ?? "", address),
                  let value = out["value"] as? Int else { continue }
            net += value
        }
        for input in vin {
            guard let prevout = input["prevout"] as? [String: Any],
                  sameAddress((prevout["scriptpubkey_address"] as? String) ?? "", address),
                  let value = prevout["value"] as? Int else { continue }
            net -= value
        }
        return net
    }

    /// Bech32 is lowercase by convention and case-INSENSITIVE as text;
    /// legacy/P2SH base58 is case-SENSITIVE (the same asymmetry `WalletStore`
    /// already keeps for EVM-vs-Solana). Esplora always answers a bech32
    /// address lowercased regardless of how it was watched.
    private static func sameAddress(_ a: String, _ b: String) -> Bool {
        guard !a.isEmpty else { return false }
        if a.lowercased().hasPrefix("bc1") { return a.lowercased() == b.lowercased() }
        return a == b
    }

    private static func activityRef(address: String, txid: String) -> String {
        "bitcoin:\(address.lowercased()):\(txid)"
    }

    /// Below this, an amount reads in SATS instead of BTC (2026-07-27).
    ///
    /// Not decoration — the denomination is doing legibility work, which is
    /// the §218 test for delight ("does structural work"). "0.00042 BTC"
    /// reads as nothing; "42,000 sats" reads as an amount. Above 0.01 the
    /// relationship inverts (100,000,000 sats is a wall of digits where
    /// "1 BTC" is a fact), so the switch is genuinely about which unit tells
    /// the truth more plainly at that magnitude, not about which is cuter.
    static let satsThreshold = 1_000_000   // 0.01 BTC

    /// "0.05 BTC" or "42,000 sats" — the unit that reads as an amount at
    /// this magnitude. Its own formatter, never `WalletIngest.format`, whose
    /// 4-decimal cap would round a typical sub-0.0001 BTC receipt to
    /// "0.0000" and read as nothing arriving at all.
    static func formatAmount(sats: Int) -> String {
        guard abs(sats) >= satsThreshold else {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.maximumFractionDigits = 0
            let grouped = f.string(from: NSNumber(value: sats)) ?? String(sats)
            return String(localized: "\(grouped) sats")
        }
        return "\(formatBTC(sats)) BTC"
    }

    /// Trimmed, full satoshi precision, no unit — for the callers that need
    /// the bare BTC number (`transferAmount`'s structured field, which the
    /// stage re-renders itself).
    private static func formatBTC(_ sats: Int) -> String {
        var s = String(format: "%.8f", Double(sats) / 100_000_000)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    // MARK: - Confirmation watchlist (item 2 — settlement as news)

    private static func pendingKey(_ address: String) -> String {
        "bitcoin.pending.\(address.lowercased())"
    }

    private static func addPending(address: String, txids: [String]) {
        let key = pendingKey(address)
        var known = Set((UserDefaults.standard.array(forKey: key) as? [String]) ?? [])
        known.formUnion(txids)
        UserDefaults.standard.set(Array(known), forKey: key)
    }

    /// Walks every watched address's pending list, lands a settlement alert
    /// for anything that has now reached `settledConfirmations`, and drops
    /// it from the list either way it resolves (settled, or the tx vanished
    /// from the mempool — a dropped/replaced tx has nothing left to wait
    /// for). Cheap by construction: a personal wallet's pending list is a
    /// handful of entries at most, each one `/tx/<id>/status` call.
    @MainActor
    private static func settlePending(context: ModelContext, tip: Int) async -> Int {
        var added = 0
        for entry in WalletStore.shared.addresses {
            let address = entry.address
            let key = pendingKey(address)
            let pending = (UserDefaults.standard.array(forKey: key) as? [String]) ?? []
            guard !pending.isEmpty else { continue }
            var stillPending: [String] = []
            for txid in pending {
                guard let status = await txStatus(txid) else { stillPending.append(txid); continue }
                guard status.confirmed, let height = status.height else {
                    stillPending.append(txid)   // still unconfirmed — keep watching
                    continue
                }
                let confirmations = max(0, tip - height + 1)
                guard confirmations >= settledConfirmations else {
                    stillPending.append(txid)
                    continue
                }
                let ref = "bitcoin:settled:\(address.lowercased()):\(txid)"
                guard !IngestSupport.hasSourceRef(context, source: "Wallet", ref: ref) else { continue }
                let thing = Thing(kind: .transaction,
                                  title: String(localized: "Your Bitcoin transfer settled (\(settledConfirmations)+ confirmations)"),
                                  content: explorer + txid, source: "Wallet",
                                  capturedAt: .now, sourceRef: ref)
                thing.walletAddress = address
                context.insert(thing)
                SpotlightIndex.index([thing])
                if context.saveHonestly() { added += 1 }
            }
            UserDefaults.standard.set(stillPending, forKey: key)
        }
        return added
    }

    // MARK: - The halving (the one scheduled event everyone shares)

    /// Blocks per halving epoch — consensus, not a tunable.
    private static let halvingInterval = 210_000

    /// How far ahead the halving becomes a row.
    ///
    /// Wider than `ENSExpiry`'s 90 days, deliberately. That horizon exists
    /// because "a deadline is news when it is near, and noise when it isn't"
    /// — and an admin deadline you can act on is news for about a quarter.
    /// The halving is a different animal: nobody can act on it, it is
    /// genuinely anticipated further out, and it recurs only every ~4 years,
    /// so even a 180-day window shows it for roughly 12% of the cycle rather
    /// than parking a row in the feed forever.
    private static let halvingHorizonDays = 180

    /// DEBUG override for the horizon (`-bitcoinHalvingHorizon <days>`), so
    /// the landing branch is verifiable today — the real next halving is
    /// ~90,000 blocks out, well past any shippable horizon, which would
    /// otherwise make this code unrunnable until 2028.
    static var halvingHorizonOverrideDays: Int?

    struct Halving {
        let height: Int
        let blocksRemaining: Int
        let estimated: Date
    }

    /// The next halving, computed off the tip this pass already fetched.
    ///
    /// **600 seconds per block, NOT the live average — a deliberate choice
    /// against the more precise-looking number.** mempool.space's
    /// `/v1/difficulty-adjustment` reports a real `timeAvg` (617.6s when
    /// measured 2026-07-27, i.e. blocks running ~3% slow), and using it
    /// would look more accurate while being less so: difficulty retargets
    /// every 2,016 blocks specifically to pull block time back to 600s, and
    /// a halving is up to 210,000 blocks — a hundred retargets — away.
    /// Extrapolating a two-week sample across that span projects a
    /// transient. 600s is what the protocol actively steers toward, so it is
    /// the honest long-horizon estimator. It also keeps this computation
    /// host-independent: `/v1/difficulty-adjustment` is mempool.space-only
    /// (blockstream.info 404s it, measured), and the halving must not go
    /// dark just because one host is down.
    static func nextHalving(tip: Int) -> Halving {
        let height = ((tip / halvingInterval) + 1) * halvingInterval
        let remaining = height - tip
        return Halving(height: height, blocksRemaining: remaining,
                       estimated: Date.now.addingTimeInterval(Double(remaining) * 600))
    }

    /// Lands — or reconciles — the halving row.
    ///
    /// The ENSExpiry shape exactly (prd §168's forward-deadline chip): the
    /// ref is the TARGET HEIGHT, stable for the whole epoch, and `dueAt`
    /// carries the date structurally so the "What's coming up?" chip and the
    /// brief's what's-next module both pick it up with no new surface. The
    /// estimate drifts as real blocks come in, so the row is reconciled in
    /// place every pass rather than re-landed — it quietly sharpens as the
    /// date approaches.
    ///
    /// No "in N days" in the title, for ENSExpiry's own recorded reason: a
    /// stored title would start lying the next morning.
    @MainActor
    private static func landHalving(context: ModelContext, tip: Int) async -> Int {
        let halving = nextHalving(tip: tip)
        let ref = "bitcoin:halving:\(halving.height)"
        let fresh = halvingTitle(halving)
        if let landed = try? context.fetch(
            FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef == ref })).first {
            if landed.dueAt != halving.estimated || landed.title != fresh {
                landed.dueAt = halving.estimated
                landed.title = fresh
                context.saveHonestly()
            }
            return 0
        }
        let horizonDays = halvingHorizonOverrideDays ?? halvingHorizonDays
        guard let horizon = Calendar.current.date(byAdding: .day, value: horizonDays, to: .now),
              halving.estimated <= horizon else { return 0 }
        // `.link`, NOT `.event` — the ENSExpiry precedent, and the reason is
        // an honesty one found on screen (2026-07-27): `.event` renders the
        // calendar sheet, which put the block URL in a "When" row and
        // captioned the halving "on your calendar". It is not on anyone's
        // calendar. A deadline-bearing row is a `.link` whose `dueAt` carries
        // the date structurally; the kind describes what the thing IS, and
        // this one is a pointer to a block that hasn't been mined yet.
        let thing = Thing(
            kind: .link,
            title: fresh,
            content: "https://mempool.space/block/\(halving.height)",
            source: "Wallet",
            capturedAt: .now,
            sourceRef: ref)
        thing.dueAt = halving.estimated
        context.insert(thing)
        SpotlightIndex.index([thing])
        return context.saveHonestly() ? 1 : 0
    }

    /// "The Bitcoin halving lands around March 2028, at block 1,050,000" —
    /// the date and the height are the facts. Past tense once it's happened,
    /// so a row can never sit in the feed claiming the future about
    /// something already done (the ENSExpiry lesson).
    private static func halvingTitle(_ h: Halving) -> String {
        let when = h.estimated.formatted(.dateTime.month(.wide).year())
        let height = h.height.formatted(.number.grouping(.automatic))
        return h.estimated < .now
            ? String(localized: "The Bitcoin halving has happened, at block \(height)")
            : String(localized: "The Bitcoin halving lands around \(when), at block \(height)")
    }

    // MARK: - Coin vintage (the oldest unspent piece)

    private static func vintageKey(_ address: String) -> String {
        "bitcoin.vintage.\(address.lowercased())"
    }

    /// The date of the OLDEST unspent piece of this address's balance, or nil
    /// when nothing is cached yet.
    ///
    /// Bitcoin is the only asset in this app whose balance is made of
    /// individually dated pieces: an ETH balance is one number with no
    /// history inside it, while a Bitcoin balance is a pile of UTXOs each
    /// stamped with the block that created it. So "how long have you held
    /// this" is a fact here and an unanswerable question everywhere else —
    /// which is exactly the kind of thing worth showing, and it costs ZERO
    /// extra requests: `/utxo` (already fetched for the consolidation
    /// nudge) carries `status.block_time` per entry.
    ///
    /// A standing line, not a moment: it changes honestly as coins are spent
    /// and received, so it must never fire a toast (a spend that consumes
    /// your oldest UTXO would "celebrate" your vintage going DOWN).
    static func vintage(for address: String) -> Date? {
        let t = UserDefaults.standard.double(forKey: vintageKey(address))
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    /// The cached balance in sats, for the address card's own line — written
    /// by the same sweep that writes the vintage so the two always agree.
    static func cachedBalanceSats(for address: String) -> Int? {
        let key = "bitcoin.balance.\(address.lowercased())"
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        return UserDefaults.standard.integer(forKey: key)
    }

    private static func cacheVintage(address: String, utxos: [[String: Any]]) {
        let times = utxos.compactMap { utxo -> Double? in
            guard let status = utxo["status"] as? [String: Any],
                  (status["confirmed"] as? Bool) == true,
                  let t = status["block_time"] as? Double, t > 0 else { return nil }
            return t
        }
        guard let oldest = times.min() else { return }
        UserDefaults.standard.set(oldest, forKey: vintageKey(address))
    }

    // MARK: - One-shot insights (the consolidation nudge and dormancy note)

    /// The consolidation nudge and the dormancy note — each lands AT MOST
    /// ONCE per address, ever (ref-deduped like everything else): a true
    /// fact worth stating once, not a live status worth restating every
    /// refresh. `txs` is the same recent page the caller already fetched for
    /// activity — the dormancy read is free.
    private static func consolidationRef(_ address: String) -> String {
        "bitcoin:utxo:\(address.lowercased())"
    }

    @MainActor
    private static func landInsights(context: ModelContext, address: String,
                                     txs: [[String: Any]],
                                     utxos: [[String: Any]]?,
                                     existing: Set<String>) async -> Int {
        var added = 0

        // Dormancy: the newest tx in the page IS the most recent activity —
        // Esplora returns newest-first regardless of total history size.
        let dormantRef = "bitcoin:dormant:\(address.lowercased())"
        if !existing.contains(dormantRef),
           let newest = txs.first,
           let status = newest["status"] as? [String: Any],
           (status["confirmed"] as? Bool) == true,
           let blockTime = status["block_time"] as? Double {
            let last = Date(timeIntervalSince1970: blockTime)
            let days = Date.now.timeIntervalSince(last) / 86400
            if days >= 180 {
                let thing = Thing(
                    kind: .transaction,
                    title: String(localized: "This address hasn't moved since \(last.formatted(.dateTime.month(.wide).year()))"),
                    content: explorer, source: "Wallet", capturedAt: .now, sourceRef: dormantRef)
                thing.walletAddress = address
                context.insert(thing)
                SpotlightIndex.index([thing])
                if context.saveHonestly() { added += 1 }
            }
        }

        // Consolidation: only when the UTXO read actually succeeded (a busy
        // address's own /utxo call 400s past 500 pieces — see the header) and
        // the fragmentation is real enough to be worth a nudge.
        let consolidateRef = consolidationRef(address)
        if !existing.contains(consolidateRef),
           let utxos, utxos.count >= 15,
           let rate = await feeRateSatPerVByte(), let price = await priceUSD() {
            // A rough mixed-input estimate (43 vbytes overhead + one output,
            // 68 vbytes per input — native SegWit's own weight, the median
            // real-world case) — a nudge, not a quote; `WalletPrepare`'s
            // `eth_estimateGas` reads are exact because the EVM will answer
            // that precisely, but Esplora's `/utxo` carries no script type
            // per entry, so an honest exact figure isn't available here.
            let estimatedVBytes = 43 + utxos.count * 68
            let feeSats = Double(estimatedVBytes) * rate
            let feeUSD = feeSats / 100_000_000 * price
            let thing = Thing(
                kind: .transaction,
                title: String(localized: "Your bitcoin balance sits in \(utxos.count) pieces — consolidating costs about \(PriceFormat.string(feeUSD, currency: "USD") ?? String(format: "$%.2f", feeUSD)) today"),
                content: explorer, source: "Wallet", capturedAt: .now, sourceRef: consolidateRef)
            thing.walletAddress = address
            context.insert(thing)
            SpotlightIndex.index([thing])
            if context.saveHonestly() { added += 1 }
        }

        return added
    }

    // MARK: - Wallet unwatch cleanup

    /// Wallet unwatch takes this seat's pending-confirmation list with it —
    /// mirrors every sibling bridge's `clearState`. The landed things and
    /// their one-shot insight refs stay (they're history, like every other
    /// bridge's landed activity); only the live watch state resets.
    static func clearState(address: String) {
        UserDefaults.standard.removeObject(forKey: pendingKey(address))
    }

    // MARK: - Esplora reads (mempool.space first, blockstream.info second)

    private static func fetchTxs(_ address: String) async -> [[String: Any]]? {
        for host in hosts {
            if let arr = await IngestSupport.getJSON("\(host)/address/\(address)/txs")
                as? [[String: Any]] { return arr }
        }
        return nil
    }

    private static func txStatus(_ txid: String) async -> (confirmed: Bool, height: Int?)? {
        for host in hosts {
            if let root = await IngestSupport.getJSON("\(host)/tx/\(txid)/status") as? [String: Any],
               let confirmed = root["confirmed"] as? Bool {
                return (confirmed, root["block_height"] as? Int)
            }
        }
        return nil
    }

    private static func utxos(_ address: String) async -> [[String: Any]]? {
        for host in hosts {
            if let arr = await IngestSupport.getJSON("\(host)/address/\(address)/utxo")
                as? [[String: Any]] { return arr }
        }
        return nil
    }

    /// The ~1-hour target (key `"6"`) from Esplora's shared `/fee-estimates`
    /// map (block-target → sat/vB) — NOT mempool.space's own
    /// `/v1/fees/recommended`, which blockstream.info 404s (measured
    /// 2026-07-27). A consolidation is never urgent, so the not-rushing rate
    /// is the honest one to quote.
    private static func feeRateSatPerVByte() async -> Double? {
        for host in hosts {
            guard let root = await IngestSupport.getJSON("\(host)/fee-estimates") as? [String: Any]
            else { continue }
            if let v = root["6"] as? Double, v.isFinite, v > 0 { return v }
            if let v = root["6"] as? Int { return Double(v) }
        }
        return nil
    }

    /// The chain tip's block height — served as a bare integer body by both
    /// hosts, not JSON, so it can't ride `IngestSupport.getJSON`.
    private static func tipHeight() async -> Int? {
        for host in hosts {
            if let h = await rawInt("\(host)/blocks/tip/height") { return h }
        }
        return nil
    }

    private static func rawInt(_ url: String) async -> Int? {
        guard let u = URL(string: url) else { return nil }
        var request = URLRequest(url: u)
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              let value = Int(text)
        else { return nil }
        return value
    }

    // MARK: - Probe

    /// `-bitcoinProbe <address>` — runs the sweep for one address directly
    /// (bypassing the watch list) and NSLogs everything: balance, tx count,
    /// landed things, pending confirmations, and the two insights' verdicts.
    @MainActor
    static func probe(context: ModelContext, address: String) async -> Int? {
        guard BitcoinAddress.isAddress(address) else {
            NSLog("[Casberi] bitcoinProbe: not a valid Bitcoin address")
            return nil
        }
        let kind = BitcoinAddress.scriptKind(address) ?? "?"
        let stats = await addressStats(address)
        let price = await priceUSD()
        NSLog("[Casberi] bitcoinProbe: %@ (%@) — %@ txs, balance %@ sats, BTC $%@",
              address, kind,
              stats.map { String($0.txCount) } ?? "UNREAD",
              stats.map { String($0.balanceSats) } ?? "UNREAD",
              price.map { String(format: "%.2f", $0) } ?? "UNREAD")
        // The halving math, logged EVERY run whether or not the row is
        // inside its horizon — otherwise this branch is unverifiable until
        // 2028 and the arithmetic would ship unchecked. Pair with
        // `-bitcoinHalvingHorizon 9999` to exercise the landing itself.
        if let tip = await tipHeight() {
            let h = nextHalving(tip: tip)
            NSLog("[Casberi] bitcoinHalving: tip %d → block %d in %d blocks, est %@ (horizon %d days)",
                  tip, h.height, h.blocksRemaining,
                  h.estimated.formatted(.dateTime.year().month().day()),
                  halvingHorizonOverrideDays ?? halvingHorizonDays)
        }
        for _ in 0..<60 where running {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        guard !running else { return 0 }
        running = true
        defer { running = false }
        let n = await syncLocked(
            context: context, addresses: [address],
            existing: IngestSupport.existingSourceRefs(context, source: "Wallet"))
        let pending = (UserDefaults.standard.array(forKey: pendingKey(address)) as? [String]) ?? []
        NSLog("[Casberi] bitcoinProbe: %@ landed; %d pending confirmation",
              n.map(String.init) ?? "FAILED", pending.count)
        NSLog("[Casberi] bitcoinVintage: %@ · balance %@",
              vintage(for: address).map {
                  $0.formatted(.dateTime.month(.wide).year())
              } ?? "UNREAD",
              cachedBalanceSats(for: address).map { formatAmount(sats: $0) } ?? "UNREAD")
        return n
    }
}
