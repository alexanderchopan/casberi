import Foundation
import SwiftData

/// Day's Needs you, read (prd §1327 item 9): the app half of `DayNeeds`.
///
/// Each place's list is read off the SAME rows that place's own page reads —
/// its merged room's members, newest first, `FeedScreen.sourceRoomFetchLimit`
/// of them — so a row Day lists is a row the place lists. The read runs on a
/// context of its own off the main actor (Work's object keys read `content`,
/// the heavy column), returning values only; Day's `.task` resolves the few
/// ids it keeps on the main context.
enum DayNeedsSource {

    /// A Wallet row's values, as `WalletNeedsYou.waiting` reads them.
    struct WalletRow: Sendable {
        let id: UUID
        let source: String
        let ref: String?
        let tags: [String]
        let at: Date
        let holder: String?
    }

    struct Read: Sendable {
        var wallet: [WalletRow] = []
        var work: [DayNeeds.Item] = []
    }

    /// The candidates, off the main actor. `wallet` and `work` are each room's
    /// members (`RoomAccounts.roomSources`), resolved by the caller.
    static func read(container: ModelContainer, wallet: [String], work: [String],
                     workPlace: String, limit: Int, now: Date) async -> Read {
        await Task.detached(priority: .utility) { () -> Read in
            let context = ModelContext(container)
            var out = Read()

            var w = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { wallet.contains($0.source) },
                                           sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
            w.fetchLimit = limit
            for thing in (try? context.fetch(w)) ?? [] where thing.sourceRef != nil {
                out.wallet.append(WalletRow(id: thing.id, source: thing.source, ref: thing.sourceRef,
                                            tags: thing.tags, at: thing.capturedAt,
                                            holder: thing.walletAddress))
            }

            var k = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { work.contains($0.source) },
                                           sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
            k.fetchLimit = limit
            let rows = ((try? context.fetch(k)) ?? []).map { thing in
                DayNeeds.WorkRow(id: thing.id, at: thing.capturedAt,
                                 key: ObjectFold.key(room: .work, source: thing.source, link: thing.content),
                                 row: WorkStage.Row(thing))
            }
            out.work = DayNeeds.workAsks(rows, place: workPlace, now: now)
            return out
        }.value
    }

    /// The Wallet's Needs you over the read rows, through the Wallet's own
    /// rule. The zFi book is read only when a reclaim row is among them, over
    /// those rows' holders, and a book that cannot be read counts as the
    /// Wallet's empty one does: nothing waiting.
    static func walletItems(_ rows: [WalletRow], safePending: Set<String>, place: String,
                            now: Date) async -> [DayNeeds.Item] {
        let holders = Set(rows.filter { WalletNeedsYou.readsBook(ref: $0.ref) }.compactMap(\.holder))
        let zfi = holders.isEmpty ? ZFiOrders.Book()
            : (await ZFiOrders.book(addresses: holders.sorted()) ?? ZFiOrders.Book())
        return rows
            .filter {
                WalletNeedsYou.waiting(source: $0.source, ref: $0.ref, tags: $0.tags, capturedAt: $0.at,
                                       safePending: safePending, zfi: zfi, now: now)
            }
            .sorted { $0.at > $1.at }
            .map { DayNeeds.Item(id: $0.id, place: place, at: $0.at) }
    }
}
