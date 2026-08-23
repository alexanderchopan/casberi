import Foundation

/// What a DRAWING says out loud (prd §299: "a drawing either speaks or is
/// hidden, never silent-and-present").
///
/// **Why this file exists.** §299 adopted the rule and applied it by hand to
/// the four figures in front of it that day — `WalletFlowBand`,
/// `WalletRiskStrip`, and the two rails it chose to hide. Everything drawn
/// since has been decided one call site at a time, and the 2026-08-23 sweep
/// found the predictable result: a heatmap of 371 daily counts, both runways,
/// every `AgentPanelGrid` figure, the topic treemap and the ranked boards were
/// each a `Canvas` or a stack of `Shape`s with no label of any kind. A bare
/// SwiftUI `Shape` is not an accessibility element, so none of them announced
/// anything at all — the fact was not mispronounced, it was **absent**, and
/// absent is invisible to every other check in this repo.
///
/// So the sentences live in ONE Foundation-only enum rather than as a computed
/// property per view. Three reasons, in order of how much they cost when
/// ignored:
///
///  1. **Two grammars for one figure drift.** The runway is drawn in four
///     places (`GenRunway`, `RunwayFigure`, `WalletRunwayRail`, the widget's
///     `HeroRunway`). Written four times it would be described four ways, and
///     the §418 lesson — a duplicate parser that reads the same bytes worse
///     than the original — is exactly this shape.
///  2. **A sentence is arithmetic, and arithmetic here gets a harness.** Every
///     other number this app speaks aloud is compiled whole and mutation-tested
///     (`money-receipt-selftest`, `wallet-rooms-selftest`). A spoken figure is
///     the one reading its own user can never check against the drawing, which
///     makes it MORE deserving of a harness than the visible ones, not less.
///  3. **The widget target needs the same words.** `Casberi/Shared/` is what
///     both targets compile, so `HeroRunway` and `ThemesTreemap` say what their
///     in-app twins say without a second copy crossing a process boundary.
///
/// **THE RULE THESE ALL FOLLOW: say the figure's CLAIM, not its contents.**
/// §299 settled this when it hid the Stripe and Cloudflare rails — "a spoken
/// rail is the same facts a second time in a worse order". A heatmap does not
/// read out 371 cells; it says how much, over how long, and where the peak was.
/// A board does not read out every row; the rows below it are already text. The
/// figure speaks the thing that exists ONLY as a picture, and stops.
///
/// **AND NEVER INVENT A NUMBER.** Each composer takes facts already computed
/// for the drawing and refuses rather than estimates: an empty figure says it
/// is empty, an unknown peak is omitted rather than guessed at zero, and a
/// curve whose ends we cannot read reports direction alone. A confident wrong
/// sentence is worse than silence, because the person hearing it has no picture
/// to check it against — the §83 honesty law, on the one surface where it
/// cannot be caught by looking.
enum FigureVoice {

    // MARK: - Ranked rows

    /// One row of a ranked figure — a leaderboard bar, a treemap cell, a
    /// source-mix block. `detail` is the row's own printed value ("23 posts",
    /// "3.4h"), never a number this file formats, so the spoken figure and the
    /// drawn one can never disagree about the units.
    struct Row {
        let label: String
        let detail: String
        init(label: String, detail: String) {
            self.label = label
            self.detail = detail
        }
    }

    // MARK: - A calendar grid of daily counts

    /// The heatmap's claim: how much, spread over how many days, and the peak.
    ///
    /// `activeDays` is the count of days with anything at all — the reading the
    /// grid is FOR, and the one a total alone destroys: 300 things on four days
    /// and 300 things across 300 days draw very differently and total the same.
    ///
    /// The peak is named only when it has a date. A busiest-day count with no
    /// date to put it on is a number floating free of the calendar it claims to
    /// describe, and the grid's whole subject is when.
    static func heatmap(total: Int, activeDays: Int, spanDays: Int,
                        busiest: Int, busiestDate: Date?) -> String {
        guard total > 0, spanDays > 0 else {
            return String(localized: "Nothing in this window.")
        }
        var parts: [String] = []
        parts.append(activeDays == 1
            ? String(localized: "\(total) on one day.")
            : String(localized: "\(total) across \(activeDays) days of \(spanDays)."))
        if busiest > 0, let date = busiestDate {
            let day = date.formatted(.dateTime.month().day())
            parts.append(String(localized: "Busiest \(busiest) on \(day)."))
        }
        return parts.joined(separator: " ")
    }

    // MARK: - A time rail

