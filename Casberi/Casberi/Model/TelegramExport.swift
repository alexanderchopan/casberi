import Foundation

/// A Telegram Desktop data export (`result.json`), read as text (prd §456,
/// 2026-08-23). The PURE half: this file turns the export's bytes into shapes
/// and makes no claim about the corpus — the landing half consumes it.
///
/// **WHY AN IMPORT AT ALL, BESIDE THE LIVE CHANNEL SEAT.** `TelegramChannel`
/// follows a PUBLIC channel through its own web preview, which is broadcast
/// media and nothing else: it can never see Saved Messages, a DM, a group, or
/// a private channel you are a member of. Those live behind MTProto, and §57's
/// 2026-07-14 ruling shut both remaining doors (a Bot API bot sees only what is
/// forwarded to it; TDLib is a client-grade dependency behind a platform wall).
/// The desktop export is the third door, and it is the same door Snapchat,
/// ChatGPT, Day One and the X archive already use — a file the person asks
/// their own client for, parsed offline, reaching nothing.
///
/// **SAVED MESSAGES IS THE LEAD.** It is the reason this seat is worth having:
/// a personal pile of forwarded links, self-notes and things somebody meant to
/// come back to — which is the corpus's own semantics, already written by hand
/// by the person, with real dates. So each saved message is its OWN entry,
/// while a DM or a group is ONE conversation thing (`SnapchatImport`'s shape,
/// and the module doctrine's reason: a chat is a relationship, not N tallies).
///
/// **UNMEASURED, ENTIRELY.** No real Telegram export has ever been held by this
/// project. Every rule below is derived from Telegram Desktop's own JSON
/// generator (`export_output_json.cpp`) plus published fixtures — never from
/// bytes in hand — so the whole file is written to fail SAFE: an unknown field
/// is a skip, an unparseable date is a skip, and nothing here ever invents a
/// timestamp. Re-measure against a real export before hardening any of it.
///
/// The schema facts that shape this parser, each of which fails INVISIBLY if it
/// drifts (the import stays green and the corpus is quietly wrong):
///
///   1. **The file is frequently INVALID JSON.** Telegram escapes control
///      bytes as `\xNN`, which RFC 8259 does not permit, and
///      `JSONSerialization` fails on the whole document with no partial
///      result. `repairControlEscapes` is the pre-pass, and it is the single
///      most likely reason a real import would otherwise fail outright.
///   2. **A single-chat export is a BARE chat object**, not
///      `{chats: {list: […]}}`. Detection is the presence of a `chats` key and
///      deliberately NOT of `messages` — a full export's chats carry that too.
///   3. **`type` has THREE values, and `"unsupported"` carries NO date, NO
///      `from` and NO text.** Gate on the type before reading anything else or
///      an unsupported message either crashes the read or lands undated.
///   4. **`date` is ISO local time with NO offset**, in the exporting
///      machine's zone, which the export records nowhere.
///      `date_unixtime` is authoritative — and is ABSENT in pre-~2021
///      exports, along with `text_entities`. See `timestamp(_:)`.
///   5. **`text` is polymorphic** (`""`, a bare String, or an array mixing
///      bare strings with entity objects) while `text_entities` is always an
///      array and lossless. Prefer the latter; fall back to the former.
///   6. **A skipped file's path field carries a placeholder sentence**, and it
///      can be PREFIXED by a name — so it is matched as a substring, never by
///      equality. A `photo` field uses the "File" wording despite its key.
///   7. **Message `id` is unique per CHAT, not globally**, so every ref here
///      is keyed on the pair.
///
/// Foundation-only BY DESIGN — no `Thing`, no `ModelContext`, and deliberately
/// not even `IngestSupport` — so a harness can compile it WHOLE and unmodified.
/// That is the only proof these rules hold: nothing in a build or a screen
/// sweep can see a parser that quietly returns the wrong three thousand
/// messages, or dates a decade of them to 1970.
enum TelegramExport {

    // MARK: - Identity

    /// The `Thing.source` both halves of this seat land under — the same string
    /// `TelegramChannel.source` uses, so a followed channel and an imported
    /// export share one room.
    static let source = "Telegram"

    /// The three ref namespaces this import writes.
    ///
    /// **None of them may collide with `TelegramChannel.refPrefix`
    /// (`"telegram:post:"`)**, which is a member of `Corpus.liveRefPrefixes` —
    /// the set that decides whether a row reaches the All feed or stays in its
    /// own bulk-import room. A namespace that overlapped would either flood All
    /// with a decade of somebody's DMs or silence a followed channel, and both
    /// render perfectly from the inside. This is `ref-shape-audit`'s exact
    /// class, so the prefixes are declared once here and read by the landing
    /// half rather than being spelled a second time there.
    static let savedRefPrefix = "telegram:saved:"
    static let chatRefPrefix = "telegram:chat:"
    static let channelRefPrefix = "telegram:channel:"

    /// One saved message. Keyed on the message id alone because Saved Messages
    /// is a single chat by construction — there is exactly one per account.
    static func savedRef(messageID: Int) -> String {
        "\(savedRefPrefix)\(messageID)"
    }

