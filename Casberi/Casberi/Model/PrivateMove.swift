import Foundation
import Observation

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
/// Sepolia only; in DEBUG builds only, because the sender is the DEBUG
/// testnet sender (`PrivacyTestnetSender`) until your account sends.
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

    init(mode: Mode = .deposit, recipient: String? = nil) {
        self.mode = mode
        self.recipient = recipient
    }
    /// The sender's Sepolia ETH and the gas a first move keeps back, base units.
    private(set) var balance: String?
    private(set) var reserve: String?
    private(set) var sender: String?
    var amount = "0.001"

    /// Whether this build can move to private at all.
    static var available: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// What the sender holds, as a number ("0.0412").
    var held: String? { balance.flatMap { PrivateMoney.number($0, decimals: 18) } }

    var choices: [String] {
        switch mode {
        case .deposit:
            guard let balance, let reserve else { return [] }
            return PrivateMoney.choices(balance: balance, reserve: reserve)
        case .send:
            // The approved private balance; the relayer's fee comes out of it.
            return PrivateMoney.choices(balance: PrivateMoneyStore.shared.spendable(chainId: PrivacyNetwork.sepolia.chainId),
                                        reserve: "0")
        }
    }

    /// The relayer's fee on this amount, base units, once its terms are read.
    var fee: String? {
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

    func read() async {
        #if DEBUG
        if mode == .send { await readSend(); return }
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
    private func readSend() async {
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
        stage = .ready
        NSLog("privateMove| send read | %d choices | fee %@ bps", options.count, terms.map { String($0.feeBPS) } ?? "-")
    }

    /// The act: a deposit, or switch on a relayed withdrawal.
    func run() async {
        if mode == .send { await runSend(); return }
        await runDeposit()
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
            let owner = try PrivacyTestnetSender.ensure()
            stage = .opening
            if !PrivacyPoolsKey.exists() { try PrivacyPoolsKey.create() }
            var seed = try PrivacyPoolsKey.seed(reason: String(localized: "Send from your private balance"))
            defer { seed.resetBytes(in: 0..<seed.count) }
            stage = .preparing
            _ = try await engine.open(seed: seed, owner: owner, network: .sepolia)
            seed.resetBytes(in: 0..<seed.count)
            // The notes as the pool holds them: what is spendable is theirs.
            let found = try await engine.discover()
            PrivateMoneyStore.shared.reconcile(found)
            stage = .proving
            let spend = try await engine.prepareWithdraw(tokenId: PrivateMove.eth, amount: hex, to: to)
            NSLog("privateMove| proved withdraw | %d ms", spend.ms)
            stage = .sending
            let relayed = try await engine.relay(handle: spend.handle)
            stage = .done(relayed.tx)
            NSLog("privateMove| relayed | %@ | %@ ETH | %d s", relayed.tx, amount, Int(Date().timeIntervalSince(started)))
            if let after = try? await engine.discover() { PrivateMoneyStore.shared.reconcile(after) }
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
            let owner = try PrivacyTestnetSender.ensure()
            stage = .opening
            if !PrivacyPoolsKey.exists() { try PrivacyPoolsKey.create() }
            var seed = try PrivacyPoolsKey.seed(reason: String(localized: "Move to private"))
            defer { seed.resetBytes(in: 0..<seed.count) }
            stage = .preparing
            // Opened every time: the account's owner is the sender, and a
            // page a probe opened may name another.
            _ = try await engine.open(seed: seed, owner: owner, network: .sepolia)
            seed.resetBytes(in: 0..<seed.count)
            if try await !engine.isRegistered().registered {
                let registration = try await engine.prepareRegister()
                for (i, tx) in registration.txs.enumerated() {
                    stage = .registering(i + 1)
                    let hash = try await PrivacyTestnetSender.send(tx)
                    NSLog("privateMove| register %d | %@", i + 1, hash)
                }
            }
            stage = .proving
            let deposit = try await engine.prepareDeposit(tokenId: PrivateMove.eth, value: hex)
            NSLog("privateMove| proved | %@ | %d ms", deposit.proofs.map { "\($0.circuit ?? "?") \($0.ms) ms" }.joined(separator: ", "), deposit.ms)
            stage = .sending
            for approval in deposit.approvals { _ = try await PrivacyTestnetSender.send(approval) }
            let hash = try await PrivacyTestnetSender.send(deposit.tx)
            PrivateMoneyStore.shared.add(.init(commitment: deposit.commitment, label: deposit.label, labelHash: deposit.labelHash,
                                               symbol: "ETH", amount: value, decimals: 18, chainId: PrivacyNetwork.sepolia.chainId,
                                               tx: hash, at: Date(), status: .waiting))
            stage = .done(hash)
            NSLog("privateMove| deposited | %@ | %@ ETH | label hash %@ | %d s",
                  hash, amount, deposit.labelHash, Int(Date().timeIntervalSince(started)))
            await PrivateMoneyStore.shared.refresh(force: true)
        } catch {
            stage = .failed(Self.words(error))
            NSLog("privateMove| failed | %@", String(describing: error))
        }
        #endif
    }

    static let eth = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"

    /// A failure in the sentence's words: short, and what to do where there is something.
    static func words(_ error: Error) -> String {
        if let failure = error as? PrivacyEngineWire.Failure {
            NSLog("privateMove| engine | %@ | %@", failure.name, failure.message)
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
        if error is PrivacyPoolsKey.Failure { return String(localized: "Face ID did not open the private account") }
        return String(localized: "Sepolia could not be reached")
    }
}
