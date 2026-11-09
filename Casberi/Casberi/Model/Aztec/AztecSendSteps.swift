import Foundation
import Observation

/// **THE STEPS A SEND SHOWS (prd §1700w).** A private transaction on Aztec
/// takes about 20 seconds: checked on the phone, proved on the phone (7 to
/// 11 s), handed to Aztec, then proposed in a block. Move drew one unchanged
/// word ("Proving…") the whole time and the browser drew nothing after
/// Approve, so the wait read as stuck. The engine now says each step as it
/// happens (`tools/aztec-engine/src/steps.js`: the prover's first command,
/// the node's `sendTx`), and the screen that started the send draws it:
/// Move's three rows (`AztecStepRows`), the browser's capsule
/// (`AztecStepCapsule`). Real seconds, never a percentage it cannot know.
@MainActor
@Observable
final class AztecSendSteps {
    static let shared = AztecSendSteps()

    /// Who started the send: Move, or an app in the browser.
    enum Kind: String { case move, app }
    enum Step: Int { case checking, proving, sent }

    struct Run: Equatable {
        var kind: Kind
        var started: Date
        var provingAt: Date?
        var sentAt: Date?
        var ended: Date?
        var ok: Bool?
        /// The node took the transaction (a failure after that still reached Aztec).
        var reachedAztec = false

        var step: Step { sentAt != nil ? .sent : provingAt != nil ? .proving : .checking }
        var isRunning: Bool { ended == nil }
        /// Whole seconds from the tap to the end, for "Sent privately · 19 s".
        var total: Int? { ended.map { max(1, Int($0.timeIntervalSince(started).rounded())) } }
    }

    private(set) var run: Run?

    /// Move starts the clock at its tap, before a cold engine has said anything.
    func begin(_ kind: Kind) {
        run = Run(kind: kind, started: .now)
    }

    /// One `engineStep` message from the engine.
    func received(_ body: [String: Any]) {
        guard let step = body["step"] as? String, let kind = Kind(rawValue: body["kind"] as? String ?? "") else { return }
        if step == "checking" {
            // Move's own tap already started this run; anything else is a new send.
            if let run, run.kind == kind, run.isRunning { return }
            run = Run(kind: kind, started: .now)
            return
        }
        guard var current = run, current.kind == kind, current.isRunning else { return }
        switch step {
        case "proving": current.provingAt = current.provingAt ?? .now
        case "sent":
            current.sentAt = current.sentAt ?? .now
            current.reachedAztec = true
        case "done", "failed":
            current.ended = .now
            current.ok = step == "done"
            if body["sent"] as? Bool == true { current.reachedAztec = true }
        default: return
        }
        run = current
    }

    /// The person put a failure away.
    func clear() { run = nil }
}
