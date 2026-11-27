import Foundation

/// **TACIT'S FARMS (prd §1993).** Tacit pays TAC to whoever keeps private
/// liquidity in its pools on Ethereum: an LP share bonded into a farm earns a
/// part of the farm's TAC stream. Tacit's farm program says, for anyone and
/// with no key, how much TAC each pool streams in a year and how many of its
/// shares are bonded; the pool says its reserves.
///
/// A rate is priced from Tacit's own pools, never a price from elsewhere:
/// every farm pairs TAC or cETH, and the TAC/cETH pool says what an ETH is in
/// TAC. So a pool's worth is twice the side we can name, in TAC, and its rate
/// is the TAC it pays in a year over the TAC its bonded shares are worth.
/// Foundation only, so `tacit-farms-selftest.sh` compiles it alone.
enum TacitFarms {
    struct Pool: Codable, Equatable, Identifiable {
        let pair: String
        let lpAsset: String
        /// TAC paid to the pool's bonded shares over a year at today's stream.
        let tacPerYear: Double
        let staked: Double
        let shares: Double
        let a: String
        let b: String
        let reserveA: Double
        let reserveB: Double
        var id: String { lpAsset }
    }

    struct Reading: Codable, Equatable {
        let pools: [Pool]
        /// False once this round of rewards has ended: every rate is then nil.
        let active: Bool
        let endsAt: Date
        let asOf: Date
    }

    /// A farm position of yours: shares of one pool, and TAC earned, unclaimed.
    struct Position: Codable, Equatable, Identifiable {
        let pair: String
        let lpAsset: String
        let shares: Double
        let pendingTAC: Double
        var id: String { lpAsset }
    }

    /// Value units are 8 decimals for every asset the farms pair.
    static let unit = 1e8

    static func reading(_ wire: TacitEngineWire.Farms, at now: Date) -> Reading? {
        let pools = wire.pools.compactMap { p -> Pool? in
            guard let year = TacitEngineWire.number(p.perYear), let staked = TacitEngineWire.number(p.staked),
                  let shares = TacitEngineWire.number(p.shares), let ra = TacitEngineWire.number(p.reserveA),
                  let rb = TacitEngineWire.number(p.reserveB), !p.pair.isEmpty else { return nil }
            return Pool(pair: p.pair, lpAsset: p.lpAsset.lowercased(), tacPerYear: year / unit, staked: staked, shares: shares,
                        a: p.a, b: p.b, reserveA: ra / unit, reserveB: rb / unit)
        }
        guard !pools.isEmpty else { return nil }
        return Reading(pools: pools, active: wire.active, endsAt: now.addingTimeInterval(TimeInterval(max(0, wire.remaining))), asOf: now)
    }

    static func position(_ wire: TacitEngineWire.Farmed.Position) -> Position? {
        guard let shares = TacitEngineWire.number(wire.shares), shares > 0,
              let pending = TacitEngineWire.number(wire.pending) else { return nil }
        return Position(pair: wire.pair, lpAsset: wire.lpAsset.lowercased(), shares: shares, pendingTAC: pending / unit)
    }

    /// What one ETH is in TAC, off the TAC/cETH pool; nil without it.
    static func ethInTAC(_ pools: [Pool]) -> Double? {
        for p in pools {
            if p.a == "cETH", p.b == "TAC", p.reserveA > 0 { return p.reserveB / p.reserveA }
            if p.a == "TAC", p.b == "cETH", p.reserveB > 0 { return p.reserveA / p.reserveB }
        }
        return nil
    }

    /// The whole pool's worth in TAC: twice the side we can name.
    static func worthTAC(_ pool: Pool, ethInTAC: Double?) -> Double? {
        let side: Double?
        if pool.a == "TAC" { side = pool.reserveA }
        else if pool.b == "TAC" { side = pool.reserveB }
        else if pool.a == "cETH" { side = ethInTAC.map { pool.reserveA * $0 } }
        else if pool.b == "cETH" { side = ethInTAC.map { pool.reserveB * $0 } }
        else { side = nil }
        guard let side, side > 0 else { return nil }
        return 2 * side
    }