    /// One conversation. Keyed on the CHAT, never the counterpart's name: a
    /// name is renameable and two people can share one, while the id is what
    /// Telegram itself considers the conversation.
    static func chatRef(chatID: Int) -> String {
        "\(chatRefPrefix)\(chatID)"
    }

    /// One post in an imported channel. Both halves, because of schema fact 7.
    static func channelRef(chatID: Int, messageID: Int) -> String {
        "\(channelRefPrefix)\(chatID)/\(messageID)"
    }

    // MARK: - Caps

    /// The refusals, and they are COUNTED rather than silent (prd §307/§309).
    /// A truncated import and a complete one otherwise produce identical
    /// receipts — that is how four import rooms shipped capped at 500 for
    /// months with nobody able to see it — so every number the caps refuse is
    /// returned in `Parsed.counts` and belongs on the receipt.
    ///
    /// The three differ because the units do. A saved message is one row per
    /// CAPTURE and a heavy user's pile runs deep; a conversation is one row per
    /// PERSON OR GROUP, so five thousand is already a generous read of anybody's
    /// contact list; a channel post is one row per broadcast, capped PER CHANNEL
    /// rather than across all of them, since one busy channel must not be able
    /// to starve every other one.
    static let savedCap = 20_000
    static let conversationCap = 5_000
    static let channelPostCap = 10_000

    /// Lines kept per conversation, newest-biased, and the transcript's own
    /// ceiling. `SnapchatImport`'s numbers, deliberately identical: two rooms
    /// holding the same kind of object should hold the same amount of it.
    static let lineCap = 60
    static let transcriptCap = 4_000

    // MARK: - Shapes

    /// What a chat IS, folded from Telegram's ten `type` values.
    ///
    /// The three supergroup/group spellings collapse because nothing
    /// downstream treats them differently — a group transcript is a group
    /// transcript — while `channel` keeps both its spellings apart from
    /// `group` because a channel is broadcast media and lands as posts, not as
    /// a conversation.
    ///
    /// **`.other` is never landed, and two of its members are the reason.**
    /// `verification_codes` is Telegram's own login-code chat: its entire
    /// content is one-time secrets, and importing it would walk a pile of live
    /// credentials straight into the corpus, into Spotlight, and into whatever
    /// a keyed agent is grounded on (prd §277 — `SecretScan` is a tripwire, not
    /// a licence to collect). `replies` is a pseudo-chat Telegram synthesises
    /// for comment threads and names nobody. Anything Telegram adds later lands
    /// here too, which is the safe default: a type we do not understand is one
    /// we must not file.
    enum ChatKind: Equatable {
        case savedMessages
        case personal
        case bot
        case group
        case channel
        case other

        init(rawType: String?) {
            switch (rawType ?? "").lowercased() {
            case "saved_messages": self = .savedMessages
            case "personal_chat": self = .personal
            case "bot_chat": self = .bot
            case "private_group", "private_supergroup", "public_supergroup": self = .group
            case "private_channel", "public_channel": self = .channel
            default: self = .other
            }
        }

        /// Does this kind land as ONE thing per message (a pile) rather than
        /// one thing per chat (a relationship)?
        var landsPerMessage: Bool {
            self == .savedMessages || self == .channel
        }
    }

    /// One landable item — a saved message or a channel post.
    struct Entry: Equatable {
        /// Unique within its chat and nowhere else (schema fact 7).
        var id: Int
        var date: Date
        /// The message's words, reconstructed from `text_entities` where the
        /// export has them. Empty exactly when the message carried none.
        var text: String
        /// What this message WAS, when it has no words of its own — "Photo",
        /// "Voice message", the document's own file name. nil when the message
        /// carries no media at all.
        ///
        /// Deliberately independent of `mediaPath`: an export made with file
        /// downloading switched off still says a photograph was sent, and
        /// dropping those would delete the shape of somebody's chat history
        /// because of a checkbox in the exporter.
        var mediaLabel: String?
        /// This message is a PHOTOGRAPH (the `photo` field), as opposed to a
        /// sticker, a video or a document. Pair it with `mediaPath != nil`
        /// before drawing anything: this says what the message is, that says
        /// whether the pixels are on disk.
        var isPhoto: Bool
        /// Relative to the EXPORT ROOT, exactly as the export spells it —
        /// `chats/chat_03/photos/photo_12@01-08-2020_22-01-49.jpg` in a full
        /// export, `photos/photo_1@…jpg` in a single-chat one. The per-chat
        /// prefix is the export's business, not ours, so it is never rebuilt:
        /// the landing half appends this to the folder the person picked.
        /// nil for every placeholder (schema fact 6).
        var mediaPath: String?
        /// Every URL the message names — an entity `link`'s own text and a
        /// `text_link`'s `href`. This is the point of Saved Messages: a pile of
        /// forwarded links whose destination is the thing worth keeping.
        var links: [String]
        /// Whose message this repeats, when it was forwarded in. The display
        /// NAME, which is all the export carries — never a handle, so nothing
        /// downstream may treat it as one.
        var forwardedFrom: String?
        /// The message this one answers, within the same chat.
        var replyTo: Int?

