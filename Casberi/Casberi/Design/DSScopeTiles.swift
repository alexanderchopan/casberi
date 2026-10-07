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
}

extension DSTileScope {
    static var readsInTime: Bool { false }
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
/// **The tile is the dock's category tile** — a 20pt glyph over the
/// `dockCaption10` word, 52pt tall, the tint fill on the pick — so a scope reads
/// as the same kind of thing as the folder that opened the room. A short last
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
    /// over word, the pick filled in tint — and an unpicked tile draws no
    /// fill, because the dock's don't: a row of ten grey squares is the plate
    /// §782 deleted.
    var strip: Bool = false
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
    let onPick: (Scope) -> Void

    /// The verb whose hold just fired. A `Button` still fires on the release
    /// that ends a long press, so the release after a hold is consumed here
    /// and never counted as the tap. Cleared by that release, or by a short
    /// window if no release reaches the button.
    @State private var held: Scope? = nil
    /// The verb tile a finger is resting on (prd §973), and the one that has
    /// rested long enough to arm — past a tap, before the hold lands.
    @GestureState private var pressing: Scope? = nil
    @State private var arming: Scope? = nil
    @State private var armTask: Task<Void, Never>? = nil
    /// Past a tap's length, short of the hold's 0.45s: long enough that a tap
    /// never flickers the glyph, short enough to be seen before the sheet.
    private static var armDelay: Duration { .milliseconds(180) }

    private static var columns: Int { 4 }
    private static var stripTileWidth: CGFloat { 52 }
    /// Frozen, like the dock's `CategoryGlyph`, so a wide symbol and a tall one
    /// seat the word at the same height.
    private static var glyphSize: CGFloat { 20 }
    /// **GLYPH OVER WORD, everywhere (user, 2026-09-26, reversing "remove
    /// the glyphs" within the hour: "we do need those glyphs b/c we have them
    /// elsewhere in the app, it's a language — the app categories, and in the
    /// rooms like github").** The glyphs are the app's one vocabulary for a
    /// section; a room's tiles speak it too.
    private static var tileHeight: CGFloat { 52 }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous)
    }

    var body: some View {
        if strip, !sections.isEmpty, sections.allSatisfy({ verbs.contains($0) }) {
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
        } else if sections.count > 1 {
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
            onPick(section)
        } label: {
            VStack(spacing: 2) {
                // The dock's glyph, bouncing once when its tile becomes the
                // pick — in the strip only, the one place these tiles ARE the
                // dock's (user, 2026-09-17). A room's scope grid stays still.
                CategoryGlyph(name: arming == section ? (hold?.glyph ?? section.glyph) : section.glyph,
                              size: Self.glyphSize, isActive: strip && isOn)
                // A section that wants you says so in its WORD's tone, never
                // a dot (user, 2026-09-24: "if we want yellow just make the
                // word Risk yellow"). The picked tile stays white on its tint.
                Text(section.label)
                    .dsText(.dockCaption10)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(isOn ? Color.white : isInert ? DS.textTertiary : wants ? DS.attentionInk : isVerb ? DS.tint : DS.textPrimary)
            }
            .foregroundStyle(isOn ? Color.white : isInert ? DS.textTertiary : isVerb ? DS.tint : DS.textPrimary)
            .frame(maxWidth: .infinity, minHeight: Self.tileHeight)
            // A disabled tile swaps its fill (§83), never only its ink.
            .background { shape.fill(isOn ? DS.tint : (strip ? Color.clear : DS.surfaceRaised.opacity(isInert ? 0.45 : 1))) }
            // **BECOMING THE PICK IS A CROSSFADE (prd §966).** The fill and the
            // ink ride the template's own clock, so a room whose pick handler
            // forgets `withAnimation` still slides the tint in under the
            // finger instead of snapping it on release.
            .animation(DS.Motion.standard, value: isOn)
            .contentShape(shape)
        }
        .buttonStyle(PressSpring())
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
