import Foundation
import SwiftData

/// The Polar room head's reading half (2026-08-30) — `StripeRoomSource`'s
/// exact split and reason: this file touches `Thing` and `UserDefaults` and so
/// can never be compiled by a harness, while `PolarRoom.swift` is
/// Foundation-only and compiled WHOLE by `scripts/polar-selftest.sh`.
enum PolarRoomSource {

    static let horizonDays = 90
    static let overdueGraceDays = 14
    static let rowCap = 4

    @MainActor
    static func compose(things: [Thing], now: Date = .now) -> PolarRoom? {
        let reading = PolarState.reading()

        // Filtered to live at the BOUNDARY, before a single stored property
        // is read (corollary 4) — the caller's array may be a debounced
        // snapshot.
        var items: [PolarRoom.Item] = []
        for thing in things.live where thing.source == "Polar" {
            guard let due = thing.dueAt, thing.tags.contains("Dispute") else { continue }
            let days = PolarRoom.days(from: now, to: due)
            guard days <= horizonDays, days >= -overdueGraceDays else { continue }
            items.append(PolarRoom.Item(id: thing.sourceRef ?? thing.id.uuidString,
                                        name: thing.title, due: due, days: days))
        }
        items.sort { $0.days < $1.days }

        let room = PolarRoom(mrr: PolarState.mrrText(),
                             activeSubscriptions: reading.activeSubscriptions,
                             asOf: reading.fetchedAt,
                             items: Array(items.prefix(rowCap)),
                             total: items.count)
        return room.isEmpty ? nil : room
    }

    /// The probe's lines — driven by `-polarRoomProbe`, calling the REAL
    /// `compose` (`CloudflareRunwaySource.probeLines`'s rule: a probe must
    /// not be able to disagree with the card it explains).
    @MainActor
    static func probeLines(context: ModelContext, now: Date = .now) -> [String] {
        let things = ((try? context.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Polar" },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]))) ?? []).live
        let reading = PolarState.reading()
        var out: [String] = [
            "connected=\(TokenBridge.polar.connected) rows=\(things.count)",
            "mrr=\(PolarState.mrrText() ?? "UNREAD")"
                + " activeSubs=\(reading.activeSubscriptions.map(String.init) ?? "nil")"
                + " asOf=\(reading.fetchedAt.map { PolarRoom.staleNote(asOf: $0, now: now) ?? "fresh" } ?? "NEVER READ")",
            "withDueAt=\(things.filter { $0.dueAt != nil }.count)",
        ]
        guard let room = compose(things: things, now: now) else {
            out.append("compose=nil — no card (nothing read, nothing due)")
            return out
        }
        out.append("headline=\(PolarRoom.headline(room))")
        out.append("note=\(PolarRoom.note(room))")
        let span = PolarRoom.span(days: room.items.map(\.days))
        out.append("span=\(span) (\(PolarRoom.spanLabel(span: span)))")
        for item in room.items {
            out.append("item| \(item.name) · days=\(item.days) · \(PolarRoom.value(days: item.days))"
                       + " · pos=" + String(format: "%.2f", PolarRoom.position(days: item.days, span: span)))
        }
        return out
    }
}
