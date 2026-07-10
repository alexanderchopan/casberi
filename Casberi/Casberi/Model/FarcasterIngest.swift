import Foundation
import Observation
import SwiftData

/// The Farcaster bridge (2026-07-07) — like Bluesky, an open protocol whose
/// posts are public: a username alone connects it. The Farcaster team's own
/// public Snapchain node serves name→fid and a person's casts with no key
/// and no password. Casts land as chat things linking to farcaster.xyz.
@Observable
final class FarcasterStore {
    static let shared = FarcasterStore()
    private static let nameKey = "farcaster.username"
    private static let fidKey = "farcaster.fid"

    var username: String {
        didSet {
            UserDefaults.standard.set(username, forKey: Self.nameKey)
            if username != oldValue { fid = 0 }   // re-resolve on change
        }
    }
    /// Resolved once per username, then cached.
    var fid: Int {
        didSet { UserDefaults.standard.set(fid, forKey: Self.fidKey) }
    }

    private init() {
        username = UserDefaults.standard.string(forKey: Self.nameKey) ?? ""
        fid = UserDefaults.standard.integer(forKey: Self.fidKey)
    }

    /// "@dwr" and "dwr.eth" both normalize to the registered name.
    static func normalize(_ raw: String) -> String {
        var n = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for junk in ["https://", "http://", "www.", "farcaster.xyz/", "warpcast.com/", "@"] {
            if n.hasPrefix(junk) { n.removeFirst(junk.count) }
        }
        if let slash = n.firstIndex(of: "/") { n = String(n[..<slash]) }
        return n
    }
}

enum FarcasterIngest {

    private static let node = "https://snap.farcaster.xyz:3381"
    /// Snapchain timestamps count seconds from the Farcaster epoch.
    private static let epoch = Date(timeIntervalSince1970: 1_609_459_200)

    @MainActor private static var running = false

    /// Resolves the username (once), fetches recent casts, lands new ones as
    /// chat things. Returns the new count, or nil when the name can't be
    /// resolved.
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        let store = FarcasterStore.shared
        guard !store.username.isEmpty, !running else {
            return store.username.isEmpty ? nil : 0
        }
        running = true
        defer { running = false }

        if store.fid == 0 {
            guard let proof = await IngestSupport.getJSON(
                "\(node)/v1/userNameProofByName?name=\(store.username)") as? [String: Any],
                  let fid = proof["fid"] as? Int else { return nil }
            store.fid = fid
        }

        guard let root = await IngestSupport.getJSON(
            "\(node)/v1/castsByFid?fid=\(store.fid)&pageSize=30&reverse=true") as? [String: Any],
              let messages = root["messages"] as? [[String: Any]] else { return nil }

        let existing = IngestSupport.existingSourceRefs(context)
        let artless = IngestSupport.artlessThings(context, source: "Farcaster")
        var added = 0
        var backfilled = 0

        for message in messages {
            guard let hash = message["hash"] as? String,
                  let data = message["data"] as? [String: Any],
                  let body = data["castAddBody"] as? [String: Any],
                  let text = body["text"] as? String, !text.isEmpty,
                  body["parentCastId"] is NSNull || body["parentCastId"] == nil  // casts, not replies
            else { continue }
            let ref = "fc:\(hash)"
            let image = imageEmbed(body)
            if existing.contains(ref) {
                if let image, let thing = artless[ref] {
                    thing.previewImageURL = image
                    backfilled += 1
                }
                continue
            }

            // farcaster.xyz's canonical short link: the name + hash prefix.
            let short = String(hash.prefix(10))
            let when = (data["timestamp"] as? Double).map { epoch.addingTimeInterval($0) }

            let thing = Thing(
                kind: .chat,
                title: IngestSupport.titleLine(text),
                content: "https://farcaster.xyz/\(FarcasterStore.shared.username)/\(short)",
                source: "Farcaster",
                capturedAt: when ?? .now,
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

    /// A cast's first image embed. Snapchain serves raw protocol data — no
    /// hydrated thumbs — so only URLs that are plainly images qualify:
    /// Farcaster's own image CDN, or a file extension that says so. A cast
    /// embedding an article link keeps the chat glyph.
    private static func imageEmbed(_ body: [String: Any]) -> String? {
        for embed in (body["embeds"] as? [[String: Any]]) ?? [] {
            guard let url = embed["url"] as? String else { continue }
            let lower = url.lowercased()
            if lower.contains("imagedelivery.net")
                || [".jpg", ".jpeg", ".png", ".gif", ".webp"].contains(where: lower.hasSuffix) {
                return url
            }
        }
        return nil
    }
}
