import Foundation

/// Where a row came from — the ONLY hierarchy the All feed applies
/// (prd §378). Provenance, never predicted interest: each tier is a
/// one-sentence fact about the row's origin, so the feed can be skimmed
/// without anything being ranked, reordered or scored.
enum FeedTier {
    /// A deliberate act of yours — a screenshot, a voice note, anything from
    /// You. The same "human capture" set `FeedFold.bundleable` has named since
    /// 2026-07-09; one definition, so the two cannot disagree about what a
    /// deliberate act is.
    case made
    /// A row where you are the SUBJECT: consent waiting on you, money moving,
    /// a clock of yours. Not "important" — a fact about the row.
    case concerns
    /// Everything that simply arrived: posts, articles, drops, trending. The
    /// only tier that recedes.
    case arrived
}

/// The All feed's fold decisions, as pure functions over `Thing` (prd §379).
///
/// **Why this file exists.** These rules carry real judgment — strip beats
/// sentence, remote images dedupe and stored pixels don't, the two-tile floor,
/// the threshold, the clock carve-out, the tier table — and every one of them
/// is invisible to a build and to a screen sweep: a feed that folds wrongly
/// renders perfectly, it just says the wrong thing about what arrived. Until
/// this extraction they lived as private methods inside a 5,000-line SwiftUI
/// view that no harness can compile, so the only proof they were right was
/// that somebody had read them. §255 is the record of what that is worth: a
/// gate that measured THINGS while the feed drew ROWS, wrong for a month,
/// found by eye.
///
/// Everything here is a pure function over value types and `Thing`'s stored
/// properties — no SwiftUI, no SwiftData, no view state — so
/// `scripts/feed-fold-selftest.sh` compiles it WHOLE and unmodified against an
/// inert `Thing` stub. Its two view-layer dependencies are INJECTED rather than
/// imported (`faceSources`, and whether a row is live) precisely so that stays
/// true; the drift guards in that harness are what keep the injected values
/// honest.
enum FeedFold {
    /// How many things from one source in one day collapse into a single row
    /// (lowered from 4, 2026-07-12 — smaller same-source runs were the real
    /// All-feed clutter). ONE number for both folds since §377: a strip and a
    /// bundle are the same compression drawn two ways, and a run that is "too
    /// small to fold" should not depend on which way it would have been drawn.
    static let bundleThreshold = 3

    /// How many members a strip draws before the count carries the rest.
    /// Four, because the tiles sit in the row's own 26pt leading seat beside a
    /// name and a count: past four they start eating the title on the narrowest
    /// iPhone. Volume beyond that is what the source's room is for (§35).
    static let stripCap = 4

    /// One member the strip will draw, named by its INDEX into the run rather
    /// than by the model it came from — which is what keeps this whole file
    /// pure, and what lets the harness assert the dedupe and the door priority
    /// without a `Thing` in sight. The view maps a choice back to its member.
    struct TileChoice: Equatable {
        let index: Int
        /// The tile's remote image URL, or nil when the tile is the member's
        /// own stored pixels.
        let remote: String?
        /// A face is a circle, everything else the app-icon squircle.
        let circular: Bool
    }

    /// Which shape a source's same-day run folds into.
    enum Decision: Equatable {
        /// Drawn as its members.
        case strip([TileChoice])
        /// Drawn as a sentence about them, with up to three DISTINCT member
        /// pictures fanned behind the leader.
        case bundle([String])
    }

    // MARK: - Tier

    static func tier(_ t: Thing) -> FeedTier {
        if t.kind == .screenshot || t.kind == .voice
            || t.source == "You" || t.source == "Voice" { return .made }
        if t.kind == .approval || t.kind == .transaction
            || t.kind == .event || t.kind == .reminder
            || t.dueAt != nil || t.isFlagged { return .concerns }
        return .arrived
    }

    // MARK: - Eligibility

