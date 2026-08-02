import Foundation
import SwiftData

/// Railgun — onchain privacy read at its two public doors (2026-08-01, prd
/// §252). Railgun is a shielded pool: you SHIELD tokens into its contract,
/// move them privately inside as encrypted notes, and UNSHIELD back out to a
/// public address. Railgun's own docs are explicit that shields and unshields
/// are the only interactions carrying public information — everything between
/// them is readable only by the holder of a spending or viewing key.
///
/// So this bridge reads exactly the two doors, and never claims to see the
/// room. It rides the watched wallets like Peer, Privacy Pools and Gnosis
/// Pay: no account, no key, no connect switch — watching the wallet is the
/// consent (prd §207).
///
/// **The structural difference from Privacy Pools, and why this file looks
/// like Gnosis Pay instead.** 0xBow's Entrypoint indexes the depositor, so one
/// filtered read of ITS OWN event answers "did this wallet deposit". Railgun's
/// events (`Shield`, `Unshield`, `Transact`, `Nullified`) index NOTHING —
/// there is no wallet topic to filter on, and an unfiltered read of them
/// truncates (the Gnosis Pay lesson) and couldn't be attributed anyway. But
/// none of that matters, because a shield MOVES A TOKEN: it emits a plain
/// ERC-20 `Transfer(from: wallet, to: railgun)`, indexed on both sides. That
/// is the same server-side two-topic filter Gnosis Pay uses for card spends,
/// and it is exact.
///
/// Two reads, one landing pass:
///  1. SHIELDS — `Transfer(from: wallet, to: railgun)`. "Shielded 1.2 WETH
///     into Railgun." Unambiguous: the watched wallet signed it.
///  2. UNSHIELDS — the same filter reversed. This is the differentiated read,
///     and the reason this seat is worth having: the sender inside the pool is
///     unknowable BY DESIGN, so an unshield is the one shape in which someone
///     can pay you privately and Casberi can still show the money arriving.
///
/// Honesty boundaries, by ruling (prd §252) — the copy must not overreach:
/// - CAPTURE ONLY. Nothing here shields, unshields, proves, or signs.
/// - **NEVER NAME A SENDER.** An unshield arriving at a watched wallet has
///   TWO indistinguishable causes — you withdrawing your own funds, or someone
///   paying you — and the chain cannot tell them apart. That is the product
///   working, not a gap in the read. So the title states only what is
///   observable ("Received 500 USDC from Railgun") and `enrichedText` says
///   plainly that the sender is private. A title claiming "You unshielded"
///   would be a fake status (§83) in the one domain where believing it costs
///   money.
/// - **PRIVATE ACTIVITY IS INVISIBLE, AND THAT IS THE POINT.** Transfers,
///   swaps and balances inside the pool are never read, never estimated, and
///   never implied. Reading them would need the viewing key and a full note
///   scan — see "not built" below.
/// - **ONLY A DIRECT MOVE IS ATTRIBUTABLE, AND THAT IS ABOUT HALF OF THEM.**
///   Measured, and the single most important fact about this bridge: 51.5% of
///   shields (3,245 of 6,306 over 500k blocks) reach the pool from Railgun's
///   RelayAdapt contract rather than from the person's own address — that's
///   every native-ETH shield (the ETH arrives as `msg.value` and RelayAdapt
///   wraps it, so no user→adapter `Transfer` log exists AT ALL) plus every
///   multicall/relayer shield. In those the depositor appears only as
///   `tx.from`, which is in no topic and therefore cannot be filtered on at
///   any price. Recovering them means one `eth_getTransactionByHash` per
///   candidate transaction over an UNSCOPED read of everyone's shields —
///   thousands of calls per pass, and hopeless for a backfill — so this reads
///   the direct half and the copy says exactly that. Showing half of someone's
///   history while implying it is all of it is the failure this note exists to
///   prevent. A relayed shield is not LOST: the wallet's own outbound leg
///   already lands through `WalletIngest`'s activity sweep, unlabelled, as a
///   transfer to a contract.
///
/// NOT BUILT, deliberately: the private balance. Reading it means scanning
/// every `Transact` commitment ever emitted and trial-decrypting each against
/// a viewing key — Railgun's own engine, in TypeScript, ported to Swift. That
/// is a project, not a bridge, and a viewing key in this app would also
/// undercut "watching can never move funds" as the thing people trust here.
///
/// UNMEASURED where marked — see the `MEASURED` block below for what was
/// checked live and what was taken from documentation. Every read is a GET-
/// shaped JSON-RPC call and every failure path returns nil into existing
/// behaviour, so this fails safe: a wrong constant makes the seat go quiet,
/// never wrong.
enum RailgunBridge {

