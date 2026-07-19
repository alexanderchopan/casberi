import Foundation
import Observation

/// The wallet's own delight bus (2026-07-15) — the sibling of the starred-repo
/// major-release rain (MainSurface's arrival watcher). Holdings never land as
/// things (prd §72: a treemap cell is a door, not a thing), so they can't ride
/// the corpus-arrival detector that fires the release rain. Instead
/// `WalletStore.recordSample` calls in here when a wallet hits a new value high;
/// MainSurface observes `pulse` and deals the berry rain + names the moment in a
/// toast. One surface, so every wallet celebration looks like the release one.
///
/// Detection is deliberately honest and quiet on first sight: the first value
/// sample seeds the high-water mark silently (a baseline isn't a new high). Only
/// a genuine NEW high fires. (NFT-arrival moments were removed 2026-07-19 with
/// the wallet NFT shelves.)
@MainActor
@Observable
final class WalletMoments {
    static let shared = WalletMoments()

    /// Bumped for each moment — MainSurface hangs the berry rain off it and
    /// drains `pending`.
    private(set) var pulse = 0
    /// Queued moment lines, oldest first — a QUEUE, not a single slot, so two
    /// moments in one pass (an NFT arrival AND a new high) don't collapse to
    /// one, and a moment fired while backgrounded survives until MainSurface
    /// next drains on foreground (SwiftUI defers the onChange while inactive).
    private(set) var pending: [String] = []

    private init() {}

    /// A moment worth marking — the caller has already decided it's real.
    func fire(_ text: String) {
        pending.append(text)
        pulse += 1
    }

    /// MainSurface takes the queued lines and clears them (rain once, show the
    /// most recent line). Returns [] when nothing is pending.
    func drain() -> [String] {
        defer { pending.removeAll() }
        return pending
    }

    // MARK: - High-water marks

    private static func highKey(_ scope: String) -> String { "wallet.high.\(scope)" }

    /// Records a value for a scope ("combined", or a wallet address) and
    /// returns true when it's a genuine NEW high above the stored mark. The
    /// FIRST value for a scope seeds the mark silently and returns false — a
    /// baseline is not a high. A drop never fires (asymmetric by design: a
    /// new high earns a moment, a drawdown earns only the honest red pill on
    /// the line). A tiny epsilon guards against a re-high on the same value.
    func notedNewHigh(scope: String, value: Double) -> Bool {
        guard value > 0 else { return false }
        let key = Self.highKey(scope)
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: key) != nil else {
            defaults.set(value, forKey: key)
            return false
        }
        let prev = defaults.double(forKey: key)
        guard value > prev * 1.0001 else {
            // Still update the stored mark on a genuine rise below the fire
            // threshold isn't needed; only ever raise it on a real new high.
            return false
        }
        defaults.set(value, forKey: key)
        return true
    }
}
