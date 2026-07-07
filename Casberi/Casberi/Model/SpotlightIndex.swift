import Foundation
import CoreSpotlight
import SwiftData

/// Spotlight — things are findable from the system's own search (goal 4 at
/// the OS level: one home, reachable from anywhere). Titles, content, and
/// tags index; tapping a result deep-links into the thing sheet. The index
/// mirrors the store: save indexes, delete deindexes, launch reconciles.
enum SpotlightIndex {

    private static let domain = "things"

    static func index(_ things: [Thing]) {
        guard !things.isEmpty else { return }
        let items = things.map { thing in
            let attrs = CSSearchableItemAttributeSet(contentType: .text)
            attrs.title = thing.title
            attrs.contentDescription = thing.content.isEmpty
                ? "A \(thing.kind.typeTag.lowercased()) in Casberi"
                : thing.content
            attrs.keywords = thing.tags + [thing.source, "Casberi"]
            return CSSearchableItem(
                uniqueIdentifier: thing.id.uuidString,
                domainIdentifier: domain,
                attributeSet: attrs
            )
        }
        CSSearchableIndex.default().indexSearchableItems(items)
    }

    static func remove(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        CSSearchableIndex.default()
            .deleteSearchableItems(withIdentifiers: ids.map(\.uuidString))
    }

    static func removeAll() {
        CSSearchableIndex.default()
            .deleteSearchableItems(withDomainIdentifiers: [domain])
    }

    /// Launch reconciliation — cheap at phone scale, and it covers things
    /// created by the share extension while the app was closed.
    static func reindexAll(context: ModelContext) {
        let things = (try? context.fetch(FetchDescriptor<Thing>())) ?? []
        removeAll()
        index(things)
    }
}
