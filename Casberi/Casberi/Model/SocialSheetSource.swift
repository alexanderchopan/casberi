import Foundation
import SwiftData

/// The `Thing` half of the social sheet (prd §363, 2026-08-12) — everything
/// `SocialSheet.swift` deliberately cannot see.
///
/// The split is the house pattern (`StripeRoom`/`StripeRoomSource`,
/// `PeerRoom`/`PeerRoomSource`): the judgement is Foundation-only so a harness
/// can compile it whole, and the reads that touch SwiftData, UserDefaults and
/// the catalog live here, where there is no judgement to test — only lookups.
enum SocialSheetSource {

    /// The catalog's `Network` group, as a source test. NOT the same set as
    /// `SocialThread.sources`, and the difference is the whole point of §363:
    /// that one is the three networks with a thread API and a profile lookup,
    /// this one is every source whose things are social at all.
    ///
    /// A literal set rather than a `BridgeCatalog` walk on purpose — this is
    /// read on every sheet open, and the catalog answer is a linear scan over
    /// sixty-odd offers with a suffix match at the end of it. Guarded against
    /// the catalog by `social-sheet-selftest.sh`, so a renamed or added
    /// `Network` seat fails the build rather than silently losing its anatomy.
    static let sources: Set<String> = [
        "Bluesky", "Farcaster", "Nostr", "X", "Instagram", "TikTok", "Snapchat",
        "Telegram",
    ]

    static func isSocial(_ source: String) -> Bool { sources.contains(source) }

    // MARK: - Shape

    /// What anatomy this thing's sheet wears, or nil for none.
    ///
    /// Liveness: reads stored properties, so every caller must already hold a
    /// live model — which the sheet does (its `init` and `body` both guard,
    /// and this is only ever reached from inside those guards).
    static func shape(for thing: Thing) -> SocialSheet.Shape? {
        SocialSheet.shape(facts(for: thing))
    }

    static func facts(for thing: Thing) -> SocialSheet.Facts {
        SocialSheet.Facts(
            social: isSocial(thing.source),
            threadCapable: SocialThread.isSocial(thing.source),
            kind: thing.kind.rawValue,
            hasWords: hasWords(thing),
            context: thing.socialContext)
    }