    /// Whether a thing may collapse into a SENTENCE about its run
    /// ("Wallet · 14 transactions"). Since §377 this is no longer the same
    /// question as "may it fold at all" — `stripCandidate` is the other door,
    /// and the two exemption lists mean different things:
    ///
    /// - A screenshot stays out HERE forever. Its content is its pixels, so a
    ///   sentence is the one shape that destroys it. It folds into a strip
    ///   instead, which shows the pictures.
    /// - Voice, approvals and anything from You stay out of BOTH. These are
    ///   genuinely one-at-a-time deliberate acts at low volume, which is the
    ///   2026-07-09 reasoning still describing them accurately — unlike the
    ///   social exemption below, which volume outgrew.
    ///
    /// The test that decides a future exemption: a source earns one while its
    /// rows are BOTH rare and individually distinct. Volume alone retires it
    /// (Bluesky/Farcaster, 2026-08-09), and if the rows are distinct in a way
    /// a picture can carry, the answer is a strip rather than an exemption.
    static func bundleable(_ t: Thing) -> Bool {
        t.kind != .screenshot && t.kind != .voice && t.kind != .approval
            && t.source != "You" && t.source != "Voice"
            // REVERSED 2026-08-09 (user: following 140 Farcaster accounts made
            // "deliberate reads" the wrong call at that follow count — the
            // 2026-07-12 ruling held for a handful of watched accounts, not a
            // feed wide enough to flood All on its own). Bluesky/Farcaster now
            // bundle the same as any other source: 3+ same-day posts collapse
            // into one row, still fully readable one tap away in the source's
            // own `.social` room, which never bundles.
            //
            // Watched tokens stay out: each row wears its own sparkline
            // (TokenPulse), so collapsing 3+ into "Tokens · N things" silently
            // drops every one of them.
            && t.source != "Tokens"
            // And Bitrefill orders: each wears the product's own artwork and a
            // "name · $value" title (prd §103). Deliberate purchases, low
            // volume — not machine bulk — so a gift-card spree stays legible
            // row by row instead of "Bitrefill · N things".
            && t.source != "Bitrefill"
            // And 1Claw grants: policies are typically created together, so
            // they share a created_at day — bundled, the grant table the
            // bridge exists to show collapses into "1Claw · N links".
            && t.source != "1Claw"
    }

    /// The FACE a row already leads with, when it leads with one. `faceSources`
    /// is injected — it is `BandRow.faceSources`, the registry that already
    /// decides whose rows lead with a face, so a source that gains a face
    /// leader gains a face strip the same day and a strip can never draw an
    /// identity the row itself doesn't.
    ///
    /// This is the only door that reads `authorAvatarURL`: RSS's publisher
    /// mark rides the same field but is NOT a strip identity — its runs come
    /// through the own-art door instead, so an RSS strip shows the ARTICLES'
    /// pictures, never the feed's logo repeated four times. A strip earns its
    /// place only where it shows MORE than the shape it replaces.
    static func identityLeader(_ t: Thing, faceSources: Set<String>) -> String? {
        guard let avatar = t.authorAvatarURL, !avatar.isEmpty,
              faceSources.contains(t.source) else { return nil }
        return avatar
    }

    /// Whether a thing can be drawn as itself in a strip — any row that
    /// carries a picture of its own. Three doors, checked cheapest-first, and
    /// the ORDER is also the tile priority in `tileChoices`:
    ///
    /// 1. A FACE — the user's own ruling for posts: the run is drawn as WHO,
    ///    not as the posts' photos.
    /// 2. OWN PIXELS — a screenshot always (its kind IS a picture; the view's
    ///    `PhotoWell` falls back to the PHAsset when the stored bytes haven't
    ///    healed yet), or stored `previewImageData` (a healed file image).
    /// 3. REMOTE ART — an album cover, an article's or episode's art, a drop's
    ///    image.
    ///
    /// The `previewImageData` read faults externalStorage bytes, so it sits
    /// LAST among the model reads and only runs for rows with no URL to check
    /// first.
    static func stripCandidate(_ t: Thing, faceSources: Set<String>) -> Bool {
        if t.kind == .screenshot { return true }
        if identityLeader(t, faceSources: faceSources) != nil { return true }
        if let art = t.previewImageURL, !art.isEmpty { return true }
        return t.previewImageData != nil
    }

