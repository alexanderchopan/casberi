import Foundation
import Observation
import SwiftData

/// **SEND, PRIVATELY (prd §1554).** Two acts on Send, neither a verb:
///
/// - **Into your private balance** (`Mode.deposit`, the recipient "Your
///   private balance"): the private account opens (its seed behind Face ID),
///   the keystore is registered the first time (two transactions, so the
///   notes can be spent later), the deposit is proved on the phone and sent,
///   and the note is kept as waiting for approval.
/// - **From your private balance** (`Mode.send`, the Private switch on): the
///   account opens, finds its notes, proves a withdrawal of the amount to the
///   address, and hands it to 0xBow's relayer, which posts it and pays the
///   gas for a fee. Only APPROVED private money is spendable.
///
/// On Ethereum (prd §1563, every build, `PrivateMainnet.on`) your account
/// sends with Face ID and what moves in earns on Aave (`PrivateOnEthereum`);
/// on Sepolia (DEBUG builds only) the DEBUG test sender sends
/// (`PrivacyTestnetSender`).
@MainActor
@Observable
final class PrivateMove {

    enum Mode: Equatable { case deposit, send }

    enum Stage: Equatable {
        case reading
        case ready
        /// Switch on, nothing approved to spend.
        case nothingPrivate
        /// The sender holds too little Sepolia ETH; the address to fund.
        case needsFunds(String)
        /// Face ID, for the private account's seed.
        case opening
        /// The engine opening the account and reading the pool.
        case preparing
        case registering(Int)
        case proving
        case sending
        case done(String)
        case failed(String)
    }

    var mode: Mode
    var stage: Stage = .reading
    /// Switch on: who it goes to, an address.
    var recipient: String?
    /// **A ZK.MONEY TAG, PAID FROM YOUR PRIVATE BALANCE (prd §1874).** The
    /// bare tag; its one-time deposit address is asked of zk.money's
    /// resolver at the moment of sending, never kept, and the relayer pays
    /// it in USDC (a deposit takes dollars; your private balance holds USDC
    /// and ETH). Ethereum only. Nil for an address.
    var tag: String?
    /// **WHERE A SEND ARRIVES (prd §1879, §1880):** Ethereum, or ETH or USDC
    /// to Base or Robinhood through a fresh sender and Across (`PrivateSendAway`).
    var destination: Int = 1
    /// A send of ETH to Base or Robinhood.
    var away: Bool { mode == .send && onEthereum && destination != PrivacyNetwork.ethereum.chainId }
    /// Whether a send may go to Base or Robinhood now: ETH to an address.
    var canGoAway: Bool { mode == .send && onEthereum && (symbol == "ETH" || symbol == "USDC") && tag == nil }
    /// Switch on: the relayer's terms for ETH (`PrivateMoney.relayerTerms`).
    private(set) var terms: PrivateMoney.RelayerTerms?

    /// Where this move happens: Ethereum, or in a DEBUG build Sepolia
    /// (`PrivacyNetwork.current`).
    let network: PrivacyNetwork

    init(mode: Mode = .deposit, recipient: String? = nil) {
        self.mode = mode
        self.recipient = recipient
        self.network = PrivacyNetwork.current(debugAsks: Self.debugNetwork) ?? .ethereum
    }

