import Foundation

/// X's direct messages, read off the live session's own inbox (prd §1244) —
/// `/i/api/1.1/dm/inbox_initial_state.json`, the call x.com's Messages page
/// makes on open, with the same cookies, CSRF header and public bearer the
/// notifications read already carries (`XLiveNotifications`). The PURE half.
///
/// **What it reads, and what it does not.** The inbox's own folder only: a
/// conversation X marks `trusted: false` is a message REQUEST and is skipped,
/// because a request is a stranger asking, not a conversation you are in. An
/// encrypted chat is not in this response at all. Reading never marks
/// anything read — that is a separate POST (`mark_read.json`) this app never
/// sends.
///
/// **UNMEASURED** (`XLiveNotifications`' own sense of the word): authored
/// against the publicly documented shape of the response, with no X session
/// on any build host. Every path fails to nil or skips, so a drift lands
/// nothing rather than something wrong, and `-xLiveProbe YES` prints the
/// shape (keys and counts, never a message) in one launch.
enum XLiveMessages {
    /// Its own namespace beside `x-live:notif:`, and registered in
    /// `Corpus.liveRefPrefixesBySource` under "X" — so a conversation is live
    /// in All and "Remove import" steps over it. Not the archive's `x:dm:`:
    /// that row is the export's, and "Remove import" removes it.
    static let refPrefix = "x-live:dm:"

    static func url() -> URL? {
        var comps = URLComponents(string: "https://x.com/i/api/1.1/dm/inbox_initial_state.json")
        // The query x.com's own page sends, trimmed to what changes the
        // answer: groups included, low-quality filtering on, no user lookup
        // beyond the participants the response already carries.
        comps?.queryItems = [
            URLQueryItem(name: "nsfw_filtering_enabled", value: "false"),
            URLQueryItem(name: "filter_low_quality", value: "true"),
            URLQueryItem(name: "include_quality", value: "all"),
            URLQueryItem(name: "include_groups", value: "true"),
            URLQueryItem(name: "include_inbox_timelines", value: "true"),
            URLQueryItem(name: "include_ext_media_color", value: "false"),
            URLQueryItem(name: "supports_reactions", value: "true"),
            URLQueryItem(name: "dm_users", value: "false"),
            URLQueryItem(name: "include_conversation_info", value: "true"),
            URLQueryItem(name: "ext", value: "mediaColor"),
        ]
        return comps?.url
    }

    /// The `twid` cookie's user id — `u%3D<id>`, or `u=<id>` once decoded.
    static func userID(fromTwid twid: String) -> String? {
        let decoded = twid.removingPercentEncoding ?? twid
        let trimmed = decoded.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        guard trimmed.hasPrefix("u=") else { return nil }
        let id = String(trimmed.dropFirst(2))
        return !id.isEmpty && id.allSatisfy(\.isNumber) ? id : nil
    }

    static func state(_ json: Any?) -> [String: Any]? {
        (json as? [String: Any])?["inbox_initial_state"] as? [String: Any]
    }

    /// Who is signed in, when the cookie did not say: the one id every
    /// conversation shares. nil when that is not exactly one id — a single
    /// one-to-one names two people and either could be you.
    static func viewerID(_ json: Any?) -> String? {
        guard let conversations = state(json)?["conversations"] as? [String: Any],
              !conversations.isEmpty else { return nil }
        var common: Set<String>?
        for case let conversation as [String: Any] in conversations.values {
            let ids = Set(((conversation["participants"] as? [[String: Any]]) ?? [])
                .compactMap { LiveMessages.idString($0["user_id"]) })
            guard !ids.isEmpty else { continue }
            common = common.map { $0.intersection(ids) } ?? ids
        }
        guard let common, common.count == 1 else { return nil }
        return common.first
    }

    struct User: Equatable {
        var name: String?
        var handle: String?
        var avatar: String?
        /// The display name, else the handle with its @.
        var label: String? { name ?? handle.map { "@" + $0 } }
    }

