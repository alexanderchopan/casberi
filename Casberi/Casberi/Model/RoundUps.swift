import Foundation

/// **ROUND-UPS (prd §1452, §1545).** Every dollar send from your account
/// rounds up to the next $1 (or $5), and the change buys a token you pick —
/// ETH on Base unless you choose another — once it reaches $5, with the send
/// that gets it there.
///
/// **How the change buys (prd §1545).** A token on the send's own network is
/// bought on the exchanges, as Swap buys (§1542): the best of the pinned
/// pools, the dollar's exact `approve` to that router and one router call,
/// the minimum written in and the simulation before Face ID. Only a token on
/// ANOTHER network goes through Relay: a plain `transfer` of the dollar to
/// Relay's deposit address for the route (`YourAccountChain.depositAddress`).
///
/// **Who may buy.** A send you approve with Face ID buys. A send the spend
/// limit's session key signs alone never buys on the exchanges: the session
/// may only `transfer` the dollar and send ETH through Multicall3 (§1447
/// item 15), and it is never widened to approve or call a router. Its change
/// keeps counting (`savedAfter(_:bought:)`) and the buy rides your next Face
/// ID send. A Relay buy is itself a `transfer`, so the session carries one to
/// another network as it always did.
///
/// **Why the change waits for $5.** Relay charged a flat few cents a buy
/// (measured 2026-10-21: ~$0.03 on Base), which is why the count began. The
/// pools charge nothing beside their fee, which is in the price, and a swap's
/// gas on Base is about a quarter of a cent (§1539): the $5 now keeps a buy
/// to one swap in several sends, so the network fee stays a sliver of what is
/// bought — on Ethereum, where a swap's gas is dollars, it is what keeps a
/// $0.70 buy from costing more than it buys. One balance, a running count, a
/// buy at $5.
///
/// **What it bought is Spending's Round-ups door (prd §1523)**, never part of
/// the total: the change was kept, not spent. A Relay buy is known by the
/// deposit address this phone asked for (`noteDeposit`); an exchange buy by
/// its own transaction — this account's dollar leaving in exactly the buy's
/// amount, in the hours after it was signed (`noteSwapBuy`, `swapBuy`).
enum RoundUps {
    /// What the change buys. `address` is Relay's spelling: the zero address
    /// for a network's own coin.
    ///
    /// `onExchanges(from:)`: the target is on the send's own network, so the
    /// pools buy it (§1545); anywhere else Relay does.
    struct Target: Codable, Equatable, Hashable, Sendable {
        var chainId: Int
        var address: String
        var symbol: String
        var decimals: Int
        var network: String

        func onExchanges(from chainId: Int) -> Bool { self.chainId == chainId }

        /// The token as the account holds it: nil for the network's own coin.
        var contract: String? {
            address.lowercased() == "0x0000000000000000000000000000000000000000" ? nil : address.lowercased()
        }

        static let ethOnBase = Target(chainId: 8453, address: "0x0000000000000000000000000000000000000000",
                                      symbol: "ETH", decimals: 18, network: "Base")
    }

    struct Setting: Codable, Equatable, Sendable {
        var on = false
        /// Dollars to round up to: 1 or 5.
        var step = 1
        var target = Target.ethOnBase
        /// The change moves into your private balance instead of buying
        /// `target` (prd §1561). Off unless picked; nil reads as off, so a
        /// setting kept before it decodes as it was.
        var toPrivate: Bool? = nil

        /// Picked, and this build has a pool: a setting kept by a DEBUG
        /// build reads as buying `target` in one that has none.
        var movesPrivately: Bool { RoundUps.movesPrivately(self, pools: RoundUps.privatePools) }
    }

    // MARK: - Swaps and Buy round up too (prd §1561)

