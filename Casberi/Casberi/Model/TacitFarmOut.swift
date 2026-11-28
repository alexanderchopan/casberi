import Foundation
import Observation

/// **WITHDRAW FROM A TACIT FARM (prd §2006; user, 2026-11-27: "Yes, skip
/// Join").** Earn's Withdraw, on a farm you are in: the whole position comes
/// out, in Tacit's own three steps (`farm-ops.js`, as Tacit's Earn tab takes
/// them), each signed in the engine with your Tacit key and proved and sent
/// by Tacit's relay:
///
/// 1. **Claim** what the position earned. It lands as wTAC, TAC 1:1. A
///    harvest goes first because an unbond pays out nothing unharvested.
/// 2. **Release** the position's shares as an LP-share note.
/// 3. **Take out** the shares as the pair's two coins, private in Tacit's
///    DeFi pool; the relay's fee comes from the first.
///
/// Nothing is sent from your Casberi account, so there is no Face ID. Each
/// step reads the chain again before it acts, so Try again picks up where the
/// last stopped: a claimed position is not claimed twice, a released one is
/// only taken out. Joining stays on Tacit's site (prd §2006).
@MainActor
@Observable
final class TacitFarmOut {

    static let shared = TacitFarmOut()

    enum Step: Equatable {
        case idle
        case claiming
        case releasing
        case takingOut
        case done
        case failed(String)
    }

    private(set) var step: Step = .idle {
        didSet { Self.followAway(step) }
    }
    /// The farm being left, by its pool's LP-share asset id.
    private(set) var lpAsset: String?
    /// What came back: TAC claimed, and the pair's coins by name.
    private(set) var claimedTAC: Double = 0
    private(set) var paid: [String: Double] = [:]
    /// Tacit's relay fee for the take-out, read before you hold: the coin
    /// it comes from and how much; nil until read.
    private(set) var fee: (coin: String, amount: Double)?
    private(set) var feeFor: String?
    /// When the steps began, for "Took 2 min 40 s".
    private(set) var startedAt: Date?
    private(set) var tookSeconds: Int?

    /// Reads the fee for leaving `lpAsset` (no key, nothing signed).
    func quote(_ lpAsset: String) async {
        if DemoMode.isActive { fee = ("ETH", 0.0004); feeFor = lpAsset; return }
        guard TacitEngine.shared.isOpen else { return }
        guard let q = try? await TacitEngine.shared.farmQuote(lpAsset: lpAsset),
              let units = TacitEngineWire.number(q.fee) else { return }
        fee = (TacitFarms.coinName(q.ticker), units / pow(10, Double(q.decimals)))
        feeFor = lpAsset
    }

    /// Closes the sheet once the steps start; nil where it stays.
    var onAway: (() -> Void)?

    private init() {}

    /// Running: Holdings and the sheet say so, and nothing starts it twice.
    var inFlight: Bool {
        switch step {
        case .claiming, .releasing, .takingOut: true
        default: false
        }
    }

    /// The shared run's three steps (`PrivateStepRows`), in Tacit's words.
    static var plan: PrivateSendSteps.Plan {
        PrivateSendSteps.Plan(steps: [
            PrivateSendSteps.Step(key: .checking, running: String(localized: "Claiming what it earned"), done: String(localized: "Claimed what it earned")),
            PrivateSendSteps.Step(key: .signing, running: String(localized: "Releasing your shares"), done: String(localized: "Released your shares")),
            PrivateSendSteps.Step(key: .sent, running: String(localized: "Taking out your coins"), done: String(localized: "Took out your coins")),
        ])
    }

    /// **BEHIND ITS SHEET (prd §2003, as Tacit's other moves):** the steps
    /// ask nobody anything, so once they start the sheet may close and the
    /// capsule hears the rest from here.
    private static func followAway(_ step: Step) {
        let steps = PrivateSendSteps.shared
        guard steps.awayFrom == .tacitFarm else { return }
        switch step {
        case .releasing: steps.mark(.signing, from: .tacitFarm)
        case .takingOut: steps.mark(.sent, from: .tacitFarm)
        case .done: steps.finish(from: .tacitFarm)
        case .failed(let why): steps.fail(why, from: .tacitFarm)
        default: break
        }
    }

