import Foundation

/// What the two devnet seats have to say to a lock screen (2026-08-29, prd §522).
///
/// **THE GATHERING HALF ONLY.** Every rule — what is news, how long it stays
/// news, what may be said about it — is `NotifyDevnet` in `NotifyPlan.swift`,
/// the Foundation-only file `scripts/notify-selftest.sh` compiles WHOLE. This
/// file reads app state and hands it over as values, and makes no decision it
/// could get wrong on its own. The split is `StripeRoom`/`PostHogRoom`'s and it
/// earns itself the same way: nothing in this repo can make a devnet reset or
/// a timelock elapse on demand, so the harness is the only proof these two
/// notifications are right.
///
/// **IT REACHES NOTHING.** Every read below is of state a foreground sweep
/// already wrote — `VibenetSeenChain`'s sticky reset, `HegotaLiveState`'s
/// genesis record, the unlock book. No request, no new `Thing` field, no
/// CloudKit deploy. The cost is a handful of `UserDefaults` reads.
@MainActor
enum DevnetNotify {

    /// Everything the two seats would tell you right now.
    ///
    /// Composed, never submitted: `WalletBackgroundRefresh.runNotifySweep` adds
    /// these to the corpus sweep's own plans and submits ONCE, so a devnet
    /// alarm competes in the same batch as every other alarm and cannot become
    /// a second buzz beside a dispute. That is also what keeps
    /// `notify-selftest.sh`'s "only one file submits" guard true.
    static func plans(now: Date = .now) -> [NotifyPlan] {
        NotifyDevnet.plans(resets: resets(), unlocks: unlocks(), now: now)
    }

    /// Housekeeping the sweep runs AFTER it has composed and submitted — never
    /// before, or an entry would be pruned in the same pass that would have
    /// announced it.
    static func prune(now: Date = .now) {
        VibenetUnlockBook.prune(now: now)
    }

    /// Why the two seats said nothing, when they said nothing — for
    /// `-notifyProbe` only.
    ///
    /// **Silence is the healthy answer here almost every day**, and it has
    /// several causes per seat that are indistinguishable from outside: nobody
    /// watching, no reset observed, an observation older than the week it stays
    /// sayable, nobody having turned unlock tracking on, or the gathering
    /// having drifted. Only the last is a bug, and a bare `devnet=0` cannot
    /// separate them — `-kalshiBookProbe`'s reason, on a feature nothing else
    /// in this repo can exercise.
    static func census() -> [String] {
        var out: [String] = []

        let vWatching = VibenetWatch.shared.addresses.count
        let vReset = VibenetSeenChain.observedReset()
        out.append("vibenet watching=\(vWatching) reset=" +
                   (vReset.map { "\($0.key) observed \($0.at)" } ?? "none observed"))

        let book = VibenetUnlockBook.all()
        out.append("vibenet tracked-unlocks=\(book.count)" +
                   (book.isEmpty ? " (nobody turned tracking on — §473's control)" : ""))
        for entry in book {
            let due = entry.unlocksAt
            out.append("vibenet unlock \(entry.name) at \(due) " +
                       (due > .now ? "still counting" : "elapsed"))
        }

        let hWatching = HegotaWatch.shared.addresses.count
        let hRestart = HegotaLiveState.observedRestart()
        out.append("hegota watching=\(hWatching) accounts=\(HegotaLiveState.shared.accounts.count) restart=" +
                   (hRestart.map { "\($0.key) observed \($0.at)" } ?? "none observed"))

        return out
    }

    // MARK: - What was reset

    private static func resets() -> [NotifyDevnet.Reset] {
        var out: [NotifyDevnet.Reset] = []
        if let seen = VibenetSeenChain.observedReset() {
            out.append(.init(seat: .vibenet, key: seen.key, observedAt: seen.at,
                             watching: VibenetWatch.shared.addresses.count))
        }
        if let seen = HegotaLiveState.observedRestart() {
            out.append(.init(seat: .hegota, key: seen.key, observedAt: seen.at,
                             watching: HegotaWatch.shared.addresses.count))
        }
        return out
    }

    // MARK: - What finished unlocking

    /// **The book is the whole gate.** An entry exists only because somebody
    /// turned tracking on (§473's control), so `tracked` is true for every one
    /// of them — and it is passed explicitly rather than defaulted, because the
    /// pure half asserts that rule and a caller silently agreeing with it is
    /// how a rule stops being tested.
    private static func unlocks() -> [NotifyDevnet.Unlock] {
        VibenetUnlockBook.all().map { entry in
            // The name is re-resolved rather than trusted: an account renamed
            // after tracking began should be announced under the name it has
            // now, not the one it had when the countdown started.
            .init(address: entry.address,
                  name: VibenetWatch.shared.name(for: entry.address) ?? entry.name,
                  unlocksAt: entry.unlocksAt,
                  tracked: true)
        }
    }
}