        /// A message with no words of its own — a bare photograph, a voice
        /// note, a sticker. The room draws these as pictures rather than as
        /// rows wearing a placeholder title (§375's ruling, one product over).
        var isWordless: Bool { text.isEmpty }
    }

    /// One imported channel, and its posts.
    ///
    /// Carries its `id` rather than being a `(name, [Entry])` pair, because the
    /// ref is built from the chat id (fact 7) and a name cannot stand in for
    /// one: channels are renamed, and two of them can share a title.
    struct ChannelChat: Equatable {
        var id: Int
        var name: String
        /// `.channel` always; kept so a consumer can pattern-match uniformly.
        var kind: ChatKind
        /// Newest first, already capped.
        var entries: [Entry]

        var newest: Date? { entries.first?.date }
    }

    /// One conversation — a DM, a bot chat or a group — flattened for landing
    /// as a SINGLE thing (`SnapchatImport.Conversation`'s shape).
    struct Conversation: Equatable {
        var id: Int
        /// The counterpart's display name, or the group's.
        var handle: String
        var kind: ChatKind
        var newest: Date
        /// Oldest → newest, already clamped to `lineCap` and speaker-prefixed.
        var lines: [String]
        /// Every message this conversation holds — counted BEFORE `lines` was
        /// clamped, so it survives the clamp that `transcript` then applies
        /// again. This is the only moment the true number exists: nothing
        /// downstream can recover it from a stored transcript, which is why
        /// `Thing.messageCount` is a field and not a computed line count, and
        /// why a room's "who you talk to most" board ranks on it. Clamping it
        /// would flatten a decade-long friendship onto a week-old chat.
        var total: Int

        var transcript: String {
            String(lines.joined(separator: "\n").prefix(TelegramExport.transcriptCap))
        }
    }

    /// What the caps and the schema refused, so the receipt can say it.
    struct Counts: Equatable {
        /// Chats the export held, of every kind — including the ones `.other`
        /// declined, so "we read 40 chats and landed 12" is sayable.
        var chats = 0
        /// Chats whose kind is not landed (`replies`, `verification_codes`,
        /// anything Telegram adds later).
        var chatsSkipped = 0
        /// `type: "service"` — a join, a title change, a pinned message.
        /// Never an entry: it is Telegram narrating itself.
        var service = 0
        /// `type: "unsupported"` — a message this export's own writer could
        /// not represent. It carries nothing at all, so there is nothing to
        /// land; counting it is the only honest thing available.
        var unsupported = 0
        /// A message whose date could not be read. Skipped rather than stamped
        /// with `.now`, which would file somebody's 2016 as today's news.
        var undated = 0
        /// A message with neither words nor media. Genuinely nothing to keep.
        var empty = 0
        /// A message with no readable id — nothing to build a ref from, so it
        /// could never dedupe.
        var malformed = 0
        var savedDropped = 0
        var conversationsDropped = 0
        var channelPostsDropped = 0

        /// What the caps refused, in one number, for a receipt line.
        var dropped: Int { savedDropped + conversationsDropped + channelPostsDropped }
    }

    /// Everything one export holds.
    struct Parsed {
        var savedMessages: [Entry] = []
        var channels: [ChannelChat] = []
        var conversations: [Conversation] = []
        var counts = Counts()
        /// Did the root look like a Telegram export AT ALL?
        ///
        /// Separate from "landed nothing", and the distinction is the whole
        /// point: an export whose chats are all `.other`, or whose DMs were not
        /// asked for, legitimately lands zero — while a JSON that is not this
        /// file lands zero too, and telling somebody "nothing new" when they
        /// handed us the wrong file is the §83 fake status.
        var isExport = false
    }

    // MARK: - The `\xNN` repair (schema fact 1)

