import Foundation

/// The category fold (prd §351, 2026-08-11, generalizing `MarketsRoom`): every
/// source-bearing chip in the strip is a CATEGORY chip, ALWAYS — not a fold
/// that only kicks in once a category is crowded.
///
/// **What changed from the Markets-only fold this replaces.** `MarketsRoom`
/// (2026-08-10) folded exactly one category, and only once ≥2 of its members
/// were present (`foldFloor`) — a lone connected market seat kept its own
/// icon. This engine drops the floor entirely: a category with exactly one
/// connected member still folds to its category chip, word-labeled, the
/// moment the user answered "i want the category chips always" rather than
/// "fold when crowded." `MarketsRoom` itself now shims onto this file for its
/// callers that still need Markets specifically (its dedicated venue
/// switcher screen, which no other category has yet).
///
/// **THE CENTRAL INVARIANT survives unchanged.** A category name is a chip
/// LABEL, never a source: `FeedFilter.source` stays a real seat at all times,
/// `chipLabel`/`landing`/`remember` are the only places a label and a source
/// ever meet, and nothing downstream of the strip (no `@Query` shape, no
/// `FeedScreen.Shape` case, no `Corpus.earnsRoom` exception, no deep-link
/// rewrite) ever sees a category string. This is the exact property that made
/// the Markets fold safe to ship, generalized rather than re-derived.
///
/// **Composable across categories because membership is disjoint.**
/// `BridgeCatalog.category(of:)` gives every offer exactly one category, so
/// folding category A over an ordered list never touches a label category B
/// owns — `foldAll` can therefore apply every category in any order and reach
/// the same result.
///
/// **What this does NOT do.** It does not decide what a category chip's ROOM
/// looks like once you're inside it — that is still per-category (Markets
/// keeps its own venue switcher; most categories have none yet and simply
/// land on the resolved member, reachable individually through the Sources
/// Tray in the meantime, per §351's own recommendation). It does not touch
/// Wallet's own room content, and it does not build a switcher for any
/// category besides Markets — both are flagged in §351 as their own passes.
enum CategoryFold {
    /// Every catalog category's members, resolved once — `static let`, not a
    /// computed property, for the same perf reason `MarketsRoom.members` was:
    /// this is read on every strip body evaluation (through `isCategory`,
    /// `chipLabel`), and the catalog is a compile-time constant so there is
    /// nothing to gain by re-deriving it per read.
    private static let memberCache: [String: [String]] = {
        var out: [String: [String]] = [:]
        for category in BridgeCatalog.categories {
            out[category.name] = BridgeCatalog.offers
                .filter { category.groups.contains($0.group) }
                .map(\.name)
        }
        return out
    }()

    private static let memberSetCache: [String: Set<String>] = {
        memberCache.mapValues(Set.init)
    }()

    /// A category's members, in catalog order.
    static func members(of category: String) -> [String] { memberCache[category] ?? [] }

    static func memberSet(of category: String) -> Set<String> { memberSetCache[category] ?? [] }

    static func isMember(_ source: String, of category: String) -> Bool {
        memberSetCache[category]?.contains(source) ?? false
    }

    /// Is `label` one of the catalog's category names — the strip's own test
    /// for "render this as a word chip, not a source icon."
    static func isCategory(_ label: String) -> Bool { memberCache[label] != nil }

    /// Fold ONE category over an ordered chip list. The folded chip takes the
    /// position of the highest-ranked member it replaces (`ChipMemory`'s
    /// learning still decides where the cluster sits), and — unlike
    /// `MarketsRoom.fold` — there is no floor: a single present member still
    /// folds, because the strip no longer shows a bare source chip at all.
    static func fold(_ ordered: [String], category: String, members: Set<String>) -> [String] {
        guard !members.isEmpty else { return ordered }
        var folded: [String] = []
        var placed = false
        for label in ordered {
            guard members.contains(label) else { folded.append(label); continue }
            if !placed { folded.append(category); placed = true }
        }
        return folded
    }

    /// Fold EVERY catalog category over an ordered chip list, one pass per
    /// category. Safe to compose (see the type doc): each pass only replaces
    /// labels that belong to its own category, so passes never interfere.
    static func foldAll(_ ordered: [String]) -> [String] {
        var chips = ordered
        for category in BridgeCatalog.categories {
            chips = fold(chips, category: category.name, members: memberSetCache[category.name] ?? [])
        }
        return chips
    }

    /// Which chip is lit for a given source — the strip asks this rather than
    /// comparing against `filter.source` directly, or standing inside a
    /// category room would light no chip at all once that source's own circle
    /// is gone (the `MarketsRoom.chipLabel` reasoning, unchanged).
    ///
    /// Fully generic: resolves the source's OWN category through the catalog
    /// rather than taking one as a parameter, so a single call answers
    /// correctly no matter which category (if any) `source` belongs to.
    static func chipLabel(for source: String, folded: [String]) -> String {
        guard let category = BridgeCatalog.category(forSource: source), folded.contains(category)
        else { return source }
        return category
    }

    // MARK: - Where a category chip opens

    /// One persisted "last visited member" per category — `MarketsRoom` had
    /// exactly one such key because it only ever folded one category; this is
    /// the same idea, namespaced.
    private static func lastVenueKey(_ category: String) -> String {
        "categoryFold.lastVenue.\(category)"
    }

    /// The member the folded chip opens onto: where you left off in THIS
    /// category, else the highest-ranked present member.
    static func landing(category: String, present: [String]) -> String? {
        if let last = UserDefaults.standard.string(forKey: lastVenueKey(category)),
           present.contains(last) { return last }
        return present.first
    }

    /// Called when a source becomes active, so its category's chip reopens
    /// there next time. Reads before it writes (the `MarketsRoom.remember`
    /// reasoning, unchanged): driven by `onChange(of: filter.source)`, which
    /// fires on every room switch, and re-writing an unchanged value would
    /// dirty UserDefaults on each one for nothing. A no-op for a source that
    /// belongs to no catalog category ("All", "Pinned", or anything the
    /// catalog has never heard of).
    static func remember(_ source: String) {
        guard let category = BridgeCatalog.category(forSource: source) else { return }
        let key = lastVenueKey(category)
        guard UserDefaults.standard.string(forKey: key) != source else { return }
        UserDefaults.standard.set(source, forKey: key)
    }

    /// A category's present members, in CATALOG order — for a switcher's own
    /// display (Markets' own reasoning, unchanged: a capsule this short has
    /// not earned learned order, and one that reshuffles between opens reads
    /// as broken).
    static func scopes(category: String, present: Set<String>) -> [String] {
        members(of: category).filter { present.contains($0) }
    }
}
