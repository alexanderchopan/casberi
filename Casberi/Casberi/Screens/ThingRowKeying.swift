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
///
/// COROLLARY 3 (build 176, 2026-07-28) — **keying does not make the row body
/// safe**, and the note that used to sit here ("bodies only ever render the
/// post-delete `@Query` snapshot, which already excludes the deleted row") was
/// simply false. `ForEachChild.updateValue()` re-evaluates the CONTENT closure
/// against the array the `ForEach` value already holds, under its own
/// observation callback, when a tracked model changes — the parent body has
/// not re-run yet, so the array still contains the row that was just deleted.
/// Build 176 crashed on first open exactly there: the id was a captured
/// `String` (safe), and the trap came one frame later from `thing.kind` inside
/// the row builder. So a derived `ForEach` needs BOTH: `keyed` for identity,
/// and a `live` check inside the closure before the first stored-property
/// read — including reads in the ARGUMENTS of a row builder call
/// (`imageOnly.contains(thing.id)`), which are evaluated at the call site and
/// therefore beat any guard the builder does internally.
struct KeyedThing: Identifiable {
    let id: String
    let thing: Thing
    init(_ thing: Thing) {
        // Captured now, while `thing` is a live, valid model — never re-read
        // off the model during diffing.
        self.id = thing.id.uuidString
        self.thing = thing
    }

    /// The row's model, or nil if it has been deleted/invalidated since this
    /// row was derived — the corollary-3 guard for a `ForEach` content
    /// closure: `if let thing = row.live { … }`, so nothing in the body (or in
    /// a row builder's argument list) can touch a tombstoned model.
    var live: Thing? { thing.isLive ? thing : nil }
}

/// One member of a folded same-source run, drawn as ITSELF rather than as a
/// number in a sentence about it (prd §377).
///
/// Identity is captured at construction for exactly `KeyedThing`'s reason —
/// these tiles ride a `ForEach` inside the row, so diffing must never reach a
/// model that a heal may have deleted since the row was derived. `remote` and
/// `circular` are resolved at construction too, and that is not convenience:
/// reading `authorAvatarURL`/`previewImageURL` lazily in the tile body would
/// be a stored-property read on a possibly-dead model, which is the whole
/// class this file exists for.
struct StripTile: Identifiable {
    let id: String
    let item: KeyedThing
    /// The tile's REMOTE image URL when it has one — a social author's face,
    /// an album cover, an article's art. nil means the tile is the thing's
    /// own STORED pixels (a screenshot, a healed file image), which
    /// `PhotoWell` reads off the model at render time behind its own
    /// liveness guard.
    let remote: String?
    /// A face is a circle, everything else the app-icon squircle —
    /// `RemoteThumb`'s own distinction, decided once by the builder so the
    /// view never re-derives it from a source name.
    let circular: Bool

    init(_ thing: Thing, remote: String? = nil, circular: Bool = false) {
        self.id = thing.id.uuidString
        self.item = KeyedThing(thing)
        self.remote = remote
        self.circular = circular
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
