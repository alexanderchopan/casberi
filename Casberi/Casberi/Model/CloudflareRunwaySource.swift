import Foundation
import SwiftData

/// The reading half of the Cloudflare runway (prd §296) — landed rows plus the
/// pass's own estate snapshot, in, one `CloudflareRunway` out.
///
/// Split from `CloudflareRunway` for the reason `WalletApprovalExposureSource`
/// is split from its model: everything here touches `Thing` and UserDefaults
/// and therefore cannot be compiled by the harness, so it is kept as thin as
/// it can be — classify, name, hand over. Every judgement worth testing lives
/// on the other side of this file.
///
/// **It spends nothing.** No request, no new `Thing` field, no CloudKit
/// deploy: the dates are already on rows the room is holding, and the two
/// facts a row can't carry (which zone a certificate belongs to, whether a
/// registration auto-renews) come from the snapshot the pass already writes.
enum CloudflareRunwaySource {

    /// Nil when there is nothing to draw — no completed pass, or a pass that
    /// found neither a deadline nor a date to name. See `CloudflareRunway`.
    ///
    /// `things.live` at the boundary, then no suspension: this is synchronous
    /// and `@MainActor`, so nothing can delete a `Thing` between the filter and
    /// the reads (liveness corollaries 4 and 6).
    @MainActor
    static func compose(things: [Thing], now: Date = .now) -> CloudflareRunway? {
        guard let estate = CloudflareEstateStore.load() else { return nil }

        var items: [CloudflareRunway.Item] = []
        // `where thing.isLive` rather than `things.live`: the same guarantee
        // (still synchronous, still `@MainActor`, so nothing can delete between
        // the check and the reads) without allocating a filtered copy of the
        // whole room on every render.
        for thing in things where thing.isLive {
            guard thing.source == "Cloudflare",
                  thing.mark != .done,
                  let ref = thing.sourceRef,
                  let item = item(ref: ref, title: thing.title, dueAt: thing.dueAt,
                                  estate: estate, now: now)
            else { continue }
            items.append(item)
        }

        let ranked = CloudflareRunway.rank(items)
        let runway = CloudflareRunway(items: ranked,
                                      zonesSeen: estate.zonesSeen,
                                      uncovered: estate.uncovered,
                                      next: ranked.isEmpty ? nextDate(estate, now: now) : nil)
        return runway.isEmpty ? nil : runway
    }

    /// One landed row as a rail item, or nil if it isn't one.
    ///
    /// DNS rows are the deliberate nil: they are EVENTS stamped with their
    /// moment — what a record changed to on Tuesday is not a deadline, and the
    /// reconcile already exempts them for the same reason.
    static func item(ref: String, title: String, dueAt: Date?,
                     estate: CloudflareEstate, now: Date) -> CloudflareRunway.Item? {
        func days() -> Int? { dueAt.flatMap { CloudflareFetch.daysUntil($0, from: now) } }

        if ref == "cloudflare:token" {
            guard let d = days() else { return nil }
            return .init(id: ref, name: String(localized: "API token"), named: true,
                         kind: .token, days: d, autoRenews: nil)
        }
        if let id = suffix(ref, after: "cloudflare:cert:") {
            guard let d = days() else { return nil }
            let name = estate.zoneNames[id]
            return .init(id: ref, name: name ?? title, named: name != nil,
                         kind: .certificate, days: d, autoRenews: nil)
        }
        if let name = suffix(ref, after: "cloudflare:domain:") {
            guard let d = days() else { return nil }
            return .init(id: ref, name: name, named: true,
                         kind: .registration, days: d, autoRenews: estate.autoRenew[name])
        }
        if let id = suffix(ref, after: "cloudflare:zone:") {
            // No date, and that is the point: a zone that isn't being served
            // is already true, so it leads the rail rather than sitting on it.
            let name = estate.zoneNames[id]
            return .init(id: ref, name: name ?? title, named: name != nil,
                         kind: .zone, days: nil, autoRenews: nil)
        }
        return nil
    }

    /// The next date the account has, for the quiet card. Refused once it's in
    /// the past — a snapshot whose "next" already happened is stale, and a card
    /// counting down to a date in March would be worse than no card.
    static func nextDate(_ estate: CloudflareEstate, now: Date) -> CloudflareRunway.Next? {
        guard let date = estate.nextDate,
              let raw = estate.nextKind,
              let kind = CloudflareRunway.Kind(rawValue: raw),
              let days = CloudflareFetch.daysUntil(date, from: now), days >= 0
        else { return nil }
        return .init(days: days, date: date, name: estate.nextName ?? "", kind: kind)
    }

    private static func suffix(_ ref: String, after prefix: String) -> String? {
        guard ref.hasPrefix(prefix) else { return nil }
        let rest = String(ref.dropFirst(prefix.count))
        return rest.isEmpty ? nil : rest
    }