    /// `-privateNetwork ethereum` (DEBUG): Ethereum in place of Sepolia.
    nonisolated static var debugNetwork: String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "privateNetwork")
        #else
        nil
        #endif
    }

    var onEthereum: Bool { network.chainId == PrivacyNetwork.ethereum.chainId }

    /// On Ethereum: the relayer's quoted fee for a send, base units of ETH
    /// (its fee is gas, quoted in shares at today's price, prd §1563), and
    /// the pool's smallest deposit.
    private(set) var quotedFee: String?
    /// The relayer was reached directly for this quote, Tor refused
    /// (`TorFallback`): the foot says "not through Tor".
    private(set) var relayerDirect = false
    private(set) var minimum: String?
    /// USDC on Ethereum (prd §1567): what your account holds, the pool's
    /// smallest deposit in USDC (read live), and the relayer's fee on a send.
    private(set) var usdcBalance: String?
    private(set) var usdcMinimum: String?
    private(set) var usdcFee: String?
    /// The token the amount is in: "ETH", or on Ethereum "USDC" (prd §1567).
    var symbol = "ETH"
    /// Switch on: the recipient has a private account of their own, so the
    /// send goes balance to balance (prd §1567); nil while it is asked.
    private(set) var balanceToBalance: Bool?
    /// The sender's Sepolia ETH and the gas a first move keeps back, base units.
    private(set) var balance: String?
    private(set) var reserve: String?
    private(set) var sender: String?
    var amount = ""

    /// Whether this build can move to private at all: Ethereum unless the
    /// kill switch is off; Sepolia in a DEBUG build.
    static var available: Bool { PrivacyNetwork.current(debugAsks: debugNetwork) != nil }

    /// Receive to a fresh address (prd §1560, §1567): wherever private money
    /// is — Ethereum in every build (the fresh key signs its own deposit
    /// through `FreshSigner`, which can make nothing but a router's deposit
    /// or its approval), Sepolia in a DEBUG one. On Ethereum the note's
    /// owner is your account, so there must be one on the phone.
    static var freshAvailable: Bool {
        guard let network = PrivacyNetwork.current(debugAsks: debugNetwork) else { return false }
        return network.isTest || PrivateOnEthereum.owner != nil
    }

    /// What the sender holds, as a number ("0.0412").
    var held: String? { balance.flatMap { PrivateMoney.number($0, decimals: 18) } }

    /// The amount's token decimals: 18 for ETH, 6 for USDC.
    var decimals: Int { symbol == "USDC" ? 6 : 18 }

    /// The token the engine is asked for: ETH's sentinel, or USDC's contract.
    var tokenId: String {
        symbol == "USDC" ? (network.yield.first { !$0.native }?.underlying ?? Self.eth) : Self.eth
    }

    /// USDC's amounts on Ethereum (prd §1567): into your private balance,
    /// what your account holds in USDC from the pool's smallest deposit up
    /// (its gas is ETH, held back from ETH's); from it, what is approved
    /// after the relayer's fee.
    var usdcChoices: [String] {
        guard onEthereum else { return [] }
        switch mode {
        case .deposit:
            guard let usdcBalance, let usdcMinimum, let balance, let reserve,
                  (Decimal(string: balance) ?? 0) >= (Decimal(string: reserve) ?? 1) else { return [] }
            return PrivateMoney.choices(balance: usdcBalance, reserve: "0", decimals: 6, ladder: usdcLadder, minimum: usdcMinimum)
        case .send:
            guard let usdcFee else { return [] }
            return PrivateMoney.choices(balance: PrivateMoneyStore.shared.largestNote(chainId: network.chainId, symbol: "USDC"),
                                        reserve: usdcFee, decimals: 6, ladder: PrivateMoney.usdcLadder)
        }
    }

    /// Moving in, nothing offered: the least ETH step the pool takes, and
    /// the ETH kept for the network fee (`PrivateMoney.leastMoveIn`), the
    /// same figures `choices` holds the balance to.
    var leastETH: String? {
        guard mode == .deposit else { return nil }
        return PrivateMoney.leastMoveIn(ladder: onEthereum ? PrivateMoney.mainnetLadder : PrivateMoney.ladder,
                                        decimals: 18, minimum: onEthereum ? (minimum ?? "0") : "0")?.step
    }

    /// The least USDC step ppUSDC takes, on Ethereum, once its minimum is read.
    var leastUSDC: String? {
        guard onEthereum, mode == .deposit, let usdcMinimum else { return nil }
        return PrivateMoney.leastMoveIn(ladder: usdcLadder, decimals: 6, minimum: usdcMinimum)?.step
    }

    /// **USDC UNDER THE POOL'S MINIMUM SAYS SO (prd §1938).** Moving in on
    /// Ethereum, an account holding some USDC but less than ppUSDC takes
    /// was offered ETH alone, with no word why ("i have 6 dollars … only
    /// shows me ethereum"). Nil when USDC is offered or none is held.
    var usdcShort: String? {
        guard onEthereum, mode == .deposit, usdcChoices.isEmpty, let least = leastUSDC,
              let usdcBalance, (Decimal(string: usdcBalance) ?? 0) > 0 else { return nil }
        let have = PrivateMoney.figure(usdcBalance, decimals: 6, symbol: "USDC")
        // The pool's round number (10 shares), never its cents (user: "don't
        // say 10.08 just say 10"); the amounts still start at the cent.
        var whole = Decimal(string: least) ?? 0, floor = Decimal()
        NSDecimalRound(&floor, &whole, 0, .down)
        return String(localized: "Privacy Pools takes \(NSDecimalNumber(decimal: floor).stringValue) USDC or more. You have \(have).")
    }

    /// USDC's steps moving in: from ppUSDC's minimum, to the cent (prd §1694).
    private var usdcLadder: [String] {
        PrivateMoney.ladder(PrivateMoney.usdcLadder, from: usdcMinimum ?? "0", decimals: 6, places: 2)
    }

    /// The ETH kept back for the network fee, rounded up.
    var feeKept: String? { reserve.flatMap { PrivateMoney.numberUp($0, decimals: 18) } }

    /// Every amount the sentence offers, ETH's then USDC's. To a tag, USDC
    /// alone, and only what zk.money takes: over its fee, under its cap.
    var options: [(symbol: String, amount: String)] {
        if tag != nil {
            return usdcChoices.filter { Self.tagTakes($0) }.map { ("USDC", $0) }
        }
        return choices.map { ("ETH", $0) } + usdcChoices.map { ("USDC", $0) }
    }

    /// Whether a deposit takes this many USDC (`ZkMoneyWire.payRefusal`).
    static func tagTakes(_ usdc: String) -> Bool {
        ZkMoneyWire.payRefusal(chainId: 1, token: ZkMoneyWire.usdc, usd: Double(usdc)) == nil
    }

    /// Pays `tag` (or an address, `tag` nil): to a tag, the amount moves to
    /// USDC's if it was ETH's (prd §1874).
    func pay(tag newTag: String?, address: String? = nil) {
        tag = newTag
        recipient = newTag == nil ? address : nil
        if newTag != nil { destination = PrivacyNetwork.ethereum.chainId }
        if newTag != nil, !options.contains(where: { $0.symbol == symbol && $0.amount == amount }), let first = options.first {
            pick(first.amount, of: first.symbol)
        }
    }

    /// **ANY AMOUNT, NOT ONLY THE STEPS (2026-11-25, user: "this private
    /// send doesn't let me choose custom amount or in usd. we can't have
    /// that!").** The most this token can move, base units: sending, the
    /// approved balance less the relayer's fee; moving in, what the account
    /// holds less the gas kept. Nil until read.
    var most: String? {
        let units: Decimal?
        switch mode {
        case .send:
            // **MAX IS EVERY NOTE (2026-11-27, user: "max should be all
            // notes"):** one send per note, as the relayer takes them, each
            // less its own fee (`maxParts`).
            guard let fee = fee.flatMap({ Decimal(string: $0) }) else { return nil }
            units = maxParts.reduce(Decimal(0)) { $0 + $1 - fee }
        case .deposit:
            if symbol == "USDC" { units = usdcBalance.flatMap { Decimal(string: $0) } }
            else { units = balance.flatMap { b in reserve.map { (Decimal(string: b) ?? 0) - (Decimal(string: $0) ?? 0) } } }
        }
        guard let units, units > 0 else { return units == nil ? nil : "0" }
        return PrivateMoney.plain(units)
    }

    /// **ONE NOTE PER SEND (2026-11-27).** 0xBow's relayer prices a
    /// withdrawal at one note's gas and refuses two (`largestNote`), so your
    /// private ETH, held in a note per deposit and per send's change, goes
    /// one note per send. The notes Max sends: each worth more than its fee.
    var maxParts: [Decimal] {
        guard mode == .send, onEthereum, let fee = fee.flatMap({ Decimal(string: $0) }) else { return [] }
        return PrivateMoneyStore.shared.noteWorths(chainId: network.chainId, symbol: symbol).filter { $0 > fee }
    }

    /// The most one send moves: the largest note less its fee.
    var oneSend: Decimal? {
        guard mode == .send, let fee = fee.flatMap({ Decimal(string: $0) }) else { return nil }
        return (Decimal(string: PrivateMoneyStore.shared.largestNote(chainId: network.chainId, symbol: symbol)) ?? 0) - fee
    }

    /// The sends the typed amount takes: Max's notes, else one.
    var sends: Int {
        guard let units = PrivateMoney.baseUnits(amount, decimals: decimals), isMax(units) else { return 1 }
        return max(maxParts.count, 1)
    }

    /// Which send of how many is going, while Max sends its notes.
    private(set) var part: (Int, Int)?

    /// The least this token may move: the pool's smallest deposit moving
    /// in, else anything over nothing. Base units.
    var least: String {
        guard mode == .deposit, onEthereum else { return "1" }
        return (symbol == "USDC" ? usdcMinimum : minimum) ?? "1"
    }

    /// **AN EARLIER SEND TO THE SAME PLACE IS FINISHED, NOT SENT AGAIN (prd
    /// §1988).** To Base or Robinhood, a send whose withdrawal went out and
    /// whose deposit did not: the next send there goes from what already
    /// left, so the sentence names that, never a new amount.
    var finishing: PrivateSendAway.Pending? {
        guard away, tag == nil, let to = recipient, PrivateMoney.isAddress(to) else { return nil }
        return PrivateSendAway.earlier(to: destination, payee: to)
    }

    /// The earlier send's token and amount become the sentence's, so what
    /// it says is what goes (an earlier send kept before its amount was
    /// keeps the sentence's, and `runEthereum` records what went).
    func adoptFinishing() {
        guard let p = finishing else { return }
        symbol = p.symbol ?? "ETH"
        if let units = p.amount, let shown = Self.plain(units, decimals: decimals) { amount = shown }
    }

    /// **A DOLLAR SEND AWAY PAYS ITS GAS IN PRIVATE ETH (prd §1988).** About
    /// what `PrivateSendAway.sendDollar` takes from your private ETH, base
    /// units: the gas, half again, plus its own withdrawal's relayer fee.
    /// Nil until read (`readAwayGas`), or where it is not that send.
    private(set) var awayGas: String?

    func readAwayGas() async {
        guard away, symbol == "USDC", !DemoMode.isActive, let quotedFee, let fee = Decimal(string: quotedFee),
              let home = PrivacyNetwork.forChain(FreshTx.homeChain), let fees = try? await PrivateRPC.fees(home) else {
            awayGas = nil
            return
        }
        awayGas = PrivateMoney.plain(PrivateSendAway.dollarGas(maxFee: fees.maxFee) + fee)
    }

    /// Base units as a typed figure ("0.0123"), every place kept.
    static func plain(_ units: String, decimals: Int) -> String? {
        guard var whole = Decimal(string: units) else { return nil }
        for _ in 0..<decimals { whole /= 10 }
        return NSDecimalNumber(decimal: whole).stringValue
    }

    /// A figure someone typed stands through a read (2026-11-26, user: "i
    /// can't enter .03 it jumps to .002": Try again swapped it for a step).
    private func typed(_ figure: String) -> Bool {
        (Decimal(string: figure) ?? 0) > 0
    }

    /// Whether `units` (base units) is the most this token can move: Max, or
    /// within a hair of it.
    func isMax(_ units: String) -> Bool {
        guard let top = most.flatMap({ Decimal(string: $0) }), let u = Decimal(string: units) else { return false }
        // Max is drawn rounded down to the keys' places (six for ETH, two
        // for a dollar): within one of those of the top is Max (2026-11-27,
        // on the phone: Max picked, "won't let me send").
        var hair = Decimal(1)
        for _ in 0..<max(decimals - (symbol == "USDC" ? 2 : 6), 0) { hair *= 10 }
        return u >= top - hair
    }

    /// A typed amount the move can take.
    var amountFits: Bool {
        // Finishing, nothing more leaves your private balance (prd §1988).
        if finishing != nil { return true }
        guard let units = PrivateMoney.baseUnits(amount, decimals: decimals).flatMap({ Decimal(string: $0) }), units > 0,
              let top = most.flatMap({ Decimal(string: $0) }) else { return false }
        // Over one note, only Max: it alone sends a note per send.
        if mode == .send, onEthereum, let one = oneSend, units > one, !isMax(PrivateMoney.plain(units)) { return false }
        return units <= top && units >= (Decimal(string: least) ?? 1)
    }

    /// Picks `step` of `token` (the glass box's row).
    func pick(_ step: String, of token: String) {
        symbol = token
        amount = step
        if token != "ETH" && token != "USDC" { destination = PrivacyNetwork.ethereum.chainId }
    }

    /// Switch on, a new recipient: asks the keystore whether they hold a
    /// private account (prd §1567), so the line can say where it goes.
    func checkRecipient() async {
        // A deposit address is nobody's private account: paid out, always.
        if tag != nil { balanceToBalance = false; return }
        guard let to = recipient, PrivateMoney.isAddress(to), !DemoMode.isActive else { balanceToBalance = nil; return }
        // **TO YOURSELF IS ALWAYS PAID OUT (user, 2026-11-26: "i just sent
        // from privacy pools to my safe and it says arrives in private
        // balance").** Your own account HAS a private account, so a transfer
        // moved your ETH from your private balance into your private balance,
        // a fee for nothing. Your public account or your co-signer is paid out.
        if Self.isYours(to) { balanceToBalance = false; return }
        balanceToBalance = nil
        let has = await PrivateOnEthereum.hasPrivateAccount(to, on: network)
        guard recipient == to else { return }
        balanceToBalance = has
        NSLog("privateMove| recipient | %@ | %@", YourAccount.short(to),
              has.map { $0 ? "has a private account" : "no private account" } ?? "not answered")
    }

    /// Your public account, its private owner or your co-signer.
    static func isYours(_ address: String) -> Bool {
        let a = address.lowercased()
        return [YourAccountKey.address, PrivateOnEthereum.owner].compactMap { $0?.lowercased() }.contains(a)
            || YourAccountFacts.coSigners.contains { $0.lowercased() == a }
    }

    var choices: [String] {
        switch mode {
        case .deposit:
            guard let balance, let reserve else { return [] }
            if onEthereum {
                return PrivateMoney.choices(balance: balance, reserve: reserve, ladder: PrivateMoney.mainnetLadder, minimum: minimum ?? "0")
            }
            return PrivateMoney.choices(balance: balance, reserve: reserve)
        case .send:
            // The largest approved note, less the relayer's fee on all of it
            // (the fee is paid from the note, beside the amount): one note per
            // send, as the relayer prices it (`largestNote`).
            let held = PrivateMoneyStore.shared.largestNote(chainId: network.chainId, symbol: "ETH")
            if onEthereum {
                guard let quotedFee else { return [] }
                return PrivateMoney.choices(balance: held, reserve: quotedFee, ladder: PrivateMoney.mainnetLadder)
            }
            return PrivateMoney.choices(balance: held,
                                        reserve: PrivateMoney.relayFee(held, terms: terms ?? PrivateMoney.measuredTerms))
        }
    }

    /// The relayer's fee on this amount, base units, once its terms are read.
    var fee: String? {
        if onEthereum { return symbol == "USDC" ? usdcFee : quotedFee }
        guard let terms, let value = PrivateMoney.baseUnits(amount, decimals: 18) else { return nil }
        return PrivateMoney.relayFee(value, terms: terms)
    }

    var busy: Bool {
        switch stage {
        case .opening, .preparing, .registering, .proving, .sending, .reading: true
        default: false
        }
    }

    /// Past the tap: Move's verbs wait for it to finish.
    var acting: Bool { busy && stage != .reading }

    /// Which read is the latest: a read the switch overtook (the mode
    /// changed and a new read began) leaves the stage to the one after it.
    @ObservationIgnored private var reads = 0

    func read() async {
        reads += 1
        let mine = reads
        if onEthereum { await readEthereum(mine); return }
        #if DEBUG
        if mode == .send { await readSend(mine); return }
        // The demo reaches nothing (§217): its sentence stands on a pretended
        // balance, and the act says it works once you leave the demo.
        if DemoMode.isActive {
            balance = "50000000000000000"
            reserve = "0"
            stage = .ready
            return
        }
        stage = .reading
        do {
            sender = try PrivacyTestnetSender.ensure()
            var have = try await PrivacyTestnetSender.balance()
            // `-movePrivateBalance <wei>`: the sentence as if the sender held
            // that much, so it can be seen with no funds; `run` refuses.
            if let pretend = Self.pretend { have = pretend }
            let price = try await PrivacyTestnetSender.gasPrice()
            guard mine == reads else { return }
            balance = have
            reserve = PrivateMoney.reserve(gasPrice: price)
            let options = choices
            if options.isEmpty {
                stage = .needsFunds(sender ?? "")
            } else {
                if !typed(amount), !options.contains(amount) { amount = options[min(2, options.count - 1)] }
                stage = .ready
            }
            NSLog("privateMove| read | sender %@ | balance %@ | reserve %@ | %d choices",
                  sender ?? "-", have, reserve ?? "-", options.count)
        } catch {
            guard mine == reads else { return }
            stage = .failed(Self.words(error))
        }
        #else
        stage = .failed(String(localized: "Not in this build"))
        #endif
    }

    #if DEBUG
    static var pretend: String? {
        UserDefaults.standard.string(forKey: "movePrivateBalance").flatMap { $0.allSatisfy(\.isNumber) && !$0.isEmpty ? $0 : nil }
    }
    #endif

    /// Switch on: what is spendable, and the relayer's terms.
    private func readSend(_ mine: Int) async {
        stage = .reading
        let options = choices
        guard !options.isEmpty else { stage = .nothingPrivate; return }
        if !typed(amount), !options.contains(amount) { amount = options[min(2, options.count - 1)] }
        if !DemoMode.isActive, terms == nil,
           let url = URL(string: PrivacyNetwork.sepolia.relayerUrl + "/v1/details/evm/\(PrivacyNetwork.sepolia.chainId)"),
           let (data, http) = await IngestSupport.sendRequest(URLRequest(url: url), service: PrivacyEngine.service),
           http.statusCode == 200 {
            terms = PrivateMoney.relayerTerms(data)
        }
        guard mine == reads else { return }
        stage = .ready
        NSLog("privateMove| send read | %d choices | fee %@ bps", options.count, terms.map { String($0.feeBPS) } ?? "-")
    }

    /// On Ethereum (prd §1563): into your private balance, what your
    /// account holds after the gas a first move keeps back, in the pool's
    /// smallest deposit or more; from it, what is approved after the
    /// relayer's quoted fee.
    private func readEthereum(_ mine: Int) async {
        if DemoMode.isActive {
            balance = "50000000000000000"
            reserve = "0"
            minimum = "4000000000000000"
            quotedFee = "60000000000000"
            // The relayer's fee measured 2026-11-18 (0.0006 ETH at 0.56 gwei,
            // about $1.40), so the demo never shows a fee nobody pays.
            usdcFee = "1400000"
            // A tag is paid in USDC (prd §1874), on the demo too.
            if mode == .send, tag != nil {
                guard let first = options.first else {
                    stage = .failed(String(localized: "A zk.money tag is paid in USDC, and Privacy Pools has none to send"))
                    return
                }
                if !options.contains(where: { $0.symbol == symbol && $0.amount == amount }) { pick(first.amount, of: first.symbol) }
                stage = .ready
                return
            }
            stage = choices.isEmpty ? (mode == .send ? .nothingPrivate : .ready) : .ready
            return
        }
        stage = .reading
        guard let account = PrivateOnEthereum.owner else {
            stage = .failed(String(localized: "Set up your account first"))
            return
        }
        sender = account
        let net = PrivateOnEthereum.accountNetwork
        let pool = network.yieldPool(for: Self.eth)
        if mode == .send {
            // The rates, ETH's quote and USDC's, at once (2026-11-27: one after
            // another over Tor, "reading Ethereum" took most of a minute).
            let asked = Date()
            let to = recipient ?? account
            let usdcPool = PrivateMoneyStore.shared.spendable(chainId: network.chainId, symbol: "USDC") != "0"
                ? network.yield.first(where: { !$0.native }) : nil
            let net = network
            async let rates: Void = PrivateMoneyStore.shared.readYield()
            async let ethQuote: Quote = pool != nil ? Self.relayerQuote(pool!, network: net, to: to) : .noPool
            async let usdcQuote: String? = usdcPool != nil ? Self.relayerFee(usdcPool!, network: net, to: to) : nil
            let (quote, usdcAnswer, _) = await (ethQuote, usdcQuote, rates)
            relayerDirect = URL(string: network.relayerUrl)?.host().map { TorFallback.shared.happened($0, since: asked) } ?? false
            if case .fee(let fee) = quote { quotedFee = fee } else { quotedFee = nil }
            if usdcPool != nil { usdcFee = usdcAnswer }
            guard mine == reads else { return }
            let options = self.options
            // A tag is paid in private USDC alone (prd §1874).
            if tag != nil, options.isEmpty {
                stage = .failed(String(localized: "A zk.money tag is paid in USDC, and Privacy Pools has none to send"))
                return
            }
            // Nothing private yet is said as that, never as the relayer's
            // silence (user, with nothing deposited: "0xBow's relayer did not
            // answer"): the quote only matters for what there is to send.
            guard !options.isEmpty else {
                let store = PrivateMoneyStore.shared
                let nothing = store.spendable(chainId: network.chainId) == "0" && store.spendable(chainId: network.chainId, symbol: "USDC") == "0"
                stage = nothing ? .nothingPrivate : (quote.failure(on: network).map(Stage.failed) ?? .nothingPrivate)
                return
            }
            if !options.contains(where: { $0.symbol == symbol && $0.amount == amount }) {
                let first = options[min(2, options.count - 1)]
                pick(first.amount, of: first.symbol)
            }
            stage = .ready
            NSLog("privateMove| ethereum send read | %d choices | fee %@ wei", options.count, quotedFee ?? "-")
            return
        }
        async let rates: Void = PrivateMoneyStore.shared.readYield(including: network)
        async let held = YourAccountChain.balance(net, YourAccountOp.eth, of: account)
        async let price = try? YourAccountChain.rpc(net, "eth_gasPrice", []) as? String
        async let terms = pool != nil ? PrivateOnEthereum.terms(pool!) : nil
        let usdcPool = network.yield.first { !$0.native }
        async let usdcHeld = YourAccountChain.balance(net, YourAccountOp.dollar(on: net), of: account)
        async let usdcFloor = usdcPool != nil ? Self.minimumBudget(usdcPool!) : nil
        let (have, gas, config, _, dollars, floor) = await (held, price, terms, rates, usdcHeld, usdcFloor)
        guard mine == reads else { return }
        guard let have, let gas, let config, config.enabled else {
            stage = .failed(String(localized: "Ethereum could not be reached"))
            return
        }
        balance = have
        reserve = PrivateMoney.reserve(gasPrice: PrivateMoney.decimal(hex: gas))
        minimum = config.minimum
        usdcBalance = dollars
        usdcMinimum = floor
        let options = self.options
        if options.isEmpty {
            stage = .needsFunds(account)
        } else {
            if !options.contains(where: { $0.symbol == symbol && $0.amount == amount }) { pick(options[0].amount, of: options[0].symbol) }
            stage = .ready
        }
        NSLog("privateMove| ethereum read | %@ | balance %@ | reserve %@ | minimum %@ | %d choices",
              YourAccount.short(account), have, reserve ?? "-", config.minimum, options.count)
    }

    /// A yield pool's smallest deposit in its token, read live (prd §1567).
    static func minimumBudget(_ pool: PrivacyNetwork.YieldPool) async -> String? {
        guard let config = await PrivateOnEthereum.terms(pool), config.enabled,
              let answer = await PrivateOnEthereum.ethCall(to: pool.share, data: PrivateYield.exchangeRateCall),
              let rate = PrivateYield.word(answer, 0), rate != "0" else { return nil }
        return FreshAddress.minimumBudget(minimumShares: config.minimum, exchangeRate: rate, shareDecimals: pool.shareDecimals)
    }

    /// The relayer's fee for a withdrawal from `pool`, in ETH base units:
    /// its own quote (uncommitted: nothing is signed), in shares, at the
    /// share's rate. The fee is the relayer's gas at today's price, so one
    /// quote serves every amount.
    static func relayerFee(_ pool: PrivacyNetwork.YieldPool, network: PrivacyNetwork, to recipient: String) async -> String? {
        if case .fee(let fee) = await relayerQuote(pool, network: network, to: recipient) { return fee }
        return nil
    }

    /// What the relayer said to a quote: its fee, a refusal (another status,
    /// or an answer with no fee in it), or nothing at all.
    enum Quote: Equatable {
        case fee(String)
        case refused
        case unanswered
        /// No yield pool for ETH on this network: the relayer was not asked.
        case noPool

        /// The sentence's words for a quote that is not a fee.
        func failure(on network: PrivacyNetwork) -> String? {
            switch self {
            case .fee: nil
            case .refused: String(localized: "0xBow's relayer refused to quote")
            case .unanswered: String(localized: "0xBow's relayer did not answer")
            case .noPool: String(localized: "Private ETH is not served on \(network.name)")
            }
        }
    }

    /// The quote, through Tor. The relayer's front end answers some Tor
    /// exits with nothing (prd §1554), so no answer gets two more circuits
    /// before it is an outage, as the engine's own relayer requests do.
    static func relayerQuote(_ pool: PrivacyNetwork.YieldPool, network: PrivacyNetwork, to recipient: String) async -> Quote {
        guard let url = URL(string: network.relayerUrl + "/v1/quote/evm/\(network.chainId)/receive") else { return .unanswered }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["asset": pool.share, "commit": false, "recipient": recipient, "extraGas": false,
                                   "amount": "0x2386f26fc10000"]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        var answer: (Data, HTTPURLResponse)?
        for _ in 0..<3 where answer == nil {
            answer = await IngestSupport.sendRequest(request, service: PrivacyEngine.service)
        }
        guard let (data, http) = answer else { return .unanswered }
        // The relayer answers a quote 201 Created (measured 2026-11-18;
        // every quote read "refused" while this asked for 200).
        guard (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let shares = json["feeAmount"] as? String, shares.allSatisfy(\.isNumber), !shares.isEmpty else { return .refused }
        guard let rate = PrivateMoneyStore.shared.rates[pool.share.lowercased()] else { return .fee(shares) }
        return PrivateYield.underlying(shares: shares, exchangeRate: rate, shareDecimals: pool.shareDecimals).map(Quote.fee) ?? .unanswered
    }

    /// The act: a deposit, or switch on a relayed withdrawal.
    func run() async {
        // zk.money's deposit addresses are Ethereum's (prd §1874).
        if tag != nil, !onEthereum {
            stage = .failed(String(localized: "zk.money takes DAI, USDC or USDT on Ethereum"))
            return
        }
        // Where a private send goes is known before anything is proved
        // (prd §1567): asked again if the node had not answered, and never
        // paid out publicly on a guess.
        if mode == .send, !DemoMode.isActive, balanceToBalance == nil {
            await checkRecipient()
            guard balanceToBalance != nil else {
                stage = .failed(network.isTest ? String(localized: "Sepolia could not be reached") : String(localized: "Ethereum could not be reached"))
                return
            }
        }
        if onEthereum { await runEthereum(); return }
        // Sepolia's flows hold the engine from the open to the send (finding 8).
        if mode == .send { await PrivacyEngine.exclusive { await runSend() }; return }
        await PrivacyEngine.exclusive { await runDeposit() }
    }

    /// On Ethereum: your account's Face ID operation into the yield pool, or
    /// a relayed send from your private balance (prd §1563).
    private func runEthereum() async {
        if DemoMode.isActive {
            stage = .failed(YourAccountDemo.actsLater)
            return
        }
        // Finishing an earlier send kept before its amount was (prd §1988):
        // nothing is typed and nothing new leaves, so no figure is needed.
        guard let value = PrivateMoney.baseUnits(amount, decimals: decimals) ?? (mode == .send && away && finishing != nil ? "0" : nil)
        else { return }
        let token = tokenId
        let started = Date()
        deposited = nil
        do {
            if mode == .send {
                let to: String
                if let tag {
                    // Asked now, fresh (prd §1692, §1874): a deposit address
                    // is single-use, and only USDC goes to one from here.
                    guard symbol == "USDC", Self.tagTakes(amount) else {
                        stage = .failed(ZkMoneyWire.payRefusal(chainId: 1, token: symbol == "USDC" ? ZkMoneyWire.usdc : nil,
                                                               usd: Double(amount)) ?? String(localized: "zk.money takes DAI, USDC or USDT on Ethereum"))
                        return
                    }
                    stage = .preparing
                    guard case .address(let deposit) = await ZkMoney.depositAddress(tag: tag) else {
                        stage = .failed(String(localized: "zk.money's resolver didn't answer. Try again in a minute."))
                        return
                    }
                    to = deposit
                    NSLog("privateMove| tag | %@ | deposit %@", tag, YourAccount.short(deposit))
                } else {
                    guard let r = recipient, PrivateMoney.isAddress(r) else { return }
                    to = r
                }
                if away {
                    adoptFinishing()
                    stage = .opening
                    let sent = try await PrivateSendAway.send(amount: value, symbol: symbol, to: destination, payee: to) { [weak self] _ in
                        self?.stage = .sending
                    }
                    // **WHAT WENT IS WHAT ACTIVITY SAYS (prd §1988):** an
                    // earlier send finished sends its own amount, not the typed one.
                    symbol = sent.symbol
                    if let shown = Self.plain(sent.amount, decimals: decimals) { amount = shown }
                    stage = .done(sent.hash)
                    return
                }
                // Waiting on the engine (a background read may hold it) says so.
                stage = .preparing
                let maxing = tag == nil && balanceToBalance != true && isMax(value)
                let parts = maxing ? max(maxParts.count, 1) : 1
                part = nil
                defer { part = nil }
                let hash = try await PrivateOnEthereum.send(token: token, amount: value, to: to,
                                                            balanceToBalance: tag == nil && balanceToBalance == true,
                                                            announce: true,
                                                            // Max sends what the notes hold, fee quoted now (2026-11-26).
                                                            upTo: maxing,
                                                            parts: parts,
                                                            step: { [weak self] s in
                    await MainActor.run {
                        switch s {
                        case .opening: self?.stage = .opening
                        case .preparing: self?.stage = .preparing
                        case .proving: self?.stage = .proving
                        case .sending: self?.stage = .sending
                        case .part(let k, let n): self?.part = (k, n)
                        }
                    }
                })
                stage = .done(hash)
            } else {
                stage = .preparing
                let made = try await PrivateOnEthereum.deposit(token: token, budget: value, context: nil, stage: { [weak self] s in
                    await MainActor.run {
                        switch s {
                        case .preparing: self?.stage = .preparing
                        case .signing, .cosigning: self?.stage = .opening
                        case .sending, .landing: self?.stage = .sending
                        }
                    }
                }, proving: { [weak self] in self?.stage = .proving })
                // Kept whether or not Ethereum named its transaction (finding 2):
                // the sentence follows the note by its commitment. **NO HASH,
                // NO ACTIVITY ROW (prd §1988):** `.done("")` lands nothing
                // (`MovePrivateSentence.land`), so no row is keyed on "".
                deposited = made.commitment
                stage = .done(made.tx ?? "")
                await PrivateMoneyStore.shared.refresh(force: true)
            }
            NSLog("privateMove| ethereum | %@ | %@ %@ | %d s", mode == .send ? (balanceToBalance == true ? "balance to balance" : "sent") : "deposited",
                  amount, symbol, Int(Date().timeIntervalSince(started)))
        } catch {
            stage = .failed(Self.words(error, network: network))
            NSLog("privateMove| ethereum failed | %@", String(describing: error))
        }
    }

    private func runSend() async {
        #if DEBUG
        if DemoMode.isActive {
            stage = .failed(YourAccountDemo.actsLater)
            return
        }
        guard let to = recipient, PrivateMoney.isAddress(to),
              let value = PrivateMoney.baseUnits(amount, decimals: 18), let hex = PrivateMoney.hex(value) else { return }
        let engine = PrivacyEngine.shared
        let started = Date()
        do {
            // One withdrawal spends from one account (prd §1562): the
            // current root's when it covers the amount and its fee, else the
            // one that does.
            let fee = PrivateMoney.relayFee(value, terms: terms ?? PrivateMoney.measuredTerms)
            guard let account = PrivateMoneyStore.shared.account(toSpend: value, fee: fee, chainId: PrivacyNetwork.sepolia.chainId) else {
                stage = .failed(String(localized: "Your approved private balance does not cover it"))
                return
            }
            stage = .opening
            try await PrivateAccount.open(account, reason: String(localized: "Send from Privacy Pools"))
            stage = .preparing
            // The notes as the pool holds them: what is spendable is theirs.
            let found = try await engine.discover()
            PrivateMoneyStore.shared.reconcile(found, root: account == PrivateRoot.legacy ? nil : account)
            stage = .proving
            // Balance to balance when they hold a private account (prd §1567),
            // else paid out to the address.
            let spend = balanceToBalance == true ? try await engine.prepareTransfer(tokenId: PrivateMove.eth, amount: hex, to: to)
                : try await engine.prepareWithdraw(tokenId: PrivateMove.eth, amount: hex, to: to)
            NSLog("privateMove| proved %@ | %d ms", balanceToBalance == true ? "transfer" : "withdraw", spend.ms)
            stage = .sending
            let relayed = try await engine.relay(handle: spend.handle)
            stage = .done(relayed.tx)
            NSLog("privateMove| relayed | %@ | %@ | %@ ETH | %d s", balanceToBalance == true ? "balance to balance" : "paid out",
                  relayed.tx, amount, Int(Date().timeIntervalSince(started)))
            if let after = try? await engine.discover() {
                PrivateMoneyStore.shared.reconcile(after, root: account == PrivateRoot.legacy ? nil : account)
            }
        } catch {
            stage = .failed(Self.words(error))
            NSLog("privateMove| failed | %@", String(describing: error))
        }
        #endif
    }

    private func runDeposit() async {
        #if DEBUG
        if DemoMode.isActive {
            stage = .failed(YourAccountDemo.actsLater)
            return
        }
        if Self.pretend != nil {
            stage = .failed(String(localized: "Not enough Sepolia ETH"))
            NSLog("privateMove| refused | -movePrivateBalance is a pretended balance")
            return
        }
        guard let value = PrivateMoney.baseUnits(amount, decimals: 18), let hex = PrivateMoney.hex(value) else { return }
        let engine = PrivacyEngine.shared
        let started = Date()
        do {
            // New money goes to the current root's account (prd §1562), the
            // one a new phone gets back; the root is made the first time.
            let account = try PrivateRootKey.ensure()
            stage = .opening
            // Opened every time: a page a probe or another account opened
            // may name another owner.
            try await PrivateAccount.open(account, reason: String(localized: "Move to private"))
            stage = .preparing
            try await PrivateAccount.registerIfNeeded(account) { [weak self] i in self?.stage = .registering(i) }
            stage = .proving
            let deposit = try await engine.prepareDeposit(tokenId: PrivateMove.eth, value: hex)
            NSLog("privateMove| proved | %@ | %d ms", deposit.proofs.map { "\($0.circuit ?? "?") \($0.ms) ms" }.joined(separator: ", "), deposit.ms)
            stage = .sending
            for approval in deposit.approvals { _ = try await PrivacyTestnetSender.send(approval) }
            let hash = try await PrivacyTestnetSender.send(deposit.tx)
            PrivateMoneyStore.shared.add(.init(commitment: deposit.commitment, label: deposit.label, labelHash: deposit.labelHash,
                                               symbol: "ETH", amount: value, decimals: 18, chainId: PrivacyNetwork.sepolia.chainId,
                                               tx: hash, at: Date(), status: .waiting, root: account))
            NSLog("privateMove| deposited | %@ | %@ ETH | label hash %@ | %d s",
                  hash, amount, deposit.labelHash, Int(Date().timeIntervalSince(started)))
            // Round-ups due on Sepolia ride the send you confirmed (prd §1561).
            await Self.moveRoundUps(engine: engine, context: context)
            stage = .done(hash)
            await PrivateMoneyStore.shared.refresh(force: true)
        } catch {
            stage = .failed(Self.words(error))
            NSLog("privateMove| failed | %@", String(describing: error))
        }
        #endif
    }

    static let eth = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"

    /// Where a move lands its Activity row; the sentence sets it.
    @ObservationIgnored var context: ModelContext?

    /// The note the last deposit on Ethereum kept, by its commitment: the
    /// sentence follows it whether or not a transaction was named (finding 2).
    var deposited: String?

    // MARK: - Round-ups into your private balance (prd §1561)

    /// **THE CHANGE MOVES TOGETHER.** When round-ups move privately and what
    /// is counted on Sepolia has reached `RoundUps.privateMoveAt`, a send the
    /// owner signs carries ONE more deposit: everything counted, its own note
    /// (0xBow labels each deposit, so one per send would tie each send to its
    /// change). The engine is open (the deposit's own Face ID). Done, the
    /// count starts again and Activity says "0.00012 ETH round-ups to your
    /// private balance". A failure leaves the change counting for the next.
    /// Returns the deposit's hash.
    @discardableResult
    static func moveRoundUps(engine: PrivacyEngine, context: ModelContext?) async -> String? {
        #if DEBUG
        let chain = PrivacyNetwork.sepolia.chainId
        let setting = RoundUps.setting
        guard setting.movesPrivately, RoundUps.applies(setting, on: chain),
              RoundUps.privateRoute(on: chain, bySession: false) == .deposit,
              let batch = RoundUps.privateMove(saved: RoundUps.privateSaved(on: chain), at: RoundUps.privateMoveAt),
              let hex = PrivateMoney.hex(batch) else { return nil }
        do {
            let deposit = try await engine.prepareDeposit(tokenId: eth, value: hex)
            for approval in deposit.approvals { _ = try await PrivacyTestnetSender.send(approval) }
            let hash = try await PrivacyTestnetSender.send(deposit.tx)
            RoundUps.setPrivateSaved("0", on: chain)
            PrivateMoneyStore.shared.add(.init(commitment: deposit.commitment, label: deposit.label, labelHash: deposit.labelHash,
                                               symbol: "ETH", amount: batch, decimals: 18, chainId: chain,
                                               tx: hash, at: Date(), status: .waiting, root: PrivateRootKey.currentID))
            let figure = PrivateMoney.figure(batch, decimals: 18, symbol: "ETH")
            if let context { PrivateActivity.land(hash: hash, title: PrivateMoney.roundUpsTitle(figure: figure), context: context) }
            NSLog("roundUpsPrivate| moved | %@ | %@ wei | label hash %@", hash, batch, deposit.labelHash)
            return hash
        } catch {
            NSLog("roundUpsPrivate| kept counting | %@", String(describing: error))
            return nil
        }
        #else
        return nil
        #endif
    }

    #if DEBUG
    /// `-roundUpsPrivateMove YES`: the same move with nothing else sent —
    /// the seed (Face ID), the account opened, the keystore set up if it is
    /// not, then the batch. On Sepolia nothing sends publicly (your account is
    /// not there), so this is the move's own door for a probe.
    static func moveRoundUpsNow(context: ModelContext?) async {
        await PrivacyEngine.exclusive { await moveRoundUpsAlone(context: context) }
    }

    private static func moveRoundUpsAlone(context: ModelContext?) async {
        do {
            // Into the current root's account (prd §1562).
            let account = try PrivateRootKey.ensure()
            let engine = PrivacyEngine.shared
            try await PrivateAccount.open(account, reason: String(localized: "Move to private"))
            try await PrivateAccount.registerIfNeeded(account)
            let hash = await moveRoundUps(engine: engine, context: context)
            NSLog("roundUpsPrivate| probe | %@", hash ?? "nothing moved")
        } catch {
            NSLog("roundUpsPrivate| probe failed | %@", String(describing: error))
        }
    }
    #endif

    /// What `words` says of an engine failure it has no words of its own
    /// for. A fresh address's move names its step instead (prd §1823).
    /// The reason in a relayer's refusal ("HTTP 400: Bad Request: {…}"):
    /// the body's `message`, `error` or `reason`, or nil.
    /// The relayer's quote no longer stands: it expired, or gas rose past it
    /// while the phone proved. Nothing went out; a fresh quote and proof fix it.
    static func staleFee(_ f: PrivacyEngineWire.Failure) -> Bool {
        f.name == "FeeCommitmentExpired"
            || (f.name == "RelayerRejected" && (f.message.localizedCaseInsensitiveContains("no longer covers")
                || f.message.localizedCaseInsensitiveContains("FeeCommitmentExpired")))
    }

    static func relayerReason(_ message: String) -> String? {
        guard let brace = message.firstIndex(of: "{"),
              let data = String(message[brace...]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // A body cut short is no JSON (2026-11-27: the reason drew as
            // raw braces): its message, as far as it goes.
            guard let r = message.range(of: #""message"\s*:\s*"([^"]+)"#, options: .regularExpression) else { return nil }
            let m = message[r].split(separator: "\"", maxSplits: 3, omittingEmptySubsequences: false)
            return m.count > 3 ? String(m[3].prefix(160)) : nil
        }
        func text(_ v: Any?) -> String? {
            if let s = v as? String, !s.isEmpty { return s }
            if let d = v as? [String: Any] { return text(d["message"]) ?? text(d["reason"]) }
            return nil
        }
        return (text(json["message"]) ?? text(json["error"]) ?? text(json["reason"])).map { String($0.prefix(160)) }
    }

    static var engineFallback: String { String(localized: "The private account could not be opened") }

    /// A failure in the sentence's words: short, and what to do where there is something.
    static func words(_ error: Error, network: PrivacyNetwork = .sepolia) -> String {
        if let failure = error as? YourAccountChain.Failure { return failure.message }
        if let failure = error as? PrivateSendAway.Failure {
            switch failure {
            case .notServed: return String(localized: "ETH or USDC, to an address")
            case .onItsWay: return String(localized: "On its way to a one-time address. Try again to finish it.")
            case .across(let why): return why
            case .gas: return String(localized: "Across's deposit would cost more gas than expected")
            case .earlierSend: return String(localized: "An earlier send to another network is still on its way")
            }
        }
        if let failure = error as? PrivateOnEthereum.Failure {
            return failure == .noAccount ? String(localized: "Set up your account first")
                : String(localized: "This could not be written, so nothing was signed")
        }
        if case PrivateOnEthereum.Failure.partly(let sent, let of, let why) = error {
            return String(localized: "\(sent) of \(of) sends went. The rest stays private: \(why)")
        }
        if let failure = error as? PrivacyEngineWire.Failure {
            NSLog("privateMove| engine | %@ | %@", failure.name, failure.message)
            // The engine's own name rides the words (2026-11-26: a send
            // failed on the phone as "could not be opened", and no log
            // reaches here): what to report is on the screen.
            // Refused is not silent (2026-11-26, user: "one time i get
            // rejected"): the relayer's own reason, as it gave it.
            if staleFee(failure) {
                return String(localized: "Gas rose while it was proving, past 0xBow's quote. Nothing was sent: try again.")
            }
            if failure.name == "RelayerRejected" {
                let why = relayerReason(failure.message)
                return why.map { String(localized: "0xBow's relayer refused it: \($0)") }
                    ?? String(localized: "0xBow's relayer refused it") + " (\(failure.message.prefix(160)))"
            }
            if failure.name.hasPrefix("Relayer") {
                return String(localized: "0xBow's relayer did not answer") + " (\(failure.name))"
            }
            if failure.name.localizedCaseInsensitiveContains("BelowMinimum") {
                return String(localized: "Below the pool's smallest deposit")
            }
            if failure.message.localizedCaseInsensitiveContains("does not cover")
                || failure.message.localizedCaseInsensitiveContains("insufficient") {
                return String(localized: "Your approved private balance does not cover it")
            }
            return engineFallback + " (\(failure.name))"
        }
        #if DEBUG
        if let failure = error as? PrivacyTestnetSender.Failure {
            switch failure {
            case .reverted: return String(localized: "Sepolia refused the move")
            case .timedOut: return String(localized: "Sepolia has not confirmed it yet")
            case .refused(let why):
                NSLog("privateMove| refused | %@", why)
                return why.localizedCaseInsensitiveContains("insufficient")
                    ? String(localized: "Not enough Sepolia ETH") : String(localized: "Sepolia refused the move")
            default: return String(localized: "Sepolia could not be reached")
            }
        }
        #endif
        if error is PrivacyPoolsKey.Failure || error is PrivateRootKey.Failure {
            return String(localized: "Face ID did not open the private account")
        }
        return network.isTest ? String(localized: "Sepolia could not be reached") : String(localized: "Ethereum could not be reached")
    }
}
