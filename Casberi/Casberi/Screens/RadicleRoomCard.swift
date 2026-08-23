import SwiftUI

/// THE RADICLE ROOM'S HEAD (prd §401) — what is stuck.
///
/// The anatomy is `CursorRoomCard`'s / `GitHubRoomCard`'s: a kicker in the
/// card's one hue, a heavy headline stating the finding as a sentence, ranked
/// rows, no decoration that isn't a reading.
///
/// ## The one drawing, and why this card may have one when GitHub's may not
///
/// A `ShareBar` per row, scaled against the OLDEST open item, encoding how long
/// each has been waiting relative to the worst. It is legitimate here for the
/// reason it is refused next door: these ages are EXACT, recovered from
/// Radicle's own record (`revisions[0].timestamp` for a patch,
/// `discussion[0].timestamp` for an issue), so a bar drawn from them is a
/// measurement rather than an impression. GitHub's dates are thread-activity
/// stamps, which is why that card draws nothing.
///
/// Scaled against the oldest rather than against a fixed window: the reading is
/// "which of these has waited longest", and a bar against, say, ninety days
/// would render a healthy repo as five near-empty slivers saying nothing.
///
/// ## No green, no red
///
/// A patch open for a long time is stated in words and by its position, never
/// painted — the ruling `StripeRoomCard` made for a dispute and every head
/// since has kept. Age is not fault: plenty of patches are open a long time for
/// good reasons, and colouring them would make the card an accusation.
///
/// ## Drafts sit at the bottom and are never ranked
///
/// Your own unfinished patches are counted in the note, apart from everything
/// above it. They are not stuck — they are waiting on you by design — and
/// ranking them with the rest would open this room by telling you your scratch
/// branch needs attention.
///
/// ## Liveness
///
/// Stores no `Thing` and reads none: `RadicleRoomSource` composes from bridge
/// STATE, so there is nothing here to invalidate.
///
/// FLAT BY LAW like its neighbours: a plain VStack, no generic `Widget`/`Row`
/// mount (the eager-head render-depth lesson, paid three times).
struct RadicleRoomCard: View {
    let room: RadicleRoom
    /// Hands back the repo id and the item id, so the section that owns the
    /// sheet can build the permalink. Never a `Thing` — this head has none.
    var onOpen: (String, String, RadicleWire.OpenItem.Kind) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var now: Date { Date() }

    /// The oldest item's age — the bar's full width, so every bar on the card
    /// is on one scale and two rows are comparable at a glance.
    private var top: Int {
        max(1, room.items.map { $0.daysOpen(asOf: now) }.max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The source-name eyebrow retired here 2026-08-22 (prd §452). A room
            // head renders only inside its own source's room, under a chip strip
            // where that source's chip is the lit one — so the card introduced
            // itself with a word already on screen, one row up.
            Text(headline)
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .dsCardLead(Text("Opens what has waited longest")) {
                    guard let oldest = room.oldest else { return }
                    DSHaptic.selection()
                    onOpen(oldest.rid, oldest.id, oldest.kind)
                }

            if let subline = room.subline(asOf: now) {
                Text(subline)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                    .padding(.top, DS.Space.s1)
            }

            ForEach(Array(room.items.enumerated()), id: \.element.id) { index, item in
                row(item, index: index)
                    .chartArrival(index: index, reduceMotion: reduceMotion)
            }
            .padding(.top, DS.Space.s3)

            if let draftLine = room.draftLine {
                Text(draftLine)
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .padding(.top, DS.Space.s3)
            }
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsWidgetSurface()
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s2)
    }

    /// The lead states the oldest thing as a sentence — an ITEM, never the
    /// count, which §223 forbids as a headline and which the subline carries.
    private var headline: String {
        guard let oldest = room.oldest else { return String(localized: "Nothing open") }
        let days = oldest.daysOpen(asOf: now)
        switch oldest.kind {
        case .patch:
            return days == 0
                ? String(localized: "A patch is waiting")
                : String(localized: "A patch has waited \(days) days")
        case .issue:
            return days == 0
                ? String(localized: "An issue is open")
                : String(localized: "An issue has been open \(days) days")
        }
    }

    // MARK: - Rows

    private func row(_ item: RadicleRoom.Item, index: Int) -> some View {
        Button {
            DSHaptic.selection()
            onOpen(item.rid, item.id, item.kind)
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Text(item.title)
                        .dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: DS.Space.s2)
                    Text(ageLine(item))
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                Text(item.repo)
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                // The stagger index is shared with the row's own arrival, so a
                // bar lands with the row that owns it rather than on a cadence
                // of its own (one beat per row — `ChartEntrance`'s rule).
                ShareBar(fraction: Double(item.daysOpen(asOf: now)) / Double(top),
                         index: index + 1,
                         reduceMotion: reduceMotion)
            }
            .padding(.vertical, DS.Space.s1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(item.title), \(item.repo), \(ageLine(item))"))
    }

    /// "Open N days" — a claim the record supports exactly, unlike GitHub's
    /// thread stamps next door.
    private func ageLine(_ item: RadicleRoom.Item) -> String {
        let days = item.daysOpen(asOf: now)
        if days == 0 { return String(localized: "Today") }
        return days == 1
            ? String(localized: "1 day")
            : String(localized: "\(days) days")
    }
}
