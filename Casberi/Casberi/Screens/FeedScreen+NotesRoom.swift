import SwiftUI
import SwiftData

// The Notes room (prd §969, §980, §985): its order, scope, tiles, sections,
// folders and deletes, split out of
// FeedScreen.swift (prd §718). Nothing here changed but the file it lives
// in and, where another file reads a member, its access level.
extension FeedScreen {
    /// The Notes room's rows in the Notes room's order (prd §969): the
    /// query's `source == "You"` half narrowed to the note kind, then newest
    /// first by `Pinboard.stamp` — the pin's time for a pin, the capture for
    /// a note. One plain list, no day dividers: the feed's dividers say when
    /// something ARRIVED, and a note you wrote is not news (user: "apple notes
    /// also doesn't separate by days").
    func notesOrder(_ rows: [Thing]) -> [Thing] {
        rows.filter { $0.isLive && Pinboard.inRoom($0) }
            .sorted { Pinboard.stamp($0) > Pinboard.stamp($1) }
    }

    /// The Notes room's tile (prd §969), gated on the room like the two
    /// above. Pinned narrows to what you pinned — a pinned note included,
    /// which is what "this one on top" means here. Folders (prd §980) narrows
    /// to what you filed: the open folder's rows, or every filed row under
    /// the folder list, so the lead covers the newest thing you filed. New is
    /// a verb and never stands.
    func notesScopeAllows(_ thing: Thing) -> Bool {
        guard Pinboard.isPinnedRoom(source) else { return true }
        // The pill's kind (prd §1099) narrows every tile.
        guard NotesKind.allows(chrome.notesKind, source: thing.source,
                               kind: thing.kind.rawValue) else { return false }
        switch chrome.notesScope {
        case .folders:
            guard let filed = thing.folder else { return false }
            guard let open = chrome.notesFolder else { return true }
            return NoteFolderName.key(filed) == NoteFolderName.key(open)
        case .all, .new, .search:  return true
        }
    }

    /// The Notes room's tiles (prd §969, §1099): All · Folders · New ·
    /// Search, on the same template as every room's. New and Search are
    /// VERBS in the row — they never light. New raises the note page; held,
    /// it raises the page with the mic live (prd §970), and under the pill's
    /// Voice notes a plain tap records too, because that is the only note
    /// that pick can make. Its plus arms into the voice kind's waveform as
    /// the hold builds (prd §973). Search raises the find tray.
    private var notesTiles: DSScopeTiles<NotesScope> {
        DSScopeTiles(sections: NotesScope.allCases,
                     active: chrome.notesScope,
                     attention: [],
                     verbs: [.new, .search],
                     hold: DSScopeTiles<NotesScope>.Hold(
                        glyph: "waveform",
                        label: String(localized: "Record a note"),
                        act: { _ in chrome.newNoteByVoice() })) { picked in
            if picked == .search {
                feedSheet = .notesSearch
            } else if picked == .new {
                if chrome.notesKind == .voice { chrome.newNoteByVoice() } else { chrome.newNote += 1 }
            } else {
                // Any pick closes an open folder — Folders tapped again is
                // the way back to the folder list (prd §980).
                withAnimation(DS.Motion.standard) {
                    chrome.notesScope = picked
                    chrome.notesFolder = nil
                }
            }
        }
    }

    /// THE NOTES ROOM (prd §969): the newest thing as the cover in the lead
    /// box, the tiles under it, then ONE plain list in `Pinboard.stamp`'s
    /// order — no day dividers (user: "apple notes also doesn't separate by
    /// days"). The room never has a head, so the tiles always stand here.
    ///
    /// Under the Folders tile (prd §980) the list is the FOLDERS — New folder
    /// first, then each folder with its count — and the cover is the newest
    /// thing filed anywhere. A folder opens in place: its name as a row that
    /// leads back, then its rows, and New files what it makes there.
    @ViewBuilder
    func notesSections(_ visible: [Thing], nextEventID: UUID?) -> some View {
        let coverID = ledeThingID(in: [(Pinboard.room, visible)])
        let cover = coverThing(coverID, in: visible)
        let folderList = chrome.notesScope == .folders && chrome.notesFolder == nil
        // Nothing filed holds the lead's box empty over the folder list, as
        // an empty room does (§979: the tiles never rise).
        standaloneLead(cover: cover, tiles: notesTiles, listEmpty: visible.isEmpty,
                       emptyWords: Text(emptyLine))
        if folderList {
            noteFolderRows(visible)
        } else {
            if chrome.notesScope == .folders, let open = chrome.notesFolder {
                openFolderRow(open)
            }
            if chrome.notesScope == .all {
                // PINNED LEADS (prd §983), under its name — Apple Notes'
                // order. Named groups, never days (§969's "no day dividers"
                // holds). The rest stand under "Notes" whenever a Pinned
                // group is drawn (prd §985): headerless, one pin made every
                // row under it read as pinned. A pin lifted out as the cover
                // draws no group, so then the list needs no name either.
                let pinned = visible.filter { $0.isLive && Pinboard.isPinned($0) }
                let rest = visible.filter { $0.isLive && !Pinboard.isPinned($0) }
                let pinnedDrawn = pinned.contains { $0.id != coverID }
                daySection(String(localized: "Pinned"), pinned, nextEventID: nextEventID,
                           dated: false, cover: coverID)
                daySection(pinnedDrawn ? String(localized: "Notes") : Pinboard.room, rest,
                           nextEventID: nextEventID, dated: false,
                           cover: coverID, headed: pinnedDrawn)
            } else {
                daySection(Pinboard.room, visible, nextEventID: nextEventID, dated: false,
                           cover: coverID, headed: false)
            }
        }
    }

