import Foundation
import Observation
import SwiftData

/// The Pinterest bridge (2026-07-09) — handle-only, like Bluesky: Pinterest
/// still publishes a public RSS feed per user (pinterest.com/<name>/feed.rss),
/// so your recent public pins land as link things with just a username. No
/// OAuth, no developer-app review, no token — the official API's
/// confidential-client dance doesn't fit a serverless iPhone, and the feed
/// carries the same content for a personal corpus. Public boards only, by
/// construction.
@Observable
final class PinterestStore {
    static let shared = PinterestStore()
    private static let key = "pinterest.username"

    var username: String {
        didSet { UserDefaults.standard.set(username, forKey: Self.key) }
    }

    private init() {
        username = UserDefaults.standard.string(forKey: Self.key) ?? ""
    }

    /// "pinterest.com/name", "@name", and bare "name" all normalize.
    static func normalize(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for junk in ["https://", "http://", "www.", "pinterest.com/", "@"] {
            if name.hasPrefix(junk) { name.removeFirst(junk.count) }
        }
        if let slash = name.firstIndex(of: "/") { name = String(name[..<slash]) }
        return name
    }
}

enum PinterestIngest {

    @MainActor private static var running = false

    /// Fetches the username's public feed and lands new pins as link things.
    /// Returns the new count, or nil when the feed can't be read (bad
    /// username / offline — Pinterest answers a 404 page the parser yields
    /// nothing from).
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        let username = PinterestStore.shared.username
        guard !username.isEmpty, !running else { return username.isEmpty ? nil : 0 }
        running = true
        defer { running = false }

        guard let url = URL(string: "https://www.pinterest.com/\(username)/feed.rss"),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        let parsed = FeedParser.parse(data)
        // A wrong username serves an HTML page, not a feed — nothing parses.
        guard !parsed.items.isEmpty || !parsed.title.isEmpty else { return nil }

        let existing = IngestSupport.existingSourceRefs(context)
        var added = 0

        for item in parsed.items.prefix(25) {
            guard !item.link.isEmpty else { continue }
            let ref = "pinterest:\(item.guid.isEmpty ? item.link : item.guid)"
            guard !existing.contains(ref) else { continue }
            let thing = Thing(
                kind: .link,
                // Pins are often untitled — an empty row title reads broken.
                title: item.title.isEmpty ? "Pin" : item.title,
                content: item.link,
                source: "Pinterest",
                capturedAt: item.date ?? .now,
                sourceRef: ref
            )
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }
        if added > 0 { try? context.save() }
        return added
    }
}
