import SwiftUI

/// WHAT A WALLET-FAMILY ROOM WEARS INSTEAD OF A BAR (prd §744, 2026-09-15).
///
/// One type, five rooms, and deliberately shaped as a DROP-IN for
/// `DSRoomRailSlab`: the same `sections` / `active` / `attention` / `onPick`
/// on the reading side and the same `scope` / `onPick` on the account side.
/// The rooms disagree about almost everything else — Vibenet's chrome lives
/// inside its card and Hegotá's is four `FeedScreen` sections; Frames mounts
/// its send card inside the list and the Privacy devnet mounts its own as a
/// section — so a component that asked them to agree about mounting would
/// convert none of them. This asks them to agree about ARGUMENTS.
///
/// **What it draws, and it is one of two things.**
///
/// On HOME: the account deck (`DSAccountDeck`), each card carrying the room's
/// crown and the room's acts, and under it the readings as door rows
/// (`DSScopeRows`). Home has no list of its own any more — the rows ARE the
/// list, which is what makes this a deletion rather than another strip.
///
/// Off home: the scope header (`DSScopeHeader`) — the reading's name at the
/// room's title rung, the rest beside it, back to Home. The room's own figure
/// and list are untouched underneath.
///
/// **`home` is a parameter, not a convention.** Every one of the five scope
/// enums calls its first case `home`, and none of them can say so through
/// `DSSectionScope` without that protocol growing a case it has no business
/// knowing about. The caller passes it; `rest` is everything else in the
/// room's own order.
struct DSRoomScopeChrome<Scope: DSSectionScope, Crown: View, Acts: View>: View {

    /// Every reading the room publishes, in its own order, INCLUDING home.
    let sections: [Scope]
    let active: Scope
    /// Which of them is the room itself.
    let home: Scope
    var attention: Set<Scope> = []
    let onPick: (Scope) -> Void

    /// The accounts, deck-shaped. Empty is legal and means the room has no
    /// account to page (a devnet before its key): the deck is skipped and the
    /// crown and acts draw on their own card, which is how the "Create
    /// account" tile ends up being the whole card.
    let accounts: [DSAccountSlot]
    /// The account showing — nil is "All".
    let scope: String?
    let onPickAccount: (String?) -> Void

    /// What the scope holds right now, in the room's words. An empty scope
    /// answers with its own `emptyHeadline`, which is how §611's promise —
    /// every scope present, every empty scope explaining itself — is kept
    /// BEFORE the tap rather than after it.
    let reading: (Scope) -> String?
    @ViewBuilder let crown: (DSAccountSlot) -> Crown
    @ViewBuilder let acts: (DSAccountSlot) -> Acts

    /// The readings minus home, in the room's order — the rows on Home and the
    /// words in the header off it, from one list so the two can never disagree.
    private var rest: [Scope] { sections.filter { $0 != home } }

    /// The card a room draws when it has no account to page. One card, no
    /// scroll, and the same anatomy — a devnet before its key still has a
    /// venue to name and a tile to offer, and a deck of one that cannot be
    /// paged is a deck pretending.
    private var soloSlot: DSAccountSlot? {
        accounts.isEmpty ? nil : accounts.first
    }

    var body: some View {
        if active == home {
            VStack(alignment: .leading, spacing: DSRoomChassis.contentGap) {
                if accounts.count > 1 {
                    DSAccountDeck(slots: accounts, scope: scope, onPick: onPickAccount) { slot in
                        cardBody(slot)
                    }
                } else if let solo = soloSlot {
                    // A deck of one pages nowhere, so it is drawn as the card
                    // it is. The room keeps its head, its crown and its acts —
                    // only the scroll is absent, because there is nothing to
                    // scroll to.
                    DSAccountDeck(slots: [solo], scope: scope, onPick: onPickAccount) { slot in
                        cardBody(slot)
                    }
                }
                DSScopeRows(sections: rest, attention: attention,
                            reading: reading, onPick: onPick)
            }
        } else {
            DSScopeHeader(sections: rest, active: active, attention: attention,
                          onBack: { onPick(home) }, onPick: onPick) {
                accountLine
            }
        }
    }

    @ViewBuilder
    private func cardBody(_ slot: DSAccountSlot) -> some View {
        VStack(alignment: .leading, spacing: DSRoomChassis.contentGap) {
            crown(slot)
            acts(slot)
        }
    }

    /// Which account this reading is OF, under the header — the one fact the
    /// deck was carrying that a pushed scope would otherwise lose. Nothing at
    /// all when there is one account or none: a line naming the only account
    /// there is says nothing the room does not already say.
    @ViewBuilder
    private var accountLine: some View {
        if accounts.count > 1 {
            let showing = accounts.first { $0.isShowing(scope) } ?? accounts.first
            if let showing {
                HStack(spacing: DS.Space.s2) {
                    HStack(spacing: -(DS.Face.row / 3.5)) {
                        ForEach(Array(showing.faces.prefix(2).enumerated()), id: \.offset) { pair in
                            RailFace(face: pair.element, size: DS.Face.row)
                        }
                    }
                    Text(showing.sub.map { "\(showing.name) · \($0)" } ?? showing.name)
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
        }
    }
}
