import Foundation

/// WHERE THE REST OF THE MONEY IS (2026-07-31, prd §240).
///
/// The Wallet room's crown number counts wallet token holdings, connected
/// exchange balances and watched validators — that and nothing else
/// (`WalletPortfolio.from`). Every protocol position the app reads sits
/// outside it, and not by oversight: Zerion is asked for `only_simple`
/// positions precisely so loan and LP legs never reach the treemap. So an
/// Aave supply, a Morpho vault, a Uniswap position, a Hyperliquid account and
/// a veAERO lock are all read on every foreground pass, and none of them
/// reach the number the room calls your money. For Hyperliquid and Aerodrome
/// it's worse than invisible in the total — until this pass they had no seat
/// on the screen at all.
///
/// **The ruling (user, 2026-07-31) was NOT to fold them into the total.** A
/// single net-worth scalar bakes in accounting choices nobody outside this app
/// would agree on — does debt subtract, is a four-year lock worth spot — and a
/// number that answers those silently loses every comparison against a tracker
/// that answered them differently. Zerion, DeBank and MetaMask already
/// disagree with each other on the same address; there is no "how everyone
/// else calculates it" to match. It also couldn't be done without lying about
/// the past: the headline's sparkline draws off `WalletStore.ValueSample`s
/// recorded under today's rule, so changing what the total counts would step
/// the line and print a delta that never happened.
///
/// So this is a COMPOSITION, not a total: named lines, each stating one fact,
/// summed by nobody. Someone who thinks a lock shouldn't count ignores that
/// line; someone who wants it net does the subtraction themselves, in one
/// glance, from numbers they can see. Every disagreement about how to add it
/// up becomes visible instead of hidden inside a scalar.
///
/// Three rules this type keeps, each load-bearing:
///
/// 1. **It makes no claim about the crown.** Not "not in that number", not
///    "plus" — just what's there. The reason is measured, not fussiness:
///    holdings normally come from Zerion (which types a deposit as a deposit
///    and filters it out), but `WalletIngest` falls back to Alchemy when
///    Zerion can't be reached, and Alchemy returns raw ERC-20 balances —
///    where an aToken or a Morpho vault share IS a plain token. On a fallback
///    day the same money can legitimately appear in both places, so a
///    set-relation claim would be false exactly when the network is worst.
/// 2. **Locked money is never priced.** A veAERO lock and staked HYPE are
///    reported in their own units ("12,977 AERO"), never in dollars. Pricing
///    them would need a quote this file doesn't have, and quoting an illiquid
///    four-year lock at spot is the exact accounting opinion the ruling
///    refused. The unit IS the honest answer.
/// 3. **Nothing here is a tally.** These are amounts of money in places, which
///    the module doctrine has always allowed (money moving is the one counted
///    thing) — never "3 positions", never "5 protocols".
struct WalletComposition: Equatable, Sendable {

    /// Money deposited into one protocol — lending collateral and supply,
    /// vault deposits, liquidity principal, a perp account's own value.
    struct Deposit: Equatable, Sendable, Identifiable {
        let place: String
        let usd: Double
        var id: String { place }
    }

    /// Money owed to one protocol. A positive magnitude — the view spells the
    /// sign, so nothing downstream can accidentally add it as income.
    struct Debt: Equatable, Sendable, Identifiable {
        let place: String
        let usd: Double
        var id: String { place }
    }

    /// ONE lock — a single veAERO NFT or a single HYPE delegation, never a
    /// per-symbol roll-up. A lock is the unit a person actually holds: two
    /// veNFTs can end years apart, and merging them would invent a lock with
    /// an end date neither has.
    struct Lock: Equatable, Sendable, Identifiable {
        let id: String
        let place: String
        let symbol: String
        let amount: Double
        /// Voting power remaining, for a lock that DECAYS (veAERO: measured
        /// 12,977 AERO reading 5,342 votes on a 2028 lock). nil where the
        /// concept doesn't exist — a HYPE delegation just sits until its
        /// unlock, so drawing it a decay bar would invent a mechanic.
        let power: Double?
        /// nil for a permanent lock — it has no end by definition.
        let until: Date?
        let isPermanent: Bool

        /// How much of the lock's power is left, 0…1 — the melt. nil when
        /// there's nothing to melt (permanent, no power read, or an amount of
        /// zero that would divide badly).
        var remaining: Double? {
            guard !isPermanent, let power, amount > 0 else { return nil }
            return min(max(power / amount, 0), 1)
        }
    }

    /// One entry per protocol, biggest first. These three are the only stored
    /// state — every total, place list and per-symbol roll-up below is derived,
    /// so the strip and the trays can never disagree about the same money.
    var deposits: [Deposit] = []
    var debts: [Debt] = []
    var locks: [Lock] = []

