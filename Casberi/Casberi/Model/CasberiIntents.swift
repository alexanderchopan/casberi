import AppIntents
import SwiftData
import SwiftUI

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
        // extensionContainer(), not container(): Siri/Shortcuts can run an
        // intent's perform() out-of-process while the app is also open, and
        // a fresh CloudKit-mirroring container here would fight the app's
        // own mirror on the same store file (SharedStore's own warning). A
        // write made through the local-only container still reaches iCloud
        // next time the app opens, same as the share extension.
        let container = try SharedStore.extensionContainer()
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
        let container = try SharedStore.extensionContainer()
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
                IntentDialog(LocalizedStringResource("\(top.key) fills your week — \(top.value) things across \(sources) app.")))
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

    func perform() async throws -> some IntentResult & ReturnsValue<[ThingEntity]> & ProvidesDialog & ShowsSnippetView {
        let hits = try IntentCorpus.match(query, limit: 5)
        guard !hits.isEmpty else {
            return .result(value: [], dialog: "Nothing in your things matches that.",
                           view: IntentRowsSnippet(rows: []))
        }
        let entities = hits.map(ThingEntity.init)
        // The credential tripwire (prd §277), at the boundary that matters:
        // this dialog is SPOKEN by Siri and shown outside the app, exactly as
        // the snippet rows below are. Both of `AskCasberiIntent`'s paths and
        // `IntentRowsSnippet.Row.init` have always scrubbed here; this one
        // line did not, so a search that matched a screenshot of a recovery
        // phrase read it out loud. Found by `redaction-coverage-audit.py` on
        // its first run (2026-08-19).
        let lines = hits.map { "\(SecretScan.redacted($0.title)) — \($0.source)" }
        let joined = lines.joined(separator: "\n")
        // The rows are built here, off the live models, and handed to the
        // snippet as plain values — a view that held `Thing`s would be reading
        // SwiftData from the system's process on the system's schedule.
        // Redaction applies for the same reason it does in the dialog (prd
        // §277): a snippet is shown outside the app.
        let rows = hits.map(IntentRowsSnippet.Row.init)
        return .result(value: entities,
                       dialog: IntentDialog(full: LocalizedStringResource("\(hits.count) thing:\n\(joined)"),
                                            supporting: "From your things."),
                       view: IntentRowsSnippet(rows: rows))
    }
}

/// What Siri and Shortcuts SHOW for a search or an ask (prd §282,
/// 2026-08-02) — the matched things as rows, instead of the titles glued into
/// one spoken paragraph. The intents have grounded their answers in real
/// things since they shipped; until now the person could only hear about them.
///
/// Plain values, never `Thing`s: a snippet view is rendered by the system, in
/// its own process and on its own schedule, and handing it live SwiftData
/// models would be the held-reference crash class (`ThingRowKeying`) reached
/// from the one place the app cannot see it happen.
///
/// On the RAMP since 2026-08-11, not raw sizes. It shipped at 17/15/12 — the
/// reading band as it stood BEFORE the 2026-07-25 pass moved it to 18/16/14
/// (Typography.swift) — so the app's own answer rendered a point denser in
/// Siri than in the composer, and none of it scaled with Dynamic Type. Exactly
/// the "frozen while its neighbours grew" drift that ramp's own comments name.
/// The row is the feed's own idiom (`body17` title over `subhead13` meta), so
/// what Siri shows and what the feed shows are now one shape.
struct IntentRowsSnippet: View {
    struct Row: Identifiable {
        let id: UUID
        let title: String
        let subtitle: String
        let symbol: String

        init(_ thing: Thing) {
            id = thing.id
            // The credential tripwire, at the boundary that matters: this
            // leaves the app the same way a Spotlight donation does, and a
            // screenshot's title is OCR-derived.
            title = SecretScan.redacted(thing.title)
            subtitle = thing.kind.typeTag + " · " + thing.source
            symbol = thing.kind.symbol
        }
    }

    var answer: String? = nil
    let rows: [Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let answer, !answer.isEmpty {
                Text(answer)
                    .dsText(.body17)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(rows) { row in
                HStack(spacing: 10) {
                    Image(systemName: row.symbol)
                        .dsGlyph(13)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.title)
                            .dsText(.body17)
                            .lineLimit(1)
                        Text(row.subtitle)
                            .dsText(.subhead13)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(4)
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

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        let hits = try IntentCorpus.match(question, limit: 10)
        guard !hits.isEmpty else {
            return .result(value: "", dialog: "Nothing in your things matches that.",
                           view: IntentRowsSnippet(rows: []))
        }
        // The credential tripwire (prd §277): an intent result is spoken by
        // Siri and pipeable anywhere by Shortcuts, so it leaves the app the
        // same way a Spotlight donation does. Titles are the whole payload
        // here, and a screenshot's title is OCR-derived.
        let candidates = hits.map {
            OnDeviceModel.Candidate(title: SecretScan.redacted($0.title),
                                    kind: $0.kind.typeTag,
                                    source: $0.source,
                                    when: $0.capturedAt.formatted(.relative(presentation: .named)))
        }
        if let answer = await OnDeviceModel.compose(query: question, candidates: candidates) {
            // The snippet shows the sentence AND the things it rests on — the
            // same grounding the in-app answer paints beneath its prose, which
            // a spoken-only result could never carry.
            let cited = answer.picks.compactMap { hits.indices.contains($0) ? hits[$0] : nil }
            let shown = (cited.isEmpty ? Array(hits.prefix(3)) : cited).prefix(4)
            return .result(value: answer.insight,
                           dialog: IntentDialog(stringLiteral: answer.insight),
                           view: IntentRowsSnippet(answer: answer.insight,
                                                   rows: shown.map(IntentRowsSnippet.Row.init)))
        }
        // No model (or it declined) — the matched things ARE the answer.
        let line = "Found: " + hits.prefix(3)
            .map { SecretScan.redacted($0.title) }.joined(separator: " · ")
        return .result(value: line, dialog: IntentDialog(stringLiteral: line),
                       view: IntentRowsSnippet(rows: hits.prefix(3).map(IntentRowsSnippet.Row.init)))
    }
}

/// The intents' shared corpus access — one plain matcher so Search and Ask
/// agree on what a query reaches.
enum IntentCorpus {
    static func match(_ query: String, limit: Int) throws -> [Thing] {
        try match(query, in: corpus(), limit: limit)
    }

    /// One fetch of the whole corpus, newest first — callers matching several
    /// queries in a row (the Visual Intelligence labels) fetch once and run
    /// the in-memory variant below per query, instead of opening a fresh
    /// container per label.
    static func corpus() throws -> [Thing] {
        let container = try SharedStore.extensionContainer()
        let context = ModelContext(container)
        return (try? context.fetch(FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        ))) ?? []
    }

    static func match(_ query: String, in things: [Thing], limit: Int) -> [Thing] {
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
