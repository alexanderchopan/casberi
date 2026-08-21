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
/// looks like once you're inside it — every folded category with ≥2 present
/// members gets the generic `CategoryVenueSwitcher` (the §351 follow-up,
/// "each category should have a switcher"; this doc once said only Markets
/// had one, which cost a session a wrong answer), and anything beyond that
/// is the room's own business. It does not touch Wallet's own room content:
/// §354 ruled Wallet behaves like every other category, its one divergence
/// being the landing anchor below.
enum CategoryFold {
    /// How many members must be PRESENT before a category's own venue
    /// SWITCHER draws (`CategoryVenueSwitcher`, wired generically in
    /// `FeedScreen.categorySwitcher` — prd §351, "each category should have a
    /// switcher"). A different question from whether the CHIP folds, which has
    /// no floor at all.
    ///
    /// **ONE since 2026-08-11 (user ruling), reversing this file's own
    /// argument.** It was 2, reasoning that "a switcher offering one scope is
    /// not a control" — true in isolation, and wrong about the thing that
    /// actually matters, which is that a room should not change SHAPE based on
    /// how many apps you happen to have connected to it. Reported from the
    /// Work category with GitHub as its only seat: "we aren't showing the icon
    /// source bar, but i think we should so it's the same on every screen —
    /// it's ok to have a bar with only one icon in it."
    ///
    /// So the bar is chrome that says WHICH ROOM YOU ARE IN, not a control
    /// that only earns its place by offering a choice. At one member it names
    /// the room and shows you its face; at two it also switches. That is the
    /// same reading `MainSurface.roomControls` already gave it by mounting it
    /// on the shell rather than the screen (§357).
    ///
    /// `MarketsRoom.switcherFloor` aliases this, so Markets moves with it: a
    /// single connected exchange now gets the generic switcher and
    /// `PredictionRoomBook` stands its own down, which is exactly the
    /// no-switcher-inside-a-switcher rule it already followed at two.
    static let switcherFloor = 1

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

    /// `source` here is a THING'S OWN `source` string, not a catalog offer
    /// name — resolved through `category(forSource:)`, never by testing the
    /// raw member set directly (the alias bug found live, 2026-08-11 — see
    /// `fold`'s own doc; this is the SAME bug in a second function, found
    /// because it fed `MainSurface`'s `categoryVenues[category]`, which is
    /// what the switcher scrolls-to-center and what `scopes` below filters —
    /// so "Privacy Pools" was invisible to the Wallet switcher for the exact
    /// reason it once failed to fold at all).
    static func isMember(_ source: String, of category: String) -> Bool {
        BridgeCatalog.category(forSource: source) == category
    }

    /// Is `label` one of the catalog's category names — the strip's own test
    /// for "render this as a word chip, not a source icon."
    static func isCategory(_ label: String) -> Bool { memberCache[label] != nil }

    /// Fold ONE category over an ordered chip list. The folded chip takes the
    /// position of the highest-ranked member it replaces (`ChipMemory`'s
    /// learning still decides where the cluster sits), and — unlike
    /// `MarketsRoom.fold` — there is no floor: a single present member still
    /// folds, because the strip no longer shows a bare source chip at all.
    ///
    /// **Membership is resolved PER LABEL through `BridgeCatalog.category(forSource:)`,
    /// never by testing `members.contains(label)` directly (bug found live,
    /// 2026-08-11 — see the type doc's own reasoning for why this file exists
    /// and got it wrong on its first pass anyway).** `members` names CATALOG
    /// OFFERS ("0xBow Privacy Pools"), but a chip's label is the THING'S OWN
    /// `source` string ("Privacy Pools") — the exact alias family
    /// `BridgeCatalog.offer(forSource:)` suffix-matches for, because a source
    /// string and its catalog display name are allowed to differ. Checking the
    /// raw member set against a label meant Privacy Pools (and any other
    /// aliased seat) never folded at all — it sat beside "Wallet" as its own
    /// chip, silently contradicting the ONE thing this fold claims to do,
    /// caught only by reading the strip's own live `chipLabels:` NSLog output
    /// rather than by this file's own self-test, whose stub catalog had no
    /// aliased member to expose it (fixed in `category-fold-selftest.sh`
    /// alongside this). `members` stays as a cheap SKIP for a category with
    /// nothing to ever match, not as the membership test itself.
    /// Sources that keep their OWN chip and never fold into their category.
    ///
    /// A venue switcher says "different views of the same subject" — Aave, Morpho and
    /// Peer are lenses on YOUR ADDRESSES, so folding them behind one Wallet chip loses
    /// nothing.
    ///
    /// **WALLETBEAT WAS HERE FOR A DAY AND IS NOT (user ruling 2026-08-20, prd §423).**
    /// It was exempted the same morning on the argument that reviewing the SOFTWARE your
    /// money sits in is a change of subject rather than a change of view. The ruling is
    /// that it is a SOURCE ROOM in the Wallet band like any other, and belongs behind
    /// that chip: a top-level chip is what the strip gives a whole category, and spending
    /// one on a single seat is what the fold exists to stop. The report the exemption was
    /// written for — "I don't see Walletbeat" — was really about a room that had just
    /// moved bands, and the venue switcher is the answer to it.
    ///
    /// CardPointers stays, and the difference is its SUBJECT: every other Wallet member
    /// reads addresses or the software holding them, while CardPointers reads offers on
    /// cards from banks — nothing it shows is about a wallet at all, so a switcher
    /// promising "another view of this" would not be telling the truth.
    ///
    /// Deliberately a SOURCE list, not a category one: the rest of Wallet folds exactly
    /// as before, and this stays the narrow exception it is rather than turning the fold
    /// off for a whole band.
    static let neverFold: Set<String> = ["CardPointers"]

