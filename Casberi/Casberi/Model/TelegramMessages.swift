import Foundation

/// Your Telegram chats, read through TDLib signed in as you (prd §1575) — the
/// third live messages seat beside X and Instagram (§1244), and the door §57
/// refused and §456 never weighed. The PURE half: TDLib's JSON objects
/// (`chat`, `message`, `user`) to `LiveConversation`s, Foundation only,
/// compiled whole by `scripts/telegram-messages-selftest.sh`. The client is
/// `TelegramClient`, the read `TelegramMessagesRead`.
///
/// **What it reads, and what it does not.** One-to-ones, small groups and
/// supergroups in the main chat list. Not channels: a public one is the
/// follow half (`TelegramChannel`), and a private one is broadcast, not a
/// conversation. Not secret chats: they live on the phone that opened them,
/// and TDLib here never opens one. Not bots. **Never Telegram's own service
/// account (777000)**: it is where login codes arrive, and a login code in
/// the corpus is a credential in the corpus. Reading never marks anything
/// read — that is `viewMessages`, which this app never sends.
///
/// **MEASURED** against one real account on 2026-10-27 through the probe
/// that preceded this file: 100 chats listed in 0.6s, 20 messages from each
/// of 30 chats in 2.4s, `messageText` and `messagePhoto` the bulk, service
/// lines (auto-delete timers, joins, pins) beside them — which land nothing.
enum TelegramMessages {
    /// Its own namespace, registered in `Corpus.liveRefPrefixesBySource`
    /// under "Telegram" so a conversation reaches All and "Remove import"
    /// steps over it. Not the export's `telegram:chat:`: that row is the
    /// file's, and "Remove import" removes it.
    static let refPrefix = "telegram:dm:"

    /// A person's public photo, by username: Telegram's own redirect to its
    /// CDN (`telesco.pe`), keyless, and a 404 for anyone without a public
    /// username or photo — the row then keeps the Telegram mark. TDLib's own
    /// photos are files on this device, which no other device of yours has.
    static func face(handle: String) -> String {
        "https://t.me/i/userpic/320/\(handle).jpg"
    }

    /// Telegram's service notifications — login codes among them.
    static let serviceUserID: Int64 = 777000

    struct User: Equatable {
        var name: String?
        var handle: String?
        var isBot: Bool
        /// The display name, else the handle with its @.
        var label: String? { name ?? handle.map { "@" + $0 } }
    }

    static func int64(_ any: Any?) -> Int64? {
        if let n = any as? NSNumber { return n.int64Value }
        if let s = any as? String { return Int64(s) }
        return nil
    }

    static func user(_ json: [String: Any]) -> User {
        let first = (json["first_name"] as? String) ?? ""
        let last = (json["last_name"] as? String) ?? ""
        let name = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        let usernames = json["usernames"] as? [String: Any]
        let handle = (usernames?["active_usernames"] as? [String])?.first
        let type = (json["type"] as? [String: Any])?["@type"] as? String
        return User(name: name.isEmpty ? nil : name,
                    handle: handle.flatMap { $0.isEmpty ? nil : $0 },
                    isBot: type == "userTypeBot")
    }

    enum Kind: Equatable {
        case saved
        case oneToOne(userID: Int64)
        case group
    }

    /// Which kind of conversation a chat is, nil for one this seat never
    /// reads (a channel, a secret chat, a bot, the service account).
    static func kind(_ chat: [String: Any], me: Int64?, users: [Int64: User]) -> Kind? {
        guard let type = chat["type"] as? [String: Any] else { return nil }
        switch type["@type"] as? String {
        case "chatTypePrivate":
            guard let id = int64(type["user_id"]), id != serviceUserID else { return nil }
            if id == me { return .saved }
            if users[id]?.isBot == true { return nil }
            return .oneToOne(userID: id)
        case "chatTypeBasicGroup":
            return .group
        case "chatTypeSupergroup":
            return (type["is_channel"] as? Bool) == true ? nil : .group
        default:
            return nil
        }
    }

