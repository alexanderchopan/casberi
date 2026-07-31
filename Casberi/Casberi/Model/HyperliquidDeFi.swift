import Foundation
import SwiftData

/// Hyperliquid (2026-07-30) — perp positions, spot balances, and staked HYPE
/// for a watched wallet, read off Hyperliquid's own public `info` endpoint
/// (`api.hyperliquid.xyz/info`, keyless — every request in this file
/// measured live against real accounts pulled off the public leaderboard,
/// each returning in well under a second). Rides watched wallets like
/// Peer/Privacy Pools/Gnosis Pay — no account, no key, no connect switch: an
/// address either has a Hyperliquid account or it doesn't, and the read
/// answers that for free.
///
/// Modeled in THREE parts, the WalletDeFi/Morpho split:
/// (1) `book(addresses:)` is LIVE STATE — perp positions, spot balances,
///     staked HYPE, read fresh every foreground pass, never landed, never
///     persisted beyond the screen's own state.
/// (2) `sync(...)` lands DISCRETE EVENTS, and the design problem
///     Hyperliquid poses is real: a single measured wallet returned 2000
///     fills spanning 3.5 hours, so landing fills would bury the corpus.
///     What lands instead is a POSITION TRANSITION — a coin appearing in the
///     open-position set is "Opened", disappearing is "Closed", collapsing
///     an unbounded trade history into the two facts that are actually
///     news. A liquidation-proximity crossing (the WalletDeFi/Morpho bucket
///     pattern, scaled to price distance rather than a health factor, since
///     this API carries no HF) lands the same way, diffed per position.
/// (3) `syncUnlocks(...)` lands a dated thing for staked HYPE's unlock — the
///     `ENSExpiry` reconciling-dueAt shape, since a delegation's
///     `lockedUntilTimestamp` can move (re-delegating resets it) the same
///     way a name's expiry can move on renewal.
///
/// MEASURED (2026-07-30, live against real leaderboard accounts — don't
/// re-derive without re-measuring):
/// - `clearinghouseState` positions carry `coin` as a PLAIN SYMBOL (ETH,
///   SOL, BTC) — no mapping needed. `szi`'s SIGN is the side (negative =
///   short); `positionValue` is USD notional; `liquidationPx`/`entryPx` are
///   plain decimal strings.
/// - A DUST position is real and dangerous to alert on blind: one measured
///   position of 0.00001 BTC ($0.65 notional) carried a `liquidationPx` of
///   8.3 BILLION — mathematically correct (near-zero leverage), but an
///   unfiltered alert would shout about a position worth six ways to
///   nothing. Every read here floors on `positionValue`/spot USD.
/// - `spotClearinghouseState` balances are keyed by plain SYMBOL too
///   ("HYPE", "UBTC"), but pricing them is NOT `allMids` — that endpoint
///   returns 0 for every spot token. The real read is
///   `spotMetaAndAssetCtxs`, and its two arrays are NOT positionally
///   aligned with `spotMeta.universe` past the first few entries (measured:
///   `universe[106].name == "@108"` while `ctxs[106]['coin'] == "@106"`) —
///   every ctx MUST be matched by its own `coin` field, never by index.
/// - `subAccounts` is real and can matter: one measured wallet held 5, each
///   its own `clearinghouseState` — folded into the same book, each
///   position tagged with its sub-account name so "Opened ETH short in
///   NACLOOOOOOOOOOO" reads honestly rather than silently attributing a
///   sub-account's risk to the watched wallet.
/// - `portfolio`'s own `accountValueHistory` does NOT reconcile with
///   perps + spot + staked summed independently (measured gap: ~5%) — so
///   this file never invents a single "Hyperliquid total"; the book reports
///   its parts, named, the way `WalletDeFiAsk` already treats Aave/Morpho as
///   separate lines rather than a summed guess.
///
/// NOT built this pass, by scope, not oversight: `userFills`/`userFunding`
/// (exactly the firehose the position-transition design avoids landing);
/// spot-pair discovery beyond the tokens a watched wallet already holds
/// (no watchlist, unlike Tokens/GeckoTerminal — Hyperliquid rides the
/// watched wallets, and its catalog seat is a MIRROR of that, not a switch:
/// it lights once a watched wallet is really seen trading here, and its
/// Connect routes to the wallet manager. See `WalletSeatEvidence`.)
enum HyperliquidDeFi {

