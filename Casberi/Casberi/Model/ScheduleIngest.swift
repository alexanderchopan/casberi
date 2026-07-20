import Foundation
import EventKit
import SwiftData

/// Calendar and Reminders as READ bridges — Bob's actual day lands in the
/// feed with zero setup (the biggest open feeds he has are the system's own).
/// Same law as Photos: the permission ask arrives in context, and connect
/// ends in proof — things land. Dedupe rides sourceRef.
enum ScheduleIngest {

    /// How far ahead calendar events are pulled. Re-ruling 2026-07-14: the feed
    /// used to stop at the end of today ("the calendar owns the future"); it
    /// now reaches a week ahead so imminent events can surface as things. Past
    /// events still start a week back, so the window is a rolling ±7 days.
    static let forwardWindow: TimeInterval = 7 * 86_400

    /// Events from a week back through a week ahead — the past feeds the
    /// record, the next seven days feed imminent-event things (re-ruling
    /// 2026-07-14). BridgeRefresh re-runs this each foreground, so the
    /// forward window rolls.
    ///
    /// Recurring events (2026-07-14): EventKit hands every occurrence of a
    /// recurring event the SAME `eventIdentifier`, so a daily meeting arrives as
    /// N EKEvents sharing one id. We represent each series by ONE thing, keyed
    /// on that id, whose date is the series' NEXT upcoming occurrence (or, when
    /// the whole series is behind, its most recent past one, so it still shows
    /// in the record). Each foreground refreshes that thing forward as
    /// occurrences pass. A one-off event is just a series of one, handled the
    /// same way. Before this, dedupe on the shared id kept only the first
    /// occurrence seen — usually already past — so recurring meetings never
    /// reached "Coming up".
    static func connectCalendar(context: ModelContext) async -> Int? {
        let store = EKEventStore()
        guard (try? await store.requestFullAccessToEvents()) == true else { return nil }

        let start = Date.now.addingTimeInterval(-7 * 86_400)
        let end = Date.now.addingTimeInterval(forwardWindow)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)

        // Collapse each series to the occurrence that best represents it. The
        // series key is the event id, falling back to `calendarItemIdentifier`
        // — a Birthdays/holidays/subscribed-calendar event often has a nil
        // `eventIdentifier`, and the old `?? UUID()` minted a fresh ref every
        // refresh, re-inserting it as a duplicate each foreground; the stable
        // fallback lets those dedupe (and reach "Coming up" — a birthday is
        // exactly the kind of thing that belongs there). An event with no start
        // can't be placed on the timeline, so skip it.
        let now = Date.now
        var representative: [String: EKEvent] = [:]
        for event in events {
            let id = event.eventIdentifier ?? event.calendarItemIdentifier
            guard !id.isEmpty, event.startDate != nil else { continue }
            if let chosen = representative[id] {
                representative[id] = betterOccurrence(chosen, event, now: now)
            } else {
                representative[id] = event
            }
        }

