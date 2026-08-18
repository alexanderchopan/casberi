import Foundation

/// THE ANONYMITY SET, AS A NUMBER (2026-08-17, prd §397).
///
/// §228 already reads 0xBow's `pools-stats` for `acceptedDepositsCount` — the
/// real anonymity set, since only ASP-approved deposits sit in the merkle tree
/// a withdrawal proof draws from — and then throws the integer away, keeping
/// only a sentence on each deposit's `enrichedText`. §349 read that sentence
/// and correctly refused to draw anything from it: there is no number in prose
/// to add up, and several deposits' lines are several different moments' pool
/// sizes, which cannot be presented as one current figure.
///
/// This keeps the integer instead. Two things, both flat `UserDefaults` (the
/// `X402State`/`ASCState` shape — **no new `Thing` property, so no CloudKit
/// Production deploy**, which for one re-readable number would be a schema
/// migration to store a fact that changes daily):
///
///  1. `current` — each pool's live count, refreshed at most once a day.
///  2. `atLanding` — the count at the moment one deposit landed, keyed by the
///     ASP label the rest of this seat already keys everything by.
///
/// The pair is what lets the room say a set GREW. That is the only genuinely
/// good news this seat can deliver: a deposit already made becomes more private
/// as other people deposit, without the depositor doing anything, and nothing
/// in the app reported it. The per-deposit sentence cannot — it is frozen at
/// landing by design.
///
/// ## Keyed by OUR symbol, not the API's
///
/// `pools-stats` reports its own `tokenSymbol`, and the room joins cover to
/// holdings through `Thing.priceCurrency`, which `PrivacyPoolsBridge` stamps
/// from `Pool.symbol` in its own table. So the write side resolves scope →
/// `Pool.symbol` and stores THAT. Storing the API's spelling would mean a
/// remote rename silently unjoins every cover line — the card would just stop
/// mentioning cover, with nothing anywhere to say why.
///
/// ## Fails safe, everywhere
///
/// No reading is not an error. `pools-stats` unreachable, a pool absent from
/// the response, a deposit older than this store — each ends as "no cover line
/// on the card", never a guessed number on the screen whose whole subject is
/// how much privacy someone actually has.
enum PrivacyPoolsCover {

    private static let currentKey  = "privacypools.cover.current"
    private static let lastReadKey = "privacypools.cover.lastRead"
    private static let landingKey  = "privacypools.cover.atLanding"

    /// How often the live set size is re-read. A day, because this number
    /// moves at the pace of strangers depositing into a pool that has taken
    /// years to reach four figures — polling it per foreground would buy
    /// nothing and spend a request on every open of the app.
    static let refreshInterval: TimeInterval = 24 * 60 * 60

    /// Runaway guard on the landing snapshots. Deposits are rare (the whole
    /// ETH pool holds ~4k accepted deposits EVER, across everybody), so a real
    /// person's map is a handful of entries; this only bounds a pathological
    /// one. Excess is dropped rather than allowed to grow without limit — a
    /// dropped snapshot costs the growth half of one cover line, never a wrong
    /// number.
    static let snapshotCap = 500

    // MARK: - Current set sizes

    /// Each pool's latest `acceptedDepositsCount`, keyed by `Pool.symbol`.
    static func current() -> [String: Int] {
        (UserDefaults.standard.dictionary(forKey: currentKey) as? [String: Int]) ?? [:]
    }

    /// Replaces the whole snapshot and stamps the clock. Whole rather than
    /// merged: a pool missing from a fresh `pools-stats` response is a pool we
    /// no longer have a reading for, and keeping the old number would state a
    /// stale set size as current on the one card where currency is the point.
    static func save(current readings: [String: Int]) {
        guard !readings.isEmpty else { return }
        UserDefaults.standard.set(readings, forKey: currentKey)
        UserDefaults.standard.set(Date.now, forKey: lastReadKey)
    }

    static var lastRead: Date? {
        UserDefaults.standard.object(forKey: lastReadKey) as? Date
    }

    /// Whether the live read is due. True when it has never run, so a seat
    /// that has just found its first deposit gets a reading on that same pass.
    static func needsRefresh(now: Date = .now) -> Bool {
        guard let lastRead else { return true }
        return now.timeIntervalSince(lastRead) >= refreshInterval
    }

    // MARK: - Set size when a deposit landed

    private static func landings() -> [String: Int] {
        (UserDefaults.standard.dictionary(forKey: landingKey) as? [String: Int]) ?? [:]
    }

    /// Records the set size a deposit landed into. Written once and never
    /// overwritten — the whole value of this number is that it is the size AT
    /// LANDING, and re-stamping it on a later pass would quietly turn every
    /// growth claim into "up from itself", i.e. into silence.
    static func snapshot(label: String, count: Int) {
        guard !label.isEmpty, count > 0 else { return }
        var map = landings()
        guard map[label] == nil else { return }
        guard map.count < snapshotCap else { return }
        map[label] = count
        UserDefaults.standard.set(map, forKey: landingKey)
    }

    static func landingCount(label: String) -> Int? { landings()[label] }

    // MARK: - Teardown

    /// The live set sizes and their clock. Safe to drop at any time: the next
    /// sweep buys them back, and until it does the card simply says nothing
    /// about cover.
    static func forgetCurrent() {
        UserDefaults.standard.removeObject(forKey: currentKey)
        UserDefaults.standard.removeObject(forKey: lastReadKey)
    }

    /// Specific landing snapshots.
    ///
    /// Demo teardown calls THIS rather than dropping the whole map, and the
    /// difference matters more here than in the sibling stores: a landing
    /// snapshot cannot be re-bought. It is the set size at a moment that has
    /// passed, so a real depositor who walked the demo would lose the growth
    /// half of their cover line permanently — not for a few hours until the
    /// next refresh, the way `forgetCurrent` costs nothing. Demo labels are
    /// `demo…`; a real one is a uint256 in decimal, so the two can never
    /// collide.
    static func forget(labels: [String]) {
        guard !labels.isEmpty else { return }
        var map = landings()
        for label in labels { map.removeValue(forKey: label) }
        UserDefaults.standard.set(map, forKey: landingKey)
    }

    /// Everything. Not used by demo teardown — see `forget(labels:)`.
    static func forgetAll() {
        forgetCurrent()
        UserDefaults.standard.removeObject(forKey: landingKey)
    }
}
