import Foundation
import SwiftData
#if canImport(FoundationModels)
import FoundationModels
#endif

/// What a long conversation was ABOUT (prd §282, 2026-08-02) — a lazy sweep
/// that reads an imported thread on the person's own silicon and writes two or
/// three sentences into `enrichedText`.
///
/// It exists because the imported chats are the worst-retrieved things in the
/// corpus, and for a structural reason rather than a tuning one. A ChatGPT or
/// Claude export lands as a transcript: thousands of words of two voices
/// talking, whose TITLE is whatever the first message happened to open with.
/// The sentence embedding caps at 800 characters (`EmbeddingIndex.indexText`),
/// so a two-hour debugging session is indexed by its opening pleasantries, and
/// the keyword scan can only match words that literally appear — it cannot
/// know the thread was about deployment when the word "deployment" was never
/// typed. Ask "what was I working through with the auth bug", and the one
/// thing that answers it is the one thing that doesn't come back.
///
/// A summary fixes both at once, which is why it lands in `enrichedText`
/// rather than anywhere visible: that field is retrieval-only by ruling
/// (2026-07-15), it is read by `EmbeddingIndex.indexText` (so the vector
/// finally reflects the whole thread) and by the retriever's content scan (so
/// the words the summary uses become matchable), and it never shows up as a
/// title, a tag, or a row. **Nothing a model wrote is displayed by this
/// feature.** The person still reads their own transcript; the model's words
/// only ever help find it.
///
/// Setting `enrichedText` clears `embedding` per that field's own contract, so
/// the next `EmbeddingIndex` sweep re-indexes the thread on the richer text.
enum ThreadDigest {

    /// Below this a transcript is already well served by its own text — the
    /// 800-character index window covers most of it and a summary would add
    /// nothing the embedding doesn't already see.
    static let minimumLength = 1_200

    /// How much of a transcript the model reads. A long thread costs context
    /// and time; the head and the tail carry the subject and the outcome,
    /// which is what a retrieval summary needs.
    static let readWindow = 4_000

    /// Whether a thing is a thread worth digesting: a long conversation that
    /// hasn't been digested and doesn't already carry enrichment from
    /// somewhere else (a scraped article, a pool's anonymity cover). The
    /// import RECEIPT is excluded — it's the app's own row about an import,
    /// and summarizing "312 saved · 1,204 comments" would put our voice in a
    /// field meant to describe the person's things.
    static func wants(_ thing: Thing) -> Bool {
        guard thing.isLive, thing.kind == .chat else { return false }
        guard thing.enrichedText == nil else { return false }
        guard !Corpus.isImportReceipt(thing) else { return false }
        return thing.content.count >= minimumLength
    }

    /// The text handed to the model — the head and, for a long thread, the
    /// tail, marked as a cut so the model doesn't read a gap as a topic change.
    static func excerpt(of content: String) -> String {
        guard content.count > readWindow else { return content }
        let half = readWindow / 2
        let head = String(content.prefix(half))
        let tail = String(content.suffix(half))
        return head + "\n\n[…]\n\n" + tail
    }

    // MARK: - Sweep

    @MainActor private static var sweeping = false

    /// Digest a bounded number of threads. Bounded hard and low: each one is a
    /// real inference over thousands of characters, and this runs on a
    /// foreground alongside every bridge refresh — the rest arrive on later
    /// opens, the same contract every other sweep in this app keeps.
    ///
    /// Returns how many threads gained a summary. A thread the model declines
    /// or errors on is left alone and retried on a later pass; unlike the
    /// screenshot naming sweep there is no "asked already" ledger, because a
    /// long transcript that failed once is worth another try and there is no
    /// cheap wrong answer to guard against — `enrichedText` staying nil is
    /// exactly the pre-existing behaviour.
    @MainActor
    @discardableResult
    static func sweep(context: ModelContext, limit: Int = 3) async -> Int {
        guard AgentLibrarian.available, !sweeping else { return 0 }
        sweeping = true
        defer { sweeping = false }

        // `#Predicate` can't compare Codable enums, so the kind filter runs in
        // memory — bounded by asking only for undigested rows, newest first.
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.enrichedText == nil },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.fetchLimit = 200
        let candidates = ((try? context.fetch(descriptor)) ?? [])
            .filter(wants)
            .prefix(limit)
        guard !candidates.isEmpty else { return 0 }

