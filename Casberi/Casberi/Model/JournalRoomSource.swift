import Foundation
import SwiftData

/// The journal room head's reading half (2026-08-17, prd §398) — landed rows
/// turned into the card's own value, with every judgement left to `JournalRoom`.
///
/// The split is `XRoomSource`'s and exists for its reason: this file touches
/// `Thing` and so can never be compiled by a harness, while `JournalRoom.swift`
/// is Foundation-only and is compiled WHOLE by
/// `scripts/journal-room-selftest.sh`. Everything that could be wrong in a way
/// that still renders perfectly — a year named fullest because ties broke the
/// other way, a streak counted across a gap, a subject claimed off one mention,
/// a strip that skips the silent years and quietly rescales itself — lives on
/// the other side of that line.
enum JournalRoomSource {

    /// The two rooms this head serves, and the ONE place that membership is
    /// written down — `FeedScreen` reads it for the head and again for the
    /// anniversary above it, so a third room joining is one edit here.
    ///
    /// Obsidian is deliberately absent: a vault note is dated by its file's
    /// mtime, so an edit moves a 2019 note to today and years composed over
    /// that would chart when files were touched while claiming to chart when
    /// somebody wrote (`JournalRoom`'s own note).
    static let sources: Set<String> = ["Day One", "Apple Journal"]

    /// The head, or nil when this journal has no span to show.
    ///
    /// `now` is taken for signature parity with every other `…RoomSource` in the
    /// `sourceHead` chain and is deliberately unused: this card is entirely
    /// historical, so nothing about it may change between two opens of the same
    /// corpus.
    @MainActor
    static func compose(things: [Thing] = [], now: Date = .now) -> JournalRoom? {
        _ = now
        // Filtered live at the BOUNDARY before any stored property is read
        // (corollary 4) — the caller's array may be a debounced snapshot, and
        // the foreground sweep deletes rows while it is held.
        let rows = things.live.filter { thing in
            sources.contains(thing.source)
                && thing.kind == .note
                && !Corpus.isImportReceipt(thing)
        }
        guard !rows.isEmpty else { return nil }
        return JournalRoom.compose(rows.map(sighting))
    }

    /// ONE calendar for every row, taken once. Asking `Calendar.current` per row
    /// is both slower and — across a run that spans a timezone change — capable
    /// of filing two entries from the same minute in different years
    /// (`XRoomSource`'s rule, which matters more here because this one also
    /// resolves DAYS and an off-by-one day breaks a streak silently).
    private static let calendar = Calendar.current

    /// One landed row, reduced to the four facts the head reads. The ONLY place
    /// a `Thing` is touched.
    ///
    /// The day ordinal is `ordinality(of: .day, in: .era, …)` — a day NUMBER, so
    /// two entries are adjacent exactly when their ordinals differ by one, with
    /// no arithmetic on seconds anywhere. A `timeIntervalSince` divided by 86,400
    /// would be wrong twice a year in every zone that observes daylight saving,
    /// and wrong in the direction that silently shortens a streak.
    @MainActor
    private static func sighting(_ thing: Thing) -> JournalRoom.Sighting {
        JournalRoom.Sighting(
            ref: thing.sourceRef,
            year: calendar.component(.year, from: thing.capturedAt),
            day: calendar.ordinality(of: .day, in: .era, for: thing.capturedAt) ?? 0,
            // Stamped by the room's own `ScreenshotTopics` sweep, so it is the
            // SAME vocabulary the treemap ranks — which is what lets this card
            // claim to carry the treemap's signal along time rather than a
            // second opinion of it.
            terms: thing.ocrTopics)
    }

    /// The probe's lines — driven by `-roomInsightProbe`, and deliberately
    /// calling the REAL `compose` rather than reimplementing it: a probe whose
    /// job is explaining the card must not be able to disagree with the card
    /// (`PeerRoomSource.probeLines`' rule).
    ///
    /// It exists because an empty head has FIVE causes that render as one
    /// nothing, and only the last is a bug:
    ///
    ///   1. nothing imported, so the room has no rows at all;
    ///   2. a journal shorter than `JournalRoom.minimumYears` years,
    ///      `minimumSpanDays` days or `minimumEntries` entries — the card
    ///      declining on purpose, and the topic map leads instead;
    ///   3. a span that LOOKS like two years and is six weeks across New Year,
    ///      which the day floor refuses and the year count alone would pass;
    ///   4. the topic sweep hasn't run, so every year is subject-less — the card
    ///      still draws, and its own footnote says so;
    ///   5. `capturedAt` not resolving to plausible years, which draws a strip
    ///      spanning centuries and is invisible from a feed sorted by the same
    ///      field.
    ///
    /// Hence one line PER YEAR (the `-todayProbe` truncation lesson).
    @MainActor
    static func probeLines(things: [Thing], now: Date = .now) -> [String] {
        let all = things.live.filter { sources.contains($0.source) }
        let entries = all.filter { $0.kind == .note && !Corpus.isImportReceipt($0) }
        var out: [String] = [
            "journalRoom| rows=\(all.count) entries=\(entries.count)"
                + " minYears=\(JournalRoom.minimumYears)"
                + " minSpanDays=\(JournalRoom.minimumSpanDays)"
                + " minEntries=\(JournalRoom.minimumEntries)",
        ]
        // Coverage of the one field the card's extras rest on, BEFORE
        // composition: a card with no subjects at all is healthy or broken
        // depending entirely on this number.
        let withTerms = entries.filter { !$0.ocrTopics.isEmpty }.count
        out.append("journalRoomFields| topicsStamped=\(withTerms)/\(entries.count)")
        // The raw span, printed whether or not the card composes — it is the
        // floor most likely to be the reason for a nil, and the only one that
        // cannot be read off the row count.
        let dayOrdinals = entries.compactMap {
            calendar.ordinality(of: .day, in: .era, for: $0.capturedAt)
        }
        if let lo = dayOrdinals.min(), let hi = dayOrdinals.max() {
            out.append("journalRoomSpan| days=\(hi - lo) distinctDays=\(Set(dayOrdinals).count)")
        }
        guard let room = compose(things: things, now: now) else {
            out.append("compose=nil — no card (nothing imported, or under the floors above)")
            return out
        }
        out.append("headline=\(JournalRoom.headline(room))")
        out.append("note=\(JournalRoom.note(room))")
        out.append("footnote=\(JournalRoom.footnote(room) ?? "none")")
        out.append("totals| span=\(room.span) silent=\(room.silent)"
                   + " total=\(room.total) days=\(room.days)"
                   + " fullest=\(room.fullest.year) streak=\(room.streak)"
                   + " streakYear=\(room.streakYear.map(String.init) ?? "none")")
        let top = room.fullest.entries
        for year in room.years {
            out.append("journalRoomYear| \(year.year) · \(JournalRoom.yearLine(year))"
                       + " · days=\(year.days)"
                       + " · share=\(String(format: "%.2f", JournalRoom.share(entries: year.entries, of: top)))"
                       + " · newest=\(year.newestRef ?? "none")")
        }
        return out
    }
}
