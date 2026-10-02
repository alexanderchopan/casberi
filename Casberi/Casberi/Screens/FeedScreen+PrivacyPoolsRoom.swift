import SwiftUI
import SwiftData

// The Privacy Pools room's sections and its rows gate (prd §162), split out of
// FeedScreen.swift (prd §718). Nothing here changed but the file it lives
// in and, where another file reads a member, its access level.
extension FeedScreen {
    /// Which of the Privacy Pools room's three readings have anything to show
    /// (prd §486).
    ///
    /// **EVERY FLAG IS THE SCOPE'S OWN RENDER GATE, SPELLED THE SAME WAY** —
    /// §483's lesson, learned there from a Risk chip that opened an empty page.
    /// `shielded` is exactly the test `PrivacyPoolsRoomCard.shieldedHasContent`
    /// makes, and `review` exactly the one `reviewHasContent` makes; the card
    /// draws the untagged deposits as a legend row of their own, which is why
    /// a room with no state tags at all still earns that scope.
    ///
    /// Derived here rather than published to the shell like Wallet's,
    /// because the CARD draws this strip: there is no shell-mounted
    /// control to feed, so a published list would be state nothing reads.
    func privacyPoolsSections(_ room: PrivacyPoolsRoom) -> [PrivacyPoolsSection] {
        // Every scope, always (prd §611): the card decides figure-or-empty
        // from `shieldedHasContent`/`reviewHasContent` itself.
        PrivacyPoolsSection.present()
    }

    /// Whether the Privacy Pools room's rows draw — true for every other room
    /// the `.ledger` shape serves, so the footer and the rows can never
    /// disagree about whether there is a list to be at the bottom of.
    ///
    /// Railgun shares that shape and has no scopes, so it must never be gated
    /// by one; the source test is what keeps this room's control from reaching
    /// into its neighbour's room. Recomposing the room here is the same read
    /// the head above already makes on this pass — `PrivacyPoolsRoomSource`
    /// composes from `visible` and touches nothing else — and deriving it is
    /// what keeps the gate and the strip from describing different rooms.
    func privacyPoolsShowsRows(_ visible: [Thing]) -> Bool {
        guard source == PrivacyPoolsRoomSource.source,
              let room = PrivacyPoolsRoomSource.compose(things: visible) else { return true }
        let scopes = privacyPoolsSections(room)
        return !PrivacyPoolsSection.shows(present: scopes)
            || PrivacyPoolsSection.resolve(chrome.privacyPoolsSection, present: scopes) == .activity
    }
}
