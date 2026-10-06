import Foundation
import SwiftData

/// CALENDARS YOU SUBSCRIBE TO (prd §1137, user: "one idea could be 'calendars'
/// and in the calendar feature we give user ability to subscribe to
/// calendars").
///
/// A calendar is subscribed by its address — a `webcal://` or `https://` link
/// to an `.ics` file, the link every published calendar offers. Casberi reads
/// it itself: iOS lets no app add a subscribed calendar to the system's
/// Calendar, and Casberi writes nothing there (read-only, prd §1025's rule).
///
/// Its events land as `Calendar` rows so they fold into Day and stand in
/// Coming up beside EventKit's, told apart by their ref: `ics:<calendar>:<event>`
/// where EventKit's are `ekevent:` (`ScheduleIngest` prunes and heals only
/// its own prefix). The list itself is listed under Settings › Subs.
@Observable
final class CalendarSubscriptionStore {
    static let shared = CalendarSubscriptionStore()
    private static let key = "calendars.subscribed"

    struct Entry: Codable, Identifiable, Equatable {
        var id = UUID()
        /// The address as it is fetched: `webcal://` read as `https://`.
        var url: String
        /// The calendar's own name (`X-WR-CALNAME`), learned on first read.
        var name: String = ""
        var lastRead: Date?
        /// Events ahead at the last read.
        var ahead: Int = 0

        var displayName: String {
            if !name.isEmpty { return name }
            return URL(string: url)?.host()?.replacingOccurrences(of: "www.", with: "") ?? url
        }
    }

    var calendars: [Entry] {
        didSet { persist() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            calendars = saved
        } else {
            calendars = []
        }
    }

    /// A pasted link as it would be fetched, or nil when it isn't an address.
    /// `webcal://` is HTTP by another name; a bare domain is given `https://`.
    static func normalized(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.lowercased().hasPrefix("webcal://") {
            text = "https://" + text.dropFirst("webcal://".count)
        } else if !text.contains("://") {
            text = "https://" + text
        }
        guard let url = URL(string: text), url.host()?.isEmpty == false,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return text
    }

    func isSubscribed(_ raw: String) -> Bool {
        guard let text = Self.normalized(raw) else { return false }
        return calendars.contains { $0.url.lowercased() == text.lowercased() }
    }

    /// Adds a link; nil when it isn't an address or is already subscribed.
    @discardableResult
    func add(_ raw: String) -> Entry? {
        guard let text = Self.normalized(raw), !isSubscribed(text) else { return nil }
        let entry = Entry(url: text)
        calendars.append(entry)
        return entry
    }

    func remove(_ id: UUID) {
        calendars.removeAll { $0.id == id }
    }

    fileprivate func update(_ id: UUID, name: String?, ahead: Int, at date: Date) {
        guard let i = calendars.firstIndex(where: { $0.id == id }) else { return }
        var next = calendars[i]
        if let name, !name.isEmpty { next.name = name }
        next.ahead = ahead
        next.lastRead = date
        if next != calendars[i] { calendars[i] = next }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(calendars) {
            DefaultsWrite.set(data, forKey: Self.key)
        }
    }
}

// MARK: - Ingest

enum CalendarSubscriptionIngest {
    /// What the receipts screen names these requests (`NetworkReach`'s entry).
    static let service = "Calendars"
    /// The ref prefix every subscribed event carries.
    static let refPrefix = "ics:"
    /// How far ahead a calendar is read: the same five weeks Coming up shows.
    static let window: TimeInterval = 35 * 86_400

    @MainActor private static var running = false

    static func ref(calendar: UUID, event: String) -> String {
        "\(refPrefix)\(calendar.uuidString):\(event)"
    }

