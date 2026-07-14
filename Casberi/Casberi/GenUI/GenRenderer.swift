import SwiftUI
import SwiftData
import Photos
import CoreImage

/// The gen UI renderer — recursive over the element map, faithful to the v94
/// prototype's RenderEl. A missing reference renders a skeleton in a row/tile
/// slot and drops elsewhere (the skeleton/drop laws).
///
/// Fidelity note (flagged): the prototype renders widgets and tiles at radius
/// 20 while brief §8 says cards 10. Fidelity to the visual spec won at review;
/// the value routes through `DS.Radius.widget` so the ruling is one line.
extension DS.Radius {
    /// Widget/tile surface radius per the v94 prototype (§8 conflict flagged).
    static let widget: CGFloat = 20
}

enum GenSlot { case none, row, tile }

/// Tap routes out of the renderer — the prototype's `projectTap`/`tagTap`.
/// Surfaces provide these; components stay dumb.
private struct GenProjectTapKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}
extension EnvironmentValues {
    var genProjectTap: ((String) -> Void)? {
        get { self[GenProjectTapKey.self] }
        set { self[GenProjectTapKey.self] = newValue }
    }
    var genZoomNS: Namespace.ID? {
        get { self[GenZoomNSKey.self] }
        set { self[GenZoomNSKey.self] = newValue }
    }
    /// A pinned row's tap → open the thing (the surface resolves the id
    /// and presents the sheet). nil outside Home.
    var genThingOpen: ((String) -> Void)? {
        get { self[GenThingOpenKey.self] }
        set { self[GenThingOpenKey.self] = newValue }
    }
    /// A pinned row's "Open in app" — the real hand-off to the thing's
    /// source (calshow://, the link, …). nil outside Home.
    var genThingHandoff: ((String) -> Void)? {
        get { self[GenThingHandoffKey.self] }
        set { self[GenThingHandoffKey.self] = newValue }
    }
    /// "Remove from Home" for the pinned APP tile a row lives in — set by
    /// GenWidget for its children so a long-press on ANY row can drop the whole
    /// app (each row carries its own contextMenu, which would otherwise shadow
    /// the card's). nil off a pinned tile.
    var genAppRemove: (() -> Void)? {
        get { self[GenAppRemoveKey.self] }
        set { self[GenAppRemoveKey.self] = newValue }
    }
    /// The screen's top safe-area inset — the cover is full-bleed, so its
    /// date eyebrow needs the clearance the surface measured.
    var genCoverTopInset: CGFloat {
        get { self[GenCoverTopInsetKey.self] }
        set { self[GenCoverTopInsetKey.self] = newValue }
    }
    /// True while a prose answer is still arriving — the Insight carries a
    /// breathing dot after its last character (§2 polish).
    var genProseStreaming: Bool {
        get { self[GenProseStreamingKey.self] }
        set { self[GenProseStreamingKey.self] = newValue }
    }
    /// True on a live answer's tree — cited rows glint once on mount.
    var genCitationGlint: Bool {
        get { self[GenCitationGlintKey.self] }
        set { self[GenCitationGlintKey.self] = newValue }
    }
    /// Bumped by Home's pull-to-refresh — live modules (token charts) key
    /// their fetch on it so a pull re-fetches what a recompose alone
    /// wouldn't (same doc line → same task id → no refetch).
    var genRefreshTick: Int {
        get { self[GenRefreshTickKey.self] }
        set { self[GenRefreshTickKey.self] = newValue }
    }
    /// True while the board module currently rendering is in its LARGE
    /// state (prd 58a) — set per top-level card by the surface (HomeScreen
    /// scopes it to each board ref); descendants inherit it, so a pinned
    /// row rendered inside a large Widget sees the same flag. false (and a
    /// no-op) outside Home.
    var genModuleLarge: Bool {
        get { self[GenModuleLargeKey.self] }
        set { self[GenModuleLargeKey.self] = newValue }
    }
    /// Tap-the-pin (prd 58a): the pin on any board module is a button —
    /// tap toggles that module between regular and large. nil outside Home.
    var genSizeToggle: ((String) -> Void)? {
        get { self[GenSizeToggleKey.self] }
        set { self[GenSizeToggleKey.self] = newValue }
    }
    /// A pinned media shelf's "Remove from Home" (long-press) — the surface
    /// drops that source's pin (and its saved size/order) and recomposes.
    /// Takes the shelf's ref id. nil outside Home.
    var genSourceUnpin: ((String) -> Void)? {
        get { self[GenSourceUnpinKey.self] }
        set { self[GenSourceUnpinKey.self] = newValue }
    }
    /// A screenshot's own stored thumbnail bytes (prd 48) — local, not a
    /// URL, so a media tile resolves it by thing id rather than a doc-line
    /// image ref. nil outside Home.
    var genThumbnailData: ((String) -> Data?)? {
        get { self[GenThumbnailDataKey.self] }
        set { self[GenThumbnailDataKey.self] = newValue }
    }
    /// True when a media module renders as a HALF-WIDTH tile in a magazine
    /// pair row (prd 58f) — a single art tile, not the scrolling shelf. Set
    /// per-tile by MagazineBoard; false everywhere else (the full-width
    /// shelf/hero is the default).
    var genMediaCompact: Bool {
        get { self[GenMediaCompactKey.self] }
        set { self[GenMediaCompactKey.self] = newValue }
    }
    /// The board tile's span (prd 58h bento) — small / wide / big — set per
    /// module by HomeScreen and inherited by descendants (a pinned row reads
    /// its card's span). nil off the board (Feed, sheets), where a module
    /// renders its plain form. `genModuleLarge` / `genMediaCompact` are derived
    /// from this for the existing two-state renderers; a module reads `genSpan`
    /// directly only where it needs a distinct SMALL (1×1) form.
    var genSpan: ModuleSpan? {
        get { self[GenSpanKey.self] }
        set { self[GenSpanKey.self] = newValue }
    }
}

private struct GenSpanKey: EnvironmentKey {
    static let defaultValue: ModuleSpan? = nil
}

private struct GenMediaCompactKey: EnvironmentKey {
    static let defaultValue = false
}

private struct GenProseStreamingKey: EnvironmentKey {
    static let defaultValue = false
}

/// Set true on a LIVE answer's render tree only: rows the answer cites glint
/// once as they mount — "I went and found these" as a gesture, never
/// replayed on scroll-back (delight 2026-07-13).
private struct GenCitationGlintKey: EnvironmentKey {
    static let defaultValue = false
}

private struct GenCoverTopInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}
private struct GenThingOpenKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}
private struct GenThingHandoffKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}
private struct GenAppRemoveKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}
private struct GenRefreshTickKey: EnvironmentKey {
    static let defaultValue = 0
}
private struct GenModuleLargeKey: EnvironmentKey {
    static let defaultValue = false
}
private struct GenSizeToggleKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}
private struct GenSourceUnpinKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}
private struct GenThumbnailDataKey: EnvironmentKey {
    static let defaultValue: ((String) -> Data?)? = nil
}

private struct GenZoomNSKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension View {
    /// Marks a zoom-transition source when the surface provides a namespace.
    @ViewBuilder
    func zoomSource(id: some Hashable, in ns: Namespace.ID?) -> some View {
        if let ns { matchedTransitionSource(id: id, in: ns) } else { self }
    }
}

struct GenRender: View {
    let id: String
    let els: GenEls
    var slot: GenSlot = .none

    var body: some View {
        // AnyView is load-bearing (2026-07-06 crash fix): the component
        // switch nests recursively (Stack → Widget → rows...), and without
        // erasure the combined generic type got deep enough that
        // instantiating its metadata overflowed the stack — an intermittent
        // SIGSEGV ("excessive recursion") on first render of a new branch
        // combination, seen when pushing a project during onboarding demo.
        // Erasing at every nesting level keeps the type flat forever.
        if let el = els[id] {
            AnyView(component(el))
        } else {
            switch slot {
            case .row:  GenSkeletonRow().mountIn()
            case .tile: GenSkeletonTile().mountIn()
            case .none: EmptyView()   // unresolved refs drop
            }
        }
    }

    @ViewBuilder
    private func component(_ el: GenEl) -> some View {
        switch el.comp {
        case "Stack":
            ForEach(el.refs(0), id: \.self) { GenRender(id: $0, els: els) }

        case "Hero":        GenHero(el: el).mountIn()
        case "Cover":       GenCover(el: el).mountIn()
        case "KindPills":   GenKindPills(el: el).mountIn()
        case "Insight":     GenInsight(el: el).mountIn()
        case "Widget":      GenWidget(id: id, el: el, els: els).mountIn()
        case "Row":         GenRow(id: id, el: el).mountIn()
        case "TokenChip":   GenTokenChip(el: el).mountIn()
        case "Suggest":     GenSuggest().mountIn()
        case "Skeleton":    GenSkeletonRow().mountIn()
        case "Chip":        GenChip(el: el).mountIn()
        case "Tile":        GenTile(el: el).mountIn()
        case "ProjectTile": GenProjectTile(el: el).mountIn()
        case "PhotoTile":   GenPhotoTile(el: el).mountIn()
        case "VoiceTile":   GenVoiceTile(el: el).mountIn()
        case "TagMap":
            #if DEBUG
            // MOCK (-homeTitles YES): "Holdings" above the first wallet
            // map; the week map keeps its in-card title for contrast.
            if UserDefaults.standard.bool(forKey: "homeTitles"),
               el.str(0).hasPrefix("@pin "), el.str(3) == "token" {
                Text("Holdings")
                    .dsText(.heading22)
                    .foregroundStyle(DS.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, DS.Space.s2)
            }
            #endif
            GenTagMap(id: id, el: el).mountIn()
        // The starter shape: same geometry, muted fill, nothing to tap — an
        // honest preview of the map that composes once things land.
        case "TagMapPreview": GenTagMap(id: id, el: el, preview: true).mountIn()
        // A quiet day's slot is a DOOR now, not a logo (2026-07-10, user:
        // the berry under a quiet cover was saying quiet twice and doing
        // nothing) — connect more apps and quiet days get rarer.
        case "AppsInvite":  GenAppsInvite(el: el).mountIn()
        // Rich module interiors (prd 58, Goal 3) — music/Pinterest/
        // screenshots (a source's own image strip) and a social source's
        // single latest post. Board members exactly like pinned/wallet/map:
        // draggable (Goal 1), sizable via the same pin (Goal 2).
        case "MediaShelf":  GenMediaShelf(id: id, el: el, els: els).mountIn()
        // One retiring teaching line (Feed's coach grammar) — plain tinted
        // words, no overlays, no arrows.
        case "Coach":       GenCoach(el: el).mountIn()
        case "KindBar":     GenKindBar(el: el).mountIn()

        // Shaped-feed grammar (docs/handoff-shaped-feeds.md) — display forms
        // of the shaped rows, so compositions can paint them; the interactive
        // twins live in Screens/ShapedRows.swift and belong to the List.
        case "TxRow":        GenTxRow(el: el).mountIn()
        case "AgendaRow":    GenAgendaRow(el: el).mountIn()
        case "MailRow":      GenMailRow(el: el).mountIn()
        case "PostRow":      GenPostRow(el: el).mountIn()
        case "TakeawayCard": GenTakeawayCard(el: el).mountIn()
        case "ApprovalCard": GenApprovalCard(el: el).mountIn()

        case "Shelf":
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s2) {
                    ForEach(el.refs(0), id: \.self) { GenRender(id: $0, els: els) }
                }
                .padding(.horizontal, DS.Space.s4)
            }

