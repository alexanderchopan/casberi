import SwiftUI

/// A scope that can stand as a TILE: its word, with a glyph over it (prd §752).
/// A refinement rather than a new requirement on `DSSectionScope`, because the
/// directory screens and the person room scope with that protocol too and draw
/// words only.
protocol DSTileScope: DSSectionScope {
    /// An SF Symbol name. One table for the whole wallet family
    /// (`ScopeTileGlyph`), so a scope called Activity wears the same glyph in
    /// every room.
    var glyph: String { get }
    /// True when the scopes are SPANS OF TIME, which read in time, never A–Z
    /// (prd §999): Calendar's Today · Week · Month.
    static var readsInTime: Bool { get }
    /// True when the caller's order IS the meaning and must stand as given:
    /// a thing sheet's tiles, whose first is the thing's own act and whose
    /// last is always Share (prd §1178), never A–Z.
    static var keepsOrder: Bool { get }
}

extension DSTileScope {
    static var readsInTime: Bool { false }
    static var keepsOrder: Bool { false }
}

/// THE SCOPES AS TILES — under the head on Home and under the figure in every
/// section, so the grid is one control in one place on every page (prd §752,
/// 2026-09-15, user: "i don't want the app to have controls at the top of the
/// screen anywhere", then, between a strip and buttons, "the buttons seem more
/// utile").
///
/// Replaces `DSScopeHeader`, which put a back chevron and a sideways-scrolling
/// row of 22pt words at the top of the screen. Two things about that strip were
/// wrong, and a tile grid answers both:
///
/// - **Where it sat.** Top of the screen. The chrome now draws this BELOW the
///   scope's figure, where §547's bar sat: figure, tiles, list.
/// - **What it hid.** Wallet has eight scopes, and a strip scrolled to
///   Permissions pushed Activity and Holdings off the leading edge with no sign
///   they were there. Four columns show all eight at once; no room in the family
///   has more than eight, so this is never more than two rows.
///
/// **Home is a tile, and there is no back chevron.** Leaving a scope and moving
/// sideways are one act on a grid that shows both, so one control does both.
///
/// **The tile speaks at the page's volume** (prd §1336) — a 30pt semibold glyph
/// over a `tile15` word, 70pt tall, no backing; the pick fills its glyph and
/// takes the full ink, the rest stand in secondary ink. The row sits centred
/// between the box above and the list below (`dsRoomTilesListRow`). A short last
/// row is left-aligned, and every column is the same width in every room.
///
/// **Flat, never raised** (§752b). The first build gave each tile
/// `dsWidgetSurface` — the big cards' sheet fill, a 150pt pour and an 18pt
/// shadow — and eight of them side by side smeared into dark columns on the
/// device. A tile is a control on the page, like the dock's, so it takes one
/// flat `surfaceRaised` fill and nothing else.
///
/// **A room with one scope draws no grid** (§83): a single tile is a control
/// that offers nothing.
///
/// **It scrolls away with the page.** Pinning was tried in §495 and a plain
/// `List` section header does not hold a row-less section on screen; a scope
/// list is short in most rooms, so the cost is a flick back up.
struct DSScopeTiles<Scope: DSTileScope>: View {