    private static let endpoint = "https://api.hyperliquid.xyz/info"

    /// Positions/spot holdings below this stay invisible — `WalletIngest
    /// .holdingFloor`, the dust line the treemap and Morpho both draw. The
    /// $0.65-notional / $8.3B-liquidationPx position above is exactly why.
    private static var floor: Double { WalletIngest.holdingFloor }

    /// Which watched wallets actually trade on Hyperliquid — the catalog
    /// seat's gate (2026-07-30). See `WalletSeatEvidence` for why a seat is
    /// evidence-gated rather than lit for every watched wallet.
    static let evidence = WalletSeatEvidence("hyperliquid.accounts")

    /// Distance from mark to liquidation, as a fraction of mark — under this
    /// is the heads-up margin. Not Aave/Morpho's health factor (this API
    /// carries no HF), so it's its own scale rather than borrowing
    /// `DeFiRisk.floor`: 15% headroom sits in the same "still time to react"
    /// zone Aave's 1.5 HF represents, a design choice, not a measured
    /// liquidation-mechanics constant.
    private static let riskProximity = 0.15

    struct Position: Equatable, Sendable {
        /// The WATCHED wallet this position belongs to — distinct from
        /// `account`, which may be a sub-account's own address.
        let owner: String
        let account: String
        let accountLabel: String?   // sub-account display name, nil = main
        let coin: String
        let isLong: Bool
        let sizeAbs: Double
        let entryPx: Double
        let markPx: Double
        let liquidationPx: Double?
        let positionValue: Double
        let leverageX: Int
        let leverageType: String    // "cross" or "isolated"
        let unrealizedPnl: Double
        let fundingSinceOpen: Double
    }

    struct SpotHolding: Equatable, Sendable {
        let symbol: String
        let amount: Double
        let usd: Double
    }

    struct Delegation: Equatable, Sendable {
        let owner: String
        let validator: String
        let amountHYPE: Double
        let lockedUntil: Date?
    }

    struct Book: Equatable, Sendable {
        var positions: [Position] = []
        var spot: [SpotHolding] = []
        var delegations: [Delegation] = []
        var perpAccountValue: Double = 0
        var spotUsd: Double { spot.reduce(0) { $0 + $1.usd } }
        var isEmpty: Bool {
            positions.isEmpty && spot.isEmpty && delegations.isEmpty && perpAccountValue == 0
        }
    }

    private static let cache = CoalescingCache<Book>()

    // MARK: - Live state

    static func book(addresses: [String]) async -> Book? {
        guard !addresses.isEmpty else { return Book() }
        let key = addresses.map { $0.lowercased() }.sorted().joined(separator: ",")
        return await cache.value(key: key, ttl: 60) {
            await fetchBook(addresses: addresses)
        }
    }