        var digested = 0
        for thing in candidates {
            // Re-check liveness: the awaits below give a heal or a CloudKit
            // delete room to land between fetching this batch and writing to
            // one of its rows (the `ScreenshotIngest.heal` lesson).
            guard thing.isLive else { continue }
            let text = excerpt(of: thing.content)
            let title = thing.title
            guard let summary = await summarize(title: title, transcript: text) else { continue }
            guard thing.isLive else { continue }
            thing.enrichedText = summary
            // The field's own contract: richer text means the vector is stale.
            thing.embedding = nil
            digested += 1
        }
        if digested > 0 {
            context.saveHonestly()
            NSLog("[Casberi] ThreadDigest: summarized %d threads", digested)
        }
        return digested
    }

    /// Two or three sentences saying what a thread was about. nil when
    /// neither engine could summarize it.
    ///
    /// The on-device model answers whenever it exists and its nil is FINAL —
    /// see `ScreenshotNaming.name` for why paying a key to second-guess a
    /// local decline is the wrong trade. The key is reached only where there
    /// is no local model at all (2026-08-06, `AgentLibrarian`).
    static func summarize(title: String, transcript: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), OnDeviceModel.isAvailable {
            return await ThreadDigestModel.summarize(title: title, transcript: transcript)
        }
        #endif
        return await AgentLibrarian.summarize(title: title, transcript: transcript)
    }
}

#if canImport(FoundationModels)

/// The digest layout — one field, file-scope (never nested; a nested
/// `@Generable` emits broken keypaths and corrupts the heap, CLAUDE.md).
@available(iOS 26.0, *)
@Generable
struct ThreadDigestLayout {
    @Guide(description: "Two or three plain sentences saying what this conversation was about: the subject, what was being worked out, and how it ended if the text says. Use only what the transcript says. If the transcript is too thin to summarize, the single word NONE.")
    var summary: String
}

@available(iOS 26.0, *)
enum ThreadDigestModel {
    @MainActor
    static func summarize(title: String, transcript: String) async -> String? {
        guard OnDeviceModel.isAvailable else { return nil }
        // A throwaway session — never `ConversationModel`, whose transcript
        // belongs to the composer. A sweep quietly digesting threads in the
        // background must not end up as context in somebody's next Ask.
        let session = LanguageModelSession(instructions: """
        You summarize a saved conversation so it can be FOUND again later. \
        Write two or three plain sentences naming the subject, what was being \
        worked out, and how it ended if the text says so. Name the specific \
        things the conversation was actually about — tools, places, people, \
        problems — because those words are what someone will search for. Use \
        only what the transcript says: never invent a fact, an outcome, or a \
        name. No preamble like "This conversation", no bullet points, no \
        markdown. If the transcript is too thin to summarize honestly, reply \
        with exactly the single word NONE.
        """ + LanguageStore.shared.llmLanguageDirective)
        do {
            let response = try await session.respond(
                to: """
                Title: "\(title)"

                Transcript:
                \(transcript)

                Write the summary, or NONE.
                """,
                generating: ThreadDigestLayout.self)
            let text = response.content.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            let stripped = text.trimmingCharacters(in: CharacterSet(charactersIn: ".!\"' "))
            guard !stripped.isEmpty, stripped.uppercased() != "NONE", text.count >= 20 else {
                return nil
            }
            return text
        } catch {
            return nil
        }
    }
}
#endif
