import Foundation
import Observation

/// BACK TO PUBLIC (prd §1977; user, 2026-11-25: "lets do that", of Tacit's
/// pieces in Move, then "do you want to continue or wait for me?").
///
/// Private TAC on the Tacit chain goes back to an Ethereum address you own,
/// in Tacit's own two steps (`TacitBlocks`):
///
/// 1. **Out of the Tacit chain.** Tacit's code proves the withdrawal on this
///    phone with the Tacit key and hands it to the leader. No wallet signs:
///    the proof is the spend. When a block takes it, Tacit's contract OWES
///    the address the TAC (`owed(address)`).
/// 2. **Collected.** Anyone may call `withdraw(address)` to pay out what is
///    owed; your Casberi account does, with Face ID, as any of its calls
///    goes (`YourAccountChain.privateCalls`: checked against the chain first,
///    nothing signed if it would fail). The address is yours either way:
///    your Casberi account or your co-signer.
///
/// TAC owed and not collected stays owed; the sheet offers Collect whenever
/// the contract owes the address, so a closed sheet loses nothing.
@MainActor
@Observable
final class TacitOut {

    static let shared = TacitOut()

    enum Step: Equatable {
        case idle
        case quoting
        case ready
        case proving
        case handing
        /// Handed; waiting for a Tacit block to take it.
        case landing
        /// Owed on Ethereum; your account is paying it out.
        case collecting
        case done
        case failed(String)
    }

    private(set) var step: Step = .idle
    private(set) var quote: TacitEngineWire.OutQuote?
    private(set) var units: UInt64 = 0
    /// TAC the contract owes `owedTo` and nobody has collected, 18 decimals.
    private(set) var owedWei: Decimal = 0
    private(set) var owedTo: String?
    private(set) var provingSince: Date?
    /// Set once a withdrawal is handed to the leader, until it is collected:
    /// from then the sheet offers Collect, never a second withdrawal.
    private(set) var handed = false
    /// When the last payout went out, and how much: a node a few blocks
    /// behind still says it is owed, so for three minutes after a payout
    /// nothing is owed here (user, 2026-11-25: a second payout of 0 TAC two
    /// blocks after the first).
    private var paidAt: Date?
    private(set) var paidTAC: Double?

    private init() {}

    /// Another Tacit account, when this is a private send rather than back
    /// to public (prd §1982): its `tc1…` or `tacit1…` address. Nothing to
    /// collect: the note is theirs once a block takes it.
    var payTo: String?

    /// **AGAIN (prd §1983, as Send's §1904 item 5):** the last private send,
    /// kept on this phone; Send's To leads with it.
    struct Again: Codable, Equatable {
        let to: String
        let tac: Double
    }
    private static let againKey = "tacit.again.v1"
    static var again: Again? {
        UserDefaults.standard.data(forKey: againKey).flatMap { try? JSONDecoder().decode(Again.self, from: $0) }
    }
    private static func keepAgain(_ a: Again) {
        if let data = try? JSONEncoder().encode(a) { UserDefaults.standard.set(data, forKey: againKey) }
    }

    /// Whether `text` reads as a Tacit address a private send can take.
    nonisolated static func isTacitAddress(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.hasPrefix("tc1") { return t.count > 100 && t.dropFirst(3).allSatisfy(\.isHexDigit) }
        if t.hasPrefix("tacit1") { return t.count > 60 && t.dropFirst(6).allSatisfy { "023456789acdefghjklmnpqrstuvwxyz".contains($0) } }
        return false
    }

    /// `withdraw(address)` on `TacitChain.blocks`, read off Tacit's contract
    /// (keccak256 of the signature, checked against its source 2026-11-25).
    static let withdrawSelector = "51cff8d9"

    static func withdrawCalldata(_ address: String) -> String? {
        let hex = address.lowercased().replacingOccurrences(of: "0x", with: "")
        guard hex.count == 40, hex.allSatisfy(\.isHexDigit) else { return nil }
        return "0x" + withdrawSelector + String(repeating: "0", count: 24) + hex
    }

    /// The most that can go and what it costs, for `tac`. The account must
    /// be open; the first quote reads the account's notes (about half a
    /// minute through Tor).
    func quote(tac: Double) async {
        guard let u = TacitShield.units(tac), TacitEngine.shared.isOpen else { quote = nil; step = .idle; return }
        units = u
        step = .quoting
        do {
            quote = payTo == nil ? try await TacitEngine.shared.outQuote(units: u)
                : try await TacitEngine.shared.payQuote(units: u)
            if units == u { step = .ready }
        } catch {
            step = .failed(TacitAccount.words(error))
        }
    }

    /// What the contract owes `address` now; Collect stands while it is more
    /// than nothing.
    func readOwed(_ address: String) async {
        if let paidAt, Date().timeIntervalSince(paidAt) < 180 { owedWei = 0; return }
        guard TacitEngine.shared.isOpen, let o = try? await TacitEngine.shared.owed(address),
              let wei = TacitPermit.number(o.wei) else { return }
        owedWei = wei
        owedTo = address
    }

