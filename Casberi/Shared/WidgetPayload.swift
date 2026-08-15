import Foundation

/// What the app publishes for the widgets to draw (2026-08-14, prd §382).
///
/// `WidgetLede` established the shape for one payload and this generalizes it
/// to the rest. The constraint is the same and it is not negotiable: the widget
/// extension runs in a ~30MB budget and cannot make a network read, so it can
/// never RECOMPUTE any of this. Every reading a tile shows was computed by the
/// app while it was open and left in the app group. The app writes, the widget
/// mirrors, and both sides name the keys here so a rename can't strand a tile
/// on a key nobody writes anymore.
///
/// THE RULE THIS FILE EXISTS TO ENCODE: a widget may show a stale QUESTION and
/// may show a stale DATE, but it may never show a stale READING. Those are
/// three different lifetimes and collapsing them into one freshness window is
/// how a home-screen tile ends up quietly lying:
///
///   - A standing question ("What's my wallet doing?") is durable. It was true
///     the day it was kept and it is true now.
///   - A deadline is a DATE. A date published yesterday is still exactly as
///     true today — it just means something different, which is why `overdue`
///     is never published as a flag and is always derived at draw time from the
///     date itself. A published boolean would be a fact that rots within
///     minutes of being written.
///   - A reading — a balance, a count, "3 things late" — is a measurement with
///     a shelf life. `KeptAskStore.currentDeltas` refuses to persist these at
///     all for exactly this reason ("restoring 'ETH is up 2.1%' from
///     UserDefaults at launch would put a stale number in the largest type on
///     the screen"). A widget has no choice but to persist them, so instead it
///     DROPS them once they age out and keeps the question standing alone. The
///     tile gets quieter, never wrong.
///
/// Freshness is therefore per-payload, not global — see each type's own window.
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

// MARK: - Kept asks

/// One kept standing question, as a widget draws it.
///
/// `reading` is `KeptAskComposers.Result.delta` — the one-line answer that ask's
/// own deterministic composer wrote ("3 things late", "$12,480 · up 2.1%"). It
/// is optional and it is the first thing to go: see `WidgetAsks.readingWindow`.
struct WidgetAskCell: Codable, Equatable {
    /// The stable kind string (`away`, `wallet`, `showtag:Recipes`) — the
    /// widget's configuration stores THIS, never the title, so re-wording a
    /// question can't orphan a tile somebody placed. Same reasoning
    /// `KeptAskStore` keys everything on kind.
    let kind: String
    /// The question as it was asked. This is also what the tap hands to
    /// `chrome.askRequest`, which is exactly what tapping the kept pill in the
    /// composer does (`draft = title; commit()`) — one door, so a widget can
    /// never open an answer the app itself wouldn't produce.
    let title: String
    /// The composer's own reading, or nil when it hasn't been computed since
    /// the app was last open long enough to matter.
    var reading: String?
    /// Whether this ask's answer had changed since it was last opened, as of
    /// publication. A presence signal only — never a count (§213).
    var changed: Bool = false
}

enum WidgetAsks {
    static let kind = "casberi.keptask"
    static let key = "widget.asks"
    static let stampKey = "widget.asksAt"

    /// How long a published set of kept asks stays worth drawing. Long, because
    /// the QUESTION is the durable part and a tile that empties overnight reads
    /// as broken.
    static let freshness: TimeInterval = 7 * 24 * 3600

    /// How long a READING inside one stays worth showing. Short, because a
    /// balance or a late-count is a measurement — past this the tile shows the
    /// question alone rather than a number nobody has checked since yesterday.
    /// Six hours is chosen so a morning reading survives the morning and no
    /// longer; anything that puts a number on a Home Screen overnight is
    /// claiming a freshness the app hasn't earned.
    static let readingWindow: TimeInterval = 6 * 3600

    /// The published asks. Readings are stripped once `readingWindow` has
    /// passed — the stripping happens HERE, at the one read door, so no tile
    /// layout can accidentally skip it.
    static func published(now: Date = .now,
                          defaults: UserDefaults? = UserDefaults(suiteName: SharedStore.appGroup))
    -> [WidgetAskCell] {
        guard let cells = WidgetPayload.read([WidgetAskCell].self, key: key, stampKey: stampKey,
                                             freshness: freshness, now: now, defaults: defaults),
              !cells.isEmpty
        else { return [] }
        let stamp = defaults?.double(forKey: stampKey) ?? 0
        guard now.timeIntervalSince1970 - stamp < readingWindow else {
            // Aged out: the questions stand, the numbers go, and `changed`
            // goes with them — a dot claiming "this moved" is a reading too.
            return cells.map { WidgetAskCell(kind: $0.kind, title: $0.title,
                                             reading: nil, changed: false) }
        }
        return cells
    }
}

/// The `casberi://ask?q=…` link a tile taps through to.
///
/// MEASURED, and it is why this is a function rather than one line at each call
/// site: **`CharacterSet.urlQueryAllowed` PERMITS `&`, `+`, `=` and `?`**,
/// because those are legal in a query STRING — they are only special inside a
/// query ITEM, which is exactly what the other end parses. So the obvious
/// spelling truncates any question containing an ampersand at the ampersand:
/// `"What's new with M&S?"` encodes unchanged, and `URLComponents` on the far
/// side hands back `q = "What's new with M"` plus a junk second item (measured
/// 2026-08-14). The tile then asks a question nobody asked, retrieves the wrong
/// things, and reads as the widget being broken.
///
/// A kept ask's title is whatever the person typed, so this is not a hypothetical
/// character set — it is the one class of question this feature is FOR.
enum WidgetAskLink {
    /// The sub-delimiters that mean something to the parser on the other side.
    /// `#` is already excluded by `urlQueryAllowed` (it starts a fragment).
    private static let allowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&+=?")
        return set
    }()

    static func url(asking question: String) -> URL? {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowed)
        else { return nil }
        return URL(string: "casberi://ask?q=\(encoded)")
    }
}

