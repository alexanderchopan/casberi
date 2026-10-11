import Foundation
import SwiftData
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif

/// Pins one followed row's price to the Lock Screen, moves it whenever the
/// app reads that price, and takes it down (prd §1250; the rules are
/// `PriceLive`'s, the view `CasberiWidgets/PriceActivity.swift`).
///
/// `MoneyActivityDriver`'s shape: the whole ActivityKit surface behind one
/// `#if`, empty on Mac Catalyst, no permission spent (Live Activities are a
/// Settings switch). The ONE activity is whatever ActivityKit holds
/// (`Activity.activities`), never a copy kept here, so a relaunch finds the
/// pin it left.
@MainActor
enum PriceActivityDriver {

    enum PinResult {
        case pinned
        /// Live Activities are switched off for Casberi.
        case off
        /// The row has no price read yet: nothing honest to pin.
        case unread
    }

    #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
    private static var current: Activity<PriceActivityAttributes>? {
        Activity<PriceActivityAttributes>.activities.first
    }

    static var available: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    static var isPinned: Bool { current != nil }
    static var pinnedRef: String? { current?.attributes.ref }

    /// Pins a row, replacing whatever was pinned. Every value is read off the
    /// row before the first wait.
    static func pin(_ thing: Thing) async -> PinResult {
        guard available else { return .off }
        guard thing.isLive, let ref = thing.sourceRef,
              let reading = PriceAlertStore.reading(for: thing) else { return .unread }
        let attributes = PriceActivityAttributes(
            ref: ref,
            symbol: StockWatch.symbol(of: thing) ?? thing.authorHandle ?? TokensAsk.symbol(of: thing.title),
            name: TokensAsk.name(of: thing.title),
            thingID: thing.id.uuidString,
            pinnedAt: .now)
        let state = PriceActivityAttributes.ContentState(
            price: reading.price, change: reading.change,
            closes: line(ref: ref, isStock: StockWatch.symbol(of: thing) != nil),
            at: reading.at)
        await unpin()
        let activity = try? Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: PriceLive.staleDate(at: reading.at)))
        return activity == nil ? .off : .pinned
    }

    /// Takes the pinned price down.
    static func unpin() async {
        for activity in Activity<PriceActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Brings the pinned price up to the newest read (called after the
    /// foreground pulse and the background check). Ends it past its lifetime,
    /// or when the row is no longer followed. Only values cross the waits.
    static func sync(context: ModelContext) async {
        guard let activity = current else { return }
        let attributes = activity.attributes
        if PriceLive.expired(pinnedAt: attributes.pinnedAt, now: .now) {
            await activity.end(nil, dismissalPolicy: .immediate)
            return
        }
        let ref = attributes.ref
        let source = TokenWatch.source
        var d = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == source && $0.sourceRef == ref })
        d.fetchLimit = 1
        guard let thing = (try? context.fetch(d))?.first, thing.isLive else {
            await activity.end(nil, dismissalPolicy: .immediate)
            return
        }
        let symbol = StockWatch.symbol(of: thing)
        let title = thing.title
        if let symbol {
            // A stock's price is Nasdaq's quote, held ten minutes; read it if
            // it is older (the alert check reads it only when one is set).
            await CompanyQuotes.shared.load([CompanyPacks.Company(name: title, listing: .stock(symbol),
                                                                   seats: [TokenWatch.source])])
        }
        let read: (price: Double, change: Double?, at: Date)?
        if let symbol {
            read = CompanyQuotes.shared.quote(.stock(symbol)).map { (price: $0.price, change: $0.change, at: $0.at) }
        } else {
            read = TokenPulse.shared.pulses[ref].map { (price: $0.price, change: $0.change24h, at: $0.fetchedAt) }
        }
        guard let read, PriceLive.advances(shown: activity.content.state.at, read: read.at) else { return }
        let state = PriceActivityAttributes.ContentState(
            price: read.price, change: read.change,
            closes: line(ref: ref, isStock: symbol != nil), at: read.at)
        await activity.update(.init(state: state, staleDate: PriceLive.staleDate(at: read.at)))
    }

    /// The day's line for the activity, thinned as the widget's.
    private static func line(ref: String, isStock: Bool) -> [Double]? {
        let closes = isStock ? TokenPulse.shared.stockLines[ref]?.closes : TokenPulse.shared.pulses[ref]?.closes
        return closes.flatMap(WidgetWatch.sparkCloses)
    }
    #else
    static var available: Bool { false }
    static var isPinned: Bool { false }
    static var pinnedRef: String? { nil }
    static func pin(_ thing: Thing) async -> PinResult { .off }
    static func unpin() async {}
    static func sync(context: ModelContext) async {}
    #endif
}
