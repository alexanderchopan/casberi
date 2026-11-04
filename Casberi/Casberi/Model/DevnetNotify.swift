import Foundation

/// What the devnet seat has to say to a lock screen (2026-08-29, prd §522;
/// Logos since §1084).
///
/// **THE GATHERING HALF ONLY.** Every rule — what is news, how long it stays
/// news, what may be said about it — is `NotifyDevnet` in `NotifyPlan.swift`,
/// the Foundation-only file `scripts/notify-selftest.sh` compiles WHOLE. This
/// file reads app state and hands it over as values, and makes no decision it
/// could get wrong on its own. The split is `StripeRoom`/`PostHogRoom`'s and it
/// earns itself the same way: nothing in this repo can make a devnet reset on
/// demand, so the harness is the only proof this notification is right.
///
/// **IT REACHES NOTHING.** Every read below is of state a foreground sweep
/// already wrote — the seat's stored genesis record. No request, no new
/// `Thing` field, no CloudKit deploy. The cost is a handful of `UserDefaults`
/// reads.
@MainActor
enum DevnetNotify {

    /// Everything the seat would tell you right now.
    ///
    /// Composed, never submitted: `WalletBackgroundRefresh.runNotifySweep` adds
    /// these to the corpus sweep's own plans and submits ONCE, so a devnet
    /// alarm competes in the same batch as every other alarm and cannot become
    /// a second buzz beside a dispute. That is also what keeps
    /// `notify-selftest.sh`'s "only one file submits" guard true.
    static func plans(now: Date = .now) -> [NotifyPlan] {
        NotifyDevnet.plans(resets: resets(), now: now)
    }

    /// Why the seat said nothing, when it said nothing — for `-notifyProbe`
    /// only.
    ///
    /// **Silence is the healthy answer here almost every day**, and it has
    /// several causes that are indistinguishable from outside: nobody
    /// watching, no reset observed, an observation older than the week it stays
    /// sayable, or the gathering having drifted. Only the last is a bug, and a
    /// bare `devnet=0` cannot separate them — `-kalshiBookProbe`'s reason, on a
    /// feature nothing else in this repo can exercise.
    static func census() -> [String] {
        let lReset = LogosStore.shared.resetSeen
        return ["logos watching=\(LogosStore.shared.accounts.count) reset=" +
                (lReset.map { "\($0.key) observed \($0.at)" } ?? "none observed")]
    }

    // MARK: - What was reset

    private static func resets() -> [NotifyDevnet.Reset] {
        var out: [NotifyDevnet.Reset] = []
        // Logos (prd §1084): the accounts watched, this phone's own among
        // them (Create watches it).
        if let seen = LogosStore.shared.resetSeen {
            out.append(.init(seat: .logos, key: seen.key, observedAt: seen.at,
                             watching: LogosStore.shared.accounts.count))
        }
        return out
    }
}
