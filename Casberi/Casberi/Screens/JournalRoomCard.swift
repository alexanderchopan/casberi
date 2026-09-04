import SwiftUI

/// THE JOURNAL ROOMS' HEAD (2026-08-17, prd §398) — the whole span of a
/// journal, with its longest run named.
///
/// The anatomy is `XRoomCard`'s, because the object is the same shape: a
/// corpus that spans years, arriving in one tap, whose room could previously
/// only speak about a trailing twelve months. What differs is the FINDING —
/// that card names the loudest year of a public archive, this one names the
/// longest stretch somebody kept showing up, which is the reading a journal
/// is for and the one nothing else in this app can produce.
///
/// ## Silent years are drawn
///
/// A year with no entries still takes its column, at the floor height every
/// other bar has, in a fainter fill. Dropping it would put two bars four years
/// apart side by side and quietly rescale the axis — see `JournalRoom`'s note.
///
/// ## No colour for "more" or "less"
///
/// One hue, one scale. Writing more in 2019 than in 2023 is not a win and not a
/// failure, and the app has no idea which the person wanted. `XRoom` calls this
/// the room where the temptation to editorialise is strongest; a journal is the
/// room where acting on it would be worst, because the thing being scored would
/// be somebody's own life rather than their posting.
///
/// ## Two rooms, one card
///
/// Day One and Apple Journal share every line of this, and differ only in the
/// kicker and the hue — which is the whole of what distinguishes them, since
/// both hold the same object under different app names. The source is passed in
/// rather than read from a `Thing`, so this view still stores no model.
///
/// FLAT BY LAW: a plain VStack, no generic `Widget`/`Row` mount.
struct JournalRoomCard: View {
    let room: JournalRoom
    /// Which journal this is — the kicker's words and the strip's hue, and
    /// nothing else.
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
        VStack(alignment: .leading, spacing: 0) {
            // The source-name eyebrow retired here 2026-08-22 (prd §452). A room
            // head renders only inside its own source's room, under a chip strip
            // where that source's chip is the lit one — so the card introduced
            // itself with a word already on screen, one row up.
            // ONE LEAD, and which line takes it depends on whether there is a
            // run to name (2026-08-22, prd §451). `JournalRoom.headline` is
            // the streak or nil now — its other branch named the fullest year
            // and its entry count, which is row one verbatim and the strip's
            // only full-height capsule. So on a journal with no run the note
            // is promoted into the empty slot rather than the card leading
            // with a sentence that reads the drawing out loud.
            //
            // The note is NOT drawn twice: it appears once, at whichever tier
            // it is standing in.
            // THE LEDE (prd §585). A run of days is a FIGURE, so it takes
            // the loud rung with its meaning demoted underneath; a journal
            // with no run has only a sentence to show and keeps `heading22`,
            // which §584 measured is where a sentence belongs.
            //
            // The undrawn headline becomes the SPOKEN label, so the localized
            // sentence stays live for VoiceOver rather than being replaced by
            // a bare number and a fragment.
            // The card lead rides the GROUP so it survives whichever branch
            // draws — this headline is the card's only door.
            Group {
                if let lede = JournalRoom.lede(room) {
                    RoomLedeView(lede: lede, spoken: JournalRoom.headline(room))
                } else {
                    Text(JournalRoom.note(room))
                        .dsText(.heading22)
                        .foregroundStyle(DS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // The whole card is a tap target for touch and pointer and
            // carries nothing for VoiceOver; this states the same verb on
            // the line that names its destination.
            .dsCardLead(Text("Opens this year's last entry")) {
                DSHaptic.selection()
                onOpen(room.fullest)
            }

            if JournalRoom.headline(room) != nil {
                Text(JournalRoom.note(room))
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s1)
            }

            yearStrip
                .padding(.top, DS.Space.s3)

            ForEach(Array(JournalRoom.rows(room).enumerated()), id: \.element.id) { index, year in
                row(year, index: index)
                    .chartArrival(index: index, reduceMotion: reduceMotion)
            }
            .padding(.top, DS.Space.s3)

            if let footnote = JournalRoom.footnote(room) {
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
            onOpen(room.fullest)
        }
    }

    // MARK: - The span

    /// A column per YEAR, oldest at the left, ends labelled.
    ///
    /// Only the first and last years are labelled: a decade of ticks at label
    /// size is a row of noise, and the two ends are what make the middle
    /// readable (`XRoomCard.yearStrip`'s ruling, inherited whole).
    private var yearStrip: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(room.years) { year in
                    Capsule(style: .continuous)
                        // A silent year is drawn FAINT rather than absent — it
                        // is part of the span and its emptiness is the reading.
                        .fill(mark.opacity(year.entries == 0 ? 0.18 : 0.85))
                        // Floored so a year with a single entry is still a
                        // visible column rather than a sub-pixel nothing: a
                        // year you wrote in must never draw as one you didn't.
                        .frame(height: max(4, 38 * JournalRoom.share(entries: year.entries, of: top)))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 38, alignment: .bottom)
            .chartWipe(reduceMotion: reduceMotion)
            if let first = room.years.first, let last = room.years.last, room.years.count > 1 {
                HStack {
                    Text(verbatim: String(first.year))
                    Spacer(minLength: DS.Space.s2)
                    Text(verbatim: String(last.year))
                }
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
            }
        }
        .accessibilityElement()
        // The span, not `JournalRoom.note` — on a journal with no run that
        // sentence is the card's LEAD (prd §451), and a strip repeating it
        // makes VoiceOver say it twice.
        .accessibilityLabel(Text("A column per year, \(String(room.years.first?.year ?? 0)) to \(String(room.years.last?.year ?? 0))"))
    }

    // MARK: - Rows

    /// The fullest years, each with what it was about — the half that meets
    /// §349's "a head must never draw less than what it displaces", since this
    /// card takes the slot the topic treemap held.
    private func row(_ year: JournalRoom.Year, index: Int) -> some View {
        Button {
            DSHaptic.selection()
            onOpen(year)
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Text(verbatim: String(year.year))
                        .dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: DS.Space.s2)
                    Text(JournalRoom.yearLine(year))
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                ShareBar(fraction: JournalRoom.share(entries: year.entries, of: top),
                         index: index,
                         reduceMotion: reduceMotion)
            }
            .padding(.vertical, DS.Space.s1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(String(year.year)), \(JournalRoom.yearLine(year))"))
    }
}
