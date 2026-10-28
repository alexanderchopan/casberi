import SwiftUI

/// **SOURCES IS A LIBRARY (prd §1316, user: "Do A. it's like Apple's Library
/// and so will feel familiar"; "the app is a joy to use, but the app
/// catalogue and sources section is not").** Under the box, every category is
/// a folder, three across, as the App Library draws them: inside, the apps you
/// have wearing a green dot (§1319), every icon in colour; under
/// it the name and "3 of 21". A tap springs the folder open in place, over the
/// page (`SourcesOpenFolder`), the way the dock's folders spring (§621):
/// yours first with the dot, the rest with a plus. Casberi's own settings take the
/// first slot, where the App Library keeps Suggestions.
///
/// The search field stays above the folders: on the phone Sources rises as a
/// sheet over the band's search (§1245), and a focused field lists every app
/// A–Z, as the App Library's does.
struct SourcesLibrary: View {
    struct Folder: Identifiable {
        let category: String
        /// Yours first, A–Z, then the rest, A–Z.
        let apps: [String]
        let have: Int
        var id: String { category }
    }

    let folders: [Folder]
    /// Whether an app is yours: drawn in colour.
    let has: (String) -> Bool
    let open: (String) -> Void
    let openCasberi: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: DS.Space.s4, alignment: .top),
                                count: 3)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: DS.Space.s6) {
            CasberiFolder(action: openCasberi)
            ForEach(folders) { folder in
                SourcesFolderTile(folder: folder, has: has) { open(folder.category) }
            }
        }
    }

    /// Every category's apps, yours first.
    static func folders(_ groups: [(category: String, apps: [BridgeCatalog.Offer])],
                        has: (String) -> Bool) -> [Folder] {
        groups.map { group in
            let names = group.apps.map(\.name)
            let yours = names.filter(has)
            return Folder(category: group.category,
                          apps: yours + names.filter { !has($0) },
                          have: yours.count)
        }
    }
}

/// AN APP YOU HAVE WEARS A GREEN DOT (prd §1319, user: "C is better but not
/// green check can't we do green dot?"). Every icon stands in its own colour,
/// as the App Library draws them, so a first run is not a wall of grey; the
/// dot at the corner says which are yours. The ring is the ground it sits
/// on, so the dot reads apart from the icon under it.
private extension View {
    func sourcesYours(_ yours: Bool, size: CGFloat, ring: Color) -> some View {
        modifier(SourcesYoursDot(yours: yours, size: size, ring: ring))
    }
}

/// The dot, which springs in the moment an app becomes yours (prd §1588):
/// back in its folder after a connect, the new one is the one that moves.
private struct SourcesYoursDot: ViewModifier {
    let yours: Bool
    let size: CGFloat
    let ring: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottomTrailing) {
            if yours {
                Circle()
                    .fill(DS.confirm)
                    .frame(width: size, height: size)
                    // The ring is the ground under it: the page, and the
                    // folder's own lift where it stands in a well.
                    .overlay(Circle().strokeBorder(ring, lineWidth: max(1.5, size * 0.18)))
                    .overlay(Circle().strokeBorder(ring == DS.page ? DS.fillFaint : .clear,
                                                   lineWidth: max(1.5, size * 0.18)))
                    .offset(x: size * 0.3, y: size * 0.3)
                    .accessibilityHidden(true)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.1).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : DS.Motion.folder, value: yours)
    }
}

/// One folder: the well with nine of its apps, the name, the count.
private struct SourcesFolderTile: View {
    let folder: SourcesLibrary.Folder
    let has: (String) -> Bool
    let action: () -> Void

    var body: some View {
        Button {
            DSHaptic.tap()
            action()
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        GeometryReader { geo in
                            let pad = DS.Space.s3
                            let gap = DS.Space.s2
                            let side = max(0, (geo.size.width - 2 * pad - 2 * gap) / 3)
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: gap), count: 3),
                                      alignment: .leading, spacing: gap) {
                                ForEach(folder.apps.prefix(9), id: \.self) { name in
                                    BridgeIcon(name: name, size: side)
                                        .sourcesYours(has(name), size: max(7, side * 0.34), ring: DS.page)
                                }
                            }
                            .padding(pad)
                        }
                    }
                    .dsWell(cornerRadius: DS.Radius.widget)
                SourcesFolderWords(name: folder.category,
                                   fact: String(localized: "\(folder.have) of \(folder.apps.count)"))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressSpring())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(folder.category), \(folder.have) of \(folder.apps.count)"))
        .accessibilityAddTraits(.isButton)
    }
}

