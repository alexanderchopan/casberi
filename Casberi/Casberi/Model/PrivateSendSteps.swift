import Foundation
import Observation
import UIKit

/// **THE STEPS A PRIVATE SEND SHOWS (prd §1700w, §1700x).** A private send
/// takes from seconds to a minute: checked, proved or signed on this device,
/// then on its network. Each engine says each step as it happens: Aztec's
/// (`tools/aztec-engine/src/steps.js`: the prover's first command, the
/// node's `sendTx`) and Railgun's, both as one `engineStep` message
/// `{step, kind, sent, reason}`. The screen that started the send draws
/// it: Move's rows (`PrivateStepRows`), the Aztec browser's capsule
/// (`AztecStepCapsule`). Real seconds, never a percentage it cannot know.
///
/// One model for both, so the two private balances read the same (user,
/// 2026-11-09: "i want to make sure we are consistent"). A send's PLAN is
/// its ordered steps: an Aztec send is Checking · Proving · Sent to Aztec, a
/// Railgun move-in Checking · Signing · Sent on Ethereum.
@MainActor
@Observable
final class PrivateSendSteps {
    static let shared = PrivateSendSteps()

    /// Who started the send: Move, or an app in the Aztec browser.
    enum Kind: String { case move, app }

    /// The engines' step names, as their messages spell them.
    enum Key: String { case checking, proving, signing, sent, screening }

    /// Where the money lands, said by the last step.
    enum Place: Equatable {
        case aztec, ethereum, base

        var sending: String {
            switch self {
            case .aztec: String(localized: "Sending to Aztec")
            case .ethereum: String(localized: "Sending on Ethereum")
            case .base: String(localized: "Sending on Base")
            }
        }

        var sent: String {
            switch self {
            case .aztec: String(localized: "Sent to Aztec")
            case .ethereum: String(localized: "Sent on Ethereum")
            case .base: String(localized: "Sent on Base")
            }
        }
    }

    /// One step: its key, its words while it runs and once it is done.
    struct Step: Equatable {
        let key: Key
        let running: String
        let done: String

        static var checking: Step { Step(key: .checking, running: String(localized: "Checking"), done: String(localized: "Checked")) }
        @MainActor static var proving: Step { Step(key: .proving, running: DeviceWord.proving, done: DeviceWord.proved) }
        static var signing: Step { Step(key: .signing, running: String(localized: "Signing"), done: String(localized: "Signed")) }
        static func sent(_ place: Place) -> Step { Step(key: .sent, running: place.sending, done: place.sent) }
    }

    /// A send's steps, in order. The first is under way from `begin`.
    struct Plan: Equatable {
        let steps: [Step]

        /// A private send with a proof: Checking · Proving · Sent.
        @MainActor static func send(_ place: Place) -> Plan { Plan(steps: [.checking, .proving, .sent(place)]) }
        /// A move that is signed, not proved: Checking · Signing · Sent.
        static func signed(_ place: Place) -> Plan { Plan(steps: [.checking, .signing, .sent(place)]) }
    }

    struct Run: Equatable {
        var kind: Kind
        var plan: Plan
        var started: Date
        /// When each step after the first began, as the engine said it.
        var at: [Key: Date] = [:]
        var ended: Date?
        var ok: Bool?
        /// A failure's own words, from the engine (or the caller).
        var reason: String?
        /// The network took the transaction (a failure after that still reached it).
        var reachedNetwork = false

        var isRunning: Bool { ended == nil }

        /// The furthest step the engine has reached; the first until then.
        var currentIndex: Int {
            plan.steps.indices.last { i in i == 0 || at[plan.steps[i].key] != nil } ?? 0
        }

        /// When step `i` began and ended, as far as the engine has said. A
        /// step the engine passed without a word (no proof seen) has none.
        func span(_ i: Int) -> (start: Date?, end: Date?) {
            let start = i == 0 ? started : at[plan.steps[i].key]
            let later = plan.steps.indices.filter { $0 > i }.compactMap { at[plan.steps[$0].key] }.min()
            return (start, later ?? ended)
        }

        /// Whole seconds from the tap to the end, for "Sent privately · 19 s".
        var total: Int? { ended.map { max(1, Int($0.timeIntervalSince(started).rounded())) } }
    }

    private(set) var run: Run?

    /// **A SEND THAT GOES ON BEHIND ITS SHEET (prd §1777).** Once every ask
    /// is answered a send within Aztec needs nobody for a minute or two, so
    /// its sheet closes and the run moves here, where the shell's capsule
    /// draws it (`MoveStepCapsule`). Its own slot: a second move started
    /// meanwhile begins in `run` and cannot overwrite it, and the engine's
    /// words about it still reach it (`received`).
    private(set) var away: Run?

