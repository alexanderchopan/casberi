import SwiftUI

/// What the CardPointers room leads with (prd §420, §487): one sentence about
/// the deadlines, and the shape of them.
///
/// **It states no summed value, by ruling.** The obvious card is "$312 waiting
/// for you" and it is false twice — an offer is worth its face value only to
/// somebody who was going to spend there anyway (a CEILING, not a saving), and
/// the values do not share a unit ("$10 back on $50+" beside "20% off").
/// Nothing here is added up.
///
/// **And it states nothing the rows below already state.** §487 deleted the
/// first-deadline block (row one, restated a card higher), the card-by-card
/// tally (a count, which the module doctrine refuses as a thing) and the
/// undated footnote (now a group header sitting on the rows it describes).
/// What is left is the sentence and `WalletRunwayRail` — whether the deadlines
/// are bunched or spread, which is the one reading a sorted list cannot give
/// (§417) and the reason the head still earns its slot at all.
///
/// Holds no `Thing` and no door (liveness corollary 5) — it is handed a
/// headline and a list of dates, and every row below is its own door. Drawn
/// through `DSRoomChassis.Head` since prd §745, so §510a's missing card chrome
/// is the template's now and cannot go missing again.
struct CardPointersRoomCard: View {
    let room: CardPointers.Room

    var body: some View {
        DSRoomChassis.Head(lead: .sentence(room.headline)) {
            // Nothing at all when every offer is dateless: an empty track is a
            // parcel holding a slot, and the room's own "No end date" group is
            // already saying the true thing one screen down.
            if !room.deadlines.isEmpty {
                DSRoomChassis.Block {
                    WalletRunwayRail(dates: room.deadlines)
                        // The head's one figure box (prd §751).
                        .frame(height: DSRoomChassis.figureHeight)
                }
            }
        }
    }
}
