import SwiftUI
import SwiftData

// The music rooms (prd §995): tiles, sections, and the name shelves, split out of
// FeedScreen.swift (prd §718). Nothing here changed but the file it lives
// in and, where another file reads a member, its access level.
extension FeedScreen {
    // MARK: - The music rooms (prd §995)

    /// Activity · Albums · Artists · Songs, on the template every room scopes
    /// with. A tile is an ORDER here, never a filter (`MusicScope`), so every
    /// tile holds every song and none can stand over nothing. Any pick closes
    /// an open album or artist — the lit tile tapped again leads back.
    ///
    /// Albums and Artists stand only over at least one name (§83): a room
    /// whose songs all predate the stored album would light Albums onto
    /// nothing.
    private func musicTiles(_ live: [Thing]) -> DSScopeTiles<MusicScope> {
        let offered = MusicScope.allCases.filter { scope in
            !scope.groups || live.contains { musicName($0, scope) != nil }
        }
        return DSScopeTiles(sections: offered,
                     active: offered.contains(chrome.musicScope) ? chrome.musicScope : .activity,
                     attention: []) { picked in
            withAnimation(DS.Motion.standard) {
                chrome.musicScope = picked
                chrome.musicGroup = nil
            }
        }
    }

    /// THE MUSIC ROOMS (Apple Music and Spotify, one face): the newest song
    /// as the cover in the lead box, the tiles under it, then the tile's list.
    /// Activity is the room as it was — sittings, not days (2026-07-21), the
    /// cover lifted out. Songs is every song A–Z under letter headers. Albums
    /// and Artists are A–Z lists of names; one opens in place, its name a row
    /// that leads back and its songs A–Z under it (the Notes folder shape,
    /// prd §980). The cover stays the newest song under every tile, so the
    /// lead box and the tiles never move (the fixed template).
    @ViewBuilder
    func musicSections(_ visible: [Thing], nextEventID: UUID?, heroShown: Bool) -> some View {
        let live = visible.filter(\.isLive)
        let days = sessionGroups(live)
        let coverID = heroShown ? nil : ledeThingID(in: days)
        let tiles = musicTiles(live)
        standaloneLead(cover: coverThing(coverID, in: live), tiles: tiles,
                       listEmpty: live.isEmpty, emptyWords: Text(chrome.musicScope.summary))
        // A pick whose tile is no longer offered stands as Activity.
        let pick = tiles.active
        switch pick {
        case .activity:
            let sittings = liftingCover(days, id: coverID)
            groupedSections(sittings, nextEventID: nextEventID, boundary: boundaryThingID(in: sittings))
        case .songs:
            let sections = MusicShelf.sections(live) { TitleSeam.name($0.title) }
            ForEach(sections, id: \.letter) { section in
                daySection(section.letter, section.items, nextEventID: nextEventID, dated: false)
            }
        case .albums, .artists:
            let scope = pick
            if let open = chrome.musicGroup {
                let key = MusicShelf.key(open)
                let songs = live
                    .filter { musicName($0, scope).map(MusicShelf.key) == key }
                    .sorted { MusicShelf.ordered(TitleSeam.name($0.title), TitleSeam.name($1.title)) }
                musicOpenGroupRow(open, scope: scope)
                daySection(open, songs, nextEventID: nextEventID, dated: false, headed: false)
            } else {
                musicNameSections(live, scope: scope)
            }
        }
    }

    /// The album a song came off, or the artist who made it — the name the
    /// Albums or Artists tile files it under. Nil files it nowhere: the
    /// album gap (rows landed before the album was stored) is accepted.
    private func musicName(_ thing: Thing, _ scope: MusicScope) -> String? {
        switch scope {
        case .albums:
            return MusicShelf.album(fact: thing.factList.first { $0.label == "Album" }?.value,
                                    summary: thing.summary)
        case .activity, .songs, .artists:
            return MusicShelf.artist(handle: thing.authorHandle,
                                     titleLine: TitleSeam.split(thing.title).line)
        }
    }

    /// Every album or artist A–Z under letter headers, each with how many
    /// songs it holds. An album leads with its newest cover; an artist has
    /// no picture of its own, so it leads with nothing rather than a guess.
    @ViewBuilder
    private func musicNameSections(_ rows: [Thing], scope: MusicScope) -> some View {
        let groups = MusicShelf.groups(rows.map { (musicName($0, scope), $0.previewImageURL) })
        let sections = MusicShelf.sections(groups) { $0.name }
        ForEach(sections, id: \.letter) { section in
            Section {
                musicLetterHeader(section.letter)
                ForEach(section.items, id: \.name) { group in
                    DSPushRow(title: Text(verbatim: group.name),
                              fact: Text(verbatim: "\(group.count)"),
                              action: { withAnimation(DS.Motion.standard) { chrome.musicGroup = group.name } }) {
                        if scope == .albums {
                            if let art = group.art {
                                RemoteThumb(urlString: art, size: DS.Mark.row, fallback: source)
                            } else {
                                BridgeIcon(name: source, size: DS.Mark.row)
                            }
                        }
                    }
                    .frame(minHeight: DS.Hit.min)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.rowInset,
                                              bottom: 0, trailing: DSRoomChassis.rowInset))
                }
            }
        }
    }

    /// A letter over a list of names — the day header's type on the primary
    /// ramp, because a letter is not a time (prd §740).
    private func musicLetterHeader(_ letter: String) -> some View {
        Text(verbatim: letter)
            .dsText(.heading24)
            .foregroundStyle(DS.textPrimary)
            .accessibilityAddTraits(.isHeader)
            .padding(.leading, DSRoomChassis.rowInset)
            .padding(.top, DS.Space.s6)
            .padding(.bottom, DS.Space.s1)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// The open album's or artist's name, under the tiles: the tap leads back
    /// to the list of names, as the lit tile does.
    private func musicOpenGroupRow(_ name: String, scope: MusicScope) -> some View {
        Section {
            DSDoorRow(icon: "chevron.left", title: Text(verbatim: name)) {
                withAnimation(DS.Motion.standard) { chrome.musicGroup = nil }
            }
            .accessibilityHint(scope == .albums ? Text("Back to albums") : Text("Back to artists"))
            .noteFolderRowChrome()
        }
    }
}
