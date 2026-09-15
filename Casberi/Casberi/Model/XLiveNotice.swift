import Foundation

/// WHEN an X notice happened, and whether a notice already landed has moved on
/// since (prd §741) — the pure half of `XLiveNotifications`, Foundation-only so
/// `x-live-selftest.sh` compiles it WHOLE.
///
/// **The two defects this answers** (user, 2026-09-14: "they refreshed but
/// don't show the newest likes… they show some from hours ago and say they
/// were from minutes ago"):
///   · every notice was stamped `capturedAt: .now`, the moment the sweep read
///     it, so a like from four hours ago that first landed on this minute's
///     sweep read "2 min ago" — the Instagram and TikTok doors both stamp the
///     payload's own time and X never did;
///   · X AGGREGATES: "Ana and 4 others liked your post" is ONE entry whose id
///     holds while the sentence grows and the entry climbs back to the top. The
///     ref dedupe saw the id, backfilled a face, and left the old sentence and
///     the old time in place, so the newest likes never showed.
///
/// **UNMEASURED, like the rest of the X door:** no X session is reachable from
/// a build host. The time is read from `itemContent.timestamp_ms` and then the
/// entry's `sortIndex`, the two places X's timeline responses carry one, and a
/// value is believed only if it decodes to a date between X's founding and a
/// day from now — so a field that turns out not to be a time lands the notice
/// at the moment it was read (the old behaviour), never at a wrong hour.
/// `-xLiveProbe` prints both raw values and the date chosen.
enum XLiveNoticeTime {
    /// X's snowflake epoch (2010-11-04): an id's top 42 bits are milliseconds
    /// since this.
    static let snowflakeEpochMS: Int64 = 1_288_834_974_657

    /// The earliest date a notice can carry — X's first post, 2006-03-21.
    static let earliest = Date(timeIntervalSince1970: 1_142_899_200)

    /// The notice's own time, or nil when the entry carries none this file can
    /// believe.
    static func date(entry: [String: Any], now: Date) -> Date? {
        let content = entry["content"] as? [String: Any]
        let item = content?["itemContent"] as? [String: Any]
        for raw in [item?["timestamp_ms"], content?["timestamp_ms"], entry["sortIndex"]] {
            if let date = date(raw, now: now) { return date }
        }
        return nil
    }

    /// One raw value — a string or a JSON number — read as seconds,
    /// milliseconds or a snowflake by its magnitude, and kept only if plausible.
    static func date(_ raw: Any?, now: Date) -> Date? {
        guard let n = integer(raw), n > 0 else { return nil }
        let seconds: Double
        switch n {
        case 1_000_000_000..<10_000_000_000:
            seconds = Double(n)
        case 1_000_000_000_000..<10_000_000_000_000:
            seconds = Double(n) / 1000
        case 1_000_000_000_000_000...:
            seconds = Double((n >> 22) + snowflakeEpochMS) / 1000
        default:
            return nil
        }
        let date = Date(timeIntervalSince1970: seconds)
        guard date >= earliest, date <= now.addingTimeInterval(86_400) else { return nil }
        return date
    }

    private static func integer(_ raw: Any?) -> Int64? {
        if let s = raw as? String { return Int64(s.trimmingCharacters(in: .whitespaces)) }
        if let n = raw as? NSNumber {
            // A JSON number arrives as NSNumber; a Double with a fraction is
            // not an id or a timestamp X sends.
            let d = n.doubleValue
            guard d.rounded() == d, abs(d) < 9.2e18 else { return nil }
            return n.int64Value
        }
        return nil
    }

    /// What to rewrite on a notice that has already landed.
    ///
    /// `title`: the sentence changed — an aggregate grew ("and 4 others") or X
    /// reworded it. `at`: the notice's own time differs from the stored one by
    /// more than a minute, in EITHER direction — later is an aggregate that
    /// climbed back to the top, earlier is a row the old code stamped with the
    /// sweep's clock. A nil time never moves a row.
    static func changes(storedTitle: String, storedAt: Date,
                        title: String, at: Date?) -> (title: Bool, at: Bool) {
        let retitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            != storedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            && !title.isEmpty
        let restamp = at.map { abs($0.timeIntervalSince(storedAt)) > 60 } ?? false
        return (retitle, restamp)
    }
}
