import Foundation
import NaturalLanguage
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device language model (iOS 26 Foundation Models) — the free,
/// private agent brain. Only Apple Intelligence devices have it; everywhere
/// else the scoring engine keeps answering, so this is an upgrade, never a
/// requirement.
enum OnDeviceModel {

    /// One plain line for logs and (later) a Support row.
    static var availabilityLine: String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return "Available"
            case .unavailable(.deviceNotEligible):
                return "Unavailable — this device can't run it"
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Unavailable — Apple Intelligence is off in Settings"
            case .unavailable(.modelNotReady):
                return "Unavailable — still downloading"
            case .unavailable(let other):
                return "Unavailable — \(String(describing: other))"
            }
        }
        return "Unavailable — needs iOS 26"
        #else
        return "Unavailable — SDK too old"
        #endif
    }

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        return false
        #else
        return false
        #endif
    }

    // MARK: - Grounded answer

    /// A retrieved thing, flattened to plain text for the model. No SwiftData,
    /// no iOS-26 types — the caller stays version-agnostic.
    struct Candidate {
        let title: String
        let kind: String
        let source: String
        let when: String
        /// A short excerpt of the thing's own body — what the title alone
        /// can't convey (a note's text, a chat's substance). Empty when the
        /// body adds nothing (missing, same as the title, or a bare URL).
        /// Without this the model can only restate titles, which reads as a
        /// generic inventory rather than an answer about what's IN the things.
        var note: String = ""
        /// A screenshot's own downscaled picture (already-encoded JPEG,
        /// ~480pt, q0.7 — `Thing.previewImageData`), 2026-07-21. nil for
        /// every other kind. Only the BYO-key vision path reads this — the
        /// on-device model and `numberedCandidates` stay text-only, so it
        /// carries no @Guide/prompt weight there.
        var imageData: Data? = nil
        /// Whether the SOURCE thing carried a secret anywhere in its full
        /// text (prd §277). Computed by whoever builds the candidate, from
        /// `thing.content` — NOT from `note`, which is a 300-character
        /// excerpt. That distinction is the whole point: a recovery phrase
        /// or key appearing past character 300 leaves `note` clean, and the
        /// keyed agent would then have posted the screenshot's PICTURE with
        /// the secret plainly legible in it.
        var carriesSecret: Bool = false
    }

    /// The model's answer, grounded strictly on the candidates it was handed:
    /// one plain sentence plus which candidates answer, by index into the list
    /// it was given. Plain type, so the caller needs no availability dance.
    struct GroundedAnswer {
        let insight: String
        let picks: [Int]
    }

    /// Composes a grounded answer over the retrieved candidates on the person's
    /// own silicon. The model may only choose among these things and summarize
    /// them — it never invents one, so every row we then paint is a real thing
    /// (the honesty rule holds). Returns nil when the model is unavailable or
    /// errors; the caller then paints the scoring engine's doc — zero
    /// regression on non-Apple-Intelligence devices.
    static func compose(query: String, candidates: [Candidate]) async -> GroundedAnswer? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await FoundationAnswer.compose(query: query, candidates: candidates)
        }
        #endif
        return nil
    }

    /// Streams a short plain synthesis over the retrieved candidates — for open
    /// "what's my week" questions where a summary beats a list. Each element is
    /// the cumulative text so far, so the caller can paint it growing. Grounded
    /// by the prompt: the model may only reference these things, never invent
    /// one (a softer rail than `compose`'s indices, which is why lookups stay
    /// on `compose`). Returns nil when the model is unavailable or the set is
    /// empty; the caller then falls back to the scoring doc — zero regression.
    static func synthesisStream(query: String, candidates: [Candidate]) -> AsyncStream<String>? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), isAvailable, !candidates.isEmpty {
            return FoundationAnswer.synthesisStream(query: query, candidates: candidates)
        }
        #endif
        return nil
    }

    // MARK: - Shared synthesis prompt

    /// The one serialization every model path shares: a numbered line per
    /// thing, with the thing's own text (when it has any) quoted on an
    /// indented line under it. Lives on the ungated enum so the BYO-key path
    /// (AgentAnswer) hands the provider the SAME evidence shape the on-device
    /// model saw — prd §67: the key buys a stronger model, not a different
    /// contract.
    static func numberedCandidates(_ candidates: [Candidate]) -> String {
        candidates.enumerated().map { i, c in
            var line = "\(i + 1). \(c.title) — \(c.kind), from \(c.source), \(c.when)"
            if !c.note.isEmpty { line += "\n   \"\(c.note)\"" }
            return line
        }.joined(separator: "\n")
    }

    /// The synthesis contract both models answer under. `length` is the one
    /// sanctioned divergence: the small on-device model is held to "two or
    /// three plain sentences"; the keyed model may run "a few". Everything
    /// else — grounding, voice, honesty — is one text, so a tuning fix can't
    /// reach one model and miss the other.
    static func synthesisInstructions(length: String) -> String {
        """
        You help someone reflect on the things they have saved. Speak TO them \
        as "you" — never write in the first person, and never narrate as if you \
        are the person ("This week you spent…", never "This week I spent…"). \
        Answer in \(length) using ONLY the things listed. Find the \
        threads ACROSS the things — including the same subject showing up in \
        different apps — and say what the stretch was actually about, drawing \
        on the quoted text for substance. Do NOT walk the list item by item — \
        "You saved X. You saved Y. You saved Z." is wrong; group and \
        synthesize instead. Never invent a thing, a number, a detail, or a \
        connection that isn't in the list. No metaphors, no marketing. Write \
        the answer directly — no preamble like "Here is" or "Summary:", no \
        bullet points, no markdown. If the list is thin, say so plainly.
        """ + LanguageStore.shared.llmLanguageDirective
    }

    /// The synthesis user prompt both models receive, over the same evidence.
    static func synthesisPrompt(query: String, candidates: [Candidate]) -> String {
        """
        Question: "\(query)"

        Their things, numbered (an indented quote under a thing is its own \
        text — everything you may use):
        \(numberedCandidates(candidates))

        Answer the question directly in plain sentences, grounded only in \
        these things.
        """
    }

    // MARK: - Home "Noticed" line

    /// One observational sentence for Home's "Noticed" line — a genuine
    /// cross-thing connection among recent things, or nil when there's none
    /// worth stating. Unlike `compose`/`synthesisStream`, this answers no
    /// question: it's an unprompted observation, and it is ALLOWED to decline
    /// (prd §36c — the old deterministic version was removed precisely because
    /// it manufactured connections; the model saying nothing is the fix). Runs
    /// on a throwaway session so it never touches the composer's conversation.
    /// Returns nil where the model is unavailable — Home then shows no line,
    /// exactly as before this existed.
    static func homeInsight(candidates: [Candidate]) async -> (line: String, picks: [Int])? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await FoundationAnswer.homeInsight(candidates: candidates)
        }
        #endif
        return nil
    }

    /// The Home-insight contract: notice ONE real thread across MORE THAN ONE
    /// thing, in one plain sentence, or write the single word NONE. The NONE
    /// escape and the "never invent" rail are what keep §36c from recurring.
    static var homeInsightInstructions: String {
        """
        You help someone notice a connection across the things they have \
        saved. Speak TO them as "you" — never write in the first person, and \
        never narrate other people by name or as "he"/"she" doing something \
        ("Alex went…", "Sam attended…"); if a thing doesn't plainly state who \
        did what, do not guess. Find ONE genuine thread across MORE THAN ONE \
        of the things: a shared TOPIC, PROJECT, PLACE, or PERSON the things \
        are actually about — a subject that shows up across different apps, or \
        several saves clearly about the same thing. Two items merely being the \
        same KIND (both transactions, both events) or from the same APP is NOT \
        a connection worth noting — that is trivial; skip it. State the thread \
        in ONE short plain sentence, grounded only in these things — no \
        metaphors, no marketing, no preamble, no lists. Do NOT copy or restate \
        a single item. Write ONLY the observation itself — never echo the \
        list's formatting, and never include an app name, a kind label, or a \
        timestamp (no "— Transaction, from Wallet, 12h", no "from the Wallet \
        app"). If there is no real thread worth noting — if the things are \
        unrelated, or the only thing in common is trivial — reply with exactly \
        the single word NONE. A truthful NONE is better than a forced or \
        obvious connection.
        """ + LanguageStore.shared.llmLanguageDirective
    }

    /// The Home-insight user prompt, over the same numbered evidence shape
    /// every model path shares.
    static func homeInsightPrompt(candidates: [Candidate]) -> String {
        """
        Their recent things, numbered (an indented quote under a thing is its \
        own text — everything you may use):
        \(numberedCandidates(candidates))

        Reply with one plain sentence naming a real connection across two or \
        more of these things — plus the numbers of the things it runs \
        across — or the single word NONE.
        """
    }

    // MARK: - Lifecycle

    /// Warms the model so the first Ask doesn't pay the one-time load. Safe to
    /// call repeatedly (idempotent) and non-blocking — a no-op when the model
    /// isn't available. Call at launch and on foreground.
    static func prewarm() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            Task { @MainActor in WarmModel.prewarm() }
        }
        #endif
    }

    /// Releases the warm session so the model's memory can be reclaimed (call
    /// on background); the next `prewarm()` reloads it.
    static func teardown() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            Task { @MainActor in WarmModel.teardown() }
        }
        #endif
    }

    /// Starts a fresh answer CONVERSATION (2026-07-15) — drops the persistent
    /// session so the next Ask begins with no transcript. Called when the
    /// composer opens, so one conversation's turns never bleed into the next.
    /// A no-op where the model isn't available.
    static func resetConversation() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            Task { @MainActor in ConversationModel.reset() }
        }
        #endif
    }
}