        case "Bento":
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: DS.Space.s3),
                          GridItem(.flexible(), spacing: DS.Space.s3)],
                spacing: DS.Space.s3
            ) {
                ForEach(el.refs(0), id: \.self) { child in
                    GenRender(id: child, els: els, slot: .tile)
                        .gridSpan(els[child].map { $0.str(0) == "2" } ?? false)
                }
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s4)

        default:
            EmptyView()
        }
    }
}

// MARK: - Mount animation (prototype `.mount`: 180ms rise 3px + fade)

private struct MountIn: ViewModifier {
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 3)
            .onAppear {
                withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.18)) {
                    shown = true
                }
            }
    }
}

private struct GridSpan: ViewModifier {
    let span2: Bool
    func body(content: Content) -> some View {
        // LazyVGrid has no native span; span-2 tiles get full-width treatment
        // by the composition placing them in their own Bento.
        content
    }
}

extension View {
    func mountIn() -> some View { modifier(MountIn()) }
    fileprivate func gridSpan(_ span2: Bool) -> some View { modifier(GridSpan(span2: span2)) }
}

// MARK: - Components

/// Hero(eyebrow, title, subline) — the one place color breathes (ruling
/// 2026-07-05): a soft radial wash behind the hero, the person's accent
/// warmed by the hour (dawn leans amber, evening leans indigo). The
/// composition below stays on the quiet page.
private struct GenHero: View {
    let el: GenEl
    /// Home's scroll ignores the top safe area (the cover bleeds); the quiet
    /// hero must clear it — plus the floating doors pill — itself.
    @Environment(\.genCoverTopInset) private var topInset

    private var field: Color {
        let hour = Calendar.current.component(.hour, from: .now)
        let warm: Color = hour < 12 ? Color(hex: "#ff9f0a")
                        : hour < 17 ? DS.tint
                        : Color(hex: "#5e5ce6")
        return DS.tint.mix(with: warm, by: 0.35)
    }

    var body: some View {
        heroBody
            .background(alignment: .topLeading) {
                RadialGradient(
                    colors: [field.opacity(0.28), .clear],
                    center: .topLeading,
                    startRadius: 0, endRadius: 340
                )
                .padding(.top, -60)
                .padding(.leading, -40)
            }
    }

    private var heroBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(el.str(0))
                .dsText(.label12)
                .foregroundStyle(DS.textSecondary)
            Text(el.str(1))
                .dsText(.heading34)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s2)
                .padding(.bottom, DS.Space.s1)
            Text(el.str(2))
                .dsText(.callout15)
                .foregroundStyle(DS.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // topInset clears the status bar; s8 + 24 clears the doors pill row
        // so the headline never runs beneath it.
        .padding(.init(top: topInset + DS.Space.s8 + 24, leading: DS.Space.s4,
                       bottom: DS.Space.s6, trailing: DS.Space.s4))
    }
}

/// Insight(text) — the one cross-source connection, "Noticed" eyebrow.
private struct GenInsight: View {
    let el: GenEl
    @Environment(\.genProseStreaming) private var streaming

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text("Noticed")
                .dsText(.label12)
                .foregroundStyle(DS.textSecondary)
            if streaming {
                // The model is still writing — one small dot breathes after
                // the last character. No shimmer, no skeleton (§2).
                TimelineView(.animation) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    let phase = (sin(t * 2 * .pi) + 1) / 2
                    (Text(el.str(0))
                     + Text(" ●")
                        .font(.system(size: 9))
                        .foregroundStyle(DS.tint.opacity(0.3 + 0.7 * phase)))
                        .dsText(.callout15)
                        .foregroundStyle(DS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(el.str(0))
                    .dsText(.callout15)
                    .foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.s4)
        .background(DS.tintDim, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s4)
    }
}

/// Widget(title, subline, [rowRefs], source?) — a titled card of rows. Off the
/// board (store previews) it's a plain display card. On Home, arg 3 names the
/// pinned SOURCE the card stands for (2026-07-12): the card becomes a board
/// module, sized by the same corner pin every tile wears, removable via
/// long-press "Remove from Home" (which drops that source's pin) — and now
/// (2026-07-14) it takes all three spans, not just wide/big: `big` is a card
/// of THREE items, `wide` a card of ONE item as a line, `small` a 1×1 tile
/// rendering that ONE item full-size (`SoloRowTile` etc. below) — never a row
/// cramped into a square, which is what truncated a token's own symbol.
private struct GenWidget: View {
    let id: String
    let el: GenEl
    let els: GenEls
    @Environment(\.genSpan) private var span
    @Environment(\.genSizeToggle) private var sizeToggle
    @Environment(\.genSourceUnpin) private var sourceUnpin

    /// arg 3 — the pinned source this tile stands for; empty off the board.
    private var source: String { el.str(3) }
    private var pinned: Bool { !source.isEmpty }
    /// Grown tiles show more of the app; a wide tile stays a one-line peek.
    private var rowRefs: [String] {
        let all = el.refs(2)
        guard pinned else { return all }
        return Array(all.prefix(span == .some(.big) ? 3 : 1))
    }

    var body: some View {
        // A pinned tile at SMALL is its own square — the multi-row card
        // chrome (header + list) never fits a readable row into a 1×1 seat,
        // so it renders its one most recent item full-size instead. Its own
        // pinnedRowActions() already offers Remove from Home, so no outer
        // contextMenu here — a second one would just be shadowed by it, the
        // same bug fixed for the card's own rows.
        if pinned, span == .some(.small) {
            soloContent
                .environment(\.genAppRemove) { sourceUnpin?(id) }
        } else if pinned, let sourceUnpin {
            card.contextMenu {
                Button(role: .destructive) {
                    sourceUnpin(id)
                } label: {
                    Label("Remove from Home", systemImage: "pin.slash")
                }
            }
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text(LocalizedStringKey(el.str(0))).dsText(.heading22).foregroundStyle(DS.textPrimary)
                if !el.str(1).isEmpty {
                    Text(el.str(1)).dsText(.callout15).foregroundStyle(DS.textTertiary)
                        .contentTransition(.numericText())
                        .animation(DS.Motion.standard, value: el.str(1))
                }
                if pinned, let sizeToggle {
                    Spacer(minLength: DS.Space.s2)
                    ShelfSizePin(large: span == .some(.big)) { sizeToggle(id) }
                        // Same top-right corner, same 44pt hit box overflowing
                        // the header padding, as every other module's size pin.
                        .padding(.top, -12).padding(.trailing, -12)
                }
            }
            .padding(.init(top: DS.Space.s4, leading: DS.Space.s4,
                           bottom: DS.Space.s1, trailing: DS.Space.s4))
            // A pinned tile's rows are lines within the card — reset the board
            // span so a Row renders its lineForm, not its own square tile — and
            // carry the tile's "Remove from Home" so a long-press on any row can
            // drop the app (each row's own contextMenu shadows the card's).
            ForEach(rowRefs, id: \.self) {
                GenRender(id: $0, els: els, slot: .row)
                    .environment(\.genSpan, pinned ? ModuleSpan?.none : span)
                    .environment(\.genAppRemove, pinned ? { sourceUnpin?(id) } : nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, DS.Space.s2)
        .dsWidgetSurface()
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s4)
    }

    /// The small-span solo tile — dispatches on the one child's component so
    /// each kind renders in its own full shape (a token's symbol full-width,
    /// a post's avatar, a mail's snippet), not a squeezed generic line.
    @ViewBuilder private var soloContent: some View {
        if let ref = el.refs(2).first, let childEl = els[ref] {
            switch childEl.comp {
            case "Row":       SoloRowTile(widgetID: id, el: childEl)
            case "MailRow":   SoloMailTile(widgetID: id, el: childEl)
            case "PostRow":   SoloPostTile(widgetID: id, el: childEl)
            case "TokenChip": SoloTokenTile(widgetID: id, el: childEl)
            default:          GenSkeletonTile()
            }
        } else {
            GenSkeletonTile()
        }
    }
}

/// The 1×1 solo-tile chrome shared by the four `Solo*Tile` forms below — the
/// same sheet-square surface every other small board tile wears. Small tiles
/// are inset and top-gapped by the board's packer (not here), and stretch to
/// their row-mate's height so a paired 1×1 never under-fills raggedly.
private extension View {
    func soloTileChrome() -> some View {
        self
            .padding(DS.Space.s4)
            .frame(maxWidth: .infinity, minHeight: 150, maxHeight: .infinity, alignment: .topLeading)
            .dsWidgetSurface()
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
    }
}

/// A pinned Row (everything without a bespoke shape — Reminders, Calendar,
/// GitHub, Linear, …) as a solo 1×1 tile: icon, the title given its full
/// height (up to 3 lines, never truncated to a fragment), source · time below.
private struct SoloRowTile: View {
    let widgetID: String
    let el: GenEl
    @Environment(\.genThingOpen) private var thingOpen
    @Environment(\.genThingHandoff) private var thingHandoff
    @Environment(\.genSizeToggle) private var sizeToggle
    @Environment(\.genAppRemove) private var appRemove