    /// The prose the sheet would show, if there is any.
    ///
    /// `postText` first (the FULL post), else `content` — the same fallback
    /// `PostCard` and the sheet's own `postWords` already use, so a row and
    /// its sheet can never disagree about whether a thing has words.
    ///
    /// **A bare URL is not words.** Every save in the corpus stores its
    /// permalink in `content`, so without this test an Instagram save would
    /// classify as a post and the sheet would set an https:// string in
    /// display type as if it were somebody's sentence. The test is on the
    /// WHOLE trimmed string, never `contains`: a post that quotes a link
    /// inside a sentence is prose, and only a string that is nothing but a
    /// link is not.
    static func hasWords(_ thing: Thing) -> Bool {
        let words = (thing.postText ?? thing.content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return false }
        guard words.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return true }
        return !(words.hasPrefix("http://") || words.hasPrefix("https://"))
    }

    /// The words themselves — what `.post` puts in the title slot.
    static func words(for thing: Thing) -> String {
        let full = (thing.postText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !full.isEmpty { return full }
        let body = thing.content.trimmingCharacters(in: .whitespacesAndNewlines)
        // `content` is the permalink on every live-network post, so falling
        // back to it unconditionally would put a URL where the words go. The
        // title is the honest last resort — it is at worst a clamp OF the
        // words, never a different string.
        return hasWords(thing) && !body.isEmpty ? body : thing.title
    }

    // MARK: - What the eyebrow already said

    /// Does the thing sheet's eyebrow lead with the PERSON (prd §451)?
    ///
    /// When it does it draws a face and "@dwr · in /design · 2h ago" — who,
    /// why and when — and the reception block's live sentence underneath was
    /// the same source and the same `contextPhrase` said again. This is the
    /// eyebrow's own condition, lifted here so ONE predicate decides both what
    /// the eyebrow draws and what the sentence stands down for; two copies is
    /// how a card ends up either repeating itself or saying neither.
    ///
    /// A transcript is excluded for the eyebrow's own reason: a conversation's
    /// `authorHandle` is the thread's name, not a person, so wearing it would
    /// introduce a chat as somebody.
    static func eyebrowLeadsWithPerson(_ thing: Thing, shape: SocialSheet.Shape?) -> Bool {
        guard let shape, shape != .transcript else { return false }
        return !SocialThread.shortHandle(thing.authorHandle ?? "").isEmpty
    }

    // MARK: - Reception

    /// The "how it landed" reading for one thing, or nil when there is nothing
    /// honest to say.
    @MainActor
    static func reception(for thing: Thing, shape: SocialSheet.Shape,
                          live: SocialEngagement?,
                          context: ModelContext?) -> SocialReception? {
        // Live when it lands, the sync's own snapshot until then — the same
        // precedence `SocialPostContent` has kept since 2026-07-16, moved here
        // so one place decides it.
        let stored = SocialEngagement(
            likes: thing.likeCount.map { SocialCount(value: $0) },
            reposts: thing.repostCount.map { SocialCount(value: $0) },
            replies: thing.replyCount.map { SocialCount(value: $0) })
        let shown = live ?? (stored.isEmpty ? nil : stored)
        let archive = Corpus.bulkImportSources.contains(thing.source)

        return SocialReception.compose(.init(
            source: thing.source,
            shape: shape,
            archive: archive,
            when: thing.capturedAt,
            importedAt: archive ? importedAt(source: thing.source, context: context) : nil,
            act: act(for: thing),
            phrase: SocialThread.contextPhrase(for: thing),
            eyebrowNamesIt: eyebrowLeadsWithPerson(thing, shape: shape),
            likes: shown?.likes.map {
                .init(text: $0.text, noun: String(localized: "likes")) },
            reposts: shown?.reposts.map {
                .init(text: $0.text, noun: SocialThread.recastWord(thing.source).lowercased()) },
            replies: shown?.replies.map {
                .init(text: $0.text, noun: String(localized: "replies")) },
            likers: SocialLikers.shared.roll(for: thing.sourceRef)?.line,
            ceiling: ceiling(for: thing, shape: shape)))
    }

    /// What the person DID. Tags first, because a bulk import writes the act
    /// straight onto the row as a §308 facet ("Liked", "Saved", "Reply") and
    /// those are the rows whose sentence carries a date; `socialContext` is the
    /// live networks' marker for the same idea.
    ///
    /// nil is a real answer, not a gap: a cast an account you watch posted is
    /// nobody's act of yours, and the sentence correctly says so by omission.
    static func act(for thing: Thing) -> SocialReception.Act? {
        let tags = Set(thing.tags)
        if tags.contains("Liked") { return .liked }
        if tags.contains("Saved") { return .saved }
        if tags.contains("Reply") { return .replied }
        if tags.contains("Comment") { return .wrote }
        if tags.contains("Post") || tags.contains("Thread") { return .posted }
        switch thing.socialContext {
        case "liked":  return .liked
        case "follow": return .followed
        case "reply":  return .replied
        default:       return nil
        }
    }

    /// What a source structurally cannot give us, for the one shape where an
    /// empty card reads as a broken fetch rather than a stated limit.
    ///
    /// Instagram alone, and only for a save: §245 measured that an IG export
    /// records a saved post as a handle and a timestamp and NOTHING else — no
    /// caption, no image, confirmed against four independent parsers. Every
    /// other save in the corpus really does have a page behind it, so saying
    /// this anywhere else would be inventing a limitation.
    static func ceiling(for thing: Thing, shape: SocialSheet.Shape) -> String? {
        guard shape == .save, thing.source == "Instagram" else { return nil }
        guard (thing.previewImageURL ?? "").isEmpty, thing.previewImageData == nil
        else { return nil }
        return String(localized:
            "Instagram's export records the handle and the date; the caption and the image stay on Instagram.")
    }

    /// When this source's archive was read, off the import receipt's own date
    /// — no new `Thing` field, and therefore no CloudKit Production deploy
    /// (§310 already reads the same row for staleness).
    ///
    /// Scoped by `sourceRef` and capped at one row: this is called on every
    /// social sheet open, and "no screen reads the whole corpus to say one
    /// thing" is a standing rule here.
    @MainActor
    static func importedAt(source: String, context: ModelContext?) -> Date? {
        guard let context else { return nil }
        let ref = Corpus.importReceiptRef(source: source)
        var d = FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef == ref })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first?.capturedAt
    }

    // MARK: - The person shape

    /// Their newest posts already in the corpus — what makes a follower sheet
    /// an answer to "who is this?" rather than a notice that somebody exists.
    ///
    /// Scoped by source AND handle with a hard `fetchLimit`, never a corpus
    /// walk. Returns [] rather than nil for the ordinary case: most people who
    /// follow you have never posted anything you've landed, and an empty
    /// section is the honest reading of that.
    @MainActor
    static func recentPosts(by handle: String, source: String,
                            context: ModelContext, limit: Int = 3) -> [Thing] {
        let clean = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        var d = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == source && $0.authorHandle == clean },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        // Over-fetch, because the filter below runs in Swift: a `#Predicate`
        // comparing an OPTIONAL `socialContext` against a literal is exactly
        // the shape that reads fine and behaves surprisingly, and this is a
        // small bounded fetch either way.
        d.fetchLimit = limit + 3
        // A FOLLOW NOTICE IS NOT SOMETHING THEY POSTED (2026-08-12).
        // `SocialInbound.landFollower` stamps `authorHandle` on the follower
        // row, so the very row this card is opened FROM came back as one of
        // "What they post" — the person's own shelf led with "Sam (@sam)
        // started following you", and at `limit` 3 it pushed a real post off
        // the end. Not a demo artifact: it reproduces for any followed
        // account whose posts are also in the corpus.
        //
        // `.live` at the boundary (corollary 4): this array is handed onward to
        // a view, so the guarantee is made here rather than promised to every
        // reader downstream.
        return ((try? context.fetch(d)) ?? []).live
            .filter { $0.socialContext != "follow" }
            .prefix(limit)
            .map { $0 }
    }
}
