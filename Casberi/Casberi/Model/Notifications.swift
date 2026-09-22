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

    /// One switch per CATEGORY, and nothing else (prd §770, §869). Stored in
    /// the app group so the background task reads the same values the settings
    /// screen writes.
    ///
    /// **On means the digest, for every category, Wallet included.** Nothing a
    /// category holds is delivered on its own except the four kinds in
    /// `NotifyKind.standsAlone`, so a switch has two states and no third. Off
    /// means off for those four too: a switch that still let some things
    /// through would be a switch that lies (§83).
    ///
    /// Every category defaults ON. §644 kept arrivals off because each one was
    /// its own notification riding a grant given for a dispute; one digest
    /// a category, once a day, is not that, and a person who wants less turns a category
    /// off where it is named.
    ///
    /// Stored as the set that is OFF, so a category the catalog adds later
    /// arrives switched on like every other. The two class switches
    /// (`notify.alarms`, `notify.arrivals`) are read once, only to carry an
    /// install that had BOTH off into all-off; nothing writes them now. The
    /// daily whisper's keys (§706) and quiet hours' three (§869) stay unread
    /// as before.
    struct Settings: Sendable, Equatable {
        var off: Set<String> = []

        static var categories: [String] { BridgeCatalog.categories.map(\.name) }

        /// Whether anything at all could fire — the gate on asking iOS for
        /// background time. Everything off means the task has no work, and
        /// asking for a run we would do nothing with is how an app earns a
        /// throttle it then can't spend when it matters.
        var anyOn: Bool { !Set(Self.categories).isSubset(of: off) }

        func allows(category: String) -> Bool { !off.contains(category) }
    }

    private static var store: UserDefaults {
        UserDefaults(suiteName: SharedStore.appGroup) ?? .standard
    }

    static var settings: Settings {
        get {
            var s = Settings()
            let d = store
            if let off = d.stringArray(forKey: "notify.offCategories") {
                s.off = Set(off)
            } else if d.object(forKey: "notify.alarms") != nil,
                      !d.bool(forKey: "notify.alarms"), !d.bool(forKey: "notify.arrivals") {
                // Both classes switched off under the old sheet: the person
                // said "nothing", and a new layout must not overrule that.
                s.off = Set(Settings.categories)
            }
            return s
        }
        set {
            let d = store
            d.set(newValue.off.sorted(), forKey: "notify.offCategories")
        }
    }

    /// The category a plan belongs to, through the catalog's own join. A
    /// source the catalog has never heard of (a thing you made yourself, with
    /// a date on it) falls to Life, the default `BridgeCatalog.category(of:)`
    /// already uses, so every plan answers to exactly one switch.
    static func category(of plan: NotifyPlan) -> String {
        plan.source.flatMap { BridgeCatalog.category(forSource: $0) } ?? "Life"
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

    /// The ask happens the first time something ACTUALLY ARRIVES for a switch
    /// that is on — never at launch (§306). An ask at launch arrives before the
    /// person has seen anything worth being told about, gets declined, and the
    /// decline is permanent short of a trip to Settings. Widened from "the
    /// first alarm" in §770: a category whose only news is a digest would
    /// otherwise be a switch that silently did nothing.
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

    /// The one door. Filters by category, drops anything already fired, sends
    /// the few that stand alone, and folds everything else into the digest.
    ///
    /// `photos` carries real bytes for `.thing(id)` art — the caller has the
    /// `Thing` in hand at the fire site, and passing the data avoids this file
    /// needing a `ModelContext` it would otherwise have to build in a
    /// background task.
    ///
    /// Returns what it really scheduled: the plans that stand alone, then the
    /// digest as it now reads. That is what the probe prints.
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
        let previous = digestState
        var eligible = plans.filter { s.allows(category: category(of: $0)) }
        // Nothing new and nothing queued: no work, and no reason to ask iOS
        // anything. A queue that is not empty still has to be walked, because
        // its slot may have passed or its category may have been switched off.
        guard !eligible.isEmpty || !previous.queue.isEmpty else { return [] }

        // Ask only when something is genuinely in hand — and NEVER on a dry run.
        // A probe that prompts is a probe that changes the state it reports on:
        // it burns the one-and-only system prompt, flips `hasAsked` forever, and
        // `requestAuthorization` then BLOCKS on a dialog no headless run will
        // ever tap, so the probe hangs and prints nothing. Caught by
        // `-notifyProbe` logging a valid plan and then falling silent.
        if !dryRun, !eligible.isEmpty {
            _ = await askIfNeeded()
        }
        if !dryRun {
            guard await authorized() else { return [] }
        }

        // Fires once, ever. Claim BEFORE batching so the count in "and N more"
        // never includes an alarm we already told them about, and so an item
        // already delivered in a digest never queues again.
        if !dryRun {
            let fresh = Set(ledger.claim(eligible.map(\.id)))
            eligible = eligible.filter { fresh.contains($0.id) }
        } else {
            eligible = eligible.filter { !ledger.hasFired($0.id) }
        }

        let alone = NotifyRules.collapse(eligible.filter { $0.kind.standsAlone })
        let next = NotifyDigest.advance(previous,
                                        adding: eligible.filter { !$0.kind.standsAlone }.map(digestItem),
                                        allowed: { s.allows(category: $0.category) },
                                        now: now, calendar: .current,
                                        slots: NotifyDigest.readingSlots(opens: opens, now: now,
                                                                         calendar: .current))
        let digest = NotifyDigest.plans(next.queue)
        guard !dryRun else { return alone + digest }

        for plan in alone {
            await schedule(plan, photo: photos[plan.id], now: now)
        }
        await scheduleDigest(next, previous: previous, now: now)
        return alone + digest
    }

    // MARK: - The reading hour

    /// When the person opened the app, newest last, kept only as long as
    /// `NotifyDigest.readingSlots` looks back. Stored in the app group so the
    /// background sweep schedules against the same habit the foreground saw.
    /// Times only, on this device: nothing about what was opened.
    static var opens: [Date] {
        (store.array(forKey: "notify.opens") as? [Double] ?? []).map(Date.init(timeIntervalSince1970:))
    }

    /// Called on every foreground activation. One entry per activation, the
    /// oldest dropped past the lookback, and bounded outright so a device
    /// that is opened constantly cannot grow the array.
    static func recordOpen(now: Date = .now) {
        let floor = now.addingTimeInterval(-NotifyDigest.readingLookback).timeIntervalSince1970
        var kept = (store.array(forKey: "notify.opens") as? [Double] ?? []).filter { $0 >= floor }
        kept.append(now.timeIntervalSince1970)
        store.set(Array(kept.suffix(200)), forKey: "notify.opens")
    }

    // MARK: - The digest (prd §770)

    /// The queue and its slot, kept between sweeps in the app group so the
    /// background task and a foreground sweep extend the same digest.
    static var digestState: NotifyDigest.State {
        get {
            guard let data = store.data(forKey: "notify.digest"),
                  let state = try? JSONDecoder().decode(NotifyDigest.State.self, from: data)
            else { return NotifyDigest.State() }
            return state
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                store.set(data, forKey: "notify.digest")
            }
        }
    }

    private static func digestItem(_ plan: NotifyPlan) -> NotifyDigest.Item {
        let source = plan.source ?? "Casberi"
        var picture: String?
        if case .remote(let url) = plan.art { picture = url }
        return NotifyDigest.Item(id: plan.id,
                                 seat: BridgeCatalog.seatName(forSource: source),
                                 name: source,
                                 category: category(of: plan),
                                 kind: plan.kind.rawValue,
                                 title: plan.title,
                                 body: plan.body,
                                 link: plan.link,
                                 occurredAt: plan.occurredAt,
                                 source: plan.source,
                                 picture: picture,
                                 mark: plan.mark,
                                 who: plan.who,
                                 usd: plan.usd)
    }

    private static func digestRequestID(_ slot: Date, _ category: String) -> String {
        NotifyDigest.requestPrefix + category + ":" + String(Int(slot.timeIntervalSince1970))
    }

    /// Rewrites the pending request for the slot with the queue as it stands.
    /// Unchanged state schedules nothing, so a sweep with no news does not
    /// churn a request or re-fetch its picture.
    private static func scheduleDigest(_ next: NotifyDigest.State,
                                       previous: NotifyDigest.State,
                                       now: Date) async {
        guard next != previous else { return }
        digestState = next
        // "Last sent" is said only once a slot has PASSED. Recording a digest
        // when it is scheduled would put a time still to come on the settings
        // sheet under the word "sent" (§83).
        if let old = previous.slot, old <= now, let sent = NotifyDigest.plans(previous.queue).first {
            rememberSent(sent, at: old)
        }
        let center = UNUserNotificationCenter.current()
        // A pending slot that moved is pulled whole; one that stayed loses only
        // the categories that emptied or were switched off, because re-adding
        // an id replaces it. One that has passed is already delivered, and
        // pulling a PENDING id cannot touch it. The bare slot id is the
        // single-digest request an install scheduled before the split.
        if let old = previous.slot, old > now {
            let kept: Set<String> = old == next.slot ? Set(next.queue.map(\.category)) : []
            let gone = Set(previous.queue.map(\.category)).subtracting(kept)
            center.removePendingNotificationRequests(
                withIdentifiers: gone.map { digestRequestID(old, $0) }
                    + [NotifyDigest.requestPrefix + String(Int(old.timeIntervalSince1970))])
        }
        guard let slot = next.slot else { return }

        for group in NotifyDigest.groups(next.queue) {
            guard let plan = NotifyDigest.plan(group), let category = group.first?.category else { continue }
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            if group.count == 1 {
                let dateline = NotifyRules.datelinePhrase(
                    occurredAt: plan.occurredAt, deliveredAt: slot, calendar: .current)
                content.subtitle = [plan.place, dateline].compactMap { $0 }.joined(separator: " · ")
            }
            // Lights the screen and makes no sound: one a category, once a
            // day, neither hidden nor loud. One thread, so the categories
            // arriving together read as one stack.
            content.sound = nil
            content.interruptionLevel = .active
            content.threadIdentifier = "digest"
            // Ranked by the most urgent thing inside, so a scheduled summary
            // leads with the Wallet digest's transfer, not the Social one's like.
            content.relevanceScore = NotifyDigest.relevance(group)
            var info: [AnyHashable: Any] = [:]
            if let link = plan.link { info["link"] = link }
            if group.count == 1, let art = await attachment(for: plan, photo: nil) {
                content.attachments = [art]
            } else if group.count > 1 {
                // Several things: the thumbnail is the faces and app tiles
                // (§770), and the long press is the card, its rows drawn by
                // the NotificationContent extension (prd §809), under the
                // same picture at card size. Every picture rides the
                // notification as an ATTACHMENT, the tile sheet first (iOS
                // draws the first as the thumbnail), so the extension needs
                // no app group and no shared folder (§809a).
                var attachments: [UNNotificationAttachment] = []
                if let sheet = await tileSheetPNG(for: group),
                   let made = write(sheet, id: plan.id + ".tiles", identifier: NotifyCard.headAttachment) {
                    attachments.append(made)
                }
                if var card = NotifyDigest.card(group) {
                    if !attachments.isEmpty { card.head = NotifyCard.headAttachment }
                    let faced = await withFaces(card, items: Array(NotifyDigest.ordered(group)
                        .prefix(NotifyDigest.cardRowCap)), id: plan.id)
                    attachments += faced.files
                    if let data = faced.card.encoded() { info[NotifyCard.userInfoKey] = data }
                    content.categoryIdentifier = NotifyCard.category
                }
                content.attachments = attachments
            }
            content.userInfo = info
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, slot.timeIntervalSince(now)), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: digestRequestID(slot, category),
                                                        content: content, trigger: trigger))
        }
    }

    /// Delivered when the sweep finds it — there is no hold (prd §869).
    ///
    /// The app used to run quiet hours of its own, and it was both unexplained
    /// and wrong twice over: it held `positionAtRisk` and `safeSignatureNeeded`
    /// until morning, the two kinds §770 stands alone precisely BECAUSE they
    /// cannot keep; and iOS already does this better than an app can, per
    /// person and system-wide. A Sleep Focus silences everything below
    /// `.timeSensitive`, which is every plan but a dispute and a deadline.
    private static func schedule(_ plan: NotifyPlan,
                                 photo: Data?,
                                 now: Date) async {
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        // The subtitle is WHERE and, when delivery lags the event, WHEN (prd
        // §712). Nothing is held any more, so the moment of delivery is `now` —
        // but the lag is still real, because iOS decides when the background
        // task runs and an event can be hours old before this line sees it.
        let dateline = NotifyRules.datelinePhrase(
            occurredAt: plan.occurredAt, deliveredAt: now, calendar: .current)
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
        // break a Focus. This line is unchanged — it was always correct; what
        // changed is that iOS stopped silently capping it to `.active`. Since
        // §869 it carries more weight: it is now the ONE thing deciding what
        // may reach a sleeping person, with iOS's Focus on the other side.
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

        // A nil trigger means "as soon as this is added", which is the whole
        // rule now: the sweep found it, so it goes.
        let request = UNNotificationRequest(identifier: plan.id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
        rememberSent(plan, at: now)
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

    // MARK: - The digest's thumbnail (prd §770)

    private enum LoadedTile: Sendable {
        case picture(Data)
        case mark(UIImage)
    }

    /// Several things in one category draw their people and their apps
    /// together as one square, up to four: a picture is a circle, a mark a
    /// rounded tile (user, 2026-09-15: "mixed together is fine avatars and
    /// faces"). The pictures are fetched at once, each on rung 1's short
    /// budget; one that misses falls to its app's mark, and a tile with
    /// nothing to draw is left out. Nothing at all draws no thumbnail.
    private static func tileSheetPNG(for group: [NotifyDigest.Item]) async -> Data? {
        let tiles = NotifyDigest.tiles(group)
        let loaded = await withTaskGroup(of: (Int, LoadedTile?).self) { tasks in
            for (index, tile) in tiles.enumerated() {
                tasks.addTask { @MainActor in
                    switch tile {
                    case .picture(let url, let source):
                        if let data = await rungOne(.remote(url), photo: nil, service: source ?? "Casberi") {
                            return (index, .picture(data))
                        }
                        return (index, source.flatMap(brandAsset).map(LoadedTile.mark))
                    case .mark(let name):
                        return (index, (BrandMark.image(for: name) ?? brandAsset(name)).map(LoadedTile.mark))
                    }
                }
            }
            var out: [(Int, LoadedTile?)] = []
            for await result in tasks { out.append(result) }
            return out.sorted { $0.0 < $1.0 }.compactMap(\.1)
        }
        guard !loaded.isEmpty else { return nil }
        return await Task.detached(priority: .utility, operation: { composeTiles(loaded) }).value
    }

    /// Draws the tiles into one 240px square, off the main thread, at scale 1
    /// (iOS shows it at about 40pt, and the renderer defaults to 3×). One tile
    /// fills it, two overlap on the diagonal, three or four sit in a grid.
    nonisolated private static func composeTiles(_ tiles: [LoadedTile]) -> Data? {
        let images: [(image: UIImage, round: Bool)] = tiles.compactMap { tile in
            switch tile {
            case .picture(let data): return UIImage(data: data).map { ($0, true) }
            case .mark(let image): return (image, false)
            }
        }
        guard !images.isEmpty else { return nil }
        let side: CGFloat = 240
        let rects: [CGRect]
        switch images.count {
        case 1:
            rects = [CGRect(x: 0, y: 0, width: side, height: side)]
        case 2:
            rects = [CGRect(x: 0, y: 0, width: 150, height: 150),
                     CGRect(x: 90, y: 90, width: 150, height: 150)]
        default:
            let cell: CGFloat = 112, gap: CGFloat = 16
            rects = images.indices.map { i in
                CGRect(x: CGFloat(i % 2) * (cell + gap), y: CGFloat(i / 2) * (cell + gap),
                       width: cell, height: cell)
            }
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).pngData { context in
            for (tile, rect) in zip(images, rects) {
                context.cgContext.saveGState()
                let clip = tile.round
                    ? UIBezierPath(ovalIn: rect)
                    : UIBezierPath(roundedRect: rect, cornerRadius: rect.width * 0.22)
                clip.addClip()
                let size = tile.image.size
                let scale = max(rect.width / max(size.width, 1), rect.height / max(size.height, 1))
                let drawn = CGSize(width: size.width * scale, height: size.height * scale)
                tile.image.draw(in: CGRect(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2,
                                           width: drawn.width, height: drawn.height))
                context.cgContext.restoreGState()
            }
        }
    }

    // MARK: - The card's faces (prd §809)

    /// Fills each row's lead: the item's picture when it has one (a face, a
    /// cover), otherwise its own mark, otherwise its app's — rung 1 and rung 2
    /// of the ladder the single notification climbs. Fetched at once, each on
    /// rung 1's short budget, downscaled, and handed back as attachments the
    /// extension reads by identifier. A row with nothing to draw keeps a nil
    /// face and the extension draws its initial.
    private static func withFaces(_ card: NotifyCard, items: [NotifyDigest.Item],
                                  id: String) async -> (card: NotifyCard, files: [UNNotificationAttachment]) {
        let loaded = await withTaskGroup(of: (Int, Data?, Bool).self) { tasks in
            for (index, item) in items.enumerated() {
                tasks.addTask { @MainActor in
                    if let picture = item.picture, !picture.isEmpty,
                       let data = await rungOne(.remote(picture), photo: nil, service: item.source ?? "Casberi") {
                        return (index, data, true)
                    }
                    let mark = item.mark.flatMap { BrandMark.image(for: $0) } ?? brandAsset(item.seat)
                    return (index, mark?.pngData(), false)
                }
            }
            var out: [(Int, Data?, Bool)] = []
            for await result in tasks { out.append(result) }
            return out.sorted { $0.0 < $1.0 }
        }
        var faced = card
        var files: [UNNotificationAttachment] = []
        for (index, data, round) in loaded where index < faced.rows.count {
            guard let data,
                  let small = await Task.detached(priority: .utility, operation: { downscale(data) }).value
            else { continue }
            let name = NotifyCard.faceAttachment(index)
            guard let made = write(small, id: id + "." + name, identifier: name) else { continue }
            files.append(made)
            faced.rows[index].face = name
            faced.rows[index].round = round
        }
        return (faced, files)
    }

    /// A lead is drawn at 26pt, so 96px covers 3× with room; a 2MB avatar
    /// would otherwise be copied whole into the container for every digest.
    nonisolated private static func downscale(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let side: CGFloat = 96
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).pngData { _ in
            let size = image.size
            let scale = max(side / max(size.width, 1), side / max(size.height, 1))
            let drawn = CGSize(width: size.width * scale, height: size.height * scale)
            image.draw(in: CGRect(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2,
                                  width: drawn.width, height: drawn.height))
        }
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
    private static func write(_ data: Data, id: String, identifier: String = "") -> UNNotificationAttachment? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("notify", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = id.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let url = dir.appendingPathComponent(safe + ".png")
        guard (try? data.write(to: url)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: identifier, url: url, options: nil)
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
            place: String(localized: "Your post on \(source)"),
            who: lead)
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

    /// The digest's category, so iOS hands its long press to the
    /// NotificationContent extension. No actions: every row in the card is
    /// already a door to its own thing, and a button repeating one would be
    /// the same door twice (§736).
    static func registerCategories() {
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: NotifyCard.category, actions: [],
                                   intentIdentifiers: [], options: [])
        ])
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
