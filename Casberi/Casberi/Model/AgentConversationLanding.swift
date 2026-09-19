import Foundation
import SwiftData

/// Where a conversation with a KEYED agent becomes a thing (prd §839).
///
/// **Why this file exists: a keyed seat had no room, so it had no door.** A
/// person adds a Bankr key and nothing appears in the dock — a chip is earned
/// by owning a row (`MainSurface.newestPerSource`) or by being a live-room
/// seat (`LiveRoomSources`, the three devnets), and an agent that answered in
/// the composer and stored nothing qualified for neither. The only way back to
/// it was Accounts → Bankr → "Ask Bankr", three taps into a settings screen,
/// which is where the Apple Intelligence seat was found stranded on 2026-09-19.
/// The answer is not a new kind of chip. It is that a conversation IS a thing,
/// and always was on the import side.
///
/// **It lands the shape the four importers already land**, deliberately and to
/// the letter: `kind: .chat`, the transcript in `enrichedText` as
/// `"<Speaker>: <text>"` lines joined by `\n`, `messageCount` counted before
/// the clamp, the opening ask as `content`. That is not tidiness — it is the
/// whole reason this costs four small registry entries instead of a feature.
/// `AgentSheet.turns` parses it back, `ExcerptRow` draws it, the room leads
/// with it, `Corpus.earnsRoom` lets it through, and the swipe walk and
/// `ChipWalker` pick it up, none of which needed a line written for it here.
/// §418 records what happens when a second reader of this format is written
/// instead of reused, so `ChatTranscript.make` is called rather than copied.
///
/// **A conversation is the COMPOSER SESSION, not a turn.** `RootShell`'s
/// `keyedHistory` accumulates `AgentTurn` pairs and is cleared when the
/// composer lowers, so that run is the unit, and `conversationID` is minted
/// alongside it. The row is UPSERTED on every answer rather than written once
/// at the end: a conversation abandoned by swiping the app away is still the
/// one you had, and a row that only exists after a clean exit is a row people
/// lose. Upserting also means the room's newest thing is the conversation you
/// are in, which is what makes the lede honest while you are still typing.
///
/// **Nothing here is a model's opinion.** The question is what the person
/// typed and the answer is what the provider returned; this file adds a
/// speaker label and a clamp and no words of its own. Typed text still never
/// saves (the design law) — what lands is an EXCHANGE that happened, the same
/// standing as a reply that arrived, which is why this is a landing and not
/// the composer growing a save button.
enum AgentConversationLanding {

    /// The speaker a keyed provider's words wear in the transcript.
    ///
    /// It is `AgentProvider.agent` — the agent a person knows, not the
    /// company — because `AgentSheet.assistant(for:)` reads the SOURCE back
    /// and the two have to agree exactly or the parse returns nothing and the
    /// sheet silently draws one enormous turn under the reader's name. The
    /// three big keys resolve to "Claude", "ChatGPT" and "Gemini", which are
    /// the import sources too, so a keyed Claude conversation lands in the
    /// same room as an imported one. That is the intended answer rather than a
    /// collision to break: it is the same agent, and a person who imported
    /// their history and then talked to it here has one Claude, not two.
    static func source(for provider: AgentProvider) -> String { provider.agent }

    /// What a conversation had HERE is keyed by, and the one thing that tells
    /// it apart from an imported one.
    ///
    /// A Claude export and a keyed Claude chat share a source on purpose
    /// (§839: one agent, one room), so the source cannot separate them and the
    /// ref must — the importers stamp `chatgpt:` / `claude:` / `claudecode:` /
    /// `gemini:`. `AgentChatView` fences its query on this; without it the
    /// Chat tile opens showing an imported conversation as the live one.
    static let refPrefix = "agentchat:"

    /// Land or update the conversation `turns` belongs to.
    ///
    /// `@MainActor` because it is handed the main `ModelContext` — walking one
    /// off the main actor is a SIGSEGV that reads like the liveness class
    /// (CLAUDE.md), and every caller is already on it.
    ///
    /// Returns the thing, so a caller that wants to open it does not fetch it
    /// back by ref.
    @MainActor
    @discardableResult
    static func record(turns: [AgentTurn], provider: AgentProvider,
                       conversationID: UUID, in context: ModelContext) -> Thing? {
        guard let opening = turns.first?.question.trimmingCharacters(in: .whitespacesAndNewlines),
              !opening.isEmpty else { return nil }
        let source = source(for: provider)
        let assistant = AgentSheet.assistant(for: source) ?? source
        // Through the constant, never a second literal: the reader fences its
        // query on it, and two spellings of one prefix is one of them silently
        // matching nothing.
        let ref = refPrefix + conversationID.uuidString

        // Flattened to the importers' own pair-per-turn shape. A trailing ask
        // with no answer yet is NOT written: the upsert runs after an answer
        // settles, so there is never a pending turn here — and writing one
        // would make `messageCount` disagree with what the sheet can parse.
        var lines: [(speaker: String, text: String)] = []
        for turn in turns {
            let q = turn.question.trimmingCharacters(in: .whitespacesAndNewlines)
            let a = turn.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !q.isEmpty { lines.append((AgentSheet.readerLabel, q)) }
            if !a.isEmpty { lines.append((assistant, a)) }
        }
        let transcript = ChatTranscript.make(lines)
        guard !transcript.isEmpty else { return nil }

        let title = IngestSupport.titleLine(opening)
        // The importers' own rule: the opening ask is the body UNLESS the
        // title is already that same line, in which case a row would print it
        // twice (`ClaudeImport`).
        let body = title == opening ? "" : String(opening.prefix(200))

        let existing = FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef == ref })
        let thing: Thing
        if let found = (try? context.fetch(existing))?.first {
            thing = found
            thing.title = title
            thing.content = body
        } else {
            thing = Thing(kind: .chat, title: title, content: body,
                          source: source, capturedAt: .now, sourceRef: ref)
            context.insert(thing)
        }
        // `capturedAt` moves to the latest exchange on purpose — a growing
        // conversation is the newest thing in its room while it is happening,
        // which is what the room's lede is for.
        thing.capturedAt = .now
        // The embedding and topics were computed from a shorter transcript and
        // are now stale; `ChatImportLanding` clears them for the same reason.
        if thing.enrichedText != transcript.text {
            thing.enrichedText = transcript.text
            thing.embedding = nil
            thing.topicsAt = nil
        }
        thing.messageCount = transcript.messages
        SpotlightIndex.index([thing])
        return thing
    }
}
