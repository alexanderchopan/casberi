import Foundation
import SwiftData
import WidgetKit

/// Fills the app group the widgets read from (2026-08-14, prd §382): the
/// wallet's line and flow, and the Category widget's shelves (2026-10-04).
///
/// Everything here already existed as a reading the app computes on every
/// foreground anyway — the wallet series the balance card draws, the week's
/// flow — and was simply never handed across the process boundary. So this
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
        var stale = false

        if WidgetPayload.write(flow(things: things), key: WidgetWallet.flowKey,
                               stampKey: WidgetWallet.flowStampKey, defaults: group) {
            stale = true
        }
        if WidgetPayload.write(wallet(), key: WidgetWallet.key,
                               stampKey: WidgetWallet.stampKey, defaults: group) {
            stale = true
        }

        // The accent every tile draws with is NOT written here — `ThemeStore`
        // already publishes it to the same app group on init, and a second
        // writer for one key is how the two spellings of a colour start
        // disagreeing about which is current.

        if stale { WidgetCenter.shared.reloadTimelines(ofKind: WidgetWallet.kind) }

        if WidgetPayload.write(shelves(things: things, context: context), key: WidgetShelves.key,
                               stampKey: WidgetShelves.stampKey, defaults: group) {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetShelves.kind)
        }

        sweepRetired(group)
    }

    /// The payloads of widgets that no longer exist: the hero (§877), and the
    /// Today and kept-ask tiles with the pictures the Today rows led with
    /// (2026-10-01) — plus the brief's request flag. Cleared rather than left
    /// in the app group forever; a no-op once they are gone.
    static let retiredKeys = ["widget.lede", "widget.ledeAt", "widget.themes", "widget.themesAt",
                              "widget.dayLead", "widget.dayLeadAt",
                              "widget.asks", "widget.asksAt",
                              "widget.deadlines", "widget.deadlinesAt",
                              "widget.safe", "widget.safeAt",
                              "widget.requests", "widget.requestsAt",
                              "widget.people", "widget.peopleAt",
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

    /// The Category widget's shelves (2026-10-04): Notes first, always, then
    /// every catalog category with something in it, in the tray's order.
    ///
    /// Notes reads its own fetch — the room's `pinnedAt != nil || source ==
    /// "You"` — because a note from March is still the newest note, and the
    /// newest-600 slice of a busy corpus has long since dropped it. The
    /// categories read the slice, where their newest rows always are.
    ///
    /// Hide wallet balances (§374) takes the money categories off the Home
    /// Screen whole: a row's title is where a transfer says how much.
    static func shelves(things: [Thing], context: ModelContext) -> [WidgetShelf] {
        var d = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.pinnedAt != nil || $0.source == "You" },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        d.fetchLimit = 400
        let notes = ((try? context.fetch(d)) ?? []).live
            .filter(Pinboard.inRoom)
            .sorted { Pinboard.stamp($0) > Pinboard.stamp($1) }
        var out = [WidgetShelf(room: Pinboard.room, name: String(localized: "Notes"),
                               glyph: "note.text", rows: rows(notes, stamp: Pinboard.stamp))]

        let money: Set<String> = ["Wallet", "Markets", "Testnets"]
        let hidden = BalancePrivacy.shared.hidden
        var byCategory: [String: [Thing]] = [:]
        for thing in things {
            guard let category = BridgeCatalog.category(forSource: thing.source) else { continue }
            if byCategory[category, default: []].count < WidgetShelves.rowCap {
                byCategory[category, default: []].append(thing)
            }
        }
        for category in BridgeCatalog.categories.map(\.name) {
            guard !(hidden && money.contains(category)),
                  let members = byCategory[category], !members.isEmpty else { continue }
            out.append(WidgetShelf(room: category, name: category,
                                   glyph: CategoryFold.glyph(for: category),
                                   rows: rows(members, stamp: \.capturedAt)))
        }
        return out
    }

    private static func rows(_ things: [Thing], stamp: (Thing) -> Date) -> [WidgetShelf.Row] {
        things.prefix(WidgetShelves.rowCap).map { thing in
            let words = thing.title.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return WidgetShelf.Row(id: thing.id.uuidString,
                                   title: String((words.isEmpty ? thing.source : words).prefix(140)),
                                   source: thing.source, at: stamp(thing))
        }
    }

    /// The week's money in against money out.
    ///
    /// Reads `WalletFlowSource.band`, the wallet room's own reading.
    ///
    /// **Nothing is gated here**: `WalletFlow.band` already declines on an
    /// unpriceable window, on fewer than two lanes, and on lanes too thin to
    /// draw honestly. Re-deciding any of that would be a second opinion that
    /// could disagree with the room's.
    ///
    /// The LANES are dropped — the widget draws totals and a ratio, never
    /// counterparties (see `WidgetFlowBand`) — but their COUNTS are kept, because
    /// they are what says how much of the week is actually in the bars.
    static func flow(things: [Thing], now: Date = .now) -> WidgetFlowBand? {
        // `span` is a DURATION, not a date — passing it straight through would
        // silently ask for a window starting at 1970.
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

        for shelf in WidgetShelves.published(defaults: group) {
            NSLog("[Casberi] widgetShelf| %@ (%@) rows=%d newest=%@", shelf.name, shelf.room,
                  shelf.rows.count, shelf.rows.first?.title ?? "none")
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
