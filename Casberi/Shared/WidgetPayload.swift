import Foundation

/// What the app publishes for the widgets to draw (2026-08-14, prd §382).
///
/// The hero's lede (deleted in §877) established the shape for one payload; this generalizes it
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
    // No `kind` of its own since prd §877: the deadlines ride the Today tile,
    // which reloads under `WidgetToday.kind`.
    static let key = "widget.deadlines"
    static let stampKey = "widget.deadlinesAt"

    /// Dates don't rot, but the SET does — something gets marked done, a
    /// dispute closes. A day and a half is the same window the hero's lede used
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

// MARK: - A signature somebody is waiting on

/// What a Safe is waiting on YOU for (2026-08-17).
///
/// This tile's subject is things that want something from you, and until now
/// it could only see `dueAt` — so the clearest "needs you" fact the whole app
/// carries never reached it. A your-turn signature has NO DATE (Safe publishes
/// a `submissionDate`, which is when it was asked, not when it is due), so it
/// can never be a `WidgetDeadline` and must not be faked into one: putting a
/// made-up due date on the rail would place it among real deadlines and let it
/// draw as "late", which is a claim nobody made.
///
/// It is a READING, so it takes the short shelf life — a signature collected
/// in the Safe app five minutes after you looked makes every count here wrong,
/// and no amount of the app being closed makes that number true again.
struct WidgetSafeCall: Codable, Equatable {
    /// The row to open, when the pending transaction is in the corpus.
    /// Optional because the tracking store and the corpus are two different
    /// records: a queue item can be tracked before its row has landed. The
    /// tile falls back to the ask rather than minting a link to nothing.
    let id: String?
    /// "a transfer of 1,500 USDC to payroll.eth" — the bridge's own rendering,
    /// never re-derived here.
    let subject: String
    /// Transactions whose missing signature is genuinely yours — `awaitsYou`,
    /// not `yourTurn`: a threshold already met without you needs nothing from
    /// you, and this tile exists to say what does.
    let awaitsYou: Int
    /// Fully signed, waiting only on an execution. Counted apart because it is
    /// a different act by a different person.
    let ready: Int
    /// Whole days the oldest request has waited, or nil when the wire carried
    /// no submission date. Nil is not zero — "waiting" and "waiting 0 days"
    /// are different claims.
    let waitingDays: Int?
}

enum WidgetSafe {
    static let key = "widget.safe"
    static let stampKey = "widget.safeAt"

    /// Six hours, the reading window — deliberately far shorter than the
    /// 36-hour deadline set beside it in the same tile. See the type's doc:
    /// dates don't rot and counts do.
    static let freshness: TimeInterval = 6 * 3600

