import Foundation

/// THE CASH THE WALLET TOTAL COUNTS (prd §1048, user: "top number should
/// include cash and exchange balances"). Exchanges were already in it (§163);
/// this is the money held at a bank: Wise's balances and Apple Wallet's asset
/// accounts (Apple Cash, Savings). Both are readings their own seats already
/// store, so this asks no provider for a balance.
///
/// Combined read only, like the exchanges: a page scoped to one address is
/// answering "what does THIS address hold".
enum WalletCash {

    struct Held: Equatable {
        /// ISO currency code: what the money is, and the position it joins.
        let currency: String
        let amount: Double
        /// `cash:` + the place, so `WalletPortfolio.isVenue` knows it is no
        /// address and puts no address verb on it.
        let holderID: String
        let label: String
        /// When the seat read this balance, for Holdings' stamp (prd §1078).
        var readAt: Date? = nil
    }

    static let holderPrefix = "cash:"

    /// Every stored cash reading, by the place it joins (prd §1078).
    static func readings() -> [WalletPortfolio.PlaceReading] {
        held().compactMap { cash in
            cash.readAt.map { WalletPortfolio.PlaceReading(holderID: cash.holderID, label: cash.label, at: $0) }
        }
        .reduce(into: [WalletPortfolio.PlaceReading]()) { out, reading in
            if !out.contains(where: { $0.holderID == reading.holderID }) { out.append(reading) }
        }
    }

    /// Every card balance owed, in words ("$812 owed on Apple Card"), for the
    /// crown's note. Never counted (prd §1078).
    static func owed() -> [String] {
        guard AppleWalletBridge.connected else { return [] }
        return AppleWalletBridge.owed.sorted(by: { $0.key < $1.key }).compactMap { name, balance in
            guard balance.value > 0, balance.currency.count == 3 else { return nil }
            let money = balance.value.formatted(.currency(code: balance.currency))
            return String(localized: "\(money) owed on \(name)")
        }
    }

    /// Every cash balance the seats hold right now. Off main: it reads the
    /// Keychain (`WiseAuth.configured`).
    static func held() -> [Held] {
        var out: [Held] = []
        if WiseAuth.configured {
            for balance in WiseState.standing.balances {
                guard let value = balance.value, value > 0, balance.currency.count == 3 else { continue }
                out.append(Held(currency: balance.currency, amount: value,
                                holderID: holderPrefix + "wise", label: "Wise",
                                readAt: WiseState.standing.lastRead))
            }
        }
        // Bitrefill's balance (prd §1051a): money held to spend on gift cards,
        // read only while the seat is connected, as its room's lede was.
        if TokenBridge.bitrefill.connected, let balance = BitrefillBalance.reading,
           balance.amount > 0, balance.currency.count == 3 {
            out.append(Held(currency: balance.currency, amount: balance.amount,
                            holderID: holderPrefix + "bitrefill", label: "Bitrefill"))
        }
        // A Lightning wallet's balance (prd §1098), in bitcoin, priced by
        // `rates` off the same source the on-chain balance uses.
        if LightningAuth.configured, let sats = LightningState.balanceSats, sats > 0 {
            out.append(Held(currency: "BTC", amount: Double(sats) / 100_000_000,
                            holderID: holderPrefix + "lightning", label: "Lightning",
                            readAt: LightningState.readAt))
        }
        if AppleWalletBridge.connected {
            for (name, balance) in AppleWalletBridge.cash.sorted(by: { $0.key < $1.key }) {
                guard balance.value > 0, balance.currency.count == 3 else { continue }
                out.append(Held(currency: balance.currency, amount: balance.value,
                                holderID: holderPrefix + "applewallet:" + name, label: name,
                                readAt: AppleWalletBridge.balancesAt))
            }
        }
        return out
    }

    /// The pairs Kraken quotes against USD, from its own `AssetPairs`
    /// (measured 2026-10-01): EUR, GBP and AUD as XXXUSD; CAD, JPY and CHF as
    /// USDXXX. Kraken lists no other fiat against USD. Only these are ever
    /// asked, because ONE pair it doesn't know fails the whole call
    /// (`EQuery:Unknown asset pair`, measured with EURUSD,CADUSD).
    static let quotedOverUSD: Set<String> = ["EUR", "GBP", "AUD"]
    static let quotedUnderUSD: Set<String> = ["CAD", "JPY", "CHF"]