    // MARK: - Probe

    /// `-cloudflareRunwayProbe YES` — the card's whole reading, one line at a
    /// time (the `-todayProbe` truncation lesson).
    ///
    /// It exists because a missing runway has FIVE causes that render as the
    /// same nothing, and only two of them are bugs:
    ///
    /// 1. no completed pass, so no estate snapshot (`estate=none`) — connect
    ///    and sync first;
    /// 2. the room holds only DNS event rows, which are correctly not
    ///    deadlines (`skippedEvent`);
    /// 3. every deadline reconciled to done, which is the healthy answer
    ///    (`skippedDone`);
    /// 4. a deadline row with no `dueAt` at all (`skippedUndated` — a bug);
    /// 5. an estate whose `next` is in the past, so even the quiet card
    ///    declines (`next=stale` — a stale snapshot).
    ///
    /// The per-item lines then name the four fields every shaping decision
    /// rests on: kind, whether the estate could NAME it, days, and auto-renew.
    /// A run where every row reads `named=NO` is the zone table failing to
    /// join, which on screen looks merely wordy rather than broken.
    @MainActor
    static func probeLines(context: ModelContext) -> [String] {
        var out: [String] = []
        guard let estate = CloudflareEstateStore.load() else {
            return ["estate=none — no completed Cloudflare pass on this device; connect with -tokenBridge \"Cloudflare:<token>\" and sync first"]
        }
        out.append("estate zones=\(estate.zonesSeen) covered=\(estate.zonesCovered) uncovered=\(estate.uncovered) named=\(estate.zoneNames.count) registrar=\(estate.autoRenew.count)")

        let now = Date.now
        if let date = estate.nextDate {
            let days = CloudflareFetch.daysUntil(date, from: now) ?? 0
            out.append("estate next=\(ISO8601DateFormatter().string(from: date)) in \(days)d name=\(estate.nextName ?? "—") kind=\(estate.nextKind ?? "—")\(days < 0 ? " STALE (a past date can't be next — the quiet card will decline)" : "")")
        } else {
            out.append("estate next=none — the quiet card can't name a date, so a healthy room draws nothing")
        }

        let all = (try? context.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Cloudflare" }))) ?? []

        // The tallies are the only thing this probe derives for itself, and
        // they are the whole point: `compose` throws away WHY a row didn't
        // become a deadline, and that why is what separates the five causes.
        var skippedDone = 0, skippedEvent = 0, skippedUndated = 0, rows = 0
        for thing in all where thing.isLive {
            rows += 1
            guard let ref = thing.sourceRef else { continue }
            if thing.mark == .done { skippedDone += 1; continue }
            if ref.hasPrefix("cloudflare:dns:") { skippedEvent += 1; continue }
            if item(ref: ref, title: thing.title, dueAt: thing.dueAt,
                    estate: estate, now: now) == nil { skippedUndated += 1 }
        }

        // Everything below reads off the REAL composition — never a second
        // implementation of it. A probe whose job is explaining the card must
        // not be able to disagree with the card.
        guard let runway = compose(things: all, now: now) else {
            out.append("corpus rows=\(rows) skippedDone=\(skippedDone) skippedEvent=\(skippedEvent) skippedUndated=\(skippedUndated)")
            out.append("card=NONE — nothing to draw: no deadline survived and no usable next date")
            return out
        }
        out.append("corpus rows=\(rows) deadlines=\(runway.items.count) skippedDone=\(skippedDone) skippedEvent=\(skippedEvent) skippedUndated=\(skippedUndated)")

        if let next = runway.next {
            out.append("card=QUIET \(CloudflareRunway.quietHeadline(days: next.days))")
            out.append("card note=\(CloudflareRunway.quietNote(next))")
        } else {
            out.append("card=LOADED span=\(runway.span)d headline=\(CloudflareRunway.headline(items: runway.items, span: runway.span))")
            if let head = runway.items.first {
                out.append("card note=\(CloudflareRunway.note(for: head, alone: runway.items.count == 1))")
            }
        }
        for item in runway.items {
            let pos = CloudflareRunway.position(days: item.days, span: runway.span)
            out.append(String(format: "cfRunwayRow| kind=%@ name=%@ named=%@ days=%@ auto=%@ value=%@ rail=%.2f",
                              item.kind.rawValue, item.name, item.named ? "YES" : "NO",
                              item.days.map(String.init) ?? "none (already true)",
                              item.autoRenews.map { $0 ? "YES" : "NO" } ?? "—",
                              CloudflareRunway.value(days: item.days), pos))
        }
        if let note = CloudflareRunway.coverageNote(uncovered: runway.uncovered,
                                                    zonesSeen: runway.zonesSeen) {
            out.append("card coverage=\(note)")
        }
        return out
    }
}
