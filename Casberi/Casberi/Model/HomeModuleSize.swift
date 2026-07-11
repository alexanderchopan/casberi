import Foundation
import Observation

/// Home board module sizes (prd 58a) — regular or large, per module, tap-
/// the-pin owned. Keyed by the same stable module keys `HomeScreen.moduleKey`
/// derives ("pinned", "map", "wallet:<label>") — not by ref id, for the same
/// reason `HomeBoardOrder` isn't: a wallet's slot index shifts as other
/// wallets are pinned/unpinned, but its size choice shouldn't.
@Observable
final class HomeModuleSize {
    static let shared = HomeModuleSize()
    private static let key = "home.board.large"

    private(set) var large: Set<String>

    private init() {
        large = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
    }

    func isLarge(_ moduleKey: String) -> Bool { large.contains(moduleKey) }

    func toggle(_ moduleKey: String) {
        if large.contains(moduleKey) { large.remove(moduleKey) } else { large.insert(moduleKey) }
        UserDefaults.standard.set(Array(large), forKey: Self.key)
    }
}