    /// Dollars per one unit of `currency`, or nil when Kraken can't price it.
    /// Pure, so the arithmetic is testable without the network.
    static func usd(_ amount: Double, _ currency: String, rates: [String: Double]) -> Double? {
        if currency == "USD" { return amount }
        guard let rate = rates[currency], rate > 0 else { return nil }
        return amount * rate
    }

    /// Kraken's mid price for each priceable code, as USD per unit (a USDXXX
    /// quote is inverted).
    static func rates(for currencies: Set<String>) async -> [String: Double] {
        // Bitcoin (a Lightning balance, prd §1098) is priced where the
        // on-chain balance is, never by Kraken's fiat pairs.
        var bitcoin: [String: Double] = [:]
        if currencies.contains("BTC"), let price = await BitcoinBridge.priceUSD() { bitcoin["BTC"] = price }
        let wanted = currencies.filter { quotedOverUSD.contains($0) || quotedUnderUSD.contains($0) }
        guard !wanted.isEmpty else { return bitcoin }
        let pairs = wanted.sorted()
            .map { quotedOverUSD.contains($0) ? $0 + "USD" : "USD" + $0 }
            .joined(separator: ",")
        guard let url = URL(string: "https://api.kraken.com/0/public/Ticker?pair=\(pairs)"),
              let root = await IngestSupport.getJSON(url) as? [String: Any],
              let result = root["result"] as? [String: Any]
        else { return bitcoin }
        var out: [String: Double] = [:]
        for code in wanted {
            // Kraken answers under its own names (ZEURZUSD, ZUSDZCAD, AUDUSD),
            // and each holds exactly one of the six codes.
            guard let quote = result.first(where: { $0.key.contains(code) })?.value as? [String: Any],
                  let ask = Double(((quote["a"] as? [Any])?.first as? String) ?? ""),
                  let bid = Double(((quote["b"] as? [Any])?.first as? String) ?? ""),
                  ask > 0, bid > 0 else { continue }
            let mid = (ask + bid) / 2
            out[code] = quotedOverUSD.contains(code) ? mid : 1 / mid
        }
        return out.merging(bitcoin) { a, _ in a }
    }

    /// `rates(for:)`, remembered for ten minutes per code, so a figure that
    /// asks on every appearance (the Cards tile, prd §1078) asks Kraken once.
    static func cachedRates(for currencies: Set<String>) async -> [String: Double] {
        // The demo reaches nothing (§483): its euros convert at a fixed sample
        // rate, which the figure names as one (`isSampleRate`).
        if isSampleRate { return demoRates.filter { currencies.contains($0.key) } }
        return await RateCache.shared.rates(for: currencies)
    }

    /// True in the demo, where `cachedRates` answers from `demoRates`.
    static var isSampleRate: Bool { DemoMode.isActive }
    static let demoRates: [String: Double] = ["EUR": 1.08, "GBP": 1.27]

    private actor RateCache {
        static let shared = RateCache()
        private var held: [String: (rate: Double, at: Date)] = [:]
        private static let life: TimeInterval = 600

        func rates(for currencies: Set<String>) async -> [String: Double] {
            let now = Date()
            let stale = currencies.filter { code in
                guard code != "USD", let hit = held[code] else { return code != "USD" }
                return now.timeIntervalSince(hit.at) > Self.life
            }
            if !stale.isEmpty {
                for (code, rate) in await WalletCash.rates(for: stale) {
                    held[code] = (rate, now)
                }
            }
            return held.filter { currencies.contains($0.key) }.mapValues(\.rate)
        }
    }

    /// The cash in dollars, ready for `WalletPortfolio.from(venues:)`. A
    /// currency Kraken cannot price is LEFT OUT rather than guessed, and named
    /// in `unpriced` ("SGD at Wise") so the total can say so (§83, §827).
    static func priced() async -> (priced: [(symbol: String, usd: Double, holderID: String, label: String)],
                                   unpriced: [String]) {
        let held = held()
        guard !held.isEmpty else { return ([], []) }
        let rates = await rates(for: Set(held.map(\.currency)))
        var out: [(symbol: String, usd: Double, holderID: String, label: String)] = []
        var unpriced: [String] = []
        for cash in held {
            guard let usd = usd(cash.amount, cash.currency, rates: rates) else {
                unpriced.append("\(cash.currency) at \(cash.label)")
                continue
            }
            out.append((cash.currency, usd, cash.holderID, cash.label))
        }
        return (out, unpriced)
    }
}
