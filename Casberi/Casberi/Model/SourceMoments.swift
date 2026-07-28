import Foundation
import Observation

/// The shared delight bus (generalized 2026-07-21 from the wallet-only
/// `WalletMoments`, prd §79's "faces, glances, and moments" pass) — for any
/// source whose delight can't ride the corpus-arrival watcher that fires the
/// starred-repo release rain. Holdings/NFTs never land as things (prd §72:
/// a treemap cell is a door, not a thing) so wallet highs enqueue here;
/// watched tokens, Bitrefill balances, and quiet-then-active social accounts
/// do the same for the same reason (their "moment" isn't itself a landing
/// thing). MainSurface observes `pulse` and deals the berry rain + names the
/// moment in a toast, tinted to the firing source's own hue when it names
/// one — one surface, so every source's celebration reads the same family.
///
/// Detection at every call site is deliberately honest and quiet on first
/// sight: a first sample seeds its own high-water mark silently (a baseline
/// isn't a new high). Only a genuine new high, or a genuine return, fires.
@MainActor
@Observable
final class SourceMoments {
    static let shared = SourceMoments()

    struct Moment {
        let text: String
        /// The source whose hue should tint the rain, when the moment
        /// belongs to one — nil rains the app's own default blue.
        let source: String?
    }

    /// Bumped for each moment — MainSurface hangs the berry rain off it and
    /// drains `pending`.
    private(set) var pulse = 0
    /// Queued moments, oldest first — a QUEUE, not a single slot, so two
    /// moments in one pass don't collapse to one, and a moment fired while
    /// backgrounded survives until MainSurface next drains on foreground
    /// (SwiftUI defers the onChange while inactive).
    private(set) var pending: [Moment] = []

    private init() {}

    /// A moment worth marking — the caller has already decided it's real.
    func fire(_ text: String, source: String? = nil) {
        pending.append(Moment(text: text, source: source))
        pulse += 1
    }

    /// MainSurface takes the queued moments and clears them (rain once, show
    /// the most recent line). Returns [] when nothing is pending.
    func drain() -> [Moment] {
        defer { pending.removeAll() }
        return pending
    }

    // MARK: - High-water marks

    /// Records a value for a fully-namespaced scope (a caller-chosen key
    /// like "wallet.combined" or "token.<sourceRef>") and returns true when
    /// it's a genuine NEW high above the stored mark. The FIRST value for a
    /// scope seeds the mark silently and returns false — a baseline is not
    /// a high. A drop never fires (asymmetric by design: a new high earns a
    /// moment, a drawdown earns only the honest red pill on the line). A
    /// tiny epsilon guards against a re-high on the same value.
    func notedNewHigh(scope: String, value: Double) -> Bool {
        guard value > 0 else { return false }
        let key = "moment.high.\(scope)"
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: key) != nil else {
            defaults.set(value, forKey: key)
            return false
        }
        let prev = defaults.double(forKey: key)
        guard value > prev * 1.0001 else { return false }
        defaults.set(value, forKey: key)
        return true
    }

    /// The high-water mark's sibling for a source with no "landed thing" to
    /// compare gaps between (Steam: a game dedupes to ONE thing forever, so
    /// there's no second landing to diff a quiet stretch against — only the
    /// live API's own per-pass signal proves a return). Records "last seen
    /// active" for a scope and reports true exactly when a PRIOR stamp exists
    /// and the gap since it is at least `quietDays` — same doctrine as
    /// `notedNewHigh`: the first sighting seeds silently, never fires.
    func notedReturn(scope: String, quietDays: Double) -> Bool {
        let key = "moment.seen.\(scope)"
        let defaults = UserDefaults.standard
        let now = Date()
        defer { defaults.set(now, forKey: key) }
        guard let prev = defaults.object(forKey: key) as? Date else { return false }
        return now.timeIntervalSince(prev) >= quietDays * 86400
    }
}
