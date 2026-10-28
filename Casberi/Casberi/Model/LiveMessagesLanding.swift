import Foundation
import SwiftData

/// The landing half of a live messages read (prd §1244) — one function for
/// X and Instagram, so the two seats draw one row shape and grow it one way.
/// The parse is `LiveConversation.swift` and the two `…LiveMessages` files.
@MainActor
enum LiveMessagesLanding {
    struct Outcome: Equatable {
        /// Conversations landed for the first time.
        var added = 0
        /// Conversations already here that took new lines.
        var grew = 0
        var news: Int { added + grew }
    }

    /// Lands each conversation as ONE `.chat` thing under `refPrefix +
    /// conversation.id`, or appends the lines newer than its row's own time.
    /// A conversation whose row was deleted here stays deleted until it
    /// lands again on a later read — the ref dedupe asks the store, never a
    /// memory of past reads.
    static func land(_ conversations: [LiveConversation], source: String,
                     refPrefix: String, context: ModelContext) -> Outcome {
        let landed = landedConversations(source: source, refPrefix: refPrefix, context: context)
        var outcome = Outcome()
        var touched = false
        for conversation in conversations {
            let ref = refPrefix + conversation.id
            if let existing = landed[ref] {
                // `isLive`: a CloudKit delete can tombstone a row between the
                // fetch and this write (`InstagramLive.landSaves`).
                guard existing.isLive else { continue }
                if let merge = LiveMessages.merge(content: existing.content,
                                                  newest: existing.capturedAt,
                                                  count: existing.messageCount,
                                                  lines: conversation.lines) {
                    existing.content = merge.content
                    existing.capturedAt = merge.newest
                    existing.messageCount = merge.count
                    existing.embedding = nil
                    outcome.grew += 1
                    touched = true
                }
                // A renamed group, a new display name, a new face.
                if existing.title != conversation.title {
                    existing.title = conversation.title
                    touched = true
                }
                if let handle = conversation.handle, existing.authorHandle != handle {
                    existing.authorHandle = handle
                    touched = true
                }
                if let avatar = conversation.avatar, existing.authorAvatarURL != avatar {
                    existing.authorAvatarURL = avatar
                    touched = true
                }
                continue
            }
            guard let merge = LiveMessages.merge(content: nil, newest: nil, count: nil,
                                                 lines: conversation.lines) else { continue }
            let thing = Thing(
                kind: .chat,
                title: conversation.title,
                content: merge.content,
                source: source,
                capturedAt: merge.newest,
                tags: ["Conversation"],
                sourceRef: ref)
            thing.messageCount = merge.count
            // WHO you are talking to (§707's rule): the row's face is the
            // other person on a one-to-one; a group keeps the source mark.
            thing.authorHandle = conversation.handle
            thing.authorAvatarURL = conversation.avatar
            context.insert(thing)
            SpotlightIndex.index([thing])
            outcome.added += 1
            touched = true
        }
        if touched { context.saveHonestly() }
        return outcome
    }

    /// The newest line each landed conversation holds, by ref — what a seat
    /// that pages its own history (Telegram, §1575) reads back to.
    static func newest(source: String, refPrefix: String,
                       context: ModelContext) -> [String: Date] {
        landedConversations(source: source, refPrefix: refPrefix, context: context)
            .filter { $0.value.isLive }
            .mapValues(\.capturedAt)
    }

    /// The conversations already here, by ref — scoped by PREFIX, never by
    /// source alone: an archive is thousands of rows and the inbox is twenty.
    private static func landedConversations(source: String, refPrefix: String,
                                            context: ModelContext) -> [String: Thing] {
        let prefix = refPrefix
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate {
            $0.source == source && ($0.sourceRef?.starts(with: prefix) ?? false)
        })
        var map: [String: Thing] = [:]
        for thing in (try? context.fetch(descriptor)) ?? [] {
            if let ref = thing.sourceRef { map[ref] = thing }
        }
        return map
    }
}