#if canImport(FoundationModels)
import FoundationModels

/// Holds a prewarmed session to keep the model resident. We prewarm the *model*
/// rather than reuse one session's transcript across Asks: each Ask is
/// independent, so a shared transcript would leak one answer into the next and
/// eventually overflow the context window. Fresh per-query sessions stay
/// correct; the resident model is what makes them fast. MainActor-isolated so
/// the single warm session is never touched from two threads.
@available(iOS 26.0, *)
@MainActor
enum WarmModel {
    private static var session: LanguageModelSession?

    static func prewarm() {
        guard OnDeviceModel.isAvailable else { return }
        if session == nil { session = LanguageModelSession() }
        session?.prewarm()
    }

    static func teardown() { session = nil }
}

/// The persistent per-conversation session (2026-07-15) — what turns the
/// composer from a series of independent one-shots into a real conversation, so
/// a follow-up ("which of those were from Sam?") is carried by the transcript,
/// not a pronoun heuristic. Reset when the composer opens, so one conversation
/// never bleeds into the next; a shape change (lookup ↔ synthesis) also starts
/// fresh, since their instructions differ. MainActor-isolated so the single
/// session is never touched from two threads (the same rule `WarmModel` keeps).
///
/// Bounded on purpose — a transcript can only grow within ONE conversation, and
/// any turn that overflows the context window (or otherwise errors) drops the
/// session and retries once fresh (see `compose` / `synthesisStream`), so a
/// long conversation degrades to a stateless answer rather than a broken one.
@available(iOS 26.0, *)
@MainActor
enum ConversationModel {
    private static var session: LanguageModelSession?
    /// The instructions the live session was built with — a turn whose
    /// instructions differ (the other answer shape) starts a fresh session.
    private static var key: String?