    static func fold(_ ordered: [String], category: String, members: Set<String>) -> [String] {
        guard !members.isEmpty else { return ordered }
        var folded: [String] = []
        var placed = false
        for label in ordered {
            // An exception keeps its own chip and does NOT count as a member for the
            // cluster's placement — otherwise a category whose only present member is
            // exempt would still plant an empty cluster chip.
            guard !neverFold.contains(label) else { folded.append(label); continue }
            guard BridgeCatalog.category(forSource: label) == category
            else { folded.append(label); continue }
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
        guard !neverFold.contains(source) else { return source }
        guard let category = BridgeCatalog.category(forSource: source), folded.contains(category)
        else { return source }
        return category
    }

    /// What a seat is CALLED in a switcher capsule, which is not always what
    /// it is (prd §356, user: "we could make the 'wallet' room be 'wallets'
    /// plural to make it different").
    ///
    /// Exactly one seat renames today, for one reason: standing in the balance
    /// room lit the word "Wallet" TWICE, once as the category chip and once as
    /// the seat pill, with no way to tell which control you were reading. The
    /// plural is also the truer word — the room shows up to five addresses and
    /// its own balance card has always said "Across your wallets".
    ///
    /// **DISPLAY ONLY, and this is the central invariant read backwards.**
    /// `fold`/`landing`/`chipLabel` exist to keep a category NAME out of
    /// `FeedFilter.source`; this keeps a display LABEL out of it too. The seat
    /// stays the literal `"Wallet"` everywhere it counts — every landed
    /// `Thing.source`, every dedupe key, `FeedScreen.Shape(source:)`, the
    /// `casberi://feed` links and the CloudKit rows — so nothing downstream
    /// can tell this function ran. Renaming the SEAT instead would re-land
    /// every wallet row on every device.
    static func venueLabel(_ venue: String) -> String {
        venue == walletRoom ? String(localized: "Wallets") : venue
    }

    // MARK: - Where a category chip opens

    /// One persisted "last visited member" per category — `MarketsRoom` had
    /// exactly one such key because it only ever folded one category; this is
    /// the same idea, namespaced.
    private static func lastVenueKey(_ category: String) -> String {
        "categoryFold.lastVenue.\(category)"
    }

    /// A category whose chip always opens on ONE member, regardless of where
    /// you last stood — Wallet, and only Wallet (user ruling, prd §354,
    /// 2026-08-11: "wallet should always land on balance room"). The balance
    /// room is the SUBJECT — Peer, Privacy Pools, Gnosis Pay and Railgun are
    /// ledgers riding the same watched addresses — so the chip reopening on
    /// whichever rider you last glanced at reads as landing somewhere
    /// strange, where Markets reopening on the venue you live in is the whole
    /// point of remembering (no venue there is home). The riders stay
    /// reachable through the category switcher, and `remember` still records
    /// them: the memory is the fallback for the day the anchor is somehow
    /// absent, and the switcher's own centering reads the active seat
    /// regardless.
    private static let anchors: [String: String] = [walletCategory: walletRoom]

    /// The Wallet category's name, and the balance room inside it — the two
    /// strings §354's anchor and §356's face rail both key on, spelled once so
    /// a catalog rename breaks a build rather than silently switching the
    /// anchor off and the rail out.
    static let walletCategory = "Wallet"

    /// The balance room's SOURCE — the literal every landed wallet `Thing`
    /// carries, which dedupe, `FeedScreen.Shape(source:)`, the deep links and
    /// the CloudKit rows all key on. It happens to equal `walletCategory`
    /// today, and the pair is spelled separately anyway: they are a category
    /// and a seat, they are only accidentally the same word, and that
    /// coincidence is exactly what §356's "Wallets" display label exists to
    /// hide from the reader — never from the data.
    static let walletRoom = "Wallet"

    /// The member the folded chip opens onto: the category's anchor when it
    /// has one and that member is present, else where you left off in THIS
    /// category, else the highest-ranked present member.
    static func landing(category: String, present: [String]) -> String? {
        if let anchor = anchors[category], present.contains(anchor) { return anchor }
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
    ///
    /// `present` holds SOURCE strings (what `filter.source` actually takes),
    /// which is why this sorts `present` itself rather than filtering
    /// `members(of:)` (catalog offer NAMES) by it — the same alias bug as
    /// `isMember`/`fold`, a third place it shipped (2026-08-11): "Privacy
    /// Pools" the source is never equal to "0xBow Privacy Pools" the catalog
    /// name, so the old `filter` silently dropped every aliased present
    /// member from the switcher instead of merely mis-ordering it. Each
    /// present source resolves to its OWN catalog offer's name (falling back
    /// to itself when the catalog has never heard of it, so an unknown source
    /// still sorts — to the tail — rather than vanishing) before ranking
    /// against the category's catalog-order member list.
    static func scopes(category: String, present: Set<String>) -> [String] {
        let order = members(of: category)
        // Alias-aware membership FIRST (a present source belonging to some
        // OTHER category must never leak into this switcher), then rank the
        // survivors by their own catalog offer's position.
        // A `neverFold` source keeps its own chip, so it must NOT also appear as a venue
        // in its category's switcher — it would be reachable twice, once as itself and
        // once inside a cluster it deliberately sits outside of.
        let filtered = present.filter {
            !neverFold.contains($0) && BridgeCatalog.category(forSource: $0) == category
        }
        func rank(_ source: String) -> Int {
            let name = BridgeCatalog.offer(forSource: source)?.name ?? source
            return order.firstIndex(of: name) ?? Int.max
        }
        return filtered.sorted {
            let ra = rank($0), rb = rank($1)
            return ra != rb ? ra < rb : $0 < $1
        }
    }
}
