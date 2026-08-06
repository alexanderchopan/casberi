import Foundation
import SwiftData

/// A link already saved from a DIFFERENT source, landed earlier, resurfacing
/// now — the app recognizing its own corpus instead of silently re-showing
/// the same page as if it were new (delight pass 2026-07-21). Real matches
/// only: the exact same URL, a different source, strictly earlier
/// `capturedAt`. Exact string equality on purpose, not a loosened
/// normalization — a wrong "you already saved this" reads as a bug, and a
/// missed one costs nothing.
enum CrossSourceEcho {
    static func find(for thing: Thing, context: ModelContext) -> String? {
        guard thing.kind == .link, !thing.content.isEmpty else { return nil }
        let content = thing.content
        let source = thing.source
        let capturedAt = thing.capturedAt
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate<Thing> {
            $0.content == content && $0.source != source && $0.capturedAt < capturedAt
        })
        guard let candidates = try? context.fetch(descriptor), !candidates.isEmpty else { return nil }
        return candidates.min(by: { $0.capturedAt < $1.capturedAt })?.source
    }

    /// You WROTE about this link, somewhere else, years ago (2026-08-05,
    /// prd §307).
    ///
    /// The read only a whole corpus can make. `find` above matches a link
    /// against the same link saved twice; this matches a link against a POST
    /// whose text contains it — so opening an article can answer "you linked
    /// this on X in 2019", which neither X nor a bookmark manager can do,
    /// because each holds only its own half.
    ///
    /// STILL EXACT, not topical. The tempting version of this feature is "you
    /// posted about this subject", and that is an inference: it would be
    /// occasionally delightful and regularly wrong, and a wrong "you already
    /// wrote about this" reads as a bug — `find`'s own reasoning, unchanged.
    /// What makes the exact version possible at all is that `XArchiveImport`
    /// swaps every t.co shortening back to its real destination, so the URL in
    /// a fifteen-year-old post is literally the URL in the corpus today.
    ///
    /// Substring rather than equality, because a post wraps its link in
    /// sentence: the URL is bounded on the left by the search itself and on the
    /// right by nothing, so a stored link that is a PREFIX of a longer one
    /// could match it. Accepted deliberately — the failure is naming a post
    /// that linked a more specific page on the same site, and the alternative
    /// (parsing every post's URLs at read time) costs a scan of the whole
    /// corpus on every sheet open.
    static func writtenAbout(_ thing: Thing, context: ModelContext)
        -> (source: String, date: Date)? {
        guard thing.kind == .link, !thing.content.isEmpty,
              thing.content.hasPrefix("http"), thing.content.count >= 12 else { return nil }
        // A bare host matches half the corpus and says nothing — a post that
        // mentions "example.com" is not a post about this article.
        guard let url = URL(string: thing.content), (url.path.count > 1) else { return nil }

        let needle = thing.content
        let source = thing.source
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate<Thing> {
            $0.content.contains(needle) && $0.source != source
        })
        guard let rows = try? context.fetch(descriptor) else { return nil }
        // `.note` only: a post or a note somebody WROTE. A link row whose
        // content merely equals the URL is `find`'s job above, and counting it
        // here would report "you wrote about this" for a bookmark.
        let written = rows.live.filter { $0.kind == .note && $0.capturedAt < thing.capturedAt }
        guard let earliest = written.min(by: { $0.capturedAt < $1.capturedAt }) else { return nil }
        return (earliest.source, earliest.capturedAt)
    }
}
