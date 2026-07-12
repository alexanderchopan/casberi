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
    private static let hiddenKey = "home.board.hiddenSocial"

    /// Sources `HomeComposition.appendMediaModules` actually gates on the
    /// pinned bypass. A source's own screen only shows "Pin to Home" when
    /// its name is in here — otherwise the pin would persist and flip the
    /// button's state with no effect on the board, a dead control.
    static let pinnable: Set<String> = ["Apple Music", "Pinterest", "Photos", "RSS"]

    /// The social sources that auto-earn a Home card from a single post
    /// (`HomeComposition.appendMediaModules`), in board order. Unlike
    /// `pinnable` sources they show by default, so their control is the
    /// inverse — "Show on Home", removable into `hidden` and brought back
    /// from the source's own screen (they carry no "Pin to Home").
    static let autoSocial: [String] = ["Bluesky", "Farcaster"]

    private(set) var sources: Set<String>
    /// Auto-social sources the person removed from Home (the inverse of a
    /// pin — these show unless suppressed). Keyed by source name, same as
    /// `sources`; persisted separately so a pin and a hide never collide.
    private(set) var hidden: Set<String>

    private init() {
        sources = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
        hidden = Set(UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? [])
    }

    func isPinned(_ source: String) -> Bool { sources.contains(source) }

    /// True when the person removed this auto-social source's card from Home.
    func isHidden(_ source: String) -> Bool { hidden.contains(source) }

    /// Remove an auto-social card from Home (`true`) or bring it back
    /// (`false`) — the "Show on Home" toggle and the card's long-press
    /// "Remove from Home" both land here.
    func setHidden(_ source: String, _ value: Bool) {
        if value { hidden.insert(source) } else { hidden.remove(source) }
        UserDefaults.standard.set(Array(hidden), forKey: Self.hiddenKey)
    }

    func toggle(_ source: String) {
        if sources.contains(source) {
            sources.remove(source)
            forgetBoardState(source)
        } else {
            sources.insert(source)
        }
        UserDefaults.standard.set(Array(sources), forKey: Self.key)
    }

    /// Called when a source's bridge is disconnected or its things are
    /// purged — an outlived pin would otherwise silently reactivate the
    /// magnitude-1 bypass the moment the same-named source reconnects.
    func clear(_ source: String) {
        // A disconnect also drops a stale hide, so a reconnected social
        // account starts visible again rather than silently suppressed.
        if hidden.remove(source) != nil {
            UserDefaults.standard.set(Array(hidden), forKey: Self.hiddenKey)
        }
        guard sources.remove(source) != nil else { return }
        forgetBoardState(source)
        UserDefaults.standard.set(Array(sources), forKey: Self.key)
    }

    /// The Home board module a pinned source composes as (`HomeComposition`'s
    /// media shelves) — the bridge between a source NAME (what pins are keyed
    /// by) and a board module REF (what size/order are keyed by). nil for a
    /// source with no shelf of its own.
    static func moduleRef(for source: String) -> String? {
        switch source {
        case "Apple Music": return "musicShelf"
        case "Pinterest":   return "pinShelf"
        case "Photos":      return "shotShelf"
        case "RSS":         return "rssShelf"
        default:            return nil
        }
    }

    /// An auto-social card's board ref (`social<Source>`, from
    /// `appendSocialCard`) back to its source name, so the board's
    /// "Remove from Home" knows which source to hide.
    static func socialSource(forModuleRef ref: String) -> String? {
        for source in autoSocial where ref == "social\(source)" { return source }
        return nil
    }

    /// The inverse of `moduleRef(for:)` — a shelf's ref back to its source, so
    /// the board's "Remove from Home" knows which pin to drop.
    static func source(forModuleRef ref: String) -> String? {
        switch ref {
        case "musicShelf": return "Apple Music"
        case "pinShelf":   return "Pinterest"
        case "shotShelf":  return "Photos"
        case "rssShelf":   return "RSS"
        default:           return nil
        }
    }

    /// Unpinning a source for good drops its module's saved size and order
    /// too — a deliberate removal shouldn't leave state that resurrects the
    /// old card (large, in its old slot) on a later re-pin. Transient absence
    /// never routes through here, so a returning wallet keeps its placement.
    private func forgetBoardState(_ source: String) {
        guard let ref = Self.moduleRef(for: source) else { return }
        HomeModuleSize.shared.clear(ref)
        HomeBoardOrder.shared.remove(ref)
    }
}
