import SwiftUI
import SwiftData

// NEEDS YOU STAYS IN EACH PLACE, AND DAY GATHERS THEM ALL (prd §1327 item 9,
// user: "we DO need to leave 'needs you' in wallet … so they'd see it twice
// anyways"). The Wallet's Home keeps its stuck transfer and price rise, Work's
// Coming up its asks; Day leads its list with every one, each row naming the
// place it came from, opening what it opens there. Empty, nothing is drawn.
// The Day tab wears no badge (user: "day tab does not wear a badge!").
extension FeedScreen {

    /// What Day's read is keyed on: any change to the corpus, on Day's own
    /// page only. Everywhere else `.idle`, so the task does nothing there.
    var dayNeedsKey: Corpus.Revision {
        guard source == RoomAccounts.dayRoom else { return .idle }
        return Corpus.revision(in: modelContext)
    }

    /// Every place's Needs you, read off the rows each place reads, through
    /// each place's own rule (`WalletNeedsYou`, `WorkAsk`), gathered newest
    /// first (`DayNeeds.gather`). Runs from Day's `.task`, never a body.
    @MainActor
    func loadDayNeeds() async {
        guard source == RoomAccounts.dayRoom else {
            if !dayNeedsItems.isEmpty { dayNeedsItems = []; dayNeeds = [] }
            return
        }
        let now = Date.now
        let wallet = CategoryFold.walletRoom, work = RoomAccounts.workRoom
        let read = await DayNeedsSource.read(container: modelContext.container,
                                             wallet: RoomAccounts.roomSources(wallet),
                                             work: RoomAccounts.roomSources(work),
                                             workPlace: work, limit: Self.sourceRoomFetchLimit, now: now)
        guard !Task.isCancelled else { return }
        let safe = Set(SafeBridge.pendingSnapshot().map(\.ref))
        let walletItems = await DayNeedsSource.walletItems(read.wallet, safePending: safe,
                                                           place: wallet, now: now)
        guard !Task.isCancelled else { return }
        let items = DayNeeds.gather([walletItems, read.work])
        guard items != dayNeedsItems else { return }
        let ids = items.map(\.id)
        let found = ids.isEmpty ? []
            : ((try? modelContext.fetch(FetchDescriptor<Thing>(
                predicate: #Predicate<Thing> { ids.contains($0.id) }))) ?? [])
        let byID = Dictionary(found.live.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let things = items.compactMap { byID[$0.id] }
        dayNeedsItems = items.filter { byID[$0.id] != nil }
        dayNeeds = things
        #if DEBUG
        // `dayNeeds|` — what Day gathered, per place, for a check that
        // cannot scroll.
        NSLog("[Casberi] dayNeeds| wallet=%d work=%d shown=%d",
              walletItems.count, read.work.count, things.count)
        #endif
    }

    /// The section: "Needs you", named by what it is rather than a time
    /// (prd §740), in the day sections' own anatomy, each row the Feed's
    /// grouped row with its place first on the app's line.
    @ViewBuilder
    func dayNeedsSection(nextEventID: UUID?) -> some View {
        let places = Dictionary(dayNeedsItems.map { ($0.id, $0.place) }, uniquingKeysWith: { a, _ in a })
        let rows = dayNeeds.live
        if !rows.isEmpty {
            daySection(Self.needsYouGroup, rows, nextEventID: nextEventID,
                       dated: false, places: places)
        }
    }
}
