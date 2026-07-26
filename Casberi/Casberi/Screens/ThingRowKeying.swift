import Foundation
import SwiftData

/// Value-typed identity for a `Thing` inside a `ForEach` — the fix for the
/// recurring "crashes on different screens after an update / first sync" class
/// (builds 137/138/139, 2026-07-24).
///
/// Reading a SwiftData `@Model`'s stored property (`Thing.id`, `.title`,
/// `.source`, …) AFTER it has been deleted or invalidated traps inside
/// SwiftData (`_assertionFailure` → EXC_BREAKPOINT). SwiftUI's `ForEach`
/// identity diffing (`ForEachChild.updateValue()`) re-reads each element's
/// `id` on EVERY graph update — including the exact transaction where a
/// reconciliation delete (`SyncReconcile` at launch, or any of the
/// per-foreground bridge heals) or a CloudKit-merged delete removes the row
/// out from under the live view.
///
/// A `ForEach` **directly over a `@Query` array** is coordinated by SwiftData
/// and is safe. A `ForEach` over a **derived** array (a `.filter`/`.map`, a
/// day-grouping, a value held in `@State` from a manual fetch) that holds raw
/// `Thing` refs is NOT — its `.id`/`\.element.id` read reaches a dead model
/// during the delete. That derived case is the entire crash surface this app
/// kept hitting on screen after screen.
///
/// RULE (see CLAUDE.md): never key a `ForEach` on a persistent `@Model`
/// property from a derived array. Iterate `things.keyed` and read `$0.thing`
/// in the body — identity is then a plain `String` captured while the model
/// was still valid, so diffing never touches the model.
struct KeyedThing: Identifiable {
    let id: String
    let thing: Thing
    init(_ thing: Thing) {
        // Captured now, while `thing` is a live, valid model — never re-read
        // off the model during diffing.
        self.id = thing.id.uuidString
        self.thing = thing
    }
}

extension Array where Element == Thing {
    /// Value-keyed rows for a `ForEach` over a DERIVED thing array. See
    /// `KeyedThing`.
    var keyed: [KeyedThing] { map(KeyedThing.init) }

    /// The still-live members of a HELD thing array — the corollary-2 guard
    /// (build 150, 2026-07-25). `keyed` protects a `ForEach`'s identity
    /// diffing; it does NOT protect the row body, the section header, or any
    /// helper that reads the same array. A view owning a held array (a
    /// `@State` value from a manual fetch, or one handed down as a `let`)
    /// filters ONCE at the top with this, before positions, rows, headers or
    /// footers read through it — so a delete landing in the same graph update
    /// can't trap on the first persisted read.
    var live: [Thing] { filter(\.isLive) }
}

extension Thing {
    /// True while this model is still backed by live store data; false once it
    /// has been deleted or invalidated. Guard any HELD reference read with this
    /// — a `Thing` kept in `@State`, captured in a closure, or bound to a
    /// `sheet(item:)`/`navigationDestination` — before touching a stored
    /// property, so a delete arriving under an open sheet/dialog can't trap.
    var isLive: Bool { modelContext != nil && !isDeleted }
}
