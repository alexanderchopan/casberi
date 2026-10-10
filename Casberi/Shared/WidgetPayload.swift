import Foundation

/// What the app publishes for the widgets to draw (2026-08-14, prd §382).
///
/// The constraint is not negotiable: the widget extension runs in a ~30MB
/// budget and cannot make a network read, so it can never RECOMPUTE any of
/// this. Every reading a tile shows was computed by the app while it was open
/// and left in the app group. The app writes, the widget mirrors, and both
/// sides name the keys here so a rename can't strand a tile on a key nobody
/// writes anymore.
///
/// THE RULE THIS FILE EXISTS TO ENCODE: a widget may never show a stale
/// READING. A reading — a balance, a week's flow — is a measurement with a
/// shelf life, and a widget has no choice but to persist it, so instead it
/// DROPS it once it ages out. The tile gets quieter, never wrong.
///
/// Four widgets read this, each a small tile (prd §1210, §1223): Notes,
/// Wallet, the Feed and the Watchlist. The Today widget and the kept-ask
/// widget went with the ask (2026-10-01), the Category widget with §1210, and
/// their payloads with them.
///
/// Freshness is per-payload, not global — see each type's own window.
enum WidgetPayload {

    /// One coder for both sides. Not fussiness: `JSONEncoder`'s default date
    /// strategy is `.deferredToDate` and its ISO/secondsSince1970 alternatives
    /// are one line away, so an edit on the writing side that looks purely
    /// cosmetic makes every `decode` on the reading side return nil — and a
    /// payload that fails to decode is indistinguishable from one that was
    /// never published. Every tile would empty at once with nothing in any log
    /// to say why. Both directions go through here so there is only ever one
    /// strategy to change.
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()

    /// Reads a stamped payload, or nil when there isn't a fresh one. The
    /// staleness rule lives here rather than in each caller so a new tile
    /// can't quietly forget it.
    static func read<T: Decodable>(_ type: T.Type, key: String, stampKey: String,
                                   freshness: TimeInterval, now: Date = .now,
                                   defaults: UserDefaults?) -> T? {
        guard let defaults, let data = defaults.data(forKey: key),
              let value = try? decoder.decode(type, from: data)
        else { return nil }
        let stamp = defaults.double(forKey: stampKey)
        guard stamp > 0, now.timeIntervalSince1970 - stamp < freshness else { return nil }
        return value
    }

    /// Writes (or clears) a payload and says whether the CONTENT changed.
    ///
    /// The return value is the whole point: `WidgetCenter.reloadTimelines` is
    /// budgeted by the system, and every one of these publishes runs on every
    /// foreground. Reloading unconditionally spends that budget writing the
    /// same payload back — `TodayBrief.publishLedeToWidget` learned this first
    /// and this is the same rule, generalized so each new payload doesn't have
    /// to remember it. The STAMP is deliberately excluded from the comparison:
    /// it moves on every pass by construction, so comparing it would make every
    /// publish look like a change and defeat the check entirely.
    ///
    /// MEASURED, and the reason this decodes rather than comparing bytes:
    /// **`JSONEncoder` is not byte-stable across calls for identical input.**
    /// Encoding the same value twice in one process produced two 60-byte
    /// payloads that were not equal (measured 2026-08-14, macOS 26). So the
    /// obvious implementation — keep the old `Data`, compare it to the new
    /// `Data` — reports a change EVERY TIME, which is the exact behaviour this
    /// function exists to prevent, and it fails silently: tiles refresh more
    /// than they should and nothing anywhere says so. It was written that way
    /// first and caught only because the harness asserted the negative case.
    /// Comparing decoded VALUES is stable because it compares what the payload
    /// means rather than how it happened to serialize.
    ///
    /// `T` is `Codable & Equatable` for that reason, not for tidiness — do not
    /// relax it back to `Encodable`.
    @discardableResult
    static func write<T: Codable & Equatable>(_ value: T?, key: String, stampKey: String,
                                              defaults: UserDefaults?) -> Bool {
        guard let defaults else { return false }
        let stored = defaults.data(forKey: key)
        let previous = stored.flatMap { try? decoder.decode(T.self, from: $0) }
        guard let value, let data = try? encoder.encode(value) else {
            defaults.removeObject(forKey: key)
            defaults.removeObject(forKey: stampKey)
            return stored != nil
        }
        defaults.set(data, forKey: key)
        defaults.set(Date.now.timeIntervalSince1970, forKey: stampKey)
        return previous != value
    }
}

// MARK: - The flow band

