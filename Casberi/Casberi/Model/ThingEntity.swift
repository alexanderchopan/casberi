import AppIntents
import CoreSpotlight
import SwiftData

/// A thing as a Shortcuts/Siri/Spotlight ENTITY (2026-07-17), not just a
/// search hit — `IndexedEntity` conformance donates each match into the
/// system's semantic index, so a search or Ask result becomes tappable and
/// Siri-groundable, richer than the plain `CSSearchableItem` rows
/// `SpotlightIndex` writes for system search. The two coexist: this is
/// additive, built on the same attribute set (`SpotlightIndex.attributeSet`),
/// not a replacement for the manual index.
struct ThingEntity: AppEntity, IndexedEntity {
    let id: UUID
    let title: String
    let subtitle: String
    let content: String
    let tags: [String]
    let source: String
    let kind: ThingKind

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Thing"
    static var defaultQuery = ThingEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        // The kind's own SF Symbol (KindGlyph's mapping) — Spotlight, Shortcuts,
        // and Visual Intelligence result cards show a mark, not a bare row.
        // Redacted here as well as in `attributeSet` (prd §277). The attribute
        // set is what the semantic INDEX ingests; this is what the Siri,
        // Shortcuts and Visual Intelligence result cards actually SHOW, and a
        // screenshot's title is OCR-derived — so hiding it in one and not the
        // other would put the secret on screen while congratulating itself.
        DisplayRepresentation(title: "\(SecretScan.redacted(title))",
                              subtitle: "\(subtitle)",
                              image: .init(systemName: kind.symbol))
    }

    var attributeSet: CSSearchableItemAttributeSet {
        get async { SpotlightIndex.attributeSet(for: asThing) }
    }

    /// Rebuilt only for the attribute-set bridge above — entities themselves
    /// stay plain value types, never holding a live SwiftData model. `kind`
    /// rides along so the bridge doesn't launder every kind into `.note`
    /// (that drift shipped once already — caught in review, not in the
    /// original cut: an empty-content Accessory/Event/Product entity would
    /// have read "A note in Casberi" in Siri/Spotlight).
    private var asThing: Thing {
        Thing(kind: kind, title: title, content: content, source: source,
             tags: tags, sourceRef: "entity:\(id.uuidString)")
    }

    init(_ thing: Thing) {
        id = thing.id
        title = thing.title
        subtitle = thing.kind.typeTag + " · " + thing.source
        content = thing.content
        tags = thing.tags
        source = thing.source
        kind = thing.kind
    }
}

/// Backs `ThingEntity.defaultQuery` — both lookups read the shared corpus
/// container the same way `IntentCorpus.match` does, so Shortcuts, Siri, and
/// the in-app Ask/Search paths always agree on what a query reaches.
struct ThingEntityQuery: EntityStringQuery {
    func entities(for identifiers: [ThingEntity.ID]) async throws -> [ThingEntity] {
        let container = try SharedStore.extensionContainer()
        let context = ModelContext(container)
        let ids = Set(identifiers)
        let things = (try? context.fetch(FetchDescriptor<Thing>())) ?? []
        return things.filter { ids.contains($0.id) }.map(ThingEntity.init)
    }

    func entities(matching string: String) async throws -> [ThingEntity] {
        let hits = try IntentCorpus.match(string, limit: 25)
        return hits.map(ThingEntity.init)
    }
}

/// Tapping a thing anywhere the SYSTEM shows it as an entity — Spotlight's
/// semantic results, a Shortcuts value, an iOS 26 Visual Intelligence card —
/// opens its sheet in the app. Routed through the same `casberi://thing/<id>`
/// deep link the widgets use, so the system tap and the widget tap land on
/// one proven path instead of two.
struct OpenThingIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Thing"
    static let description = IntentDescription("Opens a thing in Casberi.")

    @Parameter(title: "Thing")
    var target: ThingEntity

    func perform() async throws -> some IntentResult & OpensIntent {
        // A UUID string is plain hex-and-dashes — this URL always parses; the
        // feed is the fallback only the type system asks for.
        let url = URL(string: "casberi://thing/\(target.id.uuidString)")
            ?? URL(string: "casberi://feed")!
        return .result(opensIntent: OpenURLIntent(url))
    }
}