    /// The session for a turn under `instructions`, and whether it was REUSED
    /// (a continuing conversation) — the caller retries fresh on a reused
    /// session's failure, but not on a brand-new one's (nothing to blame on
    /// history there).
    static func acquire(instructions: String) -> (session: LanguageModelSession, reused: Bool) {
        if let s = session, key == instructions { return (s, true) }
        let s = LanguageModelSession(instructions: instructions)
        session = s; key = instructions
        return (s, false)
    }

    /// Drop the session so the next `acquire` builds fresh — on a new
    /// conversation (`reset`) or after a turn failed on a reused session.
    static func reset() { session = nil; key = nil }
}

/// What the model returns. It writes ONE sentence and lists which things answer,
/// by their number — it cannot return a thing, only point at the ones it was
/// given, so the record stays honest. File-scope (not nested) so the @Generable
/// macro's generated schema/keypaths resolve cleanly.
@available(iOS 26.0, *)
@Generable
struct GroundedAnswerLayout {
    @Guide(description: "One plain sentence answering the question using only the listed things. No metaphors, no lists inside the sentence. If nothing fits, say so plainly.")
    var insight: String
    @Guide(description: "The 1-based numbers of the things that answer the question, most relevant first. Empty if none fit.")
    var picks: [Int]
}

/// The Home "Noticed" line's schema — one field. File-scope (not nested), the
/// same rule `GroundedAnswerLayout` follows, so the @Generable macro's keypaths
/// resolve cleanly (nesting one corrupts the heap; CLAUDE.md).
@available(iOS 26.0, *)
@Generable
struct HomeNoticeLayout {
    @Guide(description: "One plain sentence naming a real connection across two or more of the listed things, grounded only in them. If there is no real connection worth noting, the single word NONE.")
    var line: String
    @Guide(description: "The numbers of the listed things the connection runs across — two or more, from the numbered list. Empty when the line is NONE.")
    var picks: [Int]
}

