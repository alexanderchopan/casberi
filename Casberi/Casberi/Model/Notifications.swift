import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

/// The scheduling half of notifications (prd §306). Makes NO decisions — every
/// rule about what fires, when it may be delivered and what it says lives in
/// `NotifyPlan.swift`, which is Foundation-only so the harness can compile it.
/// This file does the four things that need a framework: ask permission,
/// resolve the right-hand image, hand `UNNotificationRequest`s to iOS, and
/// route a tap.
///
/// Local only. There is no server and therefore no push (§205's claim survives
/// this feature intact), which buys one real ceiling worth stating rather than
/// hiding: **iOS decides when background refresh runs**, so a notification says
/// when the EVENT happened, never implying it just did.
@MainActor
enum Notifications {

    // MARK: - Settings

    /// Per-class switches, the whisper's hour, and quiet hours. Stored in the
    /// app group so the background task reads the same values the settings
    /// screen writes.
    struct Settings: Sendable, Equatable {
        var alarms = true
        var arrivals = true
        var whisper = true
        var whisperMinute = 7 * 60 + 30      // 07:30
        var quiet = NotifyRules.Quiet.default

        /// Whether anything at all could fire — the gate on asking iOS for
        /// background time. All three off means the task has no work, and
        /// asking for a run we would do nothing with is how an app earns a
        /// throttle it then can't spend when it matters.
        var anyOn: Bool { alarms || arrivals || whisper }

        func allows(_ cls: NotifyClass) -> Bool {
            switch cls {
            case .alarm:   return alarms
            case .arrival: return arrivals
            case .whisper: return whisper
            }
        }
    }

    private static var store: UserDefaults {
        UserDefaults(suiteName: SharedStore.appGroup) ?? .standard
    }

    static var settings: Settings {
        get {
            var s = Settings()
            let d = store
            if d.object(forKey: "notify.alarms") != nil { s.alarms = d.bool(forKey: "notify.alarms") }
            if d.object(forKey: "notify.arrivals") != nil { s.arrivals = d.bool(forKey: "notify.arrivals") }
            if d.object(forKey: "notify.whisper") != nil { s.whisper = d.bool(forKey: "notify.whisper") }
            if d.object(forKey: "notify.whisperMinute") != nil {
                s.whisperMinute = d.integer(forKey: "notify.whisperMinute")
            }
            if d.object(forKey: "notify.quietOn") != nil { s.quiet.enabled = d.bool(forKey: "notify.quietOn") }
            if d.object(forKey: "notify.quietStart") != nil { s.quiet.startMinute = d.integer(forKey: "notify.quietStart") }
            if d.object(forKey: "notify.quietEnd") != nil { s.quiet.endMinute = d.integer(forKey: "notify.quietEnd") }
            return s
        }
        set {
            let d = store
            d.set(newValue.alarms, forKey: "notify.alarms")
            d.set(newValue.arrivals, forKey: "notify.arrivals")
            d.set(newValue.whisper, forKey: "notify.whisper")
            d.set(newValue.whisperMinute, forKey: "notify.whisperMinute")
            d.set(newValue.quiet.enabled, forKey: "notify.quietOn")
            d.set(newValue.quiet.startMinute, forKey: "notify.quietStart")
            d.set(newValue.quiet.endMinute, forKey: "notify.quietEnd")
        }
    }

    static var ledger: NotifyLedger { NotifyLedger(defaults: store) }

    // MARK: - Permission

    /// True once the person has been asked — win or lose. iOS only ever shows
    /// the system prompt once, so a second `requestAuthorization` after a
    /// decline returns false without showing anything; tracking it ourselves is
    /// what lets the settings screen say "turned off in iOS Settings" instead
    /// of offering a button that silently does nothing (the honesty rule).
    static var hasAsked: Bool {
        get { store.bool(forKey: "notify.asked") }
        set { store.set(newValue, forKey: "notify.asked") }
    }