    static func published(now: Date = .now,
                          defaults: UserDefaults? = UserDefaults(suiteName: SharedStore.appGroup))
    -> WidgetSafeCall? {
        WidgetPayload.read(WidgetSafeCall.self, key: key, stampKey: stampKey,
                           freshness: freshness, now: now, defaults: defaults)
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

// MARK: - Today (prd §877)

/// Something a person asked of you with NO due date — a GitHub review request
/// or an assignment (prd §877).
///
/// Its own payload, never a `WidgetDeadline`, for the reason `WidgetSafeCall`
/// gives: a request carries when it was ASKED, not when it is due, and a made-up
/// due date would sort among real ones and draw itself late.
///
/// The row cannot know the request is still open — GitHub's notification list
/// drops a request once it is read on github.com, but a landed row stays — so
/// the tile says when it was asked ("asked 2d"), never "waiting", and stops
/// drawing it past `WidgetToday.requestWindow`. "Waiting" is reserved for the
/// Safe call, whose count is a reading of the live queue.
struct WidgetRequest: Codable, Equatable {
    let id: String
    /// "Review: Feed seam haptics", composed by the app.
    let title: String
    let source: String
    let askedAt: Date
}

/// Someone who answered one of YOUR posts (prd §877). `words` is the reply
/// itself (`SocialRoomSource.words`), never the row's clamped title.
struct WidgetReply: Codable, Equatable {
    let id: String
    let who: String
    let words: String
    let source: String
    let at: Date
    /// The replier's face as a `WidgetImages` key, or nil when the row has none.
    let face: String?
}

/// The newest like roll on your posts — `SocialLikeRoll.line`, names first,
/// never a bare count (§330).
struct WidgetLikes: Codable, Equatable {
    let line: String
    let source: String
    let at: Date
    /// The liked post, when it is in the corpus.
    let id: String?
}

struct WidgetPeople: Codable, Equatable {
    var replies: [WidgetReply]
    var likes: WidgetLikes?
}

/// One thing that landed, as the widget fetched it from the shared store.
/// Not published — the widget reads the store itself, so a thing saved while
/// the app is closed still reaches the tile.
struct WidgetLanded: Equatable {
    let id: String
    let title: String
    let source: String
    let at: Date
    /// A face key, when the row names a person with a picture.
    let face: String?
}

enum WidgetToday {
    /// The hero's kind, kept on purpose: a "Your day" tile already on a Home
    /// Screen becomes a Today tile instead of the system's "unable to load"
    /// placeholder. "Needs you" had its own kind and its placements do go to
    /// that placeholder — the accepted cost of two tiles becoming one.
    static let kind = "casberi.hero"

    static let requestsKey = "widget.requests"
    static let requestsStampKey = "widget.requestsAt"
    static let peopleKey = "widget.people"
    static let peopleStampKey = "widget.peopleAt"

    /// Both payloads are SETS that change while the app is closed (a request
    /// answered, a reply deleted), so they take the deadlines' day and a half.
    /// Each row also has its own draw-time window below.
    static let freshness: TimeInterval = 36 * 3600

    /// A request older than a week is history, not a request.
    static let requestWindow: TimeInterval = 7 * 24 * 3600
    /// Replies and likes are news for a day.
    static let peopleWindow: TimeInterval = 24 * 3600
    /// A deadline this close belongs in "needs you". A later one is named on
    /// the quiet line instead ("Next: …"), and only when nothing nearer is.
    static let soonWindow: TimeInterval = 7 * 24 * 3600

    static func requests(now: Date = .now,
                         defaults: UserDefaults? = UserDefaults(suiteName: SharedStore.appGroup))
    -> [WidgetRequest] {
        (WidgetPayload.read([WidgetRequest].self, key: requestsKey, stampKey: requestsStampKey,
                            freshness: freshness, now: now, defaults: defaults) ?? [])
            .filter { now.timeIntervalSince($0.askedAt) < requestWindow }
    }

    static func people(now: Date = .now,
                       defaults: UserDefaults? = UserDefaults(suiteName: SharedStore.appGroup))
    -> WidgetPeople {
        let stored = WidgetPayload.read(WidgetPeople.self, key: peopleKey, stampKey: peopleStampKey,
                                        freshness: freshness, now: now, defaults: defaults)
        let fresh = { (at: Date) in now.timeIntervalSince(at) < peopleWindow }
        return WidgetPeople(replies: (stored?.replies ?? []).filter { fresh($0.at) },
                            likes: stored?.likes.flatMap { fresh($0.at) ? $0 : nil })
    }
}

/// One line on the Today tile. The VIEW words it; this carries only facts, so
/// the ordering and the clocks can be tested without a widget.
struct WidgetTodayRow: Equatable {
    enum Section: Equatable { case needs, people, landed }
    enum Kind: Equatable {
        case deadline
        /// A Safe transaction waiting on your signature; `count` of them.
        case signature(count: Int)
        case request
        case reply(who: String)
        case likes
        case landed
    }
    /// What the right-hand clock reads — resolved to words at DRAW time.
    enum Clock: Equatable {
        case due(Date)
        /// Whole days a signature has waited; nil when the wire had no date.
        case waiting(Int?)
        case asked(Date)
        case at(Date)
    }
    enum Lead: Equatable {
        case mark(source: String)
        case face(key: String, source: String)
    }

    let id: String?
    let section: Section
    let kind: Kind
    let title: String
    let lead: Lead
    let clock: Clock
}

/// What the Today tile draws, decided in one pure function (prd §877): what
/// wants you first, then who answered you, then what landed — so the tile is
/// full on a quiet day and never a single line.
struct WidgetTodayPlan: Equatable {
    var rows: [WidgetTodayRow]
    /// The nearest deadline past `soonWindow`, named on its own line — set
    /// only when NOTHING needs you, so the top of the tile is never empty
    /// silence on a day with a real date ahead.
    var next: WidgetDeadline?
    var late: Int
    /// Safe transactions waiting on your signature — a live reading. Requests
    /// are NOT counted here: one may already be answered (`WidgetRequest`).
    var toSign: Int
    /// Up to four reply faces, newest first, for the small tile's pile.
    var faces: [String]
    var repliers: [String]

    var isEmpty: Bool { rows.isEmpty && next == nil }
}

extension WidgetTodayPlan {
    /// `capacity` is how many rows the family has room for. When `next` is
    /// set its line takes one of them.
    static func make(deadlines: [WidgetDeadline], safe: WidgetSafeCall?,
                     requests: [WidgetRequest], people: WidgetPeople,
                     landed: [WidgetLanded], capacity: Int, now: Date) -> WidgetTodayPlan {
        let byDue = deadlines.sorted { $0.due < $1.due }
        let overdue = byDue.filter { $0.isOverdue(now: now) }
        let soon = byDue.filter { !$0.isOverdue(now: now) && $0.due.timeIntervalSince(now) <= WidgetToday.soonWindow }
        let asks = requests.filter { now.timeIntervalSince($0.askedAt) < WidgetToday.requestWindow }
            .sorted { $0.askedAt > $1.askedAt }
        let signing = (safe?.awaitsYou ?? 0) > 0 ? safe : nil

        // Needs you, in the order each is already a problem: late, then
        // somebody blocked on your signature, then a request, then what is
        // coming. A signature outranks a request because the Safe count is a
        // live reading and a request may already be answered.
        var needs: [WidgetTodayRow] = overdue.map(deadlineRow)
        if let signing {
            needs.append(WidgetTodayRow(id: signing.id, section: .needs,
                                        kind: .signature(count: signing.awaitsYou),
                                        title: signing.subject, lead: .mark(source: "Safe"),
                                        clock: .waiting(signing.waitingDays)))
        }
        needs += asks.map {
            WidgetTodayRow(id: $0.id, section: .needs, kind: .request, title: $0.title,
                           lead: .mark(source: $0.source), clock: .asked($0.askedAt))
        }
        needs += soon.map(deadlineRow)

        let next = needs.isEmpty ? byDue.first { !$0.isOverdue(now: now) } : nil

        var said: [WidgetTodayRow] = people.replies.sorted { $0.at > $1.at }.map { reply in
            WidgetTodayRow(id: reply.id, section: .people, kind: .reply(who: reply.who),
                           title: reply.words,
                           lead: reply.face.map { .face(key: $0, source: reply.source) }
                               ?? .mark(source: reply.source),
                           clock: .at(reply.at))
        }
        if let likes = people.likes {
            said.append(WidgetTodayRow(id: likes.id, section: .people, kind: .likes,
                                         title: likes.line, lead: .mark(source: likes.source),
                                         clock: .at(likes.at)))
        }

        let shown = Set((needs + said).compactMap(\.id))
        let fresh = landed.sorted { $0.at > $1.at }.filter { !shown.contains($0.id) }.map { thing in
            WidgetTodayRow(id: thing.id, section: .landed, kind: .landed, title: thing.title,
                           lead: thing.face.map { .face(key: $0, source: thing.source) }
                               ?? .mark(source: thing.source),
                           clock: .at(thing.at))
        }

        // Room: needs you may take everything, EXCEPT that half the tile (at
        // most two rows) is held back for the other sections when they have
        // something — a tile of four deadlines says less than two deadlines
        // and the two people who answered you.
        let room = max(0, capacity - (next == nil ? 0 : 1))
        let others = said.count + fresh.count
        let held = min(others, room / 2)
        let needsTaken = Array(needs.prefix(max(0, room - held)))
        var left = room - needsTaken.count
        let peopleTaken = Array(said.prefix(left))
        left -= peopleTaken.count
        let landedTaken = Array(fresh.prefix(left))

        let replies = said.filter {
            if case .reply = $0.kind { return true } else { return false }
        }
        return WidgetTodayPlan(
            rows: needsTaken + peopleTaken + landedTaken,
            next: next,
            late: overdue.count,
            toSign: signing?.awaitsYou ?? 0,
            faces: Array(replies.compactMap {
                if case .face(let key, _) = $0.lead { return key } else { return nil }
            }.prefix(4)),
            repliers: replies.compactMap {
                if case .reply(let who) = $0.kind { return who } else { return nil }
            })
    }

    private static func deadlineRow(_ d: WidgetDeadline) -> WidgetTodayRow {
        WidgetTodayRow(id: d.id, section: .needs, kind: .deadline, title: d.title,
                       lead: .mark(source: d.source), clock: .due(d.due))
    }
}

/// A span said the way a row's clock says it: minutes under an hour, hours
/// under a day, then days — with the hours kept beside the days only while
/// they still matter ("1d 6h", never "12d 3h").
struct WidgetSpan: Equatable {
    let days: Int
    let hours: Int
    let minutes: Int

    init(_ seconds: TimeInterval) {
        let s = max(0, Int(seconds))
        if s < 3600 {
            days = 0; hours = 0; minutes = max(1, s / 60)
        } else if s < 86_400 {
            days = 0; hours = s / 3600; minutes = 0
        } else {
            days = s / 86_400
            hours = days < 3 ? (s % 86_400) / 3600 : 0
            minutes = 0
        }
    }
}

/// Where the Today tile's lead pictures live: small PNGs the APP writes into
/// the app group (brand marks it bundles, faces it downloads) and the widget
/// reads by key. The widget can neither reach the app's asset catalog nor
/// fetch a URL, and this is the one channel between them for pixels.
///
/// Keys are FNV-1a hashes of the source name or the picture URL, computed the
/// same way on both sides — Swift's `hashValue` is seeded per process, so it
/// would give the app and the widget two different names for one picture.
enum WidgetImages {
    static let folder = "WidgetLeads"
    /// Past this many FACES the oldest go. Marks are a few dozen and stay.
    static let fileCap = 160

    static func markKey(source: String) -> String { "mark-" + fnv(source) }
    static func faceKey(url: String) -> String { "face-" + fnv(url) }

    static func fnv(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    static func directory() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroup)?
            .appendingPathComponent(folder, isDirectory: true)
    }

    static func file(_ key: String) -> URL? {
        directory()?.appendingPathComponent(key + ".png")
    }
}
