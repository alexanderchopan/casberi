import Foundation
import Observation

/// What the app shows of your Aztec account (prd §1700, §1700a), kept between
/// launches so the row and Holdings draw at once, before the engine has read.
///
/// - **Used.** The row appears only once the account has been used (an Aztec
///   app connected, money moved to it, something received; §1700a item 2),
///   never as an empty "$0 Aztec" row. The engine's first use marks it.
/// - **The last reading.** The engine's `holdings` (Fee Juice and every token an
///   app taught the wallet), stamped with when it was read; a read that fails
///   keeps the last one (§1548, §825's rule for the Wallet).
///
/// The address is the account's public face (its tail on rows); nothing here
/// is a key. On the Mac the store shows what the iPhone last read through
/// iCloud only once the engine has run there; the Mac has no prover (§1700).
@MainActor
@Observable
final class AztecAccountStore {

    static let shared = AztecAccountStore()

    struct Holding: Codable, Equatable, Identifiable {
        enum Kind: String, Codable { case feeJuice, token }
        let kind: Kind
        /// The token's contract on Aztec.
        let address: String
        /// "Fee Juice", or the token contract's own name until a symbol is known.
        let name: String
        /// Nil when the token's contract would not say: no amount is shown then.
        let decimals: Int?
        /// Base units, as text (they overflow 64 bits). Nil: that side was not read.
        let privateUnits: String?
        let publicUnits: String?
        var id: String { address }

        /// What the account holds of it, in whole tokens, private and public
        /// together; nil when the decimals are unknown.
        var amount: Decimal? {
            guard let decimals else { return nil }
            let units = [privateUnits, publicUnits].compactMap { $0.flatMap { Decimal(string: $0) } }.reduce(0, +)
            return units / pow(10, decimals)
        }

        /// Whether any of it is held, decimals or not.
        var isHeld: Bool {
            [privateUnits, publicUnits].contains { ($0.flatMap { Decimal(string: $0) } ?? 0) > 0 }
        }

        /// **GAS, BOTH PLACES (prd §1700aa).** Fee Juice the account can spend:
        /// its own (public on Aztec) and what it keeps inside the private fee
        /// contract (`privateUnits`, read by the engine), base units together.
        var gasUnits: Decimal {
            [privateUnits, publicUnits].compactMap { $0.flatMap { Decimal(string: $0) } }.reduce(0, +)
        }
    }

    /// One gas deposit (prd §1700e item 2): the Safe's AZTEC into Aztec's
    /// Fee Juice portal, waiting for Aztec to carry it, then claimed. Its
    /// claim secret is derived from the root and `nonce`, never stored.
    struct GasDeposit: Codable, Equatable, Identifiable {
        let nonce: UInt64
        /// AZTEC base units (18 decimals), as text.
        let amountUnits: String
        let transaction: String
        /// The message Aztec carries (the portal event's `key`) and its place.
        let messageHash: String
        let leafIndex: String
        var claimed: Bool
        let at: Date
        /// Where it went (prd §1700aa): `"private"`, to the shared private fee
        /// contract, minted by the next send; nil or `"own"` (every deposit
        /// before §1700aa), to the account itself, claimed on its own.
        var kind: String?
        var id: UInt64 { nonce }
        var isPrivate: Bool { kind == "private" }
    }

    /// One Shield deposit (prd §1700e): USDC or WETH from the Safe through
    /// Shield's portal, waiting for Aztec, then claimed privately. Its secret
    /// is derived from the root and `nonce`, never stored.
    struct ShieldDeposit: Codable, Equatable, Identifiable {
        let nonce: UInt64
        let symbol: String
        /// What arrives, after Shield's fee, in the token's base units.
        let amountUnits: String
        let transaction: String
        let messageHash: String
        let leafIndex: String
        var claimed: Bool
        let at: Date
        var id: UInt64 { nonce }
    }

