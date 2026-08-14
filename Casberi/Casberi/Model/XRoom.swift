import Foundation

/// THE X ROOM'S HEAD (2026-08-13, prd §375) — your years, not your year.
///
/// An X archive is the deepest corpus this app ever lands in one tap: a decade
/// and a half of somebody's own sentences, arriving in an afternoon. Every
/// reading the room had before this described a SLICE of it — the topic treemap
/// says what the whole pile is about with no time in it at all, and
/// `FeedHeatmap`'s "Your X year" charts the trailing twelve months, which for an
/// account that stopped posting in 2021 is an empty grid over four thousand
/// posts. Neither can say the thing that is actually true of the object: it
/// spans years, it has a loudest one, and it has years you said nothing.
///
/// ## What it costs: nothing
///
/// Every fact here is on a landed row — `capturedAt`, `ocrTopics` (stamped by
/// the `ScreenshotTopics` sweep the room already runs), `likeCount` (stamped at
/// import from the archive's own `favorite_count`) and `sourceRef`. No request,
/// no new `Thing` property, no CloudKit deploy, no `UserDefaults`. The
/// `StripeRoom`/`CursorRoom`/`PeerRoom` contract, for its reason: a head that
/// can fail is a head that can fail differently from the rows beneath it.
///
/// ## Why it may displace the treemap, and the rule it had to meet
///
/// `sourceHead` outranks `FeedInsight.topicMap`, so this card takes the slot
/// "What you post about" held. §349's rule applies — **a head must never draw
/// less than what it displaces** — which is why the year rows carry each year's
/// own SUBJECT, lifted from the same `ocrTopics` terms the treemap ranks. The
/// map says "design, wallets, Berlin" about fifteen years at once; this says
/// which of those years was which. It is the treemap along time rather than
/// instead of it.
///
/// And it DECLINES rather than competing when the archive is not deep: under
/// `minimumYears` distinct years or `minimumPosts` posts the composition
/// returns nil and the treemap leads exactly as it did before. A two-year
/// account has no eras to show, and drawing three bars over it would be the
/// card claiming a shape the corpus doesn't have.
///
/// ## What it counts: your own writing, and it says so
///
/// `.note` rows — posts and replies. NOT likes: a like is somebody else's post,
/// dated by the snowflake in its id, and folding the two would make a year of
/// heavy reading read as a year of heavy writing. The subtitle names the unit
/// so the bars can never be read as "activity" in general.
///
/// ## Silent years are DRAWN, not skipped
///
/// The strip runs first year → last year inclusive, including years with no
/// posts at all, because the gap IS the reading: an account that went quiet for
/// two years and came back says more about the person than a strip of only the
/// years that happened to have rows. Skipping them would also silently rescale
/// the axis — two bars side by side that are four years apart.
///
/// Foundation-only by design so `scripts/x-selftest.sh` can compile it WHOLE
/// and unmodified — the strongest form of "the harness ran the shipped logic",
/// and the only proof these numbers are right, since no real X archive has ever
/// been imported on this host. Everything touching `Thing` lives in
/// `XRoomSource`.
struct XRoom: Equatable {

    // MARK: - What a row is

    /// One landed post, reduced to the four facts the head reads.
    struct Sighting: Equatable {
        /// `Thing.sourceRef` — how a tap lands on the real row.
        let ref: String?
        /// The calendar year the post was written in, resolved by the caller
        /// against ONE calendar (see `XRoomSource.sighting`).
        let year: Int
        /// The row's own topic terms (`Thing.ocrTopics`), already normalised by
        /// `ScreenshotTopics`. Empty until that sweep has run, which is the
        /// common state right after an import — hence every subject here is
        /// optional and the card draws without one.
        let terms: [String]
        /// What the post got, from the archive's own `favorite_count`. Nil is
        /// NOT zero: an archive vintage that recorded no counts must not make
        /// every post look unloved (`XArchiveImport.metric`'s own rule).
        let likes: Int?
    }

    // MARK: - The shape

    /// One year of the strip. `posts == 0` is a real, drawn year — see the
    /// type note.
    struct Year: Identifiable, Equatable {
        let year: Int
        let posts: Int
        /// The term that recurs most in that year's posts, or nil when the
        /// topic sweep hasn't reached them or nothing recurred.
        let subject: String?
        /// The year's most-liked post, for the tap. Nil when no post that year
        /// carried a count.
        let loudestRef: String?
        let loudestLikes: Int?

        var id: Int { year }
    }

    /// Oldest → newest, gaps included.
    let years: [Year]
    /// Posts counted — your own writing alone.
    let total: Int
    /// The year with the most posts. Ties go to the EARLIER year, so the card
    /// names the first time you wrote that much rather than the last — and, far
    /// more importantly, so the answer is total and can't reshuffle between
    /// two identical opens.
    let busiest: Year
    /// Years inside the span with nothing in them.
    let silent: Int

    var span: Int { years.count }
    var isEmpty: Bool { years.isEmpty }

    // MARK: - Composition

    /// A room needs this many distinct years with posts in them before it has
    /// eras at all. Three is the smallest number that can show a shape (a rise,
    /// a peak, a fall); at two the strip is a comparison and the treemap says
    /// more.
    static let minimumYears = 3
    /// …and this many posts, so a handful of stray rows across three calendar
    /// years can't dress itself up as a decade.
    static let minimumPosts = 20
    /// The card draws at most this many year ROWS under the strip. The strip
    /// itself is never capped — it is the span, and a truncated span is a lie
    /// about when you started.
    static let rowCap = 3

