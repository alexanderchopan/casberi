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
    }
}
