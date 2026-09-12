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

    /// Per-class switches and quiet hours. Stored in the app group so the
    /// background task reads the same values the settings screen writes.
    ///
    /// The daily whisper (a third switch and its hour) was cut in prd §706
    /// (2026-09-12): its tap had opened onto nothing since the ask went dark
    /// (§697b), and its line summarised a day the person had already read.
    /// `notify.whisper` / `notify.whisperMinute` are left in the store unread,
    /// and any `whisper.next` an older build scheduled is pulled at launch
    /// (`cancelRetiredWhisper`).
    ///
    /// **ONLY THE CLASS THE GRANT WAS ASKED FOR IS ON BY DEFAULT (prd §644,
    /// 2026-09-08).** All three shipped `true`, and `askIfNeeded` presents the
    /// system prompt at the first real ALARM — so the permission was earned by
    /// a dispute and then spent on ordinary arrivals and a 07:30 push nobody
    /// chose. Two of the three classes were riding in on a grant given for the
    /// third. Arrivals are opt-IN now; the row says plainly what it does
    /// (`AccountDetailSheet.notifyCard`), so turning it on is one tap by
    /// somebody who wants it.
    ///
    /// `alarms` stays `true` because it IS what the prompt asks for: a person
    /// who granted permission at a dispute and then heard nothing about the
    /// next one would have a switch that silently did nothing (§83).
    struct Settings: Sendable, Equatable {
        var alarms = true
        var arrivals = false
        var quiet = NotifyRules.Quiet.default

        /// Whether anything at all could fire — the gate on asking iOS for
        /// background time. Both off means the task has no work, and
        /// asking for a run we would do nothing with is how an app earns a
        /// throttle it then can't spend when it matters.
        var anyOn: Bool { alarms || arrivals }

        func allows(_ cls: NotifyClass) -> Bool {
            switch cls {
            case .alarm:   return alarms
            case .arrival: return arrivals
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
            if d.object(forKey: "notify.quietOn") != nil { s.quiet.enabled = d.bool(forKey: "notify.quietOn") }
            if d.object(forKey: "notify.quietStart") != nil { s.quiet.startMinute = d.integer(forKey: "notify.quietStart") }
            if d.object(forKey: "notify.quietEnd") != nil { s.quiet.endMinute = d.integer(forKey: "notify.quietEnd") }
            return s
        }
        set {
            let d = store
            d.set(newValue.alarms, forKey: "notify.alarms")
            d.set(newValue.arrivals, forKey: "notify.arrivals")
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
            // No `.badge`: the app never sets one (prd §713 — it asked for
            // five weeks and badged nothing, which is asking for something
            // while reading as "we use it"). A red count on the icon is the
            // one persistent bid for attention the OS offers, and §644 is
            // that the app does not make it.
            let granted = (try? await center.requestAuthorization(
                options: [.alert, .sound])) ?? false
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
        // Quiet hours HOLD rather than drop — the news keeps, and a like that
        // wakes someone is worth less than nothing.
        let hold = NotifyRules.holdUntil(plan: plan, now: now, quiet: quiet, calendar: .current)

        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        // The subtitle is WHERE and, when delivery lags the event, WHEN (prd
        // §712). The when is computed against the moment this will actually
        // be delivered — the quiet-hours hold, not now — because a body is
        // frozen at scheduling and a like held until 08:00 must say "last
        // night", not "an hour ago" as of 23:52.
        let dateline = NotifyRules.datelinePhrase(
            occurredAt: plan.occurredAt, deliveredAt: hold ?? now, calendar: .current)
        content.subtitle = [plan.place, dateline].compactMap { $0 }.joined(separator: " · ")
        // Sound rides the class: an alarm sounds, an arrival never does (prd
        // §712). The passive level below already keeps an arrival off the lit
        // screen; a silent banner is what "does not compete" sounds like.
        content.sound = plan.cls == .alarm ? .default : nil
        content.threadIdentifier = plan.cls.rawValue        // iOS groups by this
        // The plan's own ranking, handed to the OS: a scheduled summary leads
        // with the highest score, and this is the same order `collapse` keeps.
        content.relevanceScore = Double(plan.kind.severity) / 100
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
        // Three OS levels for the app's two classes (prd §713): a dispute or
        // a deadline is time-sensitive and pierces a Focus; every other alarm
        // is active and lights the screen; an ARRIVAL is passive — it lands in
        // Notification Center without lighting the screen or sounding, and is
        // read when the person next looks. §644's ruling, taken at its word:
        // attention the app cannot judge is attention it does not claim. The
        // harness pins this line's first branch to the entitlement.
        content.interruptionLevel = plan.isTimeSensitive ? .timeSensitive
            : (plan.cls == .alarm ? .active : .passive)
        if let link = plan.link { content.userInfo = ["link": link] }
        if let art = await attachment(for: plan, photo: photo) { content.attachments = [art] }

        var trigger: UNNotificationTrigger?
        if let hold {
            trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, hold.timeIntervalSince(now)), repeats: false)
        }
        let request = UNNotificationRequest(identifier: plan.id, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
        rememberSent(plan, at: hold ?? now)
    }

    // MARK: - The last thing sent (prd §713)

    /// The one fact that answers "does this work at all" from the settings
    /// sheet: what was last scheduled, and for when. A diagnostic, never a
    /// lane (§644) — one title and one date, overwritten each time.
    static var lastSent: (title: String, at: Date)? {
        guard let title = store.string(forKey: "notify.lastTitle"),
              let at = store.object(forKey: "notify.lastAt") as? Date else { return nil }
        return (title, at)
    }

    private static func rememberSent(_ plan: NotifyPlan, at: Date) {
        store.set(plan.title, forKey: "notify.lastTitle")
        store.set(at, forKey: "notify.lastAt")
    }

    // MARK: - The right-hand slot (§306's ladder)

    /// Rung 1 a real photo the thing holds · rung 2 the source's own mark ·
    /// rung 3 nothing. It never invents: a failed download falls to the mark,
    /// and a source with no bundled asset falls to an honest blank rather than
    /// a drawn stand-in. On a lock screen a fabricated thumbnail is more
    /// convincing than anywhere else in the product, because there is no
    /// surrounding context to contradict it.
    private static func attachment(for plan: NotifyPlan, photo: Data?) async -> UNNotificationAttachment? {
        if let data = await rungOne(plan.art, photo: photo, service: plan.source ?? "Social"),
           let made = write(data, id: plan.id + ".photo") {
            return made
        }
        // Rung 2, refined (prd §714): the event's OWN bundled mark before the
        // source's — USDC's coin on a transfer, Morpho's on a position — through
        // the same `BrandMark` the treemap and the wallet rows draw. A name
        // with no asset resolves nil and the source's mark stands, as before.
        if let mark = plan.mark,
           let image = BrandMark.image(for: mark),
           let data = image.pngData(),
           let made = write(data, id: plan.id + ".mark") {
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

    private static func rungOne(_ art: NotifyArt, photo: Data?, service: String) async -> Data? {
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
            // A host that comes from the row (a face, a cover, an app icon) is
            // the person's data, never a literal — so it is named to the
            // ledger under the SERVICE that landed it, not a fixed "Social".
            if let host = url.host { NetworkLedger.shared.record(host: host, as: service) }
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
        // catalog are plain ASCII — "Ethrex Hegotá" (the seat's name until §629) was filed as
        // `brand-ethrex-hegota` — so a source whose name carries an accent
        // resolved to nothing and fell straight to rung 3, an honest blank slot
        // for a mark that was sitting right there. Found the moment a devnet
        // gained a notification; it would have been just as true of any future
        // seat with an accent in its name.
        // …and through `canonicalSource` (prd §647), for the same reason one
        // rung up: a notification's source may be a seat's PRE-RENAME name.
        let asset = "brand-" + Corpus.canonicalSource(name).lowercased()
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
            art: avatarURL.map { NotifyArt.remote($0) } ?? .none,
            place: String(localized: "Your post on \(source)"))
        await submit([plan])
    }

    // MARK: - The retired whisper

    /// The daily whisper (§165) was a one-shot re-scheduled by every sweep, so
    /// an install that had it on carries a pending `whisper.next` that would
    /// still fire once after the update — with a tap that lands nowhere. Pulled
    /// once per launch; cheap, and idempotent when there is nothing to pull.
    static func cancelRetiredWhisper() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["whisper.next"])
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
