import SwiftUI
import SwiftData

// MARK: - Reading (prd §1049, built §1052; tiles §1085)

extension FeedScreen {
    /// The Reading room: the newest thing in the box (every room's rule), All ·
    /// Highlights · Subscriptions · Search under it, the menu, then the days.
    /// Subscriptions draws its own box and list: every feed you follow, with
    /// Track a subscription first (prd §1118).
    ///
    /// Highlights is every passage you kept, from any app: Readwise's and
    /// Kindle's rows in the room, and the ones you kept yourself from a
    /// reading body (`keptHighlights`, notes of yours outside the room's
    /// query). Its box is the newest passage, by the same rule.
    @ViewBuilder
    func readingRoomSections(_ visible: [Thing], nextEventID: UUID?, heroShown: Bool) -> some View {
        let highlights = chrome.readingScope == .highlights
        let subscriptions = chrome.readingScope == .subscriptions
        // One article saved in several apps stands once, at its newest save
        // (prd §1079, `objectFolded`).
        let rows: [Thing] = highlights ? readingHighlights(visible) : objectFolded(visible)
        let days = chronoDays(rows)
        let cover: Thing? = {
            guard !heroShown else { return nil }
            if highlights { return rows.first { $0.isLive } }
            guard let id = ledeThingID(in: days) else { return nil }
            return rows.first { $0.isLive && $0.id == id }
        }()
        if subscriptions {
            Section { followingBox(.reading) }
        } else if let cover {
            Section { ledeListRow(cover) }
        } else if !heroShown {
            Section {
                if highlights {
                    emptyLeadRow(headline: DSProse.text("No highlights yet"),
                                 words: Text("Passages you keep land here"))
                } else {
                    emptyLeadRow(headline: DSProse.text("Nothing yet"),
                                 words: Text("What you read and save lands here"))
                }
            }
        }
        Section {
            DSScopeTiles(sections: ReadingScope.allCases, active: chrome.readingScope,
                         attention: []) { picked in
                withAnimation(DS.Motion.standard) { chrome.readingScope = picked }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.inset,
                                      bottom: DSRoomChassis.leadGap,
                                      trailing: DSRoomChassis.inset))
            .task(id: chrome.readingScope) {
                if chrome.readingScope == .highlights { loadKeptHighlights() }
                #if DEBUG
                readingProbe()
                #endif
            }
        }
        roomScopeSection
        if subscriptions {
            followingSections(.reading)
        } else {
            groupedSections(liftingCover(days, id: cover?.id), nextEventID: nextEventID,
                            boundary: highlights ? nil : boundaryThingID(in: days))
        }
    }

    /// Every highlight the room can show, newest first: Readwise's and
    /// Kindle's rows (narrowed by the menu with the rest of `visible`), and
    /// the passages you kept yourself unless an app is picked.
    private func readingHighlights(_ visible: [Thing]) -> [Thing] {
        let fromApps = visible.filter {
            $0.isLive && ReadingRoom.isHighlight(source: $0.source, kind: $0.kind.rawValue,
                                                 sourceRef: $0.sourceRef)
        }
        let kept = selectedSeat == nil ? keptHighlights.filter(\.isLive) : []
        return (fromApps + kept).sorted { $0.capturedAt > $1.capturedAt }
    }

    /// The passages kept from a reading body: notes of yours whose ref names
    /// their origin. Fetched when the tile is picked, never in a body (§628).
    private func loadKeptHighlights() {
        let you = NoteSheetSource.keptSource
        var d = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.source == you },
                                       sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        d.fetchLimit = 500
        keptHighlights = ((try? modelContext.fetch(d)) ?? []).filter(Highlight.isHighlight)
    }

    #if DEBUG
    /// `-readingScope highlights|subscriptions|follow` — land on a tile, or
    /// raise Follow (Subscriptions' first row, §1118), at mount (prd §1085;
    /// NSLogs `readingScope:`). Once per launch.
    private func readingProbe() {
        guard !Self.readingProbed,
              let raw = UserDefaults.standard.string(forKey: "readingScope") else { return }
        Self.readingProbed = true
        NSLog("[Casberi] readingScope: %@", raw)
        if raw == "follow" {
            chrome.readingScope = .subscriptions
            feedSheet = .followingAdd(.reading)
            return
        }
        guard let scope = ReadingScope(rawValue: raw) else { return }
        chrome.readingScope = scope
    }
    #endif
}
