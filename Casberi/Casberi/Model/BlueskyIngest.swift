import Foundation
import Observation
import SwiftData

/// The Bluesky bridge (2026-07-07) — the sixth real connectable. The AT
/// Protocol's AppView API serves a person's own posts PUBLICLY, so v1 needs
/// only a handle: no password, no token, nothing to leak. Your posts land as
/// link things that open on bsky.app. (Likes require auth — they arrive with
/// an app-password sign-in later.)
@Observable
final class BlueskyStore {
    static let shared = BlueskyStore()
    private static let key = "bluesky.handle"

    var handle: String {
        didSet { UserDefaults.standard.set(handle, forKey: Self.key) }
    }

    private init() {
        handle = UserDefaults.standard.string(forKey: Self.key) ?? ""
    }

    /// "@name.bsky.social" and bare "name" both normalize.
    static func normalize(_ raw: String) -> String {
        var h = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for junk in ["https://", "http://", "bsky.app/profile/", "@"] {
            if h.hasPrefix(junk) { h.removeFirst(junk.count) }
        }
        if let slash = h.firstIndex(of: "/") { h = String(h[..<slash]) }
        if !h.isEmpty, !h.contains(".") { h += ".bsky.social" }
        return h
    }
}

enum BlueskyIngest {

    @MainActor private static var running = false

    /// Fetches the handle's recent posts from the public AppView and lands
    /// new ones as link things. Returns the new count, or nil when the
    /// handle can't be resolved.
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        let handle = BlueskyStore.shared.handle
        guard !handle.isEmpty, !running else { return handle.isEmpty ? nil : 0 }
        running = true
        defer { running = false }

        var comps = URLComponents(string: "https://public.api.bsky.app/xrpc/app.bsky.feed.getAuthorFeed")!
        comps.queryItems = [
            URLQueryItem(name: "actor", value: handle),
            URLQueryItem(name: "limit", value: "30"),
            URLQueryItem(name: "filter", value: "posts_no_replies"),
        ]
        guard let url = comps.url,
              let root = await IngestSupport.getJSON(url) as? [String: Any],
              let feed = root["feed"] as? [[String: Any]] else {
            return nil
        }

        let existing = IngestSupport.existingSourceRefs(context)
        let artless = IngestSupport.artlessThings(context, source: "Bluesky")
        var added = 0
        var backfilled = 0

        for entry in feed {
            guard let post = entry["post"] as? [String: Any],
                  let uri = post["uri"] as? String,
                  let record = post["record"] as? [String: Any],
                  let text = record["text"] as? String, !text.isEmpty,
                  let author = post["author"] as? [String: Any],
                  author["handle"] as? String == handle   // posts, not reposts of others
            else { continue }
            let ref = "bsky:\(uri)"
            let image = embedThumb(post)
            if existing.contains(ref) {
                if let image, let thing = artless[ref] {
                    thing.previewImageURL = image
                    backfilled += 1
                }
                continue
            }

            // at://did:…/app.bsky.feed.post/<rkey> → the web permalink.
            let rkey = uri.split(separator: "/").last.map(String.init) ?? ""
            let link = "https://bsky.app/profile/\(handle)/post/\(rkey)"
            let date = IngestSupport.isoDate(record["createdAt"])

            let thing = Thing(
                kind: .chat,
                title: IngestSupport.titleLine(text),
                content: link,
                source: "Bluesky",
                capturedAt: date ?? .now,
                sourceRef: ref
            )
            if let image { thing.previewImageURL = image }
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }
        if added > 0 || backfilled > 0 { try? context.save() }
        return added
    }

    /// A post's attached image, or an external card's thumb — the AppView
    /// hydrates ready-to-fetch CDN URLs on the post-level embed view. A
    /// text-only post returns nil and keeps the butterfly glyph: the image
    /// leads only when the post actually has one.
    private static func embedThumb(_ post: [String: Any]) -> String? {
        guard let embed = post["embed"] as? [String: Any] else { return nil }
        // Images attached directly, or nested under record-with-media.
        let media = (embed["media"] as? [String: Any]) ?? embed
        if let images = media["images"] as? [[String: Any]],
           let thumb = images.first?["thumb"] as? String { return thumb }
        if let external = media["external"] as? [String: Any],
           let thumb = external["thumb"] as? String { return thumb }
        return nil
    }
}
