import Foundation
import SwiftData

/// One read of your Telegram chats, landed (prd §1575): the chats in your
/// main list with something newer than their row holds, each paged back to
/// that row's newest line, mapped by `TelegramMessages` and landed by
/// `LiveMessagesLanding` as one `.chat` thing per conversation.
///
/// **A first read looks back `firstReadDays`, at most `chatCap` chats**: a
/// Telegram account is years of chats, and the X and Instagram reads also
/// begin with what is current rather than an archive (the export is
/// Telegram's archive door, §456). TDLib keeps what it fetched in its own
/// database, so a later read asks Telegram for what is new only.
enum TelegramMessagesRead {
    static let firstReadDays = 30
    static let chatCap = 40
    /// History per chat per read — one transcript's worth (`LiveMessages`).
    static let pageCap = 60

    /// The newest message id each chat had when it was last read, so a chat
    /// whose newest message has no words (a pin, a call) is not paged again
    /// on every read for lines it will never yield.
    static let lastSeenKey = "telegram.read.lastSeen"

    static func lastSeen() -> [String: Int64] {
        guard let data = UserDefaults.standard.data(forKey: lastSeenKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Int64].self, from: data)) ?? [:]
    }

    struct Reading {
        var conversations: [LiveConversation] = []
        var chatsListed = 0
        var chatsRead = 0
        var failure: String?
    }

    /// The landing, for the sweep and the account page: how many
    /// conversations are new or grew, nil when the read failed.
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        guard TelegramClient.signedIn, LiveMessages.reads(.telegram) else { return 0 }
        let newest = LiveMessagesLanding.newest(source: "Telegram",
                                                refPrefix: TelegramMessages.refPrefix,
                                                context: context)
        let reading = await read(newest: newest)
        guard reading.failure == nil else { return nil }
        return LiveMessagesLanding.land(reading.conversations, source: "Telegram",
                                        refPrefix: TelegramMessages.refPrefix,
                                        context: context).news
    }

    /// The read itself, off the store: `newest` is each landed row's newest
    /// line by ref. `remember` false (the probe) records nothing, so a probe
    /// never hides a chat from the next real read.
    static func read(newest: [String: Date], remember: Bool = true, now: Date = .now) async -> Reading {
        var reading = Reading()
        var seen = lastSeen()
        defer {
            if remember, let data = try? JSONEncoder().encode(seen) {
                DefaultsWrite.set(data, forKey: lastSeenKey)
            }
        }
        let client = TelegramClient.shared
        guard await client.settled() == .ready else {
            reading.failure = "not signed in"
            return reading
        }
        let me = TelegramMessages.int64((await client.send(["@type": "getMe"]))["id"])
        let list: [String: Any] = ["@type": "chatListMain"]
        // `loadChats` answers an error once the list is fully loaded — not a
        // failure, so only `getChats` is read for one.
        _ = await client.send(["@type": "loadChats", "chat_list": list, "limit": 100], timeout: 60)
        let chats = await client.send(["@type": "getChats", "chat_list": list, "limit": 100], timeout: 60)
        if let failure = TelegramClient.failed(chats) {
            reading.failure = failure
            return reading
        }
        let ids = ((chats["chat_ids"] as? [Any]) ?? []).compactMap(TelegramMessages.int64)
        reading.chatsListed = ids.count
        let floor = now.addingTimeInterval(-Double(firstReadDays) * 86_400)

        var users: [Int64: TelegramMessages.User] = [:]
        func user(_ id: Int64) async -> TelegramMessages.User? {
            if let known = users[id] { return known }
            let json = await client.send(["@type": "getUser", "user_id": id])
            guard TelegramClient.failed(json) == nil else { return nil }
            let found = TelegramMessages.user(json)
            users[id] = found
            return found
        }
        var chatTitles: [Int64: String] = [:]

        for chatID in ids {
            guard reading.chatsRead < chatCap else { break }
            let chat = await client.send(["@type": "getChat", "chat_id": chatID])
            guard TelegramClient.failed(chat) == nil else { continue }
            if let title = chat["title"] as? String { chatTitles[chatID] = title }
            // The other person first: whether a one-to-one is a bot is theirs.
            if let type = chat["type"] as? [String: Any], type["@type"] as? String == "chatTypePrivate",
               let other = TelegramMessages.int64(type["user_id"]) {
                _ = await user(other)
            }
            guard TelegramMessages.kind(chat, me: me, users: users) != nil,
                  let last = TelegramMessages.lastActivity(chat) else { continue }
            let since = newest[TelegramMessages.refPrefix + String(chatID)] ?? floor
            let lastID = TelegramMessages.int64((chat["last_message"] as? [String: Any])?["id"])
            guard last > since, lastID == nil || seen[String(chatID)] != lastID else { continue }
            reading.chatsRead += 1
            seen[String(chatID)] = lastID

            let messages = await history(chatID: chatID, since: since, client: client)
            for message in messages {
                let sender = message["sender_id"] as? [String: Any]
                if sender?["@type"] as? String == "messageSenderUser",
                   let id = TelegramMessages.int64(sender?["user_id"]) { _ = await user(id) }
            }
            if let conversation = TelegramMessages.conversation(
                chat: chat, messages: messages, users: users, chatTitles: chatTitles, me: me) {
                reading.conversations.append(conversation)
            }
        }
        return reading
    }

    /// Newest first, back to `since` or `pageCap`. TDLib answers the first
    /// page from what it has (often one message), so it pages until a page
    /// comes back empty, older than `since`, or the cap is met.
    static func history(chatID: Int64, since: Date, client: TelegramClient) async -> [[String: Any]] {
        var out: [[String: Any]] = []
        var from: Int64 = 0
        for _ in 0..<8 where out.count < pageCap {
            let page = await client.send([
                "@type": "getChatHistory", "chat_id": chatID, "from_message_id": from,
                "offset": 0, "limit": min(50, pageCap - out.count), "only_local": false,
            ])
            let messages = (page["messages"] as? [[String: Any]]) ?? []
            guard let oldest = messages.last, let id = TelegramMessages.int64(oldest["id"]) else { break }
            out += messages
            from = id
            if let at = LiveMessages.date(epoch: oldest["date"]), at <= since { break }
        }
        return out
    }
}
