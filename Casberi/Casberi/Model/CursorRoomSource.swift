import Foundation
import SwiftData

/// The Cursor room head's reading half (2026-08-08, prd §340) — landed rows
/// turned into the card's own value, with every judgement left to `CursorRoom`.
///
/// The split is `ASCRoomSource`'s and exists for its reason: this file touches
/// `Thing` and so can never be compiled by a harness, while `CursorRoom.swift`
/// is Foundation-only and is compiled WHOLE by
/// `scripts/cursor-room-selftest.sh`. Everything that could be wrong in a way
/// that still renders perfectly — a repository with a failed run ranked below a
/// busy clean one, a run silently bucketed under a repo nobody named, a card
/// that reshuffles between opens — lives on the other side of that line.
///
/// Unlike `ASCRoomSource`, which takes `things` for signature parity and reads
/// none of them, this head is entirely the rows: the runs ARE the subject.
enum CursorRoomSource {

    /// The bridge's own source name, taken from the catalog rather than spelled
    /// again — a room that filters on a literal is a room that empties silently
    /// the day the seat is renamed.
    static let source = TokenBridge.cursor.rawValue

    /// The card draws at most this many repositories; the rest are counted in
    /// the note rather than silently dropped.
    static let rowCap = 3

    /// The head, or nil when there is nothing worth drawing.
    ///
    /// `now` is taken (and only used for the note's idle clause) so a probe can
    /// compose against a fixed clock — the signature every `…RoomSource` in the
    /// `sourceHead` chain shares.
    @MainActor
    static func compose(things: [Thing] = [], now: Date = .now) -> CursorRoom? {
        // Filtered live at the BOUNDARY before any stored property is read
        // (corollary 4) — the caller's array may be a debounced snapshot, and
        // the foreground sweep deletes rows while it is held.
        let rows = things.live.filter { $0.source == source }
        guard !rows.isEmpty else { return nil }
        let room = CursorRoom.compose(runs: rows.map(sighting))
        return room.isEmpty ? nil : room
    }

    /// One landed row, reduced to the four facts the head reads. The ONLY place
    /// a `Thing` is touched.
    @MainActor
    private static func sighting(_ thing: Thing) -> CursorRoom.Sighting {
        CursorRoom.Sighting(title: thing.title,
                            tags: thing.tags,
                            // Where `CursorFetch` stamps the repository, so the
                            // room groups on data rather than on a clamped
                            // display string. Nil on rows landed before §340.
                            repo: thing.authorHandle,
                            at: thing.capturedAt)
    }

    /// The probe's lines — driven by `-cursorRoomProbe`, and deliberately
    /// calling the REAL `compose` rather than reimplementing it: a probe whose
    /// job is explaining the card must not be able to disagree with the card
    /// (`ASCRoomSource.probeLines`' own rule).
    ///
    /// It exists because an empty head has FIVE causes that render as one
    /// nothing, and only the last two are bugs:
    ///
    ///   1. the bridge isn't connected, so there are no rows at all;
    ///   2. the account has run fewer than two cloud agents (`minimumRuns`) —
    ///      the common healthy case for a new connection;
    ///   3. every run is in flight, so nothing terminal has landed;
    ///   4. every run was EXCLUDED because no repository could be named, which
    ///      on a corpus of legacy rows means the title parse is failing;
    ///   5. the outcome is being read from titles rather than tags on rows that
    ///      should carry tags — the §340 wiring came undone.
    ///
    /// 4 and 5 are invisible from the feed, which draws every row correctly
    /// either way. Hence one line PER RUN naming its provenance (the
    /// `-todayProbe` truncation lesson: one NSLog per line, never a joined
    /// document).
    @MainActor
    static func probeLines(things: [Thing], now: Date = .now) -> [String] {
        let rows = things.live.filter { $0.source == source }
        let sightings = rows.map(sighting)
        var out: [String] = [
            "cursorRoom| source=\(source) handed=\(things.count) cursorRows=\(rows.count)"
                + " rowCap=\(rowCap) minimumRuns=\(CursorRoom.minimumRuns)",
        ]
        // The runs BEFORE grouping, newest first — so a card that grouped
        // wrongly can be told from one whose rows were already unreadable.
        for run in sightings.map(CursorRoom.read).sorted(by: { $0.at > $1.at }) {
            out.append("cursorRoomRun| repo=\(run.repo ?? "UNPLACED")"
                       + " (\(run.repoFrom.rawValue))"
                       + " outcome=\(run.outcome.rawValue) (\(run.outcomeFrom.rawValue))"
                       + " unfinished=\(run.outcome.unfinished ? "YES" : "no")"
                       + " at=\(run.at.formatted(.iso8601))")
        }
        guard let room = compose(things: things, now: now) else {
            out.append("compose=nil — no card (not connected, under \(CursorRoom.minimumRuns) placed runs,"
                       + " or every run unplaced)")
            return out
        }
        out.append("headline=\(CursorRoom.headline(room))")
        out.append("note=\(CursorRoom.note(room, drawn: min(rowCap, room.repos.count), now: now) ?? "none")")
        out.append("totals| placed=\(room.totalRuns) unfinished=\(room.totalUnfinished)"
                   + " excluded=\(room.excluded) repos=\(room.repos.count)")
        let top = room.lead?.runs ?? 0
        for repo in room.repos.prefix(rowCap) {
            out.append("cursorRoomRepo| \(repo.name)"
                       + " · \(CursorRoom.repoLine(repo))"
                       + " · newest=\(repo.newest.formatted(.iso8601))"
                       + " · rank=\(CursorRoom.rank(repo))"
                       + " · share=\(String(format: "%.2f", CursorRoom.share(runs: repo.runs, of: top)))")
        }
        return out
    }
}
