import SwiftUI

/// THE JOURNAL ROOMS' HEAD (2026-08-17, prd §398) — the whole span of a
/// journal, with its longest run named.
///
/// The anatomy is `XRoomCard`'s, because the object is the same shape: a
/// corpus that spans years, arriving in one tap. What differs is the FINDING —
/// that card names the loudest year of a public archive, this one names the
/// longest stretch somebody kept showing up.
///
/// ## No colour for "more" or "less"
///
/// One hue, one scale. Writing more in 2019 than in 2023 is not a win and not a
/// failure, and a journal is the room where acting on that temptation would be
/// worst, because the thing being scored would be somebody's own life.
///
/// ## Two rooms, one card
///
/// Day One and Apple Journal share every line of this, and differ only in the
/// hue. The source is passed in rather than read from a `Thing`, so this view
/// still stores no model.
///
/// Composed through `DSRoomChassis.Head`, its `SpanStrip` and its ranked `Row`
/// (prd §745).
struct JournalRoomCard: View {
    let room: JournalRoom
    /// Which journal this is — the strip's hue, and nothing else.
    let source: String
    /// Hands back the YEAR, not a `Thing` — a year owns hundreds of entries, so
    /// the honest landing is its most recent one.
    var onOpen: (JournalRoom.Year) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var mark: Color { DS.legibleCardFill(for: source) }

    /// The fullest year's entry count — every bar's full width, so the strip and
    /// the rows below it are on ONE scale and can't disagree.
    private var top: Int { room.fullest.entries }

    var body: some View {
        DSRoomChassis.Head(
            lead: lead,
            door: DSRoomChassis.Door(hint: Text("Opens this year's last entry")) {
                onOpen(room.fullest)
            },
            notes: notes,
            footnotes: [.quiet(JournalRoom.footnote(room))]) {
            DSRoomChassis.Block { yearStrip }

            DSRoomChassis.Block {
                DSRoomChassis.Rows(items: JournalRoom.rows(room)) { index, year in
                    DSRoomChassis.Row(
                        title: String(year.year),
                        line: JournalRoom.yearLine(year),
                        index: index,
                        action: { onOpen(year) }) {
                        ShareBar(fraction: JournalRoom.share(entries: year.entries, of: top),
                                 index: index,
                                 reduceMotion: reduceMotion)
                    }
                }
            }
        }
    }

    /// ONE LEAD (prd §451, §585). A run of days is a FIGURE, so it takes the
    /// lede with its meaning demoted underneath and the undrawn headline as its
    /// spoken sentence; a journal with no run has only a sentence to show, so
    /// the note is promoted into the empty slot rather than the card leading
    /// with a sentence that reads the drawing out loud.
    private var lead: DSRoomChassis.Lead {
        if let lede = JournalRoom.lede(room) {
            return .lede(lede, spoken: JournalRoom.headline(room))
        }
        return .sentence(JournalRoom.note(room))
    }

    /// The note is NOT drawn twice: under a lede it is the second sentence, and
    /// with no run it is already the lead.
    private var notes: [DSRoomChassis.Line?] {
        if JournalRoom.headline(room) != nil {
            return [.note(JournalRoom.note(room))]
        }
        return []
    }

    /// A column per YEAR, oldest at the left, ends labelled.
    private var yearStrip: some View {
        DSRoomChassis.SpanStrip(
            columns: room.years.map { year in
                DSRoomChassis.SpanStrip.Column(
                    id: year.year,
                    share: JournalRoom.share(entries: year.entries, of: top),
                    silent: year.entries == 0)
            },
            fill: mark,
            first: room.years.first.map { String($0.year) },
            last: room.years.last.map { String($0.year) },
            // The span, not `JournalRoom.note` — on a journal with no run that
            // sentence is the card's LEAD, and a strip repeating it makes
            // VoiceOver say it twice.
            spoken: String(localized: "A column per year, \(String(room.years.first?.year ?? 0)) to \(String(room.years.last?.year ?? 0))"))
    }
}
