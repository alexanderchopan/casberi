import SwiftUI

/// THE WALLET FAMILY'S HOME — one surface, in reading order (prd §750,
/// 2026-09-15, user: "look these all look like different apps each component.
/// they don't blend together in any way, and now we have the accounts faces
/// at the top it's totally confusing").
///
/// §747 put the account at the TOP as a card you page, with the crown and the
/// verbs inside it, and the readings as door rows under it. Shipped in 589 it
/// read as four apps: a deck card, verb slabs at `price40`, a grouped list,
/// the dock — four radii, four type scales, three insets — and the two grey
/// faces over the figure looked like a contacts header where every other room
/// puts its head.
///
/// This is the same facts on the app's own grammar, top to bottom:
///
///   1. **the head** — the room's crown for the account in scope (the figure,
///      the chart, its range chips), on the head surface every other room got
///      in §745;
///   2. **the account rail** — NOT drawn here. The room publishes its accounts
///      to `ShellChrome.accountRail` and the shell draws them as a
///      `FaceScopeRail` above the dock, where the Farcaster and Bluesky rails
///      already sit (user, same day: "like on farcaster and bluesky"), so a
///      pick survives a scroll and the head keeps one job;
///   3. **Actions** — the room's verbs as rows under one label, the way §746
///      made every verb a row;
///   4. **Readings** — `DSScopeRows` under its own label (user: "it can't all
///      be actions"). Not "Test": the devnets are test networks, but the
///      Wallet room holds real money and the label is shared.
///
/// **NOTHING ON HOME STANDS ON A PLATE (prd §757, then §758).** Actions and
/// Readings drew on `dsWidgetSurface`, the elevated card — the one thing §749
/// took off every row in the app and §708 off every account page — and §757
/// took it off both, keeping the head's on the grounds that a head card is what
/// every room draws. A day later the user said the same thing about a room head
/// ("again here, we don't want cards that are like this"), so the head's plate
/// went too, here and in `dsRoomHeadBlock` for every other room. Home is three
/// blocks of content on the page, separated by air.
///
/// The rail truncates a long name at its 66pt slot, which was §747's first
/// complaint. The head names the picked account in FULL beside the figure
/// (§450's caption, drawn by each room's crown), so the rail's word is a
/// label and the head is the name — the §495 pairing, not a second truncation.
///
/// Every room in the family (Wallet, Vibenet, Hegotá, Frames, the Privacy
/// devnet) passes the same arguments it passed §747's chrome; only this file
/// decides where they are drawn.
///
/// **The section TILES are on every page** (prd §752, §752b, user: "i don't
/// want the app to have controls at the top of the screen anywhere", then "i
/// think they should always show"). On Home they sit under the head, above
/// Actions and the Readings rows; in a section each room mounts this chrome
/// UNDER the section's figure and it draws the tiles alone. Home is a tile.
struct DSRoomScopeChrome<Scope: DSTileScope, Crown: View, Figure: View, Acts: View>: View {
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The natural height the active figure reported (`DSBarFigure`), or nil.
    @State private var fitted: CGFloat?
    /// The shortest a fitted box stands: a reading and one bar.
    static var fittedFloor: CGFloat { 132 }

    /// The room this chrome stands in — the key the published rail carries.
    let source: String
    let sections: [Scope]
    let active: Scope
    let home: Scope
    var attention: Set<Scope> = []
    let onPick: (Scope) -> Void

    let accounts: [DSAccountSlot]
    let scope: String?
    let onPickAccount: (String?) -> Void

    let reading: (Scope) -> String?
    @ViewBuilder let crown: (DSAccountSlot) -> Crown
    /// The section's own drawing, off Home. Drawn HERE, in the box the crown
    /// takes on Home, never as a sibling `Section` above the chrome (prd §765).
    @ViewBuilder let figure: (Scope) -> Figure
    @ViewBuilder let acts: (DSAccountSlot) -> Acts

    private var rest: [Scope] { sections.filter { $0 != home } }

    /// The slot the crown draws: the one in scope, else the "All" slot, else
    /// the only one.
    private var showing: DSAccountSlot? {
        accounts.first { $0.isShowing(scope) }
            ?? accounts.first { $0.id.isEmpty }
            ?? accounts.first
    }

