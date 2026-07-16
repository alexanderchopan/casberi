import Foundation
import SwiftData

/// Schema versioning for the corpus (RULE, established 2026-07-15).
///
/// `ModelContainer(for:)` throws when the on-disk store no longer matches the
/// compiled `Thing` schema and SwiftData can't infer a lightweight migration
/// — before this file existed, that throw was a `fatalError` in
/// `CasberiApp.init`, i.e. a crash-loop for every installed user until a new
/// build shipped (`SharedStore.containerWithFallback()` now degrades instead
/// of crashing, but a real migration is still the right fix).
///
/// SwiftData infers **lightweight** migrations automatically (no entry
/// needed here) for additive/compatible changes: a new optional property, a
/// new `@Attribute` (e.g. adding `.externalStorage` to an existing
/// property), a new model type. A new `ThingSchemaVN` + migration stage is
/// only required for a change SwiftData can't infer on its own — a rename
/// (use `@Attribute(originalName:)` first; only fall back to a version bump
/// if that's not enough), a type change, or a removed property whose data
/// must move somewhere first.
///
/// CloudKit-mirrored stores support ONLY lightweight migration — there is no
/// custom `willMigrate`/`didMigrate` transform once CloudKit sync is
/// engaged (`SharedStore.cloudKitReady`). So every stage added below must be
/// `.lightweight`; a change that needs real data transformation isn't a
/// migration-plan problem, it's a "ship it as a new field and backfill"
/// problem, same pattern as `Thing.watchPriceUsd`/`starCount` etc.
enum ThingSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Thing.self] }
}

enum ThingMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [ThingSchemaV1.self] }
    /// No stages yet — `Thing` has only ever had one shape. Add the next
    /// version's enum above and a `.lightweight(fromVersion:toVersion:)`
    /// stage here when that stops being true.
    static var stages: [MigrationStage] { [] }
}
