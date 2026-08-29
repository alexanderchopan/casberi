import Foundation

/// What the two devnet seats have to say to a lock screen (2026-08-29, prd §522).
///
/// **THE GATHERING HALF ONLY.** Every rule — what is news, how long it stays
/// news, what may be said about it — is `NotifyDevnet` in `NotifyPlan.swift`,
/// the Foundation-only file `scripts/notify-selftest.sh` compiles WHOLE. This
/// file reads app state and hands it over as values, and makes no decision it
/// could get wrong on its own. The split is `StripeRoom`/`PostHogRoom`'s and it
/// earns itself the same way: nothing in this repo can make a devnet reset, a
/// timelock elapse or a frame revert on demand, so the harness is the only
/// proof these three notifications are right.
///
/// **IT REACHES NOTHING.** Every read below is of state a foreground sweep
/// already wrote — `VibenetSeenChain`'s sticky reset, `HegotaLiveState`'s
/// persisted accounts, the unlock book. No request, no new `Thing` field, no
/// CloudKit deploy. The cost is a handful of `UserDefaults` reads and one walk
/// of at most five accounts' newest moves.
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
        NotifyDevnet.plans(resets: resets(), unlocks: unlocks(), frames: frames(), now: now)
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
    /// sayable, nobody having turned unlock tracking on, no frame having
    /// reverted, a reverted frame whose block was never dated, or the gathering
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

        // The frame funnel, stage by stage — a bare candidate count cannot say
        // whether the rules dropped everything or there was nothing to drop.
        var framed = 0, withFailure = 0, dated = 0
        for account in HegotaLiveState.shared.accounts {
            for move in account.framed {
                framed += 1
                guard let all = move.frames, all.contains(where: { $0.succeeded == false }) else { continue }
                withFailure += 1
                if move.timestamp != nil { dated += 1 }
            }
        }
        out.append("hegota frames read=\(framed) with-a-failure=\(withFailure) of-those-dated=\(dated)")
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

    // MARK: - What reverted

    /// A frame that reverted inside a transaction that otherwise succeeded.
    ///
    /// **Why every move here came from a transaction that SUCCEEDED.** These
    /// are reconstructed from EIP-7708 transfer logs, and a reverted
    /// transaction emits none — so a move existing is proof the transaction as
    /// a whole was accepted. That is exactly what makes a failed frame inside
    /// it worth a notification: no receipt anywhere else can say it.
    ///
    /// **STATED CEILING**, and it follows from the same fact: a frame that
    /// reverted in a transaction which moved no value at all is invisible here,
    /// because there is no log to have found it by. This under-reports and
    /// never over-reports, which is the right direction to be wrong on a lock
    /// screen.
    private static func frames() -> [NotifyDevnet.RevertedFrame] {
        let watch = HegotaWatch.shared
        var out: [NotifyDevnet.RevertedFrame] = []
        for account in HegotaLiveState.shared.accounts {
            let name = watch.name(for: account.address)
                ?? WalletStore.shortAddress(account.address)
            // **A SELF-TRANSFER LANDS AS TWO MOVES UNDER ONE HASH**, and
            // `framed` folds them by taking whichever came first — which for an
            // address paying itself can be the INCOMING leg, and would then
            // read as somebody else's transaction and be dropped. A hash with
            // any outgoing leg at all is one this address sent, so the
            // direction is decided over the whole set rather than off the one
            // move that survived the fold.
            let sentHashes = Set(account.moves.filter { !$0.incoming }
                                              .map { $0.hash.lowercased() })
            // `framed` already folds both directions of one transaction by hash
            // and drops the moves whose frames were never read — a move with
            // `frames == nil` is one the bounded receipt read did not reach,
            // not one that ran no steps.
            for move in account.framed {
                guard let all = move.frames else { continue }
                // `.some(false)` ONLY. A frame that could not be paired with a
                // receipt is drawn hollow by the room for the same reason: not
                // knowing whether a step worked is not knowing it failed.
                let failed = all.filter { $0.succeeded == false }.count
                guard failed > 0 else { continue }
                // A sender we can read must be this address. When the log named
                // none we fall back to the direction alone, which is what the
                // room does — value leaving a watched address is the ordinary
                // shape of "you sent this".
                if let sender = move.sender,
                   sender.caseInsensitiveCompare(account.address) != .orderedSame {
                    continue
                }
                out.append(.init(name: name, txHash: move.hash,
                                 failed: failed, total: all.count,
                                 incoming: !sentHashes.contains(move.hash.lowercased()),
                                 // MEASURED only — see `RevertedFrame.at`.
                                 at: move.timestamp))
            }
        }
        return out
    }
}
