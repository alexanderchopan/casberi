import SwiftUI

/// THE X ROOM'S HEAD (2026-08-13, prd §375) — the whole span of an archive,
/// with its loudest year named.
///
/// A sentence, a span strip, then ranked rows. The strip's fifteen years are the
/// object itself, so it is never capped and never scrolls: a span you can't see
/// the start of is not a span. Silent years are drawn faint (`SpanStrip`'s rule).
///
/// ## No colour for "more" or "less"
///
/// One hue, one scale. Posting more in 2019 than in 2023 is not a win and not a
/// failure, and the app has no idea which the person wanted.
///
/// ## Liveness
///
/// Stores no `Thing` — only value types out of `XRoom`, filtered at the
/// boundary by `XRoomSource`. The tap hands back a `Year` and the section that
/// owns the sheet does the lookup (corollary 5).
///
/// Composed through `DSRoomChassis.Head`, its `SpanStrip` and its ranked `Row`
/// (prd §745) — the anatomy the journal and agent rooms share.
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
        DSRoomChassis.Head(
            // THE NOTE LEADS (2026-08-22, prd §451). `XRoom.headline` named the
            // busiest year and its count — which is row one verbatim, and the
            // strip's only full-height capsule. What is left is the pair the
            // drawing is structurally unable to state.
            lead: .sentence(XRoom.note(room)),
            door: DSRoomChassis.Door(hint: Text("Opens this year's loudest post")) {
                onOpen(room.busiest)
            },
            footnotes: [.quiet(XRoom.footnote(room))]) {
            DSRoomChassis.Block { yearStrip }

            // The biggest years, each with what it was about — the "mostly …"
            // clause is the half the strip cannot say.
            DSRoomChassis.Block {
                DSRoomChassis.Rows(items: XRoom.rows(room)) { index, year in
                    DSRoomChassis.Row(
                        title: String(year.year),
                        line: XRoom.yearLine(year),
                        index: index,
                        action: { onOpen(year) }) {
                        ShareBar(fraction: XRoom.share(posts: year.posts, of: top),
                                 index: index,
                                 reduceMotion: reduceMotion)
                    }
                }
            }
        }
    }

    /// A column per YEAR, oldest at the left, ends labelled.
    private var yearStrip: some View {
        DSRoomChassis.SpanStrip(
            columns: room.years.map { year in
                DSRoomChassis.SpanStrip.Column(
                    id: year.year,
                    share: XRoom.share(posts: year.posts, of: top),
                    silent: year.posts == 0)
            },
            fill: Self.mark,
            first: room.years.first.map { String($0.year) },
            last: room.years.last.map { String($0.year) },
            // The span, not `XRoom.note` — that sentence is the card's LEAD, and
            // a strip repeating it makes VoiceOver say it twice.
            spoken: String(localized: "A column per year, \(String(room.years.first?.year ?? 0)) to \(String(room.years.last?.year ?? 0))"))
    }
}
