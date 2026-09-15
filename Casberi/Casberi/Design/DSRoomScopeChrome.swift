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
/// **THE TWO ROW BLOCKS STAND ON NOTHING (prd §757, user: "they should not have
/// cards").** Actions and Readings drew on `dsWidgetSurface`, the elevated
/// card — the one thing §749 took off every row in the app and §708 off every
/// account page. This was the last surface in the app drawing rows on plates.
/// The HEAD keeps its card, because that is what a room head is everywhere
/// else (`dsRoomHeadCard`, §745's "one surface").
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
/// **Off Home it draws the scopes as TILES, and each room mounts it UNDER the
/// scope's figure** (prd §752, user: "i don't want the app to have controls at
/// the top of the screen anywhere"). `DSScopeHeader` — a back chevron and a
/// scrolling strip of words at the top — is deleted; Home is a tile.
struct DSRoomScopeChrome<Scope: DSTileScope, Crown: View, Acts: View>: View {
    @Environment(ShellChrome.self) private var chrome

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
    @ViewBuilder let acts: (DSAccountSlot) -> Acts

    private var rest: [Scope] { sections.filter { $0 != home } }

    /// The slot the crown draws: the one in scope, else the "All" slot, else
    /// the only one.
    private var showing: DSAccountSlot? {
        accounts.first { $0.isShowing(scope) }
            ?? accounts.first { $0.id.isEmpty }
            ?? accounts.first
    }

    /// The slot the ACTIONS are for. Every room in the family draws its verbs
    /// for the "All" slot only — this device holds one key, so Send acts for
    /// that key whichever account is in scope — and a solo room has only its
    /// one slot. Resolved here so the label is never drawn over nothing.
    private var actsSlot: DSAccountSlot? {
        accounts.first { $0.id.isEmpty } ?? accounts.first
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

    @ViewBuilder
    private var content: some View {
        if active == home {
            VStack(alignment: .leading, spacing: DSRoomChassis.contentGap) {
                if let showing {
                    crown(showing)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, DS.Space.s2)
                        .dsWidgetSurface()
                        .padding(.horizontal, DSRoomChassis.inset)
                }
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