    /// What rounds up, and whether its own transaction can carry the buy.
    enum Act: Equatable, Sendable {
        /// Dollars sent: the transaction carries the buy (§1452).
        case send
        /// A swap: the dollar value of what is sold rounds up. Its Face ID
        /// transaction carries the buy only when what it sells is the
        /// network's dollar — the buy spends the dollar, which a swap of ETH
        /// may leave the account without; otherwise the change counts and is
        /// bought by the next send or dollar swap.
        case swap(sellsDollar: Bool)
        /// A Bitrefill purchase: paid by a signed authorisation Bitrefill
        /// submits (§1473), so no call of ours rides it; it only counts.
        case buy
    }

    static func carriesBuy(_ act: Act) -> Bool {
        switch act {
        case .send: true
        case .swap(let sellsDollar): sellsDollar
        case .buy: false
        }
    }

    /// The dollar value of what a swap sells (or a Buy pays), in the
    /// dollar's units, so it rounds up as dollars sent do. nil — no round-up
    /// — for a token with no price and for WETH⇄ETH (one for one, no trade).
    static func soldUnits(usd: Double?, wrap: Bool) -> String? {
        guard !wrap, let usd, usd.isFinite, usd > 0 else { return nil }
        let micro = (usd * 1_000_000).rounded(.down)
        guard micro >= 1, micro < 1e15 else { return nil }
        return String(Int64(micro))
    }

    // MARK: - Into your private balance (prd §1561)

    /// **WHERE THE CHANGE MAY MOVE INTO YOUR PRIVATE BALANCE:** the network
    /// this build keeps private money on (prd §1565): Ethereum in every
    /// build (0xBow's pool 1, ppUSDC), or in a DEBUG build Sepolia unless
    /// launched with `-privateNetwork ethereum` — the same choice
    /// `PrivacyNetwork.current` makes. On Base and Robinhood the choice is
    /// never offered (no dead control, prd §83); the kill switch
    /// (`PrivateMainnet.on`) takes Ethereum away where it is offered
    /// (`MoveSecurity`, `MoveSentence`).
    static var privatePools: Set<Int> {
        #if DEBUG
        UserDefaults.standard.string(forKey: "privateNetwork") == "ethereum" ? [ethereumPool] : [11_155_111]
        #else
        [ethereumPool]
        #endif
    }

    /// Ethereum's chain id: the one network with value where round-ups move
    /// into your private balance, as USDC into ppUSDC (prd §1565).
    static let ethereumPool = 1

    /// When the change moves on Ethereum, in the dollar's units: everything
    /// counted once it reaches $5 AND the pool's smallest deposit in USDC
    /// (`poolMinimum`, read live: about $10.05 on 2026-10-26), never per
    /// send. Nil before the minimum is read: the change keeps counting.
    /// A test network's threshold is its coin's (`privateMoveAt`).
    static func privateMoveAt(on chainId: Int, poolMinimum: String?) -> String? {
        guard chainId == ethereumPool else { return privateMoveAt }
        guard let floor = poolMinimum.flatMap({ Decimal(string: $0) }), floor > 0, let five = Decimal(string: buyAt) else { return nil }
        return NSDecimalNumber(decimal: max(floor, five)).stringValue
    }

    /// One send's round-up moving privately on Ethereum: the change, and —
    /// once the count reaches `threshold` with it — everything counted, to
    /// move into your private balance now (the plan's `buy`).
    static func privatePlan(dollarSent units: String, saved: String, step: Int, threshold: String?) -> Plan {
        let change = change(units, step: step)
        let total = YourAccountOp.sum(saved, change)
        if let threshold, YourAccountOp.atMost(threshold, total) {
            return Plan(change: change, buy: total, savedAfter: "0")
        }
        return Plan(change: change, buy: nil, savedAfter: total)
    }

    /// Whether a send on `chainId` rounds up at all: on, and when the change
    /// moves privately, only where there is a pool to move it into — a send
    /// elsewhere sets nothing aside for a balance it cannot reach.
    static func applies(_ setting: Setting, on chainId: Int, pools: Set<Int> = privatePools) -> Bool {
        setting.on && (!movesPrivately(setting, pools: pools) || pools.contains(chainId))
    }

    static func movesPrivately(_ setting: Setting, pools: Set<Int>) -> Bool {
        setting.toPrivate == true && !pools.isEmpty
    }

