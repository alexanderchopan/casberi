import Foundation
import SwiftData
import WidgetKit

/// Fills the app group the widgets read from (2026-08-14, prd §382).
///
/// `TodayBrief.publishLedeToWidget` was the first of these and for a year it was
/// the only one, which is why the Home Screen could show exactly one sentence
/// and nothing else the app knows. Everything here already existed as a reading
/// the app computes on every foreground anyway — the kept asks' own deltas, the
/// deadlines `upcoming` scans for, the wallet series the balance card draws —
/// and was simply never handed across the process boundary. So this adds no new
/// computation of its own beyond one bounded fetch; it is a publication step,
/// not a feature that runs work.
///
/// Called from `RootShell`'s foreground pass, immediately after
/// `KeptAskStore.refreshDigests` — which is the pass that produces the readings
/// this publishes, so running before it would publish the previous foreground's
/// numbers forever, always one open behind.
@MainActor
enum WidgetPublish {

    /// Publishes every payload and reloads only the timelines whose bytes
    /// actually changed.
    ///
    /// `things` is the caller's OWN corpus slice — the newest-600 the foreground
    /// pass already paid for. Reusing it rather than fetching again is both
    /// cheaper and MORE correct: `TodayBrief.flowBand` computes the brief's own
    /// band from exactly this array, so the tile and the brief make the same
    /// claim by construction rather than by two reads that could disagree.
    ///
    /// Deadlines are the one payload that still runs its own fetch, and for a
    /// reason this array cannot fix — see `deadlines(context:)`.
    static func publishAll(things: [Thing], context: ModelContext) {
        // The §217 demo doctrine, applied to EVERY payload (2026-09-05): the
        // Today lede already stayed home under the demo (`TodayBrief`'s
        // `skipLiveReads`), but the day lead, the flow band, the deadlines,
        // the Safe call and the wallet tile did not — the demo census found a
        // "money · 3 pictures" lead published from a corpus that is nobody's,
        // onto the most public surface the OS has, with nothing named to take
        // it down on exit. Nothing the demo composes reaches a widget.
        guard !DemoMode.isActive else { return }
        guard let group = UserDefaults(suiteName: SharedStore.appGroup) else { return }
        let things = things.live
        var stale: [String] = []

        // The kept-ask payload only has a reader while the ask is drawn: its
        // widget left the bundle with the ask (prd §697b), so writing it on
        // every foreground and reloading a kind nothing registers is work for
        // no tile. Returns with the flag, like the widget.
        if AskSurface.enabled, writeAsks(to: group) { stale.append(WidgetAsks.kind) }
        // Today (prd §877): the asks and the people are the tile's own; the
        // deadlines and the Safe call below ride it too, so every one of the
        // four reloads the same kind.
        let requests = requests(things: things)
        let people = people(things: things)
        if WidgetPayload.write(requests, key: WidgetToday.requestsKey,
                               stampKey: WidgetToday.requestsStampKey, defaults: group) {
            stale.append(WidgetToday.kind)
        }
        if WidgetPayload.write(people, key: WidgetToday.peopleKey,
                               stampKey: WidgetToday.peopleStampKey, defaults: group) {
            stale.append(WidgetToday.kind)
        }
        if WidgetPayload.write(flow(things: things), key: WidgetWallet.flowKey,
                               stampKey: WidgetWallet.flowStampKey, defaults: group) {
            stale.append(WidgetWallet.kind)
        }
        let deadlines = deadlines(context: context)
        if WidgetPayload.write(deadlines, key: WidgetDeadlines.key,
                               stampKey: WidgetDeadlines.stampKey, defaults: group) {
            stale.append(WidgetToday.kind)
        }
        if WidgetPayload.write(safeCall(things: things), key: WidgetSafe.key,
                               stampKey: WidgetSafe.stampKey, defaults: group) {
            stale.append(WidgetToday.kind)
        }
        if WidgetPayload.write(wallet(), key: WidgetWallet.key,
                               stampKey: WidgetWallet.stampKey, defaults: group) {
            stale.append(WidgetWallet.kind)
        }

        // The accent every tile draws with is NOT written here — `ThemeStore`
        // already publishes it to the same app group on init, and a second
        // writer for one key is how the two spellings of a colour start
        // disagreeing about which is current.

        for kind in Set(stale) { WidgetCenter.shared.reloadTimelines(ofKind: kind) }

        // The pictures the Today rows lead with. Off the main actor and after
        // the reloads: a mark or a face that arrives a moment later reloads
        // the tile once more, and a tile drawn before it falls back to a
        // monogram, never to an empty slot.
        let sources = Set(things.prefix(WidgetLeadImages.landedScan).map(\.source))
            .union((deadlines ?? []).map(\.source))
            .union((requests ?? []).map(\.source))
            .union((people?.replies ?? []).map(\.source))
            .union([people?.likes?.source, "Safe"].compactMap { $0 })
        // Faces: every reply the tile may draw (a reply from this morning is
        // rarely among the eight newest things), then the newest things.
        let replyFloor = Date.now.addingTimeInterval(-WidgetToday.peopleWindow)
        let faced = things.filter { $0.socialContext == "reply" && $0.capturedAt > replyFloor }
            .prefix(replyCap) + things.prefix(WidgetLeadImages.landedScan)
        let faces = faced
            .compactMap { t in t.authorAvatarURL.flatMap { $0.isEmpty ? nil : (url: $0, service: t.source) } }
        WidgetLeadImages.refresh(sources: sources, faces: Array(faces.prefix(WidgetLeadImages.faceCap)))

        // The hero's payloads have no reader since §877. Cleared rather than
        // left in the app group forever; a no-op once they are gone.
        for key in ["widget.lede", "widget.ledeAt", "widget.themes", "widget.themesAt",
                    "widget.dayLead", "widget.dayLeadAt"] where group.object(forKey: key) != nil {
            group.removeObject(forKey: key)
        }
    }