    var body: some View {
        let sub = [el.str(2), el.str(3)].filter { !$0.isEmpty }.joined(separator: " · ")
        let content = VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(alignment: .top, spacing: 0) {
                TagGlyph(tag: el.str(1), size: 26)
                Spacer(minLength: 0)
                if let sizeToggle {
                    ShelfSizePin(large: false) { sizeToggle(widgetID) }
                        .padding(.top, -12).padding(.trailing, -12)
                }
            }
            Spacer(minLength: 0)
            Text(el.str(0))
                .dsText(.body17).foregroundStyle(DS.textPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if !sub.isEmpty {
                Text(sub).dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .soloTileChrome()
        return content.pinnedRowActions(id: el.str(4), openable: el.str(5) == "app",
                                        open: thingOpen, unpin: nil, handoff: thingHandoff,
                                        removeApp: appRemove)
    }
}

/// A pinned Gmail/iCloud Mail thing as a solo 1×1 tile: subject and snippet
/// given room to breathe, instead of a one-line-each list row.
private struct SoloMailTile: View {
    let widgetID: String
    let el: GenEl
    @Environment(\.genThingOpen) private var thingOpen
    @Environment(\.genThingHandoff) private var thingHandoff
    @Environment(\.genSizeToggle) private var sizeToggle
    @Environment(\.genAppRemove) private var appRemove

    var body: some View {
        let content = VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(alignment: .top, spacing: 0) {
                KindGlyph(kind: .mail, size: 26)
                Spacer(minLength: 0)
                if let sizeToggle {
                    ShelfSizePin(large: false) { sizeToggle(widgetID) }
                        .padding(.top, -12).padding(.trailing, -12)
                }
            }
            Spacer(minLength: 0)
            Text(el.str(0)).dsText(.body17).foregroundStyle(DS.textPrimary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            if !el.str(1).isEmpty {
                Text(el.str(1)).dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            if !el.str(2).isEmpty {
                Text(el.str(2)).dsText(.subhead13).foregroundStyle(DS.textTertiary)
            }
        }
        .soloTileChrome()
        return content.pinnedRowActions(id: el.str(3), openable: el.str(4) == "app",
                                        open: thingOpen, unpin: nil, handoff: thingHandoff,
                                        removeApp: appRemove)
    }
}

/// A pinned Bluesky/Farcaster post as a solo 1×1 tile: the author's own
/// avatar and handle up top, the post's full text below — the same idiom
/// the old single-post card carried, now the tile's small form.
private struct SoloPostTile: View {
    let widgetID: String
    let el: GenEl
    @Environment(\.genThingOpen) private var thingOpen
    @Environment(\.genThingHandoff) private var thingHandoff
    @Environment(\.genSizeToggle) private var sizeToggle
    @Environment(\.genAppRemove) private var appRemove

    var body: some View {
        let content = VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(spacing: 7) {
                RemoteThumb(urlString: el.str(2), size: 26, fallback: el.str(0), circular: true)
                if !el.str(0).isEmpty {
                    Text(el.str(0)).dsText(.subhead13).foregroundStyle(DS.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let sizeToggle {
                    ShelfSizePin(large: false) { sizeToggle(widgetID) }
                        .padding(.top, -12).padding(.trailing, -12)
                }
            }
            Spacer(minLength: 0)
            Text(el.str(1)).dsText(.body17).foregroundStyle(DS.textPrimary)
                .lineLimit(4).fixedSize(horizontal: false, vertical: true)
        }
        .soloTileChrome()
        return content.pinnedRowActions(id: el.str(3), openable: el.str(4) == "app",
                                        open: thingOpen, unpin: nil, handoff: thingHandoff,
                                        removeApp: appRemove)
    }
}

/// A pinned Tokens-bridge token as a solo 1×1 tile — the layout that actually
/// motivated small-span support (2026-07-14): the symbol gets its OWN full-
/// width line, never sharing horizontal space with the plot or price the way
/// the list row does, so "ETH" (or any symbol) never truncates. Plot and
/// price/delta stack below it.
private struct SoloTokenTile: View {
    let widgetID: String
    let el: GenEl
    @State private var chart: TokenChart?
    @State private var revealed = false
    @Environment(\.genThingOpen) private var thingOpen
    @Environment(\.genThingHandoff) private var thingHandoff
    @Environment(\.genSizeToggle) private var sizeToggle
    @Environment(\.genAppRemove) private var appRemove
    @Environment(\.genRefreshTick) private var refreshTick
    @Environment(\.colorScheme) private var scheme

    private var symbol: String { el.str(0) }
    private var accent: Color {
        TokenChartStyle.accent(up: (chart?.change ?? 0) >= 0, scheme: scheme)
    }

    var body: some View {
        let content = VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(alignment: .top, spacing: DS.Space.s2) {
                Text(symbol).dsText(.callout15).foregroundStyle(DS.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let sizeToggle {
                    ShelfSizePin(large: false) { sizeToggle(widgetID) }
                        .padding(.top, -12).padding(.trailing, -12)
                }
            }
            Spacer(minLength: DS.Space.s2)
            plot
            if let chart {
                HStack(spacing: DS.Space.s2) {
                    Text(TokenChartStyle.priceText(chart.price))
                        .dsText(.subhead13).foregroundStyle(DS.textPrimary)
                        .contentTransition(.numericText())
                    TokenDeltaPill(change: chart.change, label: "1D", compact: true)
                }
            }
        }
        .soloTileChrome()
        .task(id: "\(refreshTick):\(el.str(1))/\(el.str(2))") {
            guard !el.str(1).isEmpty, !el.str(2).isEmpty else { return }
            revealed = false
            chart = await TokenChart.fetch(chain: el.str(1), address: el.str(2))
            if chart != nil { withAnimation(.easeOut(duration: 0.7)) { revealed = true } }
        }
        return content.pinnedRowActions(id: el.str(3), openable: el.str(4) == "app",
                                        open: thingOpen, unpin: nil, handoff: thingHandoff,
                                        removeApp: appRemove)
    }

    @ViewBuilder private var plot: some View {
        if let chart {
            TokenChartPlot(chart: chart, accent: accent, height: 40, pulses: false)
                .mask(alignment: .leading) {
                    GeometryReader { geo in
                        Rectangle().frame(width: revealed ? geo.size.width : 0)
                    }
                }
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(DS.surfaceWell).frame(height: 40)
        }
    }
}

/// The media/shelf size control (prd 58a) — the same pin idiom as the Pinned
/// card, sized as a secondary corner control. A tap cycles the module's span
/// (small → wide → big). The glyph reads at 15pt for discoverability, but the
/// button ALWAYS carries a full 44×44 hit target (Apple HIG minimum) via a
/// framed content shape — the old 11pt inline pins were ~11pt targets, which
/// is why the music and screenshot shelves were near-impossible to resize
/// (user, 2026-07-12). Negative padding lets the 44pt hit box overflow into
/// the surrounding whitespace, so a comfortable target costs no visible bulk.
/// `onImage` styles it white-with-shadow for a full-bleed corner.
private struct ShelfSizePin: View {
    var large: Bool
    var onImage: Bool = false
    var onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            Image(systemName: "pin.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(onImage ? AnyShapeStyle(.white.opacity(0.95))
                                         : AnyShapeStyle(DS.textSecondary))
                .rotationEffect(.degrees(-35))
                .shadow(color: onImage ? .black.opacity(0.4) : .clear,
                        radius: onImage ? 3 : 0)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(large ? "Shrink" : "Grow")
    }
}

/// MediaShelf(eyebrow, subline, [itemRefs], kind) — a source's own image
/// strip (regular) or grid/full-bleed (large): music album art, Pinterest
/// pins, screenshot thumbnails (prd 58, Goal 3). Same pin, same drag, same
/// row actions as every other board module — only the interior is source-
/// shaped. `kind` ∈ "music" | "pinterest" | "screenshot": music alone goes
/// full-bleed large (prd 58's literal wording); the other two grow into a
/// moodboard grid, the same idiom the pinned card's large form uses.
private struct GenMediaShelf: View {
    let id: String
    let el: GenEl
    let els: GenEls
    @Environment(\.genModuleLarge) private var large
    @Environment(\.genSizeToggle) private var sizeToggle
    @Environment(\.genSourceUnpin) private var sourceUnpin
    @Environment(\.genMediaCompact) private var compact

    private var kind: String { el.str(3) }
    private var refs: [String] { el.refs(2) }
    /// The shelf is on the board by an explicit pin (arg 5) — only then can it
    /// be removed from Home here (an auto-earned shelf has no pin to drop).
    private var pinned: Bool { el.str(4) == "pin" }

    var body: some View {
        // Half-width magazine tile (prd 58f): the lead item's art fills a
        // single tile with the shelf's eyebrow over a scrim — no scrolling
        // strip in a pair cell. The pin still rides the corner (tap = grow,
        // which pops it to the full-bleed row).
        let base = Group {
            if compact {
                GenMediaCompactTile(id: id, eyebrow: el.str(0), leadRef: refs.first,
                                    els: els, sizeToggle: sizeToggle)
            } else {
                shelf
            }
        }
        // Long-press to remove a PINNED shelf from Home — the shelf's parallel
        // to a pinned row's "Unpin" (the corner pin means resize, so removal
        // needs its own verb). Absent for auto-earned shelves (no pin to drop).
        if pinned, let sourceUnpin {
            base.contextMenu {
                Button(role: .destructive) {
                    sourceUnpin(id)
                } label: {
                    Label("Remove from Home", systemImage: "pin.slash")
                }
            }
        } else {
            base
        }
    }

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                // The card's title leads, real and readable (ruling 2026-07-12):
                // the type ramp carries the hierarchy — a bigger, primary-ink
                // header so cards read as separate objects, not one soft field.
                Text(el.str(0))
                    .dsText(.callout15).fontWeight(.semibold).foregroundStyle(DS.textPrimary)
                Spacer(minLength: DS.Space.s2)
                if let sizeToggle {
                    ShelfSizePin(large: large) { sizeToggle(id) }
                        // Every module's size pin sits in the SAME top-right
                        // corner now; the 44pt hit box overflows the header's
                        // top padding and the trailing inset for a full target.
                        .padding(.vertical, -12)
                        .padding(.trailing, -12)
                }
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.bottom, el.str(1).isEmpty ? DS.Space.s3 : 0)
            if !el.str(1).isEmpty {
                Text(el.str(1))
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .padding(.leading, DS.Space.s4)
                    .padding(.top, DS.Space.s1)
                    .padding(.bottom, DS.Space.s3)
            }

            if kind == "music", large {
                GenMusicHero(refs: refs, els: els)
            } else if large {
                // The user-controlled hero (prd 58g): growing a media tile
                // features its lead image full-bleed, editorial — one thing
                // dominates (the Flipboard move), by YOUR choice. The rest
                // rides as a strip below, still browsable.
                GenMediaHero(refs: refs, els: els)
            } else {
                GenMediaStrip(refs: refs, els: els)
            }
        }
        .padding(.top, DS.Space.s4)
        .padding(.bottom, DS.Space.s2)
    }
}

