import Foundation

/// **WHAT YOUR RAILGUN WALLET HOLDS, FOR THE SCREENS (prd §1713, §1721).**
/// The private balance for every token on Ethereum other than ETH and USDC:
/// the engine's own balances (item 4: whatever the wallet holds, whether or
/// not Casberi put it there), each token named by its contract and priced
/// where Casberi can price it. Holdings' Private block, Send's token list and
/// the Wallet's total read it; nothing here moves money.
///
/// - **Read only where a wallet exists** (`RailgunPocket.hasWallet`): no
///   private root is ever made just to look. Opened with no reason (the
///   reads need no Face ID, §1713), synced, every root checked; a sync the
///   roots do not confirm keeps the last reading.
/// - **At most every ten minutes**: a sync is half a minute or more.
/// - **The last reading stands** across launches, per account, so the rows
///   draw before the engine has synced.
/// - **The demo** holds 400 DAI, spendable, and 0.6 LINK still in Railgun's
///   screening ("Private in about an hour"), only in a build that carries
///   the engine.
@MainActor
@Observable
final class RailgunHoldings {
    static let shared = RailgunHoldings()

    /// One token in the wallet: the whole amount and what Railgun's
    /// screening has listed (spendable now). Base units, decimal.
    struct Held: Codable, Equatable, Identifiable {
        let contract: String
        let symbol: String
        let decimals: Int
        let amount: String
        let spendable: String
        var id: String { contract.lowercased() }

        /// Shielded and not yet listed: "Private in about an hour".
        var pending: String {
            let p = (Decimal(string: amount) ?? 0) - (Decimal(string: spendable) ?? 0)
            return p > 0 ? NSDecimalNumber(decimal: p).stringValue : "0"
        }
    }

    private struct Reading: Codable {
        let account: String
        let held: [Held]
        let at: Date
    }

    private(set) var reading: [Held]
    private(set) var readAt: Date?
    /// Dollars for one whole token, by symbol (upper case).
    private(set) var prices: [String: Double] = [:]
    private(set) var syncing = false

    static let interval: TimeInterval = 10 * 60
    private static let key = "railgun.holdings.v1"

    private init() {
        let saved = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(Reading.self, from: $0) }
        if let saved, saved.account.lowercased() == YourAccountKey.address?.lowercased() {
            reading = saved.held
            readAt = saved.at
        } else {
            reading = []
        }
    }

    /// Whether the screens show Railgun at all: a build with the engine,
    /// and an account (or the demo).
    var shows: Bool { RailgunPocket.available && (DemoMode.isActive || YourAccountKey.address != nil) }

    /// What the screens draw: the demo's, or this phone's last reading.
    var shown: [Held] {
        guard shows else { return [] }
        return DemoMode.isActive ? Self.demo : reading
    }

    /// The spendable part of each token, biggest first: Holdings' and
    /// Send's rows.
    var spendableShown: [Held] {
        shown.filter { (Decimal(string: $0.spendable) ?? 0) > 0 }
            .sorted { (usd($0, units: $0.spendable) ?? 0) > (usd($1, units: $1.spendable) ?? 0) }
    }

    /// The part still in Railgun's screening.
    var pendingShown: [Held] { shown.filter { $0.pending != "0" } }

    func usd(_ h: Held, units: String) -> Double? {
        guard let price = prices[h.symbol.uppercased()] else { return nil }
        return YourAccountOp.dollars(units, decimals: h.decimals, price: price)
    }

    /// "400", "0.6": an amount as a row says it.
    static func figure(_ units: String, decimals: Int) -> String {
        let whole = (Decimal(string: units) ?? 0) / pow(10, decimals)
        return NSDecimalNumber(decimal: whole).doubleValue.formatted(.number.precision(.significantDigits(1...4)))
    }

    /// Reads the wallet when its reading is old (never in the demo), then
    /// the prices.
    func refresh(force: Bool = false) async {
        await readPrices()
        guard shows, !DemoMode.isActive, RailgunPocket.hasWallet, !syncing,
              let account = YourAccountKey.address else { return }
        if !force, let readAt, Date().timeIntervalSince(readAt) < Self.interval { return }
        syncing = true
        defer { syncing = false }
        do {
            try await RailgunPocket.open(reason: nil)
            let synced = try await RailgunPocket.sync()
            var held: [Held] = []
            for b in synced.balances {
                let amount = PrivateMoney.decimal(hex: b.amount)
                guard (Decimal(string: amount) ?? 0) > 0 else { continue }
                let known = reading.first { $0.id == b.token.lowercased() }
                let listed = known == nil ? await YourAccountTokens.lookUp(b.token, on: YourAccountOp.ethereum) : nil
                guard let symbol = known?.symbol ?? listed?.token.symbol,
                      let decimals = known?.decimals ?? listed?.token.decimals else { continue }
                held.append(Held(contract: b.token, symbol: symbol, decimals: decimals,
                                 amount: amount, spendable: PrivateMoney.decimal(hex: b.spendable)))
            }
            reading = held
            readAt = .now
            if let data = try? JSONEncoder().encode(Reading(account: account, held: held, at: .now)) {
                UserDefaults.standard.set(data, forKey: Self.key)
            }
            NSLog("railgunHoldings| read | %d tokens", held.count)
            await readPrices()
        } catch {
            // The last reading stands: a sync the roots did not confirm, or
            // a node that did not answer, shows nothing new as yours.
            NSLog("railgunHoldings| read failed | %@", String(describing: error))
        }
    }

    private func readPrices() async {
        let symbols = Set(shown.map { $0.symbol.lowercased() })
        guard !symbols.isEmpty else { return }
        let found = await MainnetPrices.prices(for: Array(symbols))
        let upper = Dictionary(uniqueKeysWithValues: found.map { ($0.key.uppercased(), $0.value) })
        if upper != prices { prices = upper }
    }

    /// The Wallet's number counts it once, as private money (§1713 item 1:
    /// one Private balance): the whole amount, pending included, priced.
    func walletHolding() async -> [(symbol: String, usd: Double, holderID: String, label: String)] {
        await refresh()
        let total = shown.compactMap { usd($0, units: $0.amount) }.reduce(0, +)
        return total > 0 ? [(symbol: PrivateMoney.walletSymbol, usd: total, holderID: PrivateMoney.holderID,
                             label: String(localized: "Private"))] : []
    }

    /// The demo's Railgun wallet: DAI to spend, LINK still in screening.
    static let demo: [Held] = [
        Held(contract: "0x6B175474E89094C44Da98b954EedeAC495271d0F", symbol: "DAI", decimals: 18,
             amount: "400000000000000000000", spendable: "400000000000000000000"),
        Held(contract: "0x514910771AF9Ca656af840dff83E8264EcF986CA", symbol: "LINK", decimals: 18,
             amount: "600000000000000000", spendable: "0"),
    ]
}