    /// How a send carries the change into the pool once it is due.
    enum PrivateRoute: Equatable, Sendable {
        /// The send carries the deposit.
        case deposit
        /// Not this send: the change keeps counting and moves with the next
        /// send you approve with Face ID.
        case waits
        /// No pool on this network.
        case notHere
    }

    /// **A DEPOSIT IS A CONTRACT CALL**, so the spend limit's session key,
    /// which may only `transfer` the dollar and send ETH through Multicall3
    /// (§1545 item 2), never carries one: a send it signs alone leaves the
    /// change counting, and the deposit rides the next send you approve with
    /// Face ID — §1545's pattern for a buy on the exchanges.
    static func privateRoute(on chainId: Int, bySession: Bool, pools: Set<Int> = privatePools) -> PrivateRoute {
        guard pools.contains(chainId) else { return .notHere }
        return bySession ? .waits : .deposit
    }

    /// When the change moves, in the network's coin: everything counted,
    /// together, once it reaches `privateMoveAt` — never per send (0xBow
    /// labels each deposit, so one per send would tie every send to its
    /// change). nil before.
    static func privateMove(saved: String, at threshold: String) -> String? {
        guard let have = Decimal(string: saved), have > 0, let need = Decimal(string: threshold), have >= need else { return nil }
        return saved
    }

    /// The threshold on a test network, in its coin's base units: test ETH
    /// has no price (§949), so 0.0001 test ETH stands where $5 stands.
    /// DEBUG's `-roundUpsPrivateAt <wei>` lowers it.
    static var privateMoveAt: String {
        #if DEBUG
        if let wei = UserDefaults.standard.string(forKey: "roundUpsPrivateAt"), Decimal(string: wei) != nil { return wei }
        #endif
        return "100000000000000"
    }

    private static func privateSavedKey(_ chainId: Int) -> String { "yourAccount.roundUps.private.\(chainId)" }

    /// The change counted toward your private balance on a network, in its
    /// coin's base units.
    static func privateSaved(on chainId: Int) -> String {
        UserDefaults.standard.string(forKey: privateSavedKey(chainId)) ?? "0"
    }

    static func setPrivateSaved(_ units: String, on chainId: Int) {
        guard !YourAccountDemo.isOn else { return }
        UserDefaults.standard.set(units, forKey: privateSavedKey(chainId))
    }

    /// The change is bought once it reaches this, in the dollar's units ($5).
    /// DEBUG's `-roundUpsBuyAt <units>` lowers it for a test account.
    static var buyAt: String {
        #if DEBUG
        if let units = UserDefaults.standard.string(forKey: "roundUpsBuyAt"), Decimal(string: units) != nil { return units }
        #endif
        return "5000000"
    }
    static let dollarDecimals = 6

    private static let settingKey = "yourAccount.roundUps"
    private static func savedKey(_ chainId: Int) -> String { "yourAccount.roundUps.saved.\(chainId)" }

