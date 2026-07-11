import Foundation
import Observation

/// Home's board order (prd 58, Goal 1) — the person owns which module leads.
/// A saved order is a list of stable module keys ("pinned", "map",
/// "wallet:<label>"); HomeScreen composes the day's modules fresh every time
/// (a wallet can appear/disappear, the map can turn from projects to
/// sources), so this only ever REORDERS what the composer already decided
/// to show — it never adds or removes a module.
@Observable
final class HomeBoardOrder {
    static let shared = HomeBoardOrder()
    private static let key = "home.board.order"

    private(set) var saved: [String]

    private init() {
        saved = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
    }

    /// Reorders `natural` (the composer's default sequence) by the saved
    /// preference. Known keys follow the saved sequence; anything in
    /// `natural` that was never saved (a module that's new since the last
    /// arrangement) keeps its natural relative order, appended after the
    /// known ones — a fresh module never displaces a placement the person
    /// made on purpose. A stale saved key (a module that dropped out) is
    /// simply skipped. Nobody who never drags ever sees this branch run:
    /// `saved` stays empty until the first reorder.
    func apply(to natural: [String]) -> [String] {
        guard !saved.isEmpty else { return natural }
        let naturalSet = Set(natural)
        let known = saved.filter { naturalSet.contains($0) }
        let knownSet = Set(known)
        let fresh = natural.filter { !knownSet.contains($0) }
        return known + fresh
    }

    func save(_ order: [String]) {
        saved = order
        UserDefaults.standard.set(order, forKey: Self.key)
    }
}
