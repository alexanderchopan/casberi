import AppIntents
import SwiftData
import SwiftUI

/// App Intents — capture, reachable from Shortcuts, Siri phrasing, and the
/// Action Button without opening the app: save a thing, start a note, and the
/// things you have with someone (`ThingsWithContactIntent`).
///
/// "Ask Casberi", "Search Casberi" and "What's my week" went with the ask
/// (2026-10-01): the app no longer answers questions on the device.
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

/// What Siri and Shortcuts SHOW for the things you have with someone (prd
/// §282, 2026-08-02; `ThingsWithContactIntent`, §1025) — the matched things
/// as rows, instead of the titles glued into one spoken paragraph.
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
/// The row is the feed's own idiom (`body17` title over `subhead12` meta), so
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

    let rows: [Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows) { row in
                HStack(spacing: 10) {
                    Image(systemName: row.symbol)
                        .dsGlyph(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.title)
                            .dsText(.body17)
                            .lineLimit(1)
                        Text(row.subtitle)
                            .dsText(.subhead12)
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

/// The plain corpus matcher for everything that reaches the corpus from
/// OUTSIDE the app — the Shortcuts entity query (`ThingEntity`) and Visual
/// Intelligence (`VisualIntelligenceSearch`) — so they agree on what a query
/// reaches.
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

/// A new note (prd §982) — the app's half of the Quick Note. The widget
/// extension declares the same intent for its Control Center control; both
/// write `note.request` into the app group, which `RootShell` drains on
/// activation by raising the note sheet.
struct NewNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "New note"
    static let description = IntentDescription("Opens a new note in Casberi.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: SharedStore.appGroup)?
            .set(true, forKey: "note.request")
        return .result()
    }
}

/// Everything with… from Shortcuts and Siri (prd §1211 item 8): the words
/// become the page search would make — a person, an app, a span or the words
/// — composed in the app. A flag, like the Quick Note's, because a cold
/// launch has no live router yet.
struct EverythingIntent: AppIntent {
    static let title: LocalizedStringResource = "Everything with…"
    static let description = IntentDescription("Opens a page in Casberi of everything with a person, from an app, or from a time.")
    static let openAppWhenRun = true

    @Parameter(title: "Words", requestValueDialog: "Everything with what?")
    var words: String

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: SharedStore.appGroup)?
            .set(words, forKey: "everything.request")
        return .result()
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
        // Your things with someone in Addresses (prd §1025) — Siri asks
        // who when the phrase does not name them.
        AppShortcut(
            intent: ThingsWithContactIntent(),
            phrases: [
                "Things with someone in \(.applicationName)",
                "What did someone send me in \(.applicationName)",
            ],
            shortTitle: "Things with someone",
            systemImageName: "person.crop.circle"
        )
        // A Quick Note by voice or the Action button (prd §982): the same
        // flag the Control Center note control writes.
        AppShortcut(
            intent: NewNoteIntent(),
            phrases: [
                "New note in \(.applicationName)",
                "Write a note in \(.applicationName)",
            ],
            shortTitle: "New note",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: EverythingIntent(),
            phrases: [
                "Everything with someone in \(.applicationName)",
                "Search \(.applicationName)",
            ],
            shortTitle: "Everything with…",
            systemImageName: "text.magnifyingglass"
        )
    }
}
