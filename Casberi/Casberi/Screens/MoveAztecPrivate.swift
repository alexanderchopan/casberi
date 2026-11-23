import SwiftUI
import Observation

/// **YOUR PRIVATE BALANCE ON AZTEC, IN SEND (prd §1700f items 11–14).** The
/// same sentence 0xBow's private balance has (`MovePrivateSentence`), for
/// your Aztec account:
///
/// - **In** (`.deposit`): picked as "Your private account · Aztec" among
///   Send's recipients. "Send 2 USDC to your private account on Aztec." Your
///   Safe deposits through Shield (USDC or WETH), gas riding along in the
///   same operation when the account needs it; the claim on Aztec follows.
///   Or it says what stands in the way: "Fund …ca8d on Ethereum first.", or
///   "Shield needs a Human Passport score of 20 first." with Human Passport in
///   the foot (the only door a Casberi Safe has to a score).
/// - **From** (`.send`): picked as "Aztec · Private" in Send's networks.
///   "Send 2 USDC from your private account on Aztec to …4f38." An Aztec
///   address is a private send inside Aztec; an Ethereum address, anyone's,
///   is out through Shield, finished from Needs you. Either asks the
///   co-signer first (`AztecCoSign`).
///
/// No chips, no direction to choose: the place you send to or from says it.
@MainActor
@Observable
final class AztecMove {
    enum Mode: Equatable { case deposit, send }

    enum Stage: Equatable {
        case reading
        /// Your Safe holds too little to move in (or gas is short and it
        /// holds no AZTEC for it).
        case needsFunds(address: String)
        /// Shield will not take it: below the Passport score, or sanctioned.
        case shieldNo(score: Int, threshold: Int, sanctioned: Bool)
        /// Nothing private on Aztec to send from yet.
        case nothingPrivate
        /// Your Aztec account has no gas for a send of its own.
        case needsGas
        case ready
        case working(String)
        case done(String)
        case failed(String)
    }

    /// A token you can move, and how much of it, base units.
    struct Holding: Equatable, Identifiable {
        let symbol: String
        let units: String
        var id: String { symbol }
    }

    var mode: Mode = .deposit
    var stage: Stage = .reading
    var symbol = "USDC"
    var amount = ""
    var recipient: String?
    /// **PAY MANY ON AZTEC (prd §1952, user: "lets do the pay to multiple
    /// addresses on aztec").** The payments Add another kept, in the order
    /// kept; the line being written is `recipient` and `amount`. One token
    /// for all; each its own amount, typed as typed, read in the token's
    /// places when sent.
    struct Pay: Identifiable, Equatable {
        let id = UUID()
        let recipient: String
        let amount: String
    }
    private(set) var pays: [Pay] = []
    /// One Aztec transaction carries five calls at most (Aztec's
    /// `APP_MAX_CALLS`, 5 in v6.0.0): five payments, the line included.
    static let maxPays = 5
    private(set) var holdings: [Holding] = []
    /// What the Safe holds on Ethereum, base units, by symbol.
    private(set) var safeHeld: [String: String] = [:]
    /// What your account alone holds, before a co-signer's is counted in
    /// `safeHeld` (prd §1720): a gas sale is your account's own.
    private var ownHeld: [String: String] = [:]
    /// Whether a deposit brings gas along (the account is short of it).
    private(set) var bringsGas = false
    /// The last private send was paid from the account's own Fee Juice, in
    /// the open (prd §1700aa): the done line says so, never a quiet downgrade.
    private(set) var paidInTheOpen = false

    /// **THE SEND BEHIND ITS SHEET (prd §1777).** A send within Aztec asks
    /// for Face ID and the co-signer, then needs nobody while it is checked,
    /// proved and sent (34 s and 75 s on the user's phone). So the sheet
    /// closes at that point and the move is kept here: the shell's capsule
    /// draws its steps, and Move opened on Aztec again shows this same
    /// sentence, running or failed, never a second one beside it.
    static var kept: AztecMove?
    /// Closes the sheet; nil where the sentence is a page, which stays.
    var onAway: (() -> Void)?
    /// Another send is still going behind its sheet.
    private var anotherIsGoing: Bool {
        guard let other = Self.kept, other !== self, case .working = other.stage else { return false }
        return true
    }
    /// **GAS BOUGHT WITH WHAT YOU MOVE (prd §1700aa).** Gas rides along and
    /// your account holds too little AZTEC for it: a little of the token
    /// being moved is sold for it in the same operation.
    var buysGas: Bool {
        bringsGas && (Decimal(string: safeHeld["AZTEC"] ?? "0") ?? 0) < (Decimal(string: AztecGas.rideAlong) ?? 0)
    }
    /// What that sale takes of the picked token, base units; nil when gas is
    /// not bought, or while a price is still being read.
    var gasSale: String? {
        guard mode == .deposit, buysGas else { return nil }
        return AztecGas.saleUnits(sellPrice: prices[symbol], aztecPrice: prices["AZTEC"], decimals: decimals)
    }
    private(set) var maxUSD: Double?
    /// Your co-signer, when Shield scores it and not your account: the
    /// deposit is then the co-signer's own (prd §1720).
    private(set) var viaCoSigner: String?
    /// Your co-signer, eligible or not, and Shield's score for it: the way
    /// in names them as steps when Shield says no (prd §1820).
    private(set) var coSigner: String?
    private(set) var coSignerScore: Int?
    /// What the co-signer already lets Shield's portal take, by symbol, and
    /// whether your account sends with both keys: the asks it will make,
    /// counted before the hold (prd §1918).
    private(set) var coSignerAllowance: [String: Decimal] = [:]
    private(set) var bothKeys = false
    /// Your Shield key and what it may still move today, in dollars (prd
    /// §1920, §1922): the way in for everyone.
    private(set) var keyOption: String?
    private(set) var keyLeft: Double?
    /// The co-signer's own limit, when it carries a score: the fallback past
    /// the key's day (prd §1922).
    private(set) var coSignerMax: Double?

    /// **THIS IPHONE FIRST (prd §1922, user: "why should you need a cosigner
    /// to put money INTO aztec").** The move-in goes through your Shield key
    /// whenever what it moves fits what the key has left today; past that,
    /// through your co-signer when Shield scores it.
    var viaKey: String? {
        guard mode == .deposit, let key = keyOption, let left = keyLeft else { return nil }
        guard viaCoSigner != nil else { return key }
        return (amountUSD ?? 0) <= left ? key : nil
    }

    /// A send out fits this iPhone's day out (prd §1950): Shield's $100 less
    /// what this phone counted going out today. The co-signer past it.
    var outFitsKey: Bool {
        guard mode == .send, ShieldKey.address != nil, let usd = amountUSD else { return false }
        return usd <= max(0, 100 - ShieldKey.movedOutToday())
    }

    /// What the sentence moves, in dollars; nil while unpriced.
    var amountUSD: Double? {
        guard let units, let n = Decimal(string: units) else { return nil }
        let whole = NSDecimalNumber(decimal: n / pow(10, decimals)).doubleValue
        if symbol == "USDC" { return whole }
        return prices[symbol].map { whole * $0 }
    }

    /// **THE STEPS, SAID BEFORE THE HOLD (prd §1918, user: "i always feel
    /// confused how i put money into it").** How many times your co-signer's
    /// wallet will ask: Shield's sign-in (unless one stands), the portal's
    /// approval (unless it already may take this much), the deposit, and the
    /// hand-over when your account sends with both keys. Nil until read.
    var coSignerAsks: Int? {
        guard mode == .deposit, viaKey == nil, let via = viaCoSigner, let units, let wanted = Decimal(string: units) else { return nil }
        var asks = 1
        if !ShieldBridge.signedIn(via) { asks += 1 }
        if (coSignerAllowance[symbol] ?? 0) < wanted { asks += 1 }
        if bothKeys { asks += 1 }
        return asks
    }

    // MARK: - In dollars (prd §1700y, as Railgun's §1728)

    /// USD per coin, by symbol: USDC, WETH (at ETH's price), AZTEC.
    private(set) var prices: [String: Double] = [:]
    /// Aztec's minimum fee per unit of L2 gas, in Fee Juice's smallest unit.
    private(set) var feePerL2Gas: Decimal?
    /// Ethereum's gas price, wei, for a move-in signed by Your account.
    private(set) var gasPriceWei: Decimal?
    /// When this sentence began reading, for "Getting your private balance
    /// ready · 12 s" in the foot (real seconds, as Railgun's).
    private(set) var readingSince: Date?

