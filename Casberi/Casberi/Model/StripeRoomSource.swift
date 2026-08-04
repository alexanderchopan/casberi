import Foundation
import SwiftData

/// The Stripe room head's reading half (2026-08-04, prd §298) — landed rows
/// joined against the balance snapshot, with every judgement left to
/// `StripeRoom`.
///
/// The split is `CloudflareRunwaySource`'s and exists for its reason: this file
/// touches `Thing` and `UserDefaults` and so can never be compiled by a
/// harness, while `StripeRoom.swift` is Foundation-only and is compiled WHOLE
/// by `scripts/stripe-room-selftest.sh`. Everything that could be wrong in a
/// way that still renders — a deadline placed at the wrong point on the rail, a
/// headline claiming a week on a dispute due tomorrow, an overdue row sorted
/// last — lives on the other side of that line.
enum StripeRoomSource {

    /// How far ahead a deadline is still worth drawing. Past this it isn't a
    /// deadline yet, it's a date.
    static let horizonDays = 90
    /// How far BACK an overdue deadline keeps its place at the head of the
    /// rail. A dispute whose window closed two months ago is decided; keeping
    /// it would make the card permanently alarmed about nothing actionable.
    static let overdueGraceDays = 14
    /// The card draws at most this many rows; the rest are counted in the
    /// coverage note rather than silently dropped.
    static let rowCap = 4

    @MainActor
    static func compose(things: [Thing], now: Date = .now) -> StripeRoom? {
        let balance = StripeState.balance()

        // Filtered to live at the BOUNDARY, before a single stored property is
        // read (corollary 4) — the caller's array may be a debounced snapshot.
        var items: [StripeRoom.Item] = []
        for thing in things.live where thing.source == "Stripe" {
            guard let due = thing.dueAt else { continue }
            let days = StripeRoom.days(from: now, to: due)
            guard days <= horizonDays, days >= -overdueGraceDays else { continue }
            let dispute = thing.tags.contains("Dispute")
            // Only the two shapes that actually carry a clock. A payout or a
            // churn row has no `dueAt`, so this is belt-and-braces — but a new
            // shape gaining one shouldn't silently appear on the rail wearing
            // a dispute's chip.
            guard dispute || thing.tags.contains("Dunning") else { continue }
            items.append(StripeRoom.Item(id: thing.sourceRef ?? thing.id.uuidString,
                                         name: thing.title, due: due,
                                         days: days, dispute: dispute))
        }
        // Soonest first, overdue leading — the rail's own order, so the rows
        // and the marks can never disagree about which one is the lead.
        items.sort { $0.days < $1.days }

        let room = StripeRoom(available: StripeState.availableText(),
                              pending: pendingText(balance),
                              arrivesAt: balance.arrivesAt,
                              asOf: balance.fetchedAt,
                              items: Array(items.prefix(rowCap)),
                              // The uncapped count, so the headline can't
                              // disagree with the coverage note beneath it.
                              total: items.count,
                              stopped: balance.silent)
        return room.isEmpty ? nil : room
    }

    /// The pending twin of `StripeState.availableText()`, spelled here rather
    /// than added there because `availableText` is the SEAT's proof line and
    /// its wording is load-bearing on two other screens. Same rule either way:
    /// per-currency, joined, never summed.
    static func pendingText(_ balance: StripeState.Balance) -> String? {
        let pending = balance.pending.filter { $0.value != 0 }
        guard !pending.isEmpty else { return nil }
        return pending.sorted { $0.key < $1.key }
            .map { StripeMoney.text($0.value, currency: $0.key) }
            .joined(separator: " · ")
    }

    /// How many deadlines exist beyond the ones drawn, for the coverage note.
    @MainActor
    static func totalDeadlines(things: [Thing], now: Date = .now) -> Int {
        things.live.filter { thing in
            guard thing.source == "Stripe", let due = thing.dueAt else { return false }
            let days = StripeRoom.days(from: now, to: due)
            return days <= horizonDays && days >= -overdueGraceDays
                && (thing.tags.contains("Dispute") || thing.tags.contains("Dunning"))
        }.count
    }

    /// The probe's lines — driven by `-stripeRoomProbe`, and deliberately
    /// calling the REAL `compose` rather than reimplementing it: a probe whose
    /// job is explaining the card must not be able to disagree with the card
    /// (`CloudflareRunwaySource.probeLines`' own rule).
    ///
    /// It exists because an empty Stripe head has four causes that render as
    /// one nothing — the bridge isn't connected, the balance has never been
    /// read on this device (a fresh install syncs rows but not UserDefaults),
    /// no row carries a `dueAt`, or every deadline fell outside the window —
    /// and only two of those are worth acting on.
    @MainActor
    static func probeLines(context: ModelContext, now: Date = .now) -> [String] {
        let things = ((try? context.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Stripe" },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]))) ?? []).live
        let balance = StripeState.balance()
        var out: [String] = [
            "connected=\(TokenBridge.stripe.connected) rows=\(things.count)",
            "balance available=\(StripeState.availableText() ?? "UNREAD")"
                + " pending=\(pendingText(balance) ?? "none")"
                + " arrives=\(balance.arrivesAt.map(StripeRoom.dayLabel) ?? "none")"
                + " asOf=\(balance.fetchedAt.map { StripeRoom.staleNote(asOf: $0, now: now) ?? "fresh" } ?? "NEVER READ")"
                + " stopped=\(balance.silent)",
            "withDueAt=\(things.filter { $0.dueAt != nil }.count)"
                + " inWindow=\(totalDeadlines(things: things, now: now))",
        ]
        guard let room = compose(things: things, now: now) else {
            out.append("compose=nil — no card (nothing read, nothing due, no outage)")
            return out
        }
        out.append("headline=\(StripeRoom.headline(room))")
        out.append("note=\(StripeRoom.note(room, now: now))")
        let span = StripeRoom.span(days: room.items.map(\.days))
        out.append("span=\(span) (\(StripeRoom.spanLabel(span: span)))")
        for item in room.items {
            out.append("item| \(item.name) · days=\(item.days) · \(StripeRoom.value(days: item.days))"
                       + " · dispute=\(item.dispute) · pos="
                       + String(format: "%.2f", StripeRoom.position(days: item.days, span: span)))
        }
        return out
    }
}