/// A week of money in against money out (2026-08-14, prd §382b) —
/// `WalletFlow.Band` reduced to what a tile can draw.
///
/// A sparkline answers "did the total move". This answers "what moved it",
/// which is the question the curve raises and cannot settle.
///
/// **NO COUNTERPARTY NAMES, by ruling** (user: "we don't need counterparties
/// b/c i dunno how it would fit"). The room's band names every lane; at 170pt
/// a name is a truncation, and dropping them also settles the §374-adjacent
/// question a lock screen would otherwise raise — who you pay is arguably more
/// exposing than what you hold, and this way the tile never says.
///
/// **What could NOT be dropped with them is the disclosure.** `WalletFlow.Band`
/// carries two counts on purpose and its own header states the rule: "a band
/// drawn from 6 of 9 moves is a different claim from one drawn from all 9, and
/// the no-silent-caps rule says the drawing has to say so". Losing the lane
/// names loses detail; losing the disclosure would make the bars claim a
/// completeness they don't have. So the counts travel, and the tile says
/// "6 of 9 priced" whenever there is a gap.
struct WidgetFlowBand: Codable, Equatable {
    /// The two bar widths, 0…1 of the wider side. ALWAYS present, because a
    /// ratio is a shape and §374 rule 3 keeps shapes — and because deriving
    /// them from the dollar figures would mean withholding the figures kills
    /// the bars, which is the trap the first draft of this walked into.
    let inWeight: Double
    let outWeight: Double
    /// The figures, or nil when withheld (§374) — the same shape as
    /// `WidgetWalletLine.total`, and withheld for the same reason: a Home
    /// Screen is the most stood-next-to surface the OS has, and a figure that
    /// was never written cannot be leaked by a rendering bug.
    let inUSD: Double?
    let outUSD: Double?
    /// Legs that reached us with no price — they COULD have been priced and
    /// weren't. Kept apart from `predating` because only this one says
    /// anything about how well the read is working.
    let unpriced: Int
    /// Legs older than price data itself, which never can be priced. A
    /// different fact, disclosed for the same reason.
    let predating: Int
    /// How many legs are actually IN the bars.
    let priced: Int
    /// Hide wallet balances (§374). The figures are withheld exactly as the
    /// wallet line's are — and the bars keep their proportions, because a
    /// ratio is a shape.
    var hidden: Bool = false
}

extension WidgetFlowBand {
    /// The two bar widths as 0…1 of the wider side, so the larger flow fills
    /// the track and the smaller reads against it.
    ///
    /// A side of zero draws NOTHING rather than a hairline: "no money went out
    /// this week" and "a sliver went out" are different weeks, and at this size
    /// a minimum-width stub is how they start looking the same.
    ///
    /// Computed once by the publisher and carried, never recomputed from the
    /// figures — see `inWeight`.
    static func weights(inUSD: Double, outUSD: Double) -> (Double, Double) {
        let scale = max(inUSD, outUSD)
        guard scale > 0 else { return (0, 0) }
        return (inUSD / scale, outUSD / scale)
    }

    /// Every leg the window held, priced or not.
    var total: Int { priced + unpriced + predating }

    /// Whether the bars are drawn from less than the whole window — the one
    /// thing the tile must say out loud.
    var isPartial: Bool { unpriced + predating > 0 }

    /// Whether the tile owes a "6 of 9 priced" line.
    ///
    /// The FACT lives here and the SENTENCE lives in the widget (see
    /// `WalletWidgetView.pricedNote`) — deliberately, because this file compiles
    /// into the app and the share extension as well as the extension that draws
    /// tiles, and a `String(localized:)` here puts a widget-only sentence into
    /// all three string catalogs, where two of them can never show it.
    ///
    /// It is the one piece of the room's band that could NOT be dropped along
    /// with the lane names. `WalletFlow.Band`'s own header states the rule:
    /// "a band drawn from 6 of 9 moves is a different claim from one drawn from
    /// all 9, and the no-silent-caps rule says the drawing has to say so".
    /// Losing the names loses detail; losing this would make two bars claim a
    /// completeness they don't have.
    var owesDisclosure: Bool { isPartial && total > 0 }
}

// MARK: - The dated rail

