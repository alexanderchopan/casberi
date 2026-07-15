import Foundation

/// The source-neutral social surfaces (2026-07-14) — the shapes both the
/// Farcaster and Bluesky bridges answer, so the shared setup row and the
/// thing sheet's thread render from ONE path instead of a per-bridge fork.
/// When a third social bridge arrives it fills these in; nothing in the UI
/// learns its name.

/// One reply under a post/cast — the thing sheet's thread context.
struct SocialReply: Identifiable {
    let id: String
    let handle: String
    let avatarURL: String?
    let text: String
    let when: Date?
}

/// A post/cast's replies, dispatched by source. A thing that isn't a social
/// post (or a source with no thread reader) returns nothing.
enum SocialThread {
    @MainActor
    static func replies(for thing: Thing) async -> [SocialReply] {
        switch thing.source {
        case "Farcaster": return await FarcasterIngest.replies(for: thing)
        case "Bluesky":   return await BlueskyIngest.replies(for: thing)
        default:          return []
        }
    }
}

/// One "watch more" toggle on an account row (Likes / Mentions) — the
/// capability a bridge offers per account. Bluesky offers Mentions only
/// (likes need sign-in); Farcaster offers both.
struct SocialWatch: Identifiable, Equatable {
    enum Kind: String { case likes = "Likes", mentions = "Mentions" }
    let kind: Kind
    let on: Bool
    var id: String { kind.rawValue }
    var label: String { kind.rawValue }
}

/// A watched social account, rendered by the shared setup row: a face, a
/// display name over "@handle · bio", and the watch toggles the bridge
/// offers. `key` is what mutations use (the stored handle/username).
struct SocialAccount: Identifiable, Equatable {
    let key: String
    let title: String
    let subtitle: String
    let avatarURL: String?
    let watches: [SocialWatch]
    var id: String { key }

    /// "@handle · bio", or just "@handle" when there's no bio — the row's
    /// quiet second line, built the same way for every bridge.
    static func subtitle(handle: String, bio: String?) -> String {
        let b = (bio ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return b.isEmpty ? handle : "\(handle) · \(b)"
    }
}
