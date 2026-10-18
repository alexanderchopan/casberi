import SwiftUI
import SwiftData

// NEEDS YOU STAYS IN EACH PLACE, AND DAY GATHERS THEM ALL (prd §1327 item 9,
// user: "we DO need to leave 'needs you' in wallet … so they'd see it twice
// anyways"). The Wallet's Home keeps its stuck transfer and price rise, Work's
// Coming up its asks; Day's section leads its rows with every one, under the
// place it came from, opening what it opens there. Empty, nothing is drawn.
// Day wears no badge (user: "day tab does not wear a badge!").
extension FeedScreen {

    /// What Day's read is keyed on: any change to the corpus, on the Feed,
    /// whose Day section holds it (prd §1343), and on Day's room on iPad and
    /// the Mac, which draws that section (prd §1344). Everywhere else
    /// `.idle`, so the task does nothing there.
    var dayNeedsKey: Corpus.Revision {
        guard source == RoomAccounts.dayRoom || source == "All" else { return .idle }
        return Corpus.revision(in: modelContext)
    }

    /// Every place's Needs you, read off the rows each place reads, through
    /// each place's own rule (`WalletNeedsYou`, `WorkAsk`), gathered newest
    /// first (`DayNeeds.gather`). Runs from the screen's `.task`, never a body.
    @MainActor
    func loadDayNeeds() async {
        guard source == RoomAccounts.dayRoom || source == "All" else {
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

    /// **A SECTION PER PLACE (prd §1340, user: "there should be section
    /// headers like lil cards or something for the different types of 'needs
    /// you' eg wallet work life").** Each place's rows under "Needs you ·
    /// Wallet", in Day's order, inside the Day section, which is itself the
    /// card (prd §1343); the rows are Day's rows, so the place stands once
    /// over them rather than on every row's line. Day's page and its card
    /// form are deleted (prd §1344).
    @ViewBuilder
    func dayNeedsRows(nextEventID: UUID?, limit: Int? = nil) -> some View {
        let all = dayNeeds.live
        let rows = limit.map { Array(all.prefix($0)) } ?? all
        let placeOf = Dictionary(dayNeedsItems.map { ($0.id, $0.place) }, uniquingKeysWith: { a, _ in a })
        let order = rows.reduce(into: [String]()) { order, thing in
            if let place = placeOf[thing.id], !order.contains(place) { order.append(place) }
        }
        ForEach(order, id: \.self) { place in
            let mine = rows.filter { placeOf[$0.id] == place }
            // THE PLACE IS THE ONE GROUP WORD (prd §1387, user: "keep the
            // per-place split, but as the one group header word"): "Needs
            // you · Wallet" at the rung "Today" and "Tuesday" wear, never a
            // grey eyebrow of its own (§1386's finding 3).
            DSGroupHeader(word: "\(Self.needsYouGroup) · \(place)")
                .feedRowBackground()
            // Keyed by value, read live (`ThingRowKeying`, the liveness rule).
            ForEach(Array(keyed(mine).enumerated()), id: \.element.id) { i, item in
                if let thing = item.live {
                    // ONE ROW (prd §1386, §744): the Feed's row, its app and
                    // time over the title as Newest's; the heading says it
                    // waits on you, so the row does not (prd §1378).
                    shapedListRow(thing, index: i, nextEventID: nextEventID,
                                  grouped: true, app: (source: thing.source, date: thing.capturedAt))
                        .environment(\.dsGroupedSource, thing.source)
                        .environment(\.dsUnderNeedsYou, true)
                }
            }
        }
    }
}
