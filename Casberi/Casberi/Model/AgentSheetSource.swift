import Foundation
import SwiftData

/// The `Thing` half of the agent sheet (prd §367, 2026-08-12) — everything
/// `AgentSheet.swift` deliberately cannot see.
///
/// The split is the house pattern (`SocialSheet`/`SocialSheetSource`,
/// `StripeRoom`/`StripeRoomSource`): the judgement is Foundation-only so a
/// harness can compile it whole, and the reads that touch SwiftData and the
/// catalog live here, where there is no judgement to test — only lookups.
enum AgentSheetSource {

    /// The catalog's `Agent` group, as a source test — but only the seats that
    /// actually LAND something. Venice, OpenRouter, Grok and Bankr are keys
    /// rather than sources: they buy a better answer and never write a row, so
    /// there is no sheet of theirs to shape.
    ///
    /// Cursor is absent on purpose and it is the interesting absence: its runs
    /// are `.link` rows with facet tags, and `WorkStage` has drawn them as a
    /// receipt since this morning. A row can only have one anatomy, and the
    /// one it already has is right.
    ///
    /// A literal set rather than a `BridgeCatalog` walk — this is read on every
    /// sheet open, and the catalog answer is a linear scan over sixty-odd
    /// offers. Guarded against the catalog by `agent-sheet-selftest.sh`, so an
    /// `Agent` seat that starts landing chats fails the build rather than
    /// silently losing its anatomy.
    static let chatSources: Set<String> = ["ChatGPT", "Claude", "Claude Code", "Gemini"]

    /// Seats whose rows GROW — a re-import appends to the same row rather than
    /// replacing it, so "this is everything" would be a claim with a shelf
    /// life. Claude Code alone: an export is finished by the time you have it,
    /// a session on your own disk is not.
    static let growingSources: Set<String> = ["Claude Code"]

    // MARK: - Shape

    /// What anatomy this thing's sheet wears, or nil for none.
    ///
    /// Liveness: reads stored properties, so every caller must already hold a
    /// live model — which the sheet does (its `init` and `body` both guard,
    /// and this is only ever reached from inside those guards).
    static func shape(for thing: Thing) -> AgentSheet.Shape? {
        AgentSheet.shape(facts(for: thing))
    }

    static func facts(for thing: Thing) -> AgentSheet.Facts {
        AgentSheet.Facts(
            kind: thing.kind.rawValue,
            socialShaped: SocialSheetSource.shape(for: thing) != nil,
            grantRef: OneClawFetch.isGrantRef(thing.sourceRef),
            // Parsed rather than counted from a field, because the field is
            // exactly what can be missing: a chat landed before `enrichedText`
            // was written carries a count and no body, and one whose importer
            // never stamped a count carries a body and no number. Either alone
            // is a conversation.
            turns: turns(for: thing).count,
            counted: thing.messageCount)
    }

    /// The stored transcript as turns — nil-safe, and empty for a source whose
    /// speaker labels we do not know (`AgentSheet.assistant` returns nil, and
    /// guessing is how a stranger's words end up under your name).
    static func turns(for thing: Thing) -> [AgentSheet.Turn] {
        AgentSheet.turns(thing.enrichedText,
                         assistant: AgentSheet.assistant(for: thing.source))
    }

    // MARK: - The conversation reading

    static func conversation(for thing: Thing) -> AgentSheet.Conversation {
        AgentSheet.conversation(.init(
            source: thing.source,
            title: thing.title,
            ask: thing.content,
            transcript: thing.enrichedText,
            project: project(for: thing),
            counted: thing.messageCount,
            opened: thing.capturedAt,
            growing: growingSources.contains(thing.source)))
    }

    /// The project this session ran in, off `ClaudeCodeImport`'s own tag.
    ///
    /// The tags are `["Session", <project>]` — so the project is "the tag that
    /// isn't the facet". Read from a STORED field and never sliced out of the
    /// title, which is `WorkStage`'s central rule: a project guessed from a
    /// separator lands in a labelled slab row, where being wrong is
    /// indistinguishable from being right.
    static func project(for thing: Thing) -> String? {
        thing.tags.first { $0 != "Session" && !$0.isEmpty }
    }

    // MARK: - The grant reading

    @MainActor
    static func grant(for thing: Thing, now: Date = .now) -> AgentSheet.Grant {
        AgentSheet.grant(.init(
            title: thing.title,
            path: thing.summary,
            vault: thing.authorHandle,
            permissions: permissions(for: thing),
            granted: thing.capturedAt,
            expires: thing.dueAt,
            now: now))
    }

    /// The verbs the key was granted, off the row's own tags.
    ///
    /// `OneClawFetch.grantTag` is the facet naming the SHAPE ("Grant"); every
    /// other tag on the row is a permission the API reported, stamped in the
    /// API's own words so nothing here has to translate a security decision.
    static func permissions(for thing: Thing) -> [String] {
        thing.tags.filter { $0 != OneClawFetch.grantTag && !$0.isEmpty }
    }
}