    /// A message's words, or what it is when it has none. nil for a service
    /// line (a timer set, someone joined, a pin) — those are Telegram talking
    /// about the chat, not anybody in it.
    static func text(_ content: [String: Any]) -> String? {
        func formatted(_ key: String) -> String? {
            let words = ((content[key] as? [String: Any])?["text"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return words.flatMap { $0.isEmpty ? nil : $0 }
        }
        func named(_ word: String) -> String {
            formatted("caption").map { "\(word): \($0)" } ?? word
        }
        switch content["@type"] as? String {
        case "messageText": return formatted("text")
        case "messagePhoto": return named(String(localized: "Photo"))
        case "messageVideo": return named(String(localized: "Video"))
        case "messageAnimation": return named(String(localized: "GIF"))
        case "messageVoiceNote": return named(String(localized: "Voice message"))
        case "messageVideoNote": return String(localized: "Video message")
        case "messageAudio": return named(String(localized: "Audio"))
        case "messageDocument":
            let file = ((content["document"] as? [String: Any])?["file_name"] as? String)
                .flatMap { $0.isEmpty ? nil : $0 }
            return named(file ?? String(localized: "File"))
        case "messageSticker":
            let emoji = (content["sticker"] as? [String: Any])?["emoji"] as? String
            return emoji.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Sticker")
        case "messageAnimatedEmoji":
            return (content["emoji"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        case "messageLocation", "messageVenue": return String(localized: "Location")
        case "messageContact": return String(localized: "Contact")
        case "messagePoll":
            let question = (content["poll"] as? [String: Any])?["question"]
            // A `formattedText` since TDLib 1.8.32, a bare string before it.
            let words = (question as? [String: Any])?["text"] as? String ?? question as? String
            return words.map { String(localized: "Poll: \($0)") } ?? String(localized: "Poll")
        default: return nil
        }
    }

    /// One chat and a page of its history as a conversation, nil when the
    /// chat is not one this seat reads or nothing in the page has words.
    /// `messages` in any order; `chatTitles` names a sender that is a chat
    /// (an anonymous admin, a channel posting in its discussion group).
    static func conversation(chat: [String: Any], messages: [[String: Any]],
                             users: [Int64: User], chatTitles: [Int64: String] = [:],
                             me: Int64?) -> LiveConversation? {
        guard let chatID = int64(chat["id"]),
              let kind = kind(chat, me: me, users: users) else { return nil }
        var seen = Set<String>()
        var lines: [LiveConversation.Line] = []
        for message in messages {
            guard let id = int64(message["id"]).map(String.init), seen.insert(id).inserted,
                  let at = LiveMessages.date(epoch: message["date"]),
                  let content = message["content"] as? [String: Any],
                  let words = text(content) else { continue }
            let sender = message["sender_id"] as? [String: Any]
            let senderName: String? = switch sender?["@type"] as? String {
            case "messageSenderUser": int64(sender?["user_id"]).flatMap { users[$0]?.label }
            case "messageSenderChat": int64(sender?["chat_id"]).flatMap { chatTitles[$0] }
            default: nil
            }
            let line: String = switch kind {
            // Notes to yourself: every line is yours, so none says so.
            case .saved: LiveMessages.line(sender: nil, isMe: false, text: words)
            // The other person is the title; their lines carry no name.
            case .oneToOne:
                LiveMessages.line(sender: nil, isMe: (message["is_outgoing"] as? Bool) == true,
                                  text: words)
            case .group:
                LiveMessages.line(sender: senderName,
                                  isMe: (message["is_outgoing"] as? Bool) == true, text: words)
            }
            lines.append(.init(id: id, at: at, text: line))
        }
        guard !lines.isEmpty else { return nil }
        let chatTitle = (chat["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let title: String
        var handle: String?
        switch kind {
        case .saved:
            title = String(localized: "Saved Messages")
        case .oneToOne(let userID):
            let other = users[userID]
            handle = other?.handle
            title = LiveMessages.title(names: [other?.label ?? chatTitle].compactMap { $0 })
        case .group:
            title = chatTitle.map { String(localized: "Messages in \($0)") }
                ?? String(localized: "Messages")
        }
        return LiveConversation(
            id: String(chatID),
            title: title,
            handle: handle,
            // A one-to-one's face; a group keeps the source mark (§707).
            avatar: handle.map(face(handle:)),
            isGroup: kind == .group,
            lines: lines.sorted { $0.at < $1.at })
    }

    /// The chat's newest message time — what decides whether a chat has
    /// anything newer than the row already holds.
    static func lastActivity(_ chat: [String: Any]) -> Date? {
        LiveMessages.date(epoch: (chat["last_message"] as? [String: Any])?["date"])
    }
}
