import CryptoKit
import Foundation
import Observation

/// MAKING TAC PRIVATE, IN CASBERI (prd §1971 item 20; user, 2026-11-25: "i
/// thought we were going to make tacit option to make private is not in tacit
/// website. like so its a simpler ui").
///
/// Public TAC in your co-signer's wallet moves to the Tacit chain as private
/// TAC. Tacit's own code proves the deposit on this phone; your co-signer
/// signs one permit for exactly the amount and the leader's fee, checked
/// first (`TacitPermit`); the leader sweeps it and puts the deposit in a
/// block, about a minute later. A deposit no block takes goes back to Tacit's
/// DeFi pool under your key, which the page reads.
///
/// The first deposit asks your co-signer to sign Tacit's message once more,
/// as Tacit's own site does before money goes to a key: a wallet that signs
/// differently each time could not reach the account again.
@MainActor
@Observable
final class TacitShield {

    static let shared = TacitShield()

    enum Step: Equatable {
        case idle
        case quoting
        case ready
        case proving
        case signing(done: Int, of: Int)
        case handing
        case arriving
        case landed
        case failed(String)
    }

    private(set) var step: Step = .idle
    private(set) var quote: TacitEngineWire.ShieldQuote?
    private(set) var units: UInt64 = 0
    private(set) var proveMs: Int?

    /// Deposits handed and not yet landed, by the leader's id: shown as
    /// "Arriving" on the page until the chain takes them.
    struct Arriving: Codable, Equatable, Identifiable {
        let id: String
        let tac: Double
        let at: Date
    }
    private(set) var arriving: [Arriving] = []