    /// The slot the ACTIONS are for: **the page you are on (prd §774, user:
    /// "they may do it from home but may also from the account, but make it
    /// consistent").** Until §774 every room drew its verbs for the "All" slot
    /// whichever account was in scope, on the reasoning that the device held
    /// one key — false once a phone can hold several. The room's `acts`
    /// closure decides what a slot gets, and every room in the family gives
    /// EVERY page its room-level verb (Create account, Follow address), so the
    /// label is never drawn over nothing.
    private var actsSlot: DSAccountSlot? { showing }

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
            if active == home {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    DSScopeTiles(sections: sections, active: active,
                                 attention: attention, onPick: onPick)
                    accountLine
                }
                .padding(.horizontal, DSRoomChassis.inset)
                if let actsSlot {
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        WalletSectionLabel(title: String(localized: "Actions"))
                            .padding(.horizontal, DSRoomChassis.inset)
                        // NO PLATE (prd §757) — see `DSScopeRows`. The acts and
                        // the readings are one grammar, so they lose the card
                        // together or the two blocks read as different kinds of
                        // thing, which is §750's own complaint.
                        VStack(spacing: 0) {
                            acts(actsSlot)
                        }
                    }
                    .padding(.horizontal, DSRoomChassis.inset)
                }
                if !rest.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        WalletSectionLabel(title: String(localized: "Readings"))
                            .padding(.horizontal, DSRoomChassis.inset)
                        DSScopeRows(sections: rest, attention: attention,
                                    reading: reading, onPick: onPick)
                    }
                    .padding(.horizontal, DSRoomChassis.inset)
                }
            } else {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    DSScopeTiles(sections: sections, active: active,
                                 attention: attention, onPick: onPick)
                    accountLine
                }
                .padding(.horizontal, DSRoomChassis.inset)
            }
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
            // **THE BOX FITS A BAR FIGURE (prd §936).** A figure that reports
            // its natural height (`DSBarFigure`) gets a box that height, with
            // a floor; everything else keeps `visualSlot`. The report is of
            // intrinsic content, so following it cannot loop.
            .frame(height: fitted.map { min(DSRoomChassis.visualSlot, max(Self.fittedFloor, $0)) }
                   ?? DSRoomChassis.visualSlot)
            .overlay(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    if active == home {
                        if let showing { crown(showing) }
                    } else {
                        figure(active)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onPreferenceChange(DSFigureHeight.self) { height in
                    withAnimation(reduceMotion ? nil : DS.Motion.standard) { fitted = height }
                }
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
    /// **THE ACCOUNT PICKER IS A MENU UNDER THE TILES (prd §936).** The line
    /// named the account on screen and changed nothing; the faces capsule in
    /// the band did the picking, and with the dock gone that capsule was the
    /// last piece of it on the phone (user: "it's still here on wallet").
    /// Apple's answer to "which one of several" is a pull-down: the faces and
    /// the name, a chevron, and every account in the menu, "All" first. It
    /// stands on Home and every section alike.
    private var accountLine: some View {
        if accounts.count > 1 {
            let showing = accounts.first { $0.isShowing(scope) } ?? accounts.first
            if let showing {
                Menu {
                    ForEach(accounts) { slot in
                        Button {
                            DSHaptic.selection()
                            withAnimation(DS.Motion.standard) {
                                onPickAccount(slot.id.isEmpty ? nil : slot.id)
                            }
                        } label: {
                            if slot.isShowing(scope) {
                                Label(slot.name, systemImage: "checkmark")
                            } else {
                                Text(slot.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: DS.Space.s2) {
                        HStack(spacing: -(DS.Face.row / 3.5)) {
                            ForEach(Array(showing.faces.prefix(2).enumerated()), id: \.offset) { pair in
                                RailFace(face: pair.element, size: DS.Face.row)
                            }
                        }
                        Text(showing.name)
                            .dsText(.label12)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .dsGlyph(.caption)
                            .foregroundStyle(DS.textTertiary)
                    }
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(String(localized: "Account: \(showing.name)")))
            }
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
}

extension DSAccountSlot {
    func isShowing(_ scope: String?) -> Bool {
        guard let scope, !scope.isEmpty else { return id.isEmpty }
        return id.caseInsensitiveCompare(scope) == .orderedSame
    }
}
