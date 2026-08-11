import Foundation

/// The Markets fold (2026-08-10, user ruling): the market seats share ONE chip
/// in the source strip, and the room behind it carries a venue switcher.
///
/// **The problem it solves.** Seven seats browse under Markets — Tokens,
/// Stocktwits, Kalshi, Polymarket, GeckoTerminal, Circle x402, OpenSea — and
/// each earned its own 56pt circle. They are DISTINCT lists nobody wants merged
/// (a token's 24h percent, a stock's session percent and a market's probability
/// points do not convert, which is why `TokensAsk` and `MarketsAsk` are two
/// composers and why "Busiest" refuses to cross-merge Kalshi and Polymarket),
/// but they are lists somebody wants to move BETWEEN. Icon-only chips scattered
/// through a learned-order strip make that a hunt, and market marks are the
/// worst possible icons for it — several are a letter in a circle, and two of
/// them are literally an "S".
///
/// **THE CENTRAL DECISION: "Markets" is a chip LABEL, never a source.**
/// `FeedFilter.source` stays a real seat name at all times — tapping the folded
/// chip resolves to a real venue (`landing`), and the switcher inside the room
/// writes another real venue through the same `go(to:)` every chip tap and
/// swipe already uses. Nothing downstream of the strip ever sees the string
/// "Markets": no new `@Query` shape, no new `FeedScreen.Shape`, no
/// `Corpus.earnsRoom` exception, no deep-link rewrite, and every existing room
/// renders exactly as it did. Compare `Pinboard.room`, which HAD to be a
/// sentinel source because its rows are selected by `pinnedAt` rather than by
/// any seat; this room's rows already belong to seats, so inventing a sentinel
/// would buy nothing and cost every read that assumes a source is a source.
///
/// Wallet is deliberately NOT folded this way, and the reason is a shape
/// difference rather than a policy: Aave, Morpho, Peer, Safe and the rest are
/// lenses on ONE subject (your addresses), so they compose into a single room
/// with a single balance — they never had chips to fold. Five venues with five
/// separate watchlists cannot compose into one reading, so their aggregate is a
/// switcher rather than a composition. (Peer, Privacy Pools, Gnosis Pay and
/// Railgun DO now share the Wallet chip via `CategoryFold`'s always-fold rule
/// below — but that is the STRIP folding, not this room composing; the room
/// itself is still one balance, and moving between those seats' own readings
/// from inside it is its own unbuilt pass — prd §351.)
///
/// **SUPERSEDED BY `CategoryFold` (prd §351, 2026-08-11).** This type used to
/// carry the whole mechanism — membership, folding, landing, remembering,
/// scopes — for Markets alone, gated on a `foldFloor` of 2 so a lone market
/// seat kept its own icon. The user ruled the fold should be unconditional
/// and apply to EVERY category, not just a crowded Markets: "i want the
/// category chips always." `CategoryFold` is that generalization (Foundation-
/// only, same shape, no floor on the fold itself). What stays HERE is exactly
/// what is still Markets-specific: the "Markets" label constant (spelled once,
/// the reason it existed originally), and `switcherFloor` — the ≥2 floor a
/// SWITCHER control still needs (`PredictionVenueSwitcher`'s own rule: "a
/// scope control with one scope is not a control"), which is a different
/// question from whether the CHIP folds. No other category has a dedicated
/// switcher screen yet, so no other category needs this file's equivalent.
enum MarketsRoom {
    /// The folded chip's label. Spelled ONCE (the `Pinboard.room` rule) — a
    /// literal repeated across the strip, the fold and the switcher is three
    /// chances to disagree about which chip is showing.
    static let room = "Markets"

    static func isRoom(_ label: String) -> Bool { label == room }

    /// How many member seats must be PRESENT before the room's own venue
    /// SWITCHER draws (`PredictionRoomBook`/`FeedScreen.marketsSwitcher`).
    /// Distinct from the chip fold, which now has no floor at all — see the
    /// type doc. Renamed from `foldFloor` (2026-08-11): the old name described
    /// a floor on folding, which no longer exists.
    static let switcherFloor = 2

    /// The member seats, in CATALOG order.
    static let members: [String] = CategoryFold.members(of: room)

    static let memberSet: Set<String> = CategoryFold.memberSet(of: room)

    static func isMember(_ source: String) -> Bool { memberSet.contains(source) }

    /// The switcher's scopes: present members in CATALOG order.
    static func scopes(present: Set<String>) -> [String] {
        CategoryFold.scopes(category: room, present: present)
    }
}