/// The iOS-26 half — isolated so the plain `OnDeviceModel` API above carries no
/// `@available` and the composer can call it without an availability dance.
@available(iOS 26.0, *)
enum FoundationAnswer {

    @MainActor
    static func compose(query: String, candidates: [OnDeviceModel.Candidate]) async -> OnDeviceModel.GroundedAnswer? {
        guard OnDeviceModel.isAvailable, !candidates.isEmpty else { return nil }

        let numbered = OnDeviceModel.numberedCandidates(candidates)

        let instructions = """
        You help someone find and make sense of the things they have saved. \
        Speak TO them as "you" — never write in the first person, and never \
        narrate as if you are the person ("You saved…", never "I saved…"). \
        Answer only from the things you are given. Never invent a thing or a \
        fact. Keep every word plain — no metaphors, no marketing. If none of \
        the things answer the question, say so plainly and pick none.
        """ + LanguageStore.shared.llmLanguageDirective
        let prompt = """
        Question: "\(query)"

        Their things, numbered (an indented quote under a thing is its own \
        text — use it, don't just repeat the title):
        \(numbered)

        Answer in one plain sentence using only these things, then list the \
        numbers of the things that answer it, most relevant first.
        """

        // Map the model's 1-based numbers to valid 0-based indices, dropping any
        // it hallucinated out of range.
        func run(_ session: LanguageModelSession) async throws -> OnDeviceModel.GroundedAnswer {
            let response = try await session.respond(to: prompt, generating: GroundedAnswerLayout.self)
            let picks = response.content.picks.compactMap { n -> Int? in
                let idx = n - 1
                return candidates.indices.contains(idx) ? idx : nil
            }
            return OnDeviceModel.GroundedAnswer(insight: response.content.insight, picks: picks)
        }

        // The persistent conversation session carries prior turns so a follow-up
        // is understood in context. A failure on a REUSED session (an overflowed
        // transcript, most likely) drops it and retries once fresh — so a long
        // conversation degrades to a stateless answer, never a broken one.
        let (session, reused) = ConversationModel.acquire(instructions: instructions)
        do {
            return try await run(session)
        } catch {
            guard reused else { return nil }
            ConversationModel.reset()
            let (fresh, _) = ConversationModel.acquire(instructions: instructions)
            return try? await run(fresh)
        }
    }

    /// The Home "Noticed" line — a fresh, throwaway session (NOT the shared
    /// `ConversationModel`: Home is not the composer's conversation, and the
    /// two must never bleed into each other). The model writes into a one-field
    /// `@Generable` layout (the same `respond(to:generating:)` path `compose`
    /// uses), declining by putting the single word NONE in the field, which we
    /// map to nil so the caller shows no line. @MainActor to match the other
    /// model paths — the `await respond` yields the main actor for the whole
    /// inference, so this never blocks the UI.
    @MainActor
    static func homeInsight(candidates: [OnDeviceModel.Candidate]) async -> (line: String, picks: [Int])? {
        guard OnDeviceModel.isAvailable, candidates.count >= 3 else { return nil }
        let session = LanguageModelSession(instructions: OnDeviceModel.homeInsightInstructions)
        do {
            let response = try await session.respond(
                to: OnDeviceModel.homeInsightPrompt(candidates: candidates),
                generating: HomeNoticeLayout.self)
            let text = response.content.line.trimmingCharacters(in: .whitespacesAndNewlines)
            #if DEBUG
            NSLog("[Casberi] homeInsight raw → %@ picks=%@", text,
                  response.content.picks.map(String.init).joined(separator: ","))
            #endif
            // The model declined (NONE), or wrote too little to be a real
            // observation — either way, no line.
            let stripped = text.trimmingCharacters(in: CharacterSet(charactersIn: ".!\"' "))
            if stripped.isEmpty || stripped.uppercased() == "NONE" || text.count < 12 {
                return nil
            }
            // Echo guard (honesty rail): the small model sometimes copies one
            // candidate line back verbatim — scaffolding and all ("Sent … —
            // Transaction, from Wallet, 12h") — instead of connecting several
            // things. That's a single-item restatement, never the cross-thing
            // observation this line promises, so treat it as a decline.
            if echoesACandidate(text, candidates) { return nil }
            // Third-person guard (voice rail, 2026-07-17): the residual bad
            // output narrates a person by name — "Sam attended a dinner…" —
            // usually FABRICATING the action (measured: the model invented
            // attendance the things never stated). The contract speaks TO the
            // person about their things; a sentence whose subject is somebody's
            // name breaks the voice even when true, so it declines.
            if startsWithPersonName(text) { return nil }
            // The model's own indices, 1-based in the prompt → 0-based into
            // `candidates`, out-of-range dropped. An empty set is fine — the
            // line stands, it just isn't a door.
            let picks = response.content.picks
                .filter { (1...candidates.count).contains($0) }
                .map { $0 - 1 }
            return (text, picks)
        } catch {
            return nil
        }
    }