/// A media module as a single half-width magazine tile (prd 58f) — the lead
/// item's art fills the tile, the module's eyebrow rides a bottom scrim, and
/// the size-pin sits in the top corner. Tapping the tile opens the lead
/// thing; tapping the pin grows the module to its full-bleed row.
private struct GenMediaCompactTile: View {
    let id: String
    let eyebrow: String
    let leadRef: String?
    let els: GenEls
    let sizeToggle: ((String) -> Void)?
    private var lead: GenEl? { leadRef.flatMap { els[$0] } }

    var body: some View {
        Group {
            if let lead {
                GenMediaTile(el: lead, size: nil, aspectRatio: 1)
            } else {
                GenSkeletonTile(minHeight: 180)
            }
        }
        .frame(height: 180)
        .overlay(alignment: .bottomLeading) {
            Text(eyebrow)
                .dsText(.label12).foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(DS.Space.s3)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if let sizeToggle {
                // Flush to the corner so the whole 44pt hit box stays on the
                // tile; the glyph centers ~a finger's width in, which reads as
                // the top-right control and never spills off the art.
                ShelfSizePin(large: false, onImage: true) { sizeToggle(id) }
            }
        }
    }
}

/// The regular strip — square tiles, horizontally scrolling.
private struct GenMediaStrip: View {
    let refs: [String]
    let els: GenEls
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s2) {
                ForEach(refs, id: \.self) { ref in
                    if let el = els[ref] {
                        GenMediaTile(el: el, size: 96)
                    } else {
                        GenSkeletonTile(minHeight: 96).frame(width: 96)
                    }
                }
            }
            .padding(.horizontal, DS.Space.s4)
        }
    }
}

/// The large grid — Pinterest/screenshots grow into a moodboard, the same
/// 2-column idiom the pinned card's large form uses (Goal 2), just with
/// real images instead of glyph tiles.
private struct GenMediaGrid: View {
    let refs: [String]
    let els: GenEls
    var body: some View {
        Group {
            // A single pinned item (below the usual 2-item magnitude) gets
            // one full-width tile rather than a 2-column grid with an empty
            // half — a lone tile beside a blank cell reads as broken, not
            // as a moodboard.
            if refs.count == 1 {
                if let ref = refs.first, let el = els[ref] {
                    GenMediaTile(el: el, size: nil).frame(height: 220)
                } else {
                    GenSkeletonTile(minHeight: 220)
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Space.s3),
                                     GridItem(.flexible(), spacing: DS.Space.s3)],
                          spacing: DS.Space.s3) {
                    ForEach(refs, id: \.self) { ref in
                        if let el = els[ref] {
                            GenMediaTile(el: el, size: nil).frame(height: 160)
                        } else {
                            GenSkeletonTile(minHeight: 160)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, DS.Space.s4)
    }
}

/// Music's large form — literally full-bleed (prd 58's wording): the
/// newest track's own art fills the card edge to edge, title/artist over
/// a bottom scrim. The rest of the strip rides below, still tappable.
private struct GenMusicHero: View {
    let refs: [String]
    let els: GenEls
    private var lead: GenEl? { refs.first.flatMap { els[$0] } }
    private var rest: [String] { Array(refs.dropFirst()) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if let lead {
                GenMediaTile(el: lead, size: nil, aspectRatio: 1.4, overlayTitle: true)
                    .frame(height: 220)
                    .padding(.horizontal, DS.Space.s4)
            }
            if !rest.isEmpty { GenMediaStrip(refs: rest, els: els) }
        }
    }
}

/// A media module's large form (prd 58g) — the lead image full-bleed as an
/// editorial feature (Pinterest, screenshots), the rest a browsable strip
/// below. The magazine's "one thing dominates," grown by the person's own
/// pin tap. Music keeps its own GenMusicHero (title/artist split).
private struct GenMediaHero: View {
    let refs: [String]
    let els: GenEls
    private var lead: GenEl? { refs.first.flatMap { els[$0] } }
    private var rest: [String] { Array(refs.dropFirst()) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if let lead {
                GenMediaTile(el: lead, size: nil, aspectRatio: 1.5, overlayTitle: true)
                    .frame(height: 300)
                    .padding(.horizontal, DS.Space.s4)
            } else {
                GenSkeletonTile(minHeight: 300).padding(.horizontal, DS.Space.s4)
            }
            if !rest.isEmpty { GenMediaStrip(refs: rest, els: els) }
        }
    }
}

/// One media tile — reads a MediaItem's args (title, imageURL, thing id,
/// openable). A screenshot carries no imageURL (its bytes are local, prd
/// 48) — `genThumbnailData` resolves those by thing id instead. Same tap/
/// long-press vocabulary as every other Home row (`pinnedRowActions`).
private struct GenMediaTile: View {
    let el: GenEl
    /// A fixed square side, or nil to fill the parent (the grid/hero cases).
    var size: CGFloat? = 96
    var aspectRatio: CGFloat = 1
    /// Hero mode: the title/artist ride a bottom scrim over the image.
    var overlayTitle: Bool = false
    @Environment(\.genThingOpen) private var thingOpen
    @Environment(\.genThingHandoff) private var thingHandoff
    @Environment(\.genThumbnailData) private var thumbnailData
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var title: String { el.str(0) }
    private var imageURL: String { el.str(1) }
    private var thingId: String { el.str(2) }
    private var openable: Bool { el.str(3) == "app" }

    /// "Title — Artist" (the music ingest's own stored form, ShapedRows'
    /// MusicRow parses the same way) — the hero splits it so the artist
    /// rides its own line; every other tile shows the raw title.
    private var heroParts: (title: String, artist: String?) {
        let comps = title.components(separatedBy: " — ")
        guard comps.count > 1, let artist = comps.last else { return (title, nil) }
        return (comps.dropLast().joined(separator: " — "), artist)
    }

    @ViewBuilder private var image: some View {
        if !imageURL.isEmpty {
            // RemoteThumb is a fixed icon square (its own `.frame` inside);
            // the grid/hero forms need the image to FILL whatever frame
            // the layout gives it, so they get the flexible loader instead.
            if let size {
                RemoteThumb(urlString: imageURL, size: size)
            } else {
                GenFlexThumb(urlString: imageURL)
            }
        } else if let data = thumbnailData?(thingId), let ui = UIImage(data: data) {
            Image(uiImage: ui).resizable().scaledToFill()
        } else {
            ZStack {
                DS.gray200
                Image(systemName: "photo")
                    .font(.system(size: (size ?? 96) * 0.3, weight: .medium))
                    .foregroundStyle(DS.textTertiary)
            }
        }
    }