    /// A year's TAC over what the bonded shares are worth, as a fraction
    /// (2.02 is 202%); nil when rewards ended, nobody is bonded, or the pool
    /// cannot be priced.
    static func rate(_ pool: Pool, in reading: Reading) -> Double? {
        guard reading.active, pool.shares > 0, pool.staked > 0,
              let worth = worthTAC(pool, ethInTAC: ethInTAC(reading.pools)) else { return nil }
        let bonded = worth * min(1, pool.staked / pool.shares)
        guard bonded > 0 else { return nil }
        return pool.tacPerYear / bonded
    }

    /// What a position's shares are worth in TAC today, unclaimed TAC apart.
    static func worthTAC(_ position: Position, in reading: Reading) -> Double? {
        guard let pool = reading.pools.first(where: { $0.lpAsset == position.lpAsset }), pool.shares > 0,
              let worth = worthTAC(pool, ethInTAC: ethInTAC(reading.pools)) else { return nil }
        return worth * position.shares / pool.shares
    }

    /// "202%": whole percents from 10% up, one place under, as Aave's.
    static func rateWords(_ rate: Double?) -> String? {
        guard let rate, rate > 0, rate.isFinite else { return nil }
        let pct = rate * 100
        return pct < 10 ? String(format: "%.1f%%", pct) : String(format: "%.0f%%", pct)
    }

    /// The pair as Tacit's farm page names it: "TAC/ETH", its private
    /// ETH and BTC called by what they are.
    static func name(_ pair: String) -> String {
        pair.split(separator: "/").map { side in
            side == "cETH" ? "ETH" : side == "cBTC" ? "BTC" : String(side)
        }.joined(separator: "/")
    }

    /// Tacit's own farm page, where a farm is entered and left.
    static let page = URL(string: "https://tacit.finance/farm/")!

    /// The demo's farms: the real pools as read on 2026-11-26.
    static let demo = Reading(pools: [
        Pool(pair: "TAC/cETH", lpAsset: "0x17c56713a7e4a5d679a71def3ff9fa186f1556ef757b0ee6b7a3ed8c9249ef99", tacPerYear: 202_169,
             staked: 104_617_537_650, shares: 104_762_795_228, a: "cETH", b: "TAC", reserveA: 25.82, reserveB: 50_013.56),
        Pool(pair: "cETH/cUSD", lpAsset: "0xd608b0c3806e782cc213e2d52245c3c2fbef455a10410a1f5ccc61ba45262571", tacPerYear: 121_301,
             staked: 12_203_290_494, shares: 12_218_544_622, a: "cETH", b: "cUSD", reserveA: 3.763, reserveB: 4_022.36),
        Pool(pair: "cETH/cBTC", lpAsset: "0x0a0cce175bc483945822c8de3d3926e813269f5e1bbe1f9c853e09ed48b68254", tacPerYear: 80_867,
             staked: 72_942_406, shares: 73_000_719, a: "cETH", b: "cBTC", reserveA: 4.863, reserveB: 0.1105),
        Pool(pair: "SPX/TAC", lpAsset: "0x6aeed821ff89a3e1416a4e1ae85965dfc1a30478f98a9bd7fadd45ed527d2725", tacPerYear: 24_333,
             staked: 508_265_522_775, shares: 508_265_523_775, a: "", b: "TAC", reserveA: 9_332.67, reserveB: 2_922.52),
        Pool(pair: "SPX/cETH", lpAsset: "0x302984ec4f357aed29e6e2be3533ccd72c1e4766e42484f332b3855926af9ad7", tacPerYear: 12_166,
             staked: 16_832_321_093, shares: 16_834_568_765, a: "cETH", b: "", reserveA: 2.153, reserveB: 13_238.18),
    ], active: true, endsAt: Date.now.addingTimeInterval(22 * 86_400), asOf: .now)

    /// The demo's one position: a little TAC/cETH, a few TAC earned.
    static let demoPositions = [Position(pair: "TAC/cETH", lpAsset: "0x17c56713a7e4a5d679a71def3ff9fa186f1556ef757b0ee6b7a3ed8c9249ef99",
                                         shares: 104_762_795_228 * 0.002, pendingTAC: 3.42)]
}
