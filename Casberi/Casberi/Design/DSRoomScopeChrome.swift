import SwiftUI

/// THE WALLET FAMILY'S CHROME — the box, the tiles, the account menu, in that
/// order on every page (prd §1039, 2026-10-01, user approving the merge
/// mockup; it amends §750's "head, Actions, Readings").
///
/// **Every other room's anatomy: box · tiles · "whose" menu · list.** §750
/// gave Wallet, Frames and Logos a Home of their own — the head, then an
/// Actions block of verb rows, then an Overview of `DSScopeRows` that said the
/// tiles a second time as rows, and NO list. The merge deletes both blocks:
///
///   1. **the box** — the room's crown on Home (the figure, the chart, its
///      range chips), the section's figure everywhere else, one fixed box
///      (prd §765, §936);
///   2. **the tiles** — the scopes, Home first then A–Z, and the room's VERBS
///      last, A–Z among themselves (`DSScopeTiles.alphabetical`): Follow in
///      the Wallet, Create · Send · Top up in Frames, Explorer in Logos. A
///      verb tile acts and never lights — GitHub's Watch (prd §1031);
///   3. **the account menu** (`DSScopeMenu`, prd §936) — the pick the deleted
///      Accounts tiles duplicated;
///   4. **the list** — the room's own, drawn by the room under this chrome:
///      on Home, what moved (the deleted Activity tile's list).
///
/// **The verbs are per PAGE (prd §774).** The room hands in the verbs for the
/// account showing; Frames keeps Create alone on a stranger's page.
///
/// **NOTHING STANDS ON A PLATE (prd §757, §758).** The box is the head
/// template's well; the tiles are the grid's own flat fills.
///
/// The account rail is NOT drawn here: the room publishes its accounts to
/// `ShellChrome.accountRail`, and the shell draws them where the iPad and Mac
/// rail stands (§750, §936).
struct DSRoomScopeChrome<Scope: DSTileScope, Crown: View, Figure: View>: View {
    @Environment(ShellChrome.self) private var chrome

    /// The room this chrome stands in — the key the published rail carries.
    let source: String
    let sections: [Scope]
    /// The room's verbs for the page showing, drawn as the LAST tiles (prd
    /// §1039). The room's `onPick` receives them and acts; none ever lights.
    var verbs: [Scope] = []
    let active: Scope
    let home: Scope
    var attention: Set<Scope> = []
    /// Scopes with nothing for the account picked, drawn in place and not
    /// taking a tap (`DSScopeTiles.inert`, prd §1078).
    var inert: Set<Scope> = []
    let onPick: (Scope) -> Void

    let accounts: [DSAccountSlot]
    let scope: String?
    let onPickAccount: (String?) -> Void

    @ViewBuilder let crown: (DSAccountSlot) -> Crown
    /// The section's own drawing, off Home. Drawn HERE, in the box the crown
    /// takes on Home, never as a sibling `Section` above the chrome (prd §765).
    @ViewBuilder let figure: (Scope) -> Figure

    /// The slot the crown draws: the one in scope, else the "All" slot, else
    /// the only one.
    private var showing: DSAccountSlot? {
        accounts.first { $0.isShowing(scope) }
            ?? accounts.first { $0.id.isEmpty }
            ?? accounts.first
    }

    var body: some View {
        content
            .onAppear { publish() }
            .onChange(of: accounts) { _, _ in publish() }
            .onChange(of: scope) { _, _ in publish() }
            .onDisappear {
                if chrome.accountRail?.source == source { chrome.accountRail = nil }
            }
    }

    private func publish() {
        let rail = ShellChrome.AccountRail(source: source, slots: accounts,
                                           scope: scope, onPick: onPickAccount)
        if chrome.accountRail != rail { chrome.accountRail = rail }
    }

