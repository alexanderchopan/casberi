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
        guard let group = UserDefaults(suiteName: SharedStore.appGroup) else { return }
        let things = things.live
        var stale: [String] = []

        if writeAsks(to: group) { stale.append(WidgetAsks.kind) }
        if WidgetPayload.write(dayLead(things: things), key: WidgetLede.leadKey,
                               stampKey: WidgetLede.leadStampKey, defaults: group) {
            stale.append(WidgetLede.kind)
        }
        if WidgetPayload.write(flow(things: things), key: WidgetWallet.flowKey,
                               stampKey: WidgetWallet.flowStampKey, defaults: group) {
            stale.append(WidgetWallet.kind)
        }
        if WidgetPayload.write(deadlines(context: context), key: WidgetDeadlines.key,
                               stampKey: WidgetDeadlines.stampKey, defaults: group) {
            stale.append(WidgetDeadlines.kind)
        }
        if WidgetPayload.write(wallet(), key: WidgetWallet.key,
                               stampKey: WidgetWallet.stampKey, defaults: group) {
            stale.append(WidgetWallet.kind)
        }

        // The accent every tile draws with is NOT written here — `ThemeStore`
        // already publishes it to the same app group on init, and a second
        // writer for one key is how the two spellings of a colour start
        // disagreeing about which is current.

        for kind in stale { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
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
    static func publishAsks() {
        guard let group = UserDefaults(suiteName: SharedStore.appGroup) else { return }
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

    // MARK: - What the hero leads with

    /// Which of the brief's modules the hero tile leads with today.
    ///
    /// The DECISION is `WidgetDayLead.kind` — pure, tested, and the only place
    /// the ranking lives. This function's whole job is to hand it three honest
    /// measurements. The thumbnails themselves are NOT published: the extension
    /// already reads the shared store, so it fetches those bytes itself, and
    /// publishing eight JPEGs into UserDefaults on every foreground to save it a
    /// read it is already making would be the worse half of both worlds.
    static func dayLead(things: [Thing], now: Date = .now) -> WidgetDayLead? {
        let dayStart = Calendar.current.startOfDay(for: now)
        let today = things.filter { $0.capturedAt >= dayStart }

        // Counted from fields already in hand — `previewImageData` is
        // deliberately NOT touched: it is external storage, so reading it
        // materializes real bytes off disk, and this only needs to know HOW
        // MANY. The widget fetches the bytes themselves, and only when the
        // pictures lead actually won.
        let pictures = today.reduce(into: 0) { count, thing in
            if thing.previewImageURL != nil || thing.kind == .screenshot { count += 1 }
        }

        // Money leads only on a move worth mentioning — the §83 flat rule,
        // reused so the tile can't lead with "the wallet did nothing".
        let line = wallet(now: now)
        let moneyMoved = (line?.changePct).map { !MoneyFormat.isFlatPercent($0) } ?? false

        var counts: [String: Int] = [:]
        for thing in today where Corpus.showsInAll(thing) {
            counts[thing.source, default: 0] += 1
        }
        let total = counts.values.reduce(0, +)
        let ranked = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        let cells = total > 0
            ? ranked.prefix(3).map { WidgetSourceCell(name: $0.key,
                                                      share: Double($0.value) / Double(total)) }
            : []

        let kind = WidgetDayLead.kind(pictures: pictures, moneyMoved: moneyMoved,
                                      sources: cells.count)
        guard kind != .none else { return nil }
        return WidgetDayLead(kind: kind, pictures: pictures, sources: Array(cells),
                             otherSources: max(0, ranked.count - cells.count))
    }

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
        let rows = dated.live
            .filter { thing in
                guard thing.mark != .done, let due = thing.dueAt else { return false }
                return due >= floor && due <= ceiling
            }
            .sorted { ($0.dueAt ?? now) < ($1.dueAt ?? now) }
            .prefix(WidgetDeadlines.publishCap)
            .map { WidgetDeadline(id: $0.id.uuidString, title: $0.title,
                                  source: $0.source, due: $0.dueAt ?? now) }
        return rows.isEmpty ? nil : Array(rows)
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
        NSLog("[Casberi] widgetProbe| lede=%@ themes=%d asks=%d",
              WidgetLede.current(defaults: group).map { "\"\($0)\"" } ?? "none",
              WidgetLede.themes(defaults: group)?.count ?? 0, asks.count)
        for cell in asks {
            NSLog("[Casberi] widgetAsk| kind=%@ changed=%@ reading=%@ title=\"%@\"",
                  cell.kind, cell.changed ? "YES" : "no",
                  cell.reading ?? "(none — question stands alone)", cell.title)
        }

        // Which module the hero leads with, and the three measurements that
        // decided it. An empty tile and a tile leading with the wrong module
        // look nothing alike, but "why did it pick THAT" has no other answer:
        // the ranking is a pure function of these three numbers.
        if let lead = WidgetLede.lead(defaults: group) {
            NSLog("[Casberi] widgetLead| kind=%@ pictures=%d sources=%d other=%d",
                  lead.kind.rawValue, lead.pictures, lead.sources.count, lead.otherSources)
            for cell in lead.sources {
                NSLog("[Casberi] widgetLeadCell| %@ share=%.2f", cell.name, cell.share)
            }
        } else {
            NSLog("[Casberi] widgetLead| none — under the picture floor, wallet flat, fewer than two sources")
        }

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
