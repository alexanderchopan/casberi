import Foundation
import SwiftData

/// A link whose enrichment never landed, asked again (2026-09-22).
///
/// `LinkTitle.enrich` runs ONCE, detached, at the moment a link lands. Offline,
/// a slow page past its 8-second cap, a phone locked mid-fetch — any of those
/// and the row wore its URL as a title for good, because nothing ever asked
/// again. And every link named before its picture was kept (the `og:image` a
/// page declares was read on every fetch and thrown away unless the page was a
/// product) has no face either. This pass is the "again", for both.
///
/// **WHICH ROWS: exactly the ones `enrich` is already called on, and no
/// others.** A link you dropped, shared or saved through Shortcuts, and the
/// article a Farcaster or Bluesky post carries — the four callers. A retry is
/// the same request to the same page, so it widens nothing about what the app
/// reaches (the "Saved links" entry in `NetworkReach`); a new source here would
/// be a new reach and needs `FeedArticleText`'s fairness rule first. Imports
/// are left out on purpose: Instagram's and TikTok's rows keep their own
/// faces and their own passes (`InstagramImport`, `TikTokImport.fetchFaces`).
///
/// BOUNDED, PACED, LEDGERED — `FeedArticleText`'s discipline, for its reason:
/// a page with no title and no picture is not going to grow one, and asking
/// it every ten minutes forever is rude. A row is tried at most `maxAttempts`
/// times, only inside `window`, `perPass` rows per foreground.
enum LinkHeal {

    /// The sources whose links `LinkTitle.enrich` is called on at landing.
    /// "Shortcuts" is the intent's default source; a person who names another
    /// one in the Shortcut is not reached, which is the conservative miss.
    static let sources: Set<String> = ["You", "Shortcuts", "Farcaster", "Bluesky"]

    static let perPass = 6
    static let pace: Duration = .milliseconds(1200)
    static let window: TimeInterval = 30 * 86400

    private static let maxAttempts = 2
    private static let ledgerKey = "link.heal.attempts"
    private static let ledgerCap = 2000

    struct Report {
        var considered = 0
        var healed = 0
        var missed = 0
    }

    /// Whether the row still lacks what enrichment would give it. Not
    /// main-actor: `LinkScout` asks it off main.
    static func wants(_ thing: Thing) -> Bool {
        guard thing.isLive, thing.kind == .link,
              let url = LinkTitle.address(of: thing),
              url.scheme?.hasPrefix("http") == true else { return false }
        return LinkTitle.looksUnnamed(thing, url: url)
            || (thing.previewImageURL ?? "").isEmpty
    }

    @MainActor private static var running = false

    @discardableResult
    @MainActor
    static func sweep(context: ModelContext, limit: Int? = nil, trace: Bool = false) async -> Report {
        var report = Report()
        guard !running else { return report }
        running = true
        defer { running = false }

        var attempts = (UserDefaults.standard.dictionary(forKey: ledgerKey) as? [String: Int]) ?? [:]
        // The scan runs OFF MAIN (prd §878's lesson, the same week): four
        // sources' recent rows — every Farcaster and Bluesky post of the
        // month among them — materialised on the main context every
        // foreground is exactly the cost `ArticleScout` was built to remove.
        // Only ids cross back.
        guard let found = await LinkScout.scan(window: window) else { return report }
        let pending = found.filter { (attempts[$0.key] ?? 0) < maxAttempts }
        report.considered = pending.count

        for candidate in pending.prefix(limit ?? perPass) {
            // Every write below lands on the main actor; never under a finger.
            await GestureGate.idle()
            // Re-found on THIS context by id (corollary 6): the scout's row
            // belonged to its own context and is gone.
            guard let thing = context.model(for: candidate.id) as? Thing,
                  thing.isLive, wants(thing) else { continue }
            let key = candidate.key
            let needsName = LinkTitle.address(of: thing).map { LinkTitle.looksUnnamed(thing, url: $0) } ?? false
            if needsName {
                await LinkTitle.enrich(thing, context: context)
            } else {
                await LinkTitle.picture(thing, context: context)
            }
            // `enrich`/`picture` guard their own awaits; this one is ours.
            guard thing.isLive else { continue }
            if wants(thing) {
                attempts[key] = (attempts[key] ?? 0) + 1
                report.missed += 1
                if trace { NSLog("linkHeal| MISS | %@ | %@", thing.source, thing.content) }
            } else {
                attempts.removeValue(forKey: key)
                report.healed += 1
                if trace { NSLog("linkHeal| OK | %@ | %@", thing.source, thing.title) }
            }
            try? await Task.sleep(for: pace)
        }

        if attempts.count > ledgerCap {
            attempts = Dictionary(uniqueKeysWithValues: Array(attempts).suffix(ledgerCap))
        }
        UserDefaults.standard.set(attempts, forKey: ledgerKey)
        return report
    }
}

/// The scan half of `LinkHeal`, on its own context against the shared
/// container — `ArticleScout`'s shape (prd §878), for its reason.
@ModelActor
actor LinkScout {
    struct Candidate: Sendable {
        let id: PersistentIdentifier
        /// The ledger key: the row's own id, stable across launches.
        let key: String
    }

    static func scan(window: TimeInterval) async -> [Candidate]? {
        guard let container = SharedStore.live else { return nil }
        return await LinkScout(modelContainer: container).perform(window: window)
    }

    private func perform(window: TimeInterval) -> [Candidate] {
        let cutoff = Date.now.addingTimeInterval(-window)
        var rows: [(at: Date, candidate: Candidate)] = []
        // One fetch per source: a plain string predicate pushes down to SQL.
        // The kind test runs in memory — `#Predicate` cannot compare a
        // Codable enum.
        for source in LinkHeal.sources.sorted() {
            let descriptor = FetchDescriptor<Thing>(
                predicate: #Predicate<Thing> { $0.source == source && $0.capturedAt > cutoff },
                sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
            for thing in (try? modelContext.fetch(descriptor)) ?? [] where LinkHeal.wants(thing) {
                rows.append((thing.capturedAt,
                             Candidate(id: thing.persistentModelID, key: thing.id.uuidString)))
            }
        }
        return rows.sorted { $0.at > $1.at }.map(\.candidate)
    }
}
