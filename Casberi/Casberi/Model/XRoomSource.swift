import Foundation
import SwiftData

/// The X room head's reading half (2026-08-13, prd §375) — landed rows turned
/// into the card's own value, with every judgement left to `XRoom`.
///
/// The split is `PeerRoomSource`'s and exists for its reason: this file touches
/// `Thing` and so can never be compiled by a harness, while `XRoom.swift` is
/// Foundation-only and is compiled WHOLE by `scripts/x-selftest.sh`. Everything
/// that could be wrong in a way that still renders perfectly — a year named
/// loudest because ties broke the other way, a subject claimed off one
/// mention, a strip that skips the silent years and quietly rescales itself —
/// lives on the other side of that line.
enum XRoomSource {

    static let source = XArchiveImport.source

    /// The head, or nil when this archive has no eras to show.
    ///
    /// `now` is taken for signature parity with every other `…RoomSource` in
    /// the `sourceHead` chain and is deliberately unused: this card is entirely
    /// historical, so nothing about it may change between two opens of the same
    /// corpus.
    @MainActor
    static func compose(things: [Thing] = [], now: Date = .now) -> XRoom? {
        _ = now
        // Filtered live at the BOUNDARY before any stored property is read
        // (corollary 4) — the caller's array may be a debounced snapshot, and
        // the foreground sweep deletes rows while it is held.
        let rows = things.live.filter { thing in
            thing.source == source
                && thing.kind == .note              // your own writing, never a like
                && !Corpus.isImportReceipt(thing)   // our note about the sync
        }
        guard !rows.isEmpty else { return nil }
        return XRoom.compose(rows.map(sighting))
    }

    /// ONE calendar for every row, taken once (2026-08-13). Asking
    /// `Calendar.current` per row is both slower and — across a run that spans
    /// a timezone change — capable of filing two posts from the same minute in
    /// different years.
    private static let calendar = Calendar.current

    /// One landed row, reduced to the four facts the head reads. The ONLY place
    /// a `Thing` is touched.
    @MainActor
    private static func sighting(_ thing: Thing) -> XRoom.Sighting {
        XRoom.Sighting(ref: thing.sourceRef,
                       year: calendar.component(.year, from: thing.capturedAt),
                       // Stamped by the room's own `ScreenshotTopics` sweep, so
                       // it is the SAME vocabulary the treemap ranks — which is
                       // what lets this card claim to carry the treemap's
                       // signal along time rather than a second opinion of it.
                       terms: thing.ocrTopics,
                       likes: thing.likeCount)
    }

    /// The probe's lines — driven by `-xRoomProbe`, and deliberately calling
    /// the REAL `compose` rather than reimplementing it: a probe whose job is
    /// explaining the card must not be able to disagree with the card
    /// (`PeerRoomSource.probeLines`' rule).
    ///
    /// It exists because an empty head has FIVE causes that render as one
    /// nothing, and only the last is a bug:
    ///
    ///   1. no archive imported, so the room has no rows at all;
    ///   2. an archive shorter than `XRoom.minimumYears` years or
    ///      `XRoom.minimumPosts` posts — the card declining on purpose, and the
    ///      treemap leads instead;
    ///   3. every row is a LIKE (an archive whose owner never posted), which
    ///      this card counts none of, by ruling;
    ///   4. the topic sweep hasn't run, so every year is subject-less — the
    ///      card still draws, and its own footnote says so;
    ///   5. `capturedAt` not resolving to plausible years, which draws a strip
    ///      spanning centuries and is invisible from a feed sorted by the same
    ///      field.
    ///
    /// Hence one line PER YEAR (the `-todayProbe` truncation lesson).
    @MainActor
    static func probeLines(things: [Thing], now: Date = .now) -> [String] {
        let all = things.live.filter { $0.source == source }
        let notes = all.filter { $0.kind == .note && !Corpus.isImportReceipt($0) }
        var out: [String] = [
            "xRoom| source=\(source) handed=\(things.count) xRows=\(all.count)"
                + " ownPosts=\(notes.count) minYears=\(XRoom.minimumYears)"
                + " minPosts=\(XRoom.minimumPosts)",
        ]
        // Coverage of the two fields the card's extras rest on, BEFORE
        // composition: a card with no subjects and no tap targets is healthy or
        // broken depending entirely on these two numbers.
        let withTerms = notes.filter { !$0.ocrTopics.isEmpty }.count
        let withLikes = notes.filter { $0.likeCount != nil }.count
        out.append("xRoomFields| topicsStamped=\(withTerms)/\(notes.count)"
                   + " likeCounts=\(withLikes)/\(notes.count)")
        guard let room = compose(things: things, now: now) else {
            out.append("compose=nil — no card (nothing imported, or under the floors above)")
            return out
        }
        out.append("headline=\(XRoom.headline(room))")
        out.append("note=\(XRoom.note(room))")
        out.append("footnote=\(XRoom.footnote(room) ?? "none")")
        out.append("totals| span=\(room.span) silent=\(room.silent)"
                   + " total=\(room.total) busiest=\(room.busiest.year)")
        let top = room.busiest.posts
        for year in room.years {
            out.append("xRoomYear| \(year.year) · \(XRoom.yearLine(year))"
                       + " · share=\(String(format: "%.2f", XRoom.share(posts: year.posts, of: top)))"
                       + " · loudest=\(year.loudestRef ?? "none")"
                       + "(\(year.loudestLikes.map(String.init) ?? "no counts"))")
        }
        return out
    }
}
