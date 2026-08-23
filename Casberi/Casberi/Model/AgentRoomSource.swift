import Foundation
import SwiftData

/// The agent room head's reading half (2026-08-23, prd §457) — landed rows
/// turned into the card's own value, with every judgement left to `AgentRoom`.
///
/// The split is `JournalRoomSource`'s and exists for its reason: this file
/// touches `Thing` and so can never be compiled by a harness, while
/// `AgentRoom.swift` is Foundation-only and is compiled WHOLE by
/// `scripts/agent-room-selftest.sh`. Everything that could be wrong in a way
/// that still renders perfectly — a month named busiest because ties broke the
/// other way, a strip that skips its silent months and quietly rescales
/// itself, a subject claimed off one mention, a lead date that moves whenever
/// somebody takes a week off — lives on the other side of that line.
enum AgentRoomSource {

    /// The four rooms this head serves, and the ONE place that membership is
    /// written down.
    ///
    /// **Derived from `AgentSheet.assistant(for:)` rather than listed**, so a
    /// fifth agent seat joins this head the day its speaker label lands — the
    /// same registry the row's "24 turns" and the sheet's turn rendering read,
    /// which is what stops the three of them ever disagreeing about what
    /// counts as a conversation with an agent.
    static let sources: Set<String> = ["ChatGPT", "Claude", "Gemini",
                                       ClaudeCodeImport.source]

    /// The head, or nil when this room has no shape to show.
    ///
    /// **`things` is THIS ROOM'S rows and ONLY this room's** — every caller in
    /// the `sourceHead` chain hands a screen's already-scoped `visible`, never
    /// the corpus. That is why `rivals` is a SEPARATE parameter rather than
    /// something this function goes looking for inside `things`: a first
    /// draft tried to find other seats' rows by filtering `things` for a
    /// different `source`, and measured against a real probe (`things=14` for
    /// a 14-row ChatGPT room, exactly its own count and nothing else) it never
    /// found anything, because there was never anything else there to find.
    /// The comparison this card exists to make needs a read the room's own
    /// scoped fetch cannot produce — see `Rivals.fetch`.
    ///
    /// `now` is taken for signature parity with every other `…RoomSource` in
    /// the `sourceHead` chain and is deliberately unused: this card is
    /// entirely historical, so nothing about it may change between two opens
    /// of the same corpus.
    @MainActor
    static func compose(source: String, things: [Thing] = [],
                        rivals: [AgentRoom.Rival] = [], now: Date = .now) -> AgentRoom? {
        _ = now
        guard sources.contains(source) else { return nil }
        // Filtered live at the BOUNDARY before any stored property is read
        // (corollary 4) — the caller's array may be a debounced snapshot, and
        // the foreground sweep deletes rows while it is held.
        let mine = things.live.filter { $0.kind == .chat && !Corpus.isImportReceipt($0) }
        guard !mine.isEmpty else { return nil }
        return AgentRoom.compose(mine.map(sighting), rivals: rivals)
    }

