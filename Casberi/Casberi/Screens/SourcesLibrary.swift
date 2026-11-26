import SwiftUI

/// **APPS: RECENT, THE WALLET, THEN THE FEED (prd §1974, retiring §1316's
/// grid of folders).** Recent leads; the Wallet is its own section, two rows
/// of its apps; the Feed's categories follow A–Z, one line each. Yours are
/// lit and the rest step back (§1733). A tap on a section or a line springs
/// its folder open in place, over the page (`SourcesOpenFolder`, §1316):
/// yours first, the rest with a plus.
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
        /// The apps of yours that need you (prd §1733), A–Z.
        var needs: [String] = []
        var id: String { category }
    }

    let folders: [Folder]
    /// Whether an app is yours: drawn in colour.
    let has: (String) -> Bool
    /// Whether an app of yours needs you: the one amber dot.
    let needs: (String) -> Bool
    /// The apps of yours last opened here, newest first (prd §1733).
    let recents: [String]
    /// With nothing added: the apps a first run could start with.
    let starts: [String]
    let open: (String) -> Void
    /// An app's own tap, as its folder's cell takes it.
    let openApp: (String) -> Void
    let settings: (String) -> (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            // **ONE TAP TO WHAT YOU USE (prd §1733).** The apps of yours last
            // opened here; before anything is yours, the same row is the way
            // in, each app wearing the plus.
            if !recents.isEmpty {
                SourcesQuickRow(title: String(localized: "Recent"), apps: recents, adds: false,
                                needs: needs, settings: settings, open: openApp)
            } else if !starts.isEmpty {
                SourcesQuickRow(title: String(localized: "Start with any of these"), apps: starts, adds: true,
                                needs: { _ in false }, settings: { _ in nil }, open: openApp)
            }
            // **THE WALLET, THEN THE FEED (prd §1974, retiring §1316's
            // folder grid; user: "we could also have wallet be first and like
            // a different section than the feed ones").** A crypto user
            // scanned nine folders to find Wallet among the feeds. Now the
            // Wallet stands first under its own word, then the Feed's
            // categories under theirs, A–Z: every one the same row (§1974a).
            if let wallet = folders.first(where: { $0.category == CategoryFold.walletCategory }) {
                section(String(localized: "Wallet"), [wallet])
            }
            let feed = folders.filter { $0.category != CategoryFold.walletCategory }
            if !feed.isEmpty {
                section(String(localized: "Feed"), feed)
            }
            // No Settings folder here (prd §1808): Casberi's settings are
            // on the Account page, with the account they belong to.
        }
    }

    private func section(_ name: String, _ folders: [Folder]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: name)
                .dsText(.heading24).foregroundStyle(DS.headInk)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, DS.Space.s1)
            ForEach(folders) { folder in
                SourcesCategoryRow(folder: folder, has: has, needs: needs) { open(folder.category) }
            }
        }
    }

    /// Every category's apps, yours first.
    static func folders(_ groups: [(category: String, apps: [BridgeCatalog.Offer])],
                        has: (String) -> Bool,
                        needs: (String) -> Bool = { _ in false }) -> [Folder] {
        groups.map { group in
            let names = group.apps.map(\.name)
            let yours = names.filter(has)
            return Folder(category: group.category,
                          apps: yours + names.filter { !has($0) },
                          have: yours.count,
                          needs: yours.filter(needs))
        }
    }

    /// A folder's line: what needs you, in words, else its count.
    static func fact(_ folder: Folder) -> (text: String, needsYou: Bool) {
        switch folder.needs.count {
        case 0:  return (String(localized: "\(folder.have) of \(folder.apps.count)"), false)
        case 1:  return (String(localized: "\(folder.needs[0]) needs you"), true)
        default: return (String(localized: "\(folder.needs.count) need you"), true)
        }
    }
}

/// **WHAT IS YOURS IS IN COLOUR; THE REST STEPS BACK (prd §1733, amending
/// §1319's green dot).** A dot on every app you have said nothing once most
/// were lit, and a full Library and an empty one looked alike. An app you
/// could add draws at `stepped`; the one dot left is amber, on an app of
/// yours that needs you, so a mark on an icon is always an exception.
private extension View {
    func sourcesState(yours: Bool, needsYou: Bool, size: CGFloat, ring: Color) -> some View {
        modifier(SourcesStateMark(yours: yours, needsYou: needsYou, size: size, ring: ring))
    }