    /// The same dust floor the treemap and every book read already use — a
    /// $1.40 leftover in a closed position is not a line on the crown card.
    private static var floor: Double { WalletIngest.holdingFloor }

    var deposited: Double { deposits.reduce(0) { $0 + $1.usd } }
    var depositedPlaces: [String] { deposits.map(\.place) }
    var owed: Double { debts.reduce(0) { $0 + $1.usd } }
    var owedPlaces: [String] { debts.map(\.place) }
    /// Deduped, in the order the locks themselves read.
    var lockedPlaces: [String] {
        var seen = Set<String>()
        return locks.map(\.place).filter { seen.insert($0).inserted }
    }

    /// Locked amounts rolled up per UNIT, for the strip's one-line summary
    /// ("12,977 AERO · 340 HYPE"). The tray lists the locks themselves; this
    /// is the only place they're allowed to merge, because a sum of AERO is
    /// still AERO — unlike a sum of end dates, which is nothing.
    var lockedTotals: [(symbol: String, amount: Double)] {
        var order: [String] = []
        var totals: [String: Double] = [:]
        for lock in locks {
            if totals[lock.symbol] == nil { order.append(lock.symbol) }
            totals[lock.symbol, default: 0] += lock.amount
        }
        return order.map { ($0, totals[$0] ?? 0) }
    }

    var hasDeposited: Bool { deposited >= Self.floor }
    var hasOwed: Bool { owed >= Self.floor }
    var hasLocked: Bool { !locks.isEmpty }

    var isEmpty: Bool { !hasDeposited && !hasOwed && !hasLocked }

    // MARK: - Gathering