    /// **THE TILES LAND AT ONE HEIGHT ON EVERY PAGE, BY CONSTRUCTION (prd §765,
    /// user: "when you click the buttons home activity etc they don't maintain
    /// their position … the bar moves up or down").** §752b claimed it from
    /// "the head and every figure share the 300pt slot", which was true of the
    /// boxes and false of the tiles: Home drew its crown INSIDE this row
    /// (padding, then `contentGap`), while every section drew its figure as a
    /// separate `Section` ABOVE it with its own row insets — 0 in Frames and
    /// Hegotá, `s3` on top in Wallet, `s4` below in the Privacy devnet, `railGap`
    /// in Vibenet — plus whatever spacing the `List` gives a section. Five rooms,
    /// five offsets, and none of them Home's. So the lead is ONE box in ONE place
    /// for both arms: the crown on Home, the section's figure everywhere else,
    /// the same frame, padding and gap before the tiles.
    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: DSRoomChassis.contentGap) {
            lead
            // **THE TILES, THEN THE MENU, ON EVERY PAGE (prd §1039).** Home
            // drew Actions and the Overview rows under these until the merge;
            // the room's own list follows the chrome now, as in every room.
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                DSScopeTiles(sections: sections + verbs, active: active,
                             attention: attention, verbs: Set(verbs),
                             inert: inert, onPick: onPick)
                accountLine
            }
            .padding(.horizontal, DSRoomChassis.inset)
        }
    }

    /// The crown on Home, the section's figure off it — one fixed box either
    /// way. The `Color.clear` holds the box open when neither draws: a frame on
    /// a builder that produced nothing has no layout presence (Vibenet's
    /// measured 575 → 355pt jump), and the tiles would ride up by the slot.
    /// NO PLATE (prd §758) — the head is content, like the rows under it.
    ///
    /// **THE BOX IS THE CHASSIS', NEVER THE FIGURE'S (2026-09-15).** The drawing
    /// is an OVERLAY on a fixed box rather than a sibling in a `ZStack`: a
    /// `ZStack` takes its widest child's width, so a figure even a point wider
    /// than the well widened the well, and the tiles and account line under it
    /// with it. It happened twice in one day — the NFT grid ran the tiles to
    /// both screen edges, and the Snapshots ring moved them by a point. An
    /// overlay is proposed the box's size and can never report a size back.
    private var lead: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            // **THE BOX NEVER MOVES THE TILES (prd §936, reversed the same day;
            // user: "your buttons move positions they should not be doing
            // that").** A bar figure's box followed its content for one build
            // and the tiles under it jumped on every scope change. The box is
            // `visualSlot`, always.
            .frame(height: DSRoomChassis.visualSlot)
            .overlay(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    if active == home {
                        if let showing { crown(showing) }
                    } else {
                        figure(active)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        // THE WELL (prd §766), the head template's own. The box is still
        // `leadHeight` — the slot and its `s2` — so no figure loses a point of
        // height; the drawing stands `s3` inside the well's edge, at the rows'
        // column, and gives up that width instead. The tiles below keep
        // `inset`, which is now the well's edge.
        .padding(.horizontal, DS.Space.s3)
        .padding(.vertical, DS.Space.s2)
        .dsWell(cornerRadius: DS.Radius.widget)
        .padding(.horizontal, DSRoomChassis.inset)
    }

    @ViewBuilder
    /// **THE PICKER MOVED TO THE TITLE ROW (prd §1066)**: a glass pill beside
    /// the room's name, drawn by `FeedScreen.titleAccountsPill` from the rail
    /// this chrome publishes. What stays under the tiles is the one thing the
    /// pill cannot say: a picked address, one tap from copying. A slot id is
    /// the address; "All" is "" and an app (`seat:`, prd §1048b) is not an
    /// address, so neither has one to copy.
    private var accountLine: some View {
        if let showing = accounts.first(where: { $0.isShowing(scope) }),
           !showing.id.isEmpty, !RoomAccounts.isSeat(showing.id) {
            CopyAddressButton(address: showing.id)
        }
    }
}

/// One account in a room of the wallet family: what the rail captions it, what
/// the pushed header names it, and the face it wears. `id` is the address, or
/// `""` for "All".
struct DSAccountSlot: Identifiable, Equatable {
    let id: String
    let name: String
    let sub: String?
    let faces: [FaceScopeRail.Item.Face]
    /// The picker's section for this slot, nil for none. A devnet splits "On
    /// this phone" from "Watching"; a room that sets none draws a flat menu.
    var group: String? = nil
}

extension DSAccountSlot {
    /// **THE PICKER'S ON THIS PHONE / WATCHING SECTIONS (prd §964)** for a
    /// devnet, where this phone holds keys: "All" stays first and ungrouped,
    /// this phone's accounts follow, then the ones you watch.
    static func groupedByPhone(_ slots: [DSAccountSlot],
                               onPhone: (String) -> Bool) -> [DSAccountSlot] {
        let accounts = slots.filter { !$0.id.isEmpty }.map { slot -> (DSAccountSlot, Bool) in
            var slot = slot
            let held = onPhone(slot.id)
            slot.group = held ? String(localized: "On this phone") : String(localized: "Watching")
            return (slot, held)
        }
        return slots.filter { $0.id.isEmpty }
            + accounts.filter { $0.1 }.map { $0.0 }
            + accounts.filter { !$0.1 }.map { $0.0 }
    }

    func isShowing(_ scope: String?) -> Bool {
        guard let scope, !scope.isEmpty else { return id.isEmpty }
        return id.caseInsensitiveCompare(scope) == .orderedSame
    }
}