    /// The pink plus on an app you could add.
    func sourcesAddBadge(_ adds: Bool) -> some View {
        overlay(alignment: .topTrailing) {
            if adds {
                Image(systemName: "plus")
                    .dsGlyph(.tick, weight: .bold)
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(DS.brandInk, in: Circle())
                    .offset(x: 6, y: -6)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// The mark, which springs in the moment an app becomes yours (prd §1588):
/// back in its folder after a connect, the new one is the one that lights.
private struct SourcesStateMark: ViewModifier {
    /// How far an app you could add steps back.
    static let stepped = 0.3

    let yours: Bool
    let needsYou: Bool
    let size: CGFloat
    let ring: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(yours ? 1 : Self.stepped)
            .overlay(alignment: .bottomTrailing) {
            if yours && needsYou {
                Circle()
                    .fill(DS.attention)
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
        .animation(reduceMotion ? nil : DS.Motion.folder, value: needsYou)
    }
}

/// Library's row over the folders (prd §1733): up to five apps at the seat
/// size, each one tap from its room, or from its way in while it wears the
/// plus.
///
/// **THE EMPTY FEED DRAWS THIS ROW TOO (prd §1741).** Its box is the same
/// six apps with their names under them (`named`), so the Feed and Apps offer
/// one list in one drawing. The way-in row holds every starter; its gaps
/// give way on a narrow phone before an icon does.
struct SourcesQuickRow: View {
    let title: String
    let apps: [String]
    let adds: Bool
    /// The app's name under its icon: the empty Feed's box, where the icons
    /// are the whole screen and a mark alone does not say what it adds.
    var named = false
    let needs: (String) -> Bool
    let settings: (String) -> (() -> Void)?
    let open: (String) -> Void

    private var shown: [String] {
        Array(apps.prefix(adds ? LibraryRecents.starts.count : LibraryRecents.keep))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(verbatim: title)
                .dsText(.label12).foregroundStyle(DS.textSecondary)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element) { index, name in
                    if index > 0 {
                        Spacer(minLength: DS.Space.s1).frame(maxWidth: DS.Space.s4)
                    }
                    Button {
                        DSHaptic.selection()
                        open(name)
                    } label: {
                        VStack(spacing: DS.Space.s1) {
                            BridgeIcon(name: name, size: DS.Face.seat)
                                .sourcesState(yours: true, needsYou: needs(name), size: 12, ring: DS.page)
                                .sourcesAddBadge(adds)
                            if named {
                                Text(verbatim: name)
                                    .dsText(.label12).foregroundStyle(DS.textSecondary)
                                    // Its own width, centred under the icon,
                                    // so a long name never widens the row.
                                    .lineLimit(1).fixedSize()
                                    .frame(width: DS.Face.seat)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressSpring())
                    .contextMenu {
                        if let settings = settings(name) { AppMenu(open: { open(name) }, settings: settings) }
                    }
                    .accessibilityLabel(adds ? Text("\(name), Add") : Text(verbatim: name))
                }
            }
        }
    }
}

/// **THE EMPTY FEED'S BOX (prd §1741, user: "connect apps and their content
/// shows up here"; of a connect row under it: "i think its better without").**
/// One sentence saying what the Feed is, and the six apps a first run can
/// start with, drawn by Library's own row. No demo, no category tiles and no
/// second door: the Apps tab is the way to every other app. The box keeps
/// the lead's one size (the top-card rule).
struct FeedStartBox: View {
    /// The lead's one size (the Mac's and iPad's box); on the phone's
    /// Activity it stands under the Wallet at its own height (prd §1839).
    var fitsLead = true
    /// Closes the box for good, drawn as a cross beside the sentence (prd
    /// §1857); nil draws none.
    var dismiss: (() -> Void)? = nil
    let open: (String) -> Void

    var body: some View {
        if fitsLead {
            words
                // Under the title's own edge (seen on the simulator: at the box's
                // usual inset the sentence stood left of "Feed").
                .padding(.horizontal, DS.Space.s3)
                .padding(.vertical, DS.Space.s2)
                .frame(maxWidth: .infinity, minHeight: DSRoomChassis.leadHeight,
                       maxHeight: DSRoomChassis.leadHeight, alignment: .topLeading)
        } else {
            words.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            // The sentence the panel's design settled (prd §1839).
            // On the phone's first run it answers the card over it, "Set up
            // your wallet" (prd §1847, user: "for apps it could say set up
            // your feed").
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                (fitsLead ? Text("Add your apps and what's new in them shows up here.") : Text("Set up your feed"))
                    .dsText(fitsLead ? .heading28 : .heading24).foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let dismiss {
                    Spacer(minLength: 0)
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .dsGlyph(.subhead, weight: .bold)
                            .foregroundStyle(DS.textSecondary)
                            .frame(minWidth: DS.Hit.min, minHeight: DS.Hit.min)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressSpring())
                    .accessibilityLabel(Text("Close"))
                }
            }
            SourcesQuickRow(title: String(localized: "Start with any of these"),
                            apps: LibraryRecents.starts.filter { name in
                                BridgeCatalog.offers.contains { $0.name == name }
                            },
                            adds: true, named: true,
                            needs: { _ in false }, settings: { _ in nil }, open: open)
        }
    }
}

/// **ONE CATEGORY IN APPS IS ONE ROW (prd §1974a, user of the first build:
/// "its like one giant square", "even the numbers are truncated", "more
/// spacing between them", then "they should all be the same size … even if
/// wallet is separated").** Seven lines of touching icons read as one wall,
/// a tap landed on the neighbour and "+12" ran out of room. Now every
/// category, the Wallet's too, is one row of one height, as Settings draws
/// one: its name, three of its apps small at the right (yours first, the
/// rest stepped back), its fact ("3 of 22", or the amber word) and a
/// chevron. The whole row is one door, to its folder (§1316); the apps are
/// opened there. Holdings' foot draws the same row (prd §1974 item 3) under
/// its own words, "Add to Wallet", with no fact.
struct SourcesCategoryRow: View {
    let folder: SourcesLibrary.Folder
    let has: (String) -> Bool
    let needs: (String) -> Bool
    /// The words in the name's place, when they are not the category's.
    var title: String? = nil
    let action: () -> Void

    static let mark: CGFloat = 28
    static let shown = 3

    private var fact: (text: String, needsYou: Bool) { SourcesLibrary.fact(folder) }

    var body: some View {
        Button {
            DSHaptic.tap()
            action()
        } label: {
            HStack(spacing: DS.Space.s3) {
                Text(verbatim: title ?? folder.category)
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.s2)
                HStack(spacing: DS.Space.s1 + 2) {
                    ForEach(Array(folder.apps.prefix(Self.shown)), id: \.self) { name in
                        BridgeIcon(name: name, size: Self.mark)
                            .sourcesState(yours: has(name), needsYou: needs(name), size: 8, ring: DS.page)
                    }
                }
                .accessibilityHidden(true)
                if title == nil {
                    // One column for every count, so the icons line up down
                    // the page; an amber word takes the room it needs.
                    if fact.needsYou {
                        Text(verbatim: fact.text)
                            .dsText(.body17)
                            .foregroundStyle(DS.attentionInk)
                            .lineLimit(1)
                            .fixedSize()
                    } else {
                        Text(verbatim: "00 of 00")
                            .dsText(.body17)
                            .hidden()
                            .overlay(alignment: .trailing) {
                                Text(verbatim: fact.text)
                                    .dsText(.body17)
                                    .foregroundStyle(DS.textSecondary)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .fixedSize()
                    }
                }
                Image(systemName: "chevron.right")
                    .dsGlyph(.caption, weight: .semibold)
                    .foregroundStyle(DS.textSecondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: DSFeed.headHeight)
            .padding(.vertical, DS.Space.s3)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title ?? "\(folder.category), \(fact.text)"))
        .accessibilityAddTraits(.isButton)
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
    var needs: (String) -> Bool = { _ in false }
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
    /// **THE AZTEC APPS YOU HAVE CONNECTED (prd §1757).** Each opens its own
    /// site in Casberi's browser in one tap. Aztec's directory tile that led
    /// the folder is deleted (prd §1821). Nil for every other folder, and
    /// while you have no Your account (`AztecApps.tilesShown`, prd §1700s).
    var aztecApp: ((AztecAppsShape.App) -> Void)? = nil

    private let columns = Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2, alignment: .top),
                                count: 4)

    /// **YOURS, THEN ADD (prd §1733).** Two groups, each under its word: what
    /// you have, whole and in colour, then what you could add, each wearing
    /// the plus. They stood in one grid, told apart by a dot and a badge.
    private var apps: some View {
        let yours = folder.apps.filter(has)
        let rest = folder.apps.filter { !has($0) }
        return VStack(alignment: .leading, spacing: DS.Space.s4) {
            if !yours.isEmpty || notesPage != nil || (aztecApp != nil && !AztecAppsStore.shared.apps.isEmpty) {
                group(String(localized: "Yours")) {
                    if let notesPage {
                        SourcesFolderNotesPage(action: notesPage)
                    }
                    if let aztecApp {
                        ForEach(AztecAppsStore.shared.apps) { app in
                            SourcesFolderAztecApp(app: app, icon: AztecAppsStore.shared.icons[app.host]) { aztecApp(app) }
                        }
                    }
                    ForEach(yours, id: \.self) { name in
                        SourcesFolderApp(name: name, yours: true, needsYou: needs(name),
                                         settings: settings(name)) { open(name) }
                    }
                }
            }
            if !rest.isEmpty {
                group(String(localized: "Add")) {
                    ForEach(rest, id: \.self) { name in
                        SourcesFolderApp(name: name, yours: false, needsYou: false,
                                         settings: settings(name)) { open(name) }
                    }
                }
            }
        }
        .padding(.top, DS.Space.s1)
    }

    private func group<Cells: View>(_ title: String, @ViewBuilder cells: () -> Cells) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(verbatim: title)
                .dsText(.label12).foregroundStyle(DS.textSecondary)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: columns, alignment: .center, spacing: DS.Space.s4) {
                cells()
            }
        }
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

