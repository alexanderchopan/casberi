import Foundation

/// The librarian's clock (prd §67 goal ⑥) — when were you last here, and
/// what landed while you were gone. The away window FREEZES at foreground
/// (last background → this open) so things arriving while you're present
/// never count as "while you were away"; a gap under an hour isn't away at
/// all, it's switching apps.
enum AppVisit {
    private static let closedKey = "visit.lastClosed"
    private static let minimumAway: TimeInterval = 3600

    /// The stretch you were gone, frozen at this foreground — nil when the
    /// gap was trivial or this is the first ever visit. Read off-main by
    /// suggestion/answer derivation; written only on the main actor.
    nonisolated(unsafe) private static var frozen: Range<Date>?

    static var away: Range<Date>? {
        #if DEBUG
        // `-awayGap <hours>` fakes an away window ending now, so the chip and
        // the "while I was away" answer verify headlessly — read here (not at
        // foreground) so probes never race the scene-phase handler.
        if let gap = UserDefaults.standard.string(forKey: "awayGap").flatMap(Double.init),
           gap > 0 {
            return Date.now.addingTimeInterval(-gap * 3600)..<Date.now
        }
        #endif
        return frozen
    }

    @MainActor
    static func markClosed(now: Date = .now) {
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: closedKey)
    }

    @MainActor
    static func markOpened(now: Date = .now) {
        let stamp = UserDefaults.standard.double(forKey: closedKey)
        guard stamp > 0 else { frozen = nil; return }
        let closed = Date(timeIntervalSince1970: stamp)
        frozen = now.timeIntervalSince(closed) >= minimumAway ? closed..<now : nil
    }
}
