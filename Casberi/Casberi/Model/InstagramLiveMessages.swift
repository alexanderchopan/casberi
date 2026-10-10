import Foundation

/// Instagram's direct messages, read off the live session's own inbox (prd
/// §1244) — `/api/v1/direct_v2/inbox/`, the call instagram.com's Messages
/// page makes on open, with the cookies and headers the notifications read
/// already carries (`InstagramLive.headers`). The PURE half.
///
/// **What it reads, and what it does not.** The primary inbox only: message
/// requests are `pending_inbox`, a different call this app never makes. An
/// end-to-end encrypted chat is not in this response. Reading never marks a
/// thread seen — that is a POST per item this app never sends.
///
/// **Meta flags harder than X** (`InstagramLive`'s header): this read rides
/// the same ten-minute throttle as the notifications, one more request per
/// pass, and a checkpoint keeps the cookies.
///
/// **UNMEASURED**: authored against the publicly documented shape of the web
/// inbox, with no Instagram session on any build host. Every path fails to
/// nil or skips; `-igLiveProbe YES` prints the shape (keys and counts, never a
/// message) in one launch.
enum InstagramLiveMessages {
    /// Its own namespace beside `ig-live:notif:`, registered in
    /// `Corpus.liveRefPrefixesBySource` under "Instagram". Not the export's
    /// `instagram:dm:`, which "Remove import" removes.
    static let refPrefix = "ig-live:dm:"

    /// Twenty threads, ten messages each — one page, never paged. The export
    /// is the bulk door; this is the live one and carries what is recent.
    static let threadLimit = 20
    static let messagesPerThread = 10

    static var path: String {
        "/direct_v2/inbox/?persistentBadging=true&folder=&limit=\(threadLimit)&thread_message_limit=\(messagesPerThread)"
    }

    static func threads(_ json: Any?) -> [[String: Any]]? {
        ((json as? [String: Any])?["inbox"] as? [String: Any])?["threads"] as? [[String: Any]]
    }

    /// The signed-in account's id as the inbox states it, else nil (the
    /// caller falls back to the `ds_user_id` cookie).
    static func viewerID(_ json: Any?) -> String? {
        let viewer = (json as? [String: Any])?["viewer"] as? [String: Any]
        return LiveMessages.idString(viewer?["pk_id"]) ?? LiveMessages.idString(viewer?["pk"])
    }

    struct User: Equatable {
        var id: String
        var name: String?
        var handle: String?
        var avatar: String?
        var label: String? { name ?? handle.map { "@" + $0 } }
    }

    static func user(_ any: [String: Any]) -> User? {
        guard let id = LiveMessages.idString(any["pk_id"]) ?? LiveMessages.idString(any["pk"])
        else { return nil }
        return User(
            id: id,
            name: (any["full_name"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            handle: (any["username"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            avatar: (any["profile_pic_url"] as? String).flatMap { $0.isEmpty ? nil : $0 })
    }

    /// Every thread with at least one readable message, newest first. nil
    /// when the response is not an inbox at all.
    static func conversations(_ json: Any?, me: String?) -> [LiveConversation]? {
        guard let threads = threads(json) else { return nil }
        let viewer = viewerID(json) ?? me
        var out: [LiveConversation] = []
        for thread in threads {
            guard let id = LiveMessages.idString(thread["thread_id"]) else { continue }
            // `users` is everyone BUT you on the web inbox; filtered anyway,
            // so a shape that includes you never titles a chat with yourself.
            let users = ((thread["users"] as? [[String: Any]]) ?? [])
                .compactMap(user).filter { $0.id != viewer }
            var byID: [String: User] = [:]
            for u in users { byID[u.id] = u }
            let isGroup = (thread["is_group"] as? Bool) ?? (users.count > 1)

            var lines: [LiveConversation.Line] = []
            var seen = Set<String>()
            for item in (thread["items"] as? [[String: Any]]) ?? [] {
                guard let itemID = LiveMessages.idString(item["item_id"]),
                      seen.insert(itemID).inserted,
                      let at = LiveMessages.date(epoch: item["timestamp"]),
                      let words = text(item)
                else { continue }
                let sender = LiveMessages.idString(item["user_id"])
                lines.append(.init(
                    id: itemID, at: at,
                    text: LiveMessages.line(
                        sender: sender.flatMap { byID[$0]?.label },
                        isMe: (viewer != nil && sender == viewer) || (item["is_sent_by_viewer"] as? Bool) == true,
                        text: words)))
            }
            guard !lines.isEmpty else { continue }

            let threadTitle = (thread["thread_title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let title = isGroup
                ? threadTitle.map { String(localized: "Messages in \($0)") }
                    ?? LiveMessages.title(names: users.compactMap(\.label))
                : LiveMessages.title(names: [users.first?.label ?? threadTitle ?? ""])
            let other = isGroup ? nil : users.first
            out.append(LiveConversation(
                id: id,
                title: title,
                handle: other?.handle,
                avatar: other?.avatar,
                isGroup: isGroup,
                lines: lines.sorted { $0.at < $1.at }))
        }
        return out.sorted { ($0.lines.last?.at ?? .distantPast) > ($1.lines.last?.at ?? .distantPast) }
    }

    /// An item's words. Text and links carry their own; a shared post, a
    /// picture or a voice note is named as what it is, because a transcript
    /// that skips every reel somebody sent reads as half a conversation. An
    /// item type this does not know is skipped, never guessed.
    static func text(_ item: [String: Any]) -> String? {
        let type = item["item_type"] as? String
        func words(_ s: Any?) -> String? {
            (s as? String).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { $0.isEmpty ? nil : $0 }
        }
        switch type {
        case "text":
            return words(item["text"])
        case "link":
            return words((item["link"] as? [String: Any])?["text"]) ?? words(item["text"])
        case "media_share", "xma_media_share", "felix_share":
            return String(localized: "Shared a post")
        case "clip", "xma_clip":
            return String(localized: "Shared a reel")
        case "story_share", "xma_story_share":
            return String(localized: "Shared a story")
        case "reel_share":
            return words((item["reel_share"] as? [String: Any])?["text"])
                ?? String(localized: "Replied to a story")
        case "media", "raven_media", "visual_media":
            let media = (item["media"] as? [String: Any])
                ?? ((item["visual_media"] as? [String: Any])?["media"] as? [String: Any])
            return (media?["media_type"] as? Int) == 2
                ? String(localized: "Video") : String(localized: "Photo")
        case "voice_media":
            return String(localized: "Voice message")
        case "animated_media":
            return String(localized: "GIF")
        case "like":
            return "❤️"
        default:
            return nil
        }
    }
}
