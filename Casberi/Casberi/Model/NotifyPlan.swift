import Foundation

/// What a notification IS, before anything schedules it (prd §306).
///
/// Foundation-only and pure by contract — no `UserNotifications`, no UIKit, no
/// store. Everything that decides *whether* something fires, *when* it may be
/// delivered, and *what it says* lives here, so `scripts/notify-selftest.sh`
/// can compile this file WHOLE and check the judgement against fixtures. The
/// impure half (permission, attachments, `UNNotificationRequest`) is
/// `Notifications.swift`, and it makes no decisions.
///
/// The split earns itself the same way `StripeRoom`/`PostHogRoom` do: every
/// failure in this file is a SILENT WRONG NOTIFICATION — a 3am buzz that
/// should have waited for morning, a dispute that never fired, the same like
/// announced eleven times. None of those can be seen in a build, and the
/// simulator never runs a background task at all, so a harness is the only
/// proof these rules hold.

// MARK: - Classes

/// The three classes, and there is no fourth (§306). A class decides
/// interruption, batching and whether quiet hours may hold it.
enum NotifyClass: String, Sendable, CaseIterable {
    /// Something needs you.
    case alarm
    /// Something landed FOR you — money in, attention in.
    case arrival
    /// The once-a-day line, at a time the person picked.
    case whisper
}

/// Every event that may ever notify. The list is CLOSED on purpose: adding a
/// case is the moment to re-read §306's never-fires list, and the harness
/// asserts every case routes to a class and carries a severity.
enum NotifyKind: String, Sendable, CaseIterable {
    // — alarm
    case disputeOpened
    case deadlineNear
    case approvalGranted
    case poolProofNeeded
    case poolCleared
    case paymentsSilent
    case priceRose
    // — arrival
    case moneyIn
    case payoutPaid
    case likesReceived
    case repliesReceived
    case followersGained
    // — whisper
    case whisper

    var cls: NotifyClass {
        switch self {
        case .disputeOpened, .deadlineNear, .approvalGranted,
             .poolProofNeeded, .poolCleared, .paymentsSilent, .priceRose:
            return .alarm
        case .moneyIn, .payoutPaid, .likesReceived, .repliesReceived, .followersGained:
            return .arrival
        case .whisper:
            return .whisper
        }
    }

    /// Higher wins when a single sweep turns up more alarms than we will send.
    /// Money you could still lose outranks money that is merely at risk, which
    /// outranks a status flip you can act on whenever. Deliberately NOT the
    /// declaration order — reordering an enum for display is exactly the kind
    /// of edit that would silently re-rank people's alarms.
    var severity: Int {
        switch self {
        case .disputeOpened:    return 100   // money leaving, with a deadline
        case .deadlineNear:     return 90    // a window closing on you
        case .approvalGranted:  return 80    // something CAN take funds
        case .poolProofNeeded:  return 70    // action required, no clock stated
        case .paymentsSilent:   return 60    // revenue stopped; nothing to click
        case .poolCleared:      return 50    // good news, act whenever
        case .priceRose:        return 40    // recurring money, already charged
        default:                return 0     // arrivals/whisper never compete
        }
    }

    /// Only a deadline may claim the interruption level that breaks a Focus.
    /// Over-claiming is how a class gets buried by iOS's own summary, so the
    /// two that carry a real clock are the only two that ask.
    var isTimeSensitive: Bool {
        self == .disputeOpened || self == .deadlineNear
    }
}

// MARK: - A single planned notification

/// One composed, ready-to-schedule notification. Value type, `Sendable`, and
/// deliberately carrying only STRINGS for its imagery — resolving a source
/// name to a bundled asset, or a thing id to stored bytes, is the impure
/// half's job.
struct NotifyPlan: Sendable, Equatable {
    /// Stable and unique per real-world event — this is the dedupe key, and it
    /// is what makes "fires once, ever" true across launches. A Stripe dispute
    /// uses the dispute id; a like batch uses the post's ref, so later likers
    /// REPLACE the pending notification instead of adding to it.
    var id: String
    var kind: NotifyKind
    var title: String
    var body: String
    /// `casberi://…` — where a tap lands. Nil means "just open the app".
    var link: String?
    /// The event's own moment, NOT the delivery moment. Background refresh runs
    /// when iOS feels like it, so the copy must be able to say when a thing
    /// actually happened rather than implying it just did.
    var occurredAt: Date
    /// Set for `deadlineNear`/`disputeOpened` — drives the "3 days" phrasing.
    var deadline: Date?
    /// The source whose mark fills the right-hand slot when no photo can be
    /// had — rung 2 of §306's attachment ladder, and the reason a failed photo
    /// never leaves the slot empty.
    var source: String?
    /// Rung 1: a real photo this thing already holds. `.none` is the normal
    /// case and never a defect — most events have no picture, and §306 forbids
    /// drawing one.
    var art: NotifyArt = .none

