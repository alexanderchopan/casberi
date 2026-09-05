import Foundation

/// The deadline runway's arithmetic, in ONE place.
///
/// Four rooms draw a runway — Stripe's disputes, Polar's, Dodo Payments'
/// retries and Cloudflare's expiries — and until this landed each carried its
/// own byte-identical copy of `position`, and three of them of `span` and
/// `spanLabel` besides. Four copies of a placement rule is the shape
/// `ToolScore.rank` was folded into `AgentCorpusTools.rank` to end: two
/// readings of one question drift, and then two rooms disagree about where
/// "overdue" sits while both render perfectly.
///
/// **Every failure this prevents is a wrong reading that draws beautifully.**
/// An unclamped position puts the one deadline you have already missed off the
/// left edge, where it does not look wrong, it looks absent. A span that
/// disagrees with its own label draws a correct axis under a wrong number.
///
/// The room types keep their own `position`/`span`/`spanLabel` as forwarding
/// wrappers rather than being edited at every call site: their selftests assert
/// these properties by name, and a wrapper keeps every one of those assertions
/// pointed at the shipped implementation instead of at a copy of it.
///
/// Foundation-only by design, so a `swiftc` harness can compile it whole.
enum RoomRunway {

    /// Where a mark sits on the axis, 0…1.
    ///
    /// **Overdue pins to zero rather than running off the left edge**, where it
    /// would simply vanish — the one deadline you most need to see is the one
    /// you have already missed. A nil `days` is a row that has already come
    /// true and belongs at "now" for the same reason, which is why the
    /// parameter is Optional: an `Int` promotes at the call site, so a room
    /// whose days are non-optional passes them unchanged.
    ///
    /// A zero span cannot divide, and answers 0 rather than trapping.
    static func position(days: Int?, span: Int) -> Double {
        guard span > 0 else { return 0 }
        guard let days else { return 0 }
        return min(max(Double(days) / Double(span), 0), 1)
    }

    /// How far ahead the axis reaches. Rounded UP to a familiar horizon so the
    /// axis label reads as a period rather than as whatever the furthest
    /// deadline happens to be — and floored at a week, because a rail spanning
    /// two days puts a "3 days" mark off its own end.
    ///
    /// Cloudflare deliberately does NOT use this: its span is floored at its
    /// own fetch window and rounded to 30-day boundaries so the gridlines land,
    /// and a guard in `cloudflare-selftest.sh` ties the two together.
    static func span(days: [Int]) -> Int {
        let furthest = days.max() ?? 0
        for bound in [7, 14, 30, 60, 90] where furthest <= bound { return bound }
        return furthest
    }

    /// The rail's right-hand tick. Reads the same `span` the marks are placed
    /// against, so the axis can never be labelled with a length it isn't.
    ///
    /// Cloudflare deliberately keeps its own days-only label: its span is
    /// always a multiple of 30, so this would render every Cloudflare rail in
    /// months and hide that the window is exactly the fetch window.
    static func spanLabel(span: Int) -> String {
        span % 30 == 0 && span >= 30
            ? String(localized: "\(span / 30) mo")
            : String(localized: "\(span) days")
    }
}
