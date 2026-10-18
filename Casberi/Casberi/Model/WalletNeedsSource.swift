import Foundation
import SwiftData

/// **THE WALLET'S NEEDS YOU, READ FOR THE FEED (prd §1413; was Day's
/// `DayNeedsSource`, prd §1327 item 9).** The Feed's Wallet section leads
/// with what waits on you in the Wallet, through the Wallet's own rule
/// (`WalletNeedsYou`), off the SAME rows its Home reads — its merged room's
/// members, newest first, `FeedScreen.sourceRoomFetchLimit` of them — so a
/// row the Feed lists is a row the Wallet lists (§837: two surfaces, one
/// store). The read runs on a context of its own off the main actor,
/// returning values only; the Feed's `.task` resolves the few ids it keeps on
/// the main context. Work's asks are not gathered anywhere: Work's section
/// draws its own (`WorkAsk`, prd §1080), and Day is dated rows.
enum WalletNeedsSource {

    /// A Wallet row's values, as `WalletNeedsYou.waiting` reads them.
    struct Row: Sendable {
        let id: UUID
        let source: String
        let ref: String?
        let tags: [String]
        let at: Date
        let holder: String?
    }

    /// The candidates, off the main actor. `wallet` is the room's members
    /// (`RoomAccounts.roomSources`), resolved by the caller.
    static func read(container: ModelContainer, wallet: [String], limit: Int) async -> [Row] {
        await Task.detached(priority: .utility) { () -> [Row] in
            let context = ModelContext(container)
            var w = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { wallet.contains($0.source) },
                                           sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
            w.fetchLimit = limit
            var out: [Row] = []
            for thing in (try? context.fetch(w)) ?? [] where thing.sourceRef != nil {
                out.append(Row(id: thing.id, source: thing.source, ref: thing.sourceRef,
                               tags: thing.tags, at: thing.capturedAt, holder: thing.walletAddress))
            }
            return out
        }.value
    }

    /// The ids that wait on you, newest first, through the Wallet's own rule.
    /// The zFi book is read only when a reclaim row is among them, over those
    /// rows' holders, and a book that cannot be read counts as the Wallet's
    /// empty one does: nothing waiting.
    static func waiting(_ rows: [Row], safePending: Set<String>, now: Date) async -> [UUID] {
        let holders = Set(rows.filter { WalletNeedsYou.readsBook(ref: $0.ref) }.compactMap(\.holder))
        let zfi = holders.isEmpty ? ZFiOrders.Book()
            : (await ZFiOrders.book(addresses: holders.sorted()) ?? ZFiOrders.Book())
        return rows
            .filter {
                WalletNeedsYou.waiting(source: $0.source, ref: $0.ref, tags: $0.tags, capturedAt: $0.at,
                                       safePending: safePending, zfi: zfi, now: now)
            }
            .sorted { $0.at > $1.at }
            .map(\.id)
    }
}
