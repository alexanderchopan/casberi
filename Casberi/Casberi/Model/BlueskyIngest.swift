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
        if h.hasPrefix("@") { h.removeFirst() }
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
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let feed = root["feed"] as? [[String: Any]] else {
            return nil
        }

        let existing = Set(((try? context.fetch(FetchDescriptor<Thing>())) ?? [])
            .compactMap(\.sourceRef))
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]
        var added = 0

        for entry in feed {
            guard let post = entry["post"] as? [String: Any],
                  let uri = post["uri"] as? String,
                  let record = post["record"] as? [String: Any],
                  let text = record["text"] as? String, !text.isEmpty,
                  let author = post["author"] as? [String: Any],
                  author["handle"] as? String == handle   // posts, not reposts of others
            else { continue }
            let ref = "bsky:\(uri)"
            guard !existing.contains(ref) else { continue }

            // at://did:…/app.bsky.feed.post/<rkey> → the web permalink.
            let rkey = uri.split(separator: "/").last.map(String.init) ?? ""
            let link = "https://bsky.app/profile/\(handle)/post/\(rkey)"
            let title = text.count > 80
                ? String(text.prefix(80)) + "…"
                : text
            let date = (record["createdAt"] as? String)
                .flatMap { iso.date(from: $0) ?? isoPlain.date(from: $0) }

            let thing = Thing(
                kind: .chat,
                title: title.replacingOccurrences(of: "\n", with: " "),
                content: link,
                source: "Bluesky",
                capturedAt: date ?? .now,
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
