import SwiftUI
import EventKit

/// Verb derivation — verbs derive; menus die (brief §12). A thing's verbs come
/// from kind × source × bridge state, capped at three. "Open shortcut" died
/// with the platform call; App Intents hand-offs replace it (rung 2: the
/// hand-off IS the write, gated by ask-before-acting).
struct Verb: Identifiable {
    enum Action {
        case openURL(URL)             // read hand-off: opens the source app
        case addToCalendar            // write: EKEvent (confirms first)
        case addToReminders           // write: EKReminder (confirms first)
        case copyText                 // write to pasteboard
        case markDone                 // rung 1 mark
        case approve                  // S10: the person's yes — IS the consent
        case deny                     // S10: the person's no
    }
    let label: String
    let icon: String
    let action: Action
    var isWrite: Bool {
        switch action {
        case .addToCalendar, .addToReminders: return true
        default: return false
        }
    }
    /// Compact form for swipe buttons.
    var shortLabel: String {
        switch action {
        case .openURL:        return "Open"
        case .addToCalendar:  return "Calendar"
        case .addToReminders: return "Remind"
        case .copyText:       return "Copy"
        case .markDone:       return "Done"
        case .approve:        return "Approve"
        case .deny:           return "Deny"
        }
    }
    var id: String { label }
}

enum VerbDerivation {

    /// The cap-three rule: primary kind verb, then the source hand-off, then
    /// one utility. Reads pass; writes confirm.
    static func verbs(for thing: Thing) -> [Verb] {
        var out: [Verb] = []

        // 1 — the kind's primary verb.
        switch thing.kind {
        case .approval:
            // The thing IS the ask (S10) — its verbs are the answer. No
            // confirm dialog rides these: approving is the consent.
            return [Verb(label: "Approve", icon: "checkmark.circle", action: .approve),
                    Verb(label: "Deny", icon: "xmark.circle", action: .deny)]
        case .event:
            out.append(thing.source == "Calendar"
                ? Verb(label: "Open in Calendar", icon: "calendar",
                       action: .openURL(URL(string: "calshow://")!))
                : Verb(label: "Add to Calendar", icon: "calendar.badge.plus",
                       action: .addToCalendar))
        case .reminder:
            out.append(thing.source == "Reminders"
                ? Verb(label: "Mark done", icon: "checkmark.circle", action: .markDone)
                : Verb(label: "Add to Reminders", icon: "checklist",
                       action: .addToReminders))
        case .link:
            if let url = Capture.detectURL(in: thing.content.isEmpty ? thing.title : thing.content) {
                out.append(Verb(label: "Open link", icon: "safari", action: .openURL(url)))
            }
        case .screenshot:
            out.append(Verb(label: "Open in Photos", icon: "photo",
                            action: .openURL(URL(string: "photos-redirect://")!)))
        case .note:
            // A note's next action: it becomes a reminder (S4 — captures
            // become outcomes). The write confirms; copy follows.
            out.append(Verb(label: "Add to Reminders", icon: "checklist",
                            action: .addToReminders))
            out.append(Verb(label: "Copy text", icon: "doc.on.doc", action: .copyText))
        case .chat, .mail, .file, .voice:
            out.append(Verb(label: "Copy text", icon: "doc.on.doc", action: .copyText))
        default:
            break
        }

        // 2 — the source hand-off, when the source has an address.
        if let url = sourceURL(thing.source), !out.contains(where: {
            if case .openURL = $0.action { return true } else { return false }
        }) {
            out.append(Verb(label: "Open in \(thing.source)", icon: "arrow.up.right",
                            action: .openURL(url)))
        }

        // 3 — a task verb for marked things.
        if thing.mark == .todo || thing.mark == .doing,
           !out.contains(where: { $0.label == "Mark done" }) {
            out.append(Verb(label: "Mark done", icon: "checkmark.circle", action: .markDone))
        }

        return Array(out.prefix(3))   // the cap
    }

    /// Where a source can be opened. Nil = no hand-off; the verb drops.
    private static func sourceURL(_ source: String) -> URL? {
        switch source.lowercased() {
        case "calendar":  return URL(string: "calshow://")
        case "reminders": return URL(string: "x-apple-reminderkit://")
        case "photos":    return URL(string: "photos-redirect://")
        case "gmail":     return URL(string: "googlegmail://")
        case "chatgpt":   return URL(string: "chatgpt://")
        case "safari":    return nil   // links open directly via Open link
        default:          return nil
        }
    }
}

/// Rung 2 hand-off writes through EventKit. Each write is invoked only after
/// the ask-before-acting confirmation.
enum HandOff {

    static func addToCalendar(_ thing: Thing) async throws {
        let store = EKEventStore()
        guard try await store.requestWriteOnlyAccessToEvents() else {
            throw HandOffError.declined
        }
        let event = EKEvent(eventStore: store)
        event.title = thing.title
        event.notes = thing.content.isEmpty ? nil : thing.content
        event.startDate = defaultStart()
        event.endDate = event.startDate.addingTimeInterval(3600)
        event.calendar = store.defaultCalendarForNewEvents
        try store.save(event, span: .thisEvent)
    }

    static func addToReminders(_ thing: Thing) async throws {
        let store = EKEventStore()
        guard try await store.requestFullAccessToReminders() else {
            throw HandOffError.declined
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = thing.title
        reminder.notes = thing.content.isEmpty ? nil : thing.content
        reminder.calendar = store.defaultCalendarForNewReminders()
        try store.save(reminder, commit: true)
    }

    /// Tomorrow 9:00 — a sane default until the parse carries dates (M6).
    private static func defaultStart() -> Date {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    enum HandOffError: LocalizedError {
        case declined
        // After a system denial iOS never re-asks — Settings is the only
        // honest route, so the message names it.
        var errorDescription: String? { "No access — allow Casberi in iOS Settings" }
    }
}

/// The verb line in the sheet header — place words, not system activity.
enum PlaceWords {
    static func line(for thing: Thing) -> String {
        switch thing.kind {
        case .mail, .file: return "in your inbox"
        case .event:       return "on your calendar"
        case .chat:        return "from your session"
        case .screenshot:  return "in your photos"
        case .link:        return "saved by you"
        case .voice:       return "recorded by you"
        case .reminder:    return "on your list"
        case .note:        return "written by you"
        case .approval:    return "awaiting your call"
        case .job, .run, .output: return "from your machines"
        case .skill:       return "banked by you"
        case .transaction: return "in your wallet"
        default:           return "in your things"
        }
    }
}
