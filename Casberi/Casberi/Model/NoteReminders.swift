import Foundation
import EventKit
import SwiftData

/// A CHECKLIST ITEM THAT RINGS (prd §1022): hold an item on a note of yours
/// and **Remind me** makes a reminder in Reminders — in a list named Casberi,
/// titled with the item, due at the time you picked, with this note as its
/// link — and the item shows when at its trailing edge.
///
/// This amends the 2026-07-25 "we don't write" ruling (`HandOff`) for ONE
/// case: a reminder the app itself made. Ticking the item here completes
/// that reminder; completing it in Reminders ticks the item on the next read
/// (`ScheduleIngest.ingestReminders` already carries done-state back). A
/// reminder you made in Reminders is still never touched.
///
/// The record is a fact on the note — `label` the item's words, `value` the
/// reminder's identifier and its time, `action: .reminder` — so it syncs
/// with the note and needs nothing CloudKit has to learn; a build before
/// this one decodes the action to `.none` and draws "Passport · <date>",
/// which is still true.
enum NoteReminders {
    static let listName = "Casberi"
    private static let sep = "|"

    struct Entry: Equatable {
        let id: String
        let date: Date
    }

    enum Failure: Error {
        case refused, noList, saveFailed
    }

    // MARK: - The record

    static func entry(for item: String, on note: Thing) -> Entry? {
        let k = key(item)
        for fact in note.factList where fact.action == .reminder && key(fact.label) == k {
            return decode(fact.value)
        }
        return nil
    }

    /// The item's words as the fact's key: trimmed, case-folded.
    static func key(_ item: String) -> String {
        item.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func decode(_ value: String) -> Entry? {
        guard let cut = value.firstIndex(of: Character(sep)) else { return nil }
        let id = String(value[..<cut])
        let stamp = String(value[value.index(after: cut)...])
        guard !id.isEmpty, let seconds = Double(stamp) else { return nil }
        return Entry(id: id, date: Date(timeIntervalSince1970: seconds))
    }

    static func encode(_ entry: Entry) -> String {
        entry.id + sep + String(Int(entry.date.timeIntervalSince1970))
    }

    /// The fact, written or replaced; nil removes it.
    static func record(_ entry: Entry?, for item: String, on note: Thing) {
        let k = key(item)
        var facts = note.factList.filter { !($0.action == .reminder && key($0.label) == k) }
        if let entry {
            facts.append(ThingFact(item.trimmingCharacters(in: .whitespacesAndNewlines),
                                   encode(entry), .reminder))
        }
        note.facts = facts.map(\.encoded)
    }

    /// The item's words at an ordinal, as `NoteChecklist` counts them.
    static func item(at ordinal: Int, in content: String) -> String? {
        let items = content.components(separatedBy: "\n").compactMap(NoteChecklist.task)
        guard items.indices.contains(ordinal) else { return nil }
        return items[ordinal].text
    }

    // MARK: - When

    /// "Tomorrow 9:00", "Thu 6:00 PM", "Mar 4, 9:00 AM" — the row's word.
    static func label(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let clock = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Today \(clock)") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) { return String(localized: "Tomorrow \(clock)") }
        if let week = calendar.date(byAdding: .day, value: 6, to: now), date < week, date > now {
            return date.formatted(.dateTime.weekday(.abbreviated)) + " " + clock
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    struct Quick: Identifiable, Equatable {
        let name: String
        let glyph: String
        let date: Date
        var id: String { name }
    }

    /// The two fixed times the tray offers before Pick a time: tonight at
    /// six while it is still ahead, and tomorrow at nine.
    static func quickTimes(now: Date = .now, calendar: Calendar = .current) -> [Quick] {
        var out: [Quick] = []
        let today = calendar.startOfDay(for: now)
        if let tonight = calendar.date(byAdding: .hour, value: 18, to: today),
           tonight.timeIntervalSince(now) > 30 * 60 {
            out.append(Quick(name: String(localized: "Tonight"), glyph: "moon", date: tonight))
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
           let nine = calendar.date(byAdding: .hour, value: 9, to: tomorrow) {
            out.append(Quick(name: String(localized: "Tomorrow"), glyph: "sunrise", date: nine))
        }
        return out
    }

    // MARK: - Reminders

    /// Make or move the item's reminder. Asks for Reminders access the first
    /// time, through the system's own sheet.
    @MainActor
    static func set(item: String, on note: Thing, at date: Date, context: ModelContext) async -> Result<Entry, Failure> {
        let store = EKEventStore()
        guard (try? await store.requestFullAccessToReminders()) == true else { return .failure(.refused) }
        guard let list = list(in: store) else { return .failure(.noList) }
        let reminder: EKReminder
        if let existing = entry(for: item, on: note),
           let found = store.calendarItem(withIdentifier: existing.id) as? EKReminder {
            reminder = found
            reminder.alarms?.forEach(reminder.removeAlarm)
        } else {
            reminder = EKReminder(eventStore: store)
            reminder.calendar = list
        }
        reminder.title = item.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.notes = TitleSeam.split(note.title).name
        reminder.url = URL(string: "casberi://thing/\(note.id.uuidString)")
        reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        reminder.addAlarm(EKAlarm(absoluteDate: date))
        reminder.isCompleted = false
        do { try store.save(reminder, commit: true) } catch { return .failure(.saveFailed) }
        let made = Entry(id: reminder.calendarItemIdentifier, date: date)
        record(made, for: item, on: note)
        context.saveHonestly()
        return .success(made)
    }

    /// Remove the item's reminder, from Reminders and from the note.
    @MainActor
    static func remove(item: String, on note: Thing, context: ModelContext) async {
        if let existing = entry(for: item, on: note) {
            let store = EKEventStore()
            if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess,
               let found = store.calendarItem(withIdentifier: existing.id) as? EKReminder {
                try? store.remove(found, commit: true)
            }
        }
        record(nil, for: item, on: note)
        context.saveHonestly()
    }

    /// A tick here completes the reminder the app made; an untick reopens
    /// it. Silent: the tick is the act, and the reminder follows it.
    @MainActor
    static func sync(item: String, done: Bool, on note: Thing) {
        guard let existing = entry(for: item, on: note),
              EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return }
        let store = EKEventStore()
        guard let found = store.calendarItem(withIdentifier: existing.id) as? EKReminder,
              found.isCompleted != done else { return }
        found.isCompleted = done
        try? store.save(found, commit: true)
    }

    /// The Casberi list, made on first use beside the default list's source.
    private static func list(in store: EKEventStore) -> EKCalendar? {
        if let mine = store.calendars(for: .reminder).first(where: { $0.title == listName && $0.allowsContentModifications }) {
            return mine
        }
        guard let source = store.defaultCalendarForNewReminders()?.source
            ?? store.sources.first(where: { $0.sourceType == .calDAV })
            ?? store.sources.first(where: { $0.sourceType == .local }) else { return nil }
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = listName
        list.source = source
        guard (try? store.saveCalendar(list, commit: true)) != nil else { return nil }
        return list
    }
}
