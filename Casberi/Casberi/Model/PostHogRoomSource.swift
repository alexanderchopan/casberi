import Foundation
import SwiftData

/// The PostHog room head's reading half (2026-08-04, prd §298) — the watch rows
/// joined against the readings `PostHogState` already holds.
///
/// The split is `StripeRoomSource`/`CloudflareRunwaySource`'s: this file
/// touches `Thing` and `UserDefaults` and can never be harness-compiled, so
/// every judgement that fails invisibly — which metric leads, what the head
/// says, whether a change may be claimed — lives in `PostHogRoom.swift`, which
/// is compiled whole.
enum PostHogRoomSource {

    /// The head draws at most this many discs; the rest are counted in the
    /// coverage note rather than silently dropped. Four is the roster width
    /// that fits without scrolling on the narrowest supported screen.
    static let discCap = 4

    @MainActor
    static func compose(things: [Thing]) -> PostHogRoom? {
        var metrics: [PostHogRoom.Metric] = []
        var unread = 0
        // Filtered live at the BOUNDARY, before any stored property is read
        // (corollary 4) — the caller's array may be a debounced snapshot.
        for thing in things.live where thing.source == "PostHog" {
            guard let event = PostHogWatch.event(from: thing) else { continue }
            let reading = PostHogState.get(event)
            // A watch whose reading has never landed on this device is counted,
            // not drawn. A fresh install syncs the row and not the state, and a
            // roster of empty discs would read as "nothing is happening" when
            // the truth is "we haven't looked yet".
            guard reading.fetchedAt != nil else { unread += 1; continue }
            metrics.append(PostHogRoom.Metric(event: event,
                                              series: reading.series,
                                              total: reading.total,
                                              change: PostHogRoom.change(reading.series),
                                              silent: reading.silent))
        }
        guard !metrics.isEmpty else { return nil }
        return PostHogRoom(metrics: PostHogRoom.ranked(metrics), unread: unread)
    }

    /// The probe's lines — driven by `-posthogRoomProbe`, calling the REAL
    /// `compose` so it can't disagree with the card.
    ///
    /// An empty PostHog head has three causes that render as one nothing: no
    /// metric is watched, the readings have never been fetched on this device,
    /// or every watch row was filtered out. The `watched`/`unread` pair
    /// separates them in one launch — and `-posthogSeed` can plant a reading,
    /// so the whole card verifies with no account at all.
    @MainActor
    static func probeLines(context: ModelContext) -> [String] {
        let watched = PostHogWatch.watchedEvents(context: context)
        let things = ((try? context.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "PostHog" },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]))) ?? []).live
        var out: [String] = [
            "connected=\(TokenBridge.posthog.connected) rows=\(things.count) watched=\(watched.count)",
        ]
        guard let room = compose(things: things) else {
            out.append("compose=nil — no card (nothing watched, or nothing read on this device)")
            return out
        }
        out.append("headline=\(PostHogRoom.headline(room))")
        out.append("note=\(PostHogRoom.note(room, nextRung: PostHogMilestone.next(after:)))")
        out.append("unread=\(room.unread) drawn=\(min(room.metrics.count, discCap))")
        for metric in room.metrics {
            out.append("metric| \(metric.event) · week=\(PostHogRoom.week(metric.series))"
                       + " · total=\(metric.total) · points=\(metric.series.count)"
                       + " · change=\(metric.change.map { String(format: "%.2f", $0) } ?? "unknowable")"
                       + " · silent=\(metric.silent)"
                       + " · nextRung=\(PostHogMilestone.next(after: metric.total))")
        }
        return out
    }
}
