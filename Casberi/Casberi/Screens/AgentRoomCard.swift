import SwiftUI

/// THE AGENT ROOMS' HEAD (2026-08-23, prd §457) — how much you said, month by
/// month, and to which of them.
///
/// The anatomy is `JournalRoomCard`'s, because the object is the same shape: a
/// corpus that arrives in one tap and spans further back than a trailing
/// twelve months. Three things differ, and each is the corpus talking:
///
/// **The strip is MONTHS.** A year strip over ChatGPT's short life draws three
/// columns (see `AgentRoom`'s note). Silent months are still drawn, at the
/// floor height, in a fainter fill — the fortnight you stopped is the reading.
///
/// **The lead is DEPTH.** `AgentRoom.headline` names the longest conversation,
/// which is the one fact in this room no part of this drawing states: the
/// strip counts conversations, and a 300-turn afternoon is a single tick in it.
///
/// **There is a comparison line.** It is the only place in this card that
/// speaks about another room, and it is the reading none of these products can
/// make about themselves. It says CONVERSATIONS and never turns — see
/// `AgentRoom.comparison` for why that is a correctness rule rather than a
/// stylistic one.
///
/// ## No colour for "more" or "less"
///
/// One hue, one scale. Talking to Claude more in March than in June is not a
/// win and not a failure, and the app has no idea which the person wanted. The
/// comparison line is the one place a second seat is named at all, and it
/// states a count rather than a verdict.
///
/// ## Four rooms, one card
///
/// ChatGPT, Claude, Gemini and Claude Code share every line of this and differ
/// only in the strip's hue. The source is passed in rather than read from a
/// `Thing`, so this view still stores no model.
///
/// FLAT BY LAW: a plain VStack, no generic `Widget`/`Row` mount.
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
        VStack(alignment: .leading, spacing: 0) {
            // No source-name eyebrow (prd §452): a room head renders only
            // inside its own source's room, under a chip strip where that
            // source's chip is the lit one.
            //
            // ONE LEAD (prd §451). The headline is the longest conversation or
            // nil, and on a room with nothing deep enough to name the note is
            // promoted into the empty slot rather than the card leading with a
            // sentence that reads the drawing out loud. The note is NOT drawn
            // twice — it appears once, at whichever tier it is standing in.
            Text(AgentRoom.headline(room) ?? AgentRoom.note(room))
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .dsCardLead(leadAction) { openLead() }

            if AgentRoom.headline(room) != nil {
                Text(AgentRoom.note(room))
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s1)
            }

            monthStrip
                .padding(.top, DS.Space.s3)

            ForEach(Array(AgentRoom.rows(room).enumerated()), id: \.element.id) { index, month in
                row(month, index: index)
                    .chartArrival(index: index, reduceMotion: reduceMotion)
            }
            .padding(.top, DS.Space.s3)

            // The cross-assistant line sits UNDER the rows, not above them:
            // this card is about this room, and a comparison promoted over its
            // own subject would make the head about somebody else's seat.
            if let comparison = AgentRoom.comparison(room) {
                Text(comparison)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s3)
            }

            if let footnote = AgentRoom.footnote(room) {
                Text(footnote)
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
        .contentShape(Rectangle())
        .onTapGesture {
            DSHaptic.selection()
            openLead()
        }
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

    // MARK: - The span

    /// A column per MONTH, oldest at the left, ends labelled.
    ///
    /// Only the first and last months are labelled: thirty ticks at label size
    /// is a row of noise, and the two ends are what make the middle readable
    /// (`XRoomCard.yearStrip`'s ruling, inherited whole).
    private var monthStrip: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(room.months) { month in
                    Capsule(style: .continuous)
                        // A silent month is drawn FAINT rather than absent — it
                        // is part of the span and its emptiness is the reading.
                        .fill(mark.opacity(month.conversations == 0 ? 0.18 : 0.85))
                        // Floored so a month with a single conversation is
                        // still a visible column rather than a sub-pixel
                        // nothing: a month you used it must never draw as one
                        // you didn't.
                        .frame(height: max(4, 38 * AgentRoom.share(
                            conversations: month.conversations, of: top)))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 38, alignment: .bottom)
            .chartWipe(reduceMotion: reduceMotion)
            if let first = room.months.first, let last = room.months.last,
               room.months.count > 1 {
                HStack {
                    Text(AgentRoom.monthLabel(first.month))
                    Spacer(minLength: DS.Space.s2)
                    Text(AgentRoom.monthLabel(last.month))
                }
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
            }
        }
        .accessibilityElement()
        // The span, not `AgentRoom.note` — on a room with no headline that
        // sentence is the card's LEAD, and a strip repeating it makes
        // VoiceOver say it twice.
        .accessibilityLabel(Text("A column per month, \(AgentRoom.monthLabel(room.months.first?.month ?? 0)) to \(AgentRoom.monthLabel(room.months.last?.month ?? 0))"))
    }

    // MARK: - Rows

    /// The busiest months, each with what it was about — the half that meets
    /// §349's "a head must never draw less than what it displaces", since this
    /// card takes the slot the topic treemap held.
    private func row(_ month: AgentRoom.Month, index: Int) -> some View {
        Button {
            DSHaptic.selection()
            onOpen(month)
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Text(AgentRoom.monthLabel(month.month))
                        .dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: DS.Space.s2)
                    Text(AgentRoom.monthLine(month))
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                ShareBar(fraction: AgentRoom.share(conversations: month.conversations, of: top),
                         index: index,
                         reduceMotion: reduceMotion)
            }
            .padding(.vertical, DS.Space.s1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(AgentRoom.monthLabel(month.month)), \(AgentRoom.monthLine(month))"))
    }
}