    /// Leaves the farm `lpAsset` names: claim, release, take out.
    func leave(_ lpAsset: String) async {
        guard !inFlight, TacitEngine.shared.isOpen, !DemoMode.isActive else { return }
        self.lpAsset = lpAsset
        claimedTAC = 0
        paid = [:]
        startedAt = .now
        tookSeconds = nil
        do {
            step = .claiming
            let claimed = try await TacitEngine.shared.farmClaim(lpAsset: lpAsset)
            claimedTAC = TacitEngineWire.number(claimed.claimed).map { $0 / TacitFarms.unit } ?? 0
            NSLog("tacitFarm| claimed %.4f TAC, position %@", claimedTAC, claimed.position ? "yes" : "no")
            step = .releasing
            let released = try await TacitEngine.shared.farmRelease(lpAsset: lpAsset)
            NSLog("tacitFarm| released, position %@", released.position ? "yes" : "no")
            step = .takingOut
            let out = try await TacitEngine.shared.farmTakeOut(lpAsset: lpAsset)
            NSLog("tacitFarm| took out %d coins, found %@", out.out.count, out.found ? "yes" : "no")
            // Nothing bonded and nothing to take out: the farm was already left.
            if !claimed.position, !released.position, !out.found { throw Stop.nothingThere }
            for h in out.out { if let a = h.amount { paid[TacitFarms.coinName(h.ticker), default: 0] += a } }
            tookSeconds = startedAt.map { Int(Date().timeIntervalSince($0)) }
            step = .done
            notifyDone()
        } catch let stop as Stop {
            step = .failed(stop.words)
            notifyFailed(stop.words)
        } catch {
            let words = Self.words(error)
            step = .failed(words)
            notifyFailed(words)
        }
        // What the farm paid back, and the position gone, at once.
        if let coSigner = YourAccountFacts.coSigners.first {
            await TacitAccount.shared.readDefiAndFarms(coSigner: coSigner)
        }
    }

    /// The relay's refusals in plain words; anything else as the engine says it.
    static func words(_ error: Error) -> String {
        guard let f = error as? TacitEngineWire.Failure else { return TacitAccount.words(error) }
        switch f.name {
        case "RelayBusy": return String(localized: "Tacit is busy. Try again later")
        case "Claim", "Release", "TakeOut": return String(localized: "Tacit didn't finish. Try again")
        default: return TacitAccount.words(error)
        }
    }

    enum Stop: Error {
        case nothingThere

        var words: String {
            switch self {
            case .nothingThere: return String(localized: "You're not in this farm anymore")
            }
        }
    }

    /// The coins that came back, as one line: "0.12 ETH, 240 TAC and 3.4
    /// wTAC". What it earned is wTAC, said as wTAC (user: "if it is wTac we
    /// need to say it").
    var paidWords: String {
        var coins = paid
        if claimedTAC > 0 { coins["wTAC", default: 0] += claimedTAC }
        return ListFormatter.localizedString(byJoining: coins.sorted { $0.key < $1.key }
            .map { "\(TacitAccountRows.amount($0.value)) \($0.key)" })
    }

    private func notifyDone() {
        let body = paidWords.isEmpty ? String(localized: "Out of the farm") : String(localized: "Out of the farm: \(paidWords)")
        Task { await Notifications.outcome(.readyToUse, id: "tacit:farm:\(Int(Date().timeIntervalSince1970))", place: TacitAccount.name,
                                           body: body, mark: TacitAccount.name) }
    }

    private func notifyFailed(_ words: String) {
        Task { await Notifications.outcome(.moveFailed, id: "tacit:farmfail:\(Int(Date().timeIntervalSince1970))",
                                           place: TacitAccount.name, body: words, mark: TacitAccount.name) }
    }

    /// Done read and closed: the next open starts fresh.
    func finish() {
        guard !inFlight else { return }
        step = .idle
        lpAsset = nil
        claimedTAC = 0
        paid = [:]
    }

    #if DEBUG
    /// `-tacitFarmSample done|failed`: a finished withdrawal drawn on a
    /// simulator, where no co-signer opens the account. Nothing is sent.
    func sample(_ how: String, lpAsset: String) {
        self.lpAsset = lpAsset
        if how == "failed" {
            step = .failed(Self.words(TacitEngineWire.Failure(name: "RelayBusy", message: "")))
        } else {
            claimedTAC = 3.42
            paid = ["ETH": 0.0512, "TAC": 99.1]
            tookSeconds = 160
            step = .done
        }
    }
    #endif
}
