import Foundation
import SwiftData

/// The `Thing` half of the agent sheet (prd §367, 2026-08-12) — everything
/// `AgentSheet.swift` deliberately cannot see.
///
/// The split is the house pattern (`SocialSheet`/`SocialSheetSource`,
/// `StripeRoom`/`StripeRoomSource`): the judgement is Foundation-only so a
/// harness can compile it whole, and the reads that touch SwiftData and the
/// catalog live here.
///
/// "Only lookups, so there is nothing to test" is what this header said until
/// 2026-09-19, and it was wrong twice over — a lookup that FILTERS carries a
/// claim about what is in the field, and both filters here were reading tag
/// arrays whose real shape `Thing.init` decides two files away (it prepends
/// the kind's `typeTag`). Both shipped. `agent-sheet-selftest.sh` compiles
/// this file whole now, against the real `Thing`, and builds its fixtures
/// through `Thing.init` rather than by hand — a fixture assembled by hand
/// cannot see anything the initializer does.
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
    /// The four keyed seats joined on 2026-09-19 (prd §839) — a conversation
    /// you have in the composer lands as a chat thing, so its row wears the
    /// chat anatomy exactly as an imported one does.
    static let chatSources: Set<String> = ["ChatGPT", "Claude", "Claude Code", "Gemini",
                                           "Bankr", "Venice", "OpenRouter", "Grok"]

    /// Seats whose rows GROW — a re-import appends to the same row rather than
    /// replacing it, so "this is everything" would be a claim with a shelf
    /// life. Claude Code alone: an export is finished by the time you have it,
    /// a session on your own disk is not.
    /// The keyed seats joined for the same reason from the other direction
    /// (prd §839): a conversation in the composer is upserted on every answer,
    /// so a row you are looking at can gain turns while you read it. "This is
    /// everything" would be a claim with a shelf life — here, of seconds.
    static let growingSources: Set<String> = ["Claude Code",
                                              "Bankr", "Venice", "OpenRouter", "Grok",
                                              "Claude", "ChatGPT", "Gemini"]

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
            grantRef: Self.isGrantRef(thing.sourceRef),
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
    /// `ClaudeCodeImport` passes `["Session", <project>]` — but `Thing.init`
    /// PREPENDS the kind's own type tag, so what is stored is
    /// `["Chat", "Session", <project>]`, and for the three seats that pass no
    /// tags at all it is `["Chat"]` alone. Reading "the tag that isn't the
    /// facet" without excluding the type tag returned "Chat" for every agent
    /// row in the corpus — the head said "in Chat" on every sheet and Claude
    /// Code's real project never reached it or `stripProject`.
    ///
    /// The type tag is taken from the thing's OWN kind rather than matched
    /// against the literal "Chat", so a seat that starts landing a different
    /// kind cannot reintroduce this.
    ///
    /// Read from a STORED field and never sliced out of the title, which is
    /// `WorkStage`'s central rule: a project guessed from a separator lands in
    /// a labelled slab row, where being wrong is indistinguishable from being
    /// right.
    static func project(for thing: Thing) -> String? {
        let facet = thing.kind.typeTag
        return thing.tags.first { $0 != "Session" && $0 != facet && !$0.isEmpty }
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

    /// A 1Claw grant row, by its ref.
    ///
    /// INLINED here on 2026-09-06, when the 1Claw bridge was deleted with the
    /// other retired seats. The seat is gone and nothing lands a grant any
    /// more — but the rows somebody already has do NOT go with it, and a
    /// sheet that stopped recognising them would degrade a shipped row into
    /// the generic shape. Two string literals is a cheaper way to keep that
    /// promise than keeping a bridge alive to answer them.
    static func isGrantRef(_ ref: String?) -> Bool {
        ref?.hasPrefix("1claw:policy:") ?? false
    }

    /// The verbs the key was granted, off the row's own tags.
    ///
    /// "Grant" is the facet naming the SHAPE; every other tag on the row is a
    /// permission the API reported, stamped in the API's own words so nothing
    /// here has to translate a security decision.
    ///
    /// The kind's own type tag comes off too — `Thing.init` prepends it, so a
    /// grant row (`.link`) stores `["Link", "Grant", <verbs…>]` and "Link" was
    /// being listed to the reader as a permission the key holds. Derived from
    /// the thing's kind, not matched against the literal "Link", so the same
    /// row landed under a different kind cannot bring it back.
    static func permissions(for thing: Thing) -> [String] {
        let facet = thing.kind.typeTag
        return thing.tags.filter { $0 != "Grant" && $0 != facet && !$0.isEmpty }
    }
}