// MARK: - What the hero leads with

/// One app's share of the day, as a `SourceMix` cell.
///
/// `share` is a fraction of the day's rows, and it sizes the cell's AREA and
/// nothing else — no cell ever prints its count (§213). The name is the app's
/// own, and the tile draws a monogram rather than a brand mark: `Design/` is
/// app-target only, so the extension has no access to the bundled icons, and
/// `AssetMark`'s rule for a name we don't bundle is a neutral monogram rather
/// than an invented hue.
struct WidgetSourceCell: Codable, Equatable {
    let name: String
    let share: Double
}

/// What the hero tile leads with today (2026-08-14, prd §382 amendment).
///
/// It used to be the themes treemap, always — three abstract cells carrying
/// three WORDS, which is the weakest thing the brief draws and the only one
/// you have to read before it tells you anything. The brief's own vocabulary is
/// far richer, so the tile now leads with whichever of those modules the day
/// actually earns, in the order the mockup settled on:
///
///   1. **Pictures.** A contact sheet of the day's own thumbnails. The
///      strongest lead there is, because its cells are the day itself rather
///      than an abstraction of it — and it costs no new published bytes: the
///      extension already reads the shared store, so it fetches the thumbnails
///      the same way it fetches the newest rows.
///   2. **Money**, when the wallet moved and there are no pictures.
///   3. **The source mix**, one big cell and two stacked (§194), each wearing
///      its app's monogram — the same information the treemap was reaching for,
///      readable without reading.
///   4. **Nothing.** A day with none of the above draws no frame at all rather
///      than an empty one, which is the same "decline rather than fill" rule
///      every room head in the app already follows.
struct WidgetDayLead: Codable, Equatable {
    enum Kind: String, Codable { case pictures, money, sources, none }
    var kind: Kind
    /// How many of the day's things carry a picture. The BYTES are not
    /// published — the widget fetches those from the store itself — but the
    /// count is, because it is what decides the lead, and that decision belongs
    /// to the app (the widget computes nothing).
    var pictures: Int = 0
    var sources: [WidgetSourceCell] = []
    /// The apps the mix leaves out, for the residual line ("and 4 other apps").
    var otherSources: Int = 0
}

extension WidgetDayLead {
    /// PURE, and separated from the gathering so it can be tested: the day's
    /// lead is decided here and nowhere else.
    ///
    /// `pictureFloor` exists because three thumbnails do not read as a contact
    /// sheet — they read as a row that failed to fill. Below it the day falls
    /// through to whatever it can honestly say instead.
    static let pictureFloor = 4
    /// Two cells is the fewest that can show a SHARE. One cell is not a mix, it
    /// is a title with a box around it.
    static let sourceFloor = 2

    static func kind(pictures: Int, moneyMoved: Bool, sources: Int) -> Kind {
        if pictures >= pictureFloor { return .pictures }
        if moneyMoved { return .money }
        if sources >= sourceFloor { return .sources }
        return .none
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

// MARK: - Deadlines

/// One thing with a real deadline, as a widget draws it.
///
/// Deliberately carries no `overdue` flag and no "in 3 days" string — both are
/// facts about NOW, and a widget's timeline entry may be drawn hours after it
/// was made. Only the date is published; every reading of it happens at draw
/// time. This is the same reason `TodayBrief` stamps when an event happened
/// rather than implying it just did.
struct WidgetDeadline: Codable, Equatable {
    /// The thing's own id, so a row can open it (`casberi://thing/<id>`) rather
    /// than dumping you at the feed to go find it yourself.
    let id: String
    let title: String
    /// Which app it came from — a deadline with no provenance is a demand from
    /// nowhere.
    let source: String
    let due: Date
}

extension WidgetDeadline {
    /// Read at DRAW time, never published. See the type's own note: a boolean
    /// written into a timeline entry is a claim about a `now` that has already
    /// passed by the time anyone sees the tile.
    func isOverdue(now: Date = .now) -> Bool { due < now }
}

/// Deadlines on a rail (2026-08-14, prd §382 amendment) — the brief's own
/// `Runway`, at widget scale.
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

enum WidgetDeadlines {
    static let kind = "casberi.needsyou"
    static let key = "widget.deadlines"
    static let stampKey = "widget.deadlinesAt"

    /// Dates don't rot, but the SET does — something gets marked done, a
    /// dispute closes. A day and a half is the same window `WidgetLede` uses
    /// and for the same reason: it survives a night, not a weekend away.
    static let freshness: TimeInterval = 36 * 3600

    /// How many the app publishes. The large family shows four and the medium
    /// three; one spare so a row that has since passed its date doesn't leave a
    /// hole.
    static let publishCap = 5

    static func published(now: Date = .now,
                          defaults: UserDefaults? = UserDefaults(suiteName: SharedStore.appGroup))
    -> [WidgetDeadline] {
        WidgetPayload.read([WidgetDeadline].self, key: key, stampKey: stampKey,
                           freshness: freshness, now: now, defaults: defaults) ?? []
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
