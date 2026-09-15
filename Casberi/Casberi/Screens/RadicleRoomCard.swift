import SwiftUI

/// THE RADICLE ROOM'S HEAD (prd §401) — what is stuck.
///
/// A heavy headline stating the finding as a sentence, the open items as
/// ranked rows, no decoration that isn't a reading.
///
/// ## The one drawing, and why this card may have one when GitHub's may not
///
/// A `ShareBar` per row, scaled against the OLDEST open item, encoding how long
/// each has been waiting relative to the worst. It is legitimate here for the
/// reason it is refused next door: these ages are EXACT, recovered from
/// Radicle's own record (`revisions[0].timestamp` for a patch,
/// `discussion[0].timestamp` for an issue), so a bar drawn from them is a
/// measurement rather than an impression.
///
/// ## No green, no red
///
/// A patch open for a long time is stated in words and by its position, never
/// painted. Age is not fault: plenty of patches are open a long time for good
/// reasons, and colouring them would make the card an accusation.
///
/// ## Drafts sit at the bottom and are never ranked
///
/// Your own unfinished patches are counted in the footnote, apart from
/// everything above it. They are not stuck — they are waiting on you by design.
///
/// ## Liveness
///
/// Stores no `Thing` and reads none: `RadicleRoomSource` composes from bridge
/// STATE, so there is nothing here to invalidate.
///
/// Composed through `DSRoomChassis.Head` and its ranked `Row` (prd §745).
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
        DSRoomChassis.Head(
            lead: .sentence(headline),
            door: room.oldest.map { oldest in
                DSRoomChassis.Door(hint: Text("Opens what has waited longest"), wholeCard: false) {
                    onOpen(oldest.rid, oldest.id, oldest.kind)
                }
            },
            notes: [.note(room.subline(asOf: now))],
            footnotes: [.quiet(room.draftLine)]) {
            if !room.items.isEmpty {
                DSRoomChassis.Block {
                    ForEach(Array(room.items.enumerated()), id: \.element.id) { index, item in
                        DSRoomChassis.Row(
                            title: item.title,
                            line: ageLine(item),
                            detail: item.repo,
                            spoken: "\(item.title), \(item.repo), \(ageLine(item))",
                            index: index,
                            action: { onOpen(item.rid, item.id, item.kind) }) {
                            ShareBar(fraction: Double(item.daysOpen(asOf: now)) / Double(top),
                                     index: index + 1,
                                     reduceMotion: reduceMotion)
                        }
                    }
                }
            }
        }
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