    /// Mainnet only for now. Railgun also runs on BSC, Polygon and Arbitrum;
    /// each has its own contract addresses and its own host reliability to
    /// measure, and the Privacy Pools precedent is to add chains only after
    /// measuring them the way mainnet was — never by pattern-matching an
    /// address table.
    ///
    /// Host order is Privacy Pools', not `WalletApprovals`' mainnet pair, and
    /// deliberately so: this is a topic-filtered `eth_getLogs` over a wide
    /// range, which is exactly the read `publicnode` token-walls and `drpc`
    /// caps at 10k blocks.
    private static let rpcs = ["https://rpc.mevblocker.io",
                               "https://eth.api.onfinality.io/public"]

    /// Blocks per `eth_getLogs` call.
    ///
    /// **The Gnosis Pay silent-truncation trap is ABSENT here, measured, and
    /// that is why this is 500k rather than that bridge's cautious 250k.**
    /// Gnosis Chain's hosts answer an over-large range with `[]`, which reads
    /// identically to "this wallet never used the product". These two do not:
    /// the limit is 10,000 RESULTS, not a block count, and crossing it is a
    /// loud JSON-RPC error (mevblocker `-32005`, which even names the
    /// sub-range to retry; onfinality `-32002` timeout). An error returns nil
    /// from `fetchTransfers`, which breaks the chunk loop and LEAVES THE
    /// CURSOR, so the range is retried rather than skipped.
    ///
    /// The result cap also can't bind on the reads this file actually issues:
    /// it was hit only by an UNSCOPED survey (6,306 logs / 500k blocks), while
    /// every query here pins BOTH topics — a real wallet measured 8 logs over
    /// the same range. Chunk-sum proof at 500k: one call returned 6,306 and
    /// five 100k chunks over the identical range summed to exactly 6,306.
    private static let maxRange = 500_000
    /// Chunks per wallet per pass — 12M blocks, enough to walk the pool's
    /// whole history in one first-sight pass. A wallet further behind catches
    /// up over several passes; `scanned` persists even when the head isn't
    /// reached, and a chunk that errors keeps its place.
    private static let maxChunks = 24

    /// Railgun's V2 shielded-pool contract on mainnet — the address that
    /// actually HOLDS shielded tokens, so `to == railgun` is what separates a
    /// shield from the wallet's own outbound transfer, and `from == railgun`
    /// separates an unshield from any other inbound one. Both sides of
    /// ERC-20 `Transfer` are indexed, so this filters server-side with no
    /// false positives.
    ///
    /// MEASURED 2026-08-01: this is the live one (6,306 inbound transfers over
    /// 500k blocks, and it's the address that emits `Shield`). Two traps around
    /// it. Its Etherscan name tag reads "Railgun: Relay", which is MISLEADING —
    /// it is the shield/unshield core, not a relayer. And the other address
    /// widely published as Railgun's smart wallet,
    /// `0xc0bef2d373a1efade8b952f33c1370e486f209cc`, is INERT: it has code but
    /// took 0 transfers over the same 500k blocks, holds no ETH, and reverts on
    /// `symbol()`/`name()`. Pointing this bridge there would have produced a
    /// permanently silent seat with no error anywhere to explain it.
    static let smartWallet = "0xfa7093cdd9ee6932b4eb2c9e1cde7ce00b1fa4b9"