    static func users(_ state: [String: Any]) -> [String: User] {
        var out: [String: User] = [:]
        for (id, value) in (state["users"] as? [String: Any]) ?? [:] {
            guard let user = value as? [String: Any] else { continue }
            out[id] = User(
                name: (user["name"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                handle: (user["screen_name"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                // X's own `_normal` is 48px; `_400x400` is its named size, the
                // notifications read's substitution.
                avatar: (user["profile_image_url_https"] as? String).flatMap {
                    $0.isEmpty ? nil : $0.replacingOccurrences(of: "_normal.", with: "_400x400.")
                })
        }
        return out
    }

    /// Every conversation in the inbox with at least one readable message,
    /// newest first. nil when the response is not an inbox at all.
    ///
    /// `me` is the signed-in account's id (the `twid` cookie, else
    /// `viewerID`). Without it the lines still land, each under its sender's
    /// name, and the title names everybody.
    static func conversations(_ json: Any?, me: String?) -> [LiveConversation]? {
        guard let state = state(json),
              let entries = state["entries"] as? [[String: Any]] else { return nil }
        let users = users(state)
        let meta = (state["conversations"] as? [String: Any]) ?? [:]

        var linesByConversation: [String: [LiveConversation.Line]] = [:]
        var seen = Set<String>()
        for entry in entries {
            guard let message = entry["message"] as? [String: Any],
                  let conversationID = message["conversation_id"] as? String, !conversationID.isEmpty,
                  let data = message["message_data"] as? [String: Any],
                  let id = LiveMessages.idString(data["id"]) ?? LiveMessages.idString(message["id"]),
                  seen.insert(id).inserted,
                  let at = LiveMessages.date(epoch: data["time"] ?? message["time"]),
                  let words = text(data)
            else { continue }
            let sender = LiveMessages.idString(data["sender_id"])
            let line = LiveMessages.line(
                sender: sender.flatMap { users[$0]?.label },
                isMe: me != nil && sender == me,
                text: words)
            linesByConversation[conversationID, default: []].append(.init(id: id, at: at, text: line))
        }

        var out: [LiveConversation] = []
        for (conversationID, lines) in linesByConversation {
            let info = meta[conversationID] as? [String: Any]
            // A message request: a stranger asking, not a conversation you
            // are in. Only an explicit `false` — a missing flag is the inbox.
            if (info?["trusted"] as? Bool) == false { continue }
            let isGroup = (info?["type"] as? String) == "GROUP_DM"
            let participants = ((info?["participants"] as? [[String: Any]]) ?? [])
                .compactMap { LiveMessages.idString($0["user_id"]) }
            // A one-to-one's id is `<a>-<b>`; read it when the metadata is
            // missing, so the other person can still be named.
            let ids = participants.isEmpty && !isGroup
                ? conversationID.split(separator: "-").map(String.init)
                : participants
            let others = ids.filter { $0 != me }.compactMap { users[$0] }
            let groupName = (info?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let title = groupName.map { String(localized: "Messages in \($0)") }
                ?? LiveMessages.title(names: others.compactMap(\.label))
            let other = !isGroup && others.count == 1 ? others.first : nil
            out.append(LiveConversation(
                id: conversationID,
                title: title,
                handle: other?.handle,
                avatar: other?.avatar,
                isGroup: isGroup,
                lines: lines.sorted { $0.at < $1.at }))
        }
        return out.sorted { ($0.lines.last?.at ?? .distantPast) > ($1.lines.last?.at ?? .distantPast) }
    }

    /// A message's words: t.co out and the real link in, the link to its own
    /// picture dropped (`XLiveNotifications.expandLinks`' two rules), and a
    /// picture, video or GIF with no words named as one. nil for nothing.
    static func text(_ data: [String: Any]) -> String? {
        var out = (data["text"] as? String) ?? ""
        let entities = data["entities"] as? [String: Any]
        for url in (entities?["urls"] as? [[String: Any]]) ?? [] {
            guard let short = url["url"] as? String, !short.isEmpty,
                  let expanded = url["expanded_url"] as? String else { continue }
            out = out.replacingOccurrences(of: short, with: expanded)
        }
        var media: String?
        if let attachment = data["attachment"] as? [String: Any] {
            for (key, word) in [("photo", String(localized: "Photo")),
                                ("video", String(localized: "Video")),
                                ("animated_gif", String(localized: "GIF"))] {
                guard let item = attachment[key] as? [String: Any] else { continue }
                media = word
                if let short = item["url"] as? String, !short.isEmpty {
                    out = out.replacingOccurrences(of: short, with: "")
                }
            }
        }
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.isEmpty { return media }
        return out
    }
}