/// Deadlines on a rail (2026-08-14, prd §382 amendment). Born for the Today
/// widget; since that widget went with the ask (2026-10-01) its one reader is
/// the wallet's dated rail (`WalletRow`), and it stays here, Foundation-only,
/// so `widget-selftest.sh` keeps compiling it whole.
///
/// A list of four rows says what the next four things are. A rail says the
/// SHAPE of the week: two behind you, three ahead, and roughly how far. That is
/// a reading a list cannot give at any size, which is why this earns space
/// above the rows rather than replacing them.
///
/// THE INVARIANT, inherited verbatim from `GenRunway`: **the window always
/// contains now.** An overdue item pushes the left edge back and everything
/// ahead stays right of the marker. Get that wrong and the rail becomes a
/// confident lie — late items drawn ahead of the marker, which is precisely
/// the distinction the whole tile exists to make.
enum WidgetRunway {
    /// Padding at each end so a dot at either extreme isn't clipped in half by
    /// the track it sits on. A twentieth, the same as the brief's.
    static let pad = 0.05

    /// Each date's position as 0…1 along the track, plus where `now` sits.
    ///
    /// Returns nil when there is nothing to place, and — deliberately — also
    /// when every date is the SAME MOMENT: a zero-width window has no shape to
    /// draw, and the naive division would be by zero. The rows below say it
    /// instead.
    static func positions(for dates: [Date], now: Date = .now)
    -> (dots: [Double], now: Double)? {
        guard !dates.isEmpty else { return nil }
        // `now` is folded into the window rather than clamped onto it, which is
        // what makes the invariant structural instead of a rule to remember.
        let low = min(dates.min() ?? now, now)
        let high = max(dates.max() ?? now, now)
        let span = high.timeIntervalSince(low)
        guard span > 0 else { return nil }
        let place = { (d: Date) -> Double in
            pad + (d.timeIntervalSince(low) / span) * (1 - 2 * pad)
        }
        return (dates.map(place), place(now))
    }
}

// MARK: - Wallet

/// The combined wallet line, as a widget draws it.
///
/// `points` is `WalletStore.combinedValueSamples()` reduced to plain USD
/// figures — the same forward-only, never-back-filled series the app's own
/// balance card draws, so the widget's curve and the app's curve can never
/// disagree about history.
struct WidgetWalletLine: Codable, Equatable {
    /// Oldest first. Never more than `WidgetWallet.pointCap` — a home-screen
    /// sparkline is ~150pt wide and anything past that is bytes nobody can see.
    let points: [Double]
    /// The latest figure, or nil when it is WITHHELD — see `hidden`. Carried
    /// explicitly rather than read back out of `points` because the tile prints
    /// it, and taking it from the array at three call sites is how the printed
    /// number and the drawn curve end up describing different moments.
    let total: Double?
    /// Percent change across the drawn window, or nil when there aren't two
    /// points to difference (or it is withheld). Nil is NOT zero: zero has a
    /// meaning ("it didn't move") and claiming it when we don't know is §83's
    /// fake status.
    var changePct: Double?
    /// Hide wallet balances is on (§374).
    ///
    /// The figures are not merely masked at draw time here — they are NOT
    /// PUBLISHED AT ALL, which is a deliberate divergence from §374's rule 1
    /// ("mask at the render boundary and nowhere else"). That rule exists
    /// because masking inside `TokenStats.compact`/`WalletIngest.format` would
    /// write `••••` into PERSISTED, CLOUDKIT-SYNCED model data, where it would
    /// survive the toggle being turned back off. This payload is neither: it is
    /// a transport, republished from scratch on every foreground, so withholding
    /// costs exactly one republish and removes the leak path completely. And
    /// the leak path is the point — §374's threat is what somebody standing
    /// next to you can read, and a Home Screen tile is the most stood-next-to
    /// surface the OS has. A rendering bug in a mask cannot expose a figure that
    /// was never written.
    ///
    /// §374 rule 3 still holds exactly: figures go, SHAPES stay. `points` is
    /// published either way and the curve draws either way — nobody reads a net
    /// worth off an unlabelled line, and blanking it would leave the tile empty
    /// rather than private.
    var hidden: Bool = false
    /// When the last point was sampled. The tile stamps this whenever it is old
    /// enough to matter — "$12,480" and "$12,480 · as of 5h ago" are different
    /// claims and only one of them is true after five hours.
    let asOf: Date
}

extension WidgetWalletLine {
    /// The curve as 0…1, oldest first, for a sparkline to draw.
    ///
    /// A FLAT series returns 0.5 for every point, and that is the whole reason
    /// this is a named function with a test rather than two lines inside a
    /// `Path`. The obvious normalization divides by the range, which for a flat
    /// series is zero — so the naive guard against dividing by zero returns 0,
    /// which draws the line along the FLOOR of the tile. A wallet that did
    /// nothing then reads as a wallet that went to zero: the most alarming
    /// possible way to say nothing happened. `AgentPanel` has carried this rule
    /// (and a mutation test for it) since §334; this is the same rule at the one
    /// place the app draws a curve in another process.
    var normalizedPoints: [Double] {
        guard let low = points.min(), let high = points.max() else { return [] }
        let span = high - low
        guard span > 0 else { return points.map { _ in 0.5 } }
        return points.map { ($0 - low) / span }
    }
}

