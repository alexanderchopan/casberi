import Foundation
import Observation

/// A board tile's span on the bento (prd 58h): `small` is a 1×1 square,
/// `wide` a 2×1 band, `big` a 2×2 feature. The person owns it — tap the pin
/// cycles a module through the spans it allows (a treemap skips `wide`, a
/// social post has no `big`), and the board re-packs to fill the gaps.
enum ModuleSpan: String, CaseIterable, Sendable {
    case small, wide, big

    /// Grid footprint in (columns, rows) on the two-column board.
    var cols: Int { self == .small ? 1 : 2 }
    var rows: Int { self == .big ? 2 : 1 }
}

/// Home board module spans (prd 58h bento; supersedes the prd-58a two-state
/// large/regular). Keyed by the same stable module keys `HomeScreen.moduleKey`
/// derives ("pinned", "map", "wallet:<label>") — not by ref id, so a wallet's
/// span survives its slot index shifting as other wallets are pinned/unpinned.
@Observable
final class HomeModuleSize {
    static let shared = HomeModuleSize()
    private static let key = "home.board.spans"
    /// The prd-58a store this replaces — a set of "large" module keys. Read
    /// once to migrate, then left alone.
    private static let legacyLargeKey = "home.board.large"

    private(set) var spans: [String: ModuleSpan]

    private init() {
        if let raw = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: String] {
            spans = raw.compactMapValues(ModuleSpan.init(rawValue:))
        } else {
            // First launch on the bento build: every module the person had
            // grown to "large" becomes `big`; everything else falls to its
            // default (the caller supplies it — the board opens one-hero).
            var migrated: [String: ModuleSpan] = [:]
            for k in UserDefaults.standard.stringArray(forKey: Self.legacyLargeKey) ?? [] {
                migrated[k] = .big
            }
            spans = migrated
            if !migrated.isEmpty { persist() }
        }
    }

    /// The stored span, or nil if the person never sized this module — the
    /// caller applies the module's default so the board opens composed.
    func span(_ moduleKey: String) -> ModuleSpan? { spans[moduleKey] }

    /// Tap the pin: advance to the next span this module allows, wrapping.
    /// Starts from the module's current effective span (stored, or `def` if
    /// untouched), so the first tap moves off what's on screen.
    func cycle(_ moduleKey: String, allowed: [ModuleSpan], default def: ModuleSpan) {
        guard !allowed.isEmpty else { return }
        let current = spans[moduleKey] ?? def
        let i = allowed.firstIndex(of: current) ?? -1
        spans[moduleKey] = allowed[(i + 1) % allowed.count]
        persist()
    }

    /// Drops a module's saved span when it leaves the board for good (its
    /// source unpinned/disconnected) — otherwise a re-pin later silently
    /// resurrects the old span. Kept separate from a transient absence (a
    /// wallet whose fetch hasn't landed), which must NOT forget.
    func clear(_ moduleKey: String) {
        guard spans.removeValue(forKey: moduleKey) != nil else { return }
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(spans.mapValues(\.rawValue), forKey: Self.key)
    }
}
