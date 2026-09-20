import AppIntents
import CoreSpotlight
import Foundation
import SwiftData

/// A thing's KIND as a Shortcuts value (2026-09-20, prd §855) — the enum the
/// corpus already files everything under, offered as a picker so a Find query
/// can say "Kind is Screenshot" instead of hoping the word appears in a title.
///
/// The conformance lives HERE, not beside the type in `Shared/Thing.swift`,
/// because `Shared/` compiles into the share extension too and the extension
/// has no business importing App Intents. Same module, so that costs nothing
/// — with ONE exception: `AppEnum` requires `Sendable`, and a Sendable
/// conformance must be declared in the type's own file (retroactively it is a
/// Swift 6 error), so `ThingKind` spells that one word itself.
///
/// `caseDisplayRepresentations` must name every case or it does not compile —
/// which is the point: a new kind cannot drift out of the picker the way a
/// hand-kept table does (prd §831). The retired `.accessory` is listed for
/// that reason and no other; it stays in the enum so older rows still decode.
extension ThingKind: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Kind" }

    static var caseDisplayRepresentations: [ThingKind: DisplayRepresentation] {
        [.note: "Note",
         .screenshot: "Screenshot",
         .chat: "Chat",
         .event: "Event",
         .link: "Link",
         .reminder: "Reminder",
         .mail: "Mail",
         .file: "File",
         .voice: "Voice",
         .contact: "Contact",
         .job: "Job",
         .run: "Run",
         .output: "Output",
         .skill: "Skill",
         .approval: "Approval",
         .transaction: "Transaction",
         .product: "Product",
         .accessory: "Accessory"]
    }
}

/// A thing as a Shortcuts/Siri/Spotlight ENTITY (2026-07-17), not just a
/// search hit — `IndexedEntity` conformance donates each match into the
/// system's semantic index, so a search or Ask result becomes tappable and
/// Siri-groundable, richer than the plain `CSSearchableItem` rows
/// `SpotlightIndex` writes for system search. The two coexist: this is
/// additive, built on the same attribute set (`SpotlightIndex.attributeSet`),
/// not a replacement for the manual index.
///
/// **Four members are `@Property` since prd §855**, which is what makes them
/// FILTERABLE in the Shortcuts "Find Things" action (`ThingEntityQuery`'s
/// `EntityPropertyQuery` half). The rest stay plain: `subtitle` and `content`
/// are what a result SHOWS, `tags` has no comparator worth the picker, and
/// `id` is the identity. Adding a `@Property` is the whole cost of making a
/// field queryable, so add one only where a person would actually filter.
struct ThingEntity: AppEntity, IndexedEntity {
    let id: UUID

    @Property(title: "Title") var title: String
    @Property(title: "App") var source: String
    @Property(title: "Kind") var kind: ThingKind
    @Property(title: "Date") var capturedAt: Date

    let subtitle: String
    let content: String
    let tags: [String]

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
        // The plain `let`s FIRST. A `@Property` member is written through the
        // wrapper's setter, which is a call on a fully-initialized `self`, so
        // any stored property still unassigned at that point is a compile
        // error ("used before being initialized"). Order is load-bearing here.
        id = thing.id
        subtitle = thing.kind.typeTag + " · " + thing.source
        content = thing.content
        tags = thing.tags

        title = thing.title
        source = thing.source
        kind = thing.kind
        capturedAt = thing.capturedAt
    }
}