    var cls: NotifyClass { kind.cls }
    var isTimeSensitive: Bool { kind.isTimeSensitive }
}

/// Where rung 1's photo comes from, if anywhere. Both cases are REFERENCES, not
/// bytes: this type crosses into the harness, and a plan that carried image
/// data would make every fixture unreadable.
enum NotifyArt: Sendable, Equatable {
    /// A `Thing`'s own `previewImageData` — a screenshot's stored thumbnail.
    case thing(String)
    /// A remote avatar the inbound read already hydrated. Best effort: it is
    /// fetched with a short budget and falls to the source mark if it misses,
    /// because a notification that waits on the network is a notification that
    /// arrives late for no gain.
    case remote(String)
    case none
}

// MARK: - The rules

enum NotifyRules {
    /// A deadline notifies once it is inside three days AND still ahead of us.
    /// Both halves are load-bearing: without the upper bound every dated row in
    /// the corpus alarms at once on first run, and without the `> now` check a
    /// deadline that has already passed alarms forever, which is the worst
    /// possible time to be told about it.
    static let deadlineWindow: TimeInterval = 72 * 3600

    static func deadlineIsNear(_ due: Date, now: Date) -> Bool {
        let delta = due.timeIntervalSince(now)
        return delta > 0 && delta <= deadlineWindow
    }

    /// How many alarms one sweep may actually send. The rest are counted, never
    /// dropped silently — see `collapse`.
    static let alarmsPerSweep = 1

    /// Default quiet window, overridable in settings. Stored as minutes from
    /// midnight so it survives a timezone change without meaning something
    /// different.
    struct Quiet: Sendable, Equatable {
        var startMinute: Int   // 22:00
        var endMinute: Int     // 08:00
        var enabled: Bool

        static let `default` = Quiet(startMinute: 22 * 60, endMinute: 8 * 60, enabled: true)

        /// True while the clock is inside the window. Handles the wrap across
        /// midnight, which is the normal case — a window that does NOT wrap
        /// (say 09:00–17:00) is the unusual one and still has to work.
        func contains(minute: Int) -> Bool {
            guard enabled else { return false }
            if startMinute == endMinute { return false }
            if startMinute < endMinute {           // 09:00 → 17:00, same day
                return minute >= startMinute && minute < endMinute
            }
            return minute >= startMinute || minute < endMinute   // 22:00 → 08:00
        }
    }