    /// Shield's cut, both ways: 0.5% (its own page, prd §1700d).
    static let shieldBps = 50
    /// A private send's gas on Aztec: one transfer used 644K to 742K
    /// (twelve fee-bearing mainnet blocks read 2026-11-08); the higher, rounded.
    static let sendMana = 750_000
    /// An exit through Shield burns and messages Ethereum: more than a send.
    static let exitMana = 1_400_000
    /// A move-in on Ethereum: Shield's deposit used 170K to 175K (its portal's
    /// own deposits, read 2026-11-09), plus Your account's approve and its own
    /// overhead (~120K, measured 2026-11-03); gas riding along adds its
    /// portal's deposit and approve.
    static let depositGas = 350_000
    static let gasAlongGas = 150_000
    /// Buying that gas first (prd §1700aa): a hand-over and one swap through
    /// two Uniswap v4 pools. An estimate, not measured from a move of ours.
    static let gasBuyGas = 250_000

    static func usd(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    /// Base units of a token in dollars.
    func dollars(_ units: String, symbol: String) -> Double? {
        guard let price = prices[symbol], let u = Decimal(string: units) else { return nil }
        let places = symbol == "USDC" ? 6 : 18
        return NSDecimalNumber(decimal: u / pow(10, places)).doubleValue * price
    }

    /// "You have $120.00": the head of the amount's menu (prd §1802).
    var haveLine: String? {
        guard let available else { return nil }
        return dollars(available, symbol: symbol).map { String(localized: "You have \(Self.usd($0))") }
            ?? String(localized: "You have \(PrivateMoney.figure(available, decimals: decimals, symbol: symbol))")
    }

    /// The line under the sentence: "$25.00 · you have $120.00" (prd §1700y).
    /// No price: what you have, in the token.
    var amountLine: String? {
        guard let available else { return nil }
        var parts: [String] = []
        if let units, (Decimal(string: units) ?? 0) > 0, let usd = dollars(units, symbol: symbol) { parts.append(Self.usd(usd)) }
        parts.append(dollars(available, symbol: symbol).map { String(localized: "you have \(Self.usd($0))") }
                     ?? String(localized: "you have \(PrivateMoney.figure(available, decimals: decimals, symbol: symbol))"))
        return parts.joined(separator: " · ")
    }

    /// Half · All (prd §1700y, Railgun's §1728 item 1 without its floor):
    /// each types its amount, exact; one Shield would refuse is not drawn.
    enum Pick: CaseIterable { case half, all }

    func amount(for pick: Pick) -> String? {
        guard let available, let held = Decimal(string: available), held > 0 else { return nil }
        var value: Decimal
        switch pick {
        case .half:
            var half = held / 2, down = Decimal()
            NSDecimalRound(&down, &half, 0, .down)
            value = down
        // All leaves what gas is bought with (prd §1700aa), and is not
        // offered until that is priced: it would be a figure that fails.
        case .all:
            if mode == .deposit, buysGas, gasSale == nil { return nil }
            value = held - (gasSale.flatMap { Decimal(string: $0) } ?? 0)
        }
        guard value > 0 else { return nil }
        if mode == .deposit, symbol == "USDC", let maxUSD, value > Decimal(maxUSD) * 1_000_000 { return nil }
        var whole = value / pow(10, decimals), cut = Decimal()
        NSDecimalRound(&cut, &whole, decimals, .down)
        return NSDecimalNumber(decimal: cut).stringValue
    }

    /// What this move costs, in dollars and its parts (prd §1700y, the shape
    /// of Railgun's `Cost`): Shield's cut where Shield carries it, then the
    /// gas: Aztec's from your Fee Juice, Ethereum's from your account, and
    /// 30 AZTEC when gas rides along. nil where a price is missing: the foot
    /// then says Shield's percentage, as before.
    var cost: PrivateCost? {
        guard amountOK, let units else { return nil }
        var usd = 0.0
        var parts: [PrivateCost.Part] = []
        func aztecGas(_ mana: Int) -> Double? {
            guard let feePerL2Gas, let aztec = prices["AZTEC"] else { return nil }
            let fj = Decimal(mana) * feePerL2Gas / pow(10, 18)
            return NSDecimalNumber(decimal: fj).doubleValue * aztec
        }
        func shieldCut() -> Bool {
            var raw = (Decimal(string: units) ?? 0) * Decimal(Self.shieldBps) / 10_000, cut = Decimal()
            NSDecimalRound(&cut, &raw, 0, .down)
            let text = NSDecimalNumber(decimal: cut).stringValue
            guard let cutUSD = dollars(text, symbol: symbol) else { return false }
            usd += cutUSD
            parts.append(.init(words: String(localized: "Shield"), figure: PrivateMoney.figure(text, decimals: decimals, symbol: symbol)))
            return true
        }
        switch mode {
        case .deposit:
            guard shieldCut(), let gasPriceWei, let eth = prices["WETH"] else { return nil }
            let gas = Decimal(Self.depositGas + (bringsGas ? Self.gasAlongGas : 0) + (buysGas ? Self.gasBuyGas : 0)) * gasPriceWei / pow(10, 18)
            let gasUSD = NSDecimalNumber(decimal: gas).doubleValue * eth
            usd += gasUSD
            parts.append(.init(words: String(localized: "Gas, from your account"), figure: String(localized: "about \(Self.usd(gasUSD))")))
            if buysGas {
                // Bought with a little of what you move (prd §1700aa).
                guard let sale = gasSale, let along = dollars(sale, symbol: symbol) else { return nil }
                usd += along
                parts.append(.init(words: String(localized: "Private gas, bought with your \(symbol)"),
                                   figure: PrivateMoney.figure(sale, decimals: decimals, symbol: symbol)))
            } else if bringsGas {
                guard let along = dollars(AztecGas.rideAlong, symbol: "AZTEC") else { return nil }
                usd += along
                parts.append(.init(words: String(localized: "Private gas, for your account there"), figure: "30 AZTEC"))
            }
        case .send where toEthereum:
            guard shieldCut(), let gas = aztecGas(Self.exitMana) else { return nil }
            usd += gas
            parts.append(.init(words: Self.gasWords, figure: String(localized: "about \(Self.usd(gas))")))
        case .send:
            guard let gas = aztecGas(Self.sendMana) else { return nil }
            usd += gas
            parts.append(.init(words: Self.gasWords, figure: String(localized: "about \(Self.usd(gas))")))
        }
        return PrivateCost(usd: usd, parts: parts)
    }

    /// A send's gas on Aztec: "Private gas" when the private fee contract
    /// pays it, else the account's own Fee Juice, which names it.
    @MainActor static var gasWords: String {
        AztecGas.paysPrivately ? String(localized: "Private gas") : String(localized: "Gas, from your Fee Juice")
    }

    /// What the cost line says after the dollars: what the move buys you.
    var costTail: String {
        switch mode {
        case .deposit: String(localized: "private in 5 to 15 minutes")
        case .send where toEthereum: String(localized: "on Ethereum in about an hour")
        case .send: String(localized: "who, what and how much stay private")
        }
    }

    #if DEBUG
    /// For `CasberiTests`: a sentence's inputs, no network (prd §1700y).
    func seedForTests(mode: Mode, symbol: String, held: String, amount: String, recipient: String? = nil,
                      prices: [String: Double], feePerL2Gas: Decimal?, gasPriceWei: Decimal?,
                      maxUSD: Double? = nil, bringsGas: Bool = false, safeAZTEC: String = AztecGas.rideAlong) {
        self.mode = mode
        self.symbol = symbol
        self.safeHeld = ["AZTEC": safeAZTEC]
        self.holdings = [Holding(symbol: symbol, units: held)]
        self.amount = amount
        self.recipient = recipient
        self.prices = prices
        self.feePerL2Gas = feePerL2Gas
        self.gasPriceWei = gasPriceWei
        self.maxUSD = maxUSD
        self.bringsGas = bringsGas
    }
    #endif

    /// Prices, and the fees a cost is made of; read with the balances, never
    /// holding up the sentence.
    private func readCosts() async {
        var found: [String: Double] = [:]
        let mainnet = await MainnetPrices.prices(for: ["usdc", "eth"])
        if let usdc = mainnet["usdc"] { found["USDC"] = usdc }
        if let eth = mainnet["eth"] { found["WETH"] = eth; found["ETH"] = eth }
        let aztec = await DefiLlamaPrices.prices(for: [("eth-mainnet", AztecGas.token)])
        if let p = aztec.values.first?.price { found["AZTEC"] = p }
        prices = found
        switch mode {
        case .deposit:
            if let hex = try? await YourAccountChain.rpc(YourAccountOp.ethereum, "eth_gasPrice", []) as? String {
                gasPriceWei = ShieldBridge.decimal(hex: String(hex.dropFirst(2))).flatMap { Decimal(string: $0) }
            }
        case .send:
            guard AztecProver.isAvailable,
                  let fees = try? await AztecEngine.shared.call("minFees") as? [String: Any],
                  let l2 = fees["l2"] as? String else { return }
            feePerL2Gas = Decimal(string: l2)
        }
    }

    var decimals: Int { symbol == "USDC" ? 6 : 18 }
    /// Shield's asset for the picked token: ETH goes in as WETH, wrapped
    /// first (prd §1943).
    var asset: ShieldBridge.Asset? { ShieldBridge.assets.first { $0.symbol == (wraps ? "WETH" : symbol) } }
    /// Plain ETH picked: the move wraps it into WETH first (prd §1943).
    var wraps: Bool { mode == .deposit && symbol == "ETH" }
    /// What was typed, in base units: a comma is a decimal point, a leading
    /// point reads as "0.", and a trailing point (mid-typing) is ignored.
    var units: String? { units(of: amount) }
    /// `typed` in base units, as `units` reads the line's amount.
    func units(of typed: String) -> String? {
        var typed = typed.replacingOccurrences(of: ",", with: ".")
        if typed.hasSuffix(".") { typed.removeLast() }
        // ".5" is half (prd §1700r, user: "the send button stays inactive").
        if typed.hasPrefix(".") { typed = "0" + typed }
        return PrivateMoney.baseUnits(typed, decimals: decimals)
    }
    /// How much of the picked token there is to move, base units.
    var available: String? { holdings.first { $0.symbol == symbol }?.units }

    /// **ANY AMOUNT (prd §1700q, user: "we don't want a fixed list we want be
    /// able to add whatever user wants").** The amount is typed; what stands
    /// in its way is said, never a list of allowed amounts: more than you
    /// hold, or more than Shield moves for your score.
    enum AmountProblem: Equatable {
        case moreThanHeld(String)
        /// You hold it, but not with what buys gas beside it (prd §1700aa):
        /// the most that leaves room.
        case leavesNoGas(String)
        case overShieldCap(Int)
        /// Over Shield's screening tier, through your Shield key (prd §1920).
        case overDailyCap(Int)
    }
    /// What the kept payments take, base units (prd §1952).
    var paysUnits: Decimal {
        pays.reduce(Decimal(0)) { $0 + (units(of: $1.amount).flatMap { Decimal(string: $0) } ?? 0) }
    }
    /// Every payment of the transaction, the line last: (to, base units).
    var allPays: [(to: String, units: String)]? {
        guard let recipient, let units else { return nil }
        var out: [(to: String, units: String)] = []
        for p in pays {
            guard let u = self.units(of: p.amount) else { return nil }
            out.append((p.recipient, u))
        }
        return out + [(recipient, units)]
    }
    /// Add another keeps the line and starts the next (prd §1952): an Aztec
    /// account on the line, an amount that fits, room for one more.
    var canAddAnother: Bool {
        mode == .send && stage == .ready && toAztec && amountOK && pays.count < Self.maxPays - 1
    }
    func addAnother() {
        guard canAddAnother, let recipient else { return }
        pays.append(Pay(recipient: recipient, amount: amount))
        self.recipient = nil
        amount = ""
    }
    func removePay(_ id: UUID) { pays.removeAll { $0.id == id } }

    var amountProblem: AmountProblem? {
        guard let units, var want = Decimal(string: units), want > 0 else { return nil }
        // What the kept payments take comes first (prd §1952).
        want += paysUnits
        if let available, let have = Decimal(string: available), want > have {
            return .moreThanHeld(PrivateMoney.figure(available, decimals: decimals, symbol: symbol))
        }
        if let available, let have = Decimal(string: available), let sale = gasSale.flatMap({ Decimal(string: $0) }), want + sale > have {
            let most = max(have - sale, 0)
            return .leavesNoGas(PrivateMoney.figure(NSDecimalNumber(decimal: most).stringValue, decimals: decimals, symbol: symbol))
        }
        // Shield's cap is in dollars: USDC is read as dollars; WETH's is
        // Shield's to refuse, as there is no price here to read it by.
        if mode == .deposit, symbol == "USDC", let maxUSD, want > Decimal(maxUSD) * 1_000_000 {
            return viaCoSigner == nil ? .overDailyCap(Int(maxUSD)) : .overShieldCap(Int(maxUSD))
        }
        return nil
    }
    var amountOK: Bool { units != nil && amountProblem == nil }
    var acting: Bool { if case .working = stage { true } else { false } }

    /// Whether `recipient` is an Aztec account (a private send) or an
    /// Ethereum address (out through Shield).
    var toAztec: Bool { recipient.map(AztecAddressText.isAztec) ?? false }
    var toEthereum: Bool { recipient.map(PrivateMoney.isAddress) ?? false }

    /// Picks the token; the typed amount stays.
    func pick(_ symbol: String) {
        self.symbol = symbol
    }

    /// The picked token stays if it is still held; else the first held.
    private func keepPick() {
        if !holdings.contains(where: { $0.symbol == symbol }), let first = holdings.first { symbol = first.symbol }
    }

    /// Where the move stands: balances, Shield's word, the account's gas.
    func read() async {
        // Read afresh, it is a sentence like any other again (prd §1777).
        if Self.kept === self { Self.kept = nil }
        stage = .reading
        readingSince = .now
        defer { readingSince = nil }
        #if DEBUG
        // `-aztecWayInSample none|<score>`: Shield says no, with no co-signer
        // or one short of the score, so the steps are seen with nothing
        // asked of Shield (prd §1820). The address is made up.
        if mode == .deposit, let sample = UserDefaults.standard.string(forKey: "aztecWayInSample") {
            holdings = [Holding(symbol: "USDC", units: "25000000")]
            symbol = "USDC"
            if amount.isEmpty { amount = "20" }
            // `key`: no co-signer, the move-in goes through your Shield key (prd §1920).
            if sample == "key" {
                // ETH and WETH as their own choices (prd §1943).
                holdings = [Holding(symbol: "USDC", units: "25000000"), Holding(symbol: "ETH", units: "40000000000000000"),
                            Holding(symbol: "WETH", units: "10000000000000000")]
                keyOption = "0x0000000000000000000000000000000000005e1d"
                keyLeft = 100
                maxUSD = 100
                prices = ["USDC": 1, "ETH": 3000, "WETH": 3000, "AZTEC": 0.0124]
                stage = .ready
                NSLog("[Casberi] aztecWayIn| sample | key")
                return
            }
            coSigner = sample == "none" ? nil : "0x0000000000000000000000000000000000002725"
            coSignerScore = Int(sample)
            stage = .shieldNo(score: coSignerScore ?? 0, threshold: 20, sanctioned: false)
            NSLog("[Casberi] aztecWayIn| sample | %@", sample)
            return
        }
        #endif
        if DemoMode.isActive {
            holdings = [Holding(symbol: "USDC", units: "25000000")]
            symbol = "USDC"
            if amount.isEmpty { amount = "2" }
            // The demo's cost is a sample, as Railgun's demo fee is (prd §1700y).
            prices = ["USDC": 1, "ETH": 3000, "WETH": 3000, "AZTEC": 0.0124]
            feePerL2Gas = 2_186_613_113_685
            gasPriceWei = 400_000_000
            // The steps' row counts a co-signer's asks (prd §1918); made up.
            if mode == .deposit { keyOption = "0x0000000000000000000000000000000000005e1d"; keyLeft = 100; maxUSD = 100 }
            #if DEBUG
            // `-aztecPaysSample YES`: two payments kept and a third on the
            // line, made-up Aztec accounts (prd §1952).
            if mode == .send, UserDefaults.standard.bool(forKey: "aztecPaysSample"), pays.isEmpty {
                pays = [Pay(recipient: "0x" + String(repeating: "1a", count: 32), amount: "5"),
                        Pay(recipient: "0x" + String(repeating: "2b", count: 32), amount: "3")]
                recipient = "0x" + String(repeating: "3c", count: 32)
            }
            #endif
            stage = .ready
            return
        }
        Task { await readCosts() }
        guard let safe = YourAccountKey.address else { stage = .failed(String(localized: "There is no account on this iPhone")); return }
        switch mode {
        case .deposit:
            async let safeStanding = ShieldBridge.eligibility(safe)
            var held: [String: String] = [:]
            for asset in ShieldBridge.assets { held[asset.symbol] = await Self.balance(of: asset.ethToken, at: safe) }
            // **PLAIN ETH IS ITS OWN CHOICE (prd §1943; user: "if user holds
            // weth it needs to say weth", "we can't call weth eth").** ETH is
            // wrapped into WETH in the move itself; WETH goes in as it is.
            // A little ETH stays back for the moves' own gas.
            let wrappable = await Self.wrappableETH(at: safe)
            if wrappable > 0 { held["ETH"] = NSDecimalNumber(decimal: wrappable).stringValue }
            held["AZTEC"] = await Self.balance(of: AztecGas.token, at: safe)
            ownHeld = held
            bringsGas = AztecProver.isAvailable && AztecGas.ridesAlong
            guard let standing = await safeStanding else { stage = .failed(String(localized: "Shield did not answer")); return }
            // **YOUR CO-SIGNER, WHEN SHIELD SCORES IT (prd §1720).** A Safe
            // cannot link accounts on Human Passport's page; your co-signer
            // can. When your account is not eligible and your co-signer is,
            // the deposit is the co-signer's, and what it holds counts too
            // (your account moves it the rest).
            // **ALWAYS THE CO-SIGNER (prd §1890).** Shield's sign-in takes one
            // key's signature (256 characters at most); a Safe answers with
            // its owners' and the contract's, so it can never sign in, even
            // where Shield's screening tier calls it eligible (measured
            // 2026-11-18: the Safe "eligible", method none, up to $100).
            viaCoSigner = nil
            coSigner = nil
            coSignerScore = nil
            coSignerAllowance = [:]
            bothKeys = false
            keyOption = nil
            keyLeft = nil
            coSignerMax = nil
            let account = standing
            if !standing.sanctioned,
               let found = try? await YourAccountChain.knownSigners(YourAccountOp.ethereum, safe).first {
                // Remembered short of the score too: the way in names it (prd §1820).
                coSigner = found
                if let theirs = await ShieldBridge.eligibility(found) {
                    coSignerScore = Int(theirs.score)
                    if theirs.eligible, !theirs.sanctioned {
                        viaCoSigner = found
                        coSignerMax = theirs.maxUSD
                        for asset in ShieldBridge.assets {
                            coSignerAllowance[asset.symbol] = Decimal(string: await ShieldBridge.allowance(
                                of: asset.ethToken, owner: found, spender: asset.portal)) ?? 0
                        }
                        bothKeys = ((try? await YourAccountChain.knownThreshold(YourAccountOp.ethereum, safe)) ?? 1) >= 2
                        for asset in ShieldBridge.assets {
                            let more = Decimal(string: await Self.balance(of: asset.ethToken, at: found)) ?? 0
                            held[asset.symbol] = NSDecimalNumber(decimal: (Decimal(string: held[asset.symbol] ?? "0") ?? 0) + more).stringValue
                        }
                    }
                }
            }
            // **YOUR SHIELD KEY, FOR EVERYONE (prd §1920, §1922).** Up to
            // Shield's screening tier a day, less what it moved today; what
            // the key holds counts too (a move that stopped half way is
            // finished by the next).
            if !account.sanctioned, let key = ShieldKey.address,
               let mine = await ShieldBridge.eligibility(key), mine.eligible, !mine.sanctioned {
                let left = max(0, mine.screeningUSD - ShieldKey.movedToday())
                if left > 0 || viaCoSigner == nil {
                    keyOption = key
                    keyLeft = left
                }
                for asset in ShieldBridge.assets {
                    let more = Decimal(string: await Self.balance(of: asset.ethToken, at: key)) ?? 0
                    held[asset.symbol] = NSDecimalNumber(decimal: (Decimal(string: held[asset.symbol] ?? "0") ?? 0) + more).stringValue
                }
            }
            safeHeld = held
            holdings = depositHoldings(held)
            maxUSD = viaCoSigner != nil ? coSignerMax : keyLeft
            if account.sanctioned || (viaCoSigner == nil && keyOption == nil) {
                stage = .shieldNo(score: AztecWayIn.shownScore(coSignerScore: coSignerScore, accountScore: Int(standing.score)),
                                  threshold: Int(standing.threshold), sanctioned: standing.sanctioned)
                return
            }
            // Holding no AZTEC stops nobody: gas is bought with what you move (prd §1700aa).
            if holdings.isEmpty { stage = .needsFunds(address: safe); return }
            keepPick()
            stage = .ready
        case .send:
            // **WHAT IT LAST READ, AT ONCE (prd §1700r, user: "why does
            // 'reading aztec' take so long?" — the engine's start and sync, a
            // minute or two measured).** The stored balance stands while the
            // engine refreshes behind it; a move already under way is never
            // taken back to ready.
            let store = AztecAccountStore.shared
            func fill() {
                holdings = store.privateHeld.compactMap { h -> Holding? in
                    guard let units = h.privateUnits, let have = Decimal(string: units), have > 0, h.decimals != nil else { return nil }
                    return Holding(symbol: h.name, units: units)
                }
            }
            fill()
            if !holdings.isEmpty, !AztecGas.needed { keepPick(); stage = .ready }
            if AztecProver.isAvailable { await store.refresh() }
            guard stage == .reading || stage == .ready else { return }
            fill()
            if holdings.isEmpty { stage = .nothingPrivate; return }
            if AztecGas.needed { stage = .needsGas; return }
            keepPick()
            stage = .ready
        }
    }

    private func depositHoldings(_ held: [String: String]) -> [Holding] {
        // USDC, then plain ETH, then WETH: each by its own name (prd §1943).
        ["USDC", "ETH", "WETH"].compactMap { symbol -> Holding? in
            guard let units = held[symbol], let have = Decimal(string: units), have > 0 else { return nil }
            return Holding(symbol: symbol, units: units)
        }
    }

    /// ETH kept back from wrapping for the moves' own gas (prd §1943): the
    /// operation, and the ETH your account hands its Shield key or
    /// co-signer for their two sends.
    static let ethReserve: Decimal = 1_000_000_000_000_000   // 0.001 ETH

    /// Your account's plain ETH a move in may wrap, base units: its balance
    /// less `ethReserve`, never below zero.
    static func wrappableETH(at owner: String) async -> Decimal {
        guard let hex = try? await YourAccountChain.rpc(YourAccountOp.ethereum, "eth_getBalance", [owner, "latest"]) as? String,
              let units = ShieldBridge.decimal(hex: String(hex.dropFirst(2))), let wei = Decimal(string: units) else { return 0 }
        return max(0, wei - ethReserve)
    }

    /// An ERC-20 balance on Ethereum, base units, or "0".
    static func balance(of token: String, at owner: String) async -> String {
        let data = "0x70a08231" + String(repeating: "0", count: 24) + owner.lowercased().dropFirst(2)
        guard let answer = try? await YourAccountChain.rpc(YourAccountOp.ethereum, "eth_call", [["to": token, "data": data], "latest"]) as? String
        else { return "0" }
        return ShieldBridge.decimal(hex: String(answer.dropFirst(2))) ?? "0"
    }

    /// The move, as the sentence says it.
    func run() async {
        guard stage == .ready, amountOK, let units, let asset else { return }
        // One send at a time: the engine proves one, and its words name no
        // send. A move-in is signed on Ethereum and may go meanwhile.
        guard mode != .send || !anotherIsGoing else { stage = .failed(String(localized: "A send is still on its way")); return }
        let steps = PrivateSendSteps.shared
        // Last send's rows go; this send's start at its own tap (prd §1700x).
        steps.forget(.move)
        let report: @Sendable (YourAccountChain.Stage) async -> Void = { s in
            await MainActor.run {
                self.stage = .working(s == .signing ? String(localized: "Confirm with Face ID") : String(localized: "Sending…"))
                switch s {
                case .signing, .cosigning: steps.mark(.signing)
                case .sending, .landing: steps.mark(.sent)
                case .preparing: break
                }
            }
        }
        do {
            switch mode {
            case .deposit:
                stage = .working(String(localized: "Checking…"))
                // A move-in is signed on Ethereum, not proved (prd §1700x), as
                // Railgun's is: Checking · Signing · Sent on Ethereum.
                steps.begin(.move, plan: .signed(.ethereum, onThisPhone: viaKey != nil))
                let gas = try await gasPlan(asset)
                if viaKey != nil {
                    let moved = amountUSD
                    let sent = try await ShieldBridge.depositFromKey(asset, units: units, gas: gas, sale: buysGas ? gasSale : nil, wraps: wraps) { words in
                        self.stage = .working(words)
                    }
                    // Counted against the key's day (prd §1922).
                    if let moved { ShieldKey.noteMoved(moved) }
                    steps.finish()
                    stage = .done(sent.transaction)
                    break
                }
                guard let coSigner = viaCoSigner else { return }
                let sent = try await ShieldBridge.depositFromCoSigner(asset, units: units, coSigner: coSigner, gas: gas, sale: buysGas ? gasSale : nil, wraps: wraps) { words in
                    self.stage = .working(words)
                }
                steps.finish()
                stage = .done(sent.transaction)
            case .send:
                guard let recipient else { return }
                if toAztec {
                    try await PrivateRootKey.unlock(reason: String(localized: "Send privately on Aztec"))
                    // Your co-signer reads every payment (prd §1952).
                    let every = allPays ?? [(recipient, units)]
                    try await AztecCoSign.approve(every.map {
                        String(localized: "Send \(PrivateMoney.figure($0.units, decimals: decimals, symbol: symbol)) on Aztec to \($0.to)")
                    }.joined(separator: "; "))
                    // The rows' clock starts at the tap, before a cold engine
                    // has said anything (prd §1700w).
                    steps.begin(.move, plan: .send(.aztec))
                    stage = .working(String(localized: "Sending…"))
                    // Every ask is answered: the rest needs nobody, so the
                    // sheet goes and the shell's capsule says the rest
                    // (prd §1777).
                    if let onAway, steps.sendAway(from: .aztec, landed: PrivateSendSteps.Place.aztec.sent) {
                        Self.kept = self
                        onAway()
                    }
                    // One transaction, every payment in it (prd §1952).
                    let out: [String: Any]?
                    if every.count > 1 {
                        let list = every.map { ["to": $0.to.lowercased(), "units": $0.units] }
                        guard let json = try? JSONSerialization.data(withJSONObject: list), let text = String(data: json, encoding: .utf8) else {
                            throw AztecGas.Failure(message: String(localized: "This move could not be written"))
                        }
                        out = try await AztecEngine.shared.call("sendPrivatelyMany", [symbol, text, AztecGas.unminted]) as? [String: Any]
                    } else {
                        out = try await AztecEngine.shared.call("sendPrivately", [symbol, recipient.lowercased(), units, AztecGas.unminted]) as? [String: Any]
                    }
                    AztecGas.spent(by: out)
                    // The engine says "done" itself; a send it handed back
                    // without the word is done all the same.
                    steps.finishAway()
                    paidInTheOpen = (out?["paid"] as? String) == "own"
                    // Its Activity row, now: nothing reads it back (prd §1953).
                    if let tx = out?["tx"] as? String, !tx.isEmpty, let context = SharedStore.live?.mainContext {
                        let total = every.reduce(Decimal(0)) { $0 + (Decimal(string: $1.units) ?? 0) }
                        let figure = PrivateMoney.figure(NSDecimalNumber(decimal: total).stringValue, decimals: decimals, symbol: symbol)
                        let who = every.count > 1 ? String(localized: "\(every.count) people") : AddressTail.short(recipient)
                        PrivateActivity.landAztec(hash: tx, title: PrivateMoney.activityTitle(figure: figure, to: who), context: context)
                    }
                    stage = .done(out?["tx"] as? String ?? "")
                } else if toEthereum {
                    steps.begin(.move, plan: .send(.aztec))
                    stage = .working(String(localized: "Sending…"))
                    let exit = try await ShieldBridge.exit(asset, units: units, to: recipient, usd: amountUSD)
                    // Out to Ethereum, its row at once too (prd §1953).
                    if !exit.transaction.isEmpty, let context = SharedStore.live?.mainContext {
                        PrivateActivity.landAztec(hash: exit.transaction,
                                                  title: PrivateMoney.activityTitle(figure: PrivateMoney.figure(units, decimals: decimals, symbol: symbol),
                                                                                    to: AddressTail.short(recipient)),
                                                  context: context)
                    }
                    stage = .done(exit.transaction)
                }
                await AztecAccountStore.shared.refresh()
            }
            if Self.kept === self { Self.kept = nil }
            DSHaptic.success()
        } catch {
            // The rows keep the failure on the step it reached (prd §1700x),
            // in the sheet or behind it (prd §1777).
            let words = AztecEngine.words(error)
            if Self.kept === self, steps.away != nil { steps.failAway(words) } else { steps.fail(words) }
            stage = .failed(words)
            if Self.kept === self { DSHaptic.failure() }
        }
    }

    /// The gas a move-in brings along, when it brings any (prd §1700aa): the
    /// AZTEC your account holds, or, holding too little, bought with a little
    /// of the token being moved.
    private func gasPlan(_ asset: ShieldBridge.Asset) async throws -> AztecGas.Plan? {
        guard bringsGas else { return nil }
        guard buysGas else { return try await AztecGas.plan(units: AztecGas.rideAlong) }
        guard let safe = YourAccountKey.address, let sale = gasSale else {
            throw AztecGas.Failure(message: String(localized: "Gas for Aztec could not be priced just now. Try again."))
        }
        // The sale is your account's own, even when your co-signer deposits
        // (prd §1720): it must hold that much itself.
        guard (Decimal(string: ownHeld[symbol] ?? "0") ?? 0) >= (Decimal(string: sale) ?? 0) else {
            throw AztecGas.Failure(message: String(localized: "Your account needs a little \(symbol) of its own to buy gas for Aztec"))
        }
        let sell = YourAccountOp.Token(symbol: asset.symbol, decimals: asset.decimals, contract: asset.ethToken)
        return try await AztecGas.plan(selling: sell, units: sale, account: safe)
    }

    /// Claims what Aztec has carried (`AztecArrivals`: the Wallet's open and
    /// Holdings ask too, one pass at a time, prd §1700ac).
    func settle() async { await AztecArrivals.settle() }

    var waiting: Bool { AztecArrivals.waiting }
}

struct MoveAztecPrivateSentence<Head: View>: View {
    let move: AztecMove
    var inTray = false
    /// Leaves the sentence: back to Send's recipients (`pickRecipient`) or
    /// its networks (`switchOff`), as 0xBow's does.
    var leave: (MovePrivateLeave) -> Void = { _ in }
    @ViewBuilder let head: () -> Head