/// Casberi's own settings, the library's first slot.
private struct CasberiFolder: View {
    let action: () -> Void

    var body: some View {
        Button {
            DSHaptic.tap()
            action()
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        GeometryReader { geo in
                            CasberiMark(size: geo.size.width * 0.5)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .dsWell(cornerRadius: DS.Radius.widget)
                SourcesFolderWords(name: "Casberi", fact: String(localized: "Settings"))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressSpring())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Casberi, Settings"))
        .accessibilityAddTraits(.isButton)
    }
}

private struct SourcesFolderWords: View {
    let name: String
    let fact: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: name)
                .dsText(.body17).foregroundStyle(DS.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(verbatim: fact)
                .dsText(.subhead12).foregroundStyle(DS.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, DS.Space.s1)
    }
}

/// **A FOLDER SPRINGS OPEN IN PLACE (prd §1316).** Over the page, never a
/// sheet: the page dims under it, a tap outside closes it, and an app opens
/// from here as its row would (yours goes, the rest their way in, §1418). It
/// stays open behind what that raises, so coming back is the folder again.
/// Yours wear the green dot, the rest the pink plus (§1319).
struct SourcesOpenFolder: View {
    let folder: SourcesLibrary.Folder
    let has: (String) -> Bool
    let open: (String) -> Void
    /// An app of yours's page, offered on its long press (prd §1418); nil for
    /// one you could add.
    let settings: (String) -> (() -> Void)?
    let close: () -> Void
    /// **THE NOTES FOLDER LEADS WITH YOUR NOTES (prd §1347).** Notes is a
    /// category again, and its folder is where you manage it: the first
    /// cell opens the Notes page itself (All · Folders · Voice · New) as a
    /// page pushed beside Library, the way a setting opens from Casberi's
    /// folder; the apps you write in follow, as in any folder. Nil for
    /// every other folder.
    var notesPage: (() -> Void)? = nil

    private let columns = Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2, alignment: .top),
                                count: 4)

    private var apps: some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: DS.Space.s4) {
            if let notesPage {
                SourcesFolderNotesPage(action: notesPage)
            }
            ForEach(folder.apps, id: \.self) { name in
                SourcesFolderApp(name: name, yours: has(name), settings: settings(name)) { open(name) }
            }
        }
        .padding(.top, DS.Space.s2)
    }

    var body: some View {
        ZStack {
            // The page dims under the folder; no blur, so Reduce
            // Transparency has nothing to undo.
            Rectangle()
                .fill(DS.scrim)
                .ignoresSafeArea()
                .onTapGesture { close() }
                .accessibilityLabel(Text("Close \(folder.category)"))
                .accessibilityAddTraits(.isButton)
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                HStack(alignment: .firstTextBaseline, spacing: DSRoomChassis.headGap) {
                    Image(systemName: CategoryFold.glyph(for: folder.category))
                        .dsGlyph(.body, weight: .regular)
                        .foregroundStyle(DS.brandInk)
                        .frame(width: DSRoomChassis.headGlyph)
                    Text(verbatim: folder.category)
                        .dsText(.heading24).foregroundStyle(DS.headInk)
                    Spacer(minLength: DS.Space.s2)
                    Text("\(folder.have) of \(folder.apps.count)")
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
                }
                // The whole folder when it fits; a long one (the Wallet's)
                // scrolls inside the panel.
                ViewThatFits(in: .vertical) {
                    apps
                    ScrollView { apps }
                }
            }
            .padding(DS.Space.s6)
            .frame(maxWidth: 440)
            .background(DS.surfaceRaised, in: RoundedRectangle(cornerRadius: DS.Radius.widget + DS.Space.s2,
                                                               style: .continuous))
            .padding(DS.Space.s6)
        }
        // Escape closes it, on a keyboard.
        .background {
            Button(action: close) { EmptyView() }
                .keyboardShortcut(.cancelAction)
                .hidden()
        }
    }
}

