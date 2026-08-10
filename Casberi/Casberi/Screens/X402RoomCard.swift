import SwiftUI

/// THE CIRCLE x402 ROOM'S HEAD (2026-08-06) — who is actually selling.
///
/// The room-head family's anatomy (kicker, headline, note, the drawing) with
/// `UnitTreemap` as the drawing — the same component the receipts screen's reach
/// map uses, for the same job: rank-ordered magnitude with a folded, named tail.
/// Reusing it is the point; this card introduces no new component.
///
/// Why a treemap and not the roster of discs PostHog's head wears: a disc draws
/// a metric's own CURVE, and a seller has no curve — it has one number and its
/// relation to everyone else's, which is the one thing a treemap says better
/// than any list.
///
/// ## Liveness
///
/// Stores no `Thing` — only value types out of `X402Room`, filtered at the
/// boundary by `X402RoomSource`. The tap hands back a seller SLUG and the
/// section that owns the sheet does the lookup (corollary 5).
///
/// FLAT BY LAW like its neighbours: a plain VStack, no generic `Widget`/`Row`
/// mount.
struct X402RoomCard: View {
    let room: X402Room
    /// Opens that seller's own row. The card holds no `Thing`, so it hands back
    /// the slug the caller resolves against the live corpus.
    var onOpen: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let mark = DS.brandHue(for: "Circle x402") ?? Color.fixed("#60b0f0")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "Circle x402"))
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(Self.mark)

            Text(X402Room.headline(room))
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s2)

            let note = X402Room.note(room, money: X402Ingest.usd)
            if !note.isEmpty {
                Text(note)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s1)
            }

            UnitTreemap(count: room.cells.count, height: 180) { i in
                face(room.cells[i])
            }
            .padding(.top, DS.Space.s4)
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsWidgetSurface()
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s2)
    }

    /// One tile. The service count rides under the name because it IS the
    /// magnitude the tile's size encodes — a reader shouldn't have to estimate
    /// an area to learn a number we know exactly.
    private func face(_ cell: X402Room.Cell) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(cell.label)
                .dsText(.callout15).fontWeight(.semibold)
                .foregroundStyle(cell.isTail ? DS.textSecondary : DS.textPrimary)
                .lineLimit(2).minimumScaleFactor(0.8)
            // The tail's number is a SUM across several sellers, so printing it
            // beside a name would read as one company selling that many — the
            // receipts map's own refusal, same shape.
            if !cell.isTail {
                Text(cell.services == 1
                     ? String(localized: "1 service")
                     : String(localized: "\(cell.services) services"))
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                // The well, not the sheet: this card's own surface IS
                // `dsWidgetSurface`. Harmless now that the fill is the
                // neutral ink ramp (2026-08-10) rather than a translucent
                // brand wash — ink is fully opaque at every magnitude, so it
                // can no longer vanish into a matching base — but left as-is
                // rather than churned for its own sake.
                DS.surfaceWell
                if !cell.isTail {
                    DS.ink(magnitude: X402Room.share(cell, in: room))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
        .contentShape(Rectangle())
        // The tail names no seller, so it opens nothing. A tile that looks
        // tappable and isn't is the dead control the honesty rule forbids —
        // hence no gesture on it at all rather than one that quietly no-ops.
        .onTapGesture {
            guard !cell.isTail else { return }
            DSHaptic.tap()
            onOpen(cell.id)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cell.isTail
                            ? cell.label
                            : "\(cell.label), \(cell.services) services")
    }
}