    /// The RelayAdapt contracts — Railgun's wrapper for native ETH, multicall
    /// and relayed shields. Named here to EXCLUDE them: a transfer between an
    /// adapter and the pool is Railgun's own plumbing, not the person's money
    /// moving, and landing one would be a row nobody did.
    ///
    /// BOTH are live and both must be in the set (measured 2026-08-01, over
    /// 50k blocks): the current adapter sent 258 of 644 shield transfers and
    /// the superseded V3.1 one — deployed Jan 2023 and never retired — still
    /// sent 38. Carrying only the current address would leak the older
    /// adapter's plumbing into the feed as if it were someone's own deposit.
    static let relayAdapts: Set<String> = [
        "0xac9f360ae85469b27aeddeafc579ef2d052ad405",   // current (Jul 2025)
        "0x4025ee6512dbbda97049bcf5aa5d38c54af6be8a",   // V3.1, superseded, still live
    ]

    /// Railgun's fee treasury. Excluded from the unshield read, and this is
    /// NOT a nicety: measured, a treasury fee transfer rides 100% of unshield
    /// transactions and accounts for 989 of 1,978 transfer logs — so without
    /// this the feed would double every withdrawal and file Railgun's own
    /// protocol fee as money the person received.
    static let treasury = "0xe8a8b458bcd1ececc6b6b58f80929b29ccecff40"

    /// The block Railgun's V2 pool was deployed. First sight backfills from
    /// here — the Privacy Pools divergence, not Gnosis Pay's 6-day window:
    /// shields are RARE per wallet (a handful ever, not daily), so the honest
    /// first landing is the wallet's real history, capped like every sibling
    /// wallet path at the newest 10.
    /// APPROXIMATE and deliberately EARLY — this is a floor, not a fact. An
    /// early value costs a few empty chunks on the very first pass; a late one
    /// would silently hide history behind the cursor forever, so the error is
    /// taken in the safe direction.
    ///
    /// Do NOT reason about this as "the budget reaches past it anyway". It did
    /// when written (head ~25.9M against a 12M budget) and would have stopped
    /// being true around Nov 2026 at ~7,180 blocks/day — after which a fresh
    /// install's first pass would start at `head - budget`, record that as its
    /// cursor, and put everything earlier permanently out of reach with
    /// nothing logged. `firstSightFloor` exists so the walk is anchored to
    /// this block rather than to a moving window; the budget bounds how much
    /// each PASS does, never how far back the walk can ever get.
    private static let deployBlock = 14_693_000

    /// `Transfer(address indexed from, address indexed to, uint256 value)`.
    private static let transferTopic =
        "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

    // MARK: - The seat (automatic — rides the watched wallets)

    private static func cursorKey(_ address: String) -> String {
        "railgun.cursor.\(address.lowercased())"
    }

    /// Which watched wallets have actually used Railgun.
    ///
    /// Evidence-gated like Gnosis Pay and every sibling since 2026-07-30: most
    /// wallets have never shielded anything, and a seat reading "Railgun ·
    /// watching 3 wallets" for someone who has never touched it is fake
    /// status. The seat appears the day a shield or unshield is really seen.
    static let evidence = WalletSeatEvidence("railgun.accounts")

    static func accounts() -> [String] { evidence.addresses }

    /// Wallet unwatch takes this seat's cursor and its evidence mark with it —
    /// called from `WalletStore` beside the siblings'.
    static func clearState(address: String) {
        let a = address.lowercased()
        UserDefaults.standard.removeObject(forKey: cursorKey(a))
        evidence.forget(a)
    }

    // MARK: - Sync

    @MainActor private static var running = false

    /// Reads new shields and unshields for the given (resolved, hex) addresses
    /// and lands them — called inside `WalletIngest.refresh`'s pass beside
    /// `PrivacyPoolsBridge.sync`, under that pass's running guard. Returns the
    /// landed count, nil when mainnet couldn't be reached at all.
    @MainActor
    static func sync(context: ModelContext, addresses: [String],
                     existing: Set<String>) async -> Int? {
        guard !running else { return 0 }
        running = true
        defer { running = false }
        return await syncLocked(context: context, addresses: addresses,
                                existing: existing)
    }