    private static let arrivingKey = "tacit.shield.arriving.v1"
    private static func alikeKey(_ coSigner: String) -> String { "tacit.signsAlike.v1.\(coSigner.lowercased())" }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.arrivingKey),
           let kept = try? JSONDecoder().decode([Arriving].self, from: data) {
            arriving = kept.filter { Date.now.timeIntervalSince($0.at) < 3 * 3600 }
        }
    }

    /// TAC (a decimal amount) in the chain's 8-decimal units.
    static func units(_ tac: Double) -> UInt64? {
        guard tac.isFinite, tac > 0 else { return nil }
        return UInt64((tac * 1e8).rounded(.down))
    }

    /// What `tac` would cost and land as now. The account must be open.
    func quote(tac: Double) async {
        // The demo reaches nothing: its quote is the one read off the chain
        // on 2026-11-25 for 23.85 TAC, scaled (the fee does not scale).
        if DemoMode.isActive, let u = Self.units(tac) {
            units = u
            quote = .init(fee: "0x17a602", arrives: "0x" + String(UInt64(Double(u) * 0.99915), radix: 16),
                          cap: "0x174876e800", sweepFee: "0x641c508f683c00")
            step = .ready
            return
        }
        guard let u = Self.units(tac), TacitEngine.shared.isOpen else { quote = nil; step = .idle; return }
        units = u
        step = .quoting
        do {
            quote = try await TacitEngine.shared.shieldQuote(units: u)
            if units == u { step = .ready }
        } catch {
            step = .failed(String(localized: "Tacit could not be reached"))
        }
    }

    /// Where the TAC comes from: your co-signer's wallet, by a permit it
    /// signs, or your Casberi account, by a send to the deposit's inbox
    /// (user, 2026-11-25: "if a user is going to swap in casberi why not swap
    /// into casberi account", then "ok great" to making it private from there).
    enum Source: Equatable { case wallet, account }

    /// Proves, checks, asks the co-signer, hands it to the leader, and waits.
    func send(coSigner: String, from source: Source = .wallet) async {
        guard case .ready = step, let quote, units > 0, TacitEngine.shared.isOpen else { return }
        if source == .account { await sendFromAccount(coSigner: coSigner, quote: quote); return }
        let alikeDone = UserDefaults.standard.bool(forKey: Self.alikeKey(coSigner))
        let signatures = alikeDone ? 1 : 2
        do {
            // 1. Proved on this phone.
            step = .proving
            let proved = try await prove()
            proveMs = proved.proveMs
            // 2. Checked against the chain itself, before the wallet is asked.
            let chainInbox = try await Self.inbox(proved)
            guard let nonceData = TacitPermit.noncesCall(coSigner),
                  let nonceWord = await Self.ethCall(to: TacitPermit.token, data: nonceData),
                  let nonce = TacitPermit.number(nonceWord)
            else { throw Stop.notRead(.contract) }
            let balance = try await Self.balance(of: coSigner)
            if let problem = TacitPermit.check(proved: proved, quote: quote, coSigner: coSigner, owner: coSigner,
                                               units: units, chainInbox: chainInbox, balance: balance, now: .now) {
                throw Stop.refused(problem)
            }
            // 3. The first time, Tacit's message once more: the same key.
            if !alikeDone {
                step = .signing(done: 0, of: signatures)
                var again = try await TacitPocket.signIn(coSigner: coSigner)
                defer { for i in again.indices { again[i] = 0 } }
                guard TacitAccount.shared.isKey(again) else { throw Stop.signsDifferently }
                UserDefaults.standard.set(true, forKey: Self.alikeKey(coSigner))
            }
            // 4. The permit, for exactly what was checked.
            step = .signing(done: signatures - 1, of: signatures)
            guard let value = TacitPermit.number(proved.value) else { throw Stop.unreadable }
            let data = TacitPermit.typedData(owner: coSigner, spender: chainInbox, value: value, nonce: nonce,
                                             deadline: proved.deadline)
            guard let digest = TacitPermit.digest(data),
                  let json = try? JSONSerialization.data(withJSONObject: data),
                  let text = String(data: json, encoding: .utf8) else { throw Stop.unreadable }
            let tac = Double(units) / 1e8
            let signature = try await SignerRequestSheet.asking(
                signer: coSigner, title: String(localized: "Co-signer signs \(TacitAccountRows.amount(tac)) TAC to Tacit")) { ask in
                try await YourAccountSignerLink.signForApp(
                    method: "eth_signTypedData_v4", params: [coSigner, text], digest: digest, signer: coSigner,
                    resend: ask.resends, sent: { ask.ask(kept: $0) },
                    show: { ask.pair($0); ShieldBridge.openCoSignerWallet(coSigner, onto: $0) })
            }
            guard signature.count == 65 else { throw Stop.unreadable }
            // 5. Handed to the leader.
            step = .handing
            let handed = try await Self.handed { try await TacitEngine.shared.shieldHand(.init(
                owner: coSigner, v: Int(signature[64]),
                r: "0x" + Keccak256.hexString(Array(signature[0..<32])),
                s: "0x" + Keccak256.hexString(Array(signature[32..<64])))) }
            TacitShieldKept.save(handed.kept, id: handed.id)
            arriving.append(Arriving(id: handed.id, tac: tac, at: .now))
            keepArriving()
            step = .arriving
            Task { await self.watch(handed.id, coSigner: coSigner) }
        } catch is CancellationError {
            step = .ready
        } catch let stop as Stop {
            step = .failed(stop.words)
        } catch {
            step = .failed(TacitAccount.words(error))
        }
    }

    /// From your Casberi account: proved, checked, the deposit handed to the
    /// leader first (a refusal costs nothing), then your account sends the
    /// TAC to its inbox as any send goes, Face ID and your co-signer's
    /// approval included.
    private func sendFromAccount(coSigner: String, quote: TacitEngineWire.ShieldQuote) async {
        guard let account = YourAccountKey.address else { step = .failed(Stop.unreadable.words); return }
        let alikeDone = UserDefaults.standard.bool(forKey: Self.alikeKey(coSigner))
        do {
            step = .proving
            let proved = try await prove()
            proveMs = proved.proveMs
            let chainInbox = try await Self.inbox(proved)
            let balance = try await Self.balance(of: account)
            if let problem = TacitPermit.checkTransfer(proved: proved, quote: quote, units: units,
                                                       chainInbox: chainInbox, balance: balance) {
                throw Stop.refused(problem)
            }
            // The first time, Tacit's message once more: the same key.
            if !alikeDone {
                step = .signing(done: 0, of: 2)
                var again = try await TacitPocket.signIn(coSigner: coSigner)
                defer { for i in again.indices { again[i] = 0 } }
                guard TacitAccount.shared.isKey(again) else { throw Stop.signsDifferently }
                UserDefaults.standard.set(true, forKey: Self.alikeKey(coSigner))
            }
            step = .handing
            let handed = try await Self.handed { try await TacitEngine.shared.shieldOffer() }
            TacitShieldKept.save(handed.kept, id: handed.id)
            // Your account's own send: TAC, exactly the amount, to the inbox
            // the chain's contract named.
            step = .signing(done: alikeDone ? 0 : 1, of: alikeDone ? 1 : 2)
            let wei = TacitPermit.text(Decimal(units) * pow(Decimal(10), 10))
            let payment = YourAccountOp.Payment(network: YourAccountOp.ethereum,
                                                token: .init(symbol: "TAC", decimals: 18, contract: TacitPermit.token),
                                                amount: wei, to: EIP55.checksum(chainInbox), toName: "Tacit")
            let sent = try await YourAccountChain.send([payment], reason: String(localized: "Make private"), stage: { _ in })
            if case .dryRun = sent.outcome { throw Stop.unreadable }
            let tac = Double(units) / 1e8
            arriving.append(Arriving(id: handed.id, tac: tac, at: .now))
            keepArriving()
            step = .arriving
            Task { await self.watch(handed.id, coSigner: coSigner) }
        } catch is CancellationError {
            step = .ready
        } catch let stop as Stop {
            step = .failed(stop.words)
        } catch {
            step = .failed(TacitAccount.words(error))
        }
    }

    /// The longest the proof and the return path's slot may take. Asked
    /// after the DeFi read, about ten seconds; cold, through Tor, about three
    /// minutes. Past this the sheet says so and offers Try again, never a
    /// spinner that does not end (user, 2026-11-25: "just stays on this
    /// screen forever spinning"). The engine's read keeps going, so a second
    /// try picks up its answer.
    static let proveLimit: Double = 240

    /// When the proof began, for the seconds the sheet counts.
    private(set) var provingSince: Date?

    private func prove() async throws -> TacitEngineWire.ShieldProved {
        let units = self.units
        provingSince = .now
        defer { provingSince = nil }
        let once = Once()
        return try await withCheckedThrowingContinuation { cont in
            Task { @MainActor in
                do {
                    let p = try await TacitEngine.shared.shieldProve(units: units)
                    if once.take() { cont.resume(returning: p) }
                } catch is CancellationError {
                    if once.take() { cont.resume(throwing: CancellationError()) }
                } catch {
                    if once.take() { cont.resume(throwing: Stop.proofFailed) }
                }
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.proveLimit))
                if once.take() { cont.resume(throwing: Stop.tooLong) }
            }
        }
    }

    @MainActor private final class Once {
        private var taken = false
        func take() -> Bool { if taken { return false }; taken = true; return true }
    }

    /// Asks the leader every few seconds until the deposit lands or is
    /// refused; then the page reads the chain again, if the account is open.
    func watch(_ id: String, coSigner: String) async {
        let began = Date()
        while Date().timeIntervalSince(began) < 30 * 60 {
            try? await Task.sleep(for: .seconds(5))
            guard let s = try? await TacitEngine.shared.shieldStatus(id: id) else { continue }
            if s.ok, s.status == "landed" {
                finish(id)
                if step == .arriving { step = .landed }
                if TacitEngine.shared.isOpen, let chain = await TacitPocket.chain(coSigner: coSigner) {
                    TacitAccount.shared.applyChain(chain, coSigner: coSigner)
                }
                return
            }
            if s.status == "refused" {
                finish(id)
                step = .failed(String(localized: "Tacit's chain didn't take it. It goes back to your DeFi pool."))
                return
            }
        }
    }

    func reset() {
        step = .idle
        quote = nil
        units = 0
        proveMs = nil
    }

    private func finish(_ id: String) {
        arriving.removeAll { $0.id == id }
        keepArriving()
        TacitShieldKept.forget(id)
    }

    private func keepArriving() {
        if let data = try? JSONEncoder().encode(arriving) { UserDefaults.standard.set(data, forKey: Self.arrivingKey) }
    }

    enum Stop: Error {
        case unreadable
        /// A chain read after the proof that did not answer, three tries.
        case notRead(Read)
        case proofFailed
        case notTaken
        case refused(TacitPermit.Problem)
        case signsDifferently
        case tooLong

        var words: String {
            switch self {
            case .tooLong: return String(localized: "Tacit took too long. Try again")
            case .unreadable: return String(localized: "Tacit could not be read")
            case .notRead(.inbox): return String(localized: "Couldn't read Tacit's inbox. Try again")
            case .notRead(.contract): return String(localized: "Couldn't read the TAC contract. Try again")
            case .notRead(.balance): return String(localized: "Couldn't read your TAC. Try again")
            case .proofFailed: return String(localized: "Tacit couldn't make the proof. Try again")
            case .notTaken: return String(localized: "Tacit didn't take the deposit. Try again")
            case .signsDifferently: return String(localized: "Your co-signer signs differently each time, so it can't hold a Tacit key")
            case .refused(let p):
                switch p {
                case .notEnough: return String(localized: "More than it holds")
                case .feeRose: return String(localized: "Tacit's fee rose. Try again for a new quote")
                case .overCap: return String(localized: "More than Tacit takes in one deposit")
                default: return String(localized: "This deposit didn't check out, so nothing was asked")
                }
            }
        }
    }

    /// One `eth_call` at the Ethereum node the engine reads, through its funnel.
    enum Read: Sendable { case inbox, contract, balance }

    /// The inbox the chain's own contract names for this proof.
    private static func inbox(_ proved: TacitEngineWire.ShieldProved) async throws -> String {
        guard let data = TacitPermit.inboxCall(proved.deposit, back: proved.back),
              let word = await ethCall(to: TacitChain.blocks, data: data),
              let inbox = TacitPermit.address(fromWord: word) else { throw Stop.notRead(.inbox) }
        return inbox
    }

    /// The TAC an address holds, in wei, asked up to three times.
    private static func balance(of address: String) async throws -> Decimal {
        for attempt in 0..<3 {
            if attempt > 0 { try await Task.sleep(for: .seconds(Double(attempt))) }
            if let tac = await TacitPocket.publicTAC(of: address) { return Decimal(tac) * pow(Decimal(10), 18) }
        }
        throw Stop.notRead(.balance)
    }

    /// The leader's answer; any refusal of its own is "didn't take it".
    private static func handed<T>(_ hand: () async throws -> T) async throws -> T {
        do { return try await hand() }
        catch is CancellationError { throw CancellationError() }
        catch { throw Stop.notTaken }
    }

    /// One `eth_call`, asked up to three times: a public node that refuses
    /// once (it is shared, and the engine has just read it hard) is not an
    /// answer.
    static func ethCall(to: String, data: String) async -> String? {
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(Double(attempt))) }
            if let word = await ethCallOnce(to: to, data: data) { return word }
        }
        return nil
    }

    private static func ethCallOnce(to: String, data: String) async -> String? {
        guard let url = URL(string: TacitNetwork.ethereum.rpcUrl) else { return nil }
        let body: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "eth_call", "params": [["to": to, "data": data], "latest"]]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30
        guard let (data, http) = await IngestSupport.sendRequest(request, service: TacitEngine.service), http.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? String, result.count == 66 else { return nil }
        return result
    }
}

/// A handed deposit, kept as the chain client keeps it until it lands: the
/// proof, its public signals and the permit, so it can be handed again.
/// Kept in the Keychain on this device only.
enum TacitShieldKept {
    static func key(_ id: String) -> String { "tacit.shield.kept.v1.\(id)" }
    static func save(_ kept: String, id: String) { TokenVault.set(kept, for: key(id)) }
    static func forget(_ id: String) { TokenVault.delete(key(id)) }
}