    /// Every scope. The grid DRAWS them All/Home first, then A–Z, then the
    /// verbs (`alphabetical`); the strip draws them as given.
    let sections: [Scope]
    let active: Scope
    var attention: Set<Scope> = []
    /// One scrolling row of dock-width tiles instead of the four-column grid
    /// (Accounts' category strip, 2026-09-17: "just use the way the dock
    /// looks with the icons"). The dock's own anatomy — 52pt tiles, glyph
    /// over word, the pick filled in ink — and an unpicked tile draws no
    /// fill, because the dock's don't: a row of ten grey squares is the plate
    /// §782 deleted.
    var strip: Bool = false
    /// **THE GRID'S COLUMNS, SCROLLING (prd §1328, user: "should the icons
    /// in the Feed row … be same spacing the icons on the other rows are? i
    /// think so yes", "what would apple do").** Tiles one grid column wide,
    /// so they stand where every other room's row stands them, and a row
    /// longer than four scrolls sideways, the next tile peeking at the edge
    /// as Apple's shelves show there is more. Never wraps to a second row.
    var scrollsColumns: Bool = false
    /// The tiles that are VERBS, not scopes (the Notes room's New, prd
    /// §969): drawn in tint, never lit, and every tap fires — a verb has no
    /// "already picked".
    var verbs: Set<Scope> = []
    /// A verb tile's SECOND verb, reached by holding it (prd §970, §973): the
    /// Notes room's New, held, opens the note sheet recording. Nil, and a hold
    /// is a tap. Only a verb tile takes it — a scope has nothing a hold could
    /// mean.
    ///
    /// **A hold you can see, feel and reach (prd §973).** A finger resting on
    /// the tile past a tap ARMS it: the glyph morphs into `glyph` (the plus
    /// becomes the waveform), which says what holding will do before it does
    /// it. The hold lands with the LIFT buzz — the app's feel for picking
    /// something up by holding it — not the tap's. And VoiceOver, which cannot
    /// hold, gets the verb as a named action, `label`.
    struct Hold {
        let glyph: String
        let label: String
        let act: (Scope) -> Void
    }
    var hold: Hold? = nil
    /// **SCOPES THAT CAN HOLD NOTHING HERE (prd §1078, user: "do all the
    /// changes you suggested").** An app the Wallet's menu picked (a card, an
    /// exchange) has no positions, no risk and no grants: those belong to
    /// addresses. Such a tile stays in its place, because the tiles never
    /// move, and draws dimmed and disabled, because a tile onto a page that
    /// can never fill for this account is a dead control (§83). The picked
    /// tile is never inert.
    var inert: Set<Scope> = []
    /// **A ROW OF DOORS DRAWS NO BACKING AND NO PICK (prd §1252, user: "pink
    /// glyphs with … white words").** The Feed's and the Wallet's four open
    /// sheets on the phone (all but Feed and Home), so a lit tile only ever
    /// marked the page the title already names: glyph over word on the page,
    /// every glyph pink, every word in the page's ink. A room's own tiles
    /// switch in place and keep their pick.
    var bare: Bool = false
    /// Centred under a centred head (prd §1396, a money sheet's): fewer
    /// than a row of tiles stand in the middle at the grid's own column
    /// width, never flush left under a face in the middle of the sheet.
    var centered: Bool = false
    let onPick: (Scope) -> Void

    /// The verb whose hold just fired. A `Button` still fires on the release
    /// that ends a long press, so the release after a hold is consumed here
    /// and never counted as the tap. Cleared by that release, or by a short
    /// window if no release reaches the button.
    @State private var held: Scope? = nil
    /// Where each verb tile stands on screen, so what it opens can grow out
    /// of it (`DSTileOrigin`, prd §1199).
    @State private var verbFrames: [Scope: CGRect] = [:]
    /// A plus turns a quarter each time it is pressed (prd §1199).
    @State private var plusTurn: Double = 0
    /// Each tile's taps, so every tap bounces its glyph once (prd §1349):
    /// a glyph with a filled form showed the pick by morphing, and one
    /// without (Markets' chart, the Feed's jump tiles) answered nothing.
    @State private var taps: [Scope: Int] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The verb tile a finger is resting on (prd §973), and the one that has
    /// rested long enough to arm — past a tap, before the hold lands.
    @GestureState private var pressing: Scope? = nil
    @State private var arming: Scope? = nil
    @State private var armTask: Task<Void, Never>? = nil
    /// Past a tap's length, short of the hold's 0.45s: long enough that a tap
    /// never flickers the glyph, short enough to be seen before the sheet.
    private static var armDelay: Duration { .milliseconds(180) }