    private static func fetchBook(addresses: [String]) async -> Book? {
        var book = Book()
        var reached = false
        let prices = await spotPrices()

        for address in addresses {
            guard let state = await postInfo(["type": "clearinghouseState", "user": address])
            else { continue }
            reached = true
            if let summary = state["marginSummary"] as? [String: Any],
               let value = doubleValue(summary["accountValue"]) {
                book.perpAccountValue += value
            }
            book.positions += positions(from: state, owner: address, account: address, accountLabel: nil)

            if let spotState = await postInfo(["type": "spotClearinghouseState", "user": address]) {
                book.spot += spotHoldings(from: spotState, prices: prices)
            }
            if let raw = await IngestSupport.postJSON(endpoint, body: ["type": "delegations", "user": address]) {
                book.delegations += delegations(from: raw, owner: address)
            }
            // Sub-accounts (measured real: up to 5 on one wallet) — each
            // carries its OWN embedded clearinghouseState inline, so no
            // extra request; tagged so a sub-account's risk never silently
            // reads as the watched wallet's own.
            if let subs = await IngestSupport.postJSON(endpoint, body: ["type": "subAccounts", "user": address])
                as? [[String: Any]] {
                for sub in subs {
                    guard let subState = sub["clearinghouseState"] as? [String: Any],
                          let subUser = sub["subAccountUser"] as? String else { continue }
                    let name = sub["name"] as? String
                    book.positions += positions(from: subState, owner: address, account: subUser, accountLabel: name)
                    if let summary = subState["marginSummary"] as? [String: Any],
                       let value = doubleValue(summary["accountValue"]) {
                        book.perpAccountValue += value
                    }
                }
            }
        }
        return reached ? book : nil
    }

    private static func positions(from state: [String: Any], owner: String, account: String,
                                  accountLabel: String?) -> [Position] {
        guard let raw = state["assetPositions"] as? [[String: Any]] else { return [] }
        var out: [Position] = []
        for entry in raw {
            guard let p = entry["position"] as? [String: Any],
                  let coin = p["coin"] as? String,
                  let szi = doubleValue(p["szi"]), szi != 0,
                  let entryPx = doubleValue(p["entryPx"]),
                  let positionValue = doubleValue(p["positionValue"]), positionValue >= floor
            else { continue }
            let leverage = p["leverage"] as? [String: Any]
            let cumFunding = p["cumFunding"] as? [String: Any]
            let sizeAbs = abs(szi)
            out.append(Position(
                owner: owner.lowercased(), account: account, accountLabel: accountLabel, coin: coin,
                isLong: szi > 0, sizeAbs: sizeAbs, entryPx: entryPx,
                markPx: sizeAbs > 0 ? positionValue / sizeAbs : entryPx,
                liquidationPx: doubleValue(p["liquidationPx"]),
                positionValue: positionValue,
                leverageX: intValue(leverage?["value"]) ?? 1,
                leverageType: (leverage?["type"] as? String) ?? "cross",
                unrealizedPnl: doubleValue(p["unrealizedPnl"]) ?? 0,
                fundingSinceOpen: doubleValue(cumFunding?["sinceOpen"]) ?? 0))
        }
        return out
    }

    /// symbol -> USD price, off `spotMetaAndAssetCtxs`. USDC prices at 1.0
    /// trivially — it's the quote currency every pair below is against.
    private static func spotPrices() async -> [String: Double] {
        guard let raw = await IngestSupport.postJSON(endpoint, body: ["type": "spotMetaAndAssetCtxs"]) as? [Any],
              raw.count == 2,
              let meta = raw[0] as? [String: Any],
              let ctxs = raw[1] as? [[String: Any]],
              let universe = meta["universe"] as? [[String: Any]],
              let tokens = meta["tokens"] as? [[String: Any]]
        else { return ["USDC": 1.0] }
        var tokenName: [Int: String] = [:]
        for t in tokens {
            if let idx = intValue(t["index"]), let name = t["name"] as? String { tokenName[idx] = name }
        }
        // pair NAME -> markPx, matched by ctx's own `coin` field — measured
        // NOT index-aligned with `universe` past the first few entries.
        var pairPrice: [String: Double] = [:]
        for ctx in ctxs {
            guard let name = ctx["coin"] as? String, let mark = doubleValue(ctx["markPx"]) else { continue }
            pairPrice[name] = mark
        }
        var out: [String: Double] = ["USDC": 1.0]
        for u in universe {
            guard let name = u["name"] as? String,
                  let toks = u["tokens"] as? [Int], toks.count == 2,
                  let base = tokenName[toks[0]], let quote = tokenName[toks[1]], quote == "USDC",
                  let px = pairPrice[name]
            else { continue }
            out[base] = px
        }
        return out
    }