    /// The ask happens the first time an alarm-class event ACTUALLY EXISTS —
    /// never at launch (§306). An ask at launch arrives before the person has
    /// seen anything worth being told about, gets declined, and the decline is
    /// permanent short of a trip to Settings. Asking at the first real dispute
    /// means the prompt carries its own reason.
    @discardableResult
    static func askIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let current = await center.notificationSettings()
        switch current.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        default:
            guard !hasAsked else { return false }
            hasAsked = true
            // NOT `.timeSensitive` here: that authorization option was
            // deprecated in iOS 15 and grants nothing. The level is gated by
            // the `com.apple.developer.usernotifications.time-sensitive`
            // ENTITLEMENT instead, which this build carries as of 2026-08-14
            // — see `schedule`'s note. Passing the dead option would still
            // read as "we asked for it" while asking for nothing, so it stays
            // out even now that the level is honoured.
            let granted = (try? await center.requestAuthorization(
                options: [.alert, .sound, .badge])) ?? false
            return granted
        }
    }

    static func authorized() async -> Bool {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        switch s.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    // MARK: - Submitting

    /// The one door. Filters by settings, drops anything already fired, batches
    /// what is left, then schedules.
    ///
    /// `photos` carries real bytes for `.thing(id)` art — the caller has the
    /// `Thing` in hand at the fire site, and passing the data avoids this file
    /// needing a `ModelContext` it would otherwise have to build in a
    /// background task.
    ///
    /// Returns the plans it really scheduled, which is what the probe prints.
    @discardableResult
    static func submit(_ plans: [NotifyPlan],
                       photos: [String: Data] = [:],
                       now: Date = Date(),
                       dryRun: Bool = false) async -> [NotifyPlan] {
        // The demo never notifies. Its rows carry real-looking deadlines and a
        // dispute due in five days, so an ungated sweep would put "£240
        // disputed" on a stranger's lock screen about money that does not
        // exist — and it would burn the one-and-only authorization prompt to
        // do it, on someone who has not yet decided whether to keep the app.
        // Dry runs still compose, so `-notifyProbe` keeps working over a
        // furnished corpus.
        if !dryRun, DemoMode.isActive { return [] }
        let s = settings
        var eligible = plans.filter { s.allows($0.cls) }
        guard !eligible.isEmpty else { return [] }

        // Ask only when an alarm is genuinely in hand — and NEVER on a dry run.
        // A probe that prompts is a probe that changes the state it reports on:
        // it burns the one-and-only system prompt, flips `hasAsked` forever, and
        // `requestAuthorization` then BLOCKS on a dialog no headless run will
        // ever tap, so the probe hangs and prints nothing. Caught by
        // `-notifyProbe` logging a valid plan and then falling silent.
        if !dryRun, eligible.contains(where: { $0.cls == .alarm }) {
            _ = await askIfNeeded()
        }
        if !dryRun {
            guard await authorized() else { return [] }
        }

        // Fires once, ever. Claim BEFORE batching so the count in "and N more"
        // never includes an alarm we already told them about.
        if !dryRun {
            let fresh = Set(ledger.claim(eligible.map(\.id)))
            eligible = eligible.filter { fresh.contains($0.id) }
        } else {
            eligible = eligible.filter { !ledger.hasFired($0.id) }
        }
        guard !eligible.isEmpty else { return [] }

        let batched = NotifyRules.collapse(eligible)
        guard !dryRun else { return batched }

        for plan in batched {
            await schedule(plan, photo: photos[plan.id], now: now, quiet: s.quiet)
        }
        return batched
    }

    private static func schedule(_ plan: NotifyPlan,
                                 photo: Data?,
                                 now: Date,
                                 quiet: NotifyRules.Quiet) async {
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = .default
        content.threadIdentifier = plan.cls.rawValue        // iOS groups by this
        // HONOURED as of 2026-08-14: `Casberi.entitlements` and its Catalyst
        // twin now carry `com.apple.developer.usernotifications.time-sensitive`
        // (prd §306 amendment's "to finish it"), so a 3am dispute really does
        // break a Focus and the quiet-hours copy says so again. This line is
        // unchanged — it was always correct; what changed is that iOS stopped
        // silently capping it to `.active`.
        // The failure mode if that key is ever dropped is the reason this is
        // spelled out: nothing fails, no log line appears, and the
        // notification arrives looking exactly right — it just stops piercing
        // a Focus, while the settings row goes on promising it will. Both
        // halves are tied together mechanically in notify-selftest.sh.
        content.interruptionLevel = plan.isTimeSensitive ? .timeSensitive : .active
        if let link = plan.link { content.userInfo = ["link": link] }
        if let art = await attachment(for: plan, photo: photo) { content.attachments = [art] }

        // Quiet hours HOLD rather than drop — the news keeps, and a like that
        // wakes someone is worth less than nothing.
        var trigger: UNNotificationTrigger?
        if let hold = NotifyRules.holdUntil(plan: plan, now: now, quiet: quiet, calendar: .current) {
            trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, hold.timeIntervalSince(now)), repeats: false)
        }
        let request = UNNotificationRequest(identifier: plan.id, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - The right-hand slot (§306's ladder)

    /// Rung 1 a real photo the thing holds · rung 2 the source's own mark ·
    /// rung 3 nothing. It never invents: a failed download falls to the mark,
    /// and a source with no bundled asset falls to an honest blank rather than
    /// a drawn stand-in. On a lock screen a fabricated thumbnail is more
    /// convincing than anywhere else in the product, because there is no
    /// surrounding context to contradict it.
    private static func attachment(for plan: NotifyPlan, photo: Data?) async -> UNNotificationAttachment? {
        if let data = await rungOne(plan.art, photo: photo),
           let made = write(data, id: plan.id + ".photo") {
            return made
        }
        if let source = plan.source,
           let mark = brandAsset(source),
           let data = mark.pngData(),
           let made = write(data, id: plan.id + ".mark") {
            return made
        }
        return nil
    }

    private static func rungOne(_ art: NotifyArt, photo: Data?) async -> Data? {
        switch art {
        case .thing:
            return photo
        case .remote(let urlString):
            guard let url = URL(string: urlString), url.scheme == "https" else { return nil }
            // A short budget on purpose: a notification that waits on the
            // network is a notification that arrives late for no gain, and the
            // mark below is a perfectly good answer.
            var request = URLRequest(url: url)
            request.timeoutInterval = 3
            if let host = url.host { NetworkLedger.shared.record(host: host, as: "Social") }
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  data.count < 2_000_000 else { return nil }
            return data
        case .none:
            return nil
        }
    }

    /// The same `brand-<name>` convention `BridgeIcon` uses, so the mark on the
    /// lock screen is byte-identical to the one in the Apps catalog.
    private static func brandAsset(_ name: String) -> UIImage? {
        // DIACRITICS ARE FOLDED (2026-08-29, prd §522). Asset names in this
        // catalog are plain ASCII — "Ethrex Hegotá" is filed as
        // `brand-ethrex-hegota` — so a source whose name carries an accent
        // resolved to nothing and fell straight to rung 3, an honest blank slot
        // for a mark that was sitting right there. Found the moment a devnet
        // gained a notification; it would have been just as true of any future
        // seat with an accent in its name.
        let asset = "brand-" + name.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ".", with: "")
        return UIImage(named: asset)
    }

    /// `UNNotificationAttachment` needs a FILE, and it MOVES the file into its
    /// own store — so each write goes to a fresh per-request directory rather
    /// than a shared path two concurrent sweeps could race on.
    private static func write(_ data: Data, id: String) -> UNNotificationAttachment? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("notify", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = id.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let url = dir.appendingPathComponent(safe + ".png")
        guard (try? data.write(to: url)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: "", url: url, options: nil)
    }

    // MARK: - Likes (the one class with no row behind it)

    /// Likes are the only §306 arrival that cannot come from the corpus sweep,
    /// because a like never lands as a `Thing` — the module doctrine says a
    /// count is not a thing, so the read fills the post's `likeCount` and stops.
    /// The NAMES exist only inside the read itself, which is why this is called
    /// from there.
    ///
    /// One notification PER POST, replaced as more likes arrive — never one per
    /// liker. The id is stable so `UNUserNotificationCenter` swaps the pending
    /// or delivered request in place; the ledger is released whenever the count
    /// grows, which is the one legitimate re-arm (five likes then eight is new
    /// news about the same post, but eight likes read twice is not).
    ///
    /// Names, never numbers — the same rule the read itself follows. "3 people
    /// liked your post" is a tally; "Liked by paulg and 2 others" is people.
    ///
    /// `total` is how many people liked it in all, when that is MORE than the
    /// names on hand (2026-08-07, prd §330). Bluesky hydrates every liker's
    /// handle inline and so passes none — its names are the total. Farcaster
    /// reports fids only, and a name there costs a request apiece, so it
    /// resolves the newest few and reports the rest as a count: "and 39 others"
    /// is still people, and it is the honest shape when naming all forty would
    /// be forty requests to write one line.
    static func likes(postRef: String, postTitle: String,
                      likers: [String], total: Int? = nil, avatarURL: String?,
                      source: String, link: String, when: Date) async {
        guard !likers.isEmpty else { return }
        let id = "likes:" + postRef
        let countKey = "notify.likeCount." + postRef
        let previous = store.integer(forKey: countKey)
        // Never below what we can name — a caller that under-reports its total
        // must not be able to make the copy read "and -1 others".
        let count = max(total ?? likers.count, likers.count)
        guard count > previous else { return }
        store.set(count, forKey: countKey)
        ledger.release(id)

        let lead = likers[0]
        let others = count - 1
        let title: String
        switch others {
        case 0:  title = String(localized: "Liked by \(lead)")
        case 1:  title = String(localized: "Liked by \(lead) and 1 other")
        default: title = String(localized: "Liked by \(lead) and \(others) others")
        }
        let plan = NotifyPlan(
            id: id, kind: .likesReceived,
            title: title,
            body: postTitle,
            link: link,
            occurredAt: when,
            source: source,
            art: avatarURL.map { NotifyArt.remote($0) } ?? .none)
        await submit([plan])
    }

    // MARK: - The whisper

    /// The daily line (§165), scheduled as a one-shot for the next whisper time
    /// and REPLACED by every later sweep — so its content is as fresh as the
    /// last background run before it fires. A repeating trigger was the obvious
    /// shape and is wrong: the content would be frozen at whatever the day it
    /// was created looked like.
    ///
    /// Nil line means nothing is scheduled AND any pending whisper is pulled.
    /// A daily notification that always fires is an alarm clock, not a whisper.
    static func scheduleWhisper(line: String?, now: Date = Date()) async {
        let id = "whisper.next"
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        let s = settings
        let ok = await authorized()
        guard s.whisper, ok, let line, !line.isEmpty else { return }

        var comps = DateComponents()
        comps.hour = s.whisperMinute / 60
        comps.minute = s.whisperMinute % 60
        let content = UNMutableNotificationContent()
        content.title = whisperTitle(now: now)
        content.body = line
        content.sound = .default
        content.threadIdentifier = NotifyClass.whisper.rawValue
        content.interruptionLevel = .active
        content.userInfo = ["link": "casberi://brief"]
        let request = UNNotificationRequest(
            identifier: id, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        try? await center.add(request)
    }

    /// "Your Wednesday" — the day it will ARRIVE, which is tomorrow whenever
    /// we are composing after this morning's whisper already went.
    private static func whisperTitle(now: Date) -> String {
        let cal = Calendar.current
        let s = settings
        let parts = cal.dateComponents([.hour, .minute], from: now)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let target = minute < s.whisperMinute ? now : (cal.date(byAdding: .day, value: 1, to: now) ?? now)
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE"
        return "Your " + fmt.string(from: target)
    }

    // MARK: - Routing a tap

    /// The tap leaves a flag the shell reads on its next foreground, rather
    /// than opening the URL here. Same shape as the "Daily Brief" quick action,
    /// and for the same measured reason: a notification can COLD-launch the
    /// app, and `onOpenURL`'s routing is not guaranteed live at that instant.
    static func handleTap(userInfo: [AnyHashable: Any]) {
        guard let link = userInfo["link"] as? String else { return }
        store.set(link, forKey: "notify.link")
    }

    /// Read-and-clear, for `RootShell`'s foreground pass.
    static func pendingLink() -> URL? {
        guard let s = store.string(forKey: "notify.link") else { return nil }
        store.removeObject(forKey: "notify.link")
        return URL(string: s)
    }
}

/// The delegate. Split out so `AppDelegate` stays about launch.
final class NotifyDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotifyDelegate()

    /// In the foreground the app is already showing the person their corpus, so
    /// a banner over it is noise — EXCEPT a time-sensitive one, which by
    /// definition should interrupt whatever is happening, including us.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
    -> UNNotificationPresentationOptions {
        notification.request.content.interruptionLevel == .timeSensitive
            ? [.banner, .sound] : []
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        await MainActor.run {
            Notifications.handleTap(userInfo: response.notification.request.content.userInfo)
        }
    }
}