/// An Aztec app you have connected (prd §1757): its own icon over its name,
/// as any app of yours; its initials until the site's icon is read. A hold
/// offers Open and Remove: it is yours to take off the folder again.
private struct SourcesFolderAztecApp: View {
    let app: AztecAppsShape.App
    let icon: UIImage?
    let action: () -> Void

    private var side: CGFloat { DS.Face.seat + 12 }

    var body: some View {
        Button {
            DSHaptic.selection()
            action()
        } label: {
            VStack(spacing: DS.Space.s1) {
                Group {
                    if let icon {
                        Image(uiImage: icon).resizable().scaledToFill()
                            .frame(width: side, height: side)
                            .clipShape(RoundedRectangle(cornerRadius: side * 0.225, style: .continuous))
                    } else {
                        BridgeIcon(name: app.name, size: side)
                    }
                }
                Text(verbatim: app.name)
                    .dsText(.label12)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(app.name.contains(" ") ? 2 : 1)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressSpring())
        .contextMenu {
            Button(action: action) { Label("Open", systemImage: "arrow.up.forward.app") }
            Button(role: .destructive) {
                withAnimation(DS.Motion.standard) { AztecAppsStore.shared.remove(app.host) }
            } label: { Label("Remove", systemImage: "minus.circle") }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: app.name))
        .accessibilityAddTraits(.isButton)
    }
}

/// One app in an open folder: its icon over its name; one you could add
/// wears the pink plus, one of yours that needs you the amber dot. Under
/// Add an icon stands in full colour: the group's word says it is not yours.
private struct SourcesFolderApp: View {
    let name: String
    let yours: Bool
    let needsYou: Bool
    let settings: (() -> Void)?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: DS.Space.s1) {
                BridgeIcon(name: name, size: DS.Face.seat + 12)
                    .sourcesState(yours: true, needsYou: yours && needsYou, size: 14, ring: DS.surfaceRaised)
                    .sourcesAddBadge(!yours)
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
