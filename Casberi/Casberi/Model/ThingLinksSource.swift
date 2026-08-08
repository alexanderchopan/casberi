import Foundation
import SwiftData

/// The `Thing`-reading half of the "points at this" shelf (2026-08-08,
/// prd §335) — everything `ThingLinks` deliberately cannot see.
///
/// Split for the reason `AddressConnectionsSource` and `ASCRoomSource` are:
/// the judgement is pure and harness-tested, the fetching is not and cannot be.
/// `scripts/thinglinks-selftest.sh` compiles `ThingLinks.swift` whole and never
/// sees this file.
///
/// ## Two fetches, because the two edges have different completeness
///
/// The wikilink half is fetched PER SOURCE and complete, which is the guarantee
/// `NoteLinks.backlinks` already gave Obsidian and which this must not regress:
/// a vault's oldest note is exactly as likely to link somewhere as its newest,
/// and a backlink that silently disappears past some window is worse than no
/// backlink panel. It stays affordable because only a vault-shaped bridge
/// populates `wikilinks` at all, so the fetch is scoped to those sources rather
/// than to the corpus.
///
/// The mention half is BOUNDED at the newest `mentionWindow` rows, and that is
/// a real ceiling rather than a shrug: finding "which of my things carries this
/// URL in its text" means reading text, and reading the text of a
/// ten-thousand-row archive on the main actor when a sheet opens is the
/// foreground-jank class this codebase already pays for elsewhere. The shelf's
/// title never claims completeness for the same reason — it says "Points at
/// this", not "everything that points at this".
enum ThingLinksSource {

    /// The sources whose rows carry `[[wikilinks]]`. One today; a second
    /// vault-shaped bridge joins the shelf by being named here, with no other
    /// change. Kept as a list rather than "any source" so the wikilink fetch
    /// stays a handful of source-scoped reads instead of a corpus walk.
    static let wikilinkSources = ["Obsidian"]

    /// How far back the mention scan reads. The same bound
    /// `RootShell.toolSnapshot` uses for the agent, on purpose: two different
    /// surfaces answering "what else names this link?" with two different
    /// horizons would disagree, and the person would have no way to see why.
    static let mentionWindow = 2000

    /// What points at `thing`, ready to draw. Empty is the common and healthy
    /// answer — most things are pointed at by nothing.
    @MainActor
    static func ties(for thing: Thing, context: ModelContext,
                     limit: Int = ThingLinks.cap) -> [ThingLinks.Tie] {
        guard thing.isLive else { return [] }
        let target = node(for: thing, wantsMentions: false)

        var corpus: [ThingLinks.Node] = []

        // Wikilinks in — complete, per source (see the type doc).
        let title = thing.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.count >= 2 {
            for source in wikilinkSources {
                let descriptor = FetchDescriptor<Thing>(
                    predicate: #Predicate<Thing> { $0.source == source })
                guard let rows = try? context.fetch(descriptor) else { continue }
                for row in rows where row.isLive && !row.wikilinks.isEmpty {
                    corpus.append(node(for: row, wantsMentions: false))
                }
            }
        }

        // Mentions of this thing's link — bounded (see the type doc). Skipped
        // entirely when this thing has no link to be mentioned, which is most
        // of the corpus and costs the fetch nothing.
        if let link = target.link, link.count >= 12, ThingLinks.hasPath(link) {
            var descriptor = FetchDescriptor<Thing>(
                sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
            descriptor.fetchLimit = mentionWindow
            let rows = (try? context.fetch(descriptor)) ?? []
            for row in rows where row.isLive {
                corpus.append(node(for: row, wantsMentions: true))
            }
        }

        guard !corpus.isEmpty else { return [] }
        return ThingLinks.pointingAt(target, in: corpus, limit: limit)
    }

    /// Resolves a tie back to the real row, at tap time.
    ///
    /// A tie carries an id and plain strings precisely so nothing model-shaped
    /// is held across the sheet's lifetime; the walk pays one equality fetch
    /// instead, and honestly returns nil for a row deleted since the shelf was
    /// drawn rather than trapping on it.
    @MainActor
    static func resolve(_ tie: ThingLinks.Tie, context: ModelContext) -> Thing? {
        guard let uuid = UUID(uuidString: tie.id) else { return nil }
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate<Thing> { $0.id == uuid })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first.flatMap { $0.isLive ? $0 : nil }
    }

    // MARK: - Flattening

    /// A live `Thing` as a `ThingLinks.Node`.
    ///
    /// `wantsMentions` is what keeps this affordable: extracting outgoing links
    /// means scanning a row's whole text, and only the mention pass needs it.
    /// The wikilink pass reads two small stored arrays and no text at all.
    @MainActor
    static func node(for thing: Thing, wantsMentions: Bool) -> ThingLinks.Node {
        ThingLinks.Node(
            id: thing.id.uuidString,
            title: thing.title,
            source: thing.source,
            when: thing.capturedAt,
            link: ThingLinks.canonicalLink(thing.content),
            mentions: wantsMentions ? mentions(of: thing) : [],
            wikilinks: thing.wikilinks,
            sourceRef: thing.sourceRef)
    }

    /// The canonical links a thing's own text names.
    ///
    /// Three fields, scanned SEPARATELY rather than concatenated: this runs per
    /// row over a 2,000-row window, `enrichedText` holds whole article bodies,
    /// and joining three strings before deciding whether any of them contains a
    /// URL would allocate a copy of the corpus's text to answer "no" for most
    /// of it. `canonicalLinks(in:)` early-outs on `http` per field instead.
    ///
    /// `content` is the body for most kinds and the permalink for a social row,
    /// `postText` is the full post that `title`'s 80-char clamp cut, and
    /// `enrichedText` is where an imported archive keeps the words nothing
    /// draws — which for X is exactly where a 2019 post's expanded t.co link
    /// lives, i.e. the case this edge exists to catch (prd §308's
    /// `CrossSourceEcho.writtenAbout`).
    ///
    /// `summary` is excluded: it is display copy a bridge wrote (a Trello card
    /// back, a Cursor run's own report), not something the person wrote.
    @MainActor
    static func mentions(of thing: Thing) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for field in [thing.content, thing.postText ?? "", thing.enrichedText ?? ""] {
            for link in ThingLinks.canonicalLinks(in: field) where seen.insert(link).inserted {
                out.append(link)
            }
        }
        return out
    }
}
