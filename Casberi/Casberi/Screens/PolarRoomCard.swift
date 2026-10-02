import SwiftUI

/// THE POLAR ROOM'S HEAD (2026-08-30) — `StripeRoomCard`'s exact anatomy: a
/// heavy headline stating the whole finding as a sentence, one axis drawn once,
/// the evidence windows as rows, and a stamp for the single fact that changes
/// what you'd do. No coloured rail, no bar per row, no green/red anywhere —
/// money arriving and money challenged stay two registers.
///
/// A quiet account gets the SAME body: "Nothing needs you" over its MRR,
/// never a second card and never no card (`StripeRoomCard`'s own lesson).
///
/// Stores no `Thing` — only value types out of `PolarRoom`, filtered at the
/// boundary by `PolarRoomSource`. Composed through `DSRoomChassis.Head` and
/// its `DeadlineRow` (prd §745).
struct PolarRoomCard: View {
    let room: PolarRoom
    var onOpen: (PolarRoom.Item) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Polar's own accent — "Ether", the one colour in their otherwise
    /// monochrome system, reserved for moments that need to carry energy
    /// (polar.sh/brand). The exact role Stripe's indigo plays on its card.
    private static let mark = DS.brandHue(for: "Polar") ?? Color.fixed("#3619CC")

    var body: some View {
        DSRoomChassis.Head(
            lead: .sentence(PolarRoom.headline(room)),
            notes: [.note(PolarRoom.note(room))],
            footnotes: [.quiet(PolarRoom.coverageNote(room)),
                        .quiet(PolarRoom.staleNote(asOf: room.asOf))]) {
            if !room.items.isEmpty {
                DSRoomChassis.Block {
                    rail
                    DSRoomChassis.Rows(items: room.items) { index, item in
                        DSRoomChassis.DeadlineRow(
                            name: item.name,
                            stamp: PolarRoom.chip(item),
                            kind: String(localized: "Evidence window"),
                            value: PolarRoom.value(days: item.days),
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
        let span = PolarRoom.span(days: room.items.map(\.days))
        let items = room.items
        return DSRunwayRail(
            marks: items.map { item in
                DSRunwayRail.Mark(id: item.id,
                                  position: PolarRoom.position(days: item.days, span: span),
                                  lead: item.id == items.first?.id)
            },
            spanLabel: PolarRoom.spanLabel(span: span),
            leadFill: Self.mark,
            reduceMotion: reduceMotion)
    }
}
