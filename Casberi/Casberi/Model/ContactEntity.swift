import AppIntents
import SwiftData

/// An entry in Addresses as Shortcuts and Siri see it (prd §1025) — a person,
/// an organisation, a Safe or a publication, by the name the index gives it.
/// A plain value: the id is the contact's lead identity key (stable while
/// identities join, `ContactIndex.build`), and nothing here holds a model.
struct ContactEntity: AppEntity {
    let id: String
    let name: String
    /// The row's own line: the newest thing from them, else nil.
    let line: String?

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Address"
    static var defaultQuery = ContactEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)",
                              subtitle: line.map { "\(SecretScan.redacted($0))" })
    }

    init(_ contact: Contact) {
        id = contact.id
        name = contact.name
        line = contact.lastThing
    }
}

/// Reads the Addresses index — the last rebuild, or a fresh one when this
/// process has not built it yet (a cold launch by Siri). Never the person's
/// own accounts (`ContactIndexSources.isYours`), the list's own rule.
struct ContactEntityQuery: EntityStringQuery {
    @MainActor
    static func contacts() -> [Contact] {
        var all = ContactIndexSources.contacts
        if all.isEmpty, let container = try? SharedStore.extensionContainer() {
            all = ContactIndexSources.rebuild(context: ModelContext(container))
        }
        return all.filter { !ContactIndexSources.isYours($0) }
    }

    func entities(for identifiers: [String]) async throws -> [ContactEntity] {
        let ids = Set(identifiers)
        return await MainActor.run { Self.contacts().filter { ids.contains($0.id) }.map(ContactEntity.init) }
    }

    func entities(matching string: String) async throws -> [ContactEntity] {
        let q = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return await MainActor.run {
            Self.contacts()
                .filter { c in
                    c.name.localizedCaseInsensitiveContains(q)
                        || c.identities.contains { $0.body.localizedCaseInsensitiveContains(q) }
                }
                .prefix(25).map(ContactEntity.init)
        }
    }

    /// Whom you dealt with most recently, then everyone named — what a picker
    /// offers before anything is typed.
    func suggestedEntities() async throws -> [ContactEntity] {
        await MainActor.run {
            Self.contacts()
                .filter { !$0.isUnnamed }
                .sorted { ($0.lastActedAt ?? .distantPast) > ($1.lastActedAt ?? .distantPast) }
                .prefix(25).map(ContactEntity.init)
        }
    }
}

/// "What did Jesse send me?" — your things with one entry in Addresses, the
/// sheet's own "With you" list (`ContactSheet.things`), newest first.
struct ThingsWithContactIntent: AppIntent {
    static let title: LocalizedStringResource = "Things with someone"
    static let description = IntentDescription(
        "Finds your things with someone in Addresses — transfers, mail, posts and more, newest first.")

    @Parameter(title: "Who")
    var contact: ContactEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Things with \(\.$contact)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[ThingEntity]> & ProvidesDialog & ShowsSnippetView {
        guard let found = ContactEntityQuery.contacts().first(where: { $0.id == contact.id }),
              let container = try? SharedStore.extensionContainer() else {
            return .result(value: [], dialog: "That address isn't in Casberi any more.",
                           view: IntentRowsSnippet(rows: []))
        }
        let context = ModelContext(container)
        let ids = ContactSheet.things(for: found, context: context, limit: 5).map(\.id)
        let things: [Thing] = ids.compactMap { id in
            var d = FetchDescriptor<Thing>(predicate: #Predicate { $0.id == id })
            d.fetchLimit = 1
            return (try? context.fetch(d))?.first
        }
        guard !things.isEmpty else {
            return .result(value: [], dialog: "Nothing with \(found.name) yet.",
                           view: IntentRowsSnippet(rows: []))
        }
        // Redacted at the boundary, as every intent dialog is (prd §277).
        let lines = things.map { "\(SecretScan.redacted($0.title)) — \($0.source)" }.joined(separator: "\n")
        return .result(value: things.map(ThingEntity.init),
                       dialog: IntentDialog(full: LocalizedStringResource("With \(found.name):\n\(lines)"),
                                            supporting: "From your things."),
                       view: IntentRowsSnippet(rows: things.map(IntentRowsSnippet.Row.init)))
    }
}
