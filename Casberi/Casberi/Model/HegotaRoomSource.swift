import Foundation

/// The Ethrex Hegotá room's head, composed from BRIDGE STATE rather than from
/// landed rows.
///
/// **This head reads no `Thing` at all**, the `RadicleRoomSource` /
/// `ASCRoomSource` shape, and for the same reason those two give: its subject
/// is chain state, not news. Nothing this seat learns is a thing a screenshot
/// would reference or a search would want — a devnet address's balance is test
/// ETH, its coins are unspent outputs that change without an event, and its
/// transfers are already drawn as the room's own rows. So the sweep lands
/// nothing in the corpus and this composes off `HegotaLiveState`.
///
/// The consequence worth stating: the room is EMPTY of rows by construction, so
/// this card is the whole room. That is why it carries every scope rather than
/// heading a list.
enum HegotaRoomSource {
    static let source = HegotaIdentity.source

    @MainActor
    static func compose() -> HegotaRoom.Head? {
        HegotaRoom.head(HegotaLiveState.shared.accounts,
                        // **ACCOUNTS ARE THEMSELVES EVIDENCE OF A READ.**
                        // Keying only on `readAt` meant a snapshot restored
                        // from disk — or one written before that timestamp was
                        // persisted — drew "Reading the chain…" above a fully
                        // populated list. If there are accounts, a read
                        // happened; the date refines it, it is not the proof.
                        hasRead: HegotaLiveState.shared.readAt != nil
                                 || !HegotaLiveState.shared.accounts.isEmpty,
                        // The larger of the two ON PURPOSE. The demo installs
                        // accounts without adding to the watch list (nothing is
                        // really being watched), so keying on the watch list
                        // alone made `head` return nil there — and for a seat
                        // that lands no rows, a nil head is a BLACK SCREEN
                        // rather than a quiet one. Reported from a device.
                        // **THE DEMO NEEDS A FLOOR OF 1, and this is the line
                        // that closes a chicken-and-egg.** The fixture is
                        // installed by the room card's own `.task`, and the
                        // card only mounts when this returns a head — so in a
                        // demo, where nothing is genuinely watched and no sweep
                        // has run, `watching` was 0, the head was nil, the card
                        // never mounted and the task that would have furnished
                        // it never ran. A rowless seat with a nil head is a
                        // BLACK SCREEN, which is exactly how it was reported.
                        watching: max(HegotaWatch.shared.addresses.count,
                                      HegotaLiveState.shared.accounts.count,
                                      DemoMode.isActive ? 1 : 0))
    }

    @MainActor
    static func accounts() -> [HegotaAccount] { HegotaLiveState.shared.accounts }

    /// What `FeedScreen.headIdentity` keys this room's head on.
    ///
    /// Every other head re-keys off the corpus revision, because a sweep that
    /// changes a reading also lands the row that changed it. This seat lands no
    /// row, so its revision never moves and its head would be memoised once —
    /// while empty — and kept forever. Cheap by construction: two properties off
    /// an already-observed object, no fetch, no walk.
    @MainActor
    static var identity: String {
        let live = HegotaLiveState.shared
        // The genesis verdict is in the key because it changes what the room
        // SAYS without necessarily changing either of the other two — accepting
        // a restart resets them together, but a verdict arriving from a sweep
        // that found the same account count would otherwise be memoised away.
        return "hegota:\(live.accounts.count):\(live.readAt?.timeIntervalSince1970 ?? 0):\(live.genesis.rawValue)"
    }

    @MainActor
    static func sections() -> [HegotaSection] {
        HegotaRoom.sections(HegotaLiveState.shared.accounts)
    }
}
