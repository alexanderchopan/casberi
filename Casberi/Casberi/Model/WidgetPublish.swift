import Foundation
import SwiftData
import WidgetKit
import SwiftUI

/// Fills the app group the widgets read from (2026-08-14, prd §382): Home's
/// balance (§1881, published by Home), your newest notes, today's Feed as
/// Home's Activity rows and the Watchlist (§1881).
///
/// Everything here already existed as a reading the app computes anyway —
/// the figures Home prints, the Watchlist's prices — and was simply never
/// handed across the process boundary. So this
/// adds no computation of its own; it is a publication step, not a feature
/// that runs work.
///
/// The Today widget, the kept-ask widget and their payloads went with the ask
/// (2026-10-01). What they left in the app group is cleared here, once per
/// pass, until it is gone (`retiredKeys`).
@MainActor
enum WidgetPublish {

    /// Publishes every payload and reloads the wallet's timeline only when its
    /// bytes actually changed.
    ///
    /// `things` is the caller's OWN corpus slice — the newest-600 the foreground
    /// pass already paid for. Reusing it rather than fetching again is cheaper.
    static func publishAll(things: [Thing], context: ModelContext) {
        // The §217 demo doctrine: nothing the demo composes reaches a widget.
        guard !DemoMode.isActive else { return }
        guard let group = UserDefaults(suiteName: SharedStore.appGroup) else { return }
        let things = things.live
        // The Wallet tile is Home's own figures, published by Home as it
        // draws them (`home(_:)`, prd §1881), never re-derived here.
        watchlist(group)

        if WidgetPayload.write(notes(context: context), key: WidgetNotes.key,
                               stampKey: WidgetNotes.stampKey, defaults: group) {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetNotes.kind)
        }
        let today = feed(things: things)
        drawMarks(for: today.rows.map(\.source))
        if WidgetPayload.write(today, key: WidgetFeedTile.key,
                               stampKey: WidgetFeedTile.stampKey, defaults: group) {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetFeedTile.kind)
        }

        sweepRetired(group)
    }

    /// The payloads of widgets that no longer exist: the hero (§877), the
    /// Today and kept-ask tiles with the pictures the Today rows led with
    /// (2026-10-01), the Category widget (§1210) — plus the brief's request
    /// flag. Cleared rather than left in the app group forever; a no-op once
    /// they are gone.
    static let retiredKeys = ["widget.lede", "widget.ledeAt", "widget.themes", "widget.themesAt",
                              "widget.dayLead", "widget.dayLeadAt",
                              "widget.asks", "widget.asksAt",
                              "widget.deadlines", "widget.deadlinesAt",
                              "widget.safe", "widget.safeAt",
                              "widget.requests", "widget.requestsAt",
                              "widget.people", "widget.peopleAt",
                              // The Category widget's shelves (§1210).
                              "widget.shelves", "widget.shelvesAt",
                              // The Watchlist widget, gone with Markets (§1529);
                              // it came back on `widget.watch` (§1881).
                              "widget.watchlist", "widget.watchlistAt",
                              // The wallet's line and week's flow, and the
                              // Feed's counts, replaced by Home's figures and
                              // Activity's rows (§1881).
                              "widget.wallet", "widget.walletAt", "widget.flow", "widget.flowAt",
                              "widget.feed", "widget.feedAt",
                              // The Daily Brief quick action's and the brief
                              // control's flag, left by an older build.
                              "brief.request"]
    static let retiredImageFolder = "WidgetLeads"

    private static func sweepRetired(_ group: UserDefaults) {
        for key in retiredKeys where group.object(forKey: key) != nil {
            group.removeObject(forKey: key)
        }
        if let dir = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroup)?
            .appendingPathComponent(retiredImageFolder, isDirectory: true),
           FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    /// The Notes widget's shelf (prd §1210): your two newest notes.
    ///
    /// Notes reads its own fetch — the room's `source == "You"` — because a
    /// note from March is still the newest note, and the newest-600 slice of a
    /// busy corpus has long since dropped it.
    static func notes(context: ModelContext) -> WidgetShelf {
        var d = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "You" },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        d.fetchLimit = 400
        let notes = ((try? context.fetch(d)) ?? []).live
            .filter(Pinboard.inRoom)
            .sorted { $0.capturedAt > $1.capturedAt }
        return WidgetShelf(room: Pinboard.room, name: String(localized: "Notes"),
                           glyph: "note.text", rows: rows(notes, stamp: { $0.capturedAt }))
    }

    /// The Feed tile's rows (prd §1881, after §1864): each app's newest thing
    /// today, newest first, as Home's Activity draws it, and how many more
    /// came. Over the caller's newest-600 slice, the slice the Feed's day
    /// reads. No money (§1208 item 7): the Wallet and Markets are
    /// left out, so Hide balances (§374) has nothing to withhold here; a thing
    /// with no category (a note of yours) is the Notes tile's.
    static func feed(things: [Thing], now: Date = .now) -> WidgetFeed {
        let calendar = Calendar.current
        let money: Set<String> = ["Wallet", "Markets"]
        var items: [WidgetFeed.Row] = []
        for thing in things where calendar.isDate(thing.capturedAt, inSameDayAs: now) {
            guard let category = BridgeCatalog.category(forSource: thing.source),
                  !money.contains(category) else { continue }
            let words = thing.title.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard !words.isEmpty else { continue }
            items.append(WidgetFeed.Row(id: thing.id.uuidString, source: thing.source,
                                        title: String(words.prefix(140)), at: thing.capturedAt))
        }
        let cut = WidgetFeedTile.rows(items)
        return WidgetFeed(day: calendar.startOfDay(for: now), rows: cut.rows, more: cut.more)
    }

    private static func rows(_ things: [Thing], stamp: (Thing) -> Date) -> [WidgetShelf.Row] {
        things.prefix(WidgetNotes.rowCap).map { thing in
            let words = thing.title.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return WidgetShelf.Row(id: thing.id.uuidString,
                                   title: String((words.isEmpty ? thing.source : words).prefix(140)),
                                   source: thing.source, at: stamp(thing))
        }
    }

    /// Draws each app's icon, as the app draws it (`BridgeIcon`), into the app
    /// group for the Feed tile, which cannot see the app's asset catalogue.
    /// Once a week per app, so an icon that changed is drawn again.
    static func drawMarks(for sources: [String]) {
        guard let dir = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroup)?
            .appendingPathComponent(WidgetFeedTile.marksFolder, isDirectory: true) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for source in Set(sources) {
            let file = dir.appendingPathComponent(WidgetFeedTile.markFile(source))
            let made = (try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate]) as? Date
            if let made, Date().timeIntervalSince(made) < 7 * 86_400 { continue }
            let renderer = ImageRenderer(content: BridgeIcon(name: source, size: DS.Mark.hero))
            renderer.scale = 2
            guard let data = renderer.uiImage?.pngData() else { continue }
            try? data.write(to: file, options: .atomic)
        }
    }

    /// Home's balance for the Wallet tile (prd §1881), handed over by Home
    /// from the figures it draws (`FeedScreen.homeWidgetFigures`), so the tile
    /// and Home can never state two totals. Reloads only on a change.
    static func home(_ figures: WidgetWalletHome?) {
        // No wallet tile on the Mac (prd §1893).
        #if targetEnvironment(macCatalyst)
        return
        #else
        guard !DemoMode.isActive, let figures,
              let group = UserDefaults(suiteName: SharedStore.appGroup) else { return }
        if WidgetPayload.write(figures, key: WidgetWallet.key,
                               stampKey: WidgetWallet.stampKey, defaults: group) {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetWallet.kind)
        }
        #endif
    }

    /// Your first four watched tokens and the day's move of each (prd §1881),
    /// read off what Home's Watchlist row reads. Called on every foreground
    /// and again when the prices land (`WatchlistPrices.refreshIfStale`).
    static func watchlist(_ group: UserDefaults? = UserDefaults(suiteName: SharedStore.appGroup)) {
        // No Watchlist tile on the Mac (prd §1893).
        #if targetEnvironment(macCatalyst)
        let mac = true
        #else
        let mac = false
        #endif
        guard !mac, !DemoMode.isActive, let group else { return }
        // Prices live in memory: before this launch has read them, publishing
        // would blank every move the tile already holds.
        guard WatchlistPrices.shared.readAt != nil || Watchlist.shared.tokens.isEmpty else { return }
        let quotes = WatchlistPrices.shared.quotes
        let rows = Watchlist.shared.tokens.prefix(WidgetWatchlist.rowCap).map {
            WidgetWatch.Row(symbol: $0.symbol.uppercased(), dayPct: quotes[$0.id]?.change)
        }
        if WidgetPayload.write(WidgetWatch(rows: Array(rows)), key: WidgetWatchlist.key,
                               stampKey: WidgetWatchlist.stampKey, defaults: group) {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetWatchlist.kind)
        }
    }

    #if DEBUG
    /// `-widgetProbe YES` — what the wallet widget would draw this launch, one
    /// NSLog per line, read back through the SAME reader the widget uses, so
    /// it tests the round trip rather than the gather.
    static func probe(context: ModelContext) {
        let group = UserDefaults(suiteName: SharedStore.appGroup)
        // The same slice the foreground pass hands `publishAll`, so the probe
        // measures what production measures rather than a different corpus.
        var d = FetchDescriptor<Thing>(sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        d.fetchLimit = 600
        let things = Corpus.surfaced((try? context.fetch(d)) ?? [])
        publishAll(things: things, context: context)

        if let home = WidgetWallet.published(defaults: group) {
            let age = Date.now.timeIntervalSince(home.asOf) / 3600
            NSLog("[Casberi] widgetWallet| total=%@ day=%@ public=%@ private=%@ hidden=%@ age=%.1fh",
                  home.total.map { String(format: "%.2f", $0) } ?? "withheld",
                  home.dayPct.map { String(format: "%+.2f%%", $0) } ?? "unknown",
                  home.publicUSD.map { String(format: "%.2f", $0) } ?? "none",
                  home.privateUSD.map { String(format: "%.2f", $0) } ?? "none",
                  home.hidden ? "YES" : "no", age)
        } else {
            NSLog("[Casberi] widgetWallet| none — Home has not drawn a balance on All")
        }
        if let watch = WidgetWatchlist.published(defaults: group) {
            NSLog("[Casberi] widgetWatchlist| rows=%d", watch.rows.count)
            for row in watch.rows {
                NSLog("[Casberi] widgetWatchlist| %@ %@", row.symbol,
                      row.dayPct.map { String(format: "%+.2f%%", $0) } ?? "unread")
            }
        } else {
            NSLog("[Casberi] widgetWatchlist| none")
        }

        if let shelf = WidgetNotes.published(defaults: group) {
            NSLog("[Casberi] widgetNotes| rows=%d newest=%@",
                  shelf.rows.count, shelf.rows.first?.title ?? "none")
        } else {
            NSLog("[Casberi] widgetNotes| none")
        }
        if let feed = WidgetFeedTile.published(defaults: group) {
            NSLog("[Casberi] widgetFeed| current=%@ rows=%d more=%d",
                  feed.isCurrent() ? "YES" : "no", feed.rows.count, feed.more)
            for row in feed.rows {
                NSLog("[Casberi] widgetFeed| %@ | %@ | mark=%@", row.source, row.title,
                      FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroup)
                        .map { FileManager.default.fileExists(atPath: $0.appendingPathComponent(WidgetFeedTile.marksFolder)
                            .appendingPathComponent(WidgetFeedTile.markFile(row.source)).path) } == true ? "YES" : "no")
            }
        } else {
            NSLog("[Casberi] widgetFeed| none")
        }
    }
    #endif
}
