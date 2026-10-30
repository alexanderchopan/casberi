import Foundation

/// **HOW MANY DEPOSITS YOUR PRIVATE MONEY HIDES AMONG (prd §1614).** 0xBow's
/// v2 ASP publishes `acceptedDepositsCount` per asset at
/// `api-v2.0xbow.io/1/public/assets-stats` (measured 2026-10-29: ETH 14,
/// ppETH 170, ppUSDC 117, ppUSDT 56, chain 1 only). Only approved deposits
/// sit in the tree a withdrawal proves against, so that count is the crowd.
/// v1's `pools-stats` counts v1 pools, a different crowd, and is never used
/// for v2 money.
///
/// Read at most once a day into `UserDefaults` (no `Thing` property, so no
/// CloudKit deploy); no reading is "say nothing", never a guessed number.
enum PrivacyPoolsCrowd {
    static let url = "https://api-v2.0xbow.io/1/public/assets-stats"
    private static let countsKey = "privacypools.crowd.v2"
    private static let readKey = "privacypools.crowd.v2.read"
    static let refreshInterval: TimeInterval = 24 * 60 * 60

    /// Each asset's crowd, by lowercased asset address, Ethereum only. The
    /// demo reaches no host: it draws the counts measured 2026-10-29.
    static func counts() -> [String: Int] {
        if DemoMode.isActive { return demoCounts }
        return (UserDefaults.standard.dictionary(forKey: countsKey) as? [String: Int]) ?? [:]
    }

    static let demoCounts: [String: Int] = [
        "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee": 14,
        "0x66051920d25af4e3596a8a46309f4d045f9d83b7": 170,
        "0xc246afb23482ff9596e9cee5f1f678efe0eb1ad6": 117,
        "0xa4cf419558ef36cc6ffb666195684dc963910426": 56,
    ]

    /// `assets-stats`'s body into counts: chain 1, an asset and a count, or
    /// the asset is left out.
    static func parse(_ json: Any?) -> [String: Int] {
        guard let root = json as? [String: Any], let assets = root["assets"] as? [[String: Any]] else { return [:] }
        var out: [String: Int] = [:]
        for a in assets {
            guard (a["chainId"] as? String) == "1" || (a["chainId"] as? Int) == 1,
                  let asset = (a["asset"] as? String)?.lowercased(),
                  let count = a["acceptedDepositsCount"] as? Int else { continue }
            out[asset] = count
        }
        return out
    }

    /// Reads the counts once a day.
    @MainActor
    static func refresh(now: Date = .now) async {
        guard !DemoMode.isActive else { return }
        if let last = UserDefaults.standard.object(forKey: readKey) as? Date,
           now.timeIntervalSince(last) < refreshInterval, !counts().isEmpty { return }
        let read = parse(await IngestSupport.getJSON(url))
        guard !read.isEmpty else { return }
        UserDefaults.standard.set(read, forKey: countsKey)
        UserDefaults.standard.set(now, forKey: readKey)
    }

    /// The asset a row's money sits in on `chainId`: the yield pool's share
    /// where its token earns there (every Ethereum deposit, §1541), else the
    /// token itself. Nil off Ethereum, where 0xBow publishes no count.
    static func asset(symbol: String, chainId: Int, share: String? = nil, plain: Bool = false) -> String? {
        guard chainId == 1 else { return nil }
        // The note's own pool where it is known: a plain note hides among the
        // plain pool's deposits, never the yield pool's.
        if let share { return share.lowercased() }
        if !plain, let pool = PrivacyNetwork.forChain(chainId)?.yield.first(where: { $0.symbol == symbol }) {
            return pool.share.lowercased()
        }
        return PrivacyPoolsBridge.v2Assets.first { $0.value.symbol == symbol }?.key
    }

    /// The crowd a row hides among, or nil when none was read.
    static func crowd(symbol: String, chainId: Int, share: String? = nil, plain: Bool = false,
                      counts: [String: Int] = counts()) -> Int? {
        asset(symbol: symbol, chainId: chainId, share: share, plain: plain).flatMap { counts[$0] }
    }

    /// A deposit younger than this is easy to tie to a send from it: the
    /// fewer deposits since, the fewer it could be.
    static let settleTime: TimeInterval = 24 * 60 * 60

    /// Whether sending from money that landed at `newest` would be easy to link.
    static func tooSoon(newest: Date?, now: Date = .now) -> Bool {
        guard let newest else { return false }
        return now.timeIntervalSince(newest) < settleTime
    }
}
