import Foundation
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
    /// (AIAnswer) hands the provider the SAME evidence shape the on-device
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

/// The iOS-26 half — isolated so the plain `OnDeviceModel` API above carries no
/// `@available` and the composer can call it without an availability dance.
@available(iOS 26.0, *)
enum FoundationAnswer {

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

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt, generating: GroundedAnswerLayout.self)
            // Map the model's 1-based numbers to valid 0-based indices, dropping
            // any it hallucinated out of range.
            let picks = response.content.picks.compactMap { n -> Int? in
                let idx = n - 1
                return candidates.indices.contains(idx) ? idx : nil
            }
            return OnDeviceModel.GroundedAnswer(insight: response.content.insight, picks: picks)
        } catch {
            return nil
        }
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
            let task = Task {
                do {
                    let session = LanguageModelSession(instructions: instructions)
                    for try await partial in session.streamResponse(to: prompt) {
                        continuation.yield(partial.content)
                    }
                } catch {
                    // A refusal or error just ends the stream; the caller falls
                    // back to the scoring doc if nothing arrived.
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
#endif
