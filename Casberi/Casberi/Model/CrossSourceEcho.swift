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
}

// `writtenAbout` — "you wrote about this link, somewhere else, years ago"
// (2026-08-05, prd §307) — retired 2026-08-08 (prd §340), superseded by
// `ThingLinks`'s `.mention` edge on the thing sheet's "Points at this" shelf.
// It reported only the EARLIEST post carrying this link, as a spec-table row
// that could not be tapped; `ThingLinks.pointingAt` reports every one of them,
// walkable, using the same exact-containment rule this function pioneered
// (kept as `ThingLinks.canonicalLinks(in:)`'s extraction plus
// `ThingLinks.hasPath`'s bare-host guard).