    private enum Blank { case token, recipient, amount }
    @State private var open: Blank?
    /// The cost's list stands in the rows' place (prd §1876).
    @State private var costOpen = false
    @State private var typed = ""
    @State private var notAnAddress = false
    @State private var copied = false
    @State private var passport = false
    @Environment(ShellChrome.self) private var chrome

    var body: some View {
        // **A RECEIPT, AS EVERY VERB'S (prd §1931), IN AZTEC'S INK (§1779).**
        deck
        // Send opens whole: its facts and deck clip in the short sheet.
        .onAppear { chrome.moveTall = true }
        .onChange(of: open) { _, now in if now != nil { chrome.moveTall = true } }
        // The deck opens on the keys once read: never an empty panel under a
        // sentence that asks how much (prd §1782, as Earn's).
        .onChange(of: live, initial: true) { _, on in
            if on, open == nil, move.amount.isEmpty, move.mode == .deposit || move.recipient != nil {
                withAnimation(DS.Motion.standard) { open = .amount }
            }
        }
        // A send kept behind its sheet is shown as it stands, running or
        // failed, never read over (prd §1777).
        .task(id: move.mode) { if AztecMove.kept !== move { await move.read() } }
        .onAppear { if AztecMove.kept === move { PrivateSendSteps.shared.bringBack() } }
        .onDisappear {
            guard AztecMove.kept === move else { return }
            if case .working = move.stage {
                PrivateSendSteps.shared.sendAway(from: .aztec, landed: PrivateSendSteps.Place.aztec.sent)
            } else {
                // A failure seen is put away with its sheet.
                AztecMove.kept = nil
                PrivateSendSteps.shared.forget(.move)
            }
        }
        // What Aztec has carried is claimed while the sentence stands.
        .task {
            guard AztecProver.isAvailable, !DemoMode.isActive else { return }
            while !Task.isCancelled {
                if move.waiting { await move.settle() }
                try? await Task.sleep(for: .seconds(30))
            }
        }
        // Back from Human Passport, Shield is asked again. While the page is
        // open the co-signer's score is read under it (prd §1820).
        .sheet(isPresented: $passport, onDismiss: { Task { await move.read() } }) {
            AztecBrowserView(url: URL(string: "https://app.passport.xyz")!, aztec: false, ethereum: true,
                             above: move.coSigner.map { address in
                                 AnyView(PassportScoreBand(address: address, threshold: shieldThreshold) { passport = false })
                             })
                .presentationDragIndicator(.visible)
        }
    }