    static var setting: Setting {
        get {
            if YourAccountDemo.isOn { return YourAccountDemo.roundUps }
            return UserDefaults.standard.data(forKey: settingKey).flatMap { try? JSONDecoder().decode(Setting.self, from: $0) } ?? Setting()
        }
        set {
            // The demo's round-ups are its own (prd §1475): a change there
            // draws, and this phone's setting is never touched.
            guard !YourAccountDemo.isOn else { return }
            if let data = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(data, forKey: settingKey) }
        }
    }

    /// The change counted so far on a network, in its dollar's units.
    static func saved(on chainId: Int) -> String {
        // The demo's change so far: $2.60 of the $5 (§1475).
        if YourAccountDemo.isOn { return chainId == YourAccountOp.base.chainId ? "2600000" : "0" }
        return UserDefaults.standard.string(forKey: savedKey(chainId)) ?? "0"
    }

    static func setSaved(_ units: String, on chainId: Int) {
        guard !YourAccountDemo.isOn else { return }
        UserDefaults.standard.set(units, forKey: savedKey(chainId))
    }

    /// The change waiting on every network, in dollars: what Spending's
    /// Round-ups row says is not bought yet (prd §1523).
    static var waitingUSD: Double {
        YourAccountOp.networks.reduce(0) { sum, net in
            sum + ((Decimal(string: saved(on: net.chainId)).map { NSDecimalNumber(decimal: $0 / pow(10, dollarDecimals)).doubleValue }) ?? 0)
        }
    }

    // MARK: - The buys (prd §1523)

    /// **RELAY'S DEPOSIT ADDRESSES (a buy on another network) THIS PHONE PAID A ROUND-UP TO.** Relay
    /// hands out a new address per quote, so nothing on chain says a transfer
    /// to one was a round-up's buy: this list does. The landed send to one is
    /// stamped `.roundUp` (`SpendingSource.stampRoundUp`), and the stamp
    /// rides the row through iCloud; the list itself stays on this phone.
    /// Kept when the address is asked for, before the send lands: an address
    /// a send never reached marks nothing. The newest `depositCap` are kept.
    struct Deposit: Codable, Equatable, Sendable {
        var address: String
        var target: Target
        var at: Date
    }

    static let depositCap = 200
    private static let depositsKey = "yourAccount.roundUps.deposits"

    static var deposits: [Deposit] {
        UserDefaults.standard.data(forKey: depositsKey).flatMap { try? JSONDecoder().decode([Deposit].self, from: $0) } ?? []
    }

    static func noteDeposit(_ address: String, target: Target, at: Date = .now) {
        guard !YourAccountDemo.isOn, !address.isEmpty else { return }
        var list = deposits.filter { $0.address.caseInsensitiveCompare(address) != .orderedSame }
        list.append(Deposit(address: address.lowercased(), target: target, at: at))
        if list.count > depositCap { list.removeFirst(list.count - depositCap) }
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: depositsKey) }
    }

    /// What a round-up paid to each deposit address buys, by lowercased
    /// address: read once for a pass over many rows.
    static func depositTargets() -> [String: Target] {
        Dictionary(deposits.map { ($0.address.lowercased(), $0.target) }, uniquingKeysWith: { _, newer in newer })
    }

    /// What `units` of the dollar rounds up by, to the next `step` dollars;
    /// nothing when it is already whole.
    static func change(_ units: String, step: Int) -> String {
        guard step > 0, let n = Decimal(string: units) else { return "0" }
        let stepUnits = Decimal(step) * pow(10, dollarDecimals)
        var quotient = n / stepUnits
        var floored = Decimal()
        NSDecimalRound(&floored, &quotient, 0, .down)
        let rest = n - floored * stepUnits
        return rest == 0 ? "0" : NSDecimalNumber(decimal: stepUnits - rest).stringValue
    }

    /// One send's round-up: the change it adds, and — when the count reaches
    /// $5 with it — everything counted, to buy now.
    struct Plan: Equatable, Sendable {
        let change: String
        let buy: String?
        let savedAfter: String
    }

    static func plan(dollarSent units: String, saved: String, step: Int) -> Plan {
        let change = change(units, step: step)
        let total = YourAccountOp.sum(saved, change)
        if YourAccountOp.atMost(buyAt, total) {
            return Plan(change: change, buy: total, savedAfter: "0")
        }
        return Plan(change: change, buy: nil, savedAfter: total)
    }

    /// What is counted once a send lands: the plan's own when it bought,
    /// else everything it reached — the session key's send never buys on the
    /// exchanges, so its change keeps counting toward the next Face ID send.
    static func savedAfter(_ plan: Plan, bought: Bool) -> String {
        bought ? plan.savedAfter : (plan.buy ?? plan.savedAfter)
    }

    /// Whether a send signed by the spend limit's session key may carry the
    /// buy: only Relay's `transfer`, to a token on another network. A buy on
    /// the send's own network is a router call the session may not make.
    static func sessionCarries(_ target: Target, from chainId: Int) -> Bool {
        !target.onExchanges(from: chainId)
    }

    // MARK: - An exchange buy, known by its transaction (prd §1545)

    /// **A BUY SIGNED ON THE EXCHANGES.** Kept when Face ID is asked for it,
    /// before it lands: the account, the network, the dollar and the exact
    /// amount. The landed transaction whose dollar leg leaves this account in
    /// exactly that amount, from a few minutes before to a day after, is the
    /// buy (`swapBuy`), and its leg and the token it bought are stamped
    /// `.roundUp`; the note is then spent, so it marks one transaction only.
    /// Device-only, the newest `depositCap`, as the deposit addresses are.
    struct SwapBuy: Codable, Equatable, Sendable {
        var account: String
        /// The network as the Wallet spells it ("base-mainnet").
        var network: String
        /// The dollar's contract, lowercased.
        var dollar: String
        var units: String
        var target: Target
        var at: Date
    }

    private static let swapBuysKey = "yourAccount.roundUps.swapBuys"
    /// How far before the note a leg's block time may fall (a clock off),
    /// and how long after it the buy may land.
    static let swapBuyEarly: TimeInterval = 10 * 60
    static let swapBuyLate: TimeInterval = 24 * 60 * 60

    static var swapBuys: [SwapBuy] {
        UserDefaults.standard.data(forKey: swapBuysKey).flatMap { try? JSONDecoder().decode([SwapBuy].self, from: $0) } ?? []
    }

    private static func saveSwapBuys(_ list: [SwapBuy]) {
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: swapBuysKey) }
    }

    static func noteSwapBuy(account: String, network: String, dollar: String, units: String, target: Target, at: Date = .now) {
        guard !YourAccountDemo.isOn, !account.isEmpty, !dollar.isEmpty else { return }
        let buy = SwapBuy(account: account.lowercased(), network: network, dollar: dollar.lowercased(),
                          units: units, target: target, at: at)
        // A second Face ID for the same buy (the first cancelled) is one note.
        var list = swapBuys.filter { !($0.account == buy.account && $0.network == buy.network && $0.units == buy.units) }
        list.append(buy)
        if list.count > depositCap { list.removeFirst(list.count - depositCap) }
        saveSwapBuys(list)
    }

    /// The note is spent: it has marked its transaction.
    static func spendSwapBuy(_ buy: SwapBuy) {
        saveSwapBuys(swapBuys.filter { $0 != buy })
    }

    /// One leg of a landed transaction, as the match reads it.
    struct Leg: Equatable, Sendable {
        let id: String
        let received: Bool
        /// The token's contract, lowercased; nil for the network's own coin.
        let contract: String?
        /// In whole tokens, as the read reports it.
        let value: Double
        let at: Date?
    }

    /// **WHICH LEGS OF ONE TRANSACTION ARE AN EXCHANGE BUY.** Among `buys`,
    /// the first noted for this wallet on this network whose dollar left in
    /// exactly its amount, inside its window: that sent leg, and the leg of
    /// the token it bought if the transaction carries one (the largest, if a
    /// swap of the page bought the same token beside it). nil when none is.
    static func swapBuy(_ legs: [Leg], wallet: String, network: String, buys: [SwapBuy])
        -> (buy: SwapBuy, sent: String, filled: String?)? {
        let w = wallet.lowercased()
        for buy in buys where buy.account == w && buy.network == network {
            guard let want = Decimal(string: buy.units).map({ NSDecimalNumber(decimal: $0 / pow(10, dollarDecimals)).doubleValue })
            else { continue }
            let sent = legs.first { leg in
                guard !leg.received, leg.contract == buy.dollar, abs(leg.value - want) < 0.000_000_5 else { return false }
                guard let at = leg.at else { return true }
                return at >= buy.at.addingTimeInterval(-swapBuyEarly) && at <= buy.at.addingTimeInterval(swapBuyLate)
            }
            guard let sent else { continue }
            let filled = legs.filter { $0.received && $0.contract == buy.target.contract }
                .max { $0.value < $1.value }
            return (buy, sent.id, filled?.id)
        }
        return nil
    }
}
