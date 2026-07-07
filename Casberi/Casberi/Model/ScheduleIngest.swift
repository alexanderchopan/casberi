import Foundation
import EventKit
import SwiftData

/// Calendar and Reminders as READ bridges — Bob's actual day lands in the
/// feed with zero setup (the biggest open feeds he has are the system's own).
/// Same law as Photos: the permission ask arrives in context, and connect
/// ends in proof — things land. Dedupe rides sourceRef.
enum ScheduleIngest {

    /// Events from the last week through the end of today — the feed shows
    /// what happened and what's happening, not next week's agenda.
    static func connectCalendar(context: ModelContext) async -> Int? {
        let store = EKEventStore()
        guard (try? await store.requestFullAccessToEvents()) == true else { return nil }

        let cal = Calendar.current
        let start = Date.now.addingTimeInterval(-7 * 86_400)
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now)) ?? .now
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)

        let existing = existingRefs(context: context)
        var added = 0
        for event in events {
            let ref = "ekevent:\(event.eventIdentifier ?? UUID().uuidString)"
            guard !existing.contains(ref) else { continue }
            let thing = Thing(
                kind: .event,
                title: event.title ?? "Event",
                content: eventLine(event),
                source: "Calendar",
                capturedAt: event.startDate ?? .now,
                sourceRef: ref
            )
            context.insert(thing)
            added += 1
        }
        try? context.save()
        return added
    }

    /// Completes (or un-completes) the real reminder behind a thing — the
    /// lightest write (shaped-feeds ruling): the check circle is the consent,
    /// tapping again is the undo. No-op for things that aren't EK-backed
    /// (demo corpus) — those just mark locally.
    static func setCompleted(_ sourceRef: String?, _ done: Bool) async {
        guard let ref = sourceRef, ref.hasPrefix("ekreminder:") else { return }
        let id = String(ref.dropFirst("ekreminder:".count))
        let store = EKEventStore()
        guard (try? await store.requestFullAccessToReminders()) == true,
              let reminder = store.calendarItem(withIdentifier: id) as? EKReminder
        else { return }
        reminder.isCompleted = done
        try? store.save(reminder, commit: true)
    }

    /// Open reminders — the list as it stands.
    static func connectReminders(context: ModelContext) async -> Int? {
        let store = EKEventStore()
        guard (try? await store.requestFullAccessToReminders()) == true else { return nil }

        let predicate = store.predicateForReminders(in: nil)
        let reminders: [EKReminder] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { cont.resume(returning: $0 ?? []) }
        }

        let existing = existingRefs(context: context)
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
            context.insert(thing)
            added += 1
        }
        try? context.save()
        return added
    }

    // MARK: - Pieces

    private static func existingRefs(context: ModelContext) -> Set<String> {
        let refs = ((try? context.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.sourceRef != nil }
        ))) ?? []).compactMap(\.sourceRef)
        return Set(refs)
    }

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