    /// Telegram Desktop escapes every byte below 32 as `\xNN`. **That is not
    /// valid JSON** — RFC 8259 allows exactly `\"`, `\\`, `\/`, `\b`, `\f`,
    /// `\n`, `\r`, `\t` and `\uXXXX` — so `JSONSerialization` rejects the
    /// entire document and returns no partial result. A real export carrying a
    /// single vertical tab anywhere in a decade of messages is therefore
    /// unreadable end to end, and the failure looks exactly like "this isn't a
    /// Telegram export".
    ///
    /// The rewrite is `\xNN` → `\u00NN`, which is the same character in a form
    /// the parser accepts.
    ///
    /// **THE TRAP IS THE ESCAPED BACKSLASH.** A message whose text really
    /// contains `\x41` arrives as `\\x41` — an escaped backslash followed by
    /// the literal characters `x41` — and rewriting that produces `\\u0041`,
    /// silently turning somebody's words into a different string. So the
    /// preceding backslashes are COUNTED: an ODD run means the last one is
    /// introducing this escape and the `\xNN` is Telegram's; an EVEN run means
    /// every backslash is already paired and the `x` is a literal. Getting this
    /// backwards corrupts text rather than failing, which is worse than not
    /// repairing at all.
    ///
    /// Untouched when the input holds no `\x` at all, so the common path costs
    /// one substring search.
    static func repairControlEscapes(_ raw: String) -> String {
        guard raw.contains("\\x") else { return raw }
        let chars = Array(raw)
        var out = ""
        out.reserveCapacity(chars.count)
        var i = 0
        while i < chars.count {
            guard chars[i] == "\\" else {
                out.append(chars[i])
                i += 1
                continue
            }
            var run = 0
            var j = i
            while j < chars.count, chars[j] == "\\" {
                run += 1
                j += 1
            }
            if run % 2 == 1,
               j + 2 < chars.count,
               chars[j] == "x",
               chars[j + 1].isHexDigit,
               chars[j + 2].isHexDigit {
                // Every backslash but the last was a pair; the last one
                // introduces the escape we are rewriting.
                out.append(String(repeating: "\\", count: run - 1))
                out.append("\\u00")
                out.append(chars[j + 1])
                out.append(chars[j + 2])
                i = j + 3
            } else {
                out.append(String(repeating: "\\", count: run))
                i = j
            }
        }
        return out
    }

