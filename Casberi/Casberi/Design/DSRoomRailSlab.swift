import SwiftUI

/// THE FUSED RAIL — the account rail and the scope switcher as ONE object
/// (prd §547, 2026-09-01, user: *"what if we made the silouheet row and the
/// scope rail seem like more of a component together"*).
///
/// **The diagnosis, because the fix only makes sense against it.** These two
/// controls sat four points apart above three rooms and read as two unrelated
/// strips, and the reason was not the gap. They disagreed on all three things
/// that make a stack read as one component:
///
/// - **Bleed.** The rail ran full bleed (`leading: 0`, so its faces reach the
///   screen edge) while the switcher sat at `DSRoomChassis.inset`. Two
///   different left edges, one under the other.
/// - **Shape.** Circles with captions under them, over a glass capsule of
///   pills. Two shape languages, neither referring to the other.
/// - **Selection.** The rail said "picked" by leaving one face at full
///   strength while everything else receded to 0.7 (plus a semibold caption);
///   the switcher said it with a tint capsule that TRAVELS. Two grammars for
///   one idea, stacked.
///
/// `DSRoomChassis.railGap`/`switcherGap` are what remains of the old answer —
/// tightening the two toward each other and hoping proximity would read as
/// pairing. It is the same mistake that file's own header records about the
/// chassis: a room that has to be re-measured to look related will drift again
/// the next time either side is touched.
///
/// **So they share a container, an inset, and one selection shape**, and that
/// is the entire ruling. What each deck DOES is untouched — the rail still
/// scopes by address and keeps its own horizontal scroll, the switcher still
/// scopes by reading and keeps its travel, its dot, its re-centre and its
/// Reduce Motion branches.
///
/// **What this deliberately is NOT.** It is not a height saving: the slab lands
/// within a few points of the two strips it replaces, because §495 had already
/// squeezed the air out of the gaps between them and the parts themselves are
/// unchanged. Anyone reading this hoping it bought back a row of content should
/// read `DSRoomChassis.slabPadding`, which says the same thing in numbers. How
/// much chrome stands above a room's first row is a real and separate question.
///
/// **One deck is allowed to be absent, and both are gated by the caller.** A
/// room with one watched address has no rail (`WalletScopeRail.shows`) and a
/// room with one reading has no switcher (`WalletSection.shows`); with neither
/// there is no slab, and the caller emits nothing rather than an empty glass
/// box. Passing the gates in rather than deriving them here is deliberate —
/// each room already owns that predicate and a second copy would be free to
/// drift out of step with the sections it is describing.
struct DSRoomRailSlab<Scope: DSSectionScope, Rail: View>: View {

    /// Whether the upper deck draws at all — the room's own `…ScopeRail.shows`.
    let showsRail: Bool
    /// Whether the lower deck draws at all — the room's own `…Section.shows`.
    let showsSwitcher: Bool
    let sections: [Scope]
    let active: Scope
    var attention: Set<Scope> = []
    let onPick: (Scope) -> Void
    /// The room's own adapter, already configured. A closure rather than the
    /// rail's inputs, because the three rooms build their items from three
    /// different watch lists and folding that in here would put a
    /// `source == …` switch inside a shared control.
    ///
    /// **The caller passes `embedded: true`** — it is not forced here, so that
    /// a rail is never silently re-styled by which container it happens to be
    /// in; `railSelfTest`'s drift guard is what keeps the three honest.
    @ViewBuilder let rail: () -> Rail

    var body: some View {
        VStack(alignment: .leading, spacing: DSRoomChassis.slabDeckGap) {
            if showsRail { rail() }
            if showsSwitcher {
                DSSectionSwitcher(sections: sections,
                                  active: active,
                                  attention: attention,
                                  embedded: true,
                                  onPick: onPick)
            }
        }
        .padding(DSRoomChassis.slabPadding)
        // The one container. `dsGlass` rather than a drawn fill for the reason
        // the switcher already wore glass on its own: this is chrome floating
        // over content that scrolls under it, which is the design law's own
        // division (glass on the floating layer, never on content).
        .dsGlass(cornerRadius: DSRoomChassis.slabRadius)
    }
}
