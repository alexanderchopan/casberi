import SwiftUI
import UIKit
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
        case bridgeWrite(BridgeWrite) // write BACK to the bridge (prd §67 ③)
    }
    let label: String
    let icon: String
    let action: Action
    var isWrite: Bool {
        switch action {
        case .addToCalendar, .addToReminders, .bridgeWrite: return true
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
        case .bridgeWrite:    return "Do it"
        }
    }
    var id: String { label }
}

enum VerbDerivation {

    /// `NSDataDetector` loads linguistic data on construction, so building one
    /// per call is expensive — and `verbs(for:)` runs twice per visible feed
    /// row (leading + trailing swipeActions) and once per Home child. Built
    /// once and reused; the detectors are thread-safe for concurrent matching.
    private static let addressDetector =
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue)
    private static let phoneDetector =
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue)

    /// The cap-three rule: primary kind verb, then the source hand-off, then
    /// one utility. Reads pass; writes confirm.
    static func verbs(for thing: Thing) -> [Verb] {
        var out: [Verb] = []

        // 0 — the write-back, when the thing's own bridge can take one
        // (prd §67 ③: Complete in Todoist, Close on GitHub). It LEADS: acting
        // on the thing at its source is the strongest verb a thing can carry.
        // Feed swipes never see it (they surface only the open hand-off);
        // in the sheet it confirms first, like every write.
        if let write = BridgeWrites.write(for: thing) {
            let face = BridgeWrites.label(for: write)
            out.append(Verb(label: face.label, icon: face.icon,
                            action: .bridgeWrite(write)))
        }

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
            if let v = externalVerb(for: thing, apps: [.todoist]) { out.append(v) }
        case .link:
            // Music rows open the exact track in their app — the stored content
            // is a music.apple.com / open.spotify.com universal link. Named and
            // iconed by the app (like "Open in Calendar"), with the app scheme
            // as a fallback for a library play that carries no per-track URL, so
            // every music row can hand off the way events and items do (user,
            // 2026-07-13).
            if thing.source == "Apple Music" || thing.source == "Spotify" {
                if let url = Capture.detectURL(in: thing.content) ?? sourceURL(thing.source) {
                    out.append(Verb(label: "Open in \(thing.source)",
                                    icon: "music.note", action: .openURL(url)))
                }
            } else if let url = Capture.detectURL(in: thing.content.isEmpty ? thing.title : thing.content) {
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
            if let v = externalVerb(for: thing, apps: [.todoist]) { out.append(v) }
            out.append(Verb(label: "Copy text", icon: "doc.on.doc", action: .copyText))
        case .chat, .mail, .file, .voice:
            out.append(Verb(label: "Copy text", icon: "doc.on.doc", action: .copyText))
        default:
            break
        }

        // 1b — a place leads with Directions. When the thing carries an
        // address or a maps link, routing to it is the most useful move —
        // prepend so it survives the cap. Apple Maps over the web URL, so it
        // opens even if the Maps app was removed (never a dead hand-off).
        if let maps = placeURL(for: thing) {
            out.insert(Verb(label: "Directions", icon: "map", action: .openURL(maps)), at: 0)
        }

        // 1c — reach a person: call a detected number, email a detected address.
        if let tel = telURL(in: thing) {
            out.append(Verb(label: "Call", icon: "phone", action: .openURL(tel)))
        }
        if let mail = mailtoURL(for: thing) {
            out.append(Verb(label: thing.kind == .mail ? "Reply" : "Email",
                            icon: "envelope", action: .openURL(mail)))
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

        // The cap (was three): a place-y or contactful thing can earn a fourth
        // hand-off, but no thing becomes a menu (brief §12).
        return Array(out.prefix(4))
    }

    /// A place the thing points at, as an Apple Maps directions URL — or nil
    /// when there's no address to route to (the verb drops; no dead control).
    /// A maps/geo link passes straight through; otherwise a detected street
    /// address becomes the destination query.
    private static func placeURL(for thing: Thing) -> URL? {
        let text = thing.content.isEmpty ? thing.title : thing.content

        if let url = Capture.detectURL(in: text) {
            let host = url.host()?.lowercased() ?? ""
            if url.scheme == "geo"
                || host.contains("maps.apple.com")
                || host.contains("google.com/maps")
                || host.contains("maps.google")
                || host.contains("goo.gl/maps") {
                return url
            }
        }

        let range = NSRange(text.startIndex..., in: text)
        guard let match = addressDetector?.firstMatch(in: text, range: range),
              let r = Range(match.range, in: text) else { return nil }
        var comps = URLComponents(string: "https://maps.apple.com/")
        comps?.queryItems = [URLQueryItem(name: "daddr", value: String(text[r]))]
        return comps?.url
    }

    /// A phone number in the thing → a tel: URL, else nil (the verb drops).
    private static func telURL(in thing: Thing) -> URL? {
        let text = thing.content.isEmpty ? thing.title : thing.content
        let range = NSRange(text.startIndex..., in: text)
        guard let number = phoneDetector?.firstMatch(in: text, range: range)?.phoneNumber else { return nil }
        let dialable = number.filter { $0.isNumber || $0 == "+" }
        return dialable.isEmpty ? nil : URL(string: "tel:\(dialable)")
    }

    /// An email address in the thing → a mailto: compose URL, else nil. Only
    /// fires when there's a real address to reach — never a blank composer.
    private static func mailtoURL(for thing: Thing) -> URL? {
        let text = thing.content.isEmpty ? thing.title : thing.content
        guard let r = text.range(of: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
                                 options: [.regularExpression, .caseInsensitive]) else { return nil }
        var comps = URLComponents()
        comps.scheme = "mailto"
        comps.path = String(text[r])
        comps.queryItems = [URLQueryItem(name: "subject", value: thing.title)]
        return comps.url
    }

    /// A third-party app a task-shaped thing can hand off to. The rule (user,
    /// 2026-07-12): ONLY apps the person already connected as a Casberi bridge
    /// — never an arbitrary popular app — and each must carry a documented
    /// create URL. Todoist is the one that qualifies today; the table grows as
    /// more connected bridges gain schemes.
    private enum ExternalApp {
        case todoist

        /// The catalog/bridge name, lowercased — matched against connected seats.
        var bridgeName: String { switch self { case .todoist: "todoist" } }
        var scheme: String { switch self { case .todoist: "todoist" } }
        var label: String { switch self { case .todoist: "Todoist" } }
        var icon: String { switch self { case .todoist: "checklist" } }

        func url(for thing: Thing) -> URL? {
            switch self {
            case .todoist:
                var c = URLComponents(string: "todoist://addtask")
                c?.queryItems = [URLQueryItem(name: "content", value: thing.title)]
                return c?.url
            }
        }
    }

    /// An "Add to …" hand-off for the first app that is BOTH a connected bridge
    /// and installed — else nil, so the verb only shows what the person chose
    /// and can actually reach. Reads cached snapshots (no UIApplication /
    /// BridgeStore here) so derivation runs off-main inside GenUI.
    private static func externalVerb(for thing: Thing, apps: [ExternalApp]) -> Verb? {
        for app in apps
        where HandOffState.connectedBridges.contains(app.bridgeName)
           && HandOffState.installedSchemes.contains(app.scheme) {
            guard let url = app.url(for: thing) else { continue }
            return Verb(label: "Add to \(app.label)", icon: app.icon, action: .openURL(url))
        }
        return nil
    }

    /// Where a source can be opened. Nil = no hand-off; the verb drops.
    private static func sourceURL(_ source: String) -> URL? {
        switch source.lowercased() {
        case "calendar":  return URL(string: "calshow://")
        case "reminders": return URL(string: "x-apple-reminderkit://")
        case "photos":    return URL(string: "photos-redirect://")
        case "gmail":     return URL(string: "googlegmail://")
        case "chatgpt":   return URL(string: "chatgpt://")
        // Music apps — the per-track universal link opens the exact song; this
        // is the fallback that still opens the app for a URL-less library play.
        case "apple music": return URL(string: "music://")
        case "spotify":     return URL(string: "spotify://")
        case "safari":    return nil   // links open directly via Open link
        default:          return nil
        }
    }
}

/// Cached hand-off state, refreshed on the main actor each foreground.
/// `VerbDerivation` reads it off any thread — it's only ever written on main,
/// and a stale read just hides or shows one optional verb — so derivation
/// stays free of UIApplication / BridgeStore isolation and can run inside
/// off-main GenUI composition.
enum HandOffState {
    /// Custom URL schemes (from `LSApplicationQueriesSchemes`) that resolve to
    /// an installed app. A scheme not listed in Info.plist always reads absent,
    /// so the two must move together.
    nonisolated(unsafe) static var installedSchemes: Set<String> = []
    /// Lowercased names of the bridges the person has connected — the gate for
    /// "Add to <app>" hand-offs (user ruling: bridge-tied, never arbitrary).
    nonisolated(unsafe) static var connectedBridges: Set<String> = []

    private static let candidates = ["todoist", "googlegmail"]

    @MainActor static func refresh(connected: Set<String>) {
        installedSchemes = Set(candidates.filter {
            guard let url = URL(string: "\($0)://") else { return false }
            return UIApplication.shared.canOpenURL(url)
        })
        connectedBridges = connected
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
        case .contact:     return "in your contacts"
        default:           return "in your things"
        }
    }
}