    /// One move out through Shield (prd §1700b): burnt on Aztec with a
    /// message to Shield's portal, then withdrawn on Ethereum to `recipient`
    /// once Aztec's epoch is proven there (an hour or more).
    struct ShieldExit: Codable, Equatable, Identifiable {
        let symbol: String
        let amountUnits: String
        let recipient: String
        /// The Aztec transaction and the L2-to-L1 message it sent.
        let transaction: String
        let message: String
        let outbox: String?
        var withdrawal: String?
        let at: Date
        var id: String { transaction }
        var withdrawn: Bool { withdrawal != nil }
    }

    struct Snapshot: Codable, Equatable {
        var used = false
        var address: String?
        var holdings: [Holding] = []
        var readAt: Date?
        /// Optional so a reading saved before gas existed still decodes.
        var gas: [GasDeposit]?
        var shield: [ShieldDeposit]?
        var exits: [ShieldExit]?
    }

    private(set) var snapshot: Snapshot

    private static let key = "aztec.account.v1"

    private init() {
        snapshot = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) } ?? Snapshot()
    }

    /// What the screens show: the demo's sample account in the demo (prd
    /// §1618: demo data on every tab, never the phone's own), else this
    /// phone's reading.
    var shown: Snapshot { DemoMode.isActive ? Self.demo : snapshot }

    /// Whether the account shows: once you HAVE it (prd §1700t, amending
    /// §1700a item 2's "once it is used"). On an iPhone that is the moment
    /// there is Your account; on the Mac, once the iPhone has used it.
    var isShown: Bool {
        shown.used || (YourAccountKey.address != nil && AztecProver.isAvailable)
    }

    /// Whether its address is known yet: the engine derives it, so an
    /// account never opened has none until its first read (`walletAccountList`).
    var addressKnown: Bool { shown.address != nil }

    /// The demo's Aztec account: an address no key derives, a little private
    /// USDC on Aztec (Shield's bridged USDC) and some Fee Juice for gas.
    static let demo = Snapshot(
        used: true,
        address: "0x0de70a11ce0c4f7e2b9a1d3c5e7f90b2d4a6c8e01f2a3b4c5d6e7f8091a2b3c",
        holdings: [
            Holding(kind: .token, address: "0x30112e52178143b74cf6037d047bbba924f4b0db8aab587a340aacfc6ecb4f38",
                    name: "USDC", decimals: 6, privateUnits: "120000000", publicUnits: "0"),
            Holding(kind: .feeJuice, address: "0x0000000000000000000000000000000000000000000000000000000000000003",
                    name: "Fee Juice", decimals: 18, privateUnits: nil, publicUnits: "2500000000000000000"),
        ],
        readAt: nil)

    // MARK: - Worth (prd §1700e)

    /// The tokens on Aztec that have a dollar price: Shield's USDC and WETH,
    /// by their contract (pinned, `ShieldBridge`), each the coin it carries.
    /// Never by symbol: any app can register a token that calls itself USDC.
    /// Fee Juice has none on purpose: it pays Aztec's gas and can go nowhere
    /// else, so it is not money you could spend.
    static let priced: [String: String] = [
        "0x30112e52178143b74cf6037d047bbba924f4b0db8aab587a340aacfc6ecb4f38": "usdc",
        "0x2a36cedc4f7fa6bd9fbb77ab799737f30d12cd86ffa9d9d63737d51a6e7247fe": "weth",
    ]
    /// The block's name in the Wallet's box and its holder.
    static let walletSymbol = "Aztec"
    static let holderID = "aztec"

    /// USD per coin, by the coin's mainnet symbol, from the last read.
    private(set) var prices: [String: Double] = [:]

    /// A holding's worth in dollars, or nil when it has no price.
    func usd(_ holding: Holding) -> Double? {
        guard let amount = holding.amount else { return nil }
        return usd(holding, amount: amount)
    }

    /// The worth of one side of a holding (its private or its public part).
    func usd(_ holding: Holding, units: String?) -> Double? {
        guard let decimals = holding.decimals, let units = units.flatMap({ Decimal(string: $0) }), units > 0 else { return nil }
        return usd(holding, amount: units / pow(10, decimals))
    }

    private func usd(_ holding: Holding, amount: Decimal) -> Double? {
        guard holding.kind == .token, let coin = Self.priced[holding.address.lowercased()],
              let price = prices[coin] else { return nil }
        return NSDecimalNumber(decimal: amount).doubleValue * price
    }

    /// What is private on Aztec, and what stands under Tokens. Gas is one row
    /// there wherever it is kept (prd §1700aa): the account's own Fee Juice,
    /// public on Aztec by design, and what it keeps in the private fee
    /// contract, which no one else can read.
    var privateHeld: [Holding] {
        shown.holdings.filter { h in h.kind == .token && (h.privateUnits.flatMap { Decimal(string: $0) } ?? 0) > 0 }
    }
    var publicHeld: [Holding] {
        shown.holdings.filter { h in
            h.kind == .feeJuice ? h.gasUnits > 0 : (h.publicUnits.flatMap { Decimal(string: $0) } ?? 0) > 0
        }
        .sorted { a, _ in a.kind == .feeJuice }
    }

    /// **AZTEC COUNTS IN THE WALLET** as private money does
    /// (`PrivateMoneyStore.walletHolding`): one block named Aztec, its priced
    /// tokens in dollars, counted once, on All and Yours. Its own place, never
    /// folded into 0xBow's Private (§1700 item 4).
    func walletHolding() async -> [(symbol: String, usd: Double, holderID: String, label: String)] {
        guard isShown else { return [] }
        let coins = shown.holdings.filter(\.isHeld).compactMap { Self.priced[$0.address.lowercased()] }
        guard !coins.isEmpty else { return [] }
        let found = await MainnetPrices.prices(for: coins)
        if found != prices { prices = found }
        let total = shown.holdings.compactMap(usd).reduce(0, +)
        NSLog("aztecEngine| worth | $%.2f | %d prices", total, found.count)
        return total > 0 ? [(symbol: Self.walletSymbol, usd: total, holderID: Self.holderID,
                             label: String(localized: "Aztec"))] : []
    }

    /// The account was used: an app connected, money moved to it, something arrived.
    func markUsed(address: String) {
        guard !snapshot.used || snapshot.address != address else { return }
        snapshot.used = true
        snapshot.address = address
        save()
    }

    func addGas(_ deposit: GasDeposit) {
        snapshot.gas = (snapshot.gas ?? []) + [deposit]
        snapshot.used = true
        save()
    }

    func addShield(_ deposit: ShieldDeposit) {
        snapshot.shield = (snapshot.shield ?? []) + [deposit]
        snapshot.used = true
        save()
    }

    func markShieldClaimed(_ nonce: UInt64) {
        guard let i = snapshot.shield?.firstIndex(where: { $0.nonce == nonce }) else { return }
        snapshot.shield?[i].claimed = true
        save()
    }

    /// Exits not yet withdrawn on Ethereum (Needs you's rows; none in the demo).
    var pendingExits: [ShieldExit] {
        DemoMode.isActive ? [] : (snapshot.exits ?? []).filter { !$0.withdrawn }
    }

    /// "25 USDC": an exit's amount in its token.
    static func figure(_ exit: ShieldExit) -> String {
        let decimals = exit.symbol == "USDC" ? 6 : 18
        return PrivateMoney.figure(exit.amountUnits, decimals: decimals, symbol: exit.symbol)
    }

    /// An exit's worth in dollars at the last read price, or nil.
    func usd(_ exit: ShieldExit) -> Double? {
        guard let price = prices[exit.symbol.lowercased()],
              let units = Decimal(string: exit.amountUnits) else { return nil }
        return NSDecimalNumber(decimal: units / pow(10, exit.symbol == "USDC" ? 6 : 18)).doubleValue * price
    }

    func addExit(_ exit: ShieldExit) {
        snapshot.exits = (snapshot.exits ?? []) + [exit]
        save()
    }

    func markExitWithdrawn(_ transaction: String, withdrawal: String) {
        guard let i = snapshot.exits?.firstIndex(where: { $0.transaction == transaction }) else { return }
        snapshot.exits?[i].withdrawal = withdrawal
        save()
    }

    func markGasClaimed(_ nonce: UInt64) {
        guard let i = snapshot.gas?.firstIndex(where: { $0.nonce == nonce }) else { return }
        snapshot.gas?[i].claimed = true
        save()
    }

    /// Reads the engine's holdings and keeps them; a failed read keeps the last.
    /// One read at a time: Holdings' Private and Tokens both ask.
    private var reading = false

    @discardableResult
    func refresh() async -> Bool {
        guard !reading else { return false }
        reading = true
        defer { reading = false }
        do {
            let address = try await AztecEngine.shared.accountAddress()
            guard let rows = try await AztecEngine.shared.call("holdings") as? [[String: Any]] else { return false }
            snapshot.address = address
            snapshot.holdings = rows.compactMap(Self.holding)
            snapshot.readAt = Date()
            if snapshot.holdings.contains(where: \.isHeld) { snapshot.used = true }
            save()
            return true
        } catch {
            NSLog("aztecEngine| holdings | kept the last reading: %@", error.localizedDescription)
            return false
        }
    }

    /// **THE ENGINE STARTS BEFORE IT IS ASKED (prd §1700v, user, 2026-11-09:
    /// "start engine early: ok, lets do that").** A cold engine took 51 s to
    /// name the account (measured 2026-11-08 on the simulator), so the row,
    /// Move's Aztec line and an Aztec app in the browser waited on it. The app
    /// coming back, or the Wallet opening (`MoveWarm`, at most once a minute),
    /// starts it and reads the account once the launch has drawn and no finger
    /// is down. Only on an iPhone with Your account (the prover; §1700t's
    /// "have it"), never in the demo; a read under way is joined, not doubled.
    func warm() {
        guard YourAccountKey.address != nil, AztecProver.isAvailable, !DemoMode.isActive, !reading else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            await GestureGate.idle()
            guard !DemoMode.isActive else { return }
            await refresh()
        }
    }

    /// **A PULL ON THE WALLET ASKS THE ACCOUNT** (user, 2026-11-07: the rain
    /// "should also show the Aztec icon, not just safe"). Reads the holdings
    /// again and their prices, whatever the last reading's age, and says
    /// whether the account was asked, which is when its tile falls (prd §619:
    /// the rain is the apps the pull asks). The demo's account is sample data
    /// and reads nothing, as every demo seat rains and reads nothing; a build
    /// with no prover (the Mac) cannot ask, so it rains no Aztec.
    func pull() -> Bool {
        // Read only an account the engine has run for once (§1700t): a pull
        // never starts it cold for someone who has not opened Aztec.
        guard isShown, shown.used || addressKnown else { return false }
        if DemoMode.isActive { return true }
        guard AztecProver.isAvailable else { return false }
        Task { @MainActor in
            await refresh()
            _ = await walletHolding()
        }
        return true
    }

    private static func holding(_ row: [String: Any]) -> Holding? {
        guard let kind = (row["kind"] as? String).flatMap(Holding.Kind.init), let address = row["address"] as? String else { return nil }
        return Holding(kind: kind, address: address,
                       name: row["symbol"] as? String ?? row["name"] as? String ?? AddressTail.short(address),
                       decimals: row["decimals"] as? Int,
                       privateUnits: row["private"] as? String,
                       publicUnits: row["public"] as? String)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        DefaultsWrite.set(data, forKey: Self.key)
    }
}
