import Foundation
import Observation

/// Which sources the person explicitly placed on the Home board (prd 58,
/// Goal 4) — the "Pin to Home" verb on a source's own screen (Bluesky,
/// Farcaster, Pinterest, Apple Music, any bridge routed through
/// `BridgeDetailScreen`/`HandleSetupScreen`). Wallets already have their
/// own per-address `pinnedToHome` (`WalletStore`); this is the same idea
/// generalized to every other source, keyed by the source's own name
/// string (the same string `Thing.source` and `HomeComposition` already
/// use — no separate id scheme to keep in sync).
///
/// Pinning a source doesn't invent content: `HomeComposition` still needs
/// at least one real thing from that source to show a card. What pinning
/// buys is the "board grows from the catalog" promise — connecting an app
/// can end here, on ITS OWN screen, rather than waiting for the source to
/// cross the automatic magnitude threshold `sourceClusters` uses elsewhere.
@Observable
final class HomePinnedSources {
    static let shared = HomePinnedSources()
    private static let key = "home.board.pinnedSources"

    /// Sources `HomeComposition.appendMediaModules` actually gates on the
    /// pinned bypass. A source's own screen only shows "Pin to Home" when
    /// its name is in here — otherwise the pin would persist and flip the
    /// button's state with no effect on the board, a dead control.
    static let pinnable: Set<String> = ["Apple Music", "Pinterest", "Photos", "RSS"]

    private(set) var sources: Set<String>

    private init() {
        sources = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
    }

    func isPinned(_ source: String) -> Bool { sources.contains(source) }

    func toggle(_ source: String) {
        if sources.contains(source) { sources.remove(source) } else { sources.insert(source) }
        UserDefaults.standard.set(Array(sources), forKey: Self.key)
    }

    /// Called when a source's bridge is disconnected or its things are
    /// purged — an outlived pin would otherwise silently reactivate the
    /// magnitude-1 bypass the moment the same-named source reconnects.
    func clear(_ source: String) {
        guard sources.remove(source) != nil else { return }
        UserDefaults.standard.set(Array(sources), forKey: Self.key)
    }
}
