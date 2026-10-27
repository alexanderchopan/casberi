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
    static var debugNetwork: String? {
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
    var amount = "0.001"

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
            return PrivateMoney.choices(balance: usdcBalance, reserve: "0", decimals: 6, ladder: PrivateMoney.usdcLadder, minimum: usdcMinimum)
        case .send:
            guard let usdcFee else { return [] }
            return PrivateMoney.choices(balance: PrivateMoneyStore.shared.spendable(chainId: network.chainId, symbol: "USDC"),
                                        reserve: usdcFee, decimals: 6, ladder: PrivateMoney.usdcLadder)
        }
    }

    /// Every amount the sentence offers, ETH's then USDC's.
    var options: [(symbol: String, amount: String)] {
        choices.map { ("ETH", $0) } + usdcChoices.map { ("USDC", $0) }
    }

    /// Picks `step` of `token` (the glass box's row).
    func pick(_ step: String, of token: String) {
        symbol = token
        amount = step
    }

    /// Switch on, a new recipient: asks the keystore whether they hold a
    /// private account (prd §1567), so the line can say where it goes.
    func checkRecipient() async {
        guard let to = recipient, PrivateMoney.isAddress(to), !DemoMode.isActive else { balanceToBalance = nil; return }
        balanceToBalance = nil
        let has = await PrivateOnEthereum.hasPrivateAccount(to, on: network)
        guard recipient == to else { return }
        balanceToBalance = has
        NSLog("privateMove| recipient | %@ | %@", YourAccount.short(to),
              has.map { $0 ? "has a private account" : "no private account" } ?? "not answered")
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
            // The approved private balance, less the relayer's fee on all of
            // it (the fee is paid from the notes, beside the amount).
            let held = PrivateMoneyStore.shared.spendable(chainId: network.chainId)
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
                if !options.contains(amount) { amount = options[min(2, options.count - 1)] }
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
        if !options.contains(amount) { amount = options[min(2, options.count - 1)] }
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
            await PrivateMoneyStore.shared.readYield()
            let quote: Quote = if let pool { await Self.relayerQuote(pool, network: network, to: recipient ?? account) } else { .noPool }
            if case .fee(let fee) = quote { quotedFee = fee } else { quotedFee = nil }
            if let usdcPool = network.yield.first(where: { !$0.native }),
               PrivateMoneyStore.shared.spendable(chainId: network.chainId, symbol: "USDC") != "0" {
                usdcFee = await Self.relayerFee(usdcPool, network: network, to: recipient ?? account)
            }
            guard mine == reads else { return }
            let options = self.options
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
        guard http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let shares = json["feeAmount"] as? String, shares.allSatisfy(\.isNumber), !shares.isEmpty else { return .refused }
        guard let rate = PrivateMoneyStore.shared.rates[pool.share.lowercased()] else { return .fee(shares) }
        return PrivateYield.underlying(shares: shares, exchangeRate: rate, shareDecimals: pool.shareDecimals).map(Quote.fee) ?? .unanswered
    }

    /// The act: a deposit, or switch on a relayed withdrawal.
    func run() async {
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
        guard let value = PrivateMoney.baseUnits(amount, decimals: decimals) else { return }
        let token = tokenId
        let started = Date()
        deposited = nil
        do {
            if mode == .send {
                guard let to = recipient, PrivateMoney.isAddress(to) else { return }
                stage = .opening
                let hash = try await PrivateOnEthereum.send(token: token, amount: value, to: to, balanceToBalance: balanceToBalance == true)
                stage = .done(hash)
            } else {
                stage = .preparing
                let made = try await PrivateOnEthereum.deposit(token: token, budget: value, context: nil, stage: { [weak self] s in
                    await MainActor.run {
                        switch s {
                        case .preparing: self?.stage = .preparing
                        case .signing: self?.stage = .opening
                        case .sending, .landing: self?.stage = .sending
                        }
                    }
                }, proving: { [weak self] in self?.stage = .proving })
                // Kept whether or not Ethereum named its transaction (finding 2):
                // the sentence follows the note by its commitment.
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
            try await PrivateAccount.open(account, reason: String(localized: "Send from your private balance"))
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

    /// A failure in the sentence's words: short, and what to do where there is something.
    static func words(_ error: Error, network: PrivacyNetwork = .sepolia) -> String {
        if let failure = error as? YourAccountChain.Failure { return failure.message }
        if let failure = error as? PrivateOnEthereum.Failure {
            return failure == .noAccount ? String(localized: "Set up your account first")
                : String(localized: "This could not be written, so nothing was signed")
        }
        if let failure = error as? PrivacyEngineWire.Failure {
            NSLog("privateMove| engine | %@ | %@", failure.name, failure.message)
            if failure.name.hasPrefix("Relayer") {
                return String(localized: "0xBow's relayer did not answer")
            }
            if failure.name.localizedCaseInsensitiveContains("BelowMinimum") {
                return String(localized: "Below the pool's smallest deposit")
            }
            if failure.message.localizedCaseInsensitiveContains("does not cover")
                || failure.message.localizedCaseInsensitiveContains("insufficient") {
                return String(localized: "Your approved private balance does not cover it")
            }
            return String(localized: "The private account could not be opened")
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
