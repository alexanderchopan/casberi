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
    private static let key = "bluesky.accounts"
    private static let legacyKey = "bluesky.handle"

    struct Account: Codable, Identifiable, Equatable {
        var id = UUID()
        var handle: String
    }

    /// The handles whose public posts land — more than one is a small
    /// following feed of people you care about, not just your own mirror
    /// (2026-07-10). Order is the person's; add/remove are theirs.
    var accounts: [Account] {
        didSet { persist() }
    }

    var connected: Bool { !accounts.isEmpty }
    var handles: [String] { accounts.map(\.handle) }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([Account].self, from: data) {
            accounts = saved
        } else if let legacy = UserDefaults.standard.string(forKey: Self.legacyKey),
                  !legacy.isEmpty {
            accounts = [Account(handle: legacy)]   // migrate the single handle
        } else {
            accounts = []
        }
    }

    /// Adds a handle, deduped. Returns false if it was empty or already there.
    @discardableResult
    func add(_ raw: String) -> Bool {
        let h = Self.normalize(raw)
        guard !h.isEmpty, !accounts.contains(where: { $0.handle == h }) else { return false }
        accounts.append(Account(handle: h))
        return true
    }

    func remove(_ handle: String) { accounts.removeAll { $0.handle == handle } }
    func removeAll() { accounts = [] }

    /// The name a post's row shows when MORE THAN ONE account is watched —
    /// so two watched people don't read as one indistinguishable stream.
    /// One account: nil, every row is obviously them (same rule as a Wallet
    /// label). ".bsky.social" comes off — the name is what the person knows.
    func rowLabel(for handle: String?) -> String? {
        guard let handle, accounts.count > 1,
              accounts.contains(where: { $0.handle == handle }) else { return nil }
        let short = handle.hasSuffix(".bsky.social")
            ? String(handle.dropLast(".bsky.social".count)) : handle
        return "@\(short)"
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
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
        let handles = BlueskyStore.shared.handles
        guard !handles.isEmpty, !running else { return handles.isEmpty ? nil : 0 }
        running = true
        defer { running = false }

        let existing = IngestSupport.existingSourceRefs(context)
        let landed = IngestSupport.thingsByRef(context, source: "Bluesky")
        let backfill = ArtlessBackfill(context, source: "Bluesky")
        var added = 0
        var touched = false
        var anyResolved = false

        for handle in handles {
            var comps = URLComponents(string: "https://public.api.bsky.app/xrpc/app.bsky.feed.getAuthorFeed")!
            comps.queryItems = [
                URLQueryItem(name: "actor", value: handle),
                URLQueryItem(name: "limit", value: "30"),
                URLQueryItem(name: "filter", value: "posts_no_replies"),
            ]
            guard let url = comps.url,
                  let root = await IngestSupport.getJSON(url) as? [String: Any],
                  let feed = root["feed"] as? [[String: Any]] else {
                continue   // one bad handle doesn't sink the others
            }
            anyResolved = true

            // The account's avatar (same for every one of its posts) — backfill
            // it onto EVERY existing post of theirs that predates the field, so
            // the whole feed wears faces, not just posts landed since (2026-07-10).
            let accountAvatar = IngestSupport.imageURL(
                (feed.first?["post"] as? [String: Any])
                    .flatMap { $0["author"] as? [String: Any] }?["avatar"] as? String)
            if let accountAvatar {
                for t in landed.values where t.authorAvatarURL == nil
                    && t.content.contains("/profile/\(handle)/") {
                    t.authorHandle = handle
                    t.authorAvatarURL = accountAvatar
                    touched = true
                }
            }

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
                    backfill.patch(ref, image: image)
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
                thing.previewImageURL = IngestSupport.imageURL(image)
                thing.authorHandle = handle
                thing.authorAvatarURL = IngestSupport.imageURL(author["avatar"] as? String)
                context.insert(thing)
                SpotlightIndex.index([thing])
                added += 1
            }
        }
        // Every handle failing to resolve is the "couldn't find that" signal;
        // one landing means the connection is good.
        guard anyResolved else { return nil }
        if added > 0 || backfill.any || touched { try? context.save() }
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