enum WidgetWallet {
    static let kind = "casberi.wallet"
    static let key = "widget.wallet"
    static let stampKey = "widget.walletAt"
    static let flowKey = "widget.flow"
    static let flowStampKey = "widget.flowAt"

    /// The week's flow band (§382b), or nil when there isn't a fresh one. Shares the
    /// line's own freshness window: both are readings about the same wallet at
    /// the same moment, and a band that outlived the figure above it would be
    /// describing a week the total no longer belongs to.
    static func flow(now: Date = .now,
                     defaults: UserDefaults? = UserDefaults(suiteName: SharedStore.appGroup))
    -> WidgetFlowBand? {
        WidgetPayload.read(WidgetFlowBand.self, key: flowKey, stampKey: flowStampKey,
                           freshness: freshness, now: now, defaults: defaults)
    }

    /// Money is the payload with the shortest honest life. Past this the tile
    /// declines rather than showing a two-day-old balance in the largest type
    /// on the screen — the one place §83 is most expensive to break.
    static let freshness: TimeInterval = 36 * 3600

    /// How old the last sample may be before the tile stamps it. Wallet
    /// sampling is throttled to one point per four hours (`recordSample`), so
    /// anything under that is simply the normal cadence and stamping it would
    /// cry wolf on every tile, all day.
    static let stampAfter: TimeInterval = 4 * 3600

    static let pointCap = 60

    static func published(now: Date = .now,
                          defaults: UserDefaults? = UserDefaults(suiteName: SharedStore.appGroup))
    -> WidgetWalletLine? {
        WidgetPayload.read(WidgetWalletLine.self, key: key, stampKey: stampKey,
                           freshness: freshness, now: now, defaults: defaults)
    }
}

// MARK: - Notes

/// Your newest notes, for the Notes widget (prd §1210). Small tile only.
///
/// A row is not a READING: "the newest note" stays true until a newer one
/// lands. So the window is a week, not a day and a half, and past it the tile
/// asks you to open the app rather than listing what was newest a week ago.
struct WidgetShelf: Codable, Equatable {
    /// The room the tile opens (`casberi://room/<room>`): `Pinboard.room`.
    let room: String
    /// The word the tile draws ("Notes").
    let name: String
    let glyph: String
    let rows: [Row]

    struct Row: Codable, Equatable {
        /// `Thing.id`, for `casberi://thing/<id>`.
        let id: String
        let title: String
        let source: String
        let at: Date
    }
}

enum WidgetNotes {
    static let kind = "casberi.notes"
    static let key = "widget.notes"
    static let stampKey = "widget.notesAt"
    static let freshness: TimeInterval = 7 * 24 * 3600
    /// The small tile's two rows.
    static let rowCap = 2
    /// Notes' room name, spelled here because `Pinboard` is app-side.
    static let notesRoom = "Your notes"

    static func published(now: Date = .now,
                          defaults: UserDefaults? = UserDefaults(suiteName: SharedStore.appGroup))
    -> WidgetShelf? {
        WidgetPayload.read(WidgetShelf.self, key: key, stampKey: stampKey,
                           freshness: freshness, now: now, defaults: defaults)
    }
}

// MARK: - The Feed

/// The Feed's contents in Feed order, for the Feed widget (prd §1210): each
/// category with something today, in `CategoryOrder.current` (Settings › Feed
/// order), and how many came today. The Feed's glance tiles (§1208d) at the
/// size of one Home Screen tile.
///
/// A count of today is a DATE's reading, so the payload carries the day it
/// counted. The widget draws the counts only on that day and says so once it
/// has passed; it never shows yesterday's counts as today's.
struct WidgetFeed: Codable, Equatable {
    /// The start of the day the counts are for.
    let day: Date
    let sections: [Section]

    struct Section: Codable, Equatable {
        /// The category's name.
        let room: String
        /// How many came today.
        let today: Int
    }

    /// Whether the counts are for the day `now` is in.
    func isCurrent(now: Date = .now, calendar: Calendar = .current) -> Bool {
        calendar.isDate(day, inSameDayAs: now)
    }
}