        let existing = IngestSupport.thingsByRef(context, source: "Calendar")
        var added = 0
        for (id, event) in representative {
            let ref = "ekevent:\(id)"
            let when = event.startDate ?? now
            if let thing = existing[ref] {
                // Refresh the stored row forward as the series' representative
                // moves to the next occurrence (or the time/title was edited).
                if thing.capturedAt != when {
                    thing.capturedAt = when
                    thing.title = event.title ?? thing.title
                    thing.content = eventLine(event)
                }
                continue
            }
            let thing = Thing(
                kind: .event,
                title: event.title ?? "Event",
                content: eventLine(event),
                source: "Calendar",
                capturedAt: when,
                sourceRef: ref
            )
            context.insert(thing)
            added += 1
        }
        context.saveHonestly()
        return added
    }

    /// The occurrence that best stands for a series: the soonest one still ahead
    /// (the next upcoming), else — when the whole series is behind — the most
    /// recent past one. A consistent total order, so reducing the occurrences
    /// pairwise lands on the global best.
    private static func betterOccurrence(_ a: EKEvent, _ b: EKEvent, now: Date) -> EKEvent {
        let sa = a.startDate ?? .distantPast
        let sb = b.startDate ?? .distantPast
        switch (isAhead(a, now: now), isAhead(b, now: now)) {
        case (true, true):   return sa <= sb ? a : b   // both ahead → soonest
        case (true, false):  return a                  // ahead beats behind
        case (false, true):  return b
        case (false, false): return sa >= sb ? a : b   // both behind → most recent
        }
    }

    /// Whether an occurrence still counts as "ahead" for representing its
    /// series. A timed event is ahead until its start passes; an ALL-DAY event
    /// starts at 00:00, so it counts as ahead for the whole of its day — else
    /// today's all-day occurrence of a recurring series (a birthday, a daily
    /// all-day block) would read as past by mid-afternoon and the row would jump
    /// to tomorrow's instance, hiding the one happening today. Uses EKEvent's
    /// authoritative `isAllDay` flag (not a midnight guess).
    private static func isAhead(_ event: EKEvent, now: Date) -> Bool {
        guard let start = event.startDate else { return false }
        return event.isAllDay
            ? start >= Calendar.current.startOfDay(for: now)
            : start >= now
    }

    /// Completes (or un-completes) the real reminder behind a thing — the
    /// lightest write (shaped-feeds ruling): the check circle is the consent,
    /// tapping again is the undo. No-op (returns `true`, nothing to fail) for
    /// things that aren't EK-backed (demo corpus) — those just mark locally.
    /// Returns whether the real reminder actually changed, so the caller can
    /// tell the truth instead of an optimistic toast that outlives a failed
    /// write (honesty rule — a check mark that silently doesn't stick is
    /// exactly the "fake status" the design law bans).
    @discardableResult
    static func setCompleted(_ sourceRef: String?, _ done: Bool) async -> Bool {
        guard let ref = sourceRef, ref.hasPrefix("ekreminder:") else { return true }
        let id = String(ref.dropFirst("ekreminder:".count))
        let store = EKEventStore()
        guard (try? await store.requestFullAccessToReminders()) == true,
              let reminder = store.calendarItem(withIdentifier: id) as? EKReminder
        else { return false }
        reminder.isCompleted = done
        do {
            try store.save(reminder, commit: true)
            return true
        } catch {
            return false
        }
    }

    /// Open reminders — the list as it stands.
    static func connectReminders(context: ModelContext) async -> Int? {
        let store = EKEventStore()
        guard (try? await store.requestFullAccessToReminders()) == true else { return nil }

        let predicate = store.predicateForReminders(in: nil)
        let reminders: [EKReminder] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { cont.resume(returning: $0 ?? []) }
        }

        let existing = IngestSupport.existingSourceRefs(context)
        var added = 0
        for reminder in reminders where !reminder.isCompleted {
            let ref = "ekreminder:\(reminder.calendarItemIdentifier)"
            guard !existing.contains(ref) else { continue }
            let thing = Thing(
                kind: .reminder,
                title: reminder.title ?? "Reminder",
                content: dueLine(reminder),
                source: "Reminders",
                capturedAt: reminder.creationDate ?? .now,
                sourceRef: ref
            )
            // The structured deadline for the "Coming up" lane — capturedAt is
            // the creation time, so the due date rides its own field.
            thing.dueAt = reminder.dueDateComponents?.date
            context.insert(thing)
            added += 1
        }
        context.saveHonestly()
        return added
    }

    // MARK: - Pieces

    private static func eventLine(_ event: EKEvent) -> String {
        var parts: [String] = []
        if let start = event.startDate {
            parts.append(event.isAllDay
                ? "All day"
                : start.formatted(date: .omitted, time: .shortened))
        }
        if let location = event.location, !location.isEmpty {
            parts.append(location)
        }
        return parts.joined(separator: " · ")
    }

    private static func dueLine(_ reminder: EKReminder) -> String {
        guard let due = reminder.dueDateComponents?.date else { return "" }
        return "Due \(due.formatted(date: .abbreviated, time: .omitted))"
    }
}
