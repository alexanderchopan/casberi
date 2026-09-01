import Foundation

/// What the Frames devnet room reads (prd §548) — the `@MainActor` half kept
/// apart from `FramesRoom`, which is Foundation-only so the harness can
/// compile its judgement whole.
enum FramesRoomSource {
    static let source = FramesIdentity.source

    @MainActor
    static func compose() -> FramesRoom.Head? {
        let live = FramesLiveState.shared
        return FramesRoom.head(
            live.accounts,
            // **ACCOUNTS ARE THEMSELVES EVIDENCE OF A READ** (Hegotá's own
            // lesson): keying only on `readAt` draws "Reading the chain…" over
            // a fully populated list after a snapshot is restored. If there
            // are accounts, a read happened; the date refines it.
            hasRead: live.readAt != nil || !live.accounts.isEmpty,
            // **THE LARGER OF THREE, and the demo floor closes a
            // chicken-and-egg.** The demo installs accounts without watching
            // anything, and the fixture is installed by the room card's own
            // task — but the card only mounts once this returns a head. With
            // `watching` at 0 the head is nil, the card never mounts, and the
            // task that would have furnished it never runs. A rowless seat
            // with a nil head is a BLACK SCREEN, which is how Hegotá reached a
            // device four times.
            watching: max(FramesWatch.shared.addresses.count,
                          live.accounts.count,
                          // This phone's own account counts as something to
                          // watch even before a sweep: on this chain it is
                          // usually the only interesting address, and a room
                          // that is black until the first read is worse than
                          // one that says it is reading.
                          FramesKey.address() == nil ? 0 : 1,
                          DemoMode.isActive ? 1 : 0))
    }

    @MainActor
    static func accounts() -> [FramesAccount] { FramesLiveState.shared.accounts }

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

    @MainActor
    static func sections() -> [FramesSection] {
        FramesRoom.sections(FramesLiveState.shared.accounts)
    }
}
