import Foundation
// `os(iOS)` beside the usual pair: the harness compiles this file on a Mac,
// where the rule below must build and the attributes must not.
#if canImport(ActivityKit) && os(iOS) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif

/// ONE PRICE ON THE LOCK SCREEN (prd §1250): a row you follow in Markets,
/// pinned from its long press — its symbol, the price this app last read, the
/// day's move and the day's line. One at a time: pinning another replaces it.
///
/// **It is a reading, never a ticker.** There is no push server, so the price
/// moves only when the app reads it (the foreground pulse, the background
/// task iOS grants), and the activity says how old it is the way the widget
/// does (§1223): past `stampAfter` the view reads "as of 3:42 PM", through
/// ActivityKit's own `staleDate`, so iOS flips it even while the app sleeps.
/// It ends after `lifetime` (iOS's own ceiling for an activity), or when you
/// unpin it.
///
/// Prices of what you follow are not your money (§1223 item 4): no holding is
/// carried, so Hide balances has nothing to withhold here.
///
/// `PriceLive` is Foundation-only and outside the `#if`, so
/// `scripts/widget-selftest.sh` compiles the rule whole.
enum PriceLive {
    /// Past this the activity says when its price was read.
    static let stampAfter: TimeInterval = 15 * 60
    /// The activity ends this long after it was pinned.
    static let lifetime: TimeInterval = 8 * 3600

    /// ActivityKit's stale date for a price read at `at`: the moment the
    /// view must start saying its age.
    static func staleDate(at: Date) -> Date { at.addingTimeInterval(stampAfter) }

    static func stamped(at: Date, now: Date) -> Bool { now.timeIntervalSince(at) > stampAfter }

    static func expired(pinnedAt: Date, now: Date) -> Bool { now.timeIntervalSince(pinnedAt) >= lifetime }

    /// "as of 3:42 PM" once the price is past `stampAfter`, else nil.
    static func stampText(at: Date, now: Date, stale: Bool = false) -> String? {
        guard stale || stamped(at: at, now: now) else { return nil }
        return String(localized: "as of \(at.formatted(date: .omitted, time: .shortened))")
    }

    /// Whether a read may move the activity: only a price read after the one
    /// it shows, so a slower path landing late never steps it backwards.
    static func advances(shown: Date, read: Date) -> Bool { read > shown }
}

#if canImport(ActivityKit) && os(iOS) && !targetEnvironment(macCatalyst)
struct PriceActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let price: Double
        /// The day move as a FRACTION, `TokenPulse`'s unit; nil when the read
        /// carried none.
        let change: Double?
        /// The day's closes, oldest first, thinned (`WidgetWatch.sparkCloses`);
        /// nil for a row with no line.
        let closes: [Double]?
        /// When the price was read.
        let at: Date
    }

    /// The followed row's `sourceRef`: what a read updates it by.
    let ref: String
    let symbol: String
    let name: String
    /// `Thing.id`, so a tap opens the row's page.
    let thingID: String
    let pinnedAt: Date
}
#endif
