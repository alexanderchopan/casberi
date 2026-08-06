import Foundation
import SwiftData
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Naming a screenshot the heuristic couldn't (prd §282, 2026-08-02).
///
/// `ScreenshotTitle.from` picks the first OCR line with three or more words,
/// and §218 already paid for why it works that way: Vision returns regions
/// top-to-bottom, the top of a screenshot is chrome, and first-passing-line
/// retitled three different home-screen shots "Fitness". The three-word rule
/// fixed that case. It cannot fix the two it leaves behind:
///
///   • **No line qualifies.** A settings pane, a chart, a map, a receipt in
///     columns — every line is one or two words, so `from` returns nil and the
///     row wears "Screenshot" forever. On a screenshot-heavy corpus this is a
///     wall of identical rows.
///   • **A qualifying line is the wrong one.** The first three-word line is
///     often a nav header or a cookie banner. It reads as a title, so nothing
///     downstream can tell it was a bad one.
///
/// The model reads the whole text at once and names the shot — which is the
/// one thing a first-N-lines rule structurally cannot do, since the answer is
/// usually a relationship between lines rather than any single line.
///
/// **The honesty rail is the same one §218 set, enforced here rather than
/// assumed.** A title is a claim about what a thing IS, so the model is told
/// to use only words the text contains, and — more importantly — a returned
/// title is REJECTED unless most of its words really do appear in the OCR
/// text (`grounded`). A model that decides a settings screen is "Wi-Fi
/// preferences" when neither word is on screen gets no say; the row keeps
/// saying "Screenshot", which was always the honest answer.
enum ScreenshotNaming {

    /// A title is weak when it says nothing a person could pick out of a list:
    /// the placeholder itself, or one or two words (a nav label, a widget
    /// name — the §218 failure shape).
    static func isWeak(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == ScreenshotTitle.placeholder { return true }
        return trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).count <= 2
    }

    /// Whether a proposed title is actually SUPPORTED by the text it claims to
    /// summarize: at least two thirds of its words (ignoring very short ones)
    /// appear in the OCR text. This is what keeps a plausible invention out of
    /// a title slot — the model's fluency is exactly the thing that makes a
    /// wrong title unnoticeable.
    static func grounded(_ title: String, in text: String) -> Bool {
        func words(_ s: String) -> [String] {
            s.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 }
        }
        let candidate = words(title)
        guard !candidate.isEmpty else { return false }
        let haystack = Set(words(text))
        let hits = candidate.filter { haystack.contains($0) }.count
        return Double(hits) / Double(candidate.count) >= 0.66
    }

    // MARK: - Asked ledger

    /// Rows we have already put to the model, so a decline isn't re-asked on
    /// every foreground forever. Ids only — no titles, no text. Capped, oldest
    /// dropped: this is a "don't repeat work" note, not a record worth keeping.
    private static let askedKey = "screenshot.modelNamed"
    private static let askedCap = 2_000

    private static func asked() -> [String] {
        UserDefaults.standard.stringArray(forKey: askedKey) ?? []
    }

    private static func markAsked(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        var all = asked()
        all.append(contentsOf: ids)
        if all.count > askedCap { all.removeFirst(all.count - askedCap) }
        UserDefaults.standard.set(all, forKey: askedKey)
    }

    // MARK: - Sweep

    @MainActor private static var sweeping = false

    /// Name a bounded number of weakly-titled screenshots. Bounded low for the
    /// same reason `ThreadDigest` is: each row is a real inference, and this
    /// runs on a foreground beside every bridge refresh.
    ///
    /// Deliberately its own sweep rather than a branch inside
    /// `ScreenshotIngest.heal`: heal walks PHAssets and is throttled around
    /// that cost, while this needs only the `content` an earlier pass already
    /// wrote — the same split, and the same reasoning, as
    /// `ScreenshotTopics.healTopics`.
    @MainActor
    @discardableResult
    static func sweep(context: ModelContext, limit: Int = 3) async -> Int {
        guard AgentLibrarian.available, !sweeping else { return 0 }
        sweeping = true
        defer { sweeping = false }

        let descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Photos" && $0.ocrAt != nil },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        let seen = Set(asked())
        // Kind filter runs in memory — `#Predicate` can't compare Codable enums.
        let rows = ((try? context.fetch(descriptor)) ?? [])
            .filter {
                $0.kind == .screenshot && $0.isLive
                    && !$0.content.isEmpty
                    && isWeak($0.title)
                    && !seen.contains($0.id.uuidString)
            }
            .prefix(limit)
        guard !rows.isEmpty else { return 0 }

        var named = 0
        var reindex: [Thing] = []
        var askedNow: [String] = []
        for thing in rows {
            guard thing.isLive else { continue }
            let text = thing.content
            askedNow.append(thing.id.uuidString)
            guard let title = await name(text: text) else { continue }
            // The rail: only words the screenshot actually shows.
            guard grounded(title, in: text) else { continue }
            guard thing.isLive, isWeak(thing.title) else { continue }
            thing.title = title
            // The words changed, so the vector and the Spotlight donation are
            // both stale.
            thing.embedding = nil
            reindex.append(thing)
            named += 1
        }
        markAsked(askedNow)
        if named > 0 {
            context.saveHonestly()
            SpotlightIndex.index(reindex)
            NSLog("[Casberi] ScreenshotNaming: named %d screenshots", named)
        }
        return named
    }

    /// A short title for a screenshot, from its OCR text. nil when neither
    /// engine could name it.
    ///
    /// The on-device model answers whenever it exists, and its nil is FINAL
    /// (2026-08-06): it returns nil both for "unavailable" and for a
    /// deliberate NONE, and paying a key to second-guess a correct decline is
    /// spending money to make the app worse. The key is reached only where
    /// there is no local model at all — which is the whole case
    /// `AgentLibrarian` exists for.
    static func name(text: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), OnDeviceModel.isAvailable {
            return await ScreenshotNameModel.name(text: text)
        }
        #endif
        return await AgentLibrarian.name(text: text)
    }
}

