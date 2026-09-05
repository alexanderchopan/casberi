import SwiftUI

/// THE POLAR ROOM'S HEAD (2026-08-30) — `StripeRoomCard`'s exact anatomy: a
/// kicker in the card's one hue, a heavy headline stating the whole finding as
/// a sentence, one axis drawn once, ranked rows, and a chip for the single
/// fact that changes what you'd do. No coloured rail, no bar per row, no
/// green/red anywhere — money arriving and money challenged stay two
/// registers, and painting a revenue reading green would put a value
/// judgement on the one number people check most.
///
/// A quiet account gets the SAME body: "Nothing needs you" over its MRR,
/// never a second card and never no card (`StripeRoomCard`'s own lesson).
///
/// Stores no `Thing` — only value types out of `PolarRoom`, filtered at the
/// boundary by `PolarRoomSource`. FLAT BY LAW, the render-depth lesson: a
/// plain VStack, no generic `Widget`/`Row` mount.
struct PolarRoomCard: View {
    let room: PolarRoom
    var onOpen: (PolarRoom.Item) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Polar's own accent — "Ether", the one colour in their otherwise
    /// monochrome system, reserved for moments that need to carry energy
    /// (polar.sh/brand). The exact role Stripe's indigo plays on its card.
    private static let mark = DS.brandHue(for: "Polar") ?? Color.fixed("#3619CC")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(PolarRoom.headline(room))
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(PolarRoom.note(room))
                .dsText(.subhead13)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s1)

            if !room.items.isEmpty {
                rail
                    .padding(.top, DS.Space.s4)

                ForEach(Array(room.items.enumerated()), id: \.element.id) { index, item in
                    row(item, lead: index == 0)
                        .chartArrival(index: index, reduceMotion: reduceMotion)
                }
                .padding(.top, DS.Space.s1)
            }

            notes
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsWidgetSurface()
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s2)
    }

    // MARK: - The rail

    /// The card's time axis, drawn by the shared component.
    ///
    /// The placement stays here on purpose: the marks go through this
    /// room's own `position`, so the room's selftest keeps asserting the
    /// arithmetic it ships with.
    private var rail: some View {
        // Hoisted out of the view builder: these change only when the
        // deadlines do, and a closure would re-run on every layout pass.
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

    // MARK: - Rows

    private func row(_ item: PolarRoom.Item, lead: Bool) -> some View {
        Button {
            DSHaptic.selection()
            onOpen(item)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .dsText(.heading17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    metaLine(item)
                }
                Spacer(minLength: DS.Space.s2)
                Text(PolarRoom.value(days: item.days))
                    .dsText(.price16)
                    .foregroundStyle(item.days < 0 ? DS.textPrimary : DS.textSecondary)
                    .monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, DS.Space.s2)
    }

    @ViewBuilder
    private func metaLine(_ item: PolarRoom.Item) -> some View {
        HStack(spacing: DS.Space.s1 + 2) {
            Text(PolarRoom.chip(item))
                .dsText(.label11).fontWeight(.bold)
                .foregroundStyle(Color.fixed("#ffffff"))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Self.mark, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            Text("Evidence window")
                .dsText(.label12)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var notes: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let coverage = PolarRoom.coverageNote(room) {
                note(coverage)
            }
            if let stale = PolarRoom.staleNote(asOf: room.asOf) {
                note(stale)
            }
        }
        .padding(.top, DS.Space.s3)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .dsText(.label11)
            .foregroundStyle(DS.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