    var body: some View {
        let frame = Group {
            if let size {
                image.frame(width: size, height: size)
            } else {
                // A resizable().scaledToFill() image with no GeometryReader
                // pins itself to the SOURCE photo's native size, not the
                // card — a portrait screenshot then overflows the tile
                // horizontally (the moodboard grid ran off-page, review
                // 2026-07-11). GeometryReader + explicit frame + .clipped()
                // is the same fix HomePageBackground already uses.
                GeometryReader { geo in
                    // Parallax (prd 58g/v2b): the image is overscanned ~14%
                    // taller than its tile and drifts vertically as the tile
                    // scrolls through the viewport — depth, the Flipboard
                    // "alive" feel. scrollTransition is a RENDER-only
                    // transform (no gesture surface), so it can't touch the
                    // scroll/drag the way a hand-rolled gesture would. Reduce
                    // Motion collapses it: phase stays identity, offset 0.
                    let overscan = geo.size.height * 0.14
                    image
                        .aspectRatio(aspectRatio, contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height + overscan)
                        .scrollTransition(.interactive(timingCurve: .linear)) { content, phase in
                            content.offset(y: reduceMotion ? 0 : -phase.value * (overscan / 2))
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            if overlayTitle {
                let parts = heroParts
                VStack(alignment: .leading, spacing: 1) {
                    Text(parts.title).dsText(.heading17).foregroundStyle(.white).lineLimit(1)
                    if let artist = parts.artist {
                        Text(artist).dsText(.subhead13).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                    }
                }
                .padding(DS.Space.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(colors: [.black.opacity(0.55), .clear],
                                   startPoint: .bottom, endPoint: .center)
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        frame.pinnedRowActions(id: thingId, openable: openable,
                               open: thingOpen, unpin: nil, handoff: thingHandoff)
    }
}

/// A flexible-size remote image — the same bytes `RemoteThumb` would fetch,
/// but scaled to FILL whatever frame the caller gives it instead of
/// RemoteThumb's fixed icon-square shape (which the large-form grid/hero/
/// attached-post-image layouts all need). No cache/dead-URL bookkeeping —
/// a lighter loader for a first pass; URLSession's own HTTP cache still
/// avoids re-fetching the same URL.
private struct GenFlexThumb: View {
    let urlString: String
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if failed {
                ZStack {
                    DS.gray200
                    Image(systemName: "photo")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(DS.textTertiary)
                }
            } else {
                DS.gray200
            }
        }
        .task(id: urlString) { await load() }
    }
    private func load() async {
        image = nil
        failed = false
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let ui = UIImage(data: data) else {
            failed = !Task.isCancelled
            return
        }
        withAnimation(DS.Motion.standard) { image = ui }
    }
}

/// Coach(text) — the one-time teaching line, Feed's coach style verbatim:
/// tinted words on the page, retired forever by the surface once the
/// lesson is learned (the flag lives with the surface, not here).
private struct GenCoach: View {
    let el: GenEl
    var body: some View {
        Text(el.str(0))
            .dsText(.subhead13)
            .foregroundStyle(DS.tint)
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s4)
    }
}

/// Row(title, tag, source, time, thingId?) — arg 5 only on Home's pinned
/// rows: tap opens the thing, long-press offers Open / Unpin (2026-07-10;
/// swipe can't ride here — these rows live in a ScrollView, and a custom
/// DragGesture eats vertical scroll on device, a lesson already paid for).
/// Row(title, tag, source, time, thingId, openable). Two forms by context:
/// OFF the board (no `genSpan` — a line inside a Widget card, e.g. the store
/// previews) it's a thin list row; ON the board (a pinned thing is its own
/// module now, ruling 2026-07-12) it's a square tile carrying the SAME corner
/// pin every other module wears — no bundle, no oversized pin, no forced hero.
/// Row(title, tag, source, time, thingId?, openable?) — a thin list line: tag
/// glyph, title, trailing time. Inside a pinned app tile (or a store preview),
/// where the card owns the surface. arg 4/5 (thing id + openable) only on a
/// pinned tile's rows: tap opens the thing, long-press offers Open / Open in
/// app (no per-item Unpin — removal is the whole app's, on the card).
private struct GenRow: View {
    let id: String
    let el: GenEl
    @Environment(\.genThingOpen) private var thingOpen
    @Environment(\.genThingHandoff) private var thingHandoff
    @Environment(\.genAppRemove) private var appRemove
    @Environment(\.genCitationGlint) private var glintOn
    /// One glint per mount (delight 2026-07-13): a cited row flashes a
    /// whisper of tint as it lands in a live answer, then settles.
    @State private var glinted = false

    var body: some View {
        let row = HStack(spacing: DS.Space.s3) {
            TagGlyph(tag: el.str(1), size: 24)
            Text(el.str(0))
                .dsText(.body17)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(el.str(3)).dsText(.subhead13).foregroundStyle(DS.textTertiary)
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s3)
        .background {
            if glintOn {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.tint.opacity(glinted ? 0 : 0.14))
            }
        }
        .onAppear {
            guard glintOn, !glinted else { return }
            withAnimation(.easeOut(duration: 0.9).delay(0.2)) { glinted = true }
        }
        return row.pinnedRowActions(id: el.str(4), openable: el.str(5) == "app",
                             open: thingOpen, unpin: nil, handoff: thingHandoff,
                             removeApp: appRemove)
    }
}

extension View {
    /// Tap-to-open + long-press Open / Open in app / Unpin, attached only
    /// when the doc gave the row a thing id (Home's pinned rows). "Open in
    /// app" appears only when the thing has a real destination (arg 6) —
    /// the hand-off the Feed swipe carries lives here too (2026-07-10,
    /// user: moving pins to Home must not cost the hand-off).
    @ViewBuilder
    func pinnedRowActions(id: String, openable: Bool,
                          open: ((String) -> Void)?,
                          unpin: ((String) -> Void)?,
                          handoff: ((String) -> Void)?,
                          removeApp: (() -> Void)? = nil) -> some View {
        if id.isEmpty {
            self
        } else {
            contentShape(Rectangle())
                .onTapGesture { open?(id) }
                .contextMenu {
                    Button {
                        open?(id)
                    } label: {
                        Label("Open", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    if openable {
                        Button {
                            handoff?(id)
                        } label: {
                            Label("Open in app", systemImage: "arrow.up.right")
                        }
                    }
                    // Unpin only when the surface wired one (a pinned APP tile's
                    // rows have no per-item pin to drop — removal is the whole
                    // app's, on the card — so they pass nil and show no Unpin).
                    if let unpin {
                        Button {
                            unpin(id)
                        } label: {
                            Label("Unpin", systemImage: "pin.slash")
                        }
                    }
                    // A row inside a pinned app tile carries the whole tile's
                    // "Remove from Home" — each row's own contextMenu would
                    // otherwise shadow the card's, leaving removal unreachable.
                    if let removeApp {
                        Button(role: .destructive) {
                            removeApp()
                        } label: {
                            Label("Remove from Home", systemImage: "pin.slash")
                        }
                    }
                }
        }
    }

}

/// TokenChip(symbol, chain, address, thingId, openable) — a compact token line
/// inside a pinned Tokens tile: the symbol, an inline sparkline drawn
/// on-device (prd 51 — a token's content IS its chart), its price, and the 1D
/// delta. A thin row with NO surface of its own; the pinned Widget card owns the
/// surface, so a chart never nests a card inside a card. Tap opens the token;
/// long-press offers Open / Open in app / Remove from Home (the watchlist tile).
private struct GenTokenChip: View {
    let el: GenEl
    @State private var chart: TokenChart?
    /// The line DRAWS itself once when the data lands (left → right reveal).
    @State private var revealed = false
    @Environment(\.genThingOpen) private var thingOpen
    @Environment(\.genThingHandoff) private var thingHandoff
    @Environment(\.genAppRemove) private var appRemove
    @Environment(\.genRefreshTick) private var refreshTick
    @Environment(\.colorScheme) private var scheme

    private var symbol: String { el.str(0) }
    private var accent: Color {
        TokenChartStyle.accent(up: (chart?.change ?? 0) >= 0, scheme: scheme)
    }

    var body: some View {
        let row = HStack(spacing: DS.Space.s3) {
            Text(symbol).dsText(.body17).foregroundStyle(DS.textPrimary)
                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            plot.frame(width: 60, height: 26)
            if let chart {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(TokenChartStyle.priceText(chart.price))
                        .dsText(.subhead13).foregroundStyle(DS.textPrimary)
                        .contentTransition(.numericText())
                    TokenDeltaPill(change: chart.change, label: "1D", compact: true)
                }
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s2)
        // Keyed by chain/address (+ refresh tick), not a plain .task: Home's
        // first render streams token-by-token, so this can mount before those
        // args arrive; a pull re-fetches. Reveal replays when fresh data lands.
        .task(id: "\(refreshTick):\(el.str(1))/\(el.str(2))") {
            guard !el.str(1).isEmpty, !el.str(2).isEmpty else { return }
            revealed = false
            chart = await TokenChart.fetch(chain: el.str(1), address: el.str(2))
            if chart != nil { withAnimation(.easeOut(duration: 0.7)) { revealed = true } }
        }
        return row.pinnedRowActions(id: el.str(3), openable: el.str(4) == "app",
                                    open: thingOpen, unpin: nil, handoff: thingHandoff,
                                    removeApp: appRemove)
    }

    /// The sparkline, or a ghost bar while the fetch is out.
    @ViewBuilder private var plot: some View {
        if let chart {
            TokenChartPlot(chart: chart, accent: accent, height: 26, pulses: false)
                .mask(alignment: .leading) {
                    GeometryReader { geo in
                        Rectangle().frame(width: revealed ? geo.size.width : 0)
                    }
                }
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(DS.surfaceWell)
        }
    }
}

/// Suggest — inference proposes; one tap admits, one dismisses.
private struct GenSuggest: View {
    var body: some View {
        HStack(spacing: DS.Space.s3) {
            Text("2 tasks found in mail")
                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Review")
                .dsText(.label12).foregroundStyle(DS.tint)
                .padding(.horizontal, DS.Space.s3)
                .padding(.vertical, DS.Space.s1)
                .background(DS.tintDim, in: Capsule(style: .continuous))
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s3)
    }
}

/// Chip(source, label) — shelf unit.
private struct GenChip: View {
    let el: GenEl
    var body: some View {
        HStack(spacing: DS.Space.s2) {
            TagGlyph(tag: el.str(0), size: 20)
            Text(el.str(1)).dsText(.subhead13).foregroundStyle(DS.textSecondary)
        }
        .padding(.horizontal, DS.Space.s3)
        .padding(.vertical, DS.Space.s2)
        .background(DS.gray100, in: Capsule(style: .continuous))
    }
}

/// Tile(span, source, title, subline)
private struct GenTile: View {
    let el: GenEl
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            TagGlyph(tag: el.str(1), size: 24)
            Spacer(minLength: 0)
            Text(el.str(2)).dsText(.heading17).foregroundStyle(DS.textPrimary).lineLimit(1)
            Text(el.str(3)).dsText(.subhead13).foregroundStyle(DS.textSecondary).lineLimit(1)
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .dsWidgetSurface()
    }
}

/// ProjectTile(span, name, "src,src", subline, countPill, colorToken)
/// Minimal (amendment): a count above, the name below — no subline, no icons,
/// no pills. The document grammar still carries sources and the full subline
/// (server-compatible); the tile wears only what magnitude and identity need.
/// Tap routes to project detail via `genProjectTap` (gap §9.1).
private struct GenProjectTile: View {
    let el: GenEl
    @Environment(\.genProjectTap) private var projectTap

    /// Leading number from the count arg ("8 things" → "8").
    private var count: String {
        el.str(4).split(separator: " ").first.map(String.init) ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            if !count.isEmpty {
                Text(count).dsText(.subhead13).foregroundStyle(DS.textTertiary)
            }
            Spacer(minLength: 0)
            Text(el.str(1)).dsText(.heading17).foregroundStyle(DS.textPrimary)
                .lineLimit(2).minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, minHeight: el.str(0) == "2" ? 132 : 120, alignment: .topLeading)
        .dsWidgetSurface()
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
        .onTapGesture {
            let name = el.str(1)
            if !name.isEmpty { projectTap?(name) }
        }
    }
}

/// PhotoTile(span, title, subline) — four thumbnails over a caption.
private struct GenPhotoTile: View {
    let el: GenEl
    private let shades: [Color] = [DS.gray200, DS.gray300, DS.gray100, DS.gray200]
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(spacing: DS.Space.s2) {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                        .fill(shades[i])
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            Text(el.str(1)).dsText(.heading17).foregroundStyle(DS.textPrimary)
            Text(el.str(2)).dsText(.subhead13).foregroundStyle(DS.textSecondary)
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .dsWidgetSurface()
    }
}

/// VoiceTile(span, title, subline) — waveform over a caption.
private struct GenVoiceTile: View {
    let el: GenEl
    private let bars: [CGFloat] = [8, 14, 20, 12, 18, 8, 16, 22, 10, 14, 6, 12]
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, h in
                    Capsule().fill(DS.tint).frame(width: 3, height: h)
                }
            }
            .frame(height: 24)
            Spacer(minLength: 0)
            Text(el.str(1)).dsText(.heading17).foregroundStyle(DS.textPrimary)
            Text(el.str(2)).dsText(.subhead13).foregroundStyle(DS.textSecondary)
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .dsWidgetSurface()
    }
}