    private static var columns: Int { 4 }
    private static var stripTileWidth: CGFloat { 72 }
    /// Frozen, like the dock's `CategoryGlyph`, so a wide symbol and a tall one
    /// seat the word at the same height.
    private static var glyphSize: CGFloat { 30 }
    /// **THE PICK IS A LIFTED GREY, THE GLYPHS ARE PINK (prd §1252, user:
    /// "white words everywhere but pink glyphs", "pink on every").** Music's
    /// sidebar: every glyph in the hue, every word in the page's ink, the
    /// picked row one grey brighter. It was the page's ink with black words
    /// ("E1", 2026-10-10); the hue left the words for the glyphs.
    static var pickInk: Color { DS.textPrimary }
    static var glyphInk: Color { DS.brandInk }
    /// **GLYPH OVER WORD, everywhere (user, 2026-09-26, reversing "remove
    /// the glyphs" within the hour: "we do need those glyphs b/c we have them
    /// elsewhere in the app, it's a language — the app categories, and in the
    /// rooms like github").** The glyphs are the app's one vocabulary for a
    /// section; a room's tiles speak it too.
    private static var tileHeight: CGFloat { 70 }

    /// The boxes', the panels' and the glance tiles' corner (prd §1208l):
    /// one radius for every block on a page.
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous)
    }

    /// The column the scrolling row shows (`scrollsColumns`): the pick.
    @State private var shownColumn: Scope.ID?

    var body: some View {
        if scrollsColumns, sections.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s2) {
                    ForEach(sections) { section in
                        tile(section)
                            .containerRelativeFrame(.horizontal, count: Self.columns, spacing: DS.Space.s2)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollClipDisabled()
            // A row of four or fewer fits: it stands still under the finger.
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            // **THE PICK IS ON SCREEN (prd §1468):** a tile past the fourth
            // (the Wallet's Spending) landed hidden off the edge when a door
            // opened it; the row rolls to show it, clamped at the end.
            .scrollPosition(id: $shownColumn, anchor: .leading)
            .onChange(of: active.id, initial: true) { _, id in shownColumn = id }
        } else if strip, !sections.isEmpty, sections.allSatisfy({ verbs.contains($0) }) {
            // VERBS ALONE (prd §1138): Sources' Add · Search and Apps' Search,
            // whose filters are the counts in the box. Nothing scrolls.
            HStack(spacing: DS.Space.s1) {
                ForEach(sections) { section in
                    tile(section)
                        .frame(width: Self.stripTileWidth)
                }
            }
        } else if sections.count > 1, strip {
            // A VERB STANDS STILL AT THE STRIP'S END (prd §1081): the scopes
            // scroll, and a verb (Markets' Add) is pinned after them, so it
            // is never off the edge of a long row — a verb nobody can see is
            // a verb nobody can find.
            //
            // A row that FITS is as wide as its tiles (prd §1177, user: "make
            // this capsule shorter and get rid of the empty space between
            // voice and new"): the scroll view took every point it was
            // offered, so Notes' New stood at the far edge of an empty run.
            // Only a row too long for the bar scrolls.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Space.s1) {
                    ForEach(sections.filter { !verbs.contains($0) } + sections.filter { verbs.contains($0) }) { section in
                        tile(section)
                            .frame(width: Self.stripTileWidth)
                    }
                }
                HStack(spacing: DS.Space.s1) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Space.s1) {
                            ForEach(sections.filter { !verbs.contains($0) }) { section in
                                tile(section)
                                    .frame(width: Self.stripTileWidth)
                            }
                        }
                    }
                    // With a verb pinned after it, the scopes clip where the verb
                    // begins, or they slide under it.
                    .scrollClipDisabled(verbs.isEmpty)
                    ForEach(sections.filter { verbs.contains($0) }) { section in
                        tile(section)
                            .frame(width: Self.stripTileWidth)
                    }
                }
            }
        } else if sections.count > 1 || (!sections.isEmpty && sections.allSatisfy { verbs.contains($0) }) {
            // One VERB still draws (a sheet whose only act is Share, prd §1186);
            // one view alone is no choice, and draws nothing.
            // A full row needs no centring, and sized against the scroll
            // view's width it overflowed its inset and the sheet never
            // settled (a mail's four tiles, 2026-10-17).
            if centered, sections.count < Self.columns {
                HStack(spacing: DS.Space.s2) {
                    ForEach(Self.alphabetical(sections, verbs: verbs)) { section in
                        tile(section)
                            .containerRelativeFrame(.horizontal, count: Self.columns, spacing: DS.Space.s2)
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2),
                                         count: Self.columns),
                          alignment: .leading,
                          spacing: DS.Space.s2) {
                    ForEach(Self.alphabetical(sections, verbs: verbs)) { section in
                        tile(section)
                    }
                }
            }
        }
    }

    /// **A ROOM'S TILES READ A–Z (user, 2026-09-29: "for music rooms all
    /// tiles need to be alphabetical", then "that's a rule for any room").**
    /// Spans of time are the one exception (`readsInTime`, prd §999, user:
    /// "the tile order needs to be today week month new"): Month · Today ·
    /// Week is alphabetical and reads as nothing.
    /// All and the wallet family's Home stay first (user: leads stay), a
    /// verb (New) stays last because it is not a list, and everything
    /// between sorts by the word the person reads, in their language.
    /// **SEVERAL VERBS READ A–Z AMONG THEMSELVES (prd §1039)** — Reading
    /// carries two (Follow · Search), after every scope. A lead
    /// is known by its GLYPH: `tile-glyph-audit.py` holds every tile glyph
    /// to one meaning, so `ScopeTileGlyph.all` and `.home` can only be All
    /// and Home. Not "whatever is first": a room may list a scope first that
    /// is not a lead. The wallet family sorted this
    /// way already (`DSRoomScopeChrome.ordered`, prd §950); here it is the
    /// template's, so no room can forget it. The strip is exempt: it is a
    /// directory's categories, which keep the dock's own order.
    static func alphabetical(_ sections: [Scope], verbs: Set<Scope>) -> [Scope] {
        let isLead: (Scope) -> Bool = {
            // You's Today (`feed`, prd §1168) leads its four too; as "Home"
            // it led only because H sorts before M.
            $0.glyph == ScopeTileGlyph.all || $0.glyph == ScopeTileGlyph.home
                || $0.glyph == ScopeTileGlyph.feed
        }
        let leads = sections.filter(isLead)
        let tail = sections.filter { !isLead($0) && verbs.contains($0) }
        let middle = sections.filter { !isLead($0) && !verbs.contains($0) }
        guard !Scope.keepsOrder else { return sections }
        guard !Scope.readsInTime else { return leads + middle + tail }
        let byWord: (Scope, Scope) -> Bool = {
            $0.label.localizedStandardCompare($1.label) == .orderedAscending
        }
        return leads + middle.sorted(by: byWord) + tail.sorted(by: byWord)
    }

    @ViewBuilder
    private func tile(_ section: Scope) -> some View {
        let isVerb = verbs.contains(section)
        let isOn = section == active && !isVerb
        let isInert = inert.contains(section) && !isOn
        let wants = attention.contains(section) && !isInert
        Button {
            if held == section { held = nil; return }
            guard !isOn else { return }
            DSHaptic.selection()
            if !reduceMotion, section.glyph != "plus" { taps[section, default: 0] += 1 }
            if isVerb, let frame = verbFrames[section] {
                DSTileOrigin.mark(CGPoint(x: frame.midX, y: frame.midY))
                if section.glyph == "plus", !reduceMotion {
                    withAnimation(DS.Motion.press) { plusTurn += 90 }
                }
            }
            onPick(section)
        } label: {
            VStack(spacing: 2) {
                // The dock's glyph, bouncing once when its tile becomes the
                // pick — in the strip only, the one place these tiles ARE the
                // dock's (user, 2026-09-17). A room's scope grid stays still.
                // **THE PICK FILLS ITS GLYPH (prd §1336)**, as a tab bar
                // marks where you are; the rest stay drawn in line.
                CategoryGlyph(name: arming == section ? (hold?.glyph ?? section.glyph) : section.glyph,
                              size: Self.glyphSize, isActive: strip && isOn,
                              tapped: taps[section] ?? 0)
                    .symbolVariant(isOn ? .fill : .none)
                    .rotationEffect(.degrees(isVerb && section.glyph == "plus" ? plusTurn : 0))
                // A section that wants you says so in its WORD's tone, never
                // a dot (user, 2026-09-24: "if we want yellow just make the
                // word Risk yellow"). The picked tile keeps its pick ink.
                Text(section.label)
                    .dsText(.tile15)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    // NO TILE HAS A BACKING (prd §1267, user: "no backing"): a
                    // row of doors draws every word white; a row that switches
                    // in place says its pick in the word — white, the rest
                    // grey — and a verb's word stays white.
                    .foregroundStyle(isOn ? Self.pickInk
                                     : isInert ? DS.textTertiary.opacity(0.6)
                                     : wants ? DS.attentionInk
                                     : (bare || isVerb) ? DS.textPrimary : DS.textTertiary)
            }
            .foregroundStyle(isInert ? DS.textTertiary.opacity(0.6) : Self.glyphInk)
            .frame(maxWidth: .infinity, minHeight: Self.tileHeight)
            // A disabled tile swaps its fill (§83), never only its ink.
            // No fill, picked or not (prd §1267): an inert tile is dimmed
            // glyph and word and disabled, which is the §83 answer without
            // a plate.
            // **BECOMING THE PICK IS A CROSSFADE (prd §966).** The fill and the
            // ink ride the template's own clock, so a room whose pick handler
            // forgets `withAnimation` still slides the tint in under the
            // finger instead of snapping it on release.
            .animation(DS.Motion.standard, value: isOn)
            .contentShape(shape)
        }
        .buttonStyle(PressSpring())
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            if isVerb { verbFrames[section] = frame }
        }
        .disabled(isInert)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .updating($pressing) { down, state, _ in
                    state = (down && isVerb && hold != nil) ? section : nil
                }
                .onEnded { _ in
                    guard isVerb, let hold else { return }
                    held = section
                    DSHaptic.lift()
                    hold.act(section)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        if held == section { held = nil }
                    }
                },
            // **ONLY A TILE THAT HOLDS SOMETHING LISTENS FOR A HOLD
            // (2026-09-28, user: "the categories aren't scrolling").** A
            // long press on every tile of the strip took the finger from the
            // horizontal scroll view, so the capsule on Accounts, Addresses,
            // Settings and What this app reaches never scrolled and every
            // tile past the sixth (Wallet, there) was out of reach. Only the
            // Notes room's New carries a hold; `.subviews` keeps the tile's
            // own Button live everywhere else.
            including: (isVerb && hold != nil) ? .all : .subviews
        )
        // ARMING (prd §973): a finger still down past a tap's length morphs
        // the glyph; lifting early, or the hold landing, morphs it back.
        .onChange(of: pressing == section) { _, down in
            guard isVerb, hold != nil else { return }
            armTask?.cancel()
            guard down else { arming = nil; return }
            armTask = Task { @MainActor in
                try? await Task.sleep(for: Self.armDelay)
                if !Task.isCancelled { arming = section }
            }
        }
        .accessibilityActions {
            if isVerb, let hold {
                Button(hold.label) { hold.act(section) }
            }
        }
        .dsHover()
        .accessibilityLabel(wants
                            ? Text("\(section.label), \(section.summary), needs you")
                            : Text("\(section.label), \(section.summary)"))
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .dsTooltip(section.summary)
    }
}
