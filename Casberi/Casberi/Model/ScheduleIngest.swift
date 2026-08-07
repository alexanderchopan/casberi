import Foundation
import EventKit
import SwiftData

/// Calendar and Reminders as READ bridges — Bob's actual day lands in the
/// feed with zero setup (the biggest open feeds he has are the system's own).
/// Same law as Photos: the permission ask arrives in context, and connect
/// ends in proof — things land. Dedupe rides sourceRef.
enum ScheduleIngest {

    /// How far ahead calendar events are pulled. The window reaches a week
    /// ahead so imminent events can surface as things (re-ruling 2026-07-14).
    static let forwardWindow: TimeInterval = 7 * 86_400

    /// Events from the start of today through a week ahead — the calendar shows
    /// what's AHEAD, not a record of what passed (re-ruling 2026-07-29,
    /// superseding the 2026-07-14 rolling ±7-day window that kept the past week
    /// "for the record"). Only events that haven't finished land; an event that
    /// has slipped into the past is pruned. BridgeRefresh re-runs this each
    /// foreground, so the window rolls forward.
    ///
    /// Recurring events (2026-07-14): EventKit hands every occurrence of a
    /// recurring event the SAME `eventIdentifier`, so a daily meeting arrives as
    /// N EKEvents sharing one id. We represent each series by ONE thing, keyed
    /// on that id, whose date is the series' NEXT upcoming occurrence (or, when
    /// the whole series is behind but one occurrence is still under way, that
    /// ongoing one). A series entirely in the past drops off. Each foreground
    /// refreshes that thing forward as occurrences pass. A one-off event is just
    /// a series of one, handled the same way. Before this, dedupe on the shared
    /// id kept only the first occurrence seen — usually already past — so
    /// recurring meetings never reached "Coming up".
    /// `@MainActor` on every context-touching path here is load bearing, not
    /// decoration (2026-07-21). These are `async`, and an EventKit await —
    /// `requestFullAccess…`, or the `fetchReminders` continuation — resumes a
    /// NONISOLATED function on the generic executor, not the queue it started
    /// on. Everything after that await then read and mutated the `ModelContext`
    /// off the main queue, which SwiftData logged as "Unbinding from the main
    /// queue… ModelContexts are not Sendable" on most launches (21 of 30 in a
    /// measured window). The callers being `@MainActor` doesn't help — calling
    /// a nonisolated async function from a MainActor context still hops off. It
    /// is the silent-data-race precursor to the SwiftData crash CLAUDE.md warns
    /// about; the annotation pins the resumption back to main.
    @MainActor
    static func connectCalendar(context: ModelContext) async -> Int? {
        let store = EKEventStore()
        guard (try? await store.requestFullAccessToEvents()) == true else { return nil }
        return await ingestEvents(store: store, context: context)
    }