/// TagMap(eyebrow, subline, ["Label N", ...], iconMode) — treemap of flat
/// sheet-surface cards (2026-07-10, user: the tiles are LITERALLY the
/// Settings-tile surface; colored fills and colored label inks were both
/// tried the same day and read as noise). Magnitude is size alone;
/// identity is the white label and the token/bridge icons.
private struct GenTagMap: View {
    let id: String
    let el: GenEl
    /// Preview mode (TagMapPreview): the starter shape before tags exist —
    /// muted fill, no tap targets, no weekend share.
    var preview = false
    @Environment(\.genProjectTap) private var projectTap
    @Environment(\.genZoomNS) private var zoomNS
    @Environment(\.genModuleLarge) private var large
    @Environment(\.genSizeToggle) private var sizeToggle
    /// nil off the board; `small` gives the map a shorter, fewer-cell 1×1
    /// tile (prd 58h) — a treemap needs area, so it skips `wide`.
    @Environment(\.genSpan) private var span
    /// The entrance plays once per screen appearance (§3); filter and theme
    /// re-renders never replay it.
    @State private var settled = false
    /// The starter preview breathes slowly — "waiting to fill". One of the
    /// app's two sanctioned liveness loops (the other: the berry while an
    /// answer is in flight, 2026-07-13) — each exists only while something
    /// real is pending, never as decoration.
    @State private var breathe = false

    /// Grid areas (col, row, w, h) on a 4×3 unit grid, largest-first. One set
    /// per item count, each tiling the grid COMPLETELY — a holdings map can hold
    /// 1–6 tokens, and a template sized for 6 leaves holes when fewer arrive.
    private var frames: [(Int, Int, Int, Int)] {
        switch items.count {
        case 0, 1: return [(0, 0, 4, 3)]
        case 2:    return [(0, 0, 2, 3), (2, 0, 2, 3)]
        case 3:    return [(0, 0, 2, 2), (2, 0, 2, 2), (0, 2, 4, 1)]
        case 4:    return [(0, 0, 2, 2), (2, 0, 2, 2), (0, 2, 2, 1), (2, 2, 2, 1)]
        case 5:    return [(0, 0, 2, 2), (2, 0, 2, 2), (0, 2, 2, 1), (2, 2, 1, 1), (3, 2, 1, 1)]
        default:   return [(0, 0, 2, 2), (2, 0, 2, 1), (2, 1, 1, 1), (3, 1, 1, 2), (0, 2, 2, 1), (2, 2, 1, 1)]
        }
    }

    private var items: [KindCountRow.Item] {
        KindCountRow.parse(el.refs(2), cap: span == .small ? 3 : 6)
    }

    /// Arg 3 — how each cell earns its icon (2026-07-09): "source" reads an
    /// exact bridge name (Gmail, Wallet, …) through BridgeIcon — no fetch,
    /// never wrong, because a source-mode cell is always exactly one bridge.
    /// "token" reads a bundled local mark (TokenIcon) keyed by symbol — no
    /// fetch either; Alchemy's own logo field turned out null for nearly
    /// everything, including WETH and USDC. A project (a tag someone chose,
    /// or a tag cluster) spans sources by nature, so it carries neither —
    /// name only, never a guessed icon.
    private var iconMode: String { el.str(3) }

    private var isWeekend: Bool {
        let wd = Calendar.current.component(.weekday, from: .now)
        return wd == 1 || wd == 7
    }

    /// "@pin " leading the eyebrow marks a pin-born map — a pinned wallet's
    /// holdings on Home (ruling 2026-07-10): the Pinned card's tilted pin,
    /// small and in the eyebrow's own ink, says "here because you pinned
    /// it" in the vocabulary the screen already taught. GenWidget's "@pin"
    /// convention, carried into the TagMap idiom. The marker is
    /// presentation only — every text site reads the stripped title.
    private var pinBorn: Bool { el.str(0).hasPrefix("@pin ") }
    private var eyebrow: String {
        pinBorn ? String(el.str(0).dropFirst("@pin ".count)) : el.str(0)
    }
    /// Every board module wears the same small tertiary pin (prd 58) —
    /// not just pin-born wallet maps — and it's the size control (prd
    /// 58a): tap it, the module blooms to large. The preview map isn't a
    /// real module yet (nothing to size), so it carries no pin.
    private var boardHeight: CGFloat { span == .small ? 150 : (large ? 320 : 220) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !el.str(0).isEmpty {
                HStack(spacing: 7) {
                    // Off Home (Wallet/Feed compose the same wallet map) the
                    // pin is a decorative "you pinned it" badge and leads the
                    // title; on Home the size control sits in the top-right
                    // corner like every other module's pin (ruling 2026-07-12).
                    if preview == false, sizeToggle == nil, pinBorn {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DS.textSecondary)
                            .rotationEffect(.degrees(-35), anchor: .bottomLeading)
                            .accessibilityLabel("Pinned")
                    }
                    // A real, readable card title (ruling 2026-07-12): bigger,
                    // primary ink, so the type ramp carries the separation.
                    Text(eyebrow)
                        .dsText(.callout15).fontWeight(.semibold)
                        .foregroundStyle(DS.textPrimary)
                    Spacer()
                    // The size control (Home) — same top-right corner as the
                    // tiles, a pin with a real handler behind it (honesty rule).
                    if !preview, let sizeToggle {
                        ShelfSizePin(large: large) { sizeToggle(id) }
                            .padding(.top, -12).padding(.trailing, -12)
                    }
                }
                .padding(.leading, span == .small ? 0 : DS.Space.s4)
                // Air before the cells — with or without a subline (the map
                // sat flush under the eyebrow when the subline was absent).
                .padding(.bottom, (el.str(1).isEmpty || span == .small) ? DS.Space.s3 : 0)
            }
            // The subline ("$19K across 13 tokens") is dropped on a small tile —
            // no room, and the eyebrow already names the wallet.
            if !el.str(1).isEmpty, span != .small {
                Text(el.str(1))
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .padding(.leading, DS.Space.s4)
                    .padding(.top, DS.Space.s1)
                    .padding(.bottom, DS.Space.s3)
            }
            GeometryReader { geo in
                cells(width: geo.size.width, height: boardHeight, animated: true)
            }
            .frame(height: boardHeight)
        }
        // Small tiles are inset by the board's packer; wide/big self-pad.
        .padding(.horizontal, span == .small ? 0 : DS.Space.s4)
        .padding(.top, DS.Space.s4)
        .onAppear {
            if preview {
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    breathe = true
                }
            }
            guard !settled else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(30))
                settled = true
            }
        }
    }

    /// The six cells at a given width. Animated: §3's scale-in stagger on
    /// weekdays; §6's left-to-right magnitude fill on weekends (never both).
    @ViewBuilder
    private func cells(width: CGFloat, height: CGFloat = 220, animated: Bool) -> some View {
        let gap = DS.Space.s2
        let uw = (width - gap * 3) / 4
        let uh = (height - gap * 2) / 3
        ZStack(alignment: .topLeading) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                let f = frames[i]
                let w = uw * CGFloat(f.2) + gap * CGFloat(f.2 - 1)
                let h = uh * CGFloat(f.3) + gap * CGFloat(f.3 - 1)
                let on = !animated || settled
                // An icon rides above the name in "source" (an exact bridge,
                // via BridgeIcon — no fetch, never wrong) or "token" mode (a
                // logo URL that arrived with the cell, or none at all rather
                // than a wrong one). A project cell carries neither — see
                // GenTagMap's iconMode doc.
                let label = VStack(alignment: .leading, spacing: DS.Space.s1) {
                    if iconMode == "source" {
                        BridgeIcon(name: item.tag, size: 20)
                    } else if iconMode == "token" {
                        TokenIcon(symbol: item.tag, size: 20)
                    }
                    Text(item.tag)
                        .dsText(.body17)
                        // Plain primary ink, exactly like a Settings tile's
                        // title (2026-07-10, user) — colored label inks were
                        // tried the same day and read as noise.
                        .foregroundStyle(preview ? DS.textTertiary : DS.textPrimary)
                        .lineLimit(item.tag.contains(" ") ? 2 : 1)
                        .minimumScaleFactor(0.4)
                        .allowsTightening(true)
                    // The count fills the tile's empty field with the fact it
                    // already encodes as area (a name floating in a void read
                    // as unfinished). Token cells skip it — their N is a
                    // sizing value, not a thing count — and 1-unit-tall cells
                    // skip it too (no vertical room; the line would draw past
                    // the tile onto its neighbor).
                    if !preview, iconMode != "token", f.3 >= 2 {
                        Text(item.n == 1 ? "1 thing" : "\(item.n) things")
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                    }
                }
                    .padding(DS.Space.s3)
                    .frame(width: w, height: h, alignment: .topLeading)
                    .background {
                        // Tiles are CARDS, literally (2026-07-10, user):
                        // the exact sheet surface the Settings tiles and
                        // Pinned card use — no hue wash at all. Magnitude
                        // is size, the treemap's real voice; identity is
                        // the label ink and the token/bridge icons. The
                        // preview breathes the surface itself: shape
                        // without claiming substance.
                        DS.surfaceSheet
                            .opacity((preview ? (breathe ? 0.55 : 0.85) : 1)
                                     * (isWeekend && animated && !on ? 0 : 1))
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    }
                Group {
                    if preview {
                        label   // nothing behind the cell yet — no tap target
                    } else {
                        Button {
                            DSHaptic.selection()
                            // A holdings cell has no project to open — the
                            // whole map routes to the Wallet screen instead
                            // of a dead-end empty tag view (2026-07-10).
                            projectTap?(iconMode == "token" ? "@wallet" : item.tag)
                        } label: { label }
                        // The Settings tiles' own press (settle + dim) — the
                        // cells ARE tiles now, so they press like tiles
                        // (2026-07-10, user).
                        .buttonStyle(DSTileButtonStyle())
                    }
                }
                .scaleEffect(!isWeekend && animated && !on ? 0.92 : 1)
                .opacity(!isWeekend && animated && !on ? 0 : 1)
                .animation(entrance(order: isWeekend ? f.0 : i), value: settled)
                .offset(x: CGFloat(f.0) * (uw + gap), y: CGFloat(f.1) * (uh + gap))
                .zoomSource(id: item.tag, in: zoomNS)
            }
        }
    }

    /// Weekday: 35ms per cell in layout order. Weekend: the fill sweeps
    /// left to right, 600ms total across the four columns.
    private func entrance(order: Int) -> Animation {
        isWeekend
            ? DS.Motion.standard.delay(Double(order) * 0.35 / 3)
            : DS.Motion.standard.delay(Double(order) * 0.035)
    }

}