    /// The caller starts the clock at its tap, before a cold engine has said anything.
    func begin(_ kind: Kind, plan: Plan) {
        run = Run(kind: kind, plan: plan, started: .now)
    }

    /// Move's running send leaves its sheet.
    func sendAway() {
        guard let current = run, current.kind == .move, current.isRunning else { return }
        away = current
        run = nil
    }

    /// Its sheet is open again: the rows there draw it, running or failed.
    /// Never over another send that is still going in the sheet.
    func bringBack() {
        guard let current = away, run?.isRunning != true else { return }
        run = current
        away = nil
    }

    /// The send behind the sheet failed in the caller's own code.
    func failAway(_ reason: String) {
        guard var current = away, current.isRunning else { return }
        current.ended = .now
        current.ok = false
        current.reason = reason
        away = current
    }

    /// The send behind the sheet came back good and the engine never said so.
    func finishAway() {
        guard var current = away, current.isRunning else { return }
        current.ended = .now
        current.ok = true
        current.reachedNetwork = true
        away = current
    }

    /// The capsule has said "Sent" for its two seconds, or a failure was opened.
    func clearAway() { away = nil }

    /// One `engineStep` message. `plan` is the engine's own, for a send it
    /// began itself (an app's transaction in the browser).
    func received(_ body: [String: Any], plan: Plan) {
        guard let step = body["step"] as? String, let kind = Kind(rawValue: body["kind"] as? String ?? "") else { return }
        // The engine's words about a send behind its sheet go to it there
        // (prd §1777): only Aztec's engine speaks here, and only an Aztec
        // send is ever away.
        if let behind = away, behind.kind == kind, behind.isRunning {
            if step != "checking" { away = Self.advanced(behind, step: step, body: body) }
            return
        }
        if step == "checking" {
            // The caller's own tap already started this run; anything else is a new send.
            if let run, run.kind == kind, run.isRunning { return }
            run = Run(kind: kind, plan: plan, started: .now)
            return
        }
        guard let current = run, current.kind == kind, current.isRunning else { return }
        run = Self.advanced(current, step: step, body: body)
    }

    /// One step's word applied to a run: a step reached, or its end.
    static func advanced(_ run: Run, step: String, body: [String: Any]) -> Run {
        var current = run
        switch step {
        case "done", "failed":
            current.ended = .now
            current.ok = step == "done"
            if step == "failed" { current.reason = (body["reason"] as? String).flatMap { $0.isEmpty ? nil : $0 } }
            if body["sent"] as? Bool == true { current.reachedNetwork = true }
        default:
            guard let key = Key(rawValue: step), current.plan.steps.contains(where: { $0.key == key }) else { return run }
            current.at[key] = current.at[key] ?? .now
            if key == .sent { current.reachedNetwork = true }
        }
        return current
    }

    /// A step reached, said by the caller (a send its own Swift drives, like
    /// a Shield deposit signed by Your account). Same rules as an engine's.
    func mark(_ key: Key) {
        guard let current = run else { return }
        received(["step": key.rawValue, "kind": current.kind.rawValue], plan: current.plan)
    }

    /// The caller's own success.
    func finish() {
        guard let current = run else { return }
        received(["step": "done", "kind": current.kind.rawValue], plan: current.plan)
    }

    /// The caller is starting a new send: a finished run of its kind goes.
    func forget(_ kind: Kind) {
        if run?.kind == kind, run?.isRunning == false { run = nil }
    }

    /// The caller's own failure (Face ID refused, a check before the engine).
    func fail(_ reason: String) {
        guard var current = run, current.isRunning else { return }
        current.ended = .now
        current.ok = false
        current.reason = reason
        run = current
    }

    /// The person put a failure away.
    func clear() { run = nil }
}

/// **THIS DEVICE, BY NAME (prd §1700x).** "Proving on this iPhone" is wrong on
/// an iPad and a Mac, and "your phone" is wrong on both too. Whole strings,
/// never a phrase pieced together, so every language reads right.
enum DeviceWord {
    enum Kind { case phone, pad, mac }

    @MainActor static var kind: Kind {
        if ProcessInfo.processInfo.isMacCatalystApp || ProcessInfo.processInfo.isiOSAppOnMac { return .mac }
        return UIDevice.current.userInterfaceIdiom == .pad ? .pad : .phone
    }

    @MainActor static var proving: String {
        switch kind {
        case .phone: String(localized: "Proving on this iPhone")
        case .pad: String(localized: "Proving on this iPad")
        case .mac: String(localized: "Proving on this Mac")
        }
    }

    @MainActor static var proved: String {
        switch kind {
        case .phone: String(localized: "Proved on this iPhone")
        case .pad: String(localized: "Proved on this iPad")
        case .mac: String(localized: "Proved on this Mac")
        }
    }
}
