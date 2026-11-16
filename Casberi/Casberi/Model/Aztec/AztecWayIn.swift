import Foundation

/// **THE WAY INTO AZTEC, AS STEPS (prd §1820).** Shield moves money into
/// Aztec only from a wallet with a Human Passport score (20, no ID). Your
/// account is a Safe and can never hold one, so the score is your
/// co-signer's (§1720). Move said "Shield needs a score of 20 · Yours 0"
/// and offered Human Passport, where a Safe can link nothing: someone with
/// no co-signer had no way in and was not told. Now the move says its three
/// steps, and the act is always the next one.
///
/// Pure: `shield-bridge-selftest.sh` compiles this file alone.
enum AztecWayIn {
    enum Step: Int, CaseIterable, Equatable {
        case coSigner, score, send
    }

    enum Phase: Equatable { case done, next, later }

    /// The step to take now.
    static func next(coSigner: String?, score: Int?, threshold: Int) -> Step {
        guard coSigner != nil else { return .coSigner }
        guard let score, score >= threshold else { return .score }
        return .send
    }

    static func phase(_ step: Step, coSigner: String?, score: Int?, threshold: Int) -> Phase {
        let now = next(coSigner: coSigner, score: score, threshold: threshold)
        return step.rawValue < now.rawValue ? .done : step == now ? .next : .later
    }

    /// The score a step names: the co-signer's when there is one (only it
    /// can hold a score); your account's otherwise, which is always 0.
    static func shownScore(coSignerScore: Int?, accountScore: Int) -> Int {
        coSignerScore ?? accountScore
    }

    /// "12 of 20" while short; the score alone once it is enough ("24", never "24 of 20").
    static func progress(_ score: Int, of threshold: Int) -> String {
        score >= threshold ? "\(score)" : String(localized: "\(score) of \(threshold)")
    }

    /// How often the page's score is asked while Human Passport is open.
    static let pollSeconds: UInt64 = 8
}
