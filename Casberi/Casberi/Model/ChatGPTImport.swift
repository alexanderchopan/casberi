import Foundation
import SwiftData

/// The ChatGPT bridge (2026-07-07) — a one-time import, exactly as the offer
/// has always said: OpenAI offers no live read, so the person's own data
/// export is the sanctioned way in. The export's `conversations.json` parses
/// into chat things — one per conversation, titled as the person titled it,
/// dated when it last moved. Re-imports dedupe on the conversation id.
enum ChatGPTImport {

    struct Summary {
        var imported = 0
        var skipped = 0
        /// Conversations already here that GAINED something on this pass —
        /// the retrieval transcript and the message count, for rows landed by
        /// a build that threw both away (2026-08-08). The social bridges'
        /// "the dedupe hit heals" rule: without it this change reaches only
        /// conversations imported from today on, and every chat already in
        /// the corpus stays a title and one line forever. A re-import is the
        /// ONLY thing that can reach them — no foreground sweep can, because
        /// the export folder is a temporary scoped pick and the words exist
        /// nowhere but inside it.
        var healed = 0
        /// Conversations the cap refused. Reported rather than swallowed: a
        /// truncated import and a complete one are otherwise the same
        /// sentence (§307/§309).
        var dropped = 0
        /// Conversations whose transcript hit `ChatTranscript.cap` — read
        /// whole, stored short. Counted for the same reason as `dropped`.
        var clamped = 0
        var failed = false
    }

    /// The newest N conversations. Deliberately NOT raised to the §309 caps
    /// (5,000/10,000) in the same pass that gave these rooms their text: this
    /// importer builds every row and saves ONCE, on the main actor, so a 20×
    /// raise is a 20× main-thread hold. The rooms that were raised got
    /// `ImportCommit`'s chunk-and-yield in the same commit, and adopting it
    /// here means `run` becomes `async`, which changes all three import
    /// screens' call sites. What was in reach today is making the refusal
    /// VISIBLE — which is the half of §309 that a person can act on.
    static let conversationCap = 500

