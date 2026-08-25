import Foundation

/// What a vibenet EVENT sheet may say, and — more to the point — what it may
/// not (prd §464, 2026-08-25).
///
/// **The sheet it replaces said one thing and it was nothing.** A key
/// authorization opened to its title, a Share disc, and a one-row table
/// reading "From — on vibenet", which is the title's last two words wearing a
/// field label. Reported as looking bad, and it did, but the real fault is
/// that the row is not WRONG so much as EMPTY: everything a person opens a key
/// event to find out — which account, how many keys it has now, what this one
/// is allowed to do, when it dies — was already in the corpus or one lookup
/// away, and no view asked for any of it.
///
/// **The hard part is the KEY, and the honest answer is usually "we can't
/// say".** A landed event's `sourceRef` is `vibenet:<kind>:<txHash>:<logIndex>`
/// — the transaction it arrived in, never the actor it concerns — so there is
/// no id to join on. Changing that ref to carry one would re-land every event
/// already in every corpus (dedupe is by ref), which is a real cost for a
/// nicety. So the join is by EXPIRY, and it is allowed to succeed only when it
/// is UNAMBIGUOUS: the account must hold exactly one key whose expiry matches
/// the event's own `dueAt`. Two keys minted in the same block with the same
/// lifetime is a real shape — a session and its sponsor — and there the
/// permissions are simply not drawn.
///
/// That rule is the whole design. Permission chips on a key event are the most
/// believable thing this sheet can print and the least verifiable: "Send
/// anywhere" under the wrong key is a claim about what somebody can do with
/// your money, made confidently, in the one place a reader has no way to check
/// it. Silence costs a nice-looking row; a wrong chip costs the trust the room
/// is for (§83, where it is most expensive).
///
/// Foundation-only by design — no SwiftUI, no SwiftData, no store reads — so
/// `vibenet-selftest.sh` can compile it whole and mutation-test the join.
struct VibenetEventFacts: Equatable {
    /// The account the event concerns. Always known: every landed event stamps
    /// it on `authorHandle`.
    let account: String
    /// That account's name if it has one, else its short form. Resolved by the
    /// caller so this stays Foundation-only and so the sheet can never name an
    /// account differently from the room.
    let accountName: String
    /// How many keys the account carries NOW — a live fact about the account,
    /// deliberately not "how many it had when this happened", which nothing
    /// records. The sheet labels it in the present tense for that reason.
    let keysNow: Int?
    /// When the key this event minted dies. nil for a revoke, a lock, an
    /// unlock, or a key that never expires.
    let expires: Date?
    /// What that key may do — ONLY when exactly one key on the account matches
    /// the event's expiry. See the type's own note: empty is the common and
    /// correct answer, never a gap to be filled.
    let permissions: [String]
    /// Whether the event is about a key at all (authorized/revoked), as
    /// opposed to the account's lock state. Decides whether the sheet offers a
    /// key block or stays with the account.
    let concernsKey: Bool

    /// Build the facts for one landed event.
    ///
    /// `actors` is the account's CURRENT roster; `dueAt` the event's own
    /// stored expiry. Both come from the caller because this type reads no
    /// store.
    static func compose(account: String,
                        accountName: String,
                        actors: [VibenetActor],
                        dueAt: Date?,
                        concernsKey: Bool) -> VibenetEventFacts {
        VibenetEventFacts(
            account: account,
            accountName: accountName,
            keysNow: actors.isEmpty ? nil : actors.count,
            expires: dueAt,
            permissions: concernsKey ? matchedPermissions(actors: actors, dueAt: dueAt) : [],
            concernsKey: concernsKey)
    }

    /// The UNAMBIGUOUS join, and nothing looser. See the type's own note for
    /// why a best guess is refused here rather than dressed up as a match.
    ///
    /// Compared as whole seconds because `expiry` is a Keystore uint and
    /// `dueAt` is the `Date` built from it — a straight `Date ==` would work
    /// today and would start failing silently the day either side gains
    /// sub-second precision.
    static func matchedPermissions(actors: [VibenetActor], dueAt: Date?) -> [String] {
        guard let dueAt else { return [] }
        let want = Int(dueAt.timeIntervalSince1970)
        let matches = actors.filter { $0.expiry > 0 && Int($0.expiry) == want }
        guard matches.count == 1, let only = matches.first else { return [] }
        return only.scope.plainNames
    }
}