enum WidgetFeedTile {
    static let kind = "casberi.feed"
    static let key = "widget.feed"
    static let stampKey = "widget.feedAt"
    /// Two days: long enough to say "open Casberi for today" the morning after,
    /// short enough that a week-old order is not kept.
    static let freshness: TimeInterval = 48 * 3600
    /// The small tile's rows.
    static let rowCap = 4

    static func published(now: Date = .now,
                          defaults: UserDefaults? = UserDefaults(suiteName: SharedStore.appGroup))
    -> WidgetFeed? {
        WidgetPayload.read(WidgetFeed.self, key: key, stampKey: stampKey,
                           freshness: freshness, now: now, defaults: defaults)
    }
}

// MARK: - The watchlist

/// What you follow in Markets, for the Watchlist widget: each row's symbol,
/// the price this app last read and its day move, in the watchlist's own
/// order (`TokenWatchOrder`). Small tile only.
///
/// A row is not a reading; its price is. So the payload keeps a week, like
/// Notes' shelf, and each price carries the moment it was read: the tile
/// stamps a price past `stampAfter` and drops one past `priceFreshness`,
/// leaving the symbol standing alone rather than an old price drawn as now's
/// (§83).
struct WidgetWatchlist: Codable, Equatable {
    let rows: [Row]

    struct Row: Codable, Equatable {
        /// The watched row's `sourceRef`: what a later publish carries a
        /// price forward by.
        let ref: String
        /// The ticker or the token's symbol ("AAPL", "ETH").
        let symbol: String
        /// The company's or the token's name, for VoiceOver.
        let name: String
        let price: Double?
        /// The day move as a FRACTION (-0.048 is -4.8%), `TokenPulse`'s unit.
        let change: Double?
        /// When the price was read. Nil with no price.
        let at: Date?
    }
}

enum WidgetWatch {
    static let kind = "casberi.watchlist"
    static let key = "widget.watchlist"
    static let stampKey = "widget.watchlistAt"
    /// The list itself: a week, as Notes'.
    static let freshness: TimeInterval = 7 * 24 * 3600
    /// A price past this is not drawn.
    static let priceFreshness: TimeInterval = 24 * 3600
    /// A price past this is stamped ("as of 3h ago"). A watched token's pulse
    /// is read at most every 15 minutes while the app is open, so an hour is
    /// past the normal cadence.
    static let stampAfter: TimeInterval = 3600
    /// The small tile's rows.
    static let rowCap = 4

    static func published(now: Date = .now,
                          defaults: UserDefaults? = UserDefaults(suiteName: SharedStore.appGroup))
    -> WidgetWatchlist? {
        WidgetPayload.read(WidgetWatchlist.self, key: key, stampKey: stampKey,
                           freshness: freshness, now: now, defaults: defaults)
    }

    /// The row's price and move if they may be drawn at `now`: read, and
    /// read within `priceFreshness`.
    static func quote(_ row: WidgetWatchlist.Row, now: Date = .now)
    -> (price: Double, change: Double?, at: Date)? {
        guard let price = row.price, let at = row.at,
              now.timeIntervalSince(at) < priceFreshness else { return nil }
        return (price, row.change, at)
    }

    /// A price in the tile's narrow column: whole dollars from $1,000, cents
    /// from $1, four places under it, three significant digits under a cent.
    static func priceText(_ price: Double) -> String {
        if price >= 1_000 {
            return "$" + price.formatted(.number.precision(.fractionLength(0)))
        }
        if price >= 1 { return String(format: "$%.2f", price) }
        if price >= 0.01 { return String(format: "$%.4f", price) }
        return "$" + price.formatted(.number.precision(.significantDigits(1...3)).grouping(.never))
    }

    /// Carries a price forward from the last publish for a row this pass
    /// could not price (a cold launch whose read failed), so the tile keeps
    /// the last price with its stamp rather than blanking it. A carried price
    /// still ages out by its own `at`.
    static func carryForward(_ rows: [WidgetWatchlist.Row],
                             from previous: WidgetWatchlist?) -> [WidgetWatchlist.Row] {
        guard let previous else { return rows }
        let old = Dictionary(previous.rows.map { ($0.ref, $0) }, uniquingKeysWith: { a, _ in a })
        return rows.map { row in
            guard row.price == nil, let last = old[row.ref], last.price != nil else { return row }
            return WidgetWatchlist.Row(ref: row.ref, symbol: row.symbol, name: row.name,
                                       price: last.price, change: last.change, at: last.at)
        }
    }
}