    /// Proves, hands, waits for the block, then collects to `to`.
    func send(to: String) async {
        guard case .ready = step, units > 0, TacitEngine.shared.isOpen else { return }
        do {
            step = .proving
            provingSince = .now
            do {
                if let payTo {
                    _ = try await TacitEngine.shared.payProve(to: payTo, units: units)
                } else {
                    _ = try await TacitEngine.shared.outProve(to: to, units: units)
                }
                provingSince = nil
            } catch {
                provingSince = nil
                throw error
            }
            owedTo = to
            step = .handing
            let ticket = try await TacitEngine.shared.outHand()
            handed = true
            step = .landing
            try await land(ticket.id)
            if payTo != nil {
                // A pay has nothing to collect: theirs once the block took it.
                paidTAC = Double(units) / 1e8
                handed = false
                step = .done
                Self.keepAgain(Again(to: payTo ?? "", tac: Double(units) / 1e8))
                let sent = TacitAccountRows.amount(Double(units) / 1e8)
                Task { await Notifications.outcome(.moveSent, id: "tacit:pay:" + ticket.id, place: TacitAccount.name,
                                                   body: String(localized: "\(sent) TAC sent privately"), mark: TacitAccount.name) }
                if let coSigner = YourAccountFacts.coSigners.first, let chain = await TacitPocket.chain(coSigner: coSigner) {
                    TacitAccount.shared.applyChain(chain, coSigner: coSigner)
                }
                return
            }
            await readOwed(to)
            try await collect(to: to)
        } catch is CancellationError {
            step = .ready
        } catch let stop as Stop {
            step = .failed(stop.words)
            notifyFailed(stop.words)
        } catch {
            step = .failed(TacitAccount.words(error))
            notifyFailed(TacitAccount.words(error))
        }
    }

    /// A move of yours that stopped, said while you are away (prd §1881).
    private func notifyFailed(_ words: String) {
        Task { await Notifications.outcome(.moveFailed, id: "tacit:fail:\(Int(Date().timeIntervalSince1970))",
                                           place: TacitAccount.name, body: words, mark: TacitAccount.name) }
    }

    /// Pays out what the contract owes `to`, from your Casberi account.
    func collect(to: String) async throws {
        // Read again here, never trusted from before: a read that failed
        // after the block must not leave "Try again" (a second withdrawal)
        // where Collect belongs.
        // Always a fresh read, never a figure from earlier (which paid out 0).
        owedWei = 0
        for attempt in 0..<3 where owedWei <= 0 {
            if attempt > 0 { try await Task.sleep(for: .seconds(Double(2 * attempt))) }
            await readOwed(to)
        }
        guard owedWei > 0 else { throw Stop.nothingOwed }
        guard let data = Self.withdrawCalldata(to) else { throw Stop.badAddress }
        step = .collecting
        let sent = try await YourAccountChain.privateCalls([(to: TacitChain.blocks, data: data, value: "0")],
                                                           on: YourAccountOp.ethereum,
                                                           reason: String(localized: "Back to public"),
                                                           stage: { _ in })
        if case .dryRun = sent.outcome { throw Stop.nothingOwed }
        paidTAC = NSDecimalNumber(decimal: owedWei / pow(Decimal(10), 18)).doubleValue
        paidAt = .now
        owedWei = 0
        handed = false
        step = .done
        if let paid = paidTAC {
            Task { await Notifications.outcome(.readyToUse, id: "tacit:out:\(Int(Date().timeIntervalSince1970))", place: TacitAccount.name,
                                               body: String(localized: "\(TacitAccountRows.amount(paid)) TAC is public again"),
                                               mark: TacitAccount.name) }
        }
        // Your public TAC at once, then the chain's notes.
        await TacitAccount.shared.readPublic()
        if let coSigner = YourAccountFacts.coSigners.first, let chain = await TacitPocket.chain(coSigner: coSigner) {
            TacitAccount.shared.applyChain(chain, coSigner: coSigner)
        }
    }

    /// Collect alone, for TAC owed from an earlier try.
    func collectOwed() async {
        guard let to = owedTo else { return }
        do { try await collect(to: to) }
        catch let stop as Stop { step = .failed(stop.words) }
        catch { step = .failed(TacitAccount.words(error)) }
    }

    /// The leader's receipt, every five seconds, up to half an hour.
    private func land(_ id: String) async throws {
        let began = Date()
        while Date().timeIntervalSince(began) < 30 * 60 {
            try await Task.sleep(for: .seconds(5))
            guard let s = try? await TacitEngine.shared.shieldStatus(id: id) else { continue }
            if s.ok, s.status == "landed" { return }
            if s.status == "refused" { throw Stop.refused }
        }
        throw Stop.slow
    }

    /// Proved, handed, landing or collecting: Holdings shows it on its way.
    var inFlight: Bool {
        switch step {
        case .proving, .handing, .landing, .collecting: true
        default: false
        }
    }

    /// Done read and closed: the next open starts fresh.
    func finish() {
        step = .idle
        quote = nil
        units = 0
    }

    func reset() {
        switch step {
        case .collecting, .done: return
        default: break
        }
        step = .idle
        quote = nil
        units = 0
    }

    enum Stop: Error {
        case refused, slow, nothingOwed, badAddress

        var words: String {
            switch self {
            case .refused: return String(localized: "Tacit's chain didn't take it. Your TAC stays private")
            case .slow: return String(localized: "Still waiting on Tacit's chain. Collect it later from here")
            case .nothingOwed: return String(localized: "Tacit owes nothing to collect yet. Collect it later from here")
            case .badAddress: return String(localized: "That isn't an Ethereum address")
            }
        }
    }
}