    /// Built from books the room has ALREADY read this pass — this adds no
    /// network of its own. Every one of the five is coalesced behind a 60s TTL
    /// (`CoalescingCache`), which is what lets the live-state read, the
    /// refresh arm and this share one real request each.
    ///
    /// Deliberately a pure function over books rather than a fetcher: it can
    /// then be exercised with hand-built books, and it can never be the reason
    /// a screen spends a request.
    static func from(aave: [WalletDeFi.Position],
                     morpho: MorphoDeFi.Book,
                     uniswap: UniswapLiquidity.Book,
                     hyperliquid: HyperliquidDeFi.Book,
                     aerodrome: AerodromeDeFi.Book,
                     etherfiCash: EtherFiCash.Book = EtherFiCash.Book(),
                     etherfiUnstake: EtherFiUnstake.Book = EtherFiUnstake.Book())
    -> WalletComposition {
        var out = WalletComposition()

        // Aave and Spark share one type and differ by `protocolName`, so each
        // names itself rather than being folded under a house label.
        for name in ["Aave", "Spark"] {
            let positions = aave.filter { $0.protocolName == name }
            guard !positions.isEmpty else { continue }
            let supplied = positions.reduce(0) { $0 + $1.totalCollateralUSD }
            let debt = positions.reduce(0) { $0 + $1.totalDebtUSD }
            if supplied >= floor { out.deposits.append(Deposit(place: name, usd: supplied)) }
            if debt >= floor { out.debts.append(Debt(place: name, usd: debt)) }
        }

        // Morpho's three legs are genuinely distinct money: a vault deposit,
        // a market supply, and collateral posted against a borrow. Summing
        // the first two and the third is not double counting — a market
        // position can hold both at once.
        let morphoDeposited = morpho.vaults.reduce(0) { $0 + $1.usd }
            + morpho.positions.reduce(0) { $0 + $1.supplyUSD }
            + morpho.positions.reduce(0) { $0 + ($1.collateralUSD ?? 0) }
        let morphoOwed = morpho.positions.reduce(0) { $0 + $1.borrowUSD }
        if morphoDeposited >= floor {
            out.deposits.append(Deposit(place: "Morpho", usd: morphoDeposited))
        }
        if morphoOwed >= floor {
            out.debts.append(Debt(place: "Morpho", usd: morphoOwed))
        }

        // Liquidity principal only. Uncollected fees are real money too, but
        // they're the Liquidity card's own headline read — counting them here
        // as well would put the same dollars on screen twice in one scroll,
        // and the fee number is the more interesting of the two where it
        // already lives. `valueUSD` is nil when Zerion didn't price the
        // position; a missing price contributes nothing rather than a zero
        // standing in for a number we don't have.
        let liquidity = uniswap.positions.reduce(0) { $0 + ($1.valueUSD ?? 0) }
        if liquidity >= floor {
            out.deposits.append(Deposit(place: "Uniswap", usd: liquidity))
        }

        // A perp account's value plus its spot book — both sit on Hyperliquid's
        // own L1, which no wallet-holdings read in this app reaches, so this is
        // the only path by which they appear anywhere on the screen.
        let hyper = hyperliquid.perpAccountValue + hyperliquid.spotUsd
        if hyper >= floor {
            out.deposits.append(Deposit(place: "Hyperliquid", usd: hyper))
        }

        // An ether.fi Cash account is a smart account holding collateral with
        // a credit line drawn against it — the same deposited/owed pair as a
        // lending protocol, and named for the card rather than folded under
        // "ether.fi", because the staking side is a different product.
        if etherfiCash.collateralUSD >= floor {
            out.deposits.append(Deposit(place: "ether.fi Cash", usd: etherfiCash.collateralUSD))
        }
        if etherfiCash.debtUSD >= floor {
            out.debts.append(Debt(place: "ether.fi Cash", usd: etherfiCash.debtUSD))
        }

        // Locked, in units (rule 2), ONE ENTRY PER LOCK. veAERO leads — it's
        // the larger and more deliberate lock of the two, and the only one
        // that decays.
        for lock in aerodrome.locks where lock.amountAERO > 0 {
            out.locks.append(Lock(id: "aero:\(lock.tokenId)",
                                  place: "Aerodrome",
                                  symbol: "AERO",
                                  amount: lock.amountAERO,
                                  power: lock.votingPower,
                                  until: lock.lockEnd,
                                  isPermanent: lock.isPermanent))
        }
        for delegation in hyperliquid.delegations where delegation.amountHYPE > 0 {
            out.locks.append(Lock(id: "hype:\(delegation.validator)",
                                  place: "Hyperliquid",
                                  symbol: "HYPE",
                                  amount: delegation.amountHYPE,
                                  // Staked HYPE doesn't decay — it sits until
                                  // its unlock, so it gets no melt.
                                  power: nil,
                                  until: delegation.lockedUntil,
                                  isPermanent: false))
        }

        // An ether.fi unstake request is money that has left the wallet's
        // balance and not yet arrived — committed, unusable, and reported in
        // ETH rather than dollars like every other lock (rule 2). No decay
        // (`power` nil) and no end date: ether.fi finalizes in batches at its
        // own pace, so an `until` here would be invented. ONE ENTRY PER
        // REQUEST, for the same reason two veNFTs never merge.
        for request in etherfiUnstake.requests where request.amount > 0 {
            out.locks.append(Lock(id: "etherfi:\(request.tokenId)",
                                  place: "ether.fi",
                                  symbol: "ETH",
                                  amount: request.claimable ?? request.amount,
                                  power: nil,
                                  until: nil,
                                  isPermanent: false))
        }

        // Biggest first within each list — the room's own convention (the
        // treemap, the allocation tray and the holdings rows all lead with
        // the largest). Locks sort inside their protocol so the two families
        // don't interleave.
        out.deposits.sort { $0.usd > $1.usd }
        out.debts.sort { $0.usd > $1.usd }
        out.locks.sort {
            $0.place == $1.place ? $0.amount > $1.amount : $0.place < $1.place
        }
        return out
    }

    // MARK: - Probe

    /// One line per fact, for `-compositionProbe`. Named places included: the
    /// number alone can't tell "Morpho didn't answer" from "no Morpho
    /// position", and for a read that exists to close a blind spot, that
    /// distinction is the whole point.
    var probeLines: [String] {
        guard !isEmpty else { return ["(nothing outside the wallets)"] }
        var lines: [String] = []
        if hasDeposited {
            lines.append("deposited=\(WalletIngest.format(deposited)) places=[\(depositedPlaces.joined(separator: ","))]")
            for deposit in deposits {
                lines.append("  deposit \(deposit.place)=\(WalletIngest.format(deposit.usd))")
            }
        }
        for lock in locks {
            // The melt is the one number the tray draws that nothing else in
            // the app states, so the probe prints it rather than the amount
            // alone — "did the decay read" and "did the lock read" are
            // different failures.
            let melt = lock.remaining.map { " remaining=\(Int(($0 * 100).rounded()))%" }
                ?? (lock.isPermanent ? " permanent" : " no-decay")
            let ends = lock.until.map { " until=\(ISO8601DateFormatter().string(from: $0))" } ?? ""
            lines.append("  lock \(lock.place) \(WalletIngest.format(lock.amount)) \(lock.symbol)\(melt)\(ends)")
        }
        if hasOwed {
            lines.append("owed=\(WalletIngest.format(owed)) places=[\(owedPlaces.joined(separator: ","))]")
            for debt in debts {
                lines.append("  debt \(debt.place)=\(WalletIngest.format(debt.usd))")
            }
        }
        return lines
    }
}