    /// The export's root object, repaired if it needs repairing.
    ///
    /// Plain JSON is tried FIRST — most of the file is valid most of the time,
    /// and a whole-document rewrite of a several-hundred-megabyte export is not
    /// free. The repair runs only once the parser has already refused.
    ///
    /// Returns nil rather than throwing: every failure here means "this is not
    /// a readable Telegram export", which the caller says in one sentence.
    static func decode(_ data: Data) -> Any? {
        if let direct = try? JSONSerialization.jsonObject(with: data) { return direct }
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        let repaired = repairControlEscapes(raw)
        // Nothing changed, so the file is broken some other way and re-parsing
        // identical bytes would only cost the time again.
        guard repaired != raw, let fixed = repaired.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: fixed)
    }

    // MARK: - Chats (schema fact 2)

    /// Every chat in the export, whichever shape it arrived in.
    ///
    /// A FULL export is `{chats: {about, list: […]}, left_chats: {…}, …}`, and
    /// `left_chats` is often absent — it is never required, because demanding
    /// it would make a perfectly ordinary export unreadable.
    ///
    /// A SINGLE-CHAT export (Telegram's "export this chat" verb, which is how
    /// most people will actually use this) is a BARE chat object with `name`,
    /// `type`, `id` and `messages` at the root.
    ///
    /// **The fork is decided on the `chats` key and NOT on `messages`**: a full
    /// export's chats each carry `messages` too, so sniffing on that would read
    /// a full export's first chat and throw the rest away — an import that
    /// lands real rows, reports success, and silently loses everything.
    static func chats(in root: Any) -> [[String: Any]] {
        guard let dict = root as? [String: Any] else { return [] }
        if dict["chats"] != nil {
            return list(in: dict["chats"]) + list(in: dict["left_chats"])
        }
        // A bare chat must still LOOK like one, or any JSON at all would read
        // as an export holding one empty chat.
        guard dict["messages"] is [Any] else { return [] }
        return [dict]
    }

    /// `{about, list: [Chat]}`, or — defensively — a bare array, since the
    /// wrapper has been reshaped before and the inner shape is unambiguous.
    private static func list(in raw: Any?) -> [[String: Any]] {
        if let dict = raw as? [String: Any], let list = dict["list"] as? [[String: Any]] {
            return list
        }
        if let array = raw as? [[String: Any]] { return array }
        return []
    }

    /// What to call a chat.
    ///
    /// `name` is String, null, **or absent entirely** — Telegram omits it for
    /// `saved_messages`, `replies` and `verification_codes`, so a parser that
    /// requires it drops exactly the chat this seat exists for.
    static func displayName(of chat: [String: Any], kind: ChatKind) -> String {
        if let name = (chat["name"] as? String).map(tidy), !name.isEmpty { return name }
        switch kind {
        case .savedMessages: return "Saved Messages"
        default:
            if let id = intValue(chat["id"]) { return "Chat \(id)" }
            return "Telegram chat"
        }
    }

    // MARK: - Text (schema fact 5)

    /// A message's words, from whichever field carries them.
    ///
    /// `text` is polymorphic: `""` when empty, a bare String for a single plain
    /// run, and otherwise an ARRAY mixing bare strings with entity objects
    /// `{type, text, …}`. Every entity object always carries `text`, so
    /// reconstructing the body is joining every element's text in order —
    /// which is also why an entity's `type` is irrelevant HERE and matters only
    /// to `links(in:)`.
    ///
    /// Handles all three, plus the nested case, so the same function reads a
    /// poll's question and each of its answers — which are polymorphic in
    /// exactly the same way, a fact easy to miss because they sit under a
    /// different key.
    static func plainText(_ raw: Any?) -> String {
        switch raw {
        case let text as String:
            return text
        case let parts as [Any]:
            return parts.map(plainText).joined()
        case let entity as [String: Any]:
            return plainText(entity["text"])
        default:
            return ""
        }
    }

    /// The body of one message, preferring `text_entities`.
    ///
    /// `text_entities` is always an array in modern exports (including `[]`),
    /// monomorphic, and lossless — plain runs appear as `{"type":"plain", …}`,
    /// note the spelling is `plain` and not `text`. It is ABSENT in pre-~2021
    /// exports, where `text` is the only body there is.
    ///
    /// An empty `text_entities` beside a non-empty `text` should be impossible
    /// given the losslessness; it falls back anyway, because the cost of being
    /// wrong about that is a message landing with no words.
    static func body(of message: [String: Any]) -> String {
        let entities = tidy(plainText(message["text_entities"]))
        if !entities.isEmpty { return entities }
        return tidy(plainText(message["text"]))
    }

    /// Every URL a message names.
    ///
    /// Two entity types carry one and they carry it in different places: a
    /// `link` is a bare URL and its own `text` IS the URL, while a `text_link`
    /// is words standing in for a destination and the URL is its `href`.
    /// Reading only the text of both would collect the words and lose every
    /// link that was ever written as a phrase.
    ///
    /// The bare scan is the FALLBACK for a legacy export whose `text` is a
    /// plain String with no entities at all — there the URL is in the words and
    /// nowhere else. It runs only when the entity pass found nothing, so it can
    /// never duplicate or contradict what the export itself declared.
    static func links(in message: [String: Any]) -> [String] {
        var found: [String] = []
        var seen = Set<String>()

        func consider(_ url: String) {
            let clean = tidy(url)
            guard clean.count > 8, seen.insert(clean).inserted else { return }
            found.append(clean)
        }

        for raw in [message["text_entities"], message["text"]] {
            guard let parts = raw as? [Any] else { continue }
            for part in parts {
                guard let entity = part as? [String: Any] else { continue }
                switch (entity["type"] as? String)?.lowercased() {
                case "link":
                    consider(plainText(entity["text"]))
                case "text_link":
                    if let href = entity["href"] as? String { consider(href) }
                default:
                    continue
                }
            }
            if !found.isEmpty { return found }
        }

        for token in body(of: message).split(whereSeparator: { $0.isWhitespace || $0.isNewline }) {
            let candidate = String(token)
            guard candidate.hasPrefix("http://") || candidate.hasPrefix("https://") else { continue }
            // A URL at the end of a sentence keeps the sentence's punctuation.
            consider(candidate.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}\"'")))
        }
        return found
    }

    /// A poll, as words.
    ///
    /// The question and every answer's `text` are polymorphic exactly like a
    /// message body — the one place that is easy to miss, because a poll sits
    /// under its own key and looks like plain data. Vote counts are deliberately
    /// left out: `voters` is a tally, and a tally is not a thing (module
    /// doctrine, prd §166); the answers themselves are content and are kept.
    static func pollText(_ raw: Any?) -> String? {
        guard let poll = raw as? [String: Any] else { return nil }
        let question = tidy(plainText(poll["question"]))
        let answers = (poll["answers"] as? [[String: Any]] ?? [])
            .map { tidy(plainText($0["text"])) }
            .filter { !$0.isEmpty }
        guard !question.isEmpty || !answers.isEmpty else { return nil }
        var lines = question.isEmpty ? [] : [question]
        lines += answers.map { "· \($0)" }
        return lines.joined(separator: "\n")
    }

    // MARK: - Time (schema fact 4)

    /// When a message happened.
    ///
    /// `date_unixtime` is AUTHORITATIVE and is a **quoted string** of epoch
    /// seconds — a Number is accepted too, because trusting one spelling of a
    /// field that has already been respelled once is how a parser dates a whole
    /// export to nil.
    ///
    /// It is ABSENT in pre-~2021 exports, and the fallback is the ambiguous
    /// one: `date` is ISO local time with **no offset** ("2020-08-01T22:01:49")
    /// in the EXPORTING MACHINE's zone, which the export records nowhere at
    /// all. There is no way to recover the true instant, so the least-wrong
    /// reading is the DEVICE's current zone — a person usually exports from
    /// their own machine in their own zone, and the alternative (UTC) is
    /// confidently wrong for everybody who is not in it, which on a late-evening
    /// message moves it to the wrong DAY. The error is bounded by a day either
    /// way and is documented rather than hidden.
    ///
    /// Returns nil rather than guessing when neither field reads. A skipped
    /// message is recoverable by re-importing a better export; a message
    /// stamped `.now` files somebody's 2016 as today's news, and nothing
    /// downstream can ever tell that it did.
    static func timestamp(_ message: [String: Any]) -> Date? {
        instant(unix: message["date_unixtime"], naive: message["date"])
    }

    /// The same reading for `edited_unixtime` / `edited`, which are absent
    /// unless the message really was edited.
    static func editedTimestamp(_ message: [String: Any]) -> Date? {
        instant(unix: message["edited_unixtime"], naive: message["edited"])
    }

    private static func instant(unix: Any?, naive: Any?) -> Date? {
        if let seconds = doubleValue(unix), seconds > 0 {
            return Date(timeIntervalSince1970: seconds)
        }
        guard let text = (naive as? String).map(tidy), !text.isEmpty else { return nil }
        return naiveLocalDate(text)
    }

    /// "2020-08-01T22:01:49" read in the device's own zone. The space-separated
    /// spelling is accepted too — it costs one more attempt and covers a
    /// re-serialised export.
    ///
    /// `en_US_POSIX`, always: a device locale would reinterpret these digits
    /// (a Buddhist or Japanese calendar reads the year differently), which is
    /// the kind of failure that dates an entire import 543 years out while
    /// every row still renders perfectly.
    static func naiveLocalDate(_ raw: String) -> Date? {
        for formatter in [naiveISO, naiveSpaced] {
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }

    private static let naiveISO: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    private static let naiveSpaced: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    // MARK: - Media (schema fact 6)

    /// The sentences Telegram writes into a path field when the file itself was
    /// not exported.
    ///
    /// Matched as SUBSTRINGS, never by equality, for two measured reasons: the
    /// sentence can be PREFIXED by the file's own name (`name + " " +
    /// "(File not included…)"`), and its tail names an exporter setting whose
    /// wording is Telegram's to change. Only the distinctive head of each is
    /// kept here, so a reworded tail cannot turn a placeholder back into a path
    /// that the landing half would then try to open.
    ///
    /// **A `photo` field uses the "File" wording despite its key name** — the
    /// generator shares one placeholder writer across every media kind — so the
    /// same three sentences cover photographs.
    static let mediaPlaceholders = [
        "(File unavailable",
        "(File exceeds maximum size",
        "(File not included",
    ]

    /// A real relative path, or nil for every placeholder and every absence.
    ///
    /// The string is returned EXACTLY as the export spells it, per-chat prefix
    /// and all (`chats/chat_03/photos/…` in a full export, `photos/…` in a
    /// single-chat one). Rebuilding it would mean guessing which of the two
    /// shapes we are in, and guessing wrong yields a path that resolves to
    /// nothing — indistinguishable from an export whose files were left out.
    static func mediaPath(_ raw: Any?) -> String? {
        guard let text = (raw as? String).map(tidy), !text.isEmpty else { return nil }
        for placeholder in mediaPlaceholders where text.contains(placeholder) { return nil }
        return text
    }

    /// What a wordless message WAS.
    ///
    /// Keyed on the presence of the media FIELDS, deliberately not on whether
    /// their paths resolved: an export made with downloading switched off says
    /// "(File not included…)" for every one of them, and reading that as "no
    /// media" would drop every photograph, voice note and sticker in the whole
    /// export — silently, since a dropped message leaves nothing to notice.
    ///
    /// `media_type` has exactly six values and is OMITTED for a generic
    /// document, which is why the default branch exists rather than being an
    /// unreachable fallback. A generic document answers with its own FILE NAME
    /// when it has one: a row reading "quarterly-report.pdf" says something,
    /// and a row reading "File" says nothing at all.
    ///
    /// A photo carries `photo`, `photo_file_size`, `width`, `height` and NO
    /// mime or media type — so it is recognised by its own key and never by a
    /// type string it does not have.
    static func mediaLabel(_ message: [String: Any]) -> String? {
        if message["photo"] != nil { return "Photo" }
        switch (message["media_type"] as? String)?.lowercased() {
        case "sticker": return "Sticker"
        case "video_message": return "Video message"
        case "voice_message": return "Voice message"
        case "animation": return "GIF"
        case "video_file": return "Video"
        case "audio_file": return "Audio"
        default: break
        }
        guard message["file"] != nil else { return nil }
        if let name = (message["file_name"] as? String).map(tidy), !name.isEmpty { return name }
        return "File"
    }

    /// Where a message's own pixels or bytes are, if anywhere. `photo` first,
    /// because a message never carries both.
    static func attachmentPath(_ message: [String: Any]) -> String? {
        mediaPath(message["photo"]) ?? mediaPath(message["file"])
    }

    // MARK: - One message (schema fact 3)

    /// A message as something landable, or nil with the reason counted.
    ///
    /// **The type gate comes FIRST and is the whole safety property here.** An
    /// `unsupported` message is `{id, type: "unsupported"}` — no date, no
    /// `from`, no text — so any read that touches those fields before checking
    /// the type either lands it undated or treats a service message's `actor`
    /// as a speaker. A service message likewise never has `from`: it has
    /// `actor`/`actor_id`/`action`, because it is Telegram narrating itself
    /// (somebody joined, the title changed, a message was pinned) rather than
    /// anybody speaking. Neither becomes an entry.
    static func entry(from message: [String: Any], counts: inout Counts) -> Entry? {
        switch (message["type"] as? String)?.lowercased() {
        case "message":
            break
        case "service":
            counts.service += 1
            return nil
        case "unsupported":
            counts.unsupported += 1
            return nil
        default:
            // A type this build does not know. Counted with the unsupported
            // ones rather than landed on a guess — the §307 rule that a silent
            // drop is the failure, not the refusal.
            counts.unsupported += 1
            return nil
        }

        guard let id = intValue(message["id"]) else {
            counts.malformed += 1
            return nil
        }
        guard let date = timestamp(message) else {
            counts.undated += 1
            return nil
        }

        var text = body(of: message)
        var label = mediaLabel(message)
        // A poll has no `text` of its own — its words live under `poll`, and a
        // parser that only reads `text` drops every poll as empty.
        if text.isEmpty, let poll = pollText(message["poll"]) {
            text = poll
            if label == nil { label = "Poll" }
        }

        // Neither words nor media is genuinely nothing to keep.
        guard !text.isEmpty || label != nil else {
            counts.empty += 1
            return nil
        }

        return Entry(
            id: id,
            date: date,
            text: text,
            mediaLabel: label,
            isPhoto: message["photo"] != nil,
            mediaPath: attachmentPath(message),
            links: links(in: message),
            forwardedFrom: (message["forwarded_from"] as? String)
                .map(tidy)
                .flatMap { $0.isEmpty ? nil : $0 },
            replyTo: intValue(message["reply_to_message_id"])
        )
    }

    // MARK: - Who is speaking

    /// The exporting account, as the export names itself.
    ///
    /// **UNMEASURED, and it fails safe.** `personal_information` is documented
    /// to carry the account's own names; whether it carries `user_id` in every
    /// era is not something this project can check, so a miss falls through to
    /// the name heuristic in `isMine` rather than mislabelling anybody.
    struct SelfIdentity: Equatable {
        var id: String?
        var name: String?

        var isKnown: Bool { id != nil || name != nil }
    }

    static func selfIdentity(in root: Any) -> SelfIdentity {
        guard let dict = root as? [String: Any],
              let info = dict["personal_information"] as? [String: Any]
        else { return SelfIdentity() }

        let id = intValue(info["user_id"]).map { "user\($0)" }
        let parts = [info["first_name"], info["last_name"]]
            .compactMap { ($0 as? String).map(tidy) }
            .filter { !$0.isEmpty }
        let name = parts.isEmpty ? nil : parts.joined(separator: " ")
        return SelfIdentity(id: id, name: name)
    }

    /// `from_id` in one spelling.
    ///
    /// Modern exports write `"user123"` / `"channel123"` / `"chat123"`;
    /// pre-2021 ones write a bare NUMBER. Both are accepted, and a bare number
    /// is read as a user because that is what it was — a chat's own id never
    /// appears in `from_id`. Refusing the legacy form would make every old
    /// export's messages read as somebody else's, which is exactly the case
    /// where "You" matters most.
    static func normalizeFromID(_ raw: Any?) -> String? {
        if let text = (raw as? String).map(tidy), !text.isEmpty {
            if let number = Int(text) { return "user\(number)" }
            return text.lowercased()
        }
        if let number = intValue(raw) { return "user\(number)" }
        return nil
    }

    /// Did the exporting account write this?
    ///
    /// Two tests, and the second exists because the first is not always
    /// available. The id comparison is exact wherever `personal_information`
    /// named an id. Failing that, a PERSONAL chat is named after the other
    /// person by construction, so a message whose `from` is not that name is
    /// yours — a heuristic that holds for 1:1 chats and is deliberately not
    /// extended to groups, where it would label every other member "You".
    ///
    /// The safe default is `false`: attributing somebody else's words to the
    /// person reading them is a worse error than the reverse, and a transcript
    /// that says a name where it could have said "You" is still true.
    static func isMine(_ message: [String: Any], chat kind: ChatKind, name: String,
                       me: SelfIdentity) -> Bool {
        if let mine = me.id, let from = normalizeFromID(message["from_id"]) {
            return from == mine
        }
        if let myName = me.name, let from = (message["from"] as? String).map(tidy),
           !from.isEmpty, from == myName {
            return true
        }
        guard kind == .personal, !name.isEmpty else { return false }
        guard let from = (message["from"] as? String).map(tidy), !from.isEmpty else { return false }
        return from != name
    }

    // MARK: - The whole export

    /// Everything landable in one export.
    ///
    /// `includeMessages` gates DMs, bot chats and groups and is **OFF by
    /// default at every call site** (prd §310's `ImportOptions.includeMessages`
    /// ruling): somebody's private correspondence enters the corpus only
    /// because they said so, above the folder pick, in a control they had to
    /// find. Saved Messages and channels are not gated — the first is the
    /// person's own pile of notes to themselves and is the reason this seat
    /// exists, the second is broadcast media anybody could have followed
    /// instead.
    static func parse(_ root: Any, includeMessages: Bool) -> Parsed {
        var parsed = Parsed()
        let all = chats(in: root)
        guard !all.isEmpty else { return parsed }
        parsed.isExport = true
        parsed.counts.chats = all.count

        let me = selfIdentity(in: root)
        var saved: [Entry] = []

        for chat in all {
            let kind = ChatKind(rawType: chat["type"] as? String)
            guard kind != .other else {
                parsed.counts.chatsSkipped += 1
                continue
            }
            guard let messages = chat["messages"] as? [Any] else {
                parsed.counts.chatsSkipped += 1
                continue
            }
            let name = displayName(of: chat, kind: kind)
            // A chat with no id can still be read — a single-chat export has
            // been seen without one — but it can never be REFERRED to, so a
            // conversation or channel that would need a ref is skipped while a
            // saved message (whose ref is its own id) is not.
            let chatID = intValue(chat["id"])

            switch kind {
            case .savedMessages:
                for message in messages {
                    guard let dict = message as? [String: Any],
                          let entry = entry(from: dict, counts: &parsed.counts) else { continue }
                    saved.append(entry)
                }

            case .channel:
                guard let chatID else {
                    parsed.counts.chatsSkipped += 1
                    continue
                }
                var entries: [Entry] = []
                for message in messages {
                    guard let dict = message as? [String: Any],
                          let entry = entry(from: dict, counts: &parsed.counts) else { continue }
                    entries.append(entry)
                }
                guard !entries.isEmpty else { continue }
                entries.sort { $0.date > $1.date }
                parsed.counts.channelPostsDropped += max(0, entries.count - channelPostCap)
                parsed.channels.append(ChannelChat(
                    id: chatID,
                    name: name,
                    kind: kind,
                    entries: Array(entries.prefix(channelPostCap))
                ))

            case .personal, .bot, .group:
                // NOT counted as skipped: a chat the person did not ask for is
                // not a chat we failed to read, and folding the two together
                // would make the receipt report a healthy default run as
                // dozens of refusals.
                guard includeMessages else { continue }
                guard let chatID else {
                    parsed.counts.chatsSkipped += 1
                    continue
                }
                if let conversation = conversation(from: messages, id: chatID, name: name,
                                                   kind: kind, me: me,
                                                   counts: &parsed.counts) {
                    parsed.conversations.append(conversation)
                }

            case .other:
                continue
            }
        }

        // Newest first, so the cap refuses the OLDEST rather than whatever the
        // export happened to list last.
        saved.sort { $0.date > $1.date }
        parsed.counts.savedDropped = max(0, saved.count - savedCap)
        parsed.savedMessages = Array(saved.prefix(savedCap))

        parsed.conversations.sort { $0.newest > $1.newest }
        parsed.counts.conversationsDropped = max(0, parsed.conversations.count - conversationCap)
        parsed.conversations = Array(parsed.conversations.prefix(conversationCap))

        return parsed
    }

    /// One chat's messages as a single transcript.
    ///
    /// Lines are `"<speaker>: <words>"`, with `"You"` for the exporting
    /// account. A message carrying media and no words says what it was
    /// (`"You sent a photo"`) rather than vanishing — the shape of a
    /// conversation is most of what a transcript is for, and a year of voice
    /// notes rendering as an empty string reads as a chat that never happened.
    private static func conversation(from messages: [Any], id: Int, name: String,
                                     kind: ChatKind, me: SelfIdentity,
                                     counts: inout Counts) -> Conversation? {
        var rows: [(date: Date, line: String)] = []
        for message in messages {
            guard let dict = message as? [String: Any],
                  let entry = entry(from: dict, counts: &counts) else { continue }
            let speaker = isMine(dict, chat: kind, name: name, me: me)
                ? "You"
                : (dict["from"] as? String).map(tidy).flatMap { $0.isEmpty ? nil : $0 } ?? name
            let line: String
            if entry.text.isEmpty, let label = entry.mediaLabel {
                line = "\(speaker) sent a \(label.lowercased())"
            } else {
                line = "\(speaker): \(entry.text)"
            }
            rows.append((date: entry.date, line: line))
        }
        guard !rows.isEmpty else { return nil }

        let ordered = rows.sorted { $0.date < $1.date }
        return Conversation(
            id: id,
            handle: name,
            kind: kind,
            newest: ordered.last?.date ?? .distantPast,
            lines: Array(ordered.suffix(lineCap).map(\.line)),
            // BEFORE the clamp — see `Conversation.total`.
            total: ordered.count
        )
    }

    // MARK: - Shared

    private static func tidy(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A JSON number that may have arrived as a number OR a string — which for
    /// this export is not defensiveness but the schema: `id` is bare while
    /// `date_unixtime` is quoted, and `from_id` changed spelling between eras.
    static func intValue(_ raw: Any?) -> Int? {
        if let value = raw as? Int { return value }
        if let value = raw as? Double, value.magnitude < 9e15 { return Int(value) }
        if let text = (raw as? String).map(tidy), !text.isEmpty { return Int(text) }
        return nil
    }

    private static func doubleValue(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let text = (raw as? String).map(tidy), !text.isEmpty { return Double(text) }
        return nil
    }
}