    /// The bare re-scan BridgeRefresh uses — runs only when access is already
    /// granted, so it never re-presents the permission dialog on every
    /// foreground (field report 2026-07-13: same bug the Music/Contacts
    /// refresh paths already had fixed).
    @MainActor
    static func refreshCalendar(context: ModelContext) async -> Int? {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return nil }
        return await ingestEvents(store: EKEventStore(), context: context)
    }

    @MainActor
    private static func ingestEvents(store: EKEventStore, context: ModelContext) async -> Int? {
        // Start at the beginning of today so an all-day event happening today
        // (its start is midnight) is caught, then the upcoming filter below
        // drops timed events that already passed. Nothing before today is
        // fetched — the calendar shows what's ahead (re-ruling 2026-07-29).
        let start = Calendar.current.startOfDay(for: .now)
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

        // Keep only what hasn't finished: the calendar shows what's ahead, not
        // a record of what passed (re-ruling 2026-07-29). An event counts while
        // its end is still in the future — an all-day event through the end of
        // its day, an ongoing multi-day event until it wraps; a timed event that
        // already passed today, and a series entirely behind, drop off.
        let upcoming = representative.filter { _, event in
            (event.endDate ?? event.startDate ?? .distantPast) >= now
        }

        let existing = IngestSupport.thingsByRef(context, source: "Calendar")
        var seen = Set<String>()
        var added = 0
        for (id, event) in upcoming {
            let ref = "ekevent:\(id)"
            seen.insert(ref)
            let when = event.startDate ?? now
            if let thing = existing[ref] {
                // Refresh the stored row forward as the series' representative
                // moves to the next occurrence (or the time/title was edited).
                if thing.capturedAt != when {
                    thing.capturedAt = when
                    thing.title = event.title ?? thing.title
                    thing.content = eventLine(event)
                }
                // Unconditionally, unlike the block above: an event edited in
                // Calendar keeps its start, so gating the enrichment on a moved
                // date would leave notes added this morning unread until the
                // series next rolls forward — and it reaches rows landed before
                // this enrichment existed, which is the whole point.
                enrich(thing, with: event)
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
            enrich(thing, with: event)
            context.insert(thing)
            added += 1
        }
        // Prune what's no longer ahead: a landed event that has slipped into the
        // past (or aged out of the forward window) is removed so the feed never
        // shows a stale past date. `healCalendar` still handles events deleted
        // outright from EventKit; this handles the ones that merely passed.
        var removedIDs: [UUID] = []
        for (ref, thing) in existing where !seen.contains(ref) {
            removedIDs.append(thing.id)
            context.delete(thing)
        }
        context.saveHonestly()
        if !removedIDs.isEmpty { SpotlightIndex.remove(ids: removedIDs) }
        return added
    }

    /// Reconciles against what EventKit still has — an event deleted
    /// outright (not just aged out of the rolling ±7-day window) never
    /// tells Casberi. `calendarItem(withIdentifier:)` returning nil for the
    /// series id is the local, zero-network equivalent of Mail's "UID
    /// FETCH came back empty" (mirrors `ScreenshotIngest.heal`'s RECONCILE
    /// step for Photos). Unlike the ingest window, this walks every
    /// Calendar thing ever landed, so a deletion from months back clears.
    @MainActor
    static func healCalendar(context: ModelContext) -> Int {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return 0 }
        let things = IngestSupport.thingsByRef(context, source: "Calendar")
        guard !things.isEmpty else { return 0 }
        let store = EKEventStore()
        var removedIDs: [UUID] = []
        for (ref, thing) in things {
            let id = String(ref.dropFirst("ekevent:".count))
            guard store.calendarItem(withIdentifier: id) == nil else { continue }
            removedIDs.append(thing.id)
            context.delete(thing)
        }
        guard !removedIDs.isEmpty else { return 0 }
        context.saveHonestly()
        SpotlightIndex.remove(ids: removedIDs)
        return removedIDs.count
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

    /// Reminders are READ-ONLY (ruling 2026-07-25): the app never completes or
    /// un-completes a real reminder — the check circle is status mirrored from
    /// the list, not a control. The one direction that flows is Reminders → us
    /// (see `ingestReminders`, which re-syncs done-state on every refresh).

    /// Open reminders — the list as it stands. New open reminders land;
    /// already-landed things re-sync done-state, title, and due date from
    /// the real list (completed ones never land as new — the corpus records
    /// the list, not its archaeology).
    @MainActor
    static func connectReminders(context: ModelContext) async -> Int? {
        let store = EKEventStore()
        guard (try? await store.requestFullAccessToReminders()) == true else { return nil }
        return await ingestReminders(store: store, context: context)
    }

    /// The bare re-scan BridgeRefresh uses — runs only when access is already
    /// granted, so it never re-presents the permission dialog on every
    /// foreground (field report 2026-07-13, same bug as connectCalendar).
    @MainActor
    static func refreshReminders(context: ModelContext) async -> Int? {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return nil }
        return await ingestReminders(store: EKEventStore(), context: context)
    }

    @MainActor
    private static func ingestReminders(store: EKEventStore, context: ModelContext) async -> Int? {
        let predicate = store.predicateForReminders(in: nil)
        let reminders: [EKReminder] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { cont.resume(returning: $0 ?? []) }
        }

        let existing = IngestSupport.thingsByRef(context, source: "Reminders")
        var seen = Set<String>()
        var added = 0
        for reminder in reminders {
            let ref = "ekreminder:\(reminder.calendarItemIdentifier)"
            seen.insert(ref)
            if let thing = existing[ref] {
                // The real list is authoritative on refresh — a reminder
                // completed (or reopened) in the Reminders app carries that
                // state back here, the missing other half of the check
                // circle's write-through; without it the two lists silently
                // drift. Title and due-date edits follow the same way.
                if reminder.isCompleted, thing.mark != .done {
                    thing.mark = .done
                } else if !reminder.isCompleted, thing.mark == .done {
                    thing.mark = .todo
                }
                if let title = reminder.title, thing.title != title {
                    thing.title = title
                }
                let due = reminder.dueDateComponents?.date
                if thing.dueAt != due {
                    thing.dueAt = due
                    thing.content = dueLine(reminder)
                }
                // Unconditionally — the real list is authoritative on refresh
                // for these fields too, and this is what reaches rows landed
                // before the enrichment existed.
                enrich(thing, with: reminder)
                continue
            }
            guard !reminder.isCompleted else { continue }
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
            enrich(thing, with: reminder)
            context.insert(thing)
            added += 1
        }
        // RECONCILE: `predicateForReminders(in: nil)` fetches the WHOLE
        // current list every time (no window, unlike Calendar's rolling
        // ±7 days), so a ref this pass never saw was deleted outright, not
        // just out of range.
        var removedIDs: [UUID] = []
        for (ref, thing) in existing where !seen.contains(ref) {
            removedIDs.append(thing.id)
            context.delete(thing)
        }
        context.saveHonestly()
        if !removedIDs.isEmpty { SpotlightIndex.remove(ids: removedIDs) }
        return added
    }

    // MARK: - Enrichment (2026-08-06)

    /// What an event carries besides its title and its clock.
    ///
    /// EventKit hands all of this over in the same fetch — nothing here costs a
    /// request or a permission we don't already hold — and until now every
    /// field of it was dropped, so an event landed as a name, a time and
    /// (maybe) a location. The agenda you actually wrote, the video link, whose
    /// calendar it belongs to and who else is coming were all in hand and all
    /// discarded.
    ///
    /// Three destinations, by the rule each field falls under:
    ///   · NOTES → `summary`. It is text the PERSON authored and Apple handed
    ///     us in its own payload — the RSS/Linear/Trello description
    ///     precedent — so it is first-class display copy, not the
    ///     retrieval-only `enrichedText` (2026-07-15).
    ///   · URL → `externalLink`. The video link on a meeting is the one thing
    ///     you want at the moment the row matters. Note nothing DRAWS this
    ///     field today (it is read by the Reddit/Snapchat crossing passes,
    ///     both source-scoped), so this is stored data waiting on a verb, not
    ///     a control that exists and does nothing.
    ///   · ATTENDEES → `enrichedText`. Names, so "the review with Ana" finds
    ///     it; never displayed, because a row full of names is a row you can't
    ///     read, and the sheet already shows the notes.
    ///
    /// `dueAt` stays nil, by the field's own convention: an event carries its
    /// deadline as `capturedAt` (the start) and only a reminder's deadline
    /// needs its own field.
    ///
    /// Idempotent — it runs on every foreground for every event, so it must
    /// never append the same tag twice or dirty a row that hasn't changed.
    private static func enrich(_ thing: Thing, with event: EKEvent) {
        setSummary(thing, trimmed(event.notes))
        setEnriched(thing, attendeeNames(event))
        let link = event.url?.absoluteString
        if thing.externalLink != link { thing.externalLink = link }
        addTag(calendarTitle(event), to: thing)
    }

    /// The two writers that drop the stored vector when the text really moved.
    ///
    /// `EmbeddingIndex` composes what it embeds from the title, `summary` and
    /// `enrichedText`, so a row that gains either keeps a vector computed
    /// without it until something clears the old one. Load bearing on the
    /// REFRESH path and only there — a new row has no vector yet, but an event
    /// already in the corpus that gains its agenda today would otherwise stay
    /// unfindable by the words it just gained, forever.
    private static func setSummary(_ thing: Thing, _ text: String?) {
        guard thing.summary != text else { return }
        thing.summary = text
        thing.embedding = nil
    }

    private static func setEnriched(_ thing: Thing, _ text: String?) {
        guard thing.enrichedText != text else { return }
        thing.enrichedText = text
        thing.embedding = nil
    }

    /// What a reminder carries besides its title and its due date. Same three
    /// rules as `enrich(_:with: EKEvent)` above, minus the fields a reminder
    /// has no equivalent for (there is nobody else on a reminder).
    ///
    /// PRIORITY becomes a tag only when it can be said honestly. EventKit's
    /// value is RFC 5545's 0–9 scale, where 0 means "nobody set one" — so 0
    /// gets no tag at all rather than a "Low priority" nobody chose, and an
    /// out-of-range value gets none either.
    private static func enrich(_ thing: Thing, with reminder: EKReminder) {
        setSummary(thing, trimmed(reminder.notes))
        let link = reminder.url?.absoluteString
        if thing.externalLink != link { thing.externalLink = link }
        addTag(calendarTitle(reminder), to: thing)
        addTag(priorityTag(reminder.priority), to: thing)
    }

    /// The calendar (or list) a row belongs to, as a tag — "Work", "Family",
    /// the shared calendar somebody invited you to. A real facet to narrow by,
    /// and the one grouping these rows have that isn't time.
    private static func calendarTitle(_ item: EKCalendarItem) -> String? {
        trimmed(item.calendar?.title)
    }

    /// RFC 5545's priority scale in words. 1–4 high, 5 medium, 6–9 low is
    /// Apple's own reading of it (the Reminders app's !!! / !! / !), and 0 is
    /// its documented "not set".
    private static func priorityTag(_ priority: Int) -> String? {
        switch priority {
        case 1...4: return String(localized: "High priority")
        case 5:     return String(localized: "Medium priority")
        case 6...9: return String(localized: "Low priority")
        default:    return nil
        }
    }

    /// Who else is on an event, as `Name <email>` when EventKit names both.
    /// Both halves because this feeds retrieval, where a name without its
    /// address is half a search term (the `IMAPClient` recipient rule).
    /// Capped: an all-hands invite is unbounded, and the embedding window
    /// (`EmbeddingIndex.indexText`) reads the first 800 characters, so an
    /// uncapped roster would crowd out the event's own words. The overflow is
    /// COUNTED, never silently dropped.
    private static func attendeeNames(_ event: EKEvent) -> String? {
        guard let attendees = event.attendees, !attendees.isEmpty else { return nil }
        let names: [String] = attendees.compactMap { participant in
            let name = trimmed(participant.name)
            // A participant's `url` is a `mailto:` — read the address off the
            // string rather than `resourceSpecifier`, which carries the rest
            // of the URL too and is a legacy accessor.
            let raw = participant.url.absoluteString
            let email = raw.lowercased().hasPrefix("mailto:")
                ? trimmed(String(raw.dropFirst("mailto:".count))) : nil
            switch (name, email) {
            case let (name?, email?): return name == email ? name : "\(name) <\(email)>"
            case let (name?, nil):    return name
            case let (nil, email?):   return email
            case (nil, nil):          return nil
            }
        }
        guard !names.isEmpty else { return nil }
        let shown = names.prefix(attendeeCap).joined(separator: ", ")
        let extra = names.count - min(names.count, attendeeCap)
        return shown + (extra > 0 ? ", and \(extra) more" : "")
    }

    private static let attendeeCap = 25

    /// Appends a tag once. These passes re-run on every foreground over the
    /// same rows, so a plain append would grow a row's tag list without bound.
    private static func addTag(_ tag: String?, to thing: Thing) {
        guard let tag, !thing.tags.contains(tag) else { return }
        thing.tags.append(tag)
    }

    /// A string field, trimmed, or nil when it's absent or empty — so an empty
    /// notes field never lands as an empty `summary` that renders as a blank
    /// block, and never as an empty `enrichedText` that clears `embedding` for
    /// nothing.
    private static func trimmed(_ raw: String?) -> String? {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty else { return nil }
        return s
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
