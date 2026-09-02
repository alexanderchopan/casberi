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
///
/// **IT IS THREE DEVNETS' FAUCETS NOW, ONE CASE SET (prd §553b, 2026-09-01).**
/// Frames took this type by typealias on 2026-09-01 because its faucet speaks
/// Hegotá's wire byte for byte; vibenet's does not, so it takes the same four
/// cases through a second reader (`ofDrip`) rather than a second enum. The
/// file keeps its name — what is shared is the VERDICT, and forking it per
/// chain is how three rooms start saying three different things about the same
/// four outcomes.

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

    /// **THE THIRD DEVNET'S FAUCET SPEAKS A DIFFERENT WIRE (prd §553b,
    /// 2026-09-01).**
    ///
    /// vibenet's faucet is `POST api.vibes.base.org/api/vibenet/faucet/drip`
    /// with `{"address": …}`, and its answers do not fit `of` above — MEASURED
    /// 2026-09-01, all four shapes, against the live service:
    ///
    /// - `200 {"tx_hash":"0x…","amount_wei":"…","to":"0x…"}` — the claim.
    ///   There is no `msg` at all, so `of`'s `said == "sent"` test can never be
    ///   satisfied and every successful drip would classify as a refusal.
    /// - `429 {"error":"IP rate limited. Try again in 4s."}`
    /// - `400 {"error":"Invalid address"}`
    ///
    /// So this is a second READER of one wire, not a second CLASSIFIER: the
    /// case set is shared, which is what keeps three rooms saying the same
    /// four things about their faucets. Named for the wire (`drip` is
    /// vibenet's own word for the endpoint), never for the chain — a fourth
    /// devnet speaking this shape should reuse it rather than add a third.
    ///
    /// **Order, again, is the whole of it, and it differs from `of` in one
    /// place**: an `error` in the body is read BEFORE the hash. A body
    /// carrying both is contradictory, and the safe reading of a contradiction
    /// is to refuse — reporting a send that the service also complained about
    /// would put a receipt in the corpus for money that may never have moved.
    /// The success arm additionally requires a 200: a hash inside a 500 is not
    /// a claim.
    ///
    /// **The `rateLimited` SENTENCE is not this type's to give here.** Hegotá's
    /// limit is one claim an hour (§525) and vibenet's is a ten-second cooldown
    /// on both the IP and the address (measured, `faucet/status`), so the
    /// screen that asked words its own — see `VibenetSendCard.faucetNote`.
    static func ofDrip(status: Int, error: String?, txHash: String?) -> HegotaFaucetVerdict {
        if status == 0 { return .unreachable }
        if status == 429 { return .rateLimited }

        let said = (error ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hash = (txHash ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !said.isEmpty { return .refused(said) }
        if status == 200 {
            // A claim with no transaction is not a claim.
            return hash.isEmpty ? .refused(String(localized: "it reported no transaction"))
                                : .sent(hash: hash)
        }
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