    /// Reads every subscribed calendar and lands what is ahead. Returns how
    /// many rows were added, or nil when a read was already running.
    @MainActor
    @discardableResult
    static func refresh(context: ModelContext, only: UUID? = nil) async -> Int? {
        guard !running else { return nil }
        running = true
        defer { running = false }
        let store = CalendarSubscriptionStore.shared
        let entries = store.calendars.filter { only == nil || $0.id == only }
        guard !entries.isEmpty else { return 0 }
        let now = Date()
        let from = Calendar.current.startOfDay(for: now)
        let until = now.addingTimeInterval(window)

        // The network off the main actor, one calendar at a time per host.
        let reads: [(Entry, CalendarICS.Calendar?)] = await IngestSupport.boundedGather(entries, maxConcurrent: 4) { entry in
            (entry, await fetch(entry, from: from, until: until))
        }

        let existing = IngestSupport.thingsByRef(context, source: "Calendar")
        var added = 0
        var removedIDs: [UUID] = []
        for (entry, parsed) in reads {
            // A read that failed keeps what the calendar last said, rather
            // than emptying Coming up because a server blinked.
            guard let parsed else { continue }
            let prefix = "\(refPrefix)\(entry.id.uuidString):"
            var seen = Set<String>()
            for event in parsed.events {
                let ref = prefix + event.id
                seen.insert(ref)
                let calendarName = parsed.name ?? entry.displayName
                if let thing = existing[ref] {
                    apply(event, calendar: calendarName, to: thing)
                } else {
                    let thing = Thing(kind: .event, title: event.title, content: line(event),
                                      source: "Calendar", capturedAt: event.start, sourceRef: ref)
                    apply(event, calendar: calendarName, to: thing)
                    context.insert(thing)
                    added += 1
                }
            }
            // An event the calendar no longer lists, or that has passed — but
            // never on a read that listed NOTHING ahead: a server that blinks
            // an empty calendar must not empty Coming up on every device.
            // Past rows still leave when the read is empty: they are behind
            // now by date, not by absence.
            for (ref, thing) in existing where ref.hasPrefix(prefix) && !seen.contains(ref)
                && (!seen.isEmpty || (thing.endAt ?? thing.capturedAt) < now) {
                removedIDs.append(thing.id)
                context.delete(thing)
            }
            store.update(entry.id, name: parsed.name, ahead: parsed.events.filter { $0.start >= now }.count, at: now)
        }
        context.saveHonestly()
        if !removedIDs.isEmpty { SpotlightIndex.remove(ids: removedIDs) }
        return added
    }

    /// Unsubscribing takes the calendar's rows with it (prd §1137 item 3).
    @MainActor
    static func remove(_ id: UUID, context: ModelContext) {
        CalendarSubscriptionStore.shared.remove(id)
        let prefix = "\(refPrefix)\(id.uuidString):"
        var removedIDs: [UUID] = []
        for (ref, thing) in IngestSupport.thingsByRef(context, source: "Calendar") where ref.hasPrefix(prefix) {
            removedIDs.append(thing.id)
            context.delete(thing)
        }
        context.saveHonestly()
        if !removedIDs.isEmpty { SpotlightIndex.remove(ids: removedIDs) }
    }

    private static func fetch(_ entry: CalendarSubscriptionStore.Entry,
                              from: Date, until: Date) async -> CalendarICS.Calendar? {
        guard let url = URL(string: entry.url) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        // The host is the one the person typed, so the call site names it
        // (prd §205, §289).
        await MainActor.run { NetworkLedger.shared.record(request, as: service) }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
              text.contains("BEGIN:VCALENDAR") else { return nil }
        return CalendarICS.parse(text, from: from, until: until)
    }

    @MainActor
    private static func apply(_ event: CalendarICS.Event, calendar: String, to thing: Thing) {
        if thing.title != event.title { thing.title = event.title }
        if thing.capturedAt != event.start { thing.capturedAt = event.start }
        let content = line(event)
        if thing.content != content { thing.content = content }
        if thing.summary != event.notes { thing.summary = event.notes }
        if thing.endAt != (event.allDay ? nil : event.end) { thing.endAt = event.allDay ? nil : event.end }
        let link = event.url?.absoluteString
        if thing.externalLink != link { thing.externalLink = link }
        if !thing.tags.contains(calendar) { thing.tags.append(calendar) }
        var facts: [ThingFact] = []
        if event.allDay { facts.append(ThingFact("When", "All day", .allDay)) }
        if let place = event.location { facts.append(ThingFact(String(localized: "Where"), place, .map)) }
        facts.append(ThingFact(String(localized: "Calendar"), calendar))
        let encoded = facts.map(\.encoded)
        if thing.facts != encoded { thing.facts = encoded }
    }

    private static func line(_ event: CalendarICS.Event) -> String {
        var parts: [String] = [event.allDay
            ? String(localized: "All day")
            : event.start.formatted(date: .omitted, time: .shortened)]
        if let place = event.location { parts.append(place) }
        return parts.joined(separator: " · ")
    }

    typealias Entry = CalendarSubscriptionStore.Entry
}
