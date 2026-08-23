import SwiftUI

/// THE X ROOM'S HEAD (2026-08-13, prd §375) — the whole span of an archive,
/// with its loudest year named.
///
/// The anatomy is `GnosisPayRoomCard`'s: kicker, heavy headline stating the
/// finding as a sentence, a history strip, then ranked rows. What differs is
/// what the strip is FOR — that card's twelve months are a recent trend, and
/// this one's fifteen years are the object itself. So this strip is never
/// capped and never scrolls: a span you can't see the start of is not a span.
///
/// ## Silent years are drawn
///
/// A year with no posts still takes its column, at the floor height every other
/// bar has, in a fainter fill. Dropping it would put two bars four years apart
/// side by side and quietly rescale the axis — see `XRoom`'s own note.
///
/// ## No colour for "more" or "less"
///
/// One hue, one scale. Posting more in 2019 than in 2023 is not a win and not a
/// failure, and the app has no idea which the person wanted — `GnosisPayRoom`'s
/// restraint, in the room where the temptation to editorialise is strongest.
///
/// ## Liveness
///
/// Stores no `Thing` — only value types out of `XRoom`, filtered at the
/// boundary by `XRoomSource`. The tap hands back a `Year` and the section that
/// owns the sheet does the lookup (corollary 5).
///
/// FLAT BY LAW: a plain VStack, no generic `Widget`/`Row` mount.
struct XRoomCard: View {
    let room: XRoom
    /// Hands back the YEAR, not a `Thing` — a year owns hundreds of posts, so
    /// the honest landing is its loudest one (or, with no counts recorded, its
    /// newest).
    var onOpen: (XRoom.Year) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let mark = DS.legibleCardFill(for: "X")

    /// The busiest year's post count — every bar's full width, so the strip and
    /// the rows below it are on ONE scale and can't disagree.
    private var top: Int { room.busiest.posts }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "X"))
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(Self.mark)

            // THE NOTE LEADS (2026-08-22, prd §451). `XRoom.headline` stood
            // here at the same tier and named the busiest year and its count —
            // which is row one verbatim, one line below, and the strip's only
            // full-height capsule. What is left is the pair the drawing is
            // structurally unable to state: how many posts in total, and how
            // many of the span's years you actually wrote in.
            Text(XRoom.note(room))
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s2)
                // The whole card is a tap target for touch and pointer and
                // carries nothing for VoiceOver; this states the same verb on
                // the line that names its destination.
                .dsCardLead(Text("Opens this year's loudest post")) {
                    DSHaptic.selection()
                    onOpen(room.busiest)
                }

            yearStrip
                .padding(.top, DS.Space.s3)

            ForEach(Array(XRoom.rows(room).enumerated()), id: \.element.id) { index, year in
                row(year, index: index)
                    .chartArrival(index: index, reduceMotion: reduceMotion)
            }
            .padding(.top, DS.Space.s3)

            if let footnote = XRoom.footnote(room) {
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
            onOpen(room.busiest)
        }
    }

    // MARK: - The span

    /// A column per YEAR, oldest at the left, ends labelled.
    ///
    /// Only the first and last years are labelled: fifteen ticks at label size
    /// is a row of noise, and the two ends are what make the middle readable
    /// (`GnosisPayRoomCard.monthStrip`'s ruling, at a different grain).
    private var yearStrip: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(room.years) { year in
                    Capsule(style: .continuous)
                        // A silent year is drawn FAINT rather than absent — it
                        // is part of the span and its emptiness is the reading.
                        .fill(Self.mark.opacity(year.posts == 0 ? 0.18 : 0.85))
                        // Floored so a year with a single post is still a
                        // visible column rather than a sub-pixel nothing: a
                        // year you wrote in must never draw as one you didn't.
                        .frame(height: max(4, 38 * XRoom.share(posts: year.posts, of: top)))
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
        // The span, not `XRoom.note` — that sentence is the card's LEAD since
        // 2026-08-22 and a strip repeating it makes VoiceOver say it twice.
        .accessibilityLabel(Text("A column per year, \(String(room.years.first?.year ?? 0)) to \(String(room.years.last?.year ?? 0))"))
    }

    // MARK: - Rows

    /// The biggest years, each with what it was about — the half that meets
    /// §349's "a head must never draw less than what it displaces", since this
    /// card takes the slot the topic treemap held.
    private func row(_ year: XRoom.Year, index: Int) -> some View {
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
                    Text(XRoom.yearLine(year))
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                ShareBar(fraction: XRoom.share(posts: year.posts, of: top),
                         index: index,
                         reduceMotion: reduceMotion)
            }
            .padding(.vertical, DS.Space.s1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(String(year.year)), \(XRoom.yearLine(year))"))
    }
}