    /// When a plan may be delivered. Nil means "now".
    ///
    /// A time-sensitive alarm is never held — that is the entire point of the
    /// level, and iOS's Focus rules already govern it. Everything else that
    /// lands in quiet hours is HELD UNTIL MORNING rather than dropped: the news
    /// keeps, and a like you are told about at 08:00 is still worth having,
    /// while one that wakes you is worth less than nothing.
    static func holdUntil(plan: NotifyPlan, now: Date, quiet: Quiet, calendar: Calendar) -> Date? {
        guard !plan.isTimeSensitive else { return nil }
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        guard quiet.contains(minute: minute) else { return nil }
        // The next time the clock reads `endMinute`. Adding a day first and
        // then setting the time would land wrong on the morning side of the
        // window (00:30 must wait until 08:00 TODAY, not tomorrow).
        let endHour = quiet.endMinute / 60, endMin = quiet.endMinute % 60
        guard let today = calendar.date(bySettingHour: endHour, minute: endMin, second: 0, of: now) else {
            return nil
        }
        return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today)
    }

    /// The batching rule (§306), and the reason the feature stays likeable.
    ///
    /// Two groups collapse, for two different reasons. **Alarms** are ranked and
    /// only the worst is sent, with the rest COUNTED into its body: eleven
    /// separate alarms is the thing that makes a person switch notifications
    /// off, and the eleventh is never the one that mattered. **Money arrivals**
    /// collapse too — a wallet can receive several transfers in one window, and
    /// four buzzes for four transfers is the same failure wearing better news.
    /// (Money is also the one place the module doctrine allows a count, because
    /// there the count IS the event.)
    ///
    /// Likes, replies and followers pass through: each already carries a
    /// per-post or per-person id, so a second liker REPLACES that request rather
    /// than joining a queue, and two different people are two different events.
    ///
    /// Ties break on `occurredAt` (newer first) and then on `id`, so the same
    /// sweep always yields the same choice — a sweep that picked differently on
    /// each run would be untestable.
    static func collapse(_ plans: [NotifyPlan]) -> [NotifyPlan] {
        collapseGroup(plans, matching: { $0.cls == .alarm },
                      more: { $0 == 1 ? " And 1 more needs you." : " And \($0) more need you." })
            .pipe { collapseGroup($0, matching: { $0.kind == .moneyIn },
                                  more: { $0 == 1 ? " And 1 more transfer." : " And \($0) more transfers." }) }
    }

    private static func collapseGroup(_ plans: [NotifyPlan],
                                      matching: (NotifyPlan) -> Bool,
                                      more: (Int) -> String) -> [NotifyPlan] {
        let group = plans.filter(matching)
        guard group.count > alarmsPerSweep else { return plans }
        let rest = plans.filter { !matching($0) }
        let ranked = group.sorted { a, b in
            if a.kind.severity != b.kind.severity { return a.kind.severity > b.kind.severity }
            if a.occurredAt != b.occurredAt { return a.occurredAt > b.occurredAt }
            return a.id < b.id
        }
        var lead = ranked[0]
        lead.body += more(ranked.count - 1)
        return [lead] + rest
    }

    /// Plain-words time-to-deadline for the body. Never "in 71 hours".
    static func deadlinePhrase(_ due: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: due)).day ?? 0
        switch days {
        case ..<0:  return "overdue"
        case 0:     return "today"
        case 1:     return "tomorrow"
        default:    return "in \(days) days"
        }
    }
}

// MARK: - Fires once, ever

/// The ledger that makes a notification a one-time event.
///
/// Every fire site is inside a sweep that re-reads the same window, so without
/// this a dispute alarms on every background run for as long as it is open.
/// Bounded rather than unbounded: a set that only grows is a set that is one
/// day the reason a launch is slow, and an id old enough to fall off the end is
/// an id whose event is long past re-notifying.
/// Not `Sendable`: it holds a `UserDefaults`, which isn't, and every caller is
/// already `@MainActor`. Conforming would be a Swift 6 error and a claim about
/// thread safety nothing here needs.
struct NotifyLedger {
    static let cap = 500
    private static let key = "notify.fired"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    /// Ordered oldest→newest, so the prune drops the oldest.
    private var fired: [String] {
        get { defaults.stringArray(forKey: Self.key) ?? [] }
        nonmutating set { defaults.set(newValue, forKey: Self.key) }
    }

    func hasFired(_ id: String) -> Bool { fired.contains(id) }

    /// Records ids and returns only those NOT seen before, so a caller can
    /// mark-and-filter in one pass without a read/write race between them.
    @discardableResult
    func claim(_ ids: [String]) -> [String] {
        var seen = Set(fired)
        var order = fired
        var fresh: [String] = []
        for id in ids where !seen.contains(id) {
            seen.insert(id); order.append(id); fresh.append(id)
        }
        guard !fresh.isEmpty else { return [] }
        if order.count > Self.cap { order.removeFirst(order.count - Self.cap) }
        fired = order
        return fresh
    }

    /// A batching id must be able to fire AGAIN when its contents change — five
    /// likes then eight likes is new news about the same post. So the ledger is
    /// keyed on id+contents for those, and `release` exists for the one caller
    /// that legitimately re-arms: see `Notifications.likes(...)`.
    func release(_ id: String) {
        fired = fired.filter { $0 != id }
    }

    func reset() { defaults.removeObject(forKey: Self.key) }
}


private extension Array {
    /// Left-to-right chaining, so `collapse` reads as the two passes it is
    /// rather than a nested call that has to be read inside-out.
    func pipe<T>(_ transform: (Self) -> T) -> T { transform(self) }
}