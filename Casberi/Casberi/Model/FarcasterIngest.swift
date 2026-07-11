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
    private static let key = "farcaster.accounts"
    private static let legacyNameKey = "farcaster.username"
    private static let legacyFidKey = "farcaster.fid"

    struct Account: Codable, Identifiable, Equatable {
        var id = UUID()
        var username: String
        /// Resolved once per username, then cached (name→fid costs a request).
        var fid: Int = 0
    }

    /// The usernames whose public casts land — more than one is a small
    /// following feed, not just your own mirror (2026-07-10).
    var accounts: [Account] {
        didSet { persist() }
    }

    var connected: Bool { !accounts.isEmpty }
    var usernames: [String] { accounts.map(\.username) }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([Account].self, from: data) {
            accounts = saved
        } else if let legacy = UserDefaults.standard.string(forKey: Self.legacyNameKey),
                  !legacy.isEmpty {
            let fid = UserDefaults.standard.integer(forKey: Self.legacyFidKey)
            accounts = [Account(username: legacy, fid: fid)]   // migrate the single name
        } else {
            accounts = []
        }
    }

    @discardableResult
    func add(_ raw: String) -> Bool {
        let n = Self.normalize(raw)
        guard !n.isEmpty, !accounts.contains(where: { $0.username == n }) else { return false }
        accounts.append(Account(username: n))
        return true
    }

    func remove(_ username: String) { accounts.removeAll { $0.username == username } }
    func removeAll() { accounts = [] }

    /// Adds a username together with an already-known fid — search resolves
    /// both in one call, so this skips the first sync's separate name→fid
    /// lookup for it (the fid-caching invariant lives here, not in a caller).
    @discardableResult
    func add(_ raw: String, fid: Int) -> Bool {
        let added = add(raw)
        setFid(fid, for: Self.normalize(raw))
        return added
    }

    /// Caches an fid once resolved, so the name→fid lookup runs once per name.
    func setFid(_ fid: Int, for username: String) {
        guard let i = accounts.firstIndex(where: { $0.username == username }) else { return }
        accounts[i].fid = fid
    }

    /// The name a cast's row shows when MORE THAN ONE account is watched
    /// (same rule as Bluesky/Wallet). One account: nil.
    func rowLabel(for username: String?) -> String? {
        guard let username, accounts.count > 1,
              accounts.contains(where: { $0.username == username }) else { return nil }
        return "@\(username)"
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
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
        guard store.connected, !running else {
            return store.connected ? 0 : nil
        }
        running = true
        defer { running = false }

        let existing = IngestSupport.existingSourceRefs(context)
        let landed = IngestSupport.thingsByRef(context, source: "Farcaster")
        let backfill = ArtlessBackfill(context, source: "Farcaster")
        var added = 0
        var touched = false
        var anyResolved = false

        for account in store.accounts {
            var fid = account.fid
            if fid == 0 {
                guard let proof = await IngestSupport.getJSON(
                    "\(node)/v1/userNameProofByName?name=\(account.username)") as? [String: Any],
                      let resolved = proof["fid"] as? Int else { continue }
                fid = resolved
                store.setFid(fid, for: account.username)
            }

            guard let root = await IngestSupport.getJSON(
                "\(node)/v1/castsByFid?fid=\(fid)&pageSize=30&reverse=true") as? [String: Any],
                  let messages = root["messages"] as? [[String: Any]] else { continue }
            anyResolved = true

            // The avatar is a per-account lookup, not per-cast — fetch it once.
            let avatar = await avatarURL(fid: fid)
            // Backfill it onto EVERY existing cast of theirs that predates the
            // field, so the whole feed wears faces, not just casts landed since
            // (2026-07-10, user: they expected the author's avatar).
            if let avatar {
                for t in landed.values where t.authorAvatarURL == nil
                    && t.content.contains("/\(account.username)/") {
                    t.authorHandle = account.username
                    t.authorAvatarURL = avatar
                    touched = true
                }
            }

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
                    backfill.patch(ref, image: image)
                    continue
                }

                // farcaster.xyz's canonical short link: the name + hash prefix.
                let short = String(hash.prefix(10))
                let when = (data["timestamp"] as? Double).map { epoch.addingTimeInterval($0) }

                let thing = Thing(
                    kind: .chat,
                    title: IngestSupport.titleLine(text),
                    content: "https://farcaster.xyz/\(account.username)/\(short)",
                    source: "Farcaster",
                    capturedAt: when ?? .now,
                    sourceRef: ref
                )
                thing.previewImageURL = IngestSupport.imageURL(image)
                thing.authorHandle = account.username
                thing.authorAvatarURL = avatar
                context.insert(thing)
                SpotlightIndex.index([thing])
                added += 1
            }
        }
        guard anyResolved else { return nil }
        if added > 0 || backfill.any || touched { try? context.save() }
        return added
    }

    /// A user's profile picture URL from the hub — one request per account,
    /// cached onto each cast's row for the >1 case. The endpoint ignores the
    /// user_data_type filter and returns EVERY profile field in a `messages`
    /// array, so we scan it for the PFP entry (verified 2026-07-10).
    private static func avatarURL(fid: Int) async -> String? {
        guard let root = await IngestSupport.getJSON(
            "\(node)/v1/userDataByFid?fid=\(fid)") as? [String: Any],
              let messages = root["messages"] as? [[String: Any]] else { return nil }
        for message in messages {
            guard let data = message["data"] as? [String: Any],
                  let body = data["userDataBody"] as? [String: Any],
                  body["type"] as? String == "USER_DATA_TYPE_PFP",
                  let value = body["value"] as? String else { continue }
            return IngestSupport.imageURL(value)
        }
        return nil
    }

    /// A cast's first image embed. Snapchain serves raw protocol data — no
    /// hydrated thumbs — so only URLs that are plainly images qualify:
    /// Farcaster's own image CDN, or a file extension that says so. A cast
    /// embedding an article link keeps the chat glyph.
    private static func imageEmbed(_ body: [String: Any]) -> String? {
        for embed in (body["embeds"] as? [[String: Any]]) ?? [] {
            guard let url = embed["url"] as? String else { continue }
            let lower = url.lowercased()
            // Extension check runs on the PATH — a query string
            // ("photo.jpg?maxwidth=640") defeated hasSuffix on the raw URL.
            let path = URL(string: lower)?.path ?? lower
            if lower.contains("imagedelivery.net")
                || [".jpg", ".jpeg", ".png", ".gif", ".webp"].contains(where: path.hasSuffix) {
                return url
            }
        }
        return nil
    }
}