/// Your notes, the Notes folder's first cell (prd §1347): the mark a note
/// of yours wears (`BridgeIcon`'s symbol drawing, §976a) over the page's
/// name. Never a dot or a plus: it is a page, not an app.
private struct SourcesFolderNotesPage: View {
    let action: () -> Void

    var body: some View {
        Button {
            DSHaptic.selection()
            action()
        } label: {
            VStack(spacing: DS.Space.s1) {
                BridgeIcon(name: Pinboard.room, size: DS.Face.seat + 12, symbol: ScopeTileGlyph.notes)
                Text("Your notes")
                    .dsText(.label12)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressSpring())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Your notes"))
        .accessibilityAddTraits(.isButton)
    }
}

/// One app in an open folder: its icon over its name; yours wears the green
/// dot, one you could add the pink plus.
private struct SourcesFolderApp: View {
    let name: String
    let yours: Bool
    let settings: (() -> Void)?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: DS.Space.s1) {
                BridgeIcon(name: name, size: DS.Face.seat + 12)
                    .sourcesYours(yours, size: 14, ring: DS.surfaceRaised)
                    .overlay(alignment: .topTrailing) {
                        if !yours {
                            Image(systemName: "plus")
                                .dsGlyph(.tick, weight: .bold)
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(DS.brandInk, in: Circle())
                                .offset(x: 6, y: -6)
                        }
                    }
                Text(verbatim: name)
                    .dsText(.label12)
                    .foregroundStyle(DS.textPrimary)
                    // Two lines between words, never inside one: a single
                    // long word ("CardPointers") shrinks to one line instead.
                    .lineLimit(name.contains(" ") ? 2 : 1)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressSpring())
        .contextMenu {
            if let settings { AppMenu(open: action, settings: settings) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(yours ? Text(verbatim: name) : Text("\(name), Add"))
        .accessibilityAddTraits(.isButton)
    }
}

/// **AN APP'S LONG PRESS, WHEREVER IT IS DRAWN (prd §1159, §1418): Open,
/// then Settings, its account page.** The tray's icon, Library's folder and
/// its rows hold the same two, so a tap goes and a hold manages everywhere.
struct AppMenu: View {
    let open: () -> Void
    let settings: () -> Void

    var body: some View {
        Button(action: open) {
            Label("Open", systemImage: "arrow.up.forward.app")
        }
        Button(action: settings) {
            Label("Settings", systemImage: "slider.horizontal.3")
        }
    }
}

/// **CASBERI'S FOLDER IS ITS SETTINGS (prd §1321, user: "perhaps each setting
/// could be a tile like an app").** It springs open over Sources as any folder
/// does: the mark and "Casberi" over every setting as a tile, the version
/// under them. A setting opens as a page pushed beside Sources; the folder
/// stays open behind it, so coming back is the folder again.
struct SourcesSettingsFolder: View {
    let close: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(DS.scrim)
                .ignoresSafeArea()
                .onTapGesture { close() }
                .accessibilityLabel(Text("Close Casberi"))
                .accessibilityAddTraits(.isButton)
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                // The mark stands once, in the colophon under the tiles.
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Text(verbatim: "Casberi")
                        .dsText(.heading24).foregroundStyle(DS.headInk)
                    Spacer(minLength: DS.Space.s2)
                    Text("Settings")
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
                }
                SettingsRows(style: .tiles)
            }
            .padding(DS.Space.s6)
            .frame(maxWidth: 440)
            .background(DS.surfaceRaised, in: RoundedRectangle(cornerRadius: DS.Radius.widget + DS.Space.s2,
                                                               style: .continuous))
            .padding(DS.Space.s6)
        }
        .background {
            Button(action: close) { EmptyView() }
                .keyboardShortcut(.cancelAction)
                .hidden()
        }
    }
}
