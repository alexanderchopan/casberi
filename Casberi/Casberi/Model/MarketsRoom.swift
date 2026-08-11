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
/// switcher rather than a composition.
enum MarketsRoom {
    /// The folded chip's label. Spelled ONCE (the `Pinboard.room` rule) — a
    /// literal repeated across the strip, the fold and the switcher is three
    /// chances to disagree about which chip is showing.
    static let room = "Markets"

    static func isRoom(_ label: String) -> Bool { label == room }

    /// How many member seats must be PRESENT before the fold happens.
    ///
    /// Two, because one seat folded is a chip that hides nothing: it would
    /// replace a brand mark you recognize with a container holding that same
    /// mark, and add a switcher with one scope — the `PredictionVenueSwitcher`
    /// rule that a scope control with one scope is not a control. Below the
    /// floor the strip is byte-identical to what it was, and disconnecting back
    /// down to one seat un-folds it again.
    static let foldFloor = 2

    /// The member seats, in CATALOG order.
    ///
    /// Derived from the catalog's own Markets category rather than a list kept
    /// here, so a new Markets seat joins the fold the day it lands — the same
    /// single-source-of-truth rule `catalog-sync.sh` enforces for the website
    /// and the onboarding tiles. Note the category spans two `group` values
    /// ("Markets" and "NFTs"), which is why this reads `categories` rather than
    /// matching one group string.
    /// `static let`, not a computed property, and that is a perf decision not a
    /// style one. `memberSet` below is read on every body evaluation of the
    /// shell (through `isMember`, which `chipLabel` and `fold` both reach), and
    /// as computed properties the pair would filter all ~97 catalog offers and
    /// build a Set on each of those reads. The catalog is a compile-time
    /// constant, so both resolve once per launch (Swift's lazy static
    /// initialization) and are read thereafter — the same discipline
    /// `ChipMemory.snapshot` exists for.
    static let members: [String] = {
        let groups = BridgeCatalog.categories.first { $0.name == room }?.groups ?? []
        return BridgeCatalog.offers.filter { groups.contains($0.group) }.map(\.name)
    }()

    static let memberSet: Set<String> = Set(members)

    static func isMember(_ source: String) -> Bool { memberSet.contains(source) }

    /// Fold an ordered chip list — pure, so the ordering rule is testable
    /// without a shell.
    ///
    /// The folded chip takes the position of the HIGHEST-RANKED member it
    /// replaces, so `ChipMemory`'s learning still decides where the cluster
    /// sits: someone who lives in Kalshi keeps Markets near the front, someone
    /// who glances at it monthly keeps it near the back. Nothing is re-sorted
    /// and no member's learning is discarded — the weights still rank the
    /// switcher's landing and survive intact if the fold ever un-folds.
    ///
    /// That is true of the order this function RETURNS, which is what the strip
    /// wears from the next freeze onward. It is not true of the one session in
    /// which the fold first happens: `MainSurface.chipLabels` reconciles a
    /// frozen list against a live one, sees "Markets" as a label it has never
    /// held, and sends it to the HEAD — the same rule that gives any brand-new
    /// room the head slot, and correct for the same reason, since the folded
    /// chip arrives wearing the catch bob and a celebration off the right edge
    /// of the strip is one nobody sees.
    static func fold(_ ordered: [String], members: Set<String>) -> [String] {
        let present = ordered.filter { members.contains($0) }
        guard present.count >= foldFloor else { return ordered }
        var folded: [String] = []
        var placed = false
        for label in ordered {
            guard members.contains(label) else { folded.append(label); continue }
            if !placed { folded.append(room); placed = true }
        }
        return folded
    }

    /// Which chip is lit for a given source. The strip asks this rather than
    /// comparing against `filter.source` directly, or standing in Kalshi would
    /// light no chip at all once Kalshi's own circle is gone — and a filter you
    /// can't see reads as no filter — the same property the strip's own
    /// `ScrollViewReader` protects by keeping the active chip on screen.
    static func chipLabel(for source: String, folded: [String]) -> String {
        folded.contains(room) && isMember(source) ? room : source
    }

    // MARK: - Where the chip opens

    private static let lastVenueKey = "markets.lastVenue"

    /// The venue the folded chip opens onto: where you left off, else the
    /// highest-ranked present member.
    ///
    /// Remembering is the whole reason the fold does not cost a tap. A chip
    /// that always opened on a fixed default would make four of five venues
    /// strictly further away than they are today; opening where you were makes
    /// the common case identical to today and every other venue one capsule tap.
    static func landing(present: [String]) -> String? {
        if let last = UserDefaults.standard.string(forKey: lastVenueKey),
           present.contains(last) { return last }
        return present.first
    }

    /// Called when a market room is actually shown, so the chip reopens there.
    ///
    /// Reads before it writes: this is driven by `onChange(of: filter.source)`,
    /// which fires on every room switch in the app, and re-writing the same
    /// value would dirty UserDefaults on each one for no change at all.
    static func remember(_ source: String) {
        guard isMember(source),
              UserDefaults.standard.string(forKey: lastVenueKey) != source else { return }
        UserDefaults.standard.set(source, forKey: lastVenueKey)
    }

    /// The switcher's scopes: present members in CATALOG order, never learned
    /// order.
    ///
    /// Deliberately the opposite rule to the strip above it, and for the strip's
    /// own reason: position is half the identity of a control you operate by
    /// muscle memory, and this one is read every time the room opens. The strip
    /// earns its learned order by being long enough to hunt through; a capsule
    /// of four words is not, so it holds still instead.
    static func scopes(present: Set<String>) -> [String] {
        members.filter { present.contains($0) }
    }
}
