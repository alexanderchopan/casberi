import Foundation

/// What the Ethrex Privacy room reads (prd §593) — the `@MainActor` half kept
/// apart from `PrivacyDevnetRoom`, which is Foundation-only so the harness can
/// compile its judgement whole.
enum PrivacyDevnetRoomSource {
    /// The memo key for the room head, and it MUST be a revision rather than a
    /// constant.
    ///
    /// This seat lands no `Thing`, so its corpus revision is frozen and
    /// `FeedScreen.headIdentity` would never change on its own — which is
    /// exactly how the Frames room "composed once while the demo fixture was
    /// still pouring, memoised empty, and said Reading the chain… forever".
    /// The first cut of this file made that mistake verbatim, as a
    /// `static let`.
    ///
    /// `headSlot` is in the key for a reason the two siblings do not have: the
    /// window countdown is the room's headline, so a head memoised across a
    /// slot change would keep claiming a stale number of slots remaining. The
    /// genesis is in it because a relaunch changes what the room SAYS without
    /// changing any count.
    @MainActor
    static var identity: String {
        let live = PrivacyDevnetLiveState.shared
        return "privacydevnet:\(live.accounts.count):\(live.headSlot):\(live.observedGenesis ?? "-")"
    }

    /// **NEVER RETURNS NIL WHILE THE SEAT IS CONNECTED**, which is the whole
    /// contract. This seat lands no `Thing` ever, so the head is the room's
    /// entire content: a nil here renders a BLACK SCREEN rather than an empty
    /// room, which is how the Hegotá room reached a device four times. The one
    /// nil is "not connected at all", where the room does not draw either.
    @MainActor
    static func compose(scope: String? = nil) -> PrivacyDevnetRoom.Head {
        let live = PrivacyDevnetLiveState.shared
        let watched = PrivacyDevnetWatch.shared.addresses
        // **NEVER NIL.** The seat is in `LiveRoomSources`, which tells the feed
        // not to draw the corpus-shaped empty state — so a nil here is a BLACK
        // SCREEN, not an empty room, and a deep link reaches this room whether
        // or not anything is watched. That is not hypothetical: it happened on
        // a simulator when a permission sheet swallowed the tap that would have
        // watched an address. `PrivacyDevnetRoom.head` answers `.unwatched`
        // rather than nothing.
        let shown = accounts(scope: scope)
        return PrivacyDevnetRoom.head(
            accounts: shown.map {
                PrivacyDevnetRoom.Account(nullifierCount: $0.nullifiers.count,
                                          frameCount: $0.frameCount,
                                          sponsoredCount: $0.sponsoredCount,
                                          roots: $0.roots,
                                          moveCount: $0.moves.count)
            },
            // **THE LARGER OF THREE, and the demo floor closes a
            // chicken-and-egg** (Frames' own lesson): the demo installs
            // accounts without watching anything, and the fixture is installed
            // by the room card's own task — but the card only mounts once this
            // returns a head. With `watching` at 0 the head would still be
            // non-nil here, but the count would read as zero and the sentence
            // would claim the room watches nothing.
            watching: max(watched.count, live.accounts.count, DemoMode.isActive ? 1 : 0),
            // Accounts are themselves evidence of a read — keying on a date
            // alone draws "Reading the chain…" over a populated room after a
            // snapshot is restored.
            hasRead: !live.accounts.isEmpty,
            headSlot: live.headSlot,
            wasReset: live.wasReset())
    }

    /// The accounts the room is showing, narrowed by the face rail's scope.
    ///
    /// An unmatched scope returns EVERY account rather than none: a scope that
    /// matches nothing is a stale pick, and emptying the room over it turns a
    /// populated chain into what reads as a broken one.
    @MainActor
    static func accounts(scope: String?) -> [PrivacyDevnetAccount] {
        let all = PrivacyDevnetLiveState.shared.accounts
        guard let scope, !scope.isEmpty else { return all }
        let hit = all.filter { $0.address.caseInsensitiveCompare(scope) == .orderedSame }
        return hit.isEmpty ? all : hit
    }

    /// Which scopes the strip draws, for the room's switcher.
    ///
    /// **All of them, on every address (prd §610).** The scope no longer
    /// decides — each chip carries its own empty state — so this is a
    /// forwarding function rather than a reading. Kept as one because the
    /// switcher and the deep link both ask through it, and because the day a
    /// scope earns a gate again this is where it goes.
    @MainActor
    static func sections(scope: String?) -> [PrivacyDevnetSection] {
        PrivacyDevnetSection.present()
    }
}