    private var live: Bool { move.stage == .ready }

    /// The facts, the cost a row of them (prd §1876).
    private var receipt: some View {
        // **THE TOKEN LEADS THE RECEIPT, AS SEND'S DOES (prd §1929):** Home's
        // row, what leaves and where from; the facts under it.
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            // The token and its amount are the receipt's lines (prd §1931).
            MoveCostRows(cost: live && move.amountOK ? move.cost : nil, open: $costOpen, ink: DS.aztecInk, indented: false) {
                ForEach(facts, id: \.name) { f in
                    MoveFactRow(name: f.name, value: f.value, valueInk: f.ink, indented: false)
                }
            }
        }
    }

    /// **THE FACTS UNDER THE SENTENCE (prd §1927):** what the rows said that
    /// is not a choice. Where it goes and comes from, its network, who signs,
    /// what Shield takes, and who carries it.
    private var facts: [(name: String, value: String, ink: Color)] {
        switch move.stage {
        case .ready, .shieldNo(_, _, false), .needsGas: break
        default: return []
        }
        var out: [(name: String, value: String, ink: Color)] = []
        // **NOTHING THE SENTENCE SAYS (prd §1929):** it names the token,
        // the account and Aztec; the receipt says where the money comes from.
        if move.mode == .deposit {
            out.append((String(localized: "From"), String(localized: "Your public account on Ethereum"), DS.textPrimary))
            if live, move.viaKey != nil {
                out.append((String(localized: "Signs"), String(localized: "This iPhone"), DS.textPrimary))
            } else if live, let asks = move.coSignerAsks {
                out.append((String(localized: "Co-signer"),
                            asks == 1 ? String(localized: "Signs once") : String(localized: "Signs \(asks) times"), DS.textPrimary))
            }
        } else {
            // It reaches Aztec, or goes out to Ethereum (prd §1924).
            out.append((String(localized: "Reaches"), move.pays.isEmpty ? String(localized: "Aztec, or out to Ethereum") : "Aztec", DS.aztecInk))
            // Out to Ethereum: who signs in to Shield (prd §1950).
            if live, move.toEthereum {
                out.append(move.outFitsKey
                           ? (String(localized: "Signs"), String(localized: "This iPhone"), DS.textPrimary)
                           : (String(localized: "Over $100 a day"), String(localized: "Your co-signer signs"), DS.textPrimary))
            }
        }
        if live {
            out.append((String(localized: "Through"), move.mode == .send && !move.toEthereum ? "Aztec" : "Shield", DS.textPrimary))
        }
        return out
    }

