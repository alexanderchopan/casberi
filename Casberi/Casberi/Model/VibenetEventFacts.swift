import Foundation

/// What a vibenet EVENT sheet may say, and — more to the point — what it may
/// not (prd §467, 2026-08-25).
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
    /// WHICH OF THE FOUR THINGS HAPPENED.
    ///
    /// The sheet keeps ONE anatomy across all four and swaps what fills it
    /// (prd §495, user pick of three designs). That is the whole reason this
    /// enum exists rather than the sheet branching on `concernsKey`: the
    /// mocked design answered an AUTHORIZATION beautifully and was the wrong
    /// shape for the other three — a revoked key is gone, and a lock is not
    /// about a key at all — so shipping it as drawn would have meant a second
    /// sheet for three quarters of this room's events.
    ///
    /// Read from `sourceRef`'s own segment by the caller, never from a title:
    /// the title is localized and parsing it back into data is what
    /// `MoneyReceiptSource`'s doc forbids.
    enum Kind: String, Equatable, Sendable {
        case authorized, revoked, locked, unlocking
        /// Whether this event is about a KEY as opposed to the account's lock
        /// state. Decides whether a key block is drawn at all.
        var concernsKey: Bool { self == .authorized || self == .revoked }
    }

    /// The key an event minted, when the join below could name it
    /// UNAMBIGUOUSLY — see the type's own note for why "usually nil" is the
    /// correct answer rather than a gap.
    struct Key: Equatable {
        /// "Passkey", "secp256k1 key" — `VibenetAuthenticatorKind.plainTitle`,
        /// resolved by the caller so the sheet and the Permissions list can
        /// never call one key two different things.
        let title: String
        /// The one honest clause under it, or nil where there is nothing
        /// certain to add.
        let detail: String?
        /// The actor's own short id, so the sheet names the same "…0006" the
        /// Permissions list does.
        let shortID: String
        /// Total authority. Drawn as its own mark rather than folded into the
        /// chips: §490's ruling that Admin IS the chip.
        let isAdmin: Bool
    }

    let kind: Kind
    /// The account the event concerns. Always known: every landed event stamps
    /// it on `authorHandle`.
    let account: String
    /// That account's name if it has one, else its short form. Resolved by the
    /// caller so this stays Foundation-only and so the sheet can never name an
    /// account differently from the room.
    let accountName: String
    /// **RETIRED, and deliberately not merely unread** (prd §495). This was
    /// "how many keys the account carries now", and the sheet drew it as a
    /// spec row until the user ruled the sheet is about ONE event: *"we are in
    /// activity i don't think we need to know about multiple keys because we
    /// have one item we are looking at"*. The count and the roster both answer
    /// a question about the ACCOUNT, whose own card is one tap away.
    ///
    /// Deleted rather than left in place unread, because a field nothing draws
    /// is a field nobody notices going wrong — and the next reader would find
    /// a composed, tested, plausible number with no ruling behind it.
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
    var concernsKey: Bool { kind.concernsKey }
    /// The key itself, under the same unambiguous-join rule as `permissions`
    /// — and it is deliberately the SAME join rather than a looser one, so a
    /// sheet can never name a key it could not name the permissions of.
    let key: Key?
    /// The transaction this event arrived in, which every landed event
    /// already carries inside its own `sourceRef`
    /// (`vibenet:<kind>:<txHash>:<logIndex>`).
    ///
    /// **The one verb this sheet can honestly offer.** Until §495 its only
    /// control was Share — a door onto the chain is the single thing a person
    /// can do with a key event, and the hash was in the corpus the whole time
    /// with no view asking for it. No new `Thing` field, so no CloudKit
    /// deploy.
    let txHash: String?

    /// Build the facts for one landed event.
    ///
    /// `actors` is the account's CURRENT roster; `dueAt` the event's own
    /// stored expiry. Both come from the caller because this type reads no
    /// store.
    static func compose(account: String,
                        accountName: String,
                        actors: [VibenetActor],
                        dueAt: Date?,
                        kind: Kind,
                        sourceRef: String?) -> VibenetEventFacts {
        let matched = kind.concernsKey ? matchedActor(actors: actors, dueAt: dueAt) : nil
        return VibenetEventFacts(
            kind: kind,
            account: account,
            accountName: accountName,
            expires: dueAt,
            permissions: matched?.scope.plainNames ?? [],
            key: matched.map {
                Key(title: $0.kind.plainTitle,
                    detail: $0.kind.plainDetail,
                    shortID: shortActorID($0.actorId),
                    isAdmin: $0.scope.isAdmin)
            },
            txHash: transactionHash(sourceRef))
    }

    /// The transaction out of `vibenet:<kind>:<txHash>:<logIndex>`.
    ///
    /// **Positional, and it has to be**: an actor event's segment is `actor`
    /// and a lock's is `locked`, so a prefix test would need the same list
    /// twice. Four components, the hash third, and it must LOOK like one —
    /// `0x` and 64 hex digits — because this string reaches a URL, and a ref
    /// arrives here having been through a `Thing` and a CloudKit round trip.
    /// A ref that fails the shape yields nil and the sheet simply draws no
    /// door, which is the §83 answer: no verb beats a verb that lands
    /// somewhere else.
    static func transactionHash(_ sourceRef: String?) -> String? {
        guard let sourceRef else { return nil }
        let parts = sourceRef.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == "vibenet" else { return nil }
        let hash = String(parts[2])
        guard hash.count == 66, hash.hasPrefix("0x"),
              hash.dropFirst(2).allSatisfy(\.isHexDigit) else { return nil }
        return hash
    }

    /// An actor id's tail, the way the Permissions list writes it — so one
    /// key is never "…0006" on one screen and "0x00…06" on another.
    static func shortActorID(_ actorId: String) -> String {
        guard actorId.count > 4 else { return actorId }
        return "…" + actorId.suffix(4)
    }

    /// The UNAMBIGUOUS join, and nothing looser. See the type's own note for
    /// why a best guess is refused here rather than dressed up as a match.
    ///
    /// Compared as whole seconds because `expiry` is a Keystore uint and
    /// `dueAt` is the `Date` built from it — a straight `Date ==` would work
    /// today and would start failing silently the day either side gains
    /// sub-second precision.
    static func matchedActor(actors: [VibenetActor], dueAt: Date?) -> VibenetActor? {
        guard let dueAt else { return nil }
        let want = Int(dueAt.timeIntervalSince1970)
        let matches = actors.filter { $0.expiry > 0 && Int($0.expiry) == want }
        guard matches.count == 1 else { return nil }
        return matches.first
    }

    /// The permissions alone — kept as its own entry point because the
    /// harness mutation-proves the join through it and because a caller that
    /// wants only the names should not have to know about `VibenetActor`.
    static func matchedPermissions(actors: [VibenetActor], dueAt: Date?) -> [String] {
        matchedActor(actors: actors, dueAt: dueAt)?.scope.plainNames ?? []
    }
}