/// Backs `ThingEntity.defaultQuery` — every lookup reads the shared corpus
/// container the same way `IntentCorpus.match` does, so Shortcuts, Siri, and
/// the in-app Ask/Search paths always agree on what a query reaches.
///
/// **Three queries, one corpus.** `EntityStringQuery` is the free-text half
/// (what Siri and a plain "Search Casberi" reach). `EntityPropertyQuery` is
/// the STRUCTURED half added in prd §855: it is what puts a "Find Things"
/// action in Shortcuts, where a filter can say *kind is Screenshot, app is
/// Gmail, date is after Monday, newest first* — the composition a phone-level
/// agent needs and free text cannot express. It is the only App Intents work
/// here that helps every iOS this app supports; assistant schemas and
/// onscreen context are iOS 27's Siri and stay unadopted.
///
/// Filtering runs in SWIFT, over the fetched corpus, not as a `#Predicate`:
/// the comparator closures compose arbitrarily (and-of-ors), and a `#Predicate`
/// using `.contains` on the `tags` array crashes at runtime anyway (the gotcha
/// this repo has already paid for). The corpus fetch is the same one the
/// string query does.
struct ThingEntityQuery: EntityStringQuery, EntityPropertyQuery {
    /// What a comparator compiles down to: a test run against one entity.
    /// `@Sendable` because the system may evaluate a Find query off the
    /// calling actor.
    typealias ComparatorMappingType = @Sendable (ThingEntity) -> Bool

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

    static var properties = QueryProperties {
        Property(\ThingEntity.$title) {
            ContainsComparator { text in
                { @Sendable in $0.title.localizedCaseInsensitiveContains(text) }
            }
            EqualToComparator { text in
                { @Sendable in $0.title.localizedCaseInsensitiveCompare(text) == .orderedSame }
            }
        }
        Property(\ThingEntity.$source) {
            EqualToComparator { name in
                { @Sendable in $0.source.localizedCaseInsensitiveCompare(name) == .orderedSame }
            }
            ContainsComparator { name in
                { @Sendable in $0.source.localizedCaseInsensitiveContains(name) }
            }
        }
        Property(\ThingEntity.$kind) {
            EqualToComparator { kind in { @Sendable in $0.kind == kind } }
            NotEqualToComparator { kind in { @Sendable in $0.kind != kind } }
        }
        Property(\ThingEntity.$capturedAt) {
            GreaterThanComparator { date in { @Sendable in $0.capturedAt > date } }
            LessThanComparator { date in { @Sendable in $0.capturedAt < date } }
        }
    }

    static var sortingOptions = SortingOptions {
        SortableBy(\ThingEntity.$capturedAt)
        SortableBy(\ThingEntity.$title)
    }

    func entities(matching comparators: [ComparatorMappingType],
                  mode: ComparatorMode,
                  sortedBy: [EntityQuerySort<ThingEntity>],
                  limit: Int?) async throws -> [ThingEntity] {
        let entities = try IntentCorpus.corpus().map(ThingEntity.init)
        // An empty comparator list is "everything" in either mode — `allSatisfy`
        // says true on empty, but `contains` says false, which would answer a
        // filterless Find with nothing.
        var hits = comparators.isEmpty ? entities : entities.filter { entity in
            switch mode {
            case .and: return comparators.allSatisfy { $0(entity) }
            case .or:  return comparators.contains { $0(entity) }
            @unknown default: return comparators.allSatisfy { $0(entity) }
            }
        }
        for sort in sortedBy.reversed() {
            let ascending = sort.order == .ascending
            if sort.by == \ThingEntity.$capturedAt as PartialKeyPath<ThingEntity> {
                hits.sort { ascending ? $0.capturedAt < $1.capturedAt : $0.capturedAt > $1.capturedAt }
            } else if sort.by == \ThingEntity.$title as PartialKeyPath<ThingEntity> {
                hits.sort {
                    let order = $0.title.localizedCaseInsensitiveCompare($1.title)
                    return ascending ? order == .orderedAscending : order == .orderedDescending
                }
            }
        }
        // No sort asked for is newest first — the order every other surface in
        // this app reads the corpus in, and the order `IntentCorpus.corpus()`
        // already fetched.
        if let limit { hits = Array(hits.prefix(limit)) }
        return hits
    }
}

/// Tapping a thing anywhere the SYSTEM shows it as an entity — Spotlight's
/// semantic results, a Shortcuts value, an iOS 26 Visual Intelligence card —
/// opens its sheet in the app. Routed through the same `casberi://thing/<id>`
/// deep link the widgets use, so the system tap and the widget tap land on
/// one proven path instead of two.
struct OpenThingIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open thing"
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
