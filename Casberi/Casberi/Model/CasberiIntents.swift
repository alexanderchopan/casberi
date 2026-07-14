import AppIntents
import SwiftData

/// App Intents — the capture and the synthesis, reachable from Shortcuts,
/// Siri phrasing, and the Action Button without opening the app. The same
/// two moves the app itself leads with: save a thing, hear the week.
struct SaveThingIntent: AppIntent {
    static let title: LocalizedStringResource = "Save to Casberi"
    static let description = IntentDescription(
        "Saves text or a link as a thing — no app, no destination decision.")

    @Parameter(title: "Text", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    /// The app this capture came from — a per-app automation passes its own
    /// name ("Weather", "Messages") so the thing lands under that source chip
    /// instead of a flat "Shortcuts" pile. Defaults to "Shortcuts" for the
    /// generic Save action, so existing shortcuts keep working unchanged.
    @Parameter(title: "Source", default: "Shortcuts")
    var source: String

    static var parameterSummary: some ParameterSummary {
        Summary("Save \(\.$text)") {
            \.$source
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let from = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let thing = Capture.thing(from: text,
                                        source: from.isEmpty ? "Shortcuts" : from) else {
            return .result(dialog: "There was nothing to save.")
        }
        let container = try SharedStore.container()
        let context = ModelContext(container)
        context.insert(thing)
        try context.save()
        SpotlightIndex.index([thing])
        return .result(dialog: "Saved. It's in your feed.")
    }
}

/// The hero rule as a sentence — what Home leads with, spoken back.
struct WeekSynthesisIntent: AppIntent {
    static let title: LocalizedStringResource = "What's my week"
    static let description = IntentDescription(
        "One line about what your things are up to.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = try SharedStore.container()
        let context = ModelContext(container)
        let things = (try? context.fetch(FetchDescriptor<Thing>())) ?? []
        guard !things.isEmpty else {
            return .result(dialog: "Nothing yet — save a thing and your week starts.")
        }

        let typeTags = Set(ThingKind.allCases.map(\.typeTag))
        var buckets: [String: Int] = [:]
        for thing in things {
            for tag in thing.tags where !typeTags.contains(tag) {
                buckets[tag, default: 0] += 1
            }
        }
        let top = buckets.sorted {
            $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key
        }.first

        if let top, top.value >= 2 {
            let sources = Set(things.filter { $0.tags.contains(top.key) }.map(\.source)).count
            return .result(dialog:
                "\(top.key) fills your week — \(top.value) things across \(sources) app\(sources == 1 ? "" : "s").")
        }
        return .result(dialog:
            "Your things are landing — \(things.count) so far.")
    }
}

/// Search from anywhere (prd §67 goal ④) — the corpus as a Shortcuts value,
/// pipeable into the rest of an automation. Matching is the plain kind
/// (words in the title, tags, or text, newest first) — Spotlight-grade on
/// purpose; the composer's full scorer stays in-app.
struct SearchCasberiIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Casberi"
    static let description = IntentDescription(
        "Finds things by words in their title, tags, or text — newest first.")

    @Parameter(title: "Search for")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Search Casberi for \(\.$query)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let hits = try IntentCorpus.match(query, limit: 5)
        guard !hits.isEmpty else {
            return .result(value: "", dialog: "Nothing in your things matches that.")
        }
        let lines = hits.map { "\($0.title) — \($0.source)" }
        let joined = lines.joined(separator: "\n")
        return .result(value: joined,
                       dialog: IntentDialog(full: "\(hits.count) thing\(hits.count == 1 ? "" : "s"):\n\(joined)",
                                            supporting: "From your things."))
    }
}

/// Ask from anywhere — the same grounded on-device answer the composer
/// gives, as a Shortcuts value. On devices without the model, the matched
/// things answer plainly (zero regression, same as in-app).
struct AskCasberiIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Casberi"
    static let description = IntentDescription(
        "Answers a question from your things, on this device.")

    @Parameter(title: "Question")
    var question: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ask Casberi \(\.$question)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let hits = try IntentCorpus.match(question, limit: 10)
        guard !hits.isEmpty else {
            return .result(value: "", dialog: "Nothing in your things matches that.")
        }
        let candidates = hits.map {
            OnDeviceModel.Candidate(title: $0.title, kind: $0.kind.typeTag,
                                    source: $0.source,
                                    when: $0.capturedAt.formatted(.relative(presentation: .named)))
        }
        if let answer = await OnDeviceModel.compose(query: question, candidates: candidates) {
            return .result(value: answer.insight, dialog: IntentDialog(stringLiteral: answer.insight))
        }
        // No model (or it declined) — the matched things ARE the answer.
        let line = "Found: " + hits.prefix(3).map(\.title).joined(separator: " · ")
        return .result(value: line, dialog: IntentDialog(stringLiteral: line))
    }
}

/// The intents' shared corpus access — one plain matcher so Search and Ask
/// agree on what a query reaches.
enum IntentCorpus {
    static func match(_ query: String, limit: Int) throws -> [Thing] {
        let container = try SharedStore.container()
        let context = ModelContext(container)
        let things = (try? context.fetch(FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        ))) ?? []
        let terms = query.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "? "))
            .split(separator: " ").map(String.init)
            .filter { $0.count > 2 }
        guard !terms.isEmpty else { return Array(things.prefix(limit)) }
        return Array(things.filter { thing in
            let haystack = "\(thing.title) \(thing.tags.joined(separator: " ")) \(thing.content)"
                .lowercased()
            return terms.contains { haystack.contains($0) }
        }.prefix(limit))
    }
}

struct CasberiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SaveThingIntent(),
            phrases: [
                "Save to \(.applicationName)",
                "Save this to \(.applicationName)",
            ],
            shortTitle: "Save a thing",
            systemImageName: "plus"
        )
        AppShortcut(
            intent: WeekSynthesisIntent(),
            phrases: [
                "What's my week in \(.applicationName)",
                "Ask \(.applicationName) about my week",
            ],
            shortTitle: "My week",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: SearchCasberiIntent(),
            phrases: [
                "Search \(.applicationName)",
                "Find in \(.applicationName)",
            ],
            shortTitle: "Search things",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: AskCasberiIntent(),
            phrases: [
                "Ask \(.applicationName)",
            ],
            shortTitle: "Ask",
            systemImageName: "questionmark.bubble"
        )
    }
}
