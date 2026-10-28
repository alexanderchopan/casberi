import Foundation
import SwiftData
import Testing
@testable import Casberi

/// NEWEST IS NEVER DAY-BOUND (prd §1399). The card read today's rows, so
/// past midnight it hid itself and Home was a box alone. Now it reads what
/// the box's fallback reads: the five newest things across the Feed's own
/// categories, whatever day they came from.
struct NewestCardTests {
    private static let elsewhere: Set<String> = [CategoryFold.walletRoom, RoomAccounts.testnetsRoom, HomeScope.markets]

    @MainActor
    private static func inserted(_ rows: [Thing]) throws -> (ModelContainer, [Thing]) {
        let container = try ModelContainer(
            for: Thing.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        for row in rows { container.mainContext.insert(row) }
        return (container, rows)
    }

    private static func thing(_ title: String, source: String = "You", daysAgo: Double) -> Thing {
        Thing(kind: .note, title: title, source: source, capturedAt: Date.now.addingTimeInterval(-daysAgo * 86_400))
    }

    /// Past midnight: nothing from today, and the card still holds last
    /// night's five, newest first.
    @Test @MainActor func yesterdaysThingsStandWhenTodayIsEmpty() throws {
        let (container, rows) = try Self.inserted((1...7).map { Self.thing("n\($0)", source: "App\($0)", daysAgo: Double($0)) })
        _ = container
        let newest = FeedScreen.newestThings(rows.shuffled(), lede: nil, elsewhere: Self.elsewhere)
        #expect(newest.map(\.title) == ["n1", "n2", "n3", "n4", "n5"])
    }

    /// The box's thing, the same news again, a Wallet move and anything
    /// dated ahead are left out; a thin day backfills from before it.
    @Test @MainActor func theStandingExclusionsHold() throws {
        let lede = Self.thing("Box — today", daysAgo: 0.1)
        let (container, rows) = try Self.inserted([
            lede,
            Self.thing("Box — again", daysAgo: 0.2),
            Self.thing("Ahead", daysAgo: -1),
            Self.thing("Move", source: "Coinbase", daysAgo: 0.3),
            Self.thing("today", source: "Mail", daysAgo: 0.4),
            Self.thing("yesterday", source: "Bluesky", daysAgo: 1.5),
        ])
        _ = container
        let newest = FeedScreen.newestThings(rows, lede: lede, elsewhere: Self.elsewhere)
        #expect(newest.map(\.title) == ["today", "yesterday"])
    }

    /// One thing per app (prd §1581): a busy app holds one slot, its newest,
    /// whatever order the things arrive in, and the slots it would have
    /// taken go to the next apps.
    @Test @MainActor func oneThingPerApp() throws {
        let (container, rows) = try Self.inserted(
            (1...6).map { Self.thing("x\($0)", source: "X", daysAgo: Double($0) / 10) }
            + [Self.thing("mail", source: "Mail", daysAgo: 1),
               Self.thing("mail older", source: "Mail", daysAgo: 1.2),
               Self.thing("sky", source: "Bluesky", daysAgo: 2),
               Self.thing("note", daysAgo: 3)])
        _ = container
        for order in [rows, rows.reversed(), rows.shuffled()] {
            let newest = FeedScreen.newestThings(order, lede: nil, elsewhere: Self.elsewhere)
            #expect(newest.map(\.title) == ["x1", "mail", "sky", "note"])
        }
    }

    /// A thing no store backs is never read (the dead-Thing rule).
    @Test @MainActor func aDeadThingIsSkipped() throws {
        let (container, rows) = try Self.inserted([Self.thing("live", daysAgo: 1)])
        _ = container
        let dead = Self.thing("dead", daysAgo: 0.5)
        let newest = FeedScreen.newestThings(rows + [dead], lede: nil, elsewhere: Self.elsewhere)
        #expect(newest.map(\.title) == ["live"])
    }
}