/// KindBar(eyebrow, ["Tag N", ...]) — the corpus's composition as one
/// stacked strip (what your things ARE; the treemap left Feed — a feed is a
/// feed). Segments carry magnitude by width; a tap lands in the Feed
/// filtered to that kind. Labels ride a legend, not the segments.
private struct GenKindBar: View {
    let el: GenEl
    @Environment(\.openURL) private var openURL


    private var items: [KindCountRow.Item] { KindCountRow.parse(el.refs(1)) }

    var body: some View {
        let total = max(1, items.map(\.n).reduce(0, +))
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if !el.str(0).isEmpty {
                Text(el.str(0))
                    .dsText(.label12)
                    .foregroundStyle(DS.textSecondary)
            }
            GeometryReader { geo in
                let gap: CGFloat = 3
                let usable = geo.size.width - gap * CGFloat(items.count - 1)
                HStack(spacing: gap) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(hue(item.tag).opacity(0.85))
                            .frame(width: max(14, usable * CGFloat(item.n) / CGFloat(total)))
                            .onTapGesture { open(item.tag) }
                    }
                }
            }
            .frame(height: 28)
            // The legend — names and counts; tap works here too.
            FlowLayout(spacing: DS.Space.s2) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: DS.Space.s1) {
                        Circle()
                            .fill(hue(item.tag))
                            .frame(width: 8, height: 8)
                        Text(ThingKind.from(typeTag: item.tag)?.typeTagPlural ?? item.tag)
                            .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                        Text("\(item.n)")
                            .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                            .contentTransition(.numericText())
                            .animation(DS.Motion.standard, value: item.n)
                    }
                    .onTapGesture { open(item.tag) }
                    .accessibilityLabel("\(item.n) \(item.tag)")
                }
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s4)
    }

    private func hue(_ tag: String) -> Color {
        ThingKind.from(typeTag: tag)?.hue ?? DS.tint
    }

    private func open(_ tag: String) {
        DSHaptic.selection()
        FeedFilter.shared.tag = tag
        if let url = URL(string: "casberi://feed") { openURL(url) }
    }
}

/// AppsInvite(title, subline) — the quiet day's door: a card inviting more
/// apps, with a few of the catalog's icons and a chevron. Tap opens the
/// Apps page (the "@apps" marker through projectTap, same routing move as
/// the holdings map's "@wallet").
private struct GenAppsInvite: View {
    let el: GenEl
    @Environment(\.genProjectTap) private var projectTap

    private static let sampleApps = ["Photos", "Calendar", "Reminders", "Gmail"]

    var body: some View {
        Button {
            DSHaptic.selection()
            projectTap?("@apps")
        } label: {
            HStack(spacing: DS.Space.s3) {
                HStack(spacing: -6) {
                    ForEach(Self.sampleApps, id: \.self) { name in
                        BridgeIcon(name: name, size: 26, circular: true)
                            .overlay(Circle().strokeBorder(DS.surfaceSheet, lineWidth: 1.5))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(el.str(0))
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                    if !el.str(1).isEmpty {
                        Text(el.str(1))
                            .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.textTertiary)
            }
            .padding(DS.Space.s4)
            .dsWidgetSurface()
        }
        .buttonStyle(DSTileButtonStyle())
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s4)
    }
}

/// The shared quiet-state body — Feed's empty state's moment.
struct QuietStateView: View {
    let line: String

    var body: some View {
        VStack(spacing: DS.Space.s3) {
            CasberiMarkDrawOn(size: 44)
            Text(line)
                .dsText(.body17)
                .foregroundStyle(DS.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s6)
    }
}

// MARK: - Skeletons

struct GenSkeletonRow: View {
    var body: some View {
        HStack(spacing: DS.Space.s3) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(DS.gray100).frame(width: 24, height: 24)
            Capsule().fill(DS.gray100).frame(height: 12)
            Capsule().fill(DS.gray100).frame(width: 40, height: 12)
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s3)
    }
}

struct GenSkeletonTile: View {
    var minHeight: CGFloat = 96
    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous)
            .fill(DS.surfaceSheet)
            .frame(minHeight: minHeight)
    }
}

// MARK: - Shaped-feed grammar (display forms — docs/handoff-shaped-feeds.md)

/// TxRow(verb, amount, detail) — verb leads; "Received" wears confirm.
/// A token mark opens the row (ruling 2026-07-07: icons live at row scale,
/// never in the treemap): the asset that ARRIVES leads — the last ticker in
/// a swap, the only one otherwise. Bundled marks for the majors; anything
/// else wears a monogram coin, which is also what long-tail tokens get when
/// live Zerion data arrives.
private struct GenTxRow: View {
    let el: GenEl

    private static let known: Set<String> = ["ETH", "SOL", "LINK"]
    private static let coinColor: [String: Color] = [
        "USDC": Color.fixed("#2775ca"), "BTC": Color.fixed("#f7931a"),
        "ETH": Color.fixed("#3c3c44"), "SOL": Color.fixed("#141418"),
    ]

    /// The arriving asset's ticker, read from the amount text.
    private var ticker: String? {
        let words = el.str(1)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
        let tickers = words.filter { word in
            word.count >= 3 && word.count <= 5
            && word == word.uppercased() && word.rangeOfCharacter(from: .letters) != nil
            && Int(word) == nil
        }
        return tickers.last
    }

