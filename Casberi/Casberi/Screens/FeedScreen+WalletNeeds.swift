import SwiftUI
import SwiftData

// **NEEDS YOU LIVES IN ITS PLACE (prd §1413, user: "what if we got rid of
// 'needs you - work' bc so many things could fit there, and we put a few of
// the 'needs you - wallet' in the 'wallet' feed … that way we aren't
// conflating needs you w/ day").** Day is dated rows and gathers nothing
// (§1327 item 9's gather, `DayNeeds`, is deleted). Work's section draws its
// own asks, as it always did (`WorkAsk`, prd §1080). The Feed's Wallet
// section leads with the Wallet's: three on the first page under "Needs
// you", outside its five, then its moves, never repeating them. The Wallet's
// Home keeps its own Needs you. Day wears no badge.
extension FeedScreen {

    /// What the Feed's own reads are keyed on (Day's rows, Notes' rows, the
    /// Wallet's Needs you): any change to the corpus, on the Feed. Everywhere
    /// else `.idle`, so the task does nothing there.
    var feedSectionsKey: Corpus.Revision {
        guard source == "All" else { return .idle }
        return Corpus.revision(in: modelContext)
    }

    /// How many of the Wallet's asks lead its section on the first page.
    static let walletNeedsFirstRows = 3

    /// The Wallet's Needs you, read off the rows its Home reads, through the
    /// Wallet's own rule (`WalletNeedsYou`), newest first. Runs from the
    /// screen's `.task`, never a body (§628).
    @MainActor
    func loadWalletNeeds() async {
        guard source == "All" else {
            if !walletNeeds.isEmpty { walletNeeds = [] }
            return
        }
        let now = Date.now
        let rows = await WalletNeedsSource.read(container: modelContext.container,
                                                wallet: RoomAccounts.roomSources(CategoryFold.walletRoom),
                                                limit: Self.sourceRoomFetchLimit)
        guard !Task.isCancelled else { return }
        let safe = Set(SafeBridge.pendingSnapshot().map(\.ref))
        let ids = await WalletNeedsSource.waiting(rows, safePending: safe, now: now)
        guard !Task.isCancelled else { return }
        guard ids != walletNeeds.live.map(\.id) else { return }
        let found = ids.isEmpty ? []
            : ((try? modelContext.fetch(FetchDescriptor<Thing>(
                predicate: #Predicate<Thing> { ids.contains($0.id) }))) ?? [])
        let byID = Dictionary(found.live.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        walletNeeds = ids.compactMap { byID[$0] }
        #if DEBUG
        // `walletNeeds|` — what the Feed's Wallet section leads with, for a
        // check that cannot scroll.
        NSLog("[Casberi] walletNeeds| waiting=%d shown=%d", ids.count, walletNeeds.count)
        #endif
    }

    /// The rows the Wallet's section leads with: "Needs you" at the day
    /// header's rung (prd §1387, §1413), then each ask in the SAME row as
    /// the moves under it — one shape per section (prd §1413 item 7, user:
    /// "these are different sizes that is an error"), as the Wallet's Home
    /// draws them; the heading says it waits on you, so the row does not
    /// (prd §1378). Empty, nothing is drawn.
    @ViewBuilder
    func walletNeedsRows(nextEventID: UUID?, limit: Int) -> some View {
        let rows = Array(walletNeeds.live.prefix(limit))
        // Your account's outside key, while it has none (prd §1432).
        let nudge = OutsideKeyNudge.shown
        if !rows.isEmpty || nudge {
            DSGroupHeader(word: Self.needsYouGroup)
                .feedRowBackground()
            if nudge { OutsideKeyNudge().listRow }
            // Keyed by value, read live (`ThingRowKeying`, the liveness rule).
            ForEach(Array(keyed(rows).enumerated()), id: \.element.id) { i, item in
                if let thing = item.live {
                    shapedListRow(thing, index: i, nextEventID: nextEventID)
                        .environment(\.dsUnderNeedsYou, true)
                }
            }
        }
    }
}
