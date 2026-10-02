import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's language models (iOS 26 Foundation Models), in two roles.
///
/// **The on-device model READS; it no longer answers (2026-10-01, user: "we
/// no longer are using on device intelligence as an agent").** `isAvailable`
/// still gates the librarian's reading aids elsewhere — screenshot naming,
/// thread digests, screenshot facts, the Addresses verdict — and
/// `expandQuery` widens a search. Its answering half went: the prewarm, the
/// Today brief's day read, Home's "Noticed" line, the cluster names, and the
/// composer's answer falling back to the phone.
///
/// **The composer's ANSWER is Apple Intelligence's, on Private Cloud Compute
/// (prd §833).** `compose` and `synthesisStream` run only when that seat is on
/// and can answer (`AskModel.usesCloud`); a cloud failure is the answer's
/// failure, never a retry on the phone. Everywhere else the scoring engine
/// answers, as it always did on a device without the model.
///
/// `Candidate`, `numberedCandidates` and the synthesis contract are also the
/// keyed agents' evidence shape (`AgentAnswer`), which is why they live here.
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

    /// Composes a grounded answer over the retrieved candidates on Apple
    /// Intelligence (prd §833). The model may only choose among these things
    /// and summarize them — it never invents one, so every row we then paint
    /// is a real thing (the honesty rule holds). Returns nil when the seat
    /// cannot answer or the call fails; the caller then paints the scoring
    /// engine's doc.
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
    /// on `compose`). Returns nil when Apple Intelligence cannot answer or the
    /// set is empty; the caller then falls back to the scoring doc.
    static func synthesisStream(query: String, candidates: [Candidate]) -> AsyncStream<String>? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), AskModel.usesCloud, !candidates.isEmpty {
            return FoundationAnswer.synthesisStream(query: query, candidates: candidates)
        }
        #endif
        return nil
    }

    // MARK: - Semantic recall (query expansion)

    /// Rewrites a short or paraphrased query into a few CONCRETE alternative
    /// phrasings, to widen a keyword search over the person's things
    /// (2026-08-07). This is the semantic-recall step the retriever can't do on
    /// its own: `EmbeddingIndex`'s sentence vectors contribute almost nothing on
    /// a real corpus (measured, `-rankSweep` returned byte-identical results
    /// across every floor), so search is keyword-only in practice and a
    /// paraphrase — "that beach place" for a note that says "coastal property" —
    /// finds nothing. The model supplies the missing words; the caller re-runs
    /// the SAME deterministic retriever over them and unions anything new (the
    /// honesty rail is untouched — every hit is still a real ranked `Thing`).
    /// Returns nil off Apple-Intelligence devices, on a decline, or when the
    /// query is already concrete — the caller then searches the literal words
    /// alone (zero regression).
    static func expandQuery(_ query: String) async -> [String]? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await FoundationAnswer.expandQuery(query)
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
    /// sanctioned divergence: Apple's model is held to "two or three plain
    /// sentences"; the keyed model may run "a few". Everything
    /// else — grounding, voice, honesty — is one text, so a tuning fix can't
    /// reach one model and miss the other.
    static func synthesisInstructions(length: String) -> String {
        """
        You help someone reflect on the things they have saved. Address them \
        as "you" — the things are theirs, not yours. Answer in \(length), \
        grounded only in the things listed: the list is the whole evidence, so \
        a thing, number, detail or connection that isn't in it doesn't belong \
        in the answer. The useful reading is what the things add up to — the \
        same subject showing up in different apps, a thread running across \
        several of them — drawn from the quoted text for substance. The app \
        shows the list beneath your answer, so say what it amounts to rather \
        than walking it item by item. Plain words, no preamble, and no \
        markdown: the answer is drawn as plain text. If the list is thin, say \
        so.
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

/// The persistent per-conversation session (2026-07-15) — what turns the
/// composer from a series of independent one-shots into a real conversation, so
/// a follow-up ("which of those were from Sam?") is carried by the transcript,
/// not a pronoun heuristic. Reset when the composer opens, so one conversation
/// never bleeds into the next; a shape change (lookup ↔ synthesis) also starts
/// fresh, since their instructions differ. MainActor-isolated so the single
/// session is never touched from two threads.
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
    /// Whether the live session runs on Private Cloud Compute (prd §833). The
    /// callers are gated on `AskModel.usesCloud`, so this is true for every
    /// session they get; it stays in the key so a seat switched off and on
    /// mid-conversation starts fresh.
    private static var cloud = false

    /// The session for a turn under `instructions`, whether it was REUSED
    /// (a continuing conversation), and whether it runs in the cloud — the
    /// caller retries fresh on a reused session's failure, but not on a
    /// brand-new one's (nothing to blame on history there). A cloud failure
    /// is never retried on the phone (2026-10-01).
    static func acquire(instructions: String)
        -> (session: LanguageModelSession, reused: Bool, cloud: Bool) {
        let wantsCloud = AskModel.usesCloud
        if let s = session, key == instructions, cloud == wantsCloud { return (s, true, cloud) }
        let made = AskModel.session(instructions: instructions)
        session = made.session; key = instructions; cloud = made.cloud
        return (made.session, false, made.cloud)
    }

    /// Drop the session so the next `acquire` builds fresh — on a new
    /// conversation (`reset`) or after a turn failed on a reused session.
    static func reset() { session = nil; key = nil; cloud = false }
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

    @MainActor
    static func compose(query: String, candidates: [OnDeviceModel.Candidate]) async -> OnDeviceModel.GroundedAnswer? {
        guard AskModel.usesCloud, !candidates.isEmpty else { return nil }

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
        //
        // A CLOUD failure (prd §833) — no network, the quota, the service — is
        // the answer's failure: it used to answer on the phone instead, and the
        // phone no longer answers (2026-10-01). The caller paints the matches.
        let (session, reused, cloud) = ConversationModel.acquire(instructions: instructions)
        do {
            let answer = try await run(session)
            AskModel.markAnswered(cloud: cloud)
            return answer
        } catch {
            guard reused else { return nil }
            ConversationModel.reset()
            let (fresh, _, freshCloud) = ConversationModel.acquire(instructions: instructions)
            guard let answer = try? await run(fresh) else { return nil }
            AskModel.markAnswered(cloud: freshCloud)
            return answer
        }
    }

    /// Expands a query into up to three concrete alternative phrasings — the
    /// iOS-26 half of `OnDeviceModel.expandQuery`. A throwaway session (never
    /// the composer's conversation), plain-text out, parsed defensively: one
    /// phrase per line, two-to-five words, the original query and any duplicate
    /// dropped, `NONE` mapped to nothing. Fails to nil throughout, so the caller
    /// searches the literal words alone on any decline.
    ///
    /// NOT `@MainActor` (reversed 2026-08-09): measured on device, a pinned
    /// `session.respond(to:)` froze the calling thread for the whole
    /// inference rather than suspending, and this throwaway session touches no
    /// shared main-actor state.
    static func expandQuery(_ query: String) async -> [String]? {
        guard OnDeviceModel.isAvailable else { return nil }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return nil }
        let instructions = """
        You widen a search query over someone's saved things. Given a query, \
        write up to THREE alternative phrasings that mean the SAME thing in \
        DIFFERENT words — a synonym, the concrete noun behind a vague one, the \
        plain term behind slang. Each on its own line, two to four words, no \
        punctuation, no numbering, no explanation, and do not just repeat the \
        original words. If the query is already concrete and no useful \
        alternative exists, reply with the single word NONE.
        """ + LanguageStore.shared.llmLanguageDirective
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(to: "Query: \"\(trimmed)\"")
            let lower = trimmed.lowercased()
            let strip = CharacterSet(charactersIn: " -•*\t\"'.").union(.whitespaces)
            var out: [String] = []
            var seen = Set<String>()
            for raw in response.content.components(separatedBy: CharacterSet(charactersIn: "\n,;")) {
                let phrase = raw.trimmingCharacters(in: strip)
                let key = phrase.lowercased()
                guard !phrase.isEmpty, key != "none", key != lower else { continue }
                let words = phrase.split(separator: " ")
                guard (1...5).contains(words.count) else { continue }
                if seen.insert(key).inserted { out.append(phrase) }
                if out.count == 3 { break }
            }
            #if DEBUG
            NSLog("[Casberi] expandQuery \"%@\" → %@", trimmed,
                  out.isEmpty ? "(none)" : out.joined(separator: " | "))
            #endif
            return out.isEmpty ? nil : out
        } catch {
            return nil
        }
    }

    /// Streams a grounded plain-text synthesis. Bridges the model's response
    /// stream to a plain `AsyncStream<String>` (cumulative snapshots) so the
    /// caller needs no iOS-26 types and can consume it on the main actor.
    static func synthesisStream(query: String, candidates: [OnDeviceModel.Candidate]) -> AsyncStream<String> {
        // The shared contract (prd §67) — one instructions/prompt pair for
        // Apple Intelligence and the BYO-key path, differing only in length.
        let instructions = OnDeviceModel.synthesisInstructions(length: "two or three plain sentences")
        let prompt = OnDeviceModel.synthesisPrompt(query: query, candidates: candidates)

        return AsyncStream { continuation in
            // MainActor so the persistent conversation session is touched from
            // one thread only (the `ConversationModel` rule).
            let task = Task { @MainActor in
                let (session, reused, cloud) = ConversationModel.acquire(instructions: instructions)
                var yielded = false
                do {
                    for try await partial in session.streamResponse(to: prompt) {
                        if !yielded { AskModel.markAnswered(cloud: cloud) }
                        yielded = true
                        continuation.yield(partial.content)
                    }
                } catch {
                    // A failure on a REUSED session before anything streamed is
                    // most likely an overflowed transcript — drop it and stream
                    // once fresh, so a long conversation still answers. A cloud
                    // failure is never retried on the phone (2026-10-01). A
                    // refusal or a mid-stream error just ends the stream; the
                    // caller falls back to the scoring doc if nothing arrived.
                    if reused && !yielded {
                        ConversationModel.reset()
                        let (fresh, _, freshCloud) = ConversationModel.acquire(
                            instructions: instructions)
                        do {
                            var first = true
                            for try await partial in fresh.streamResponse(to: prompt) {
                                if first { AskModel.markAnswered(cloud: freshCloud); first = false }
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