    @ViewBuilder private var tokenMark: some View {
        if let ticker {
            Group {
                if Self.known.contains(ticker),
                   let ui = UIImage(named: "token-\(ticker.lowercased())") {
                    Image(uiImage: ui).resizable().scaledToFill()
                } else {
                    let coin = Self.coinColor[ticker] ?? DS.gray200
                    ZStack {
                        coin
                        Text(String(ticker.prefix(1)))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(width: 22, height: 22)
            .clipShape(Circle())
        }
    }

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            tokenMark
            Text(el.str(0))
                .dsText(.subhead13)
                .foregroundStyle(el.str(0) == "Received" ? DS.confirm : DS.textSecondary)
                .frame(width: 70, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(el.str(1)).dsText(.body17).foregroundStyle(DS.textPrimary).lineLimit(1)
                if !el.str(2).isEmpty {
                    Text(el.str(2)).dsText(.subhead13).foregroundStyle(DS.textTertiary).lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s1)
    }
}

/// AgendaRow(time, title, subline, state) — state "next" emphasizes.
private struct GenAgendaRow: View {
    let el: GenEl
    var body: some View {
        let next = el.str(3) == "next"
        HStack(spacing: DS.Space.s3) {
            Text(el.str(0))
                .dsText(.subhead13).monospacedDigit()
                .fontWeight(next ? .bold : .regular)
                .foregroundStyle(DS.textPrimary)
                .frame(width: 58, alignment: .trailing)
            Capsule(style: .continuous)
                .fill(next ? DS.tint : DS.gray200)
                .frame(width: 3, height: next ? 34 : 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(el.str(1))
                    .dsText(.body17).fontWeight(next ? .semibold : .regular)
                    .foregroundStyle(DS.textPrimary).lineLimit(1)
                if !el.str(2).isEmpty {
                    Text(el.str(2)).dsText(.subhead13).foregroundStyle(DS.textTertiary).lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s1)
    }
}

/// MailRow(subject, snippet, meta, thingId?, openable?) — args 4/5 only on a
/// pinned Gmail/iCloud tile's rows: a tap opens the mail, long-press offers
/// Open / Open in app (no Unpin — removal is the whole app's, on the card).
/// Off the board (store previews) the trailing args are absent and the row is
/// display-only.
private struct GenMailRow: View {
    let el: GenEl
    @Environment(\.genThingOpen) private var thingOpen
    @Environment(\.genThingHandoff) private var thingHandoff
    @Environment(\.genAppRemove) private var appRemove
    var body: some View {
        let row = HStack(spacing: DS.Space.s3) {
            KindGlyph(kind: .mail, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(el.str(0)).dsText(.body17).foregroundStyle(DS.textPrimary).lineLimit(1)
                if !el.str(1).isEmpty {
                    Text(el.str(1)).dsText(.subhead13).foregroundStyle(DS.textTertiary).lineLimit(1)
                }
            }
            Spacer()
            Text(el.str(2)).dsText(.subhead13).foregroundStyle(DS.textTertiary)
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s1)
        return row.pinnedRowActions(id: el.str(3), openable: el.str(4) == "app",
                                    open: thingOpen, unpin: nil, handoff: thingHandoff,
                                    removeApp: appRemove)
    }
}

/// PostRow(handle, text, avatarURL, thingId, openable) — a social post inside
/// a pinned Bluesky/Farcaster tile: the author's own avatar leads (circular,
/// same idiom the old single-post SocialCard used), then handle + text. An
/// account with no avatar URL falls back to its initial via RemoteThumb, same
/// as everywhere else a remote image can be dead or missing.
private struct GenPostRow: View {
    let el: GenEl
    @Environment(\.genThingOpen) private var thingOpen
    @Environment(\.genThingHandoff) private var thingHandoff
    @Environment(\.genAppRemove) private var appRemove
    var body: some View {
        let row = HStack(spacing: DS.Space.s3) {
            RemoteThumb(urlString: el.str(2), size: 28, fallback: el.str(0), circular: true)
            VStack(alignment: .leading, spacing: 2) {
                if !el.str(0).isEmpty {
                    Text(el.str(0)).dsText(.subhead13).foregroundStyle(DS.textSecondary).lineLimit(1)
                }
                Text(el.str(1)).dsText(.body17).foregroundStyle(DS.textPrimary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s2)
        return row.pinnedRowActions(id: el.str(3), openable: el.str(4) == "app",
                                    open: thingOpen, unpin: nil, handoff: thingHandoff,
                                    removeApp: appRemove)
    }
}

/// TakeawayCard(eyebrow, title, line) — the earned chat card, display form.
private struct GenTakeawayCard: View {
    let el: GenEl
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(el.str(0))
                .dsText(.label12).foregroundStyle(DS.textSecondary)
            Text(el.str(1))
                .dsText(.heading17).foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !el.str(2).isEmpty {
                Text(el.str(2))
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.s4)
        .dsWidgetSurface()
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s2)
    }
}

/// ApprovalCard(eyebrow, title, ask) — the consent card's display form; the
/// live Approve/Deny pills belong to the Feed's interactive twin.
private struct GenApprovalCard: View {
    let el: GenEl
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(el.str(0))
                .dsText(.label12).foregroundStyle(DS.textSecondary)
            Text(el.str(1))
                .dsText(.heading17).foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !el.str(2).isEmpty {
                Text(el.str(2)).dsText(.subhead13).foregroundStyle(DS.textSecondary).lineLimit(2)
            }
            HStack(spacing: DS.Space.s2) {
                Text("Approve").dsText(.label12).foregroundStyle(.black)
                    .padding(.horizontal, DS.Space.s4).frame(height: 32)
                    .background(DS.confirm, in: Capsule(style: .continuous))
                Text("Deny").dsText(.label12).foregroundStyle(DS.textPrimary)
                    .padding(.horizontal, DS.Space.s4).frame(height: 32)
                    .background(DS.fillFaint, in: Capsule(style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.s4)
        .dsWidgetSurface()
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s2)
    }
}

// MARK: - Cover (the slim data-first hero)

/// Cover(eyebrow, title, subline, source, dateline, tag, [Tag N, ...],
/// thingId) — the slim data-first hero, painted straight on the page
/// (2026-07-10): date, today's kind chips, and the "Just landed" card. The
/// cover stopped being an image element when the Banner became the
/// Background setting — the wallpaper is HomeScreen's page background now,
/// and this block is just content on it. Arg 6's tag still marks the
/// stream complete; arg 8 (2026-07-11, user) is the landed thing's id —
/// the card opens it, same tap the Pinned rows carry.
private struct GenCover: View {
    let el: GenEl
    @Environment(\.genCoverTopInset) private var topInset
    @Environment(\.genThingOpen) private var thingOpen
    @Environment(\.genProjectTap) private var projectTap

    /// Today's kind counts (arg 7) — the chip row that replaced the subline
    /// (ruling 2026-07-09); requireCount keeps a half-streamed tag from
    /// flashing a fallback chip.
    private var chips: [KindCountRow.Item] {
        KindCountRow.parse(el.refs(6), requireCount: true)
    }

    /// White over a set wallpaper (a deepened color or a dimmed photo —
    /// both dark fields); the page's own adaptive ink on the default page.
    private var coverInk: Color {
        HomeBackgroundStore.shared.image != nil ? .white : DS.textPrimary
    }

    /// The cover's top edge in global space — the dateline fades over the
    /// first 60pt of scroll so it never collides with the nav doors (§4).
    @State private var slotMinY: CGFloat = 0
    private var datelineFade: Double {
        let gone = Double(max(0, -slotMinY)) / 60.0
        return 1.0 - min(1.0, gone)
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: topInset)
            // Reserve the dateline's band so the content can't crowd it.
            if !el.str(4).isEmpty {
                Color.clear.frame(height: 44)
            }
            textBlock
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .global).minY
        } action: { slotMinY = $0 }
        // Left-aligned with the content below it (2026-07-10, user) —
        // centered read as a title; the date is a label, and every other
        // label on the page starts at the leading edge.
        .overlay(alignment: .topLeading) {
            if !el.str(4).isEmpty {
                // The date IS Home's header (2026-07-13 polish): Apps and
                // Settings open on a heading, and Home opened on a whisper —
                // the page's first words now carry heading weight.
                Text(el.str(4))
                    .dsText(.heading22)
                    .foregroundStyle(coverInk)
                    .padding(.top, topInset + DS.Space.s2)
                    .padding(.leading, DS.Space.s4)
                    .opacity(datelineFade)
            }
        }
    }

    /// Slim hero (redesign C, 2026-07-10): the DATA leads — today's kind
    /// counts ride above the headline, and "Just landed" is a compact card.
    /// The chips are the summary of the day; one specific capture is a
    /// detail, not the moment.
    private var textBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if !chips.isEmpty {
                KindCountRow(items: chips, ink: coverInk)
            }
            HStack(alignment: .top, spacing: DS.Space.s3) {
                // The source's icon leads the card (2026-07-10, user) — the
                // old banner ref slot (arg 4) carries the source name.
                if !el.str(3).isEmpty {
                    BridgeIcon(name: el.str(3), size: 28)
                }
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text(el.str(0))
                        .dsText(.label12)
                        .foregroundStyle(DS.textSecondary)
                    Text(el.str(1))
                        // The display-tier ramp token (36g: SF Rounded lives
                        // there) — no off-ramp sizes (2026-07-10, user).
                        .dsText(.heading22)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                    if !el.str(2).isEmpty {
                        Text(el.str(2))
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textSecondary)
                    }
                }
            }
            // Inner horizontal padding matches GenWidget's rows (s4), so
            // every card's content starts on ONE line (2026-07-10, user:
            // "Just landed" and the section labels didn't align).
            .padding(.horizontal, DS.Space.s4)
            .padding(.vertical, DS.Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The same sheet surface every other card wears — opaque, so
            // its own inks hold on any wallpaper behind it.
            .background(DS.surfaceSheet,
                        in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            // What landed opens (2026-07-11, user: "shouldn't a user be
            // able to tap it and go to it?") — the pinned tiles' tap, on
            // the one freshest thing. The id streams in last, so the card
            // simply isn't tappable until the line completes. An "@"-prefixed
            // id still routes to the surface tap handler (projectTap) for any
            // future sentinel, but the cover emits a real thing id now.
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .onTapGesture {
                let id = el.str(7)
                guard !id.isEmpty else { return }
                if id.hasPrefix("@") { projectTap?(id) } else { thingOpen?(id) }
            }
        }
        .padding(DS.Space.s4)
    }
}

// MARK: - Kind pills (replaces KindBar on Home — identity color, one row)

/// One row of kind-count chips — hue capsule, glyph in the kind's color,
/// count in `ink`. A tap opens the Feed filtered to that kind — the chips
/// are navigation, not decoration. Shared by the cover (white ink over a
/// photo or the black field) and KindPills (page ink).
private struct KindCountRow: View {
    struct Item { let tag: String; let n: Int }
    let items: [Item]
    var ink: Color = DS.textPrimary
    @Environment(\.openURL) private var openURL

    /// "[Tag N, ...]" refs → items, count-ordered upstream. The one parser
    /// for the idiom — TagMap and KindBar read it too. `requireCount` drops
    /// refs with no trailing count: the cover uses it so a tag truncated by
    /// the stream never flashes a fallback chip (composed chips always carry
    /// counts, so nothing real is lost); bare tags elsewhere still count 1.
    static func parse(_ raw: [String], cap: Int = 5, requireCount: Bool = false) -> [Item] {
        raw.prefix(cap).compactMap { r in
            let parts = r.split(separator: " ")
            if let last = parts.last, let n = Int(last) {
                return Item(tag: parts.dropLast().joined(separator: " "), n: n)
            }
            return requireCount ? nil : Item(tag: r, n: 1)
        }
    }

    /// The entrance plays once per appearance (§3's rule): each chip pops
    /// in with a small spring, 50ms after the last — the day's counts
    /// arriving one by one (2026-07-10).
    @State private var settled = false

    var body: some View {
        // Scrolls when the labels outgrow the row — the words stay (2026-07-13
        // polish: a bare icon + number was illegible to a new user; the chip
        // says what it counts).
        ScrollView(.horizontal) {
            HStack(spacing: DS.Space.s2) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    let kind = ThingKind.from(typeTag: item.tag)
                    let hue = kind?.hue ?? DS.tint
                    let word = (item.n == 1 ? kind?.typeTag : kind?.typeTagPlural)
                        ?? item.tag
                    Button {
                        DSHaptic.selection()
                        FeedFilter.shared.tag = item.tag
                        if let url = URL(string: "casberi://feed") { openURL(url) }
                    } label: {
                        HStack(spacing: DS.Space.s1) {
                            Image(systemName: kind?.symbol ?? "circle.dashed")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(hue)
                            Text("\(item.n)")
                                .dsText(.label12)
                                .foregroundStyle(ink)
                                .contentTransition(.numericText())
                                .animation(DS.Motion.standard, value: item.n)
                            Text(word.lowercased())
                                .dsText(.label12)
                                .foregroundStyle(ink.opacity(0.6))
                        }
                        .padding(.horizontal, DS.Space.s3)
                        .frame(minHeight: 34)
                        .background(hue.opacity(0.15), in: Capsule(style: .continuous))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(PressSpring())
                    .scaleEffect(settled ? 1 : 0.6)
                    .opacity(settled ? 1 : 0)
                    .animation(.spring(response: 0.35, dampingFraction: 0.6)
                        .delay(Double(i) * 0.05), value: settled)
                    .accessibilityLabel("\(item.n) \(word)")
                }
            }
        }
        .scrollIndicators(.hidden)
        // A horizontal ScrollView is greedy on the cross axis under a
        // flexible proposal — pin it to its content height so the chip row
        // never stretches apart the cover stack it sits in.
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { settled = true }
    }
}

/// KindPills(eyebrow, [Tag N, ...]) — one pill per kind, count-ordered, max 5.
/// Stays in the vocabulary; Home's counts now ride the Cover's chip row.
private struct GenKindPills: View {
    let el: GenEl

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if !el.str(0).isEmpty {
                Text(el.str(0))
                    .dsText(.label12)
                    .foregroundStyle(DS.textSecondary)
            }
            KindCountRow(items: KindCountRow.parse(el.refs(1)))
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s4)
    }
}
