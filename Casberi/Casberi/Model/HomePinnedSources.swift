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

    /// One-time migration support: carry a renamed source across the pin and
    /// hide sets so a bridge rename (Dexscreener -> Tokens, 2026-07-13) can't
    /// strand a pinned tile under the dead name. Board size/order key off the
    /// source name too, but a renamed tile re-derives default placement rather
    /// than migrating those keys — a rare, acceptable reset over new plumbing.
    func rename(_ old: String, to new: String) {
        if sources.remove(old) != nil {
            forgetBoardState(old)
            sources.insert(new)
            UserDefaults.standard.set(Array(sources), forKey: Self.key)
        }
        if hidden.remove(old) != nil {
            hidden.insert(new)
            UserDefaults.standard.set(Array(hidden), forKey: Self.hiddenKey)
        }
    }

    /// The Home board module an IMAGE-media source composes as
    /// (`HomeComposition`'s bespoke shelves) — the bridge between a source
    /// NAME and its board module REF. Image sources keep their own shelf id;
    /// every other pinned app composes as a generic `Widget` tile whose
    /// board key is `app:<source>` (see `boardKey`). nil for a non-media source.
    static func moduleRef(for source: String) -> String? {
        switch source {
        case "Apple Music": return "musicShelf"
        case "Pinterest":   return "pinShelf"
        case "Photos":      return "shotShelf"
        case "RSS":         return "rssShelf"
        case "GitHub":      return "githubGraphShelf"
        default:            return nil
        }
    }

    /// The inverse of `moduleRef(for:)` — a media shelf's ref back to its
    /// source, so the board's "Remove from Home" knows which pin to drop.
    /// A generic app tile carries its source in the doc instead (arg 3), read
    /// straight off the element, so it needs no entry here.
    static func source(forModuleRef ref: String) -> String? {
        switch ref {
        case "musicShelf": return "Apple Music"
        case "pinShelf":   return "Pinterest"
        case "shotShelf":  return "Photos"
        case "rssShelf":   return "RSS"
        case "githubGraphShelf": return "GitHub"
        default:           return nil
        }
    }

    /// The stable board key a source's tile persists its size/order under —
    /// a media source uses its shelf ref (which equals its module key), every
    /// other app uses `app:<source>`. `HomeScreen.moduleKey` derives the same
    /// key from a live element, so a pin/unpin and a reorder round-trip.
    static func boardKey(for source: String) -> String {
        moduleRef(for: source) ?? "app:\(source)"
    }

    /// Unpinning a source for good drops its module's saved size and order
    /// too — a deliberate removal shouldn't leave state that resurrects the
    /// old card (large, in its old slot) on a later re-pin. Transient absence
    /// never routes through here, so a returning wallet keeps its placement.
    private func forgetBoardState(_ source: String) {
        let key = Self.boardKey(for: source)
        HomeModuleSize.shared.clear(key)
        HomeBoardOrder.shared.remove(key)
    }
}
