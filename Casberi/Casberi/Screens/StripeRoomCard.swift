import SwiftUI

/// THE STRIPE ROOM'S HEAD (2026-08-04, prd §298) — what the money is doing, and
/// what needs you by when.
///
/// A heavy headline stating the whole finding as a sentence, one axis drawn
/// once, the deadlines as rows, and a stamp for the single fact that changes
/// what you'd do. What was ruled OUT for `WalletApprovalExposureCard` is out
/// here too — no coloured rail down the side of a row, no bar per row (user:
/// "it is too AI"), and **no green/red anywhere**: money arriving and money
/// challenged are the two registers §250 spent a whole ruling separating, and
/// painting a balance green would put a value judgement on the one number
/// people check most.
///
/// ## The quiet card is the point
///
/// Most accounts are fine most of the time, and the Stripe room's failure was
/// that a healthy account and a broken connection both rendered as a list of
/// old rows. So a quiet account gets the SAME body saying "Nothing needs you"
/// over its balance, rather than a second card or no card.
///
/// ## The one hue, and where it isn't spent
///
/// Stripe's indigo, from the brand table (never inlined — `DS.brandHue`'s own
/// rule). It marks the stamp on a dispute and the lead mark on the rail, and
/// nothing else. An outage does NOT get a colour: `stopped` is already the
/// headline.
///
/// ## Liveness
///
/// Stores no `Thing` — only value types out of `StripeRoom`, which
/// `StripeRoomSource` filtered at the boundary. The lookup happens at the tap,
/// in the section that owns the sheet.
///
/// Composed through `DSRoomChassis.Head` and its `DeadlineRow` (prd §745),
/// which Polar and Dodo Payments draw too.
struct StripeRoomCard: View {
    let room: StripeRoom
    /// Hands back the ITEM, not a `Thing` — the card never holds one.
    var onOpen: (StripeRoom.Item) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let mark = DS.brandHue(for: "Stripe") ?? Color.fixed("#635bff")

    var body: some View {
        DSRoomChassis.Head(
            lead: .sentence(StripeRoom.headline(room)),
            notes: [.note(StripeRoom.note(room))],
            footnotes: [.quiet(StripeRoom.coverageNote(room)),
                        .quiet(StripeRoom.staleNote(asOf: room.asOf))]) {
            // The axis is drawn only where it has something to place. A Stripe
            // account with no deadline is the ordinary case, and an empty axis
            // under a balance would be decoration claiming to be a reading.
            if !room.items.isEmpty {
                DSRoomChassis.Block {
                    rail
                    ForEach(Array(room.items.enumerated()), id: \.element.id) { index, item in
                        DSRoomChassis.DeadlineRow(
                            name: item.name,
                            stamp: StripeRoom.chip(item),
                            kind: StripeRoom.kindLine(item),
                            value: StripeRoom.value(days: item.days),
                            overdue: item.days < 0,
                            fill: Self.mark,
                            index: index) { onOpen(item) }
                    }
                }
            }
        }
    }

    /// The card's time axis, drawn by the shared component.
    ///
    /// The placement stays here on purpose: the marks go through this
    /// room's own `position`, so the room's selftest keeps asserting the
    /// arithmetic it ships with.
    private var rail: some View {
        // Hoisted out of the view builder: these change only when the
        // deadlines do, and a closure would re-run on every layout pass.
        let span = StripeRoom.span(days: room.items.map(\.days))
        let items = room.items
        return DSRunwayRail(
            marks: items.map { item in
                DSRunwayRail.Mark(id: item.id,
                                  position: StripeRoom.position(days: item.days, span: span),
                                  lead: item.id == items.first?.id)
            },
            spanLabel: StripeRoom.spanLabel(span: span),
            leadFill: Self.mark,
            reduceMotion: reduceMotion)
    }
}