    /// A row whose whole point is a countdown or a live state — never folded
    /// (prd §377). §35 ruled that perishables show their countdown "everywhere
    /// … not just in their source's shape", and nothing enforced it: a day
    /// with three calendar events folded the next-up row away, and a live row
    /// cannot be floated to the top of its day (2026-07-21) once it has
    /// stopped existing as a row.
    ///
    /// `isLive` is injected because the live set is a bridge's runtime state
    /// (`TwitchIngest.liveRefs`), not a property of the thing.
    static func carriesAClock(_ t: Thing, nextEventID: UUID?, isLive: Bool) -> Bool {
        if let nextEventID, t.id == nextEventID { return true }
        return isLive
    }

    // MARK: - The fold

    /// The tiles a run draws, newest first, capped at `stripCap`.
    ///
    /// REMOTE images dedupe by URL and stored pixels do not, and the line sits
    /// exactly there on purpose: five posts from three people is three faces,
    /// and five songs off one record are ONE cover — the count says five
    /// either way ("who/what" and "how many" are different questions, and the
    /// same image repeated reads as a rendering fault, not volume). Five
    /// screenshots or five scanned pages are five DIFFERENT pictures by
    /// construction — there is no URL to agree on — and collapsing them would
    /// hide the members the strip exists to show.
    static func tileChoices(_ members: [Thing], faceSources: Set<String>) -> [TileChoice] {
        var choices: [TileChoice] = []
        var seenRemote: Set<String> = []
        for (index, t) in members.enumerated() {
            guard choices.count < stripCap else { break }
            if let face = identityLeader(t, faceSources: faceSources) {
                guard seenRemote.insert(face).inserted else { continue }
                choices.append(TileChoice(index: index, remote: face, circular: true))
            } else if t.kind == .screenshot || t.previewImageData != nil {
                choices.append(TileChoice(index: index, remote: nil, circular: false))
            } else if let art = t.previewImageURL, !art.isEmpty {
                guard seenRemote.insert(art).inserted else { continue }
                choices.append(TileChoice(index: index, remote: art, circular: false))
            }
        }
        return choices
    }

    /// Strip first, sentence second (prd §377).
    ///
    /// The strip wins whenever it can be drawn, because it is strictly more
    /// informative: the same one row, carrying what arrived instead of a count
    /// of it. It needs at least TWO tiles to be worth the anatomy — one tile is
    /// a bundle with a nicer leader, which the bundle's own fan already is, and
    /// a lone repeated face reads as a rendering fault rather than as volume.
    /// (A one-album run therefore dedupes to a single tile, falls under this
    /// floor, and lands as the sentence with one cover — the honest rendering
    /// of "one record, five songs".)
    ///
    /// A run that cannot be a strip falls back to the sentence only if EVERY
    /// member is `bundleable` — otherwise the exemptions (a screenshot, an
    /// approval, a voice note) would be swallowed by a source's other rows.
    static func decide(_ members: [Thing], faceSources: Set<String>) -> Decision? {
        guard members.count >= bundleThreshold else { return nil }
        let choices = tileChoices(members, faceSources: faceSources)
        if choices.count >= 2 { return .strip(choices) }
        guard members.allSatisfy(bundleable) else { return nil }
        // The bundle's own pictures — the first three DISTINCT member images,
        // in feed order (newest first, since the day is). Deduped for the same
        // reason strip tiles are: a one-album run falls back here, and one
        // clean cover under "Music · 5 songs" says more than the same cover
        // fanned three times.
        var art: [String] = []
        var seenArt: Set<String> = []
        for m in members where art.count < 3 {
            guard let a = m.previewImageURL, !a.isEmpty,
                  seenArt.insert(a).inserted else { continue }
            art.append(a)
        }
        return .bundle(art)
    }

    /// Whether a fold recedes: only if EVERY member would (prd §378). One
    /// transaction or one clock inside a mixed run keeps the whole row at full
    /// weight, since the row is the only thing standing in for it.
    static func ambient(_ members: [Thing]) -> Bool {
        members.allSatisfy { tier($0) == .arrived }
    }
}