    /// The head, or nil when this archive has no eras to show.
    static func compose(_ sightings: [Sighting]) -> XRoom? {
        guard sightings.count >= minimumPosts else { return nil }

        var counts: [Int: Int] = [:]
        var terms: [Int: [String: Int]] = [:]
        var loudest: [Int: (ref: String?, likes: Int)] = [:]
        for sight in sightings {
            counts[sight.year, default: 0] += 1
            for term in sight.terms {
                let key = term.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { continue }
                terms[sight.year, default: [:]][key, default: 0] += 1
            }
            // STRICTLY greater, so the first post to reach a peak keeps it —
            // the same tie rule as `busiest`, for the same reason: two posts
            // with equal likes must not swap the tap target between opens.
            if let likes = sight.likes, likes > (loudest[sight.year]?.likes ?? -1) {
                loudest[sight.year] = (sight.ref, likes)
            }
        }
        guard counts.count >= minimumYears,
              let first = counts.keys.min(), let last = counts.keys.max()
        else { return nil }

        var years: [Year] = []
        for year in first...last {
            let posts = counts[year] ?? 0
            years.append(Year(year: year,
                              posts: posts,
                              subject: subject(terms[year] ?? [:], posts: posts),
                              loudestRef: loudest[year]?.ref,
                              loudestLikes: loudest[year]?.likes))
        }
        // Value desc, then YEAR ASC — a total order, so the headline names the
        // same year every time it is composed over the same rows.
        guard let busiest = years.max(by: { ($0.posts, $1.year) < ($1.posts, $0.year) })
        else { return nil }
        return XRoom(years: years,
                     total: sightings.count,
                     busiest: busiest,
                     silent: years.filter { $0.posts == 0 }.count)
    }

    /// A year's subject: its most common term, and only when the term RECURS.
    ///
    /// The floor is two mentions or a tenth of the year's posts, whichever is
    /// larger — `FeedInsight.topicMap`'s own recurrence rule in miniature, and
    /// it exists for that card's reason: one post mentioning Lisbon does not
    /// make Lisbon what 1,200 posts were about, and a card that says it does is
    /// the §83 fake status wearing a label.
    ///
    /// Ties break alphabetically so the answer is deterministic. Nil is normal
    /// and the card is built for it.
    static func subject(_ terms: [String: Int], posts: Int) -> String? {
        let floor = max(2, posts / 10)
        let top = terms
            .filter { $0.value >= floor }
            .max(by: { ($0.value, $1.key) < ($1.value, $0.key) })
        return top?.key
    }

    // MARK: - Words

    /// The whole finding as one sentence.
    ///
    /// It names the BUSIEST year rather than the newest, because the newest is
    /// what the rows underneath already show and a head that restates the feed
    /// is a wasted slot. "Busiest" is stated in posts, never in reach: the
    /// archive's counts are frozen at export time, so a year called "biggest"
    /// on likes would be a claim about an audience we measured once.
    ///
    /// The year is interpolated as a STRING, and that is not a style choice:
    /// an `Int` in a localized interpolation is formatted with the locale's
    /// grouping separator, so `2019` renders as "2,019" — a year printed as a
    /// quantity, in the largest type on the card. Caught by the harness on its
    /// first run, which is exactly the class of silent wrong answer it exists
    /// for: it renders, and it looks like a number somebody meant.
    static func headline(_ room: XRoom) -> String {
        String(localized: "\(String(room.busiest.year)) was your loudest year — \(room.busiest.posts.formatted()) posts")
    }

    /// What the strip cannot say for itself: how long the span is, and how much
    /// of it you actually wrote in.
    ///
    /// A span with no silent years says so as a whole number of years rather
    /// than claiming "every year", which would be true of the span and false of
    /// the account for anyone who joined in June.
    static func note(_ room: XRoom) -> String {
        let written = room.span - room.silent
        if room.silent == 0 {
            return String(localized: "\(room.total.formatted()) posts across \(room.span) years")
        }
        return String(localized: "\(room.total.formatted()) posts — you wrote in \(written) of \(room.span) years")
    }

    /// A year row's own line: what it held, and what it was about when we know.
    static func yearLine(_ year: Year) -> String {
        guard let subject = year.subject else {
            return String(localized: "\(year.posts.formatted()) posts")
        }
        return String(localized: "\(year.posts.formatted()) posts · mostly \(subject)")
    }

    /// The rows the card draws — biggest first, ties by year ascending, capped.
    /// Silent years are never rows: a bar of nothing under a label is a row
    /// that says "0" in the shape of a finding.
    static func rows(_ room: XRoom) -> [Year] {
        room.years
            .filter { $0.posts > 0 }
            .sorted { ($0.posts, $1.year) > ($1.posts, $0.year) }
            .prefix(rowCap)
            .map { $0 }
    }

    /// A bar's share of the busiest year drawn. Zero-safe: a room whose busiest
    /// year is somehow empty draws flat bars rather than dividing by nothing
    /// (the NaN a SwiftUI frame draws as nothing at all).
    static func share(posts: Int, of top: Int) -> Double {
        guard top > 0 else { return 0 }
        return min(1, Double(posts) / Double(top))
    }

    /// The years the card had no subject for, said out loud — or nil.
    ///
    /// It exists because a strip whose rows carry no "mostly …" clause has two
    /// causes that look identical: the topic sweep hasn't reached those rows
    /// yet (it runs bounded, on foregrounds), or nothing in that year recurred
    /// often enough to name. The first heals itself and the second never will,
    /// so the card says which it is rather than leaving a person to wonder
    /// whether something is broken.
    static func footnote(_ room: XRoom) -> String? {
        let drawn = rows(room)
        let unnamed = drawn.filter { $0.subject == nil }.count
        guard unnamed > 0 else { return nil }
        if unnamed == drawn.count {
            return String(localized: "Subjects arrive once the room has been read.")
        }
        return String(localized: "\(unnamed) of these years had no recurring subject.")
    }
}
