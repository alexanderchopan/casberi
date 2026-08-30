import Foundation

/// WHAT THE FAUCET ACTUALLY SAID (prd §531, 2026-08-30).
///
/// `POST faucet.hegota.ethrex.xyz/api/claim` rides
/// `IngestSupport.postJSON`, which returns nil for ANY non-200 — so the
/// measured hourly rate limit, an unreadable address and a dead host all
/// arrived at the key sheet as the same `"no answer"`. **The reason was on the
/// wire and was thrown away one layer below the person who needed it**, and
/// the sheet's own "already claimed this hour" branch — which greps that
/// string for `"429"` — could never once have been reached.
///
/// This is the pure half of the fix: given what came back, say what happened.
/// Foundation-only BY DESIGN so `scripts/hegota-tx-selftest.sh` compiles it
/// WHOLE — the claim itself cannot be exercised from a harness (it spends the
/// hourly budget), so the classification is the only part of it that can be
/// proven at all.
///
/// **The sentence lives here rather than in the sheet** for the reason the
/// broken branch above demonstrates: a refusal spelled per-screen drifts from
/// the shape it is classifying, and then a screen tests for text that cannot
/// occur.
///
/// The SIGNED half of this seat's writes is §530's, not this file's: a node's
/// refusal reaches the screen in the node's own words from
/// `HegotaSend.broadcast`. This file is the faucet alone.

// MARK: - The faucet

/// What `POST faucet.hegota.ethrex.xyz/api/claim` did.
enum HegotaFaucetVerdict: Equatable {
    case sent(hash: String)
    /// The measured, EXPECTED refusal: one claim per source IP per hour
    /// (§525). It is not a fault and must not read as one.
    case rateLimited
    /// The service answered and said no, in its own words.
    case refused(String)
    /// Nothing answered at all — offline, DNS, a dead host.
    case unreachable

    /// **Order is the whole of this function's correctness.**
    ///
    /// `status == 0` is `IngestSupport`'s transport failure and means we never
    /// heard back, which is a different sentence from any refusal. `429` is
    /// read BEFORE the body because the rate limit is the one refusal this
    /// service was measured to make on an ordinary day, and a service is free
    /// to attach whatever prose it likes to it. A body message is preferred
    /// over the bare status because the service's own words beat our guess at
    /// what a code means.
    static func of(status: Int, msg: String?, txHash: String?) -> HegotaFaucetVerdict {
        if status == 0 { return .unreachable }
        if status == 429 { return .rateLimited }

        let said = (msg ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hash = (txHash ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if said.lowercased() == "sent" {
            // A claim with no transaction is not a claim. Reporting it as one
            // would put a receipt in the corpus for money that never moved.
            return hash.isEmpty ? .refused(String(localized: "it reported no transaction")) : .sent(hash: hash)
        }
        if !said.isEmpty { return .refused(said) }
        if status == 200 { return .refused(String(localized: "it answered with nothing")) }
        return .refused(String(localized: "it answered \(String(status))"))
    }

    /// The line a screen shows. `sent` has none — a success is drawn by the
    /// screen that asked, with the hash it was handed.
    var sentence: String? {
        switch self {
        case .sent:
            nil
        case .rateLimited:
            String(localized: "Already claimed this hour \u{2014} the faucet allows one per hour, for everyone on your network. Try again later.")
        case .unreachable:
            String(localized: "Couldn't reach the faucet.")
        case .refused(let why):
            String(localized: "The faucet refused: \(why)")
        }
    }
}