    /// The setup screen's own entry — resolves the watch list the way the
    /// wallet refresh does.
    @MainActor
    static func syncNow(context: ModelContext) async -> Int? {
        guard !running else { return 0 }
        running = true
        defer { running = false }
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched)
            .filter { ENS.isHexAddress($0) }
        return await syncLocked(
            context: context, addresses: addresses,
            existing: IngestSupport.existingSourceRefs(context, source: "Railgun"))
    }

    @MainActor
    private static func syncLocked(context: ModelContext, addresses: [String],
                                   existing: Set<String>) async -> Int? {
        guard !addresses.isEmpty else { return 0 }
        guard let latest = await blockNumber() else { return nil }
        let defaults = UserDefaults.standard
        var added = 0
        // Evidence-gated seat + a forward-reading cursor: shields landed
        // before the mark existed sit behind it, so one fetch over what they
        // landed rebuilds it. Runs once, ever.
        evidence.backfillFromCorpus(context, source: "Railgun")

        // The dedupe set is rebuilt HERE against this bridge's OWN source,
        // rather than trusted from the caller. `WalletIngest.refresh` hands
        // every wallet-riding sweep a set scoped to `source: "Wallet"`, which
        // contains no Railgun refs at all — so `!existing.contains(ref)` would
        // pass unconditionally on the refresh path, and `seen` only dedupes
        // within a single call. Any window read twice (a save that failed and
        // left the cursor, a probe rewind, a re-watch) would then land a
        // second copy of every row under the same `sourceRef` — the duplicate
        // class `-corpusDupeProbe` exists to catch. The caller's set is
        // unioned in rather than dropped so a correctly-scoped one still
        // counts.
        let known = existing.union(
            IngestSupport.existingSourceRefs(context, source: "Railgun"))

        for address in addresses {
            let key = cursorKey(address)
            let cursor = (defaults.object(forKey: key) as? Int) ?? (deployBlock - 1)
            guard latest > cursor else { continue }
            let from = cursor + 1
            var scanned = from - 1
            var shieldLogs: [[String: Any]] = []
            var unshieldLogs: [[String: Any]] = []
            // `maxChunks` bounds the WORK PER PASS, never how far back the
            // walk can reach. The obvious alternative — leaving the loop
            // unbounded and instead clamping `from` up to `latest - budget` —
            // reads as the same thing and isn't: it silently redefines first
            // sight as "the last N blocks", so once the chain outgrows the
            // budget, everything earlier is skipped AND recorded as scanned.
            // Walking forward from the floor a bounded number of chunks per
            // pass costs a few extra foregrounds on a deep backfill and can't
            // lose a block.
            var chunks = 0
            while scanned < latest, chunks < maxChunks {
                chunks += 1
                let to = min(scanned + maxRange, latest)
                guard let shields = await fetchTransfers(from: address,
                                                         to: smartWallet,
                                                         fromBlock: scanned + 1,
                                                         toBlock: to)
                else { break }   // transient — keep the cursor, retry next pass
                shieldLogs += shields
                // Unshields ride the SAME range and cursor, so a failed
                // unshield read must STOP the walk exactly like a failed
                // shield read. Treating it as best-effort — landing the
                // shields and advancing anyway — silently retires a window
                // whose unshields were never read: 500k blocks (~10 weeks) of
                // received money behind a cursor no later pass looks below,
                // and no error anywhere. That the unshield IS the
                // differentiated read makes it the worst possible half to
                // drop. Both halves of the window succeed or neither counts.
                guard let unshields = await fetchTransfers(from: smartWallet,
                                                           to: address,
                                                           fromBlock: scanned + 1,
                                                           toBlock: to)
                else { break }
                unshieldLogs += unshields
                scanned = to
            }
            // The first chunk failed, so nothing was read — leave the cursor
            // exactly where it was and retry the same window next pass.
            guard scanned > cursor else { continue }

            // Evidence keys on logs FOUND, not things LANDED. Keying it on new
            // things loses the seat forever for anyone who unwatches and
            // re-watches: `clearState` drops the mark, the re-scan finds the
            // same transfers, dedupe removes every one, nothing lands — and
            // the seat never comes back. A log that passed this filter IS a
            // Railgun interaction by construction.
            if !shieldLogs.isEmpty || !unshieldLogs.isEmpty {
                evidence.remember(address)
            }

            let shieldBatch = await things(from: shieldLogs, wallet: address,
                                           direction: .shield, existing: known)
            let unshieldBatch = await things(from: unshieldLogs, wallet: address,
                                             direction: .unshield, existing: known)
            var landed = shieldBatch.things + unshieldBatch.things
            // A capped batch HOLDS THE CURSOR at the last move it actually
            // landed, so the remainder is read next pass instead of being
            // skipped for good. Advancing past a truncated window is how a
            // wallet with 25 shields permanently loses 15 of them — the cap
            // bounds how much lands at once, it must not bound what's ever
            // seen. Two directions, so take the earlier ceiling.
            for ceiling in [shieldBatch.ceiling, unshieldBatch.ceiling] {
                if let ceiling { scanned = min(scanned, ceiling) }
            }
            guard scanned > cursor else { continue }
            if !landed.isEmpty {
                for thing in landed {
                    context.insert(thing)
                    SpotlightIndex.index([thing])
                }
                // Land and SAVE before advancing (the WalletApprovals rule) —
                // a cursor that runs ahead of a failed save loses what it
                // skipped, permanently.
                guard context.saveHonestly() else { continue }
                added += landed.count
                // Money ARRIVING rains (the Stripe precedent, prd §250) — but
                // only money that arrived TODAY. "Really inserted" stops a
                // re-read from re-raining; it does nothing about a backfill,
                // and first sight here walks years of history, so a wallet
                // that unshielded six times in 2023 would fire six
                // celebrations at once for money that landed three years ago.
                // The freshness gate is the sibling shape (Privacy Pools seeds
                // anything older than a day silently). Shields never rain:
                // sending your own money into a pool is not a moment,
                // receiving it is.
                for thing in landed
                where thing.transferDirection == "received"
                    && Date.now.timeIntervalSince(thing.capturedAt) < 86_400 {
                    SourceMoments.shared.fire(thing.title, source: "Railgun")
                }
            }
            defaults.set(scanned, forKey: key)
        }
        return added
    }

    /// `-railgunProbe <blocksBack|YES>` — runs the sweep over the watched
    /// wallets headlessly. A numeric spec rewinds every cursor that many
    /// blocks below the head first; a fresh install already backfills from the
    /// deploy block by design. Pair with `-walletAddress <a Railgun user>`.
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
                UserDefaults.standard.set(max(deployBlock - 1, latest - back),
                                          forKey: cursorKey(address))
            }
        }
        let n = await syncLocked(
            context: context, addresses: addresses,
            existing: IngestSupport.existingSourceRefs(context, source: "Railgun"))
        dumpRows(context: context)
        return n
    }

    /// One NSLog PER ROW, never one joined message — the log reader truncates
    /// a long multi-line NSLog mid-document (the `-todayProbe` lesson). A count
    /// alone can't tell a correct amount from one off by twelve decimal places,
    /// which is the whole decimals trap, so the probe shows the money it wrote.
    @MainActor
    private static func dumpRows(context: ModelContext) {
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Railgun" },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.fetchLimit = 12
        let rows = (try? context.fetch(descriptor)) ?? []
        NSLog("[Casberi] railgunRows: %d in corpus (newest %d shown)",
              (try? context.fetchCount(FetchDescriptor<Thing>(
                  predicate: #Predicate { $0.source == "Railgun" }))) ?? rows.count,
              rows.count)
        let stamp = ISO8601DateFormatter()
        for row in rows where row.isLive {
            NSLog("[Casberi] railgunRow| %@ | %@ | %@ | %@",
                  stamp.string(from: row.capturedAt),
                  row.title,
                  row.transferAmount ?? "—",
                  row.content)
        }
    }

    /// The probe's status line — which watched wallets have used Railgun.
    static func accountSummary() -> String {
        let known = accounts()
        guard !known.isEmpty else { return "no Railgun wallets seen" }
        return "\(known.count) wallet\(known.count == 1 ? "" : "s"): "
            + known.map { WalletStore.shortAddress($0) }.joined(separator: ", ")
    }

    // MARK: - Landing

    private enum Direction {
        case shield, unshield
    }

    private struct Move {
        let token: String        // lowercased contract address
        let raw: Double
        let block: Int
        let txHash: String
        let logIndex: Int
    }

    /// Returns the rows to land, plus a `ceiling` the caller must clamp its
    /// cursor to when the batch was capped — nil when everything in the window
    /// was taken.
    @MainActor
    private static func things(from logs: [[String: Any]], wallet: String,
                               direction: Direction,
                               existing: Set<String>)
        async -> (things: [Thing], ceiling: Int?) {
        var moves: [Move] = []
        for log in logs {
            guard (log["removed"] as? Bool) != true,
                  let contract = (log["address"] as? String)?.lowercased(),
                  let topics = log["topics"] as? [String], topics.count == 3,
                  let txHash = log["transactionHash"] as? String,
                  let blockHex = log["blockNumber"] as? String,
                  let indexHex = log["logIndex"] as? String,
                  // An NFT shield rides the SAME topic0 as an ERC-20 one but
                  // carries its token id in a FOURTH topic and an EMPTY data
                  // field (measured: 23 of 6,306 logs, 0.36%). The topic count
                  // above already drops those; this is the second half of the
                  // same guard, since a malformed `data` would otherwise parse
                  // as an amount of zero and land a row claiming nothing moved.
                  let data = log["data"] as? String, data.count == 66
            else { continue }
            // Both topics are pinned in every query this file issues, so the
            // node has ALREADY excluded Railgun's own plumbing — a RelayAdapt
            // leg fails the `from` pin, and the treasury fee that rides 100%
            // of unshield transactions fails the `to` pin. That is why the
            // sweep needs no de-noising pass: the two contaminations that make
            // an unscoped read unusable (measured at 51.5% and 50% of their
            // respective directions) can't reach a pinned one.
            //
            // Verified anyway, because the cost is two string compares and the
            // failure is money misattributed to a person's own wallet. A host
            // that answers a filtered request with unfiltered logs is a bug
            // this can survive rather than one it silently launders.
            let sender = "0x" + topics[1].suffix(40).lowercased()
            let recipient = "0x" + topics[2].suffix(40).lowercased()
            let me = wallet.lowercased()
            let wantFrom = direction == .shield ? me : smartWallet
            let wantTo = direction == .shield ? smartWallet : me
            guard sender == wantFrom, recipient == wantTo,
                  !relayAdapts.contains(sender), !relayAdapts.contains(recipient),
                  sender != treasury, recipient != treasury
            else { continue }
            moves.append(Move(token: contract,
                              raw: WalletIngest.hexToDouble(data),
                              block: WalletIngest.hexToInt(blockHex),
                              txHash: txHash,
                              logIndex: WalletIngest.hexToInt(indexHex)))
        }
        // Up to 10 per direction per pass — but the OLDEST ten, not the
        // newest, and the caller holds its cursor at the last one taken.
        //
        // This diverges from every sibling wallet path on purpose. They cap to
        // the NEWEST N and let the cursor run past the rest, which is fine
        // when the event is rare enough that N is never reached. Railgun's
        // first sight walks years of history in one pass, so that shape would
        // hand someone with 25 shields their newest 10 and bury the other 15
        // below a cursor nothing reads again. Taking the oldest and stopping
        // there means a busy wallet fills in over a few foregrounds, in the
        // order things actually happened, and loses nothing.
        let cap = 10
        moves.sort { $0.block == $1.block ? $0.logIndex < $1.logIndex : $0.block < $1.block }
        var ceiling: Int?
        if moves.count > cap, let boundary = moves.prefix(cap).last?.block {
            // Cut on a BLOCK boundary, not on the count — keep every move in
            // the boundary block even if that overshoots the cap by a few.
            // Cutting mid-block and then parking the cursor on that block
            // would skip the moves that shared it, which is the same
            // permanent loss this whole branch exists to prevent, just one
            // block wide.
            moves = moves.filter { $0.block <= boundary }
            ceiling = boundary
        }
        guard !moves.isEmpty else { return ([], ceiling) }

        let meta = await tokenMetadata(contracts: moves.map(\.token))
        let times = await blockTimes(blocks: moves.map(\.block))
        var out: [Thing] = []
        var seen = Set<String>()

        for move in moves {
            let verb = direction == .shield ? "shield" : "unshield"
            let ref = "railgun:\(verb):\(move.txHash.lowercased()):\(move.logIndex)"
            guard !existing.contains(ref), seen.insert(ref).inserted else { continue }

            // Decimals are READ, never assumed — Railgun accepts any ERC-20,
            // so this pass sees 18-decimal WETH beside 6-decimal USDC and
            // 8-decimal WBTC in the same window. Hardcoding 18 would render a
            // dollar as ~$0.000000000001 (the SOL/USDCe bug, third outing). A
            // token that answers neither call lands wearing its short hex,
            // with no amount claimed at all.
            let info = meta[move.token]
            let symbol = info?.symbol ?? WalletStore.shortAddress(move.token)
            let what: String
            var amountLine: String?
            if let decimals = info?.decimals {
                let amount = move.raw / pow(10, Double(decimals))
                amountLine = "\(WalletIngest.format(amount)) \(symbol)"
                what = amountLine ?? symbol
            } else {
                what = symbol
            }

            // The unshield title NEVER names a sender (see the type doc): the
            // chain cannot distinguish "you withdrew" from "someone paid you",
            // so the row states only that the money arrived from Railgun.
            let title = direction == .shield
                ? String(localized: "Shielded \(what) into Railgun")
                : String(localized: "Received \(what) from Railgun")

            let thing = Thing(
                kind: .transaction,
                title: title,
                content: "https://etherscan.io/tx/\(move.txHash)",
                source: "Railgun",
                capturedAt: times[move.block] ?? .now,
                sourceRef: ref)
            thing.walletAddress = wallet
            thing.transferAmount = amountLine
            thing.transferDirection = direction == .shield ? "sent" : "received"
            if direction == .unshield {
                // The honesty note rides `enrichedText` — the thing sheet's
                // body and search, never the title (it's context, not a
                // claim). This is the one fact about an unshield that a
                // reader will otherwise get wrong, and getting it wrong here
                // means believing you know who paid you.
                thing.enrichedText = String(localized: "Railgun can't tell you who sent this — inside the pool the sender is private by design. If you unshielded this yourself, that's you.")
            }
            out.append(thing)
        }
        return (out, ceiling)
    }

    // MARK: - Token metadata (keyless, cached)

    /// Symbol + decimals per token contract, read straight off the contract by
    /// `eth_call` — the same `symbol()`-falling-back-to-`name()` decode
    /// `WalletApprovals.tokenMetadata` and `PeerBridge.depositToken` use, on
    /// the hosts this file already rides.
    ///
    /// CACHED ACROSS PASSES, unlike either sibling, and that difference is the
    /// point: their token sets are bounded (three card stablecoins; whatever
    /// Peer settled in), while Railgun takes ANY ERC-20, so the same handful of
    /// tokens would otherwise be re-read on every pass forever. Symbol and
    /// decimals are immutable for any token worth landing, so a hit is free and
    /// correct. A contract that answers nothing is NOT cached — that's a host
    /// hiccup as often as a strange token, and caching it would make the row
    /// wear a hex forever.
    private static func tokenMetadata(contracts: [String])
        async -> [String: (symbol: String?, decimals: Int?)] {
        var seen = Set<String>()
        let unique = contracts.filter { seen.insert($0).inserted }
        var out: [String: (symbol: String?, decimals: Int?)] = [:]
        var cache = metadataCache()
        var dirty = false

        for contract in unique.prefix(12) {
            if let hit = cache[contract] {
                out[contract] = (hit["symbol"] as? String,
                                 hit["decimals"] as? Int)
                continue
            }
            async let symbolRet = call(method: "eth_call",
                                       params: [["to": contract, "data": "0x95d89b41"], "latest"])
            async let decimalsRet = call(method: "eth_call",
                                         params: [["to": contract, "data": "0x313ce567"], "latest"])
            var symbol = (await symbolRet as? String).flatMap(IngestSupport.decodeABIString)
            if symbol == nil {
                let nameRet = await call(method: "eth_call",
                                         params: [["to": contract, "data": "0x06fdde03"], "latest"])
                symbol = (nameRet as? String).flatMap(IngestSupport.decodeABIString)
            }
            let decimals = decodeDecimals(await decimalsRet as? String)
            out[contract] = (symbol, decimals)
            // Cache ONLY a COMPLETE answer. Caching a partial one is how a
            // transient failure becomes permanent: `decimals()` times out
            // once, `{"symbol":"WETH"}` is written, and because the read
            // short-circuits on any cache hit, every future WETH row on every
            // wallet lands with no amount forever — nothing invalidates this
            // key, not even unwatching. Half an answer is a retry, not a fact.
            if let symbol, let decimals {
                cache[contract] = ["symbol": symbol, "decimals": decimals]
                dirty = true
            }
        }
        if dirty { setMetadataCache(cache) }
        return out
    }

    /// `decimals()`'s return word as a usable scale, or nil.
    ///
    /// A plain `.map(hexToInt)` is WRONG here and would state a wrong number
    /// rather than declining to state one. Several public gateways answer a
    /// REVERTING `eth_call` with `{"result":"0x"}` instead of an error object,
    /// and `hexToInt("0x")` is 0 — which would scale a raw uint256 by
    /// `10^0` and land "Shielded 1200000000000000000 WETH". So an empty word
    /// is rejected here, while a word that really encodes zero is kept: 0 is a
    /// legitimate answer (WQUBIC, measured), and the two are distinguishable
    /// only by whether any hex digits came back at all.
    ///
    /// The upper bound catches the mirror failure — a garbage word clamps
    /// `hexToInt` to something enormous, `pow(10, huge)` is `.infinity`, and
    /// the amount computes to exactly 0, landing a row claiming nothing moved.
    /// 36 is comfortably past any real token.
    private static func decodeDecimals(_ word: String?) -> Int? {
        guard let word else { return nil }
        let digits = word.hasPrefix("0x") ? String(word.dropFirst(2)) : word
        guard !digits.isEmpty else { return nil }
        let value = WalletIngest.hexToInt(word)
        guard (0...36).contains(value) else { return nil }
        return value
    }

    private static let metadataKey = "railgun.tokenmeta"

    private static func metadataCache() -> [String: [String: Any]] {
        (UserDefaults.standard.dictionary(forKey: metadataKey)
            as? [String: [String: Any]]) ?? [:]
    }

    private static func setMetadataCache(_ cache: [String: [String: Any]]) {
        UserDefaults.standard.set(cache, forKey: metadataKey)
    }

    // MARK: - RPC reads (mainnet public hosts, first that answers wins)

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

    /// ERC-20 transfers between two named addresses, in one direction, over a
    /// block range. Both `from` and `to` are indexed on `Transfer`, so this is
    /// filtered server-side and exact.
    ///
    /// NOTE there is deliberately NO `address` filter: Railgun accepts any
    /// ERC-20, so constraining the token list — the thing Gnosis Pay does,
    /// because a card spends exactly three stablecoins — would silently drop
    /// every token not in the table. The two topics are what make this read
    /// selective.
    private static func fetchTransfers(from sender: String, to recipient: String,
                                       fromBlock: Int,
                                       toBlock: Int) async -> [[String: Any]]? {
        guard toBlock - fromBlock <= maxRange else { return nil }   // structurally
        let params: [String: Any] = [
            "fromBlock": hex(fromBlock), "toBlock": hex(toBlock),
            "topics": [transferTopic, topic(sender), topic(recipient)],
        ]
        return await call(method: "eth_getLogs", params: [params]) as? [[String: Any]]
    }

    /// Block timestamps — a shield found after months away should land dated
    /// when it happened, not when the app next opened. Capped at the newest 10
    /// blocks, matching the 10-move landing cap above.
    private static func blockTimes(blocks: [Int]) async -> [Int: Date] {
        var out: [Int: Date] = [:]
        for block in Set(blocks).sorted(by: >).prefix(10) {
            guard let b = await call(method: "eth_getBlockByNumber",
                                     params: [hex(block), false]) as? [String: Any],
                  let ts = b["timestamp"] as? String else { continue }
            out[block] = Date(timeIntervalSince1970: WalletIngest.hexToDouble(ts))
        }
        return out
    }

    /// An address as a 32-byte indexed log topic.
    private static func topic(_ address: String) -> String {
        "0x000000000000000000000000" + address.dropFirst(2).lowercased()
    }

    private static func hex(_ n: Int) -> String { "0x" + String(n, radix: 16) }
}