    /// Parses a `conversations.json` (or a JSON export fragment) and lands
    /// each conversation as one chat thing.
    @MainActor
    static func run(data: Data, context: ModelContext) -> Summary {
        guard let root = try? JSONSerialization.jsonObject(with: data),
              let conversations = root as? [[String: Any]] else {
            return Summary(failed: true)
        }

        // `thingsByRef`, not `existingSourceRefs` (2026-08-08): a ref SET can
        // only answer "already here", and a conversation landed before this
        // build needs to be REPAIRED, not skipped. Snapchat's §309 change,
        // one room over.
        let existing = IngestSupport.thingsByRef(context, source: "ChatGPT")

        // Newest first, capped.
        let sorted = conversations.sorted {
            (($0["update_time"] as? Double) ?? ($0["create_time"] as? Double) ?? 0)
            > (($1["update_time"] as? Double) ?? ($1["create_time"] as? Double) ?? 0)
        }.prefix(conversationCap)

        var summary = Summary()
        summary.dropped = max(0, conversations.count - conversationCap)
        for convo in sorted {
            let title = (convo["title"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty else { summary.skipped += 1; continue }

            let stamp = (convo["update_time"] as? Double)
                ?? (convo["create_time"] as? Double)
            let id = (convo["id"] as? String)
                ?? (convo["conversation_id"] as? String)
                ?? "\(title)-\(stamp ?? 0)"
            let ref = "chatgpt:\(id)"

            let script = transcript(convo)
            if script.clamped { summary.clamped += 1 }

            if let already = existing[ref] {
                // A HELD `Thing` — guard liveness before any stored read
                // (the ForEach/`isLive` corollary chain; a CloudKit-merged
                // duplicate can be deduped away under an open import).
                guard already.isLive else { summary.skipped += 1; continue }
                if ChatImportLanding.apply(script, to: already) {
                    summary.healed += 1
                } else {
                    summary.skipped += 1
                }
                continue
            }

            let thing = Thing(
                kind: .chat,
                title: title,
                // UNCHANGED, deliberately: `content` is the opening ask and
                // nothing else. It is what `ChatBubbles` draws and what
                // several screens treat as display copy, so the conversation
                // goes to `enrichedText` — retrieval-only by the 2026-07-15
                // ruling — where it feeds `EmbeddingIndex.indexText` and the
                // retriever without changing a pixel.
                content: firstUserLine(convo),
                source: "ChatGPT",
                capturedAt: stamp.map { Date(timeIntervalSince1970: $0) } ?? .now,
                sourceRef: ref
            )
            context.insert(thing)
            ChatImportLanding.apply(script, to: thing)
            SpotlightIndex.index([thing])
            summary.imported += 1
        }
        if summary.imported > 0 || summary.healed > 0 { context.saveHonestly() }
        return summary
    }

    // MARK: - The conversation itself

    /// Every message that was really said, in the order it was said.
    ///
    /// **`mapping` is a GRAPH, not a list** — each node names its `parent` and
    /// its `children`, and a regenerated answer forks a branch. Iterating
    /// `mapping.values` (which is what the opening-ask reader below does, and
    /// can afford to, since it sorts by time afterwards) hands back a
    /// dictionary's arbitrary order: a transcript built that way is the right
    /// words in the wrong sequence, which reads as a scrambled chat and is
    /// invisible to every check that only counts rows.
    ///
    /// The walk goes UP from `current_node` — the leaf ChatGPT itself
    /// considers current — and reverses, so abandoned regenerations are left
    /// out by construction rather than interleaved. `nodeCap` and the seen-set
    /// bound it: this is somebody's data file, and a cycle in it must cost a
    /// truncation, not a hang.
    static func turns(_ convo: [String: Any]) -> [(speaker: String, text: String)] {
        guard let mapping = convo["mapping"] as? [String: [String: Any]],
              !mapping.isEmpty else { return [] }

        var chain: [[String: Any]] = []
        if let leaf = convo["current_node"] as? String, mapping[leaf] != nil {
            var cursor: String? = leaf
            var seen = Set<String>()
            while let id = cursor, chain.count < nodeCap,
                  seen.insert(id).inserted, let node = mapping[id] {
                chain.append(node)
                cursor = node["parent"] as? String
            }
            chain.reverse()
        } else {
            // No `current_node` (an older export, or a fragment). Walk DOWN
            // from the root, taking the LAST child at each fork: ChatGPT
            // appends a regeneration as a new child, so the newest branch is
            // the one `current_node` would have pointed at. A guess, and said
            // to be one — but a guess that agrees with the normal path rather
            // than one that contradicts it.
            var cursor = rootID(of: mapping)
            var seen = Set<String>()
            while let id = cursor, chain.count < nodeCap,
                  seen.insert(id).inserted, let node = mapping[id] {
                chain.append(node)
                cursor = (node["children"] as? [String])?.last
            }
        }
        return chain.compactMap(turn(in:))
    }

    /// The node with no parent in this mapping. An export that lost its root
    /// row would otherwise strand the whole walk, so a node whose named parent
    /// isn't here counts as one too.
    private static func rootID(of mapping: [String: [String: Any]]) -> String? {
        let roots = mapping.filter { _, node in
            guard let parent = node["parent"] as? String else { return true }
            return mapping[parent] == nil
        }
        // Sorted so a file with several stranded roots imports identically
        // every time — a dictionary's order is not stable across launches,
        // and a transcript that changes between re-imports would heal forever.
        return roots.keys.sorted().first
    }

    /// One node as a spoken turn, or nil when it isn't one.
    private static func turn(in node: [String: Any]) -> (speaker: String, text: String)? {
        guard let message = node["message"] as? [String: Any],
              let author = message["author"] as? [String: Any],
              let role = author["role"] as? String,
              let speaker = speakerName(role) else { return nil }
        // ChatGPT hides its own scaffolding in the same graph — the system
        // preamble, the "user context" block, the tool chatter around a
        // search. It flags them rather than filing them elsewhere.
        if let metadata = message["metadata"] as? [String: Any],
           (metadata["is_visually_hidden_from_conversation"] as? Bool) == true {
            return nil
        }
        let text = messageText(message)
        return text.isEmpty ? nil : (speaker, text)
    }

    /// Who said it. `system` and `tool` are chrome, not conversation, and
    /// return nil — landing them would put the prompt scaffolding and the
    /// output of a web search into a room labelled as the person's chats.
    private static func speakerName(_ role: String) -> String? {
        switch role {
        case "user": return "You"
        case "assistant": return "ChatGPT"
        default: return nil
        }
    }

    /// A message's words. `content_type` is the gate: `text` and
    /// `multimodal_text` are prose, while `code`, `execution_output`,
    /// `tether_browsing_display` and `user_editable_context` (the custom
    /// instructions, filed under the `user` role) are machinery. `parts` is a
    /// mixed array in the multimodal case — an image is a dictionary — so only
    /// the strings are read.
    private static func messageText(_ message: [String: Any]) -> String {
        guard let content = message["content"] as? [String: Any] else { return "" }
        let type = (content["content_type"] as? String) ?? "text"
        guard type == "text" || type == "multimodal_text" else { return "" }
        let parts = (content["parts"] as? [Any]) ?? []
        return parts.compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// The whole conversation, flattened and clamped.
    static func transcript(_ convo: [String: Any]) -> ChatTranscript {
        ChatTranscript.make(turns(convo))
    }

    /// A bound on the graph walk. Far past any real conversation — it exists
    /// so a malformed file costs a truncation instead of the app.
    private static let nodeCap = 4_000

    /// The opening ask — the one line that reminds you what the chat was.
    private static func firstUserLine(_ convo: [String: Any]) -> String {
        guard let mapping = convo["mapping"] as? [String: [String: Any]] else { return "" }
        var earliest: (time: Double, text: String)?
        for node in mapping.values {
            guard let message = node["message"] as? [String: Any],
                  let author = message["author"] as? [String: Any],
                  author["role"] as? String == "user",
                  let content = message["content"] as? [String: Any],
                  let parts = content["parts"] as? [Any],
                  let text = parts.first as? String,
                  !text.isEmpty else { continue }
            let time = (message["create_time"] as? Double) ?? .greatestFiniteMagnitude
            if earliest == nil || time < earliest!.time {
                earliest = (time, text)
            }
        }
        guard var line = earliest?.text else { return "" }
        line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return line.count > 200 ? String(line.prefix(200)) + "…" : line
    }
}

/// A conversation flattened for RETRIEVAL — shared by all three chat imports
/// (2026-08-08), because the three exports disagree about everything except
/// this: a chat is an ordered list of who said what, and until now none of the
/// three kept any of it.
///
/// What was stored before was a title and the opening ask. Everything else —
/// every answer, every follow-up, every name and number inside the
/// conversation — was parsed and thrown away at import. So the corpus could
/// not find a chat by anything said in it, `EmbeddingIndex` had one line to
/// index, and no topic map was possible because there was no text to map.
///
/// Foundation-only on purpose: `scripts/chatimport-selftest.sh` compiles this
/// as shipped, and a `Thing` in here would end that. The landing lives in
/// `ChatImportLanding` below.
struct ChatTranscript {
    /// Speaker-prefixed, oldest first, already clamped.
    let text: String
    /// Every turn the conversation holds — counted BEFORE the clamp, so it
    /// survives it. This is the only moment the true number exists: nothing
    /// downstream can recover it from a stored transcript, which is why
    /// `Thing.messageCount` is a field and not a computed line count (the
    /// `SnapchatImport.Conversation.total` reasoning).
    let messages: Int
    /// The clamp really cut something. Counted by the importer and reported,
    /// so "read whole, stored short" can't read as "that was all of it".
    let clamped: Bool

    /// The retrieval body's ceiling, in characters. `ObsidianNote`'s
    /// `retrievalLimit` is the precedent — the same job in the same store, at
    /// the same order of magnitude. Nothing renders this field, so the only
    /// cost of a larger one is the store (and CloudKit); the only cost of a
    /// smaller one is a long chat findable by its first half alone.
    static let cap = 8_000

    /// Oldest first, deliberately — the opposite of `SnapchatImport`'s
    /// newest-biased clamp, and for the reason that clamp gives: a Snapchat
    /// thread is an open-ended friendship where the recent end is the live
    /// one, while a chat is a DOCUMENT that opens with the ask it exists to
    /// answer. Cut a chat from the front and you lose the subject.
    static func make(_ turns: [(speaker: String, text: String)]) -> ChatTranscript {
        let joined = turns
            .map { "\($0.speaker): \($0.text)" }
            .joined(separator: "\n")
        return ChatTranscript(text: String(joined.prefix(cap)),
                              messages: turns.count,
                              clamped: joined.count > cap)
    }

    var isEmpty: Bool { text.isEmpty }
}

/// Where a transcript meets the store. One writer for all three imports, so a
/// first landing and a re-import can never disagree about what a chat row
/// carries.
enum ChatImportLanding {

    /// Fills the retrieval body and the message count. Returns true when
    /// something really changed — an identical re-import must read as "already
    /// here", never as a heal.
    @MainActor
    @discardableResult
    static func apply(_ transcript: ChatTranscript, to thing: Thing) -> Bool {
        var changed = false
        let body = transcript.isEmpty ? nil : transcript.text
        if thing.enrichedText != body {
            thing.enrichedText = body
            // A rewritten retrieval body invalidates BOTH marks. The vector
            // was computed from the words that were there before, and
            // `topicsAt` is a "we looked" mark and not a "we looked correctly"
            // one (§320) — a row stamped when its only text was one line has
            // been read, and read wrongly.
            thing.embedding = nil
            thing.topicsAt = nil
            changed = true
        }
        // Never overwrite a real count with a zero: a conversation whose
        // messages we couldn't read tells us nothing about how many it had.
        if transcript.messages > 0, thing.messageCount != transcript.messages {
            thing.messageCount = transcript.messages
            changed = true
        }
        return changed
    }
}