    /// Publishes the kept asks ALONE, and reloads them if they changed.
    ///
    /// Called the instant a question is kept or removed (`KeptAskStore`), which
    /// `publishAll` cannot cover: the full pass runs on foreground, and the
    /// sequence that matters here never crosses one — keep a question, press
    /// Home, add the widget. Without this the picker wouldn't list the question
    /// you just kept, and a tile pointed at one you just removed would go on
    /// showing it until the next time you opened and left the app.
    ///
    /// Needs no `ModelContext`, which is why it can live on that store's own
    /// keep/remove path: a kept ask's title comes from `KeptAskStore` itself.
    /// The new question publishes with NO reading — its composer hasn't run yet
    /// — which the tile already renders honestly as "Open to answer".
    ///
    /// Dark while the ask is deprecated (prd §697b) — see `publishAll`.
    static func publishAsks() {
        guard AskSurface.enabled,
              let group = UserDefaults(suiteName: SharedStore.appGroup) else { return }
        if writeAsks(to: group) {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetAsks.kind)
        }
    }

    private static func writeAsks(to group: UserDefaults) -> Bool {
        WidgetPayload.write(asks(), key: WidgetAsks.key,
                            stampKey: WidgetAsks.stampKey, defaults: group)
    }

    // MARK: - Kept asks

    /// The standing questions, newest-kept first, each with the reading its own
    /// deterministic composer wrote this pass.
    ///
    /// A kept ask with NO reading is published anyway rather than skipped. The
    /// question is the durable half (see `WidgetPayload`'s header) and a tile
    /// that disappears because a composer hasn't run yet reads as the widget
    /// breaking; a tile showing the question alone reads as the app being quiet,
    /// which is what is actually true.
    static func asks() -> [WidgetAskCell]? {
        let store = KeptAskStore.shared
        guard !store.order.isEmpty else { return nil }
        let cells = store.order.prefix(askCap).map { kind -> WidgetAskCell in
            let digest = store.currentDigests[kind] ?? ""
            let reading = store.currentDeltas[kind]
            return WidgetAskCell(kind: kind,
                                 title: store.titles[kind] ?? kind,
                                 reading: (reading?.isEmpty == false) ? reading : nil,
                                 // Only ever a signal that something moved — the
                                 // same plain string compare the composer's pill
                                 // dot uses, never a count of what moved (§213).
                                 changed: store.changed(kind, digest: digest))
        }
        return Array(cells)
    }

    /// More than a dozen kept asks is already past what any tile can offer to
    /// choose between, and the payload is read on every widget refresh.
    static let askCap = 12

    // MARK: - Today (prd §877)

    /// GitHub's asks — a review requested or an issue assigned — that landed
    /// inside `WidgetToday.requestWindow`, newest first.
    ///
    /// Read off the row's TAG (`GitHubFeeds.notificationAsk`), never its title,
    /// and only on a notification row (`gh:notif:`): App Store Connect wears a
    /// "Review" tag too, for a different thing. "Mentioned" is left out on
    /// purpose — it asks for nothing, it is news.
    static func requests(things: [Thing], now: Date = .now) -> [WidgetRequest]? {
        let floor = now.addingTimeInterval(-WidgetToday.requestWindow)
        let rows = things.live
            .filter { ($0.sourceRef ?? "").hasPrefix("gh:notif:") && $0.mark != .done
                        && $0.capturedAt > floor }
            .compactMap { thing -> WidgetRequest? in
                let subject = requestSubject(thing)
                let title: String
                if thing.tags.contains("Review") {
                    title = String(localized: "Review: \(subject)")
                } else if thing.tags.contains("Assigned") {
                    title = String(localized: "Assigned: \(subject)")
                } else {
                    return nil
                }
                return WidgetRequest(id: thing.id.uuidString, title: title,
                                     source: thing.source, askedAt: thing.capturedAt)
            }
            .sorted { $0.askedAt > $1.askedAt }
            .prefix(requestCap)
        return rows.isEmpty ? nil : Array(rows)
    }

    static let requestCap = 4

    /// The pull request's or issue's own title. The row's title is
    /// "<reason> · <owner/repo> · <subject>", and the reason is LOCALIZED, so
    /// the cut is made after the repo, which is read off the row's URL — data,
    /// not display copy. A row whose title does not carry that seam keeps its
    /// whole title.
    static func requestSubject(_ thing: Thing) -> String {
        guard let url = URL(string: thing.content), url.host == "github.com" else { return thing.title }
        let parts = url.path.split(separator: "/")
        guard parts.count >= 2 else { return thing.title }
        let seam = " · \(parts[0])/\(parts[1]) · "
        guard let range = thing.title.range(of: seam) else { return thing.title }
        let subject = thing.title[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return subject.isEmpty ? thing.title : subject
    }

    /// Replies to your posts inside `WidgetToday.peopleWindow`, newest first,
    /// and the newest like roll. `socialContext == "reply"` is set only on the
    /// inbound read of your OWN posts (§804), and a like roll exists only for
    /// a post that read asked about, which is only ever yours.
    static func people(things: [Thing], now: Date = .now) -> WidgetPeople? {
        let floor = now.addingTimeInterval(-WidgetToday.peopleWindow)
        let replies = things.live
            .filter { $0.socialContext == "reply" && $0.capturedAt > floor }
            .sorted { $0.capturedAt > $1.capturedAt }
            .prefix(replyCap)
            .map { thing in
                WidgetReply(id: thing.id.uuidString,
                            who: SocialRoomSource.author(of: thing),
                            words: SocialRoomSource.words(of: thing)
                                .replacingOccurrences(of: "\n", with: " "),
                            source: thing.source, at: thing.capturedAt,
                            face: thing.authorAvatarURL.flatMap { $0.isEmpty ? nil : WidgetImages.faceKey(url: $0) })
            }
        let byRef = Dictionary(things.live.compactMap { t in t.sourceRef.map { ($0, t) } },
                               uniquingKeysWith: { first, _ in first })
        let likes = SocialLikers.shared.rolls
            .filter { $0.value.when > floor && byRef[$0.key] != nil }
            .max { $0.value.when < $1.value.when }
            .flatMap { entry -> WidgetLikes? in
                guard let line = entry.value.line, let post = byRef[entry.key] else { return nil }
                return WidgetLikes(line: line, source: post.source, at: entry.value.when,
                                   id: post.id.uuidString)
            }
        guard !replies.isEmpty || likes != nil else { return nil }
        return WidgetPeople(replies: Array(replies), likes: likes)
    }

    static let replyCap = 4

    // MARK: - The flow band

    /// The week's money in against money out.
    ///
    /// Reads `WalletFlowSource.band` over exactly the array `TodayBrief.flowBand`
    /// reads, so the tile and the brief cannot disagree about the same week.
    ///
    /// **Nothing is gated here**, which is the same note the brief's own composer
    /// carries: `WalletFlow.band` already declines on an unpriceable window, on
    /// fewer than two lanes, and on lanes too thin to draw honestly. Re-deciding
    /// any of that would be a second opinion that could disagree with the room's.
    ///
    /// The LANES are dropped — the widget draws totals and a ratio, never
    /// counterparties (see `WidgetFlowBand`) — but their COUNTS are kept, because
    /// they are what says how much of the week is actually in the bars.
    static func flow(things: [Thing], now: Date = .now) -> WidgetFlowBand? {
        // `span` is a DURATION, not a date — `TodayBrief.flowBand` converts it the
        // same way, and passing it straight through would silently ask for a
        // window starting at 1970.
        guard let span = WalletRange.week.span,
              let band = WalletFlowSource.band(from: things,
                                               since: now.addingTimeInterval(-span))
        else { return nil }
        let priced = (band.inLanes + band.outLanes).reduce(0) { $0 + $1.count }
        let hidden = BalancePrivacy.shared.hidden
        // The weights are computed HERE, from the real figures, and travel
        // whether or not the figures do — §374 rule 3: figures go, shapes stay.
        let weights = WidgetFlowBand.weights(inUSD: band.inUSD, outUSD: band.outUSD)
        return WidgetFlowBand(inWeight: weights.0, outWeight: weights.1,
                              inUSD: hidden ? nil : band.inUSD,
                              outUSD: hidden ? nil : band.outUSD,
                              unpriced: band.unpricedCount,
                              predating: band.predatingCount,
                              priced: priced,
                              hidden: hidden)
    }

    // MARK: - Deadlines

    /// The soonest things that want something from you, overdue first.
    ///
    /// ITS OWN FETCH, not the caller's corpus slice. The foreground pass carries
    /// the newest 600 rows BY CAPTURE DATE, and a deadline's whole nature is that
    /// it was captured long before it matters — a 1Claw grant expiry or an ENS
    /// name lands months ahead of its date, and would drop out of that slice
    /// within a week. `KeptAskComposers.upcoming` reads the same slice and
    /// carries the same limitation; this is the one place it is worth a fetch of
    /// its own, because a home-screen tile that silently stops mentioning a
    /// deadline it used to mention is worse than one that never had it.
    ///
    /// `mark` is filtered IN MEMORY on purpose — `#Predicate` cannot compare a
    /// Codable enum (the note `ScreenshotNaming`/`ScreenshotIngest` each already
    /// carry), so a done-filter in SQL isn't available at any price.
    ///
    /// KNOWN CEILING, stated rather than papered over: the fetch takes the 500
    /// furthest-FUTURE dated rows, so a corpus holding more than 500 rows dated
    /// beyond the horizon would push the near ones out of view. Descending is
    /// chosen precisely because the past accumulates forever and the future does
    /// not, which makes that the survivable direction to be wrong in. The clean
    /// fix is a floor inside the predicate, which needs a force-unwrap of an
    /// optional inside `#Predicate` — a shape this codebase has no precedent for
    /// and has been burned by once (the `tags.contains` runtime crash), so it is
    /// not being introduced on a widget's account.
    static func deadlines(context: ModelContext, now: Date = .now) -> [WidgetDeadline]? {
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.dueAt != nil },
            sortBy: [SortDescriptor(\.dueAt, order: .reverse)])
        // Only the five fields this reads. It runs on EVERY foreground, on the
        // main actor, in the same window the app has spent three perf passes
        // clearing — and a `Thing` carries sixty stored properties, so
        // materializing 500 of them whole to look at five is exactly the shape
        // of work those passes removed.
        descriptor.propertiesToFetch = [\.id, \.title, \.source, \.dueAt, \.mark]
        descriptor.fetchLimit = 500
        guard let dated = try? context.fetch(descriptor) else { return nil }

        let floor = Calendar.current.date(byAdding: .day, value: -overdueHorizonDays, to: now) ?? now
        let ceiling = Calendar.current.date(byAdding: .day, value: aheadHorizonDays, to: now) ?? now
        // DEDUPED (prd §877, seen on the sim: "Book dentist" from Reminders
        // and "Book the dentist" from Todoist as two rows). The brief's own
        // pass, so the tile and the brief collapse the same errands.
        let rows = TodayBrief.dedupeDeadlines(dated.live
            .filter { thing in
                guard thing.mark != .done, let due = thing.dueAt else { return false }
                return due >= floor && due <= ceiling
            })
            .sorted { ($0.dueAt ?? now) < ($1.dueAt ?? now) }
            .prefix(WidgetDeadlines.publishCap)
            .map { WidgetDeadline(id: $0.id.uuidString, title: $0.title,
                                  source: $0.source, due: $0.dueAt ?? now) }
        return rows.isEmpty ? nil : Array(rows)
    }

    /// The signature a co-signer is waiting on, for the same tile (2026-08-17).
    ///
    /// Published SEPARATELY from `deadlines` rather than folded into it, and the
    /// separation is the whole design: a your-turn signature carries no due
    /// date, so it cannot be a `WidgetDeadline` without inventing one — and an
    /// invented date would sort among real deadlines and draw itself late. It is
    /// a reading and takes the reading's short shelf life (`WidgetSafe`).
    ///
    /// Reads the room head rather than the corpus, so the tile and the room can
    /// never disagree about how many transactions need you; `things` is used
    /// only to resolve the lead's `sourceRef` into an id the tile can open. That
    /// lookup deliberately does NOT fetch: the id is a convenience (the tile
    /// falls back to the ask when it is nil), and a second fetch on every
    /// foreground for a convenience is not a trade this pass makes.
    @MainActor
    static func safeCall(things: [Thing], now: Date = .now) -> WidgetSafeCall? {
        guard let room = SafeRoomSource.compose(things: things, now: now),
              let lead = room.entries.first(where: \.awaitsYou)
        else { return nil }
        let id = things.live.first { $0.sourceRef == lead.ref }?.id.uuidString
        return WidgetSafeCall(id: id,
                              subject: lead.descriptionText,
                              awaitsYou: room.awaitsYouCount,
                              ready: room.readyCount,
                              waitingDays: SafeRoom.stuckDays(room, now: now))
    }

    /// How far back an overdue thing still counts as wanting something from you.
    /// A month, not forever: a task three years late is not a deadline any more,
    /// it is a thing nobody did, and letting it lead this tile permanently would
    /// make the tile impossible to clear and therefore impossible to trust.
    static let overdueHorizonDays = 30
    /// How far ahead to look. Wider than `upcoming`'s one week, because a tile
    /// with nothing on it is worth spending on a real deadline twelve days out,
    /// where a chip you asked for is not.
    static let aheadHorizonDays = 60

    // MARK: - Wallet

    /// The combined value line, reduced to what a sparkline needs.
    ///
    /// Reads `WalletStore.combinedValueSamples()` — the same forward-only,
    /// never-back-filled, alignment-guarded series the app's own balance card
    /// draws — rather than re-deriving one, so the widget's curve and the app's
    /// curve can never disagree about history. Empty until that series exists at
    /// all (it needs two aligned points across every watched wallet, §77), and
    /// nil here means the tile declines rather than inventing a flat line.
    static func wallet(now: Date = .now) -> WidgetWalletLine? {
        let samples = WalletStore.shared.combinedValueSamples()
        guard samples.count >= 2, let last = samples.last else { return nil }
        let trimmed = samples.suffix(WidgetWallet.pointCap)
        let points = trimmed.map(\.usd)

        // Nil, never zero, when the window's opening value is zero — a percent
        // change against nothing is a division, not a reading (§83).
        var changePct: Double?
        if let first = points.first, first > 0 {
            changePct = (last.usd - first) / first * 100
        }

        let hidden = BalancePrivacy.shared.hidden
        return WidgetWalletLine(points: points,
                                total: hidden ? nil : last.usd,
                                changePct: hidden ? nil : changePct,
                                hidden: hidden,
                                asOf: last.at)
    }

    #if DEBUG
    /// `-widgetProbe YES` — everything the widgets would draw this launch, one
    /// NSLog per line (a joined multi-line message gets truncated by the log
    /// reader — the `-todayProbe` lesson).
    ///
    /// It exists because an EMPTY tile has causes that render identically and
    /// only some are bugs: nothing kept, nothing due, no wallet watched, a
    /// payload that aged past its own freshness window, or a publish that never
    /// ran because the foreground pass bailed early. The `age=` column is the
    /// one that separates the last two, and reading the payload back through the
    /// SAME reader the widget uses (rather than the values just computed) is
    /// what makes this a test of the round trip rather than of the gather.
    static func probe(context: ModelContext) {
        let group = UserDefaults(suiteName: SharedStore.appGroup)
        // The same slice the foreground pass hands `publishAll`, so the probe
        // measures what production measures rather than a different corpus.
        var d = FetchDescriptor<Thing>(sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        d.fetchLimit = 600
        let things = Corpus.surfaced((try? context.fetch(d)) ?? [])
        publishAll(things: things, context: context)

        let asks = WidgetAsks.published(defaults: group)
        NSLog("[Casberi] widgetProbe| asks=%d", asks.count)
        for cell in asks {
            NSLog("[Casberi] widgetAsk| kind=%@ changed=%@ reading=%@ title=\"%@\"",
                  cell.kind, cell.changed ? "YES" : "no",
                  cell.reading ?? "(none — question stands alone)", cell.title)
        }

        // Today (prd §877): what each section was handed, then the rows the
        // medium tile would draw — the plan the widget runs, over the same
        // payloads read back through the widget's own readers.
        let requests = WidgetToday.requests(defaults: group)
        let people = WidgetToday.people(defaults: group)
        NSLog("[Casberi] widgetToday| requests=%d replies=%d likes=%@",
              requests.count, people.replies.count, people.likes == nil ? "no" : "yes")
        let plan = WidgetTodayPlan.make(
            deadlines: WidgetDeadlines.published(defaults: group),
            safe: WidgetSafe.published(defaults: group),
            requests: requests, people: people, landed: [], capacity: 4, now: .now)
        NSLog("[Casberi] widgetToday| late=%d toSign=%d next=%@ faces=%d",
              plan.late, plan.toSign, plan.next?.title ?? "none", plan.faces.count)
        for row in plan.rows {
            NSLog("[Casberi] widgetTodayRow| %@ %@ \"%@\"", "\(row.section)", "\(row.kind)", row.title)
        }
        let dir = WidgetImages.directory()
        let files = dir.flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path) } ?? []
        NSLog("[Casberi] widgetToday| images marks=%d faces=%d",
              files.filter { $0.hasPrefix("mark-") }.count, files.filter { $0.hasPrefix("face-") }.count)

        let due = WidgetDeadlines.published(defaults: group)
        NSLog("[Casberi] widgetProbe| deadlines=%d", due.count)
        for row in due {
            NSLog("[Casberi] widgetDeadline| %@ due=%@ source=%@ title=\"%@\"",
                  row.isOverdue() ? "OVERDUE" : "ahead",
                  ISO8601DateFormatter().string(from: row.due), row.source, row.title)
        }

        if let line = WidgetWallet.published(defaults: group) {
            let age = Date.now.timeIntervalSince(line.asOf) / 3600
            NSLog("[Casberi] widgetWallet| points=%d total=%@ change=%@ hidden=%@ age=%.1fh stamped=%@",
                  line.points.count,
                  line.total.map { String(format: "%.2f", $0) } ?? "withheld",
                  line.changePct.map { String(format: "%+.2f%%", $0) } ?? "unknown",
                  line.hidden ? "YES" : "no", age,
                  age * 3600 > WidgetWallet.stampAfter ? "YES" : "no")
        } else {
            NSLog("[Casberi] widgetWallet| none — no watched wallet, or fewer than two aligned samples")
        }

        // The week's flow. `none` is the HEALTHY answer for most weeks — the
        // band declines on an unpriceable window, on fewer than two lanes, and
        // on lanes too thin to draw honestly — so the line names which, and
        // `priced/total` is the disclosure the bars themselves carry.
        if let band = WidgetWallet.flow(defaults: group) {
            NSLog("[Casberi] widgetFlow| in=%@ out=%@ weights=%.2f/%.2f priced=%d of %d note=%@",
                  band.inUSD.map { String(format: "%.2f", $0) } ?? "withheld",
                  band.outUSD.map { String(format: "%.2f", $0) } ?? "withheld",
                  band.inWeight, band.outWeight, band.priced, band.total,
                  band.owesDisclosure ? "OWED" : "(complete)")
        } else {
            NSLog("[Casberi] widgetFlow| none — nothing priced this week, or fewer than two lanes survived")
        }
    }
    #endif
}
