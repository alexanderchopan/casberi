import Foundation

/// What the Frames devnet room reads (prd §548) — the `@MainActor` half kept
/// apart from `FramesRoom`, which is Foundation-only so the harness can
/// compile its judgement whole.
enum FramesRoomSource {
    static let source = FramesIdentity.source

    @MainActor
    static func compose(scope: String? = nil) -> FramesRoom.Head? {
        let live = FramesLiveState.shared
        let shown = accounts(scope: scope)
        // **A REAL NARROWING, and only then.** Scoped, the room is watching
        // exactly what it is showing, so `head.partial` must not fire over
        // addresses the person themselves set aside — "1 of 2 addresses
        // answered" under a face you deliberately picked is a caveat about
        // nothing. Every other path keeps the unscoped count VERBATIM,
        // including all three black-screen guards below, because narrowing
        // must never be a new way for the head to come back nil.
        let narrowed = !(scope ?? "").isEmpty && !shown.isEmpty
            && shown.count < live.accounts.count
        return FramesRoom.head(
            shown,
            // **ACCOUNTS ARE THEMSELVES EVIDENCE OF A READ** (Hegotá's own
            // lesson): keying only on `readAt` draws "Reading the chain…" over
            // a fully populated list after a snapshot is restored. If there
            // are accounts, a read happened; the date refines it.
            //
            // Read off the WHOLE list rather than the scoped one, or a scope
            // matching nothing would put a populated room back into "Reading
            // the chain…".
            hasRead: live.readAt != nil || !live.accounts.isEmpty,
            // **THE LARGER OF THREE, and the demo floor closes a
            // chicken-and-egg.** The demo installs accounts without watching
            // anything, and the fixture is installed by the room card's own
            // task — but the card only mounts once this returns a head. With
            // `watching` at 0 the head is nil, the card never mounts, and the
            // task that would have furnished it never runs. A rowless seat
            // with a nil head is a BLACK SCREEN, which is how Hegotá reached a
            // device four times.
            watching: narrowed ? shown.count
                : max(FramesWatch.shared.addresses.count,
                      live.accounts.count,
                      // This phone's own account counts as something to
                      // watch even before a sweep: on this chain it is
                      // usually the only interesting address, and a room
                      // that is black until the first read is worse than
                      // one that says it is reading.
                      FramesKey.address() == nil ? 0 : 1,
                      DemoMode.isActive ? 1 : 0))
    }

    /// The accounts this room is showing, after the face rail's scope.
    ///
    /// **THE SCOPE WAS DEAD UNTIL THIS** (2026-09-02). `chrome.framesScope`
    /// was written on every pick and read by NOTHING — the figure, the curve,
    /// the crown, the sponsor split and every row all took
    /// `FramesLiveState.shared.accounts` whole — so on a room watching two
    /// addresses the face lit and not one number on the screen changed. That
    /// is §83's dead control, on the very control §547 fused into the room's
    /// chrome so that it would read as load-bearing.
    ///
    /// **Scoping the ACCOUNTS rather than each drawing is what makes it one
    /// change instead of six**, and it is the stronger version: every reading
    /// in this room is derived from this array, so they cannot disagree about
    /// which addresses are on screen.
    @MainActor
    static func accounts(scope: String? = nil) -> [FramesAccount] {
        let all = FramesLiveState.shared.accounts
        guard let scope, !scope.isEmpty else { return all }
        let picked = all.filter { $0.address.caseInsensitiveCompare(scope) == .orderedSame }
        // **A SCOPE THAT MATCHES NOTHING SHOWS EVERYTHING, NEVER NOTHING.** An
        // address can leave the watch list while its face is still the
        // remembered pick, and answering that with an empty room is a blank
        // that names no cause — `FramesSection.resolve`'s own rule for a
        // remembered scope whose content has gone, one control over.
        return picked.isEmpty ? all : picked
    }

    /// What `FeedScreen.headIdentity` keys this room's head on.
    ///
    /// **Never the corpus revision.** Every other head re-keys off it, because
    /// a sweep that changes a reading also lands the row that changed it. This
    /// seat lands no row EVER, so its revision never moves — a head composed
    /// once while empty would be memoised and kept forever. Cheap by
    /// construction: three properties off an already-observed object, no fetch
    /// and no walk.
    @MainActor
    static var identity: String {
        let live = FramesLiveState.shared
        // `reached` is in the key because it changes what the room SAYS
        // without necessarily changing the account count — a sweep that found
        // the same addresses and this time got no answer must redraw.
        return "frames:\(live.accounts.count):\(live.readAt?.timeIntervalSince1970 ?? 0):\(live.reached ? 1 : 0)"
    }

    /// Which scopes the room offers.
    ///
    /// **Computed over EVERY account, never the scoped ones**, and that is a
    /// ruling rather than an oversight. Scoping this would make the strip
    /// reflow on a face tap — pick an address that has never been sponsored
    /// and the Sponsors chip vanishes, taking you back to Home because
    /// `resolve` falls through. A control that rearranges the control beside
    /// it is one nobody can aim at.
    ///
    /// So the strip describes the ROOM and the face scopes its CONTENTS. The
    /// cost is that a scoped Sponsors page can be empty, which it says in
    /// words ("Every transaction here paid its own gas") — a true statement
    /// about the address you picked, and a better answer than a chip that
    /// moves under your finger.
    @MainActor
    static func sections() -> [FramesSection] {
        FramesRoom.sections(FramesLiveState.shared.accounts)
    }
}