    /// THE NOTES ROOM'S PILL (prd §1099): Notes · Voice notes, in the title
    /// row where every room picks between the apps in it (§1066). "All
    /// notes" while both show.
    var notesKindPill: some View {
        let all = DSAccountSlot(id: "", name: String(localized: "All notes"), sub: nil, faces: [])
        let slots = [all] + NotesKind.allCases.map { kind in
            DSAccountSlot(id: kind.rawValue, name: kind.label, sub: nil, faces: [],
                          symbol: kind.symbol)
        }
        let showing = slots.first { !$0.id.isEmpty && $0.id == chrome.notesKind?.rawValue } ?? all
        return DSScopeMenu(slots: slots, showing: showing,
                           spoken: { String(localized: "Showing: \($0)") },
                           allLabel: String(localized: "All notes"),
                           onPick: { id in
                               withAnimation(DS.Motion.standard) {
                                   chrome.notesKind = id.flatMap(NotesKind.init(rawValue:))
                               }
                           })
        #if DEBUG
        .task { notesProbe() }
        #endif
    }

    #if DEBUG
    /// `-notesKind written|voice` picks the pill's kind and `-notesScope
    /// folders|search` lands on Folders or raises Search, at mount (prd §1099;
    /// NSLogs `notesProbe:`). Once per launch.
    private func notesProbe() {
        guard !Self.notesProbed else { return }
        Self.notesProbed = true
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "notesKind"), let kind = NotesKind(rawValue: raw) {
            NSLog("[Casberi] notesProbe: kind %@", raw)
            chrome.notesKind = kind
        }
        if let raw = defaults.string(forKey: "notesScope"), let scope = NotesScope(rawValue: raw) {
            NSLog("[Casberi] notesProbe: scope %@", raw)
            if scope == .search { feedSheet = .notesSearch } else if !scope.isVerb { chrome.notesScope = scope }
        }
    }
    #endif

    /// The folder list (prd §980): New folder, then every folder — the
    /// stored ones and any a row carries — with how many rows it holds. A
    /// folder's long press renames or deletes it; deleting unfiles its rows.
    /// `filed` is this render's `visible`, which under the list is every
    /// filed row, so the counts cost one pass and no fetch.
    @ViewBuilder
    private func noteFolderRows(_ filed: [Thing]) -> some View {
        let names = NoteFolderStore.shared.list(with: filed)
        let counts = NoteFolderName.counts(filed: filed.map { $0.isLive ? $0.folder : nil })
        Section {
            ForEach(names, id: \.self) { name in
                DSPushRow(title: Text(verbatim: name),
                          fact: Text(verbatim: "\(counts[NoteFolderName.key(name)] ?? 0)"),
                          action: { openFolder(name) }) {
                    // The note's own mark (prd §983, §976a): a black
                    // circle, the glyph in the brand pink.
                    Image(systemName: ScopeTileGlyph.folders)
                        .font(.system(size: DS.Mark.row * 0.54, weight: .semibold))
                        .foregroundStyle(DS.brand)
                        .frame(width: DS.Mark.row, height: DS.Mark.row)
                        .background(Color.black, in: Circle())
                        .accessibilityHidden(true)
                }
                .frame(minHeight: DS.Hit.min)
                .contextMenu {
                    // Share leads (prd §1021): the folder as one card.
                    Button {
                        folderShare = FolderShareCard.Input(name: name, things: filed.filter {
                            $0.folder.map(NoteFolderName.key) == NoteFolderName.key(name)
                        })
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        folderPrompt = .rename(name)
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        deletingFolder = name
                    } label: {
                        Label("Delete folder", systemImage: "trash")
                    }
                }
                .noteFolderRowChrome()
            }
            // RECENTLY DELETED (prd §985), after the folders as in Apple
            // Notes, and only while it holds something: an empty one is a
            // door onto nothing.
            let trashed = NoteTrash.shared.entries.count
            if trashed > 0 {
                DSPushRow(title: Text("Recently deleted"),
                          fact: Text(verbatim: "\(trashed)"),
                          action: { trashOpen = true }) {
                    Image(systemName: "trash")
                        .font(.system(size: DS.Mark.row * 0.54, weight: .semibold))
                        .foregroundStyle(DS.brand)
                        .frame(width: DS.Mark.row, height: DS.Mark.row)
                        .background(Color.black, in: Circle())
                        .accessibilityHidden(true)
                }
                .frame(minHeight: DS.Hit.min)
                .noteFolderRowChrome()
            }
            // New folder LAST (prd §983), Apple Notes' place for it: the
            // list is what you have, and the verb that adds one follows it.
            // The folders' own anatomy (prd §986): the same 26pt mark column
            // and gap, so its word starts where every folder's does — the
            // sheet door's 18pt column put it 16pt left of them. A verb, so
            // no chevron and no circle.
            DSPushRow(title: Text("New folder"), opens: false,
                      action: { folderPrompt = .make(filing: nil) }) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: DS.Mark.row * 0.54, weight: .regular))
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: DS.Mark.row, height: DS.Mark.row)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: DS.Hit.min)
            .noteFolderRowChrome()
        }
    }

    /// The open folder's name, under the tiles: the tap leads back to the
    /// folder list, as the lit Folders tile does.
    private func openFolderRow(_ name: String) -> some View {
        Section {
            DSDoorRow(icon: "chevron.left", title: Text(verbatim: name)) {
                withAnimation(DS.Motion.standard) { chrome.notesFolder = nil }
            }
            .accessibilityHint(Text("Back to folders"))
            // The open folder's long press shares it too (prd §1021); its
            // rows are the list under it.
            .contextMenu {
                Button {
                    folderShare = FolderShareCard.Input(name: name, things: visible)
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            .noteFolderRowChrome()
        }
    }

    private func openFolder(_ name: String) {
        withAnimation(DS.Motion.standard) { chrome.notesFolder = name }
    }

    /// Make a folder from the name prompt, and file the row that asked, if
    /// one did (the row menu's New folder…).
    func commitFolderPrompt(_ prompt: FolderPrompt, _ typed: String) {
        let store = NoteFolderStore.shared
        switch prompt {
        case .make(let filing):
            guard let name = store.add(typed) else { return }
            if let filing, filing.isLive {
                Pinboard.file(filing, in: name)
                modelContext.saveHonestly()
                chrome.flash(String(localized: "Moved to \(name)"))
            } else {
                openFolder(name)
            }
        case .rename(let old):
            guard let name = store.rename(old, to: typed, in: modelContext) else { return }
            modelContext.saveHonestly()
            if let open = chrome.notesFolder,
               NoteFolderName.key(open) == NoteFolderName.key(old) {
                chrome.notesFolder = name
            }
        }
        DSHaptic.tap()
    }

    /// Delete a folder, confirmed: its rows are unfiled and stay in All.
    func deleteFolder(_ name: String) {
        NoteFolderStore.shared.remove(name, in: modelContext)
        modelContext.saveHonestly()
        DSHaptic.tap()
        chrome.flash(String(localized: "Folder deleted"))
    }

    /// The row menu's Move to folder (prd §980): file, move, or unfile.
    func fileThing(_ thing: Thing, in folder: String?) {
        guard thing.isLive else { return }
        Pinboard.file(thing, in: folder)
        modelContext.saveHonestly()
        DSHaptic.tap()
        chrome.flash(folder.map { String(localized: "Moved to \($0)") }
                     ?? String(localized: "Removed from folder"))
    }

    /// The row menu's Delete (a note of yours only): raise the confirmation.
    func askDeleteNote(_ thing: Thing) {
        guard thing.isLive, Pinboard.isNote(thing) else { return }
        deletingNote = thing
    }

    /// Delete a note of yours, confirmed. The store mirrors to iCloud, so the
    /// note leaves every device; Spotlight forgets it, as the drop toast's
    /// Undo does (`RootShell.undoCapture`). It is archived FIRST, in Recently
    /// Deleted on this device (prd §985), and a note the archive could not
    /// write is not deleted: the dialog promised it could come back.
    func deleteNote(_ thing: Thing) {
        guard thing.isLive, Pinboard.isNote(thing) else { return }
        guard NoteTrash.shared.keep(thing) else {
            DSHaptic.failure()
            chrome.flash(String(localized: "Couldn't delete the note"), tone: .failure)
            return
        }
        let id = thing.id
        withAnimation(DS.Motion.standard) {
            modelContext.delete(thing)
        }
        modelContext.saveHonestly()
        SpotlightIndex.remove(ids: [id])
        DSHaptic.tap()
        chrome.flash(String(localized: "Note deleted, recoverable for \(NoteTrashRules.keepDays) days"))
    }

    /// Recently Deleted's Recover (prd §985): the note back in the room,
    /// in its folder and pin, on its own day.
    func recoverNote(_ entry: NoteTrashEntry) {
        guard NoteTrash.shared.recover(entry, into: modelContext) != nil else {
            DSHaptic.failure()
            chrome.flash(String(localized: "Couldn't recover the note"), tone: .failure)
            return
        }
        DSHaptic.success()
        chrome.flash(String(localized: "Recovered"), tone: .success)
    }
}

extension View {
    /// A folder row in the Notes room's list: in the rows' column, on
    /// nothing, like every row (prd §749).
    func noteFolderRowChrome() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.inset,
                                      bottom: 0, trailing: DSRoomChassis.inset))
    }
}
