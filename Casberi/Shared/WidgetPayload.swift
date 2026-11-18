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
/// READING. A reading — a balance, a day's move — is a measurement with a
/// shelf life, and a widget has no choice but to persist it, so instead it
/// DROPS it once it ages out. The tile gets quieter, never wrong.
///
/// Four widgets read this, each a small tile (prd §1210, §1881): Notes,
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

/// Home's balance, as the Wallet widget draws it (prd §1881, amends §1210
/// item 2): the figure Home prints, its day, and Public and Private as Home's
/// two sections head them. Published BY HOME (`FeedScreen.homeWidgetFigures`),
/// from the very numbers it draws, so the tile and Home can never state two
/// totals; the line and the week's In and Out it drew before read the
/// followed addresses alone and are deleted.
///
/// Under Hide balances (§374) the figures are NOT PUBLISHED AT ALL: a Home
/// Screen tile is the most stood-next-to surface the OS has, and a figure that
/// was never written cannot leak through a rendering bug in a mask.
struct WidgetWalletHome: Codable, Equatable {
    /// Home's balance, or nil when withheld.
    let total: Double?
    /// The day's move in percent, or nil: unknown, or withheld. Nil is not
    /// zero (§83).
    let dayPct: Double?
    /// Home's Public head, or nil when withheld or when Home draws none.
    let publicUSD: Double?
    /// Home's Private head, or nil when withheld or when Home draws none.
    let privateUSD: Double?
    var hidden: Bool = false
    /// When the reading behind the figure was taken.
    let asOf: Date

    /// The figures Hide balances keeps off the Home Screen.
    static func withheld(asOf: Date) -> WidgetWalletHome {
        WidgetWalletHome(total: nil, dayPct: nil, publicUSD: nil, privateUSD: nil,
                         hidden: true, asOf: asOf)
    }
}

enum WidgetWallet {
    static let kind = "casberi.wallet"
    static let key = "widget.home"
    static let stampKey = "widget.homeAt"

    /// Money is the payload with the shortest honest life. Past this the tile
    /// declines rather than showing a two-day-old balance in the largest type
    /// on the screen — the one place §83 is most expensive to break.
    static let freshness: TimeInterval = 36 * 3600

    /// How old the reading may be before the tile says when it was read.
    static let stampAfter: TimeInterval = 4 * 3600

    static func published(now: Date = .now,
                          defaults: UserDefaults? = UserDefaults(suiteName: SharedStore.appGroup))
    -> WidgetWalletHome? {
        WidgetPayload.read(WidgetWalletHome.self, key: key, stampKey: stampKey,
                           freshness: freshness, now: now, defaults: defaults)
    }
}

// MARK: - Watchlist

/// Your first four watched tokens and the day's move of each, as the
/// Watchlist widget draws them (prd §1881; the Watchlist went with Markets,
/// §1529, and came back on Home, §1632). Prices, never balances, so Hide
/// balances has nothing here to withhold.
struct WidgetWatch: Codable, Equatable {
    let rows: [Row]

    struct Row: Codable, Equatable {
        let symbol: String
        /// The day's move in percent, or nil when unread.
        let dayPct: Double?
    }
}

enum WidgetWatchlist {
    static let kind = "casberi.watchlist"
    static let key = "widget.watch"
    static let stampKey = "widget.watchAt"
    /// A day's move is a day's reading: a day and a half, as the wallet's.
    static let freshness: TimeInterval = 36 * 3600
    /// The small tile's rows.
    static let rowCap = 4

    static func published(now: Date = .now,
                          defaults: UserDefaults? = UserDefaults(suiteName: SharedStore.appGroup))
    -> WidgetWatch? {
        WidgetPayload.read(WidgetWatch.self, key: key, stampKey: stampKey,
                           freshness: freshness, now: now, defaults: defaults)
    }

    /// The day's move as the tile prints it, and its direction: Home's
    /// Watchlist rule (`WatchlistRules.change`), spelled again here because
    /// the widget target cannot see the app's model. A move that rounds to
    /// zero has no sign and no colour (§83).
    static func change(_ percent: Double) -> (words: String, up: Bool?) {
        let tenths = (percent * 10).rounded()
        guard tenths != 0, percent.isFinite else { return ("0.0%", nil) }
        let magnitude = String(format: "%.1f%%", abs(tenths) / 10)
        return tenths > 0 ? ("+" + magnitude, true) : ("\u{2212}" + magnitude, false)
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

/// Today's Feed as Home's Activity draws it (prd §1881, amends §1210 item 3,
/// after §1864): each app's newest thing today, newest first, its icon and
/// its line, no name; then how many more came today. No money (§1208 item 7).
///
/// A today is a DATE's reading, so the payload carries its day. The widget
/// draws the rows only on that day and says so once it has passed; it never
/// shows yesterday's as today's.
struct WidgetFeed: Codable, Equatable {
    /// The start of the day the rows are for.
    let day: Date
    let rows: [Row]
    /// Everything else that came today, past the rows.
    let more: Int

    struct Row: Codable, Equatable {
        /// `Thing.id`, for `casberi://thing/<id>`.
        let id: String
        /// The app, whose icon leads (`WidgetFeedTile.markFile`).
        let source: String
        let title: String
        let at: Date
    }

    /// Whether the rows are for the day `now` is in.
    func isCurrent(now: Date = .now, calendar: Calendar = .current) -> Bool {
        calendar.isDate(day, inSameDayAs: now)
    }
}

enum WidgetFeedTile {
    static let kind = "casberi.feed"
    static let key = "widget.feedRows"
    static let stampKey = "widget.feedRowsAt"
    /// Two days: long enough to say "open Casberi for today" the morning after,
    /// short enough that a week-old row is not kept.
    static let freshness: TimeInterval = 48 * 3600
    /// The small tile's rows.
    static let rowCap = 3
    /// The app icons the rows lead with, drawn by the app (the widget cannot
    /// see its asset catalogue) into this app-group folder.
    static let marksFolder = "WidgetMarks"

    /// The file an app's icon is drawn to, by a name safe on disk.
    static func markFile(_ source: String) -> String {
        let safe = source.lowercased().unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }.joined()
        return safe + ".png"
    }

    /// Each app's newest thing, newest first, `rowCap` of them, and the count
    /// of everything else today. `items` are today's things, any order.
    static func rows(_ items: [WidgetFeed.Row]) -> (rows: [WidgetFeed.Row], more: Int) {
        var newest: [String: WidgetFeed.Row] = [:]
        for item in items where (newest[item.source]?.at ?? .distantPast) < item.at {
            newest[item.source] = item
        }
        let rows = Array(newest.values
            .sorted { $0.at != $1.at ? $0.at > $1.at : $0.id < $1.id }
            .prefix(rowCap))
        return (rows, items.count - rows.count)
    }

    static func published(now: Date = .now,
                          defaults: UserDefaults? = UserDefaults(suiteName: SharedStore.appGroup))
    -> WidgetFeed? {
        WidgetPayload.read(WidgetFeed.self, key: key, stampKey: stampKey,
                           freshness: freshness, now: now, defaults: defaults)
    }
}
