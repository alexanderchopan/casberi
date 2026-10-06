import SwiftUI
import SwiftData

// MARK: - What you follow (prd §1118)

extension FeedScreen {
    /// The box of a room's Subscriptions (or Work's Watching) tile: the
    /// figure once something is followed, the empty state once the reading
    /// says nothing is, and nothing before it lands. It starts the reading on
    /// every refresh, after the two Subscriptions readings the doors join.
    @ViewBuilder
    func followingBox(_ room: Following.Room) -> some View {
        let reading = FollowingReading.shared
        let items = reading.items(for: room)
        Group {
            if items.isEmpty {
                if reading.read.contains(room) {
                    DSEmptyState(headline: DSProse.text("Nothing followed yet"),
                                 words: Text(verbatim: room.emptyWords),
                                 scale: .list(rows: 3))
                } else {
                    Color.clear
                }
            } else {
                FollowingFigure(room: room, items: items)
            }
        }
        .frame(maxWidth: .infinity, minHeight: DSRoomChassis.leadBox, maxHeight: DSRoomChassis.leadBox)
        .dsRoomHeadBlock()
        .task(id: followingKey(room)) {
            await ServiceLinks.shared.refresh(modelContext, seats: bridges.bridges.map(\.name))
            FollowingReading.shared.refresh(room, context: modelContext)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DSRoomChassis.inset,
                                  bottom: DSRoomChassis.leadGap, trailing: DSRoomChassis.inset))
    }

    /// What re-reads the tile: a refresh, or the follow lists changing.
    func followingKey(_ room: Following.Room) -> String {
        let lists: Int = switch room {
        case .reading: RSSStore.shared.feeds.count &+ FeedFollowStore.substack.entries.count &* 31
        case .media:   FeedFollowStore.youtube.entries.count &+ FeedFollowStore.podcasts.entries.count &* 31
                           &+ PinterestStore.shared.follows.count &* 961
        case .work:    GitHubWatchStore.shared.watches.count
                           &+ PackageStore.shared.watched.values.reduce(0) { $0 + $1.count } &* 31
                           &+ HuggingFaceStore.shared.authors.count &* 961 &+ RadicleStore.shared.repos.count &* 29_791
        }
        return "\(room.rawValue):\(chrome.refreshPulse):\(lists)"
    }

    /// The list: the verb first, then every thing followed, the busiest this
    /// month first. A row opens its sheet; a follow read from an account
    /// (Twitch) opens too, without Stop tracking.
    @ViewBuilder
    func followingSections(_ room: Following.Room) -> some View {
        let items = FollowingReading.shared.items(for: room)
        Section {
            DSDoorRow(icon: "plus", title: Text(verbatim: room.verb)) {
                feedSheet = .followingAdd(room)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.rowInset,
                                      bottom: 0, trailing: DSRoomChassis.rowInset))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            ForEach(items) { item in
                Button {
                    feedSheet = .following(item.id, room)
                } label: {
                    FollowingRow(room: room, item: item)
                        .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .dsHover()
                .listRowInsets(EdgeInsets(top: Self.rowAir, leading: DSRoomChassis.rowInset,
                                          bottom: Self.rowAir, trailing: DSRoomChassis.rowInset))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .task(id: "followingProbe:\(room.rawValue):\(items.count)") { followingProbe(room) }
    }

    /// The tray a room's verb raises. Reading's is its Follow tray, which
    /// lands the person back on the list it added to.
    @ViewBuilder
    func followingAddTray(_ room: Following.Room) -> some View {
        switch room {
        case .reading:
            ReadingFindSheet(mode: .follow) { _ in }
        case .media:
            FollowTrackTray(room: .media)
        case .work:
            FollowTrackTray(room: .work) {
                // GitHub keeps its own tray (§1030): one sheet at a time.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    watchOnGitHub()
                }
            }
        }
    }

    /// `-followingSheet add|<name>` — with a room's tile open, raise its verb's
    /// tray or one followed thing's sheet once the tile has read (DEBUG;
    /// NSLogs `followingSheet:`), because a `simctl` capture has no tap.
    func followingProbe(_ room: Following.Room) {
        #if DEBUG
        guard !Self.followingProbed, FollowingReading.shared.read.contains(room),
              let raw = UserDefaults.standard.string(forKey: "followingSheet"), !raw.isEmpty else { return }
        Self.followingProbed = true
        let items = FollowingReading.shared.items(for: room)
        NSLog("[Casberi] followingSheet: %@ (%@, %d: %@)", raw, room.rawValue, items.count,
              items.map(\.name).joined(separator: ", "))
        if raw == "add" {
            feedSheet = .followingAdd(room)
        } else if let item = items.first(where: { $0.name.localizedCaseInsensitiveCompare(raw) == .orderedSame }) {
            feedSheet = .following(item.id, room)
        }
        #endif
    }
}
