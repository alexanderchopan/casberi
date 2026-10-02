import SwiftUI

/// The door from a room to its own account page, beside the room's name
/// (prd §1033; amends §937).
///
/// **Why it came back.** §937 deleted the floating corner gear and made the
/// rooms tray the one door — a hold on a mark, then Manage account. Nobody
/// finds a hold, so the room and its settings felt like two places with a
/// tray between them. The door returns, and NOT as it was: it does not float.
/// It is a plain disc in the title's row, inside the list, so it scrolls away
/// with the name and no drawing reserves a column for it — the thirty call
/// sites §937 freed stay free.
///
/// **The sliders, never the gear.** `gearshape` is the app's own Settings in
/// the tray's You row; this is ONE account's page, so it wears the glyph the
/// deleted corner door wore. Two glyphs, two meanings.
///
/// **Raised, not pushed** (`HomeRoute.openAccount`): the account page rises
/// over the room it belongs to, and pulling it down leaves you where you
/// were. The wallet room's pages still push, as their Connect does.
///
/// Absent, never disabled, when the room has no seat to open (All, Notes, an
/// offer with no page): the honesty law's "no dead controls" (§83).
struct RoomAccountDoor: View {
    /// The room's source — always a real source by the time a room draws
    /// (`MainSurface.go(to:)` resolves a category first).
    let source: String

    @Environment(BridgeStore.self) private var store
    @Environment(HomeRoute.self) private var route

    /// The seat registered for this room, matched on the source name or its
    /// offer name (the two differ for an aliased seat: "Privacy Pools" lands
    /// rows, "0xBow Privacy Pools" is the seat).
    private var seat: BridgeApp? { Self.seat(forSource: source, in: store) }

    private var destination: BridgeRouter.Destination? {
        Self.destination(forSource: source, in: store)
    }

    static func seat(forSource source: String, in store: BridgeStore) -> BridgeApp? {
        let offerName = BridgeCatalog.seatName(forSource: source)
        return store.bridges.first { $0.name == source || $0.name == offerName }
    }

    /// A connected seat opens its own page (`destination(forID:)`, which also
    /// gives the demo's unrouted seats their detail screen); a room with no
    /// seat yet opens what its Connect would. Shared with the rooms tray,
    /// whose app circles open these same pages once their room has folded
    /// into a merged one (prd §1048b).
    static func destination(forSource source: String, in store: BridgeStore) -> BridgeRouter.Destination? {
        if let seat = seat(forSource: source, in: store) { return BridgeRouter.destination(forID: seat.id) }
        guard let offer = BridgeCatalog.offer(forSource: source) else { return nil }
        return BridgeRouter.destination(forOffer: offer.name)
    }

    private var needsYou: Bool { seat?.status == .attention }

    var body: some View {
        if let destination {
            Button {
                DSHaptic.selection()
                route.openAccount(destination)
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .dsGlyph(.title)
                    // A broken seat's door wears the attention hue — a glyph
                    // keeps the hue, a word takes the ink (§1004).
                    .foregroundStyle(needsYou ? DS.attention : DS.textSecondary)
                    .frame(width: DS.Face.seat, height: DS.Face.seat)
                    .background(Circle().fill(DS.fillFaint))
                    .dsTapTarget(Circle())
            }
            .buttonStyle(PressSpring())
            .dsHover()
            .accessibilityLabel(needsYou
                ? Text("\(BridgeCatalog.seatName(forSource: source)) account — needs your attention")
                : Text("\(BridgeCatalog.seatName(forSource: source)) account"))
        }
    }
}