    private var isDone: Bool { if case .done = move.stage { true } else { false } }

    private var leadsWithVerb: Bool {
        switch move.stage {
        // A failure keeps the sentence's own verb: "Send" drew twice (above
        // and inside), found by the Railgun session on the simulator (prd §1700y).
        case .ready, .working, .failed: true
        default: false
        }
    }

    private var figure: String {
        // Several payments say their total (prd §1952).
        let line = Decimal(string: move.units ?? "0") ?? 0
        return PrivateMoney.figure(NSDecimalNumber(decimal: line + move.paysUnits).stringValue, decimals: move.decimals, symbol: move.symbol)
    }

    /// **ADD ANOTHER IN THE FOOT, BESIDE BACK (prd §1952, as Send's §1931).**
    private var addAnotherWord: some View {
        Button {
            withAnimation(DS.Motion.standard) { move.addAnother(); open = .recipient }
            DSHaptic.selection()
        } label: {
            Text("+ Add another")
                .dsText(.heading17)
                .foregroundStyle(DS.textSecondary)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .accessibilityHint(Text("Keeps this payment in the transaction and starts the next one"))
    }

    // MARK: - The sentence

    @ViewBuilder private var sentence: some View {
        switch move.stage {
        case .reading:
            MovePhrase(String(localized: "Reading Aztec…"), ink: DS.textSecondary)
        case .needsFunds(let address):
            MoveClause(glue: String(localized: "Fund")) {
                Button { copy(address) } label: { MoveWord(YourAccount.short(address), ink: DS.aztecInk) }
                    .buttonStyle(RowPress())
                    .accessibilityHint(Text("Copies the address"))
            }
            MovePhrase(String(localized: "Ethereum"), glue: String(localized: "on"))
            MovePhrase(String(localized: "first."))
        case .shieldNo(_, _, true):
            MovePhrase(String(localized: "Shield will not move money for this account."), ink: DS.textPrimary)
        case .nothingPrivate:
            MovePhrase(String(localized: "Nothing private to send on Aztec yet."), ink: DS.textSecondary)
        // **WHAT IS MISSING IS A ROW, NOT THE SENTENCE (prd §1803).** The
        // sentence keeps saying the move; an amber row under the rows says
        // what it waits on, and the button is the fix.
        case .shieldNo, .needsGas:
            head()
            if move.mode == .deposit {
                MovePhrase("Aztec.", glue: String(localized: "to"), ink: DS.aztecInk)
            } else {
                MovePhrase("Aztec.", glue: String(localized: "from"), ink: DS.aztecInk)
            }
        default:
            if !isDone { head() }
            if move.stage == .ready {
                if !move.amount.isEmpty { MoveClause { MoveWord(move.amount, ink: DS.aztecInk) } }
                MoveClause {
                    Button { toggle(.token) } label: {
                        MoveWord(move.symbol, ink: MoveSentence.settledInk)
                    }
                    .buttonStyle(RowPress())
                    .accessibilityLabel(Text("Token, \(move.symbol)"))
                    .accessibilityHint(Text("Picks the token"))
                }
            } else {
                MoveClause(glue: isDone ? String(localized: "Sent") : nil) {
                    MoveWord(figure, ink: DS.textPrimary)
                        .accessibilityLabel(Text("Amount, \(figure)"))
                }
            }
            if move.mode == .deposit {
                // "Your private balance", as on Ethereum (prd §1719): in Move
                // a balance is where money sits; "account" stays where it
                // has an address and apps (Your account, Receive).
                MoveWordsClause(glue: String(localized: "to"), words: "Aztec.",
                                ink: move.stage == .ready ? DS.aztecInk : DS.textPrimary,
                                action: { if move.stage == .ready { leave(.pickRecipient) } },
                                hint: Text("Picks the address"))
            } else {
                MoveWordsClause(glue: String(localized: "from"), words: "Aztec",
                                ink: move.stage == .ready ? DS.aztecInk : DS.textPrimary,
                                action: { if move.stage == .ready { leave(.switchOff) } },
                                hint: Text("Picks where it comes from"))
                MoveClause(glue: String(localized: "to")) { recipientWord }
            }
        }
    }

    @ViewBuilder private var recipientWord: some View {
        let live = move.stage == .ready
        Button { if live { toggle(.recipient) } } label: {
            Group {
                if !move.pays.isEmpty, move.recipient != nil {
                    // Several payments: how many (prd §1952).
                    MoveWord(String(localized: "\(move.pays.count + 1) people."), ink: MoveSentence.settledInk)
                } else if let to = move.recipient {
                    MoveWord(AddressTail.short(to) + ".", ink: MoveSentence.settledInk)
                } else {
                    MoveWord(String(localized: "address."), ink: open == .recipient ? DS.aztecInk : DS.textTertiary)
                }
            }
        }
        .buttonStyle(RowPress())
        .accessibilityLabel(Text(move.recipient.map { "To \($0)" } ?? String(localized: "Pick an address")))
    }

    // MARK: - The line

    @ViewBuilder private var line: some View {
        switch move.stage {
        case .ready, .working:
            if stepsRun != nil {
                // The steps stand in the foot; the sentence stands alone (prd §1700x).
                EmptyView()
            } else if move.stage == .ready, !move.pays.isEmpty, move.recipient != nil, !move.toAztec {
                // Several payments are Aztec to Aztec only (prd §1952).
                Text("Several payments go to Aztec accounts only").dsText(.body17).foregroundStyle(DS.attentionInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else if move.stage == .ready, let problem = move.amountProblem {
                Text(verbatim: problemLine(problem)).dsText(.body17).foregroundStyle(DS.attentionInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else if move.stage == .ready {
                // The amount in dollars and two choices (prd §1700y, as
                // Railgun's §1728 item 1); what it costs is the foot's.
                // What you have and Half · All are the amount's menu (prd §1802).
                EmptyView()
            } else {
                Text(verbatim: readyLine).dsText(.body17).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .needsFunds:
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(verbatim: fundsLine).dsText(.body17).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                checkAgain
            }
        case .shieldNo(let score, let threshold, let sanctioned):
            // **THE WAY IN, AS STEPS (prd §1820).** Not "Shield needs 20 ·
            // Yours 0": what to do, in order, the act always the next one.
            if !sanctioned {
                AztecWayInRows(coSigner: move.coSigner, score: score, threshold: threshold, maxUSD: move.maxUSD)
            }
        case .needsGas:
            VStack(alignment: .leading, spacing: 0) {
                fact(String(localized: "Gas"), String(localized: "Needed first"), ink: DS.attentionInk)
                fact(String(localized: "Costs"), String(localized: "30 AZTEC, about $0.45"), ink: DS.textSecondary)
            }
        case .failed(let words):
            // A failure the rows carry is said once, on its step.
            if stepsRun == nil {
                Text(verbatim: words).dsText(.body17).foregroundStyle(DS.attentionInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .done:
            Text(verbatim: doneLine).dsText(.body17).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        default:
            EmptyView()
        }
    }

    private var readyLine: String {
        if case .working(let words) = move.stage { return words }
        switch move.mode {
        case .deposit:
            let gas = move.bringsGas ? String(localized: "with 30 AZTEC of private gas") : nil
            // Who moves it, said once, when it is not your account (prd
            // §1720): Shield takes it from the wallet it scored.
            let who = move.viaCoSigner.map { String(localized: "From your co-signer (\(AddressTail.short($0)))") }
            return [who, String(localized: "Through Shield"), String(localized: "0.5% fee"), String(localized: "5 to 15 minutes"), gas]
                .compactMap { $0 }.joined(separator: " · ")
        case .send:
            if move.toEthereum {
                return [String(localized: "Through Shield"), String(localized: "0.5% fee"), String(localized: "finish on Ethereum in about an hour")]
                    .joined(separator: " · ")
            }
            return String(localized: "Who, what and how much stay private · about 20 seconds")
        }
    }

    private func problemLine(_ problem: AztecMove.AmountProblem) -> String {
        switch problem {
        case .moreThanHeld(let have): String(localized: "You have \(have).")
        case .leavesNoGas(let most): String(localized: "Up to \(most): a little buys gas for Aztec.")
        case .overShieldCap(let cap): String(localized: "Shield moves up to $\(cap) at a time for your score.")
        case .overDailyCap(let cap): String(localized: "Up to $\(cap) more today without a co-signer.")
        }
    }

    /// Gas is bought with what you move (prd §1700aa), so holding no AZTEC
    /// stops nobody here: only holding nothing Shield moves does.
    private var fundsLine: String {
        String(localized: "Shield moves USDC, ETH or WETH from your account on Ethereum.")
    }

    /// How long the send took, tap to block, so the next wait feels known (prd §1700w).
    private var sentTotal: Int? {
        guard let run = PrivateSendSteps.shared.run, run.kind == .move, run.ok == true else { return nil }
        return run.total
    }

    private var doneLine: String {
        switch move.mode {
        case .deposit: String(localized: "On its way: Aztec carries it in minutes, then it is yours.")
        case .send:
            move.toEthereum ? String(localized: "Proved. In about an hour Needs you offers Finish on Ethereum.")
                : move.paidInTheOpen ? String(localized: "Sent privately. Its gas was paid by your account, in the open.")
                : sentTotal.map { String(localized: "Sent privately · \($0) s") } ?? String(localized: "Sent privately.")
        }
    }

    // MARK: - Choices

    private func toggle(_ blank: Blank) {
        guard live else { return }
        withAnimation(DS.Motion.standard) { open = open == blank ? nil : blank }
        DSHaptic.selection()
    }

    /// The tokens there are to move, each with how much (prd §1700q).
    /// Move's one token list (prd §1910): your private account's tokens, on
    /// Aztec, as tiles.
    private var tokens: some View {
        MoveTokenGrid(places: [MoveTokenPlace(id: "aztec", choices: move.holdings.map { holding in
            let places = holding.symbol == "USDC" ? 6 : 18
            // Going in, the tokens are on Ethereum (prd §1943): said so.
            return MoveTokenChoice(id: holding.symbol, symbol: holding.symbol, network: move.mode == .deposit ? "Ethereum" : "Aztec",
                                   badge: move.mode == .deposit ? MoveSentence.networkMark(chainId: 1) : "brand-aztec",
                                   sub: PrivateMoney.figure(holding.units, decimals: places, symbol: ""),
                                   picked: holding.symbol == move.symbol) {
                withAnimation(DS.Motion.standard) { move.pick(holding.symbol); open = nil }
            }
        })])
    }

    /// An Aztec account (a private send) or an Ethereum address (out
    /// through Shield), typed or pasted.
    @ViewBuilder private var recipients: some View {
        // **YOUR ADDRESSES FIRST (prd §1700r, user: "it doesn't suggest my
        // existing addresses" — "it should").** Your account on Ethereum
        // (an exit to yourself), then the address book as Send's To lists it,
        // filtered by what is typed; the field and Paste stay for anyone else.
        ForEach(suggestions, id: \.address) { s in
            Button { take(s.address) } label: {
                HStack(spacing: DS.Space.s3) {
                    WalletFace(address: s.address, size: DS.Face.list, circular: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: s.name).dsText(MoveSentence.choiceRung).foregroundStyle(DS.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.5)
                        Text(verbatim: s.line).dsText(.body17).foregroundStyle(DS.textSecondary).lineLimit(1)
                    }
                    Spacer(minLength: DS.Space.s2)
                }
                .frame(minHeight: DSFeed.headHeight + DS.Space.s3)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
        }
        if notAnAddress {
            Text("That isn't an Aztec or Ethereum address").dsText(.body17).foregroundStyle(DS.attentionInk)
                .padding(.top, DS.Space.s2)
        }
        TextField(text: $typed, prompt: Text("0x…").foregroundStyle(DS.textTertiary)) { Text("Address") }
            .dsText(.body17)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .frame(minHeight: DSFeed.headHeight + DS.Space.s3)
            .onSubmit { take(typed) }
        Button { take(UIPasteboard.general.string ?? "") } label: {
            Text("Paste").dsText(.body17).foregroundStyle(DS.aztecInk)
                .frame(maxWidth: .infinity, minHeight: DSFeed.headHeight + DS.Space.s3, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
    }

    private struct Suggestion { let name: String; let line: String; let address: String }

    /// Your account, then the book's Ethereum addresses (prd §1700r).
    private var suggestions: [Suggestion] {
        let q = typed.trimmingCharacters(in: .whitespaces).lowercased()
        let typingAnAddress = AztecAddressText.isAztec(q) || PrivateMoney.isAddress(q)
        guard !typingAnAddress else { return [] }
        // Several payments go to Aztec accounts only (prd §1952): these are
        // Ethereum addresses, so none is offered.
        guard move.pays.isEmpty else { return [] }
        var out: [Suggestion] = []
        let mine = YourAccountKey.address
        let yours = String(localized: "Your account")
        if let mine, q.isEmpty || yours.lowercased().contains(q) || mine.lowercased().hasPrefix(q) {
            out.append(Suggestion(name: yours, line: String(localized: "Ethereum · \(AddressTail.short(mine))"), address: mine))
        }
        for e in AddressBook.shared.all where ENS.isHexAddress(e.address)
            && !(mine.map { WalletWatch.sameAddress($0, e.address) } ?? false)
            && (q.isEmpty || e.name.lowercased().contains(q) || e.address.lowercased().hasPrefix(q)) {
            out.append(Suggestion(name: e.name, line: AddressTail.short(e.address), address: EIP55.checksum(e.address)))
            if out.count >= 20 { break }
        }
        return out
    }

    private func take(_ raw: String) {
        let address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AztecAddressText.isAztec(address) || PrivateMoney.isAddress(address) else {
            typed = address
            DSHaptic.failure()
            withAnimation(DS.Motion.standard) { notAnAddress = !address.isEmpty }
            return
        }
        notAnAddress = false
        withAnimation(DS.Motion.standard) { move.recipient = address; open = nil }
        DSHaptic.selection()
    }

    // MARK: - The foot

    private var ready: Bool {
        move.stage == .ready && move.amountOK && (move.mode == .deposit || move.toAztec || move.toEthereum)
            // Several payments are Aztec to Aztec only (prd §1952).
            && (move.pays.isEmpty || move.toAztec) && !DemoMode.isActive
    }

    /// This sentence's send, while it works, once it failed with its steps, and
    /// once it is done (prd §1700x): the rows stand in the foot above the act.
    private var stepsRun: PrivateSendSteps.Run? {
        guard let run = PrivateSendSteps.shared.run, run.kind == .move else { return nil }
        switch move.stage {
        case .working: return run
        case .failed: return run.ok == false ? run : nil
        case .done: return run.ok == true ? run : nil
        default: return nil
        }
    }

    @Environment(\.moveBack) private var back

    /// **AZTEC'S DECK (prd §1927, as Earn's §1901):** the steps on Home's
    /// panel, the list or Move's keys under them, the foot's word held to act.
    private var deck: some View {
        MoveReceiptDeck(title: String(localized: "Send"), inTray: inTray, backDisabled: move.acting, back: {
            withAnimation(DS.Motion.standard) {
                // Back is the menu, never the step before (prd §1911).
                if costOpen { costOpen = false } else { open = nil; back?() }
            }
        }, lead: move.canAddAnother ? AnyView(addAnotherWord) : nil, lines: {
            if live {
                MoveReceiptSteps(steps: steps, disabled: move.acting)
            }
        }, content: {
                Group {
                    if open == .amount, live {
                        // **BIG KEYS, AT THE SAME HEIGHT AS SEND'S (prd §1931)**,
                        // Half and All their top row (prd §1932).
                        VStack(spacing: MoveReceipt.gap) {
                            Spacer(minLength: 0)
                            let quick = AztecMove.Pick.allCases.compactMap { p in move.amount(for: p).map { (p, $0) } }
                            if !quick.isEmpty {
                                MoveQuickKeys(keys: quick.map { p, value in
                                    MoveQuickKeys.Key(id: value, word: p == .half ? String(localized: "Half") : String(localized: "All"),
                                                      on: move.amount == value) { move.amount = value }
                                }, onInk: DS.aztecInk)
                            }
                            MoveKeypad(text: Binding(get: { move.amount }, set: { move.amount = $0 }),
                                       places: min(move.decimals, 6),
                                       keyHeight: MoveSentence.bigKeyHeight, big: true)
                        }
                        .transition(.opacity)
                    } else if open == .token, live {
                        ScrollView { tokens.padding(.vertical, DS.Space.s2) }
                            .scrollIndicators(.hidden)
                            .contentMargins(.bottom, MoveDeck.fade, for: .scrollContent)
                            .transition(.opacity)
                    } else if open == .recipient, live {
                        ScrollView { VStack(alignment: .leading, spacing: 0) { recipients }.padding(.vertical, DS.Space.s2) }
                            .scrollIndicators(.hidden)
                            .contentMargins(.bottom, MoveDeck.fade, for: .scrollContent)
                            .transition(.opacity)
                    } else if live {
                        // **THE RECEIPT IS THE DECK'S (prd §1927):** nothing
                        // open, what it is and costs, as Send's Ready.
                        ScrollView { receipt.padding(.vertical, DS.Space.s2) }
                            .scrollIndicators(.hidden)
                            .contentMargins(.bottom, MoveDeck.fade, for: .scrollContent)
                            .transition(.opacity)
                    } else {
                        // Reading, blocked, working, done: the sentence says
                        // where it stands; the steps and the facts the rest.
                        ScrollView {
                            VStack(alignment: .leading, spacing: DS.Space.s3) {
                                MoveFlow { sentence }
                                    .moveHoldFill()
                                    .allowsHitTesting(false)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if let run = stepsRun {
                                    // Face ID came before a send's clock; a move-in signs inside it.
                                    PrivateStepRows(run: run, confirmed: move.mode == .send ? String(localized: "Confirmed with Face ID") : nil)
                                        .transition(.opacity)
                                } else if move.stage == .reading, move.mode == .send, let since = move.readingSince {
                                    PrivateWarmingRow(since: since).transition(.opacity)
                                }
                                if stepsRun == nil, !facts.isEmpty { receipt }
                                line
                            }
                        }
                        .scrollIndicators(.hidden)
                        .transition(.opacity)
                    }
                }
        }, word: { footWord })
        .animation(DS.Motion.standard, value: open)
    }

    @Environment(\.horizontalSizeClass) private var sizeClass

    /// To (where it goes: back to Send's recipients for a move-in), Token,
    /// Amount; a send from Aztec asks To in its own list.
    private var steps: [MoveDeckStep] {
        var out: [MoveDeckStep] = []
        // **THE SENTENCE'S WORDS ARE THE LINES (prd §1931), AZTEC'S IN ITS INK
        // (§1779).**
        if move.mode == .deposit {
            out.append(MoveDeckStep(id: "to", word: String(localized: "To"), answered: true,
                                    value: "Aztec", aztec: true, glyph: "diamond",
                                    note: MoveSentence.aztecInRule) { leave(.pickRecipient) })
        } else {
            out.append(MoveDeckStep(id: "from", word: String(localized: "From"), answered: true,
                                    value: "Aztec", aztec: true, glyph: "diamond",
                                    // Several payments stay on Aztec (prd §1952).
                                    note: move.pays.isEmpty ? MoveSentence.aztecSendRule : MoveSentence.aztecRule) { leave(.switchOff) })
            // The payments Add another kept, each with its × (prd §1952).
            for pay in move.pays {
                out.append(MoveDeckStep(id: "pay-\(pay.id.uuidString)", word: String(localized: "To"), answered: true,
                                        value: "\(AddressTail.short(pay.recipient)) · \(pay.amount) \(move.symbol)",
                                        remove: { withAnimation(DS.Motion.standard) { move.removePay(pay.id) } }) {})
            }
            out.append(MoveDeckStep(id: "to", word: move.pays.isEmpty ? String(localized: "To") : String(localized: "And"),
                                    on: open == .recipient,
                                    answered: move.recipient != nil, value: move.recipient.map { AddressTail.short($0) }) { toggle(.recipient) })
        }
        let place = move.mode == .deposit ? "Ethereum" : "Aztec"
        out.append(MoveDeckStep(id: "token", word: String(localized: "Token"), on: open == .token, answered: true,
                                value: "\(move.symbol) · \(place)",
                                mark: MoveRowMark(token: move.symbol, network: move.mode == .deposit ? MoveSentence.networkMark(chainId: 1) : nil),
                                aztec: move.mode == .send) { toggle(.token) })
        out.append(MoveDeckStep(id: "amount", word: String(localized: "Amount"), on: open == .amount,
                                answered: !move.amount.isEmpty,
                                value: move.amount.isEmpty ? (open == .amount ? "0" : nil) : "\(move.amount) \(move.symbol)") { toggle(.amount) })
        return out
    }

    /// **THE FOOT'S ONE WORD (prd §1897 item 7):** Hold to send in Aztec's
    /// ink; the stage while it works; what unblocks it; Done or Try again.
    @ViewBuilder private var footWord: some View {
        switch move.stage {
        case .needsFunds(let address):
            MoveFootWord(word: copied ? String(localized: "Copied") : String(localized: "Copy address"), ink: DS.aztecInk) { copy(address) }
        case .shieldNo(let score, let threshold, let sanctioned):
            // The act is the next step (prd §1820).
            if !sanctioned {
                switch AztecWayIn.next(coSigner: move.coSigner, score: score, threshold: threshold) {
                case .coSigner:
                    MoveFootWord(word: String(localized: "Add a co-signer"), ink: DS.aztecInk) {
                        DSHaptic.selection()
                        chrome.moveTray = false
                        chrome.openYourAccount(at: FeedScreen.SecurityAnchor.account.id)
                    }
                case .score, .send:
                    MoveFootWord(word: String(localized: "Raise your score"), ink: DS.aztecInk) { passport = true }
                }
            }
        case .needsGas:
            MoveFootWord(word: String(localized: "Add gas"), ink: DS.aztecInk) {
                guard !DemoMode.isActive else { return }
                Task {
                    move.stage = .working(String(localized: "Confirm with Face ID"))
                    do { _ = try await AztecGas.topUp { _ in }; move.stage = .done("") }
                    catch { move.stage = .failed(AztecEngine.words(error)) }
                }
            }
        case .done:
            MoveFootWord(word: String(localized: "Done"), ink: DS.aztecInk) {
                if inTray { chrome.moveTray = false } else { leave(.switchOff) }
            }
        case .failed:
            MoveFootWord(word: String(localized: "Try again"), ink: DS.aztecInk) { Task { await move.read() } }
        case .working:
            MoveFootWord(word: footVerb, ink: DS.textSecondary)
        case .reading, .nothingPrivate:
            EmptyView()
        default:
            MoveHoldWord(word: DemoMode.isActive ? String(localized: "Not in the demo") : String(localized: "Hold to send"),
                         ink: DS.aztecInk, enabled: ready) {
                open = nil
                move.onAway = inTray ? { chrome.moveTray = false } : nil
                Task { await move.run() }
            }
        }
    }

    private func fact(_ name: String, _ value: String, ink: Color) -> some View {
        HStack(spacing: DS.Space.s2) {
            Text(verbatim: name).dsText(.body17).foregroundStyle(DS.textSecondary)
            Spacer(minLength: DS.Space.s2)
            Text(verbatim: value).dsText(.body17).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(minHeight: 30)
    }

    private var checkAgain: some View {
        Button {
            Task { await move.read() }
            DSHaptic.selection()
        } label: {
            Text("Check again").dsText(.heading24).foregroundStyle(DS.textPrimary)
                .lineLimit(1).fixedSize().frame(minHeight: 48)
        }
        .buttonStyle(RowPress())
    }

    /// Shield's score for the deposit, as Shield said it (20 today).
    private var shieldThreshold: Int {
        if case .shieldNo(_, let threshold, _) = move.stage { return threshold }
        return 20
    }

    private var footVerb: String {
        if case .working(let words) = move.stage { return words }
        return String(localized: "Send")
    }

    private func copy(_ address: String) {
        DSPasteboard.copy(address)
        DSHaptic.tap()
        withAnimation(DS.Motion.standard) { copied = true }
    }
}

enum AztecAddressText {
    /// An Aztec account's address: `0x` and 64 hex characters.
    static func isAztec(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        return t.hasPrefix("0x") && t.count == 66 && t.dropFirst(2).allSatisfy(\.isHexDigit)
    }
}