    private static func spotHoldings(from state: [String: Any], prices: [String: Double]) -> [SpotHolding] {
        guard let balances = state["balances"] as? [[String: Any]] else { return [] }
        var out: [SpotHolding] = []
        for b in balances {
            guard let coin = b["coin"] as? String, let total = doubleValue(b["total"]), total > 0,
                  let px = prices[coin]
            else { continue }
            let usd = total * px
            guard usd >= floor else { continue }
            out.append(SpotHolding(symbol: coin, amount: total, usd: usd))
        }
        return out
    }

    private static func delegations(from raw: Any, owner: String) -> [Delegation] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        var out: [Delegation] = []
        for d in arr {
            guard let validator = d["validator"] as? String, let amt = doubleValue(d["amount"]), amt > 0
            else { continue }
            let lockedMs = doubleValue(d["lockedUntilTimestamp"])
            out.append(Delegation(owner: owner.lowercased(), validator: validator, amountHYPE: amt,
                                  lockedUntil: lockedMs.map { Date(timeIntervalSince1970: $0 / 1000) }))
        }
        return out
    }

    private static func postInfo(_ body: [String: Any]) async -> [String: Any]? {
        await IngestSupport.postJSON(endpoint, body: body) as? [String: Any]
    }

    // MARK: - Position transitions (the design problem: never land fills)

    private struct OpenSnapshot: Codable {
        var entryPx: Double
        var leverageX: Int
        var openedAt: Date
        var lastUPnl: Double
    }

    private static func snapshotKey(_ address: String) -> String {
        "hyperliquid.positions.\(address.lowercased())"
    }

    private static func loadSnapshot(_ address: String) -> [String: OpenSnapshot] {
        guard let data = UserDefaults.standard.data(forKey: snapshotKey(address)),
              let dict = try? JSONDecoder().decode([String: OpenSnapshot].self, from: data)
        else { return [:] }
        return dict
    }

    private static func saveSnapshot(_ dict: [String: OpenSnapshot], address: String) {
        guard let data = try? JSONEncoder().encode(dict) else { return }
        UserDefaults.standard.set(data, forKey: snapshotKey(address))
    }

    private static func posKey(_ p: Position) -> String {
        "\(p.account.lowercased())|\(p.coin)|\(p.isLong ? "long" : "short")"
    }

    private static func riskDefaultsKey(_ key: String) -> String { "hyperliquid.risk.\(key)" }

    /// Lands position-transition events (opened/closed) and liquidation-
    /// proximity crossings, for the given (resolved, hex) addresses. Diffs
    /// against a per-wallet snapshot rather than landing fills — the design
    /// constraint the file header explains. Returns landed count, nil when
    /// the read reached nothing at all (an empty book is a real "no
    /// activity", not a miss).
    @MainActor
    static func sync(context: ModelContext, addresses: [String], existing: Set<String>) async -> Int? {
        guard !addresses.isEmpty else { return 0 }
        guard let book = await book(addresses: addresses) else { return nil }
        var added = 0
        let defaults = UserDefaults.standard
        let now = Int(Date.now.timeIntervalSince1970)

        for address in addresses {
            let mine = book.positions.filter { $0.owner == address.lowercased() }
            // The catalog seat's evidence mark (2026-07-30) — an open perp or
            // staked HYPE is proof this wallet trades here. Read off this
            // pass's own `book`, so it costs nothing extra; never unstamped
            // on an empty book (`WalletSeatEvidence`'s stamp-never-unstamp
            // rule). Spot holdings deliberately DON'T count: `book.spot`
            // accumulates across every watched wallet and `SpotHolding`
            // carries no owner, so a spot-only wallet can't be told apart
            // from its neighbour — and marking on it would light the seat
            // for wallets that have never touched Hyperliquid. Under-claim
            // over over-claim; a spot-only holder's seat waits for a perp.
            if !mine.isEmpty
                || book.delegations.contains(where: { $0.owner == address.lowercased() }) {
                evidence.remember(address)
            }
            var snapshot = loadSnapshot(address)
            // First sight of this wallet (no snapshot yet) seeds silently —
            // an ALREADY-open position isn't news that it just opened, the
            // Peer/Morpho/Uniswap cursor-seed rule. Caught live (2026-07-30):
            // without this, watching a wallet already holding 22 positions
            // landed 22 "Opened" things in one pass, pure backfill noise.
            // The risk-crossing check below still fires on first sight,
            // deliberately — that's the Aave/Morpho precedent (a position
            // already near liquidation when you start watching is exactly
            // what you want to know immediately).
            let isFirstSight = snapshot.isEmpty
            var seenKeys = Set<String>()

            for p in mine {
                let key = posKey(p)
                seenKeys.insert(key)
                if snapshot[key] == nil {
                    snapshot[key] = OpenSnapshot(entryPx: p.entryPx, leverageX: p.leverageX,
                                                 openedAt: .now, lastUPnl: p.unrealizedPnl)
                    if !isFirstSight {
                        let ref = "hyperliquid:open:\(key):\(now)"
                        if !existing.contains(ref) {
                            let side = p.isLong ? "long" : "short"
                            let who = p.accountLabel.map { " in \($0)" } ?? ""
                            let title = String(localized:
                                "Opened \(p.coin) \(side) on Hyperliquid\(who) — \(p.leverageX)x leverage, entry $\(WalletIngest.format(p.entryPx))")
                            let thing = Thing(kind: .transaction, title: title,
                                              content: "https://app.hyperliquid.xyz/trade/\(p.coin)",
                                              source: "Wallet", sourceRef: ref)
                            thing.walletAddress = address
                            context.insert(thing)
                            SpotlightIndex.index([thing])
                            added += 1
                        }
                    }
                } else {
                    snapshot[key]?.lastUPnl = p.unrealizedPnl
                }

                // Liquidation-proximity risk bucket — its own scale (no HF
                // here), same crossing-only-lands-once shape as Aave/Morpho.
                guard let liq = p.liquidationPx, p.markPx > 0 else { continue }
                let proximity = abs(p.markPx - liq) / p.markPx
                let rKey = riskDefaultsKey(key)
                let bucket = proximity < riskProximity ? "at-risk" : "safe"
                let lastBucket = defaults.string(forKey: rKey)
                defaults.set(bucket, forKey: rKey)
                guard bucket == "at-risk", lastBucket != "at-risk" else { continue }
                let ref = "hyperliquid:risk:\(key):\(now)"
                guard !existing.contains(ref) else { continue }
                let side = p.isLong ? "long" : "short"
                let pct = Int((proximity * 100).rounded())
                let title = String(localized:
                    "Your \(p.coin) \(side) on Hyperliquid is close to liquidation — \(pct)% away at $\(WalletIngest.format(liq))")
                let thing = Thing(kind: .transaction, title: title,
                                  content: "https://app.hyperliquid.xyz/trade/\(p.coin)",
                                  source: "Wallet", sourceRef: ref)
                thing.walletAddress = address
                context.insert(thing)
                SpotlightIndex.index([thing])
                added += 1
            }

            // Closes — anything the snapshot remembers that isn't live
            // anymore. A closed position's risk bucket is stale on purpose:
            // dropped so a re-open starts from "safe" rather than
            // inheriting the old read (the Aave/Morpho definitive-reset rule).
            for (key, snap) in snapshot where !seenKeys.contains(key) {
                snapshot.removeValue(forKey: key)
                defaults.removeObject(forKey: riskDefaultsKey(key))
                let parts = key.split(separator: "|")
                guard parts.count == 3 else { continue }
                let coin = String(parts[1]); let side = String(parts[2])
                let days = max(0, Int(Date.now.timeIntervalSince(snap.openedAt) / 86_400))
                let held = days == 0 ? String(localized: "held under a day")
                    : days == 1 ? String(localized: "held a day")
                    : String(localized: "held \(days) days")
                let pnlNote = snap.lastUPnl == 0 ? "" :
                    (snap.lastUPnl > 0
                        ? String(localized: " — was up about $\(WalletIngest.format(snap.lastUPnl)) when last checked")
                        : String(localized: " — was down about $\(WalletIngest.format(abs(snap.lastUPnl))) when last checked"))
                let ref = "hyperliquid:close:\(key):\(now)"
                if !existing.contains(ref) {
                    let title = String(localized: "Closed \(coin) \(side) on Hyperliquid — \(held)\(pnlNote)")
                    let thing = Thing(kind: .transaction, title: title,
                                      content: "https://app.hyperliquid.xyz/trade/\(coin)",
                                      source: "Wallet", sourceRef: ref)
                    thing.walletAddress = address
                    context.insert(thing)
                    SpotlightIndex.index([thing])
                    added += 1
                }
            }
            saveSnapshot(snapshot, address: address)
        }
        if added > 0 { _ = context.saveHonestly() }
        return added
    }

    // MARK: - Staked HYPE unlock (the ENSExpiry reconciling-dueAt shape)

    /// Lands (or reconciles) a dated row per staked delegation whose unlock
    /// falls inside the horizon — the ENSExpiry shape: a re-delegation moves
    /// `lockedUntilTimestamp`, and the row has to follow it. Returns landed
    /// count, nil when the read reached nothing.
    @MainActor
    static func syncUnlocks(context: ModelContext, addresses: [String], existing: Set<String>) async -> Int? {
        guard !addresses.isEmpty else { return 0 }
        guard let book = await book(addresses: addresses) else { return nil }
        guard let horizon = Calendar.current.date(byAdding: .day, value: 60, to: .now),
              let grace = Calendar.current.date(byAdding: .day, value: -14, to: .now)
        else { return 0 }
        var added = 0
        for d in book.delegations {
            guard let unlock = d.lockedUntil, d.amountHYPE >= 1 else { continue }
            let ref = "hyperliquid:unlock:\(d.owner):\(d.validator.lowercased())"
            let fresh = unlockTitle(delegation: d, unlock: unlock)
            if existing.contains(ref) {
                if let landed = try? context.fetch(FetchDescriptor<Thing>(
                    predicate: #Predicate { $0.sourceRef == ref })).first,
                   landed.dueAt != unlock || landed.title != fresh {
                    landed.dueAt = unlock
                    landed.title = fresh
                }
                continue
            }
            guard unlock <= horizon, unlock >= grace else { continue }
            let thing = Thing(kind: .link, title: fresh,
                              content: "https://app.hyperliquid.xyz/staking",
                              source: "Wallet", capturedAt: .now, sourceRef: ref)
            thing.dueAt = unlock
            thing.walletAddress = d.owner
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }
        if added > 0 { _ = context.saveHonestly() }
        return added
    }

    /// "unlocks Aug 14" / already-past reads as unlockABLE, not a future
    /// promise — no "in N days" (a stored title would start lying the next
    /// morning, the ENSExpiry rule).
    private static func unlockTitle(delegation d: Delegation, unlock: Date) -> String {
        let when = unlock.formatted(.dateTime.month(.abbreviated).day())
        let amt = WalletIngest.format(d.amountHYPE)
        return unlock < .now
            ? String(localized: "\(amt) staked HYPE has been unlockable since \(when)")
            : String(localized: "\(amt) staked HYPE unlocks \(when)")
    }

    // MARK: - Wallet unwatch

    /// Drops this wallet's position snapshot — a stale snapshot would read
    /// every live position back as freshly "opened" on re-watch. Risk
    /// buckets aren't separately enumerable without the live book; they
    /// self-correct next sync since the snapshot they key off is gone.
    static func clearState(address: String) {
        UserDefaults.standard.removeObject(forKey: snapshotKey(address))
        // …and the catalog seat's mark, or the seat stays lit for a wallet
        // that's gone (`WalletSeatEvidence` rule 2).
        evidence.forget(address)
    }

    // MARK: - Parsing helpers

    private static func doubleValue(_ raw: Any?) -> Double? {
        if let d = raw as? Double, d.isFinite { return d }
        if let i = raw as? Int { return Double(i) }
        if let s = raw as? String, let d = Double(s), d.isFinite { return d }
        return nil
    }

    private static func intValue(_ raw: Any?) -> Int? {
        if let i = raw as? Int { return i }
        if let d = raw as? Double, d.isFinite { return Int(d) }
        if let s = raw as? String { return Int(s) ?? Double(s).flatMap { Int($0) } }
        return nil
    }

    #if DEBUG
    /// `-hyperliquidProbe YES` — NSLogs each watched wallet's Hyperliquid
    /// book (perp positions with leverage/entry/liq price, spot holdings,
    /// staked HYPE) or the honest miss, then runs the position-transition +
    /// risk sync and the unlock sync once, reporting what landed. Pairs
    /// with `-walletAddress`. Returns ONE LINE PER ROW — a book with several
    /// positions (a real measured wallet had 9, across sub-accounts) joined
    /// into one NSLog call truncates past NSLog's own length limit (the
    /// `-todayProbe` lesson) and silently hides everything past the cut.
    /// The hook logs each element separately.
    @MainActor
    static func probe(context: ModelContext) async -> [String] {
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched).filter { ENS.isHexAddress($0) }
        guard !addresses.isEmpty else { return ["no EVM wallets watched"] }
        guard let book = await book(addresses: addresses) else { return ["book UNREACHABLE"] }
        var lines: [String] = []
        if book.isEmpty { lines.append("no Hyperliquid activity (a real empty book, not a miss)") }
        for p in book.positions {
            let side = p.isLong ? "long" : "short"
            let who = p.accountLabel.map { " [\($0)]" } ?? ""
            let liq = p.liquidationPx.map { "$\(WalletIngest.format($0))" } ?? "?"
            lines.append("\(WalletStore.shortAddress(p.owner))\(who) \(p.coin) \(side) \(p.leverageX)x: entry=$\(WalletIngest.format(p.entryPx)) mark=$\(WalletIngest.format(p.markPx)) liq=\(liq) uPnl=$\(WalletIngest.format(p.unrealizedPnl)) funding=$\(WalletIngest.format(p.fundingSinceOpen))")
        }
        for s in book.spot {
            lines.append("spot \(s.symbol): \(WalletIngest.format(s.amount)) ($\(WalletIngest.format(s.usd)))")
        }
        for d in book.delegations {
            let unlock = d.lockedUntil.map { $0.formatted(.dateTime.month().day().year()) } ?? "?"
            lines.append("staked \(WalletIngest.format(d.amountHYPE)) HYPE, unlock \(unlock)")
        }
        let existing = IngestSupport.existingSourceRefs(context, source: "Wallet")
        let landed = await sync(context: context, addresses: addresses, existing: existing)
        let unlocked = await syncUnlocks(context: context, addresses: addresses,
                                         existing: IngestSupport.existingSourceRefs(context, source: "Wallet"))
        lines.append("sync: \(landed.map(String.init) ?? "FAILED") landed, unlocks: \(unlocked.map(String.init) ?? "FAILED")")
        return lines
    }
    #endif
}