    /// True when the sentence's first word is a person's name (NLTagger's
    /// `.personalName`) — the shape of the third-person narration the voice
    /// rail bans. First word only: a name deeper in the sentence ("Dinner with
    /// Sam and the Lisbon flight…") is the model correctly citing a thing.
    private static func startsWithPersonName(_ text: String) -> Bool {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var isPerson = false
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word,
                             scheme: .nameType,
                             options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, _ in
            isPerson = (tag == .personalName)
            return false   // first word decides
        }
        return isPerson
    }

    /// True when `text` is (or contains) a verbatim echo of one candidate — its
    /// title alone, its whole serialized line, or the "— <kind>, from <source>,"
    /// metadata fragment that only ever appears in the list's formatting. A real
    /// observation contains none of those, so this only ever fires on a copy.
    private static func echoesACandidate(_ text: String, _ candidates: [OnDeviceModel.Candidate]) -> Bool {
        func norm(_ s: String) -> String {
            s.lowercased()
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "  ", with: " ")
                .trimmingCharacters(in: CharacterSet(charactersIn: ".!\"' "))
        }
        let out = norm(text)
        guard !out.isEmpty else { return true }
        var titleHits = 0
        for c in candidates {
            let title = norm(c.title)
            let source = norm(c.source)
            if title == out { return true }
            if norm("\(c.title) — \(c.kind), from \(c.source), \(c.when)") == out { return true }
            // Serialization / app-name leaks — pure list formatting, never a
            // synthesized sentence: ", from ChatGPT," (the numbered line's
            // metadata) or "the Wallet app" (an app name the line must not
            // carry). The prompt bans naming apps, so echoing one is a decline.
            if out.contains(", from \(source)") { return true }
            if out.contains("\(source) app") { return true }
            // Count verbatim titles present — three or more means the model
            // pasted a list of things rather than connecting them (two titles
            // can be a legitimate connective sentence, "your X and your Y", so
            // the threshold sits above that to avoid rejecting real prose).
            if !title.isEmpty, out.contains(title) { titleHits += 1 }
        }
        return titleHits >= 3
    }

    /// Streams a grounded plain-text synthesis. Bridges the model's response
    /// stream to a plain `AsyncStream<String>` (cumulative snapshots) so the
    /// caller needs no iOS-26 types and can consume it on the main actor.
    static func synthesisStream(query: String, candidates: [OnDeviceModel.Candidate]) -> AsyncStream<String> {
        // The shared contract (prd §67) — one instructions/prompt pair for the
        // on-device model and the BYO-key path, differing only in length.
        let instructions = OnDeviceModel.synthesisInstructions(length: "two or three plain sentences")
        let prompt = OnDeviceModel.synthesisPrompt(query: query, candidates: candidates)

        return AsyncStream { continuation in
            // MainActor so the persistent conversation session is touched from
            // one thread only (the `WarmModel`/`ConversationModel` rule).
            let task = Task { @MainActor in
                let (session, reused) = ConversationModel.acquire(instructions: instructions)
                var yielded = false
                do {
                    for try await partial in session.streamResponse(to: prompt) {
                        yielded = true
                        continuation.yield(partial.content)
                    }
                } catch {
                    // A failure on a REUSED session before anything streamed is
                    // most likely an overflowed transcript — drop it and stream
                    // once fresh, so a long conversation still answers. A refusal
                    // or a mid-stream error just ends the stream; the caller
                    // falls back to the scoring doc if nothing arrived.
                    if reused && !yielded {
                        ConversationModel.reset()
                        let (fresh, _) = ConversationModel.acquire(instructions: instructions)
                        do {
                            for try await partial in fresh.streamResponse(to: prompt) {
                                continuation.yield(partial.content)
                            }
                        } catch { }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
#endif