    /// The OTHER agent seats' month histograms, read directly off the store —
    /// the half `compose` cannot do with a room-scoped array, and the reason
    /// this room's head needs a `ModelContext` at all, unlike every sibling
    /// `…RoomSource` in this file's family that reads only `things`.
    ///
    /// A LIGHT fetch on purpose: `capturedAt` and `source` only, never the
    /// transcript — `AgentRoom.Rival` wants counts per month, not turns (see
    /// `AgentRoom.comparison`'s no-turns rule), so pulling the retrieval body
    /// across the whole corpus for a card that never reads it would be the
    /// cost with none of the benefit.
    ///
    /// `context.fetch` rather than `@Query`: this runs from inside a screen's
    /// own head computation (`FeedScreen.recomputeHeads`), off the render
    /// body, where a fresh `@Query` cannot be declared.
    @MainActor
    static func rivals(besides source: String, context: ModelContext) -> [AgentRoom.Rival] {
        let others = sources.subtracting([source])
        guard !others.isEmpty else { return [] }
        // Kind filter runs in memory — `#Predicate` can't compare the Codable
        // `ThingKind` (`CatalogTaste.swift`'s note, the same wall every other
        // kind-scoped fetch in this codebase runs into). `source != source`
        // scopes the fetch to strings, which a predicate CAN do, so the walk
        // is bounded to the other seats before anything is filtered in memory.
        let descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source != source })
        let rows = ((try? context.fetch(descriptor)) ?? []).live
            .filter { $0.kind == .chat && others.contains($0.source) && !Corpus.isImportReceipt($0) }
        var byName: [String: [Int: Int]] = [:]
        for thing in rows {
            let ordinal = monthOrdinal(thing.capturedAt)
            byName[thing.source, default: [:]][ordinal, default: 0] += 1
        }
        return byName.map { AgentRoom.Rival(name: $0.key, months: $0.value) }
    }

    /// ONE calendar for every row, taken once. Asking `Calendar.current` per
    /// row is both slower and — across a run that spans a timezone change —
    /// capable of filing two conversations from the same minute in different
    /// months (`XRoomSource`'s rule).
    private static let calendar = Calendar.current

    /// The month ordinal `AgentRoom` expects: `year * 12 + (month - 1)`.
    ///
    /// The encoding is the contract (`AgentRoom.Sighting.month`) — the card
    /// inverts it to label an axis, so a different packing here draws the
    /// right bars under the wrong month names, which is the failure that
    /// renders perfectly.
    private static func monthOrdinal(_ date: Date) -> Int {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return (parts.year ?? 0) * 12 + ((parts.month ?? 1) - 1)
    }

    /// One landed row, reduced to the facts the head reads. The ONLY place a
    /// `Thing` is touched.
    ///
    /// The day ordinal is `ordinality(of: .day, in: .era, …)` — a day NUMBER,
    /// so a span is a difference of day numbers with no arithmetic on seconds
    /// anywhere. A `timeIntervalSince` divided by 86,400 would be wrong twice
    /// a year in every zone that observes daylight saving.
    @MainActor
    private static func sighting(_ thing: Thing) -> AgentRoom.Sighting {
        AgentRoom.Sighting(
            ref: thing.sourceRef,
            month: monthOrdinal(thing.capturedAt),
            day: calendar.ordinality(of: .day, in: .era, for: thing.capturedAt) ?? 0,
            // Straight through, nil included — `AgentRoom` counts an unknown
            // length apart from a known one rather than reading nil as zero.
            turns: thing.messageCount,
            // Stamped by the room's own `ScreenshotTopics` sweep, so it is the
            // SAME vocabulary the treemap ranks — which is what lets this card
            // claim to carry the treemap's signal along time rather than a
            // second opinion of it.
            terms: thing.ocrTopics,
            title: thing.title)
    }

    /// The probe's lines — driven by `-roomInsightProbe`, and deliberately
    /// calling the REAL `compose` rather than reimplementing it: a probe whose
    /// job is explaining the card must not be able to disagree with the card
    /// (`PeerRoomSource.probeLines`' rule).
    ///
    /// It exists because an empty head has SIX causes that render as one
    /// nothing, and only the last two are bugs:
    ///
    ///   1. nothing imported, so the room has no rows at all;
    ///   2. fewer than `AgentRoom.minimumConversations` conversations, or a
    ///      span under `minimumMonths`/`minimumSpanDays` — the card declining
    ///      on purpose, and the topic map leads instead;
    ///   3. a span that LOOKS like two months and is a fortnight across the
    ///      31st, which the day floor refuses and the month count would pass;
    ///   4. the topic sweep hasn't run, so every month is subject-less — the
    ///      card still draws, and its own footnote says so;
    ///   5. no row carrying a `messageCount`, so there is no longest and no
    ///      turn figure — which for "Claude Code" was the state of the world
    ///      until §457, since nothing swept that source at all;
    ///   6. `capturedAt` not resolving to plausible months, which draws a
    ///      strip spanning centuries and is invisible from a feed sorted by
    ///      the same field.
    ///
    /// Hence one line PER MONTH (the `-todayProbe` truncation lesson).
    ///
    /// Takes a `context` — unlike every sibling `probeLines` in this file's
    /// family — because the rivals it reports are read the same way the real
    /// card reads them: off the store, not off `things`, which `compose`'s own
    /// doc explains is scoped to this room alone.
    @MainActor
    static func probeLines(source: String, things: [Thing], context: ModelContext,
                           now: Date = .now) -> [String] {
        let mine = things.live.filter { $0.kind == .chat && !Corpus.isImportReceipt($0) }
        var out: [String] = [
            "agentRoom| source=\(source) conversations=\(mine.count)"
                + " minConversations=\(AgentRoom.minimumConversations)"
                + " minMonths=\(AgentRoom.minimumMonths)"
                + " minSpanDays=\(AgentRoom.minimumSpanDays)",
        ]
        // Coverage of the two fields the card's extras rest on, BEFORE
        // composition: a card with no subjects and no turn figure is healthy
        // or broken depending entirely on these numbers.
        let withTerms = mine.filter { !$0.ocrTopics.isEmpty }.count
        let withTurns = mine.filter { $0.messageCount != nil }.count
        out.append("agentRoomFields| topicsStamped=\(withTerms)/\(mine.count)"
                   + " turnsStamped=\(withTurns)/\(mine.count)")
        let dayOrdinals = mine.compactMap {
            calendar.ordinality(of: .day, in: .era, for: $0.capturedAt)
        }
        if let lo = dayOrdinals.min(), let hi = dayOrdinals.max() {
            out.append("agentRoomSpan| days=\(hi - lo) distinctDays=\(Set(dayOrdinals).count)")
        }
        // The rivals, named BEFORE composition — a missing comparison line is
        // otherwise indistinguishable from a comparison that was made and lost.
        let others = rivals(besides: source, context: context)
        out.append("agentRoomRivals| " + (others.isEmpty
            ? "none — only one agent seat has anything in it"
            : others.sorted { $0.total > $1.total }
                .map { "\($0.name)=\($0.total)" }.joined(separator: " ")))
        guard let room = compose(source: source, things: things, rivals: others, now: now) else {
            out.append("compose=nil — no card (nothing imported, or under the floors above)")
            return out
        }
        out.append("headline=\(AgentRoom.headline(room) ?? "none — the note leads")")
        out.append("note=\(AgentRoom.note(room))")
        out.append("comparison=\(AgentRoom.comparison(room) ?? "none")")
        out.append("footnote=\(AgentRoom.footnote(room) ?? "none")")
        out.append("totals| span=\(room.span) silent=\(room.silent)"
                   + " total=\(room.total) turns=\(room.turns) counted=\(room.counted)"
                   + " days=\(room.days)"
                   + " busiest=\(AgentRoom.monthLabel(room.busiest.month))"
                   + " longest=\(room.longest.map { "\($0.turns)" } ?? "none")"
                   + " leadSince=\(room.leadSince.map(AgentRoom.monthLabel) ?? "none")")
        let top = room.busiest.conversations
        for month in room.months {
            out.append("agentRoomMonth| \(AgentRoom.monthLabel(month.month))"
                       + " · \(AgentRoom.monthLine(month))"
                       + " · turns=\(month.turns)"
                       + " · share=\(String(format: "%.2f", AgentRoom.share(conversations: month.conversations, of: top)))"
                       + " · newest=\(month.newestRef ?? "none")")
        }
        return out
    }
}
