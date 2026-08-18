import Foundation
import SwiftData

/// The GitHub room head's reading half (prd §401) — landed rows turned into
/// the card's value, with every judgement left to `GitHubRoom`.
///
/// The split is `CursorRoomSource`'s and exists for its reason: this file
/// touches `Thing` and so can never be compiled by a harness, while
/// `GitHubRoom.swift` is Foundation-only and is compiled WHOLE by
/// `scripts/github-room-selftest.sh`. Everything that could be wrong in a way
/// that still renders perfectly — a review request ranked below a mention, a
/// card that reshuffles between opens, an ask silently dropped — lives on the
/// other side of that line.
enum GitHubRoomSource {

    static let source = "GitHub"

    /// The head, or nil when nothing is waiting on you.
    ///
    /// `now` is taken for signature parity with every other `…RoomSource` in
    /// the `sourceHead` chain; this card needs no clock, because it refuses to
    /// turn `updated_at` into a waiting time (see `GitHubRoom`'s own doc).
    @MainActor
    static func compose(things: [Thing] = [], now: Date = .now) -> GitHubRoom? {
        // Filtered live at the BOUNDARY before any stored property is read
        // (corollary 4) — the caller's array may be a debounced snapshot, and
        // the foreground sweep deletes rows while it is held.
        let rows = things.live.filter { $0.source == source }
        guard !rows.isEmpty else { return nil }
        return GitHubRoom.compose(rows: rows.map(sighting))
    }

    /// One landed row, reduced to the four facts the head reads. The ONLY
    /// place a `Thing` is touched.
    @MainActor
    private static func sighting(_ thing: Thing)
        -> (tags: [String], title: String, lastMoved: Date, ref: String) {
        (tags: thing.tags,
         title: thing.title,
         // GitHub's `updated_at` for the notification thread — when it last
         // MOVED, not when the ask was made. `GitHubRoom` is built knowing
         // that and never words it as a waiting time.
         lastMoved: thing.capturedAt,
         ref: thing.sourceRef ?? thing.id.uuidString)
    }
}