    /// Dots on a track. The spread is the claim (`WalletRunwayRail`'s own §299
    /// reasoning), plus the one fact the drawing carries in HUE ALONE.
    ///
    /// **Overdue is the load-bearing half.** `GenRunway` and the widget's
    /// `HeroRunway` both colour a late dot `DS.attention` and say nothing else
    /// about it — on iOS there is no tooltip and no text equivalent anywhere on
    /// the figure, so lateness was carried by colour and by nothing else. That
    /// is the one place in this app where the 2026-07-16 colour law was
    /// genuinely broken rather than merely unenforced, and the fix belongs in
    /// the sentence rather than in a second glyph: the rows beneath the rail
    /// already name each item, so what the rail owes is the count.
    static func runway(dates: [Date], now: Date, overdue: Int) -> String {
        guard let first = dates.min(), let last = dates.max() else {
            return String(localized: "Nothing scheduled.")
        }
        let from = first.formatted(.dateTime.month().day())
        let to = last.formatted(.dateTime.month().day())
        var parts: [String] = []
        parts.append(dates.count == 1
            ? String(localized: "One, \(from).")
            : String(localized: "\(dates.count) from \(from) to \(to)."))
        if overdue == 1 {
            parts.append(String(localized: "One overdue."))
        } else if overdue > 1 {
            parts.append(String(localized: "\(overdue) overdue."))
        }
        // The next one still ahead — the question a spread cannot answer, and
        // the reason somebody looks at a runway rather than at the list.
        if let next = dates.filter({ $0 > now }).min() {
            parts.append(String(localized: "Next \(next.formatted(.dateTime.month().day()))."))
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Ranked figures

    /// A board, a treemap, a source mix: what leads, and how far out in front.
    ///
    /// **Only the lead and the runner-up are named, and that is deliberate.**
    /// Reading six cells aloud is the "dozen stray slab labels" §299 hid the
    /// rails to avoid, and on a board the rows are already text beneath the
    /// bars. What the picture adds is RANK — which is biggest, and whether the
    /// field is close or a runaway — so that is what it says.
    ///
    /// `shown` is how many the figure actually drew, so a folded tail is
    /// admitted ("and 4 more") rather than silently dropped — the same honesty
    /// `UnitTreemap`'s own folded cell already keeps for the eye.
    static func ranking(rows: [Row], shown: Int? = nil) -> String {
        guard let lead = rows.first else {
            return String(localized: "Nothing to rank yet.")
        }
        // A row with no `detail` states its RANK and no number. That is not a
        // fallback for missing data — it is what §213 requires of the figures
        // whose cells are forbidden to print a count (the widget's source mix
        // and themes map). Rank is the whole of what those tiles claim, so
        // rank is the whole of what they say.
        var parts: [String] = [
            lead.detail.isEmpty
                ? String(localized: "\(lead.label) leads.")
                : String(localized: "\(lead.label) leads, \(lead.detail).")
        ]
        if rows.count > 1 {
            let second = rows[1]
            parts.append(second.detail.isEmpty
                ? String(localized: "Then \(second.label).")
                : String(localized: "Then \(second.label), \(second.detail)."))
        }
        let drawn = shown ?? rows.count
        let rest = drawn - min(2, rows.count)
        if rest > 0 {
            parts.append(rest == 1
                ? String(localized: "And one more.")
                : String(localized: "And \(rest) more."))
        }
        return parts.joined(separator: " ")
    }

    // MARK: - A split bar

    /// A stacked capsule. The legend beneath already names each segment, so the
    /// bar owes the SHARE — the proportion is the only thing the drawing knows
    /// that the words do not.
    static func distribution(segments: [Row], counts: [Int]) -> String {
        let total = counts.reduce(0, +)
        guard total > 0, !segments.isEmpty, segments.count == counts.count else {
            return String(localized: "Nothing to show yet.")
        }
        let parts = zip(segments, counts).map { seg, count -> String in
            let pct = Int((Double(count) / Double(total) * 100).rounded())
            return String(localized: "\(seg.label) \(pct) percent")
        }
        return parts.joined(separator: ", ") + "."
    }

    // MARK: - A curve

    /// A sparkline or a bare plot. Direction is what the eye takes off a curve
    /// at a glance, and the SPAN is what it takes on a second look; both are
    /// lost entirely when the line is a `Path` with no label.
    ///
    /// Deliberately takes already-formatted endpoints rather than Doubles: the
    /// call sites price in dollars, in percent and in points, and a formatter
    /// living here would have to guess which — the `Row.detail` rule again.
    static func curve(from: String?, to: String?, direction: Direction) -> String {
        let word: String
        switch direction {
        case .up:   word = String(localized: "up")
        case .down: word = String(localized: "down")
        case .flat: return String(localized: "Flat.")
        }
        guard let from, let to else {
            return String(localized: "Trend \(word).")
        }
        return String(localized: "Trend \(word), \(from) to \(to).")
    }

    /// A curve whose UNITS the drawing does not know — the feed row's
    /// `Sparkline`, which holds bare closes and is mounted over tokens, stocks
    /// and prediction markets alike.
    ///
    /// It speaks the MOVE rather than the endpoints for exactly that reason: a
    /// percentage is the one reading that is true whatever the row is priced
    /// in, and formatting those closes as dollars here would put a currency on
    /// a market quoted in points. `move` is the caller's already-formatted
    /// string (`TokenChartStyle.changeText`), so the spoken figure carries the
    /// same rounding — and the same flat rule — as the printed one.
    static func trend(direction: Direction, move: String?) -> String {
        switch direction {
        case .flat: return String(localized: "Trend flat.")
        case .up:
            guard let move else { return String(localized: "Trend up.") }
            return String(localized: "Trend up \(move).")
        case .down:
            guard let move else { return String(localized: "Trend down.") }
            return String(localized: "Trend down \(move).")
        }
    }

    /// Flat is its own state, never a very small up (the 2026-07-16 law that
    /// `TokenChartStyle.isFlat` already keeps for the ink and the sign — a
    /// spoken figure that called a rounded-away move "up" would reintroduce
    /// exactly the claim the visible layer refuses to make).
    enum Direction {
        case up, down, flat

        /// Built from the same test the drawing uses, so the spoken direction
        /// and the drawn colour can never disagree.
        static func of(change: Double, flatBelow: Double = 0.0005) -> Direction {
            if abs(change) < flatBelow { return .flat }
            return change > 0 ? .up : .down
        }
    }
}