#if canImport(FoundationModels)

/// The title layout — one field, file-scope (never nested; a nested
/// `@Generable` emits broken keypaths and corrupts the heap, CLAUDE.md).
@available(iOS 26.0, *)
@Generable
struct ScreenshotNameLayout {
    @Guide(description: "Three to eight plain words naming what this screenshot shows, built only from words that appear in the text. If the text says too little to name it, the single word NONE.")
    var title: String
}

@available(iOS 26.0, *)
enum ScreenshotNameModel {
    @MainActor
    static func name(text: String) async -> String? {
        guard OnDeviceModel.isAvailable else { return nil }
        let excerpt = String(text.prefix(1_500))
        // Throwaway session — never the composer's `ConversationModel`.
        let session = LanguageModelSession(instructions: """
        You name a screenshot from the text read out of it, so its owner can \
        pick it out of a list months later. Write three to eight plain words. \
        Build the name out of words that actually appear in the text — a \
        person, a place, an app, a subject it names. Never invent a subject the \
        text does not contain, and never describe the picture ("a screenshot \
        of…"); just name the thing. No punctuation at the end, no quotes. If \
        the text is only interface chrome — buttons, times, battery, menu \
        labels — and says nothing about a subject, reply with exactly the \
        single word NONE. NONE is the right answer more often than not.
        """ + LanguageStore.shared.llmLanguageDirective)
        do {
            let response = try await session.respond(
                to: "Text read out of the screenshot:\n\(excerpt)\n\nName it in a few plain words, or NONE.",
                generating: ScreenshotNameLayout.self)
            let title = response.content.title
                .trimmingCharacters(in: CharacterSet(charactersIn: ".!\"' \n"))
            guard !title.isEmpty, title.uppercased() != "NONE",
                  title.count >= 4, title.count <= 80 else { return nil }
            return title
        } catch {
            return nil
        }
    }
}
#endif
