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

    /// Whose engine proves a send behind its sheet, so only its words reach it.
    /// Whose move a run is. Earn (Aave, Olla) and Tacit go behind their
    /// sheets too (prd §2003): your account's Face ID is drawn over anything.
    /// Tacit is two: Make private (`tacitIn`) and back to public or a send
    /// from Tacit (`tacitOut`), so a failure reopens the right sheet (prd §2005).
    enum Source { case aztec, railgun, privacyPools, earn, tacitIn, tacitOut, tacitFarm }

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
        /// Signing, named for who signs (prd §1925, user: "it didn't say
        /// signs this iphone or cosigner").
        static func signing(onThisPhone: Bool) -> Step {
            onThisPhone
                ? Step(key: .signing, running: String(localized: "Signing on this iPhone"), done: String(localized: "Signed on this iPhone"))
                : Step(key: .signing, running: String(localized: "Your co-signer signs"), done: String(localized: "Your co-signer signed"))
        }
    }

    /// A send's steps, in order. The first is under way from `begin`.
    struct Plan: Equatable {
        let steps: [Step]

        /// It ends on Aztec: its words wear Aztec's ink (prd §1779).
        var isAztec: Bool { steps.last == .sent(.aztec) }

        /// A private send with a proof: Checking · Proving · Sent.
        @MainActor static func send(_ place: Place) -> Plan { Plan(steps: [.checking, .proving, .sent(place)]) }
        /// A move that is signed, not proved: Checking · Signing · Sent.
        static func signed(_ place: Place) -> Plan { Plan(steps: [.checking, .signing, .sent(place)]) }
        /// A move into Aztec: its signing step names who signs (prd §1925).
        static func signed(_ place: Place, onThisPhone: Bool) -> Plan {
            Plan(steps: [.checking, .signing(onThisPhone: onThisPhone), .sent(place)])
        }
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
        /// A swap inside your private balance (prd §1875): it is told as
        /// swapped, never as sent (§1881).
        var swap = false
        /// Its own code tells you when it ends (Privacy Pools' send, which
        /// notifies by itself): no second notification here.
        var quiet = false
        /// Max's send `part` of `parts`, one note each (2026-11-27).
        var part: Int?
        var parts: Int?

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

    private(set) var run: Run? {
        didSet { Self.announceEnd(from: oldValue, to: run) }
    }

    /// A send that just ended tells you, if you are away from Casberi (prd
    /// §1881, `Notifications.outcome`): sent or swapped, or that it did not
    /// go through and whether anything left. Said once, by when it started.
    static func announceEnd(from old: Run?, to new: Run?) {
        guard let old, old.isRunning, let new, !new.isRunning, new.started == old.started,
              !new.quiet, let ok = new.ok else { return }
        // A private send is one this device PROVES (Aztec's, Railgun's): a
        // move-in or an Aave loan is signed on Ethereum, and is no private send.
        guard new.plan.steps.contains(where: { $0.key == .proving }) else { return }
        let place = new.plan.isAztec ? "Aztec" : "Railgun"
        let id = "send:\(Int(new.started.timeIntervalSince1970))"
        // The body never repeats the headline: where it went, or where the
        // money is now.
        let sent = new.plan.steps.last?.done ?? String(localized: "Sent")
        let body = !ok ? (new.reachedNetwork ? String(localized: "Open Casberi to see where it is")
                                             : String(localized: "Nothing was sent"))
            : new.swap ? String(localized: "Inside Railgun") : sent
        let kind: NotifyKind = !ok ? .moveFailed : new.swap ? .moveSwapped : .moveSent
        Task { await Notifications.outcome(kind, id: id, place: place, body: body, mark: place) }
    }

    /// **A SEND THAT GOES ON BEHIND ITS SHEET (prd §1777, §1806).** Once
    /// every ask is answered a private send (within Aztec, or from Railgun
    /// to someone) needs nobody for a minute or two, so its sheet closes and
    /// the run moves here, where the shell's capsule draws it
    /// (`MoveStepCapsule`). Its own slot: a second move started meanwhile
    /// begins in `run` and cannot overwrite it, and its own engine's words
    /// still reach it (`received`, `mark(_:from:)`).
    private(set) var away: Run? {
        didSet { Self.announceEnd(from: oldValue, to: away) }
    }
    /// Whose engine is proving the send behind the sheet.
    private(set) var awayFrom: Source?
    /// What the toast says once it lands (prd §1806).
    private(set) var awayLanded: String?

    /// The caller starts the clock at its tap, before a cold engine has said anything.
    func begin(_ kind: Kind, plan: Plan, swap: Bool = false, quiet: Bool = false) {
        run = Run(kind: kind, plan: plan, started: .now, swap: swap, quiet: quiet)
    }

    /// Max's send `k` of `n`, from `source`'s send: behind the sheet or in it.
    func setPart(_ k: Int, of n: Int, from source: Source) {
        if source == awayFrom, var behind = away, behind.isRunning {
            behind.part = k; behind.parts = n; away = behind
        } else if var current = run, current.isRunning {
            current.part = k; current.parts = n; run = current
        }
    }

    /// `source`'s send ended well: behind the sheet if it went there.
    func finish(from source: Source) {
        if source == awayFrom, away?.isRunning == true { finishAway() } else { finish() }
    }

    /// `source`'s send failed: behind the sheet if it went there.
    func fail(_ reason: String, from source: Source) {
        if source == awayFrom, away?.isRunning == true { failAway(reason) } else { fail(reason) }
    }

    /// Move's running send leaves its sheet. One at a time: false while
    /// another is still going behind its own.
    @discardableResult
    func sendAway(from source: Source, landed: String) -> Bool {
        guard let current = run, current.kind == .move, current.isRunning else { return false }
        guard away?.isRunning != true else { return false }
        away = current
        awayFrom = source
        awayLanded = landed
        run = nil
        return true
    }

    /// Its sheet is open again: the rows there draw it, running or failed.
    /// Never over another send that is still going in the sheet.
    func bringBack() {
        guard let current = away, run?.isRunning != true else { return }
        run = current
        away = nil
        awayFrom = nil
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

    /// The toast has said it landed, or a failure was opened.
    func clearAway() {
        away = nil
        awayFrom = nil
        awayLanded = nil
    }

    /// One `engineStep` message from Aztec's engine. `plan` is the engine's
    /// own, for a send it began itself (an app's transaction in the browser).
    func received(_ body: [String: Any], plan: Plan) {
        guard let step = body["step"] as? String, let kind = Kind(rawValue: body["kind"] as? String ?? "") else { return }
        // The engine's words about a send behind its sheet go to it there
        // (prd §1777), and only its own engine's (prd §1806).
        if let behind = away, awayFrom == .aztec, behind.kind == kind, behind.isRunning {
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
    /// a Shield deposit signed by Your account) or by an engine that names
    /// itself. An engine's word goes to its send behind the sheet while one
    /// is going; a caller's is always about the sheet's own run, never the
    /// one behind it (prd §1806).
    func mark(_ key: Key, from source: Source? = nil) {
        if let source, source == awayFrom, let behind = away, behind.isRunning {
            away = Self.advanced(behind, step: key.rawValue, body: [:])
            return
        }
        guard let current = run, current.isRunning, key != .checking else { return }
        run = Self.advanced(current, step: key.rawValue, body: [:])
    }

    /// The caller's own success, of the sheet's own run.
    func finish() {
        guard let current = run, current.isRunning else { return }
        run = Self.advanced(current, step: "done", body: [:])
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
