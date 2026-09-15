import SwiftUI

/// THE AGENT ROOMS' HEAD (2026-08-23, prd §457) — how much you said, month by
/// month, and to which of them.
///
/// The anatomy is `JournalRoomCard`'s, because the object is the same shape: a
/// corpus that arrives in one tap and spans further back than a trailing
/// twelve months. Three things differ, and each is the corpus talking:
///
/// **The strip is MONTHS.** A year strip over ChatGPT's short life draws three
/// columns (see `AgentRoom`'s note).
///
/// **The lead is DEPTH.** `AgentRoom.headline` names the longest conversation,
/// which is the one fact in this room no part of this drawing states: the
/// strip counts conversations, and a 300-turn afternoon is a single tick in it.
///
/// **There is a comparison line.** It is the only place in this card that
/// speaks about another room. It says CONVERSATIONS and never turns — see
/// `AgentRoom.comparison` for why that is a correctness rule. It sits UNDER the
/// rows: this card is about this room, and a comparison promoted over its own
/// subject would make the head about somebody else's seat.
///
/// ## Four rooms, one card
///
/// ChatGPT, Claude, Gemini and Claude Code share every line of this and differ
/// only in the strip's hue. The source is passed in rather than read from a
/// `Thing`, so this view still stores no model.
///
/// Composed through `DSRoomChassis.Head`, its `SpanStrip` and its ranked `Row`
/// (prd §745).
struct AgentRoomCard: View {
    let room: AgentRoom
    /// Which agent room this is — the strip's hue, and nothing else.
    let source: String
    /// Hands back the MONTH, not a `Thing` — a month owns many conversations,
    /// so the honest landing is its most recent one.
    var onOpen: (AgentRoom.Month) -> Void
    /// The longest conversation itself, which is a single row and so lands on
    /// it directly. Separate from `onOpen` because they hand back different
    /// things, and collapsing them would make the headline open a month.
    var onOpenLongest: (AgentRoom.Longest) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var mark: Color { DS.legibleCardFill(for: source) }

    /// The busiest month's conversation count — every bar's full height, so
    /// the strip and the rows below it are on ONE scale and can't disagree.
    private var top: Int { room.busiest.conversations }

    var body: some View {
        DSRoomChassis.Head(
            // ONE LEAD (prd §451). The headline is the longest conversation or
            // nil, and on a room with nothing deep enough to name the note is
            // promoted into the empty slot.
            lead: .sentence(AgentRoom.headline(room) ?? AgentRoom.note(room)),
            door: DSRoomChassis.Door(hint: leadAction) { openLead() },
            notes: notes,
            footnotes: [.note(AgentRoom.comparison(room)),
                        .quiet(AgentRoom.footnote(room))]) {
            DSRoomChassis.Block { monthStrip }

            DSRoomChassis.Block {
                ForEach(Array(AgentRoom.rows(room).enumerated()), id: \.element.id) { index, month in
                    DSRoomChassis.Row(
                        title: AgentRoom.monthLabel(month.month),
                        line: AgentRoom.monthLine(month),
                        index: index,
                        action: { onOpen(month) }) {
                        ShareBar(fraction: AgentRoom.share(conversations: month.conversations, of: top),
                                 index: index,
                                 reduceMotion: reduceMotion)
                    }
                }
            }
        }
    }

    /// The note is NOT drawn twice — it appears once, at whichever tier it is
    /// standing in.
    private var notes: [DSRoomChassis.Line?] {
        if AgentRoom.headline(room) != nil {
            return [.note(AgentRoom.note(room))]
        }
        return []
    }

    /// The lead's destination follows the lead's WORDS. When the headline
    /// names the longest conversation, tapping it opens that conversation;
    /// when the note has been promoted into the slot, there is no single row
    /// it names, so the busiest month is the honest landing.
    private var leadAction: Text {
        room.longest != nil && AgentRoom.headline(room) != nil
            ? Text("Opens that conversation")
            : Text("Opens this month's last conversation")
    }

    private func openLead() {
        if AgentRoom.headline(room) != nil, let longest = room.longest {
            onOpenLongest(longest)
        } else {
            onOpen(room.busiest)
        }
    }

    /// A column per MONTH, oldest at the left, ends labelled.
    private var monthStrip: some View {
        DSRoomChassis.SpanStrip(
            columns: room.months.map { month in
                DSRoomChassis.SpanStrip.Column(
                    id: month.month,
                    share: AgentRoom.share(conversations: month.conversations, of: top),
                    silent: month.conversations == 0)
            },
            fill: mark,
            first: room.months.first.map { AgentRoom.monthLabel($0.month) },
            last: room.months.last.map { AgentRoom.monthLabel($0.month) },
            // The span, not `AgentRoom.note` — on a room with no headline that
            // sentence is the card's LEAD, and a strip repeating it makes
            // VoiceOver say it twice.
            spoken: String(localized: "A column per month, \(AgentRoom.monthLabel(room.months.first?.month ?? 0)) to \(AgentRoom.monthLabel(room.months.last?.month ?? 0))"))
    }
}
