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
    /// A pinned row's Unpin (context menu) — the surface flips the pin and
    /// recomposes. nil outside Home.
    var genThingUnpin: ((String) -> Void)? {
        get { self[GenThingUnpinKey.self] }
        set { self[GenThingUnpinKey.self] = newValue }
    }
    /// A pinned row's "Open in app" — the real hand-off to the thing's
    /// source (calshow://, the link, …). nil outside Home.
    var genThingHandoff: ((String) -> Void)? {
        get { self[GenThingHandoffKey.self] }
        set { self[GenThingHandoffKey.self] = newValue }
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
    /// Bumped by Home's pull-to-refresh — live modules (token charts) key
    /// their fetch on it so a pull re-fetches what a recompose alone
    /// wouldn't (same doc line → same task id → no refetch).
    var genRefreshTick: Int {
        get { self[GenRefreshTickKey.self] }
        set { self[GenRefreshTickKey.self] = newValue }
    }
}

private struct GenProseStreamingKey: EnvironmentKey {
    static let defaultValue = false
}

private struct GenCoverTopInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}
private struct GenThingOpenKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}
private struct GenThingUnpinKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}
private struct GenThingHandoffKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}
private struct GenRefreshTickKey: EnvironmentKey {
    static let defaultValue = 0
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
        case "Widget":
            #if DEBUG
            // MOCK (-homeTitles YES): Home's sections named in the cover's
            // voice — "Kept" above the pin widget. Delete with the verdict.
            if UserDefaults.standard.bool(forKey: "homeTitles"), el.str(0) == "@pin" {
                Text("Kept")
                    .dsText(.heading22)
                    .foregroundStyle(DS.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, DS.Space.s2)
            }
            #endif
            GenWidget(el: el, els: els).mountIn()
        case "Row":         GenRow(el: el).mountIn()
        case "TokenRow":    GenTokenRow(el: el).mountIn()
        case "Suggest":     GenSuggest().mountIn()
        case "Skeleton":    GenSkeletonRow().mountIn()
        case "Chip":        GenChip(el: el).mountIn()
        case "Tile":        GenTile(el: el).mountIn()
        case "ProjectTile": GenProjectTile(el: el).mountIn()
        case "PhotoTile":   GenPhotoTile(el: el).mountIn()
        case "VoiceTile":   GenVoiceTile(el: el).mountIn()
        case "TagMap":
            #if DEBUG
            // MOCK (-homeTitles YES): "Your holdings" above the first wallet
            // map; the week map keeps its in-card title for contrast.
            if UserDefaults.standard.bool(forKey: "homeTitles"),
               el.str(0).hasPrefix("@pin "), el.str(3) == "token" {
                Text("Your holdings")
                    .dsText(.heading22)
                    .foregroundStyle(DS.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, DS.Space.s2)
            }
            #endif
            GenTagMap(el: el).mountIn()
        // The starter shape: same geometry, muted fill, nothing to tap — an
        // honest preview of the map that composes once things land.
        case "TagMapPreview": GenTagMap(el: el, preview: true).mountIn()
        // A quiet day's slot is a DOOR now, not a logo (2026-07-10, user:
        // the berry under a quiet cover was saying quiet twice and doing
        // nothing) — connect more apps and quiet days get rarer.
        case "AppsInvite":  GenAppsInvite(el: el).mountIn()
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

/// Widget(title, count?, children) — a sheet card of rows. The literal
/// title "@pin" renders as an oversized, tilted pin instead of a word
/// (2026-07-10, user): the pin glyph is universally readable, and the
/// Pinned card earns a little personality.
private struct GenWidget: View {
    let el: GenEl
    let els: GenEls
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                if el.str(0) == "@pin" {
                    PinMark()
                } else {
                    Text(el.str(0)).dsText(.heading22).foregroundStyle(DS.textPrimary)
                }
                if !el.str(1).isEmpty {
                    Text(el.str(1)).dsText(.callout15).foregroundStyle(DS.textTertiary)
                        .contentTransition(.numericText())
                        .animation(DS.Motion.standard, value: el.str(1))
                }
            }
            .padding(.init(top: DS.Space.s4, leading: DS.Space.s4,
                           bottom: DS.Space.s1, trailing: DS.Space.s4))
            ForEach(el.refs(2), id: \.self) { GenRender(id: $0, els: els, slot: .row) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, DS.Space.s2)
        .background(DS.surfaceSheet,
                    in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s4)
    }
}

/// The Pinned card's oversized pin — it SETTLES on appearance, a small
/// spring from upright toward its resting tilt, like being pressed into
/// the card (2026-07-10; same entrance-plays-once rule as everything else).
private struct PinMark: View {
    @State private var settled = false
    var body: some View {
        Image(systemName: "pin.fill")
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(DS.textPrimary)
            .rotationEffect(.degrees(settled ? -35 : -8), anchor: .bottomLeading)
            .padding(.top, DS.Space.s1)
            .accessibilityLabel("Pinned")
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.15)) {
                    settled = true
                }
            }
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
private struct GenRow: View {
    let el: GenEl
    @Environment(\.genThingOpen) private var thingOpen
    @Environment(\.genThingUnpin) private var thingUnpin
    @Environment(\.genThingHandoff) private var thingHandoff
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
        row.pinnedRowActions(id: el.str(4), openable: el.str(5) == "app",
                             open: thingOpen, unpin: thingUnpin, handoff: thingHandoff)
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
                          handoff: ((String) -> Void)?) -> some View {
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
                    Button {
                        unpin?(id)
                    } label: {
                        Label("Unpin", systemImage: "pin.slash")
                    }
                }
        }
    }
}

/// TokenRow(title, chain, address, time) — a pinned/resurfaced crypto token
/// leads with its price chart, same rule as the thing sheet (ThingContent's
/// TokenChartContent): the chart IS the token's content, not a link. Falls
/// back to the plain row's time label until the fetch resolves.
private struct GenTokenRow: View {
    let el: GenEl
    @State private var chart: TokenChart?
    /// The line DRAWS itself once when the data lands (left → right reveal,
    /// 2026-07-10) — the same entrance-plays-once juice as the pin's settle.
    /// A continuous pulse was considered and skipped: the chart is fetched
    /// per visit, not streamed, and a pulsing "live" line would overclaim.
    @State private var revealed = false
    @Environment(\.genThingOpen) private var thingOpen
    @Environment(\.genThingUnpin) private var thingUnpin
    @Environment(\.genThingHandoff) private var thingHandoff
    @Environment(\.genRefreshTick) private var refreshTick
    @Environment(\.colorScheme) private var scheme

    private var accent: Color {
        TokenChartStyle.accent(up: (chart?.change ?? 0) >= 0, scheme: scheme)
    }

    var body: some View {
        let row = VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(alignment: .center, spacing: DS.Space.s2) {
                Text(el.str(0))
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let chart {
                    Text(TokenChartStyle.priceText(chart.price))
                        .dsText(.callout15).foregroundStyle(DS.textPrimary)
                        .contentTransition(.numericText())
                        .animation(DS.Motion.standard, value: chart.price)
                    // The compact delta pill (prd 51) — Home and the sheet
                    // read as one family; the row stays the glance (24h
                    // fixed, no chips, no scrub at 48pt).
                    TokenDeltaPill(change: chart.change, label: "1D", compact: true)
                } else {
                    Text(el.str(3)).dsText(.subhead13).foregroundStyle(DS.textTertiary)
                }
            }
            if let chart {
                TokenChartPlot(chart: chart, accent: accent, height: 48, pulses: false)
                .mask(alignment: .leading) {
                    GeometryReader { geo in
                        Rectangle().frame(width: revealed ? geo.size.width : 0)
                    }
                }
                .onAppear {
                    guard !revealed else { return }
                    withAnimation(.easeOut(duration: 0.7)) { revealed = true }
                    // The line finishing its draw gets a tick (2026-07-10
                    // haptics pass) — once, when the reveal lands.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(700))
                        DSHaptic.selection()
                    }
                }
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s3)
        // Keyed by chain/address, not plain .task: Home's first render
        // streams the doc token-by-token (H7 typewriter), so this view can
        // mount before those args arrive — a bare .task would fetch once
        // with empty strings and never retry (fixed 2026-07-08).
        .task(id: "\(refreshTick):\(el.str(1))/\(el.str(2))") {
            guard !el.str(1).isEmpty, !el.str(2).isEmpty else { return }
            chart = await TokenChart.fetch(chain: el.str(1), address: el.str(2))
        }
        row.pinnedRowActions(id: el.str(4), openable: el.str(5) == "app",
                             open: thingOpen, unpin: thingUnpin, handoff: thingHandoff)
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
        .background(DS.surfaceSheet,
                    in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
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
        .background(DS.surfaceSheet,
                    in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
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
        .background(DS.surfaceSheet,
                    in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
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
        .background(DS.surfaceSheet,
                    in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
    }
}

/// TagMap(eyebrow, subline, ["Label N", ...], iconMode) — treemap of flat
/// sheet-surface cards (2026-07-10, user: the tiles are LITERALLY the
/// Settings-tile surface; colored fills and colored label inks were both
/// tried the same day and read as noise). Magnitude is size alone;
/// identity is the white label and the token/bridge icons.
private struct GenTagMap: View {
    let el: GenEl
    /// Preview mode (TagMapPreview): the starter shape before tags exist —
    /// muted fill, no tap targets, no weekend share.
    var preview = false
    @Environment(\.genProjectTap) private var projectTap
    @Environment(\.genZoomNS) private var zoomNS
    /// The entrance plays once per screen appearance (§3); filter and theme
    /// re-renders never replay it.
    @State private var settled = false
    /// Weekend recap: the map rendered to a shareable image (§6).
    @State private var weekCard: Image?
    /// The starter preview breathes slowly — "waiting to fill", the one
    /// looping motion in the app, and it only exists before things do.
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

    private var items: [KindCountRow.Item] { KindCountRow.parse(el.refs(2), cap: 6) }

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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !el.str(0).isEmpty {
                HStack(spacing: 7) {
                    if pinBorn {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DS.textSecondary)
                            .rotationEffect(.degrees(-35), anchor: .bottomLeading)
                            .accessibilityLabel("Pinned")
                    }
                    Text(eyebrow)
                        .dsText(.label12)
                        .foregroundStyle(DS.textSecondary)
                    Spacer()
                    // The banked week is shareable (§6) — weekend only.
                    if let weekCard {
                        ShareLink(item: weekCard,
                                  preview: SharePreview("Your week", image: weekCard)) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14))
                                .foregroundStyle(DS.textSecondary)
                        }
                        .accessibilityLabel("Share your week")
                    }
                }
                .padding(.leading, DS.Space.s4)
                // Air before the cells — with or without a subline (the map
                // sat flush under the eyebrow when the subline was absent).
                .padding(.bottom, el.str(1).isEmpty ? DS.Space.s3 : 0)
            }
            if !el.str(1).isEmpty {
                Text(el.str(1))
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .padding(.leading, DS.Space.s4)
                    .padding(.top, DS.Space.s1)
                    .padding(.bottom, DS.Space.s3)
            }
            GeometryReader { geo in
                cells(width: geo.size.width, animated: true)
            }
            .frame(height: 220)
        }
        .padding(.horizontal, DS.Space.s4)
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
                if isWeekend, !preview {
                    try? await Task.sleep(for: .milliseconds(700))
                    renderWeekCard()
                }
            }
        }
    }

    /// The six cells at a given width. Animated: §3's scale-in stagger on
    /// weekdays; §6's left-to-right magnitude fill on weekends (never both).
    @ViewBuilder
    private func cells(width: CGFloat, animated: Bool) -> some View {
        let gap = DS.Space.s2
        let uw = (width - gap * 3) / 4
        let uh = (220 - gap * 2) / 3
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

    /// Renders the recap card — eyebrow, map, small mark bottom-right — for
    /// the share sheet. No social copy, no other watermark.
    @MainActor
    private func renderWeekCard() {
        let end = Date.now
        let start = Calendar.current.date(byAdding: .day, value: -6, to: end) ?? end
        let range = "\(start.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day()))"
        let card = VStack(alignment: .leading, spacing: DS.Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow)   // stripped title — the "@pin" marker never leaves the app
                    .dsText(.label12)
                    .foregroundStyle(DS.textSecondary)
                // The shared image says WHICH week — it leaves the app,
                // where "The week" alone means nothing (2026-07-10).
                Text(range)
                    .dsText(.heading17)
                    .foregroundStyle(DS.textPrimary)
            }
            cells(width: 328, animated: false)
                .frame(width: 328, height: 220)
            HStack {
                Spacer()
                CasberiMark(size: 16)
            }
        }
        .padding(DS.Space.s4)
        .frame(width: 360)
        .background(DS.themedPage)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        if let ui = renderer.uiImage { weekCard = Image(uiImage: ui) }
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
            .background(DS.surfaceSheet,
                        in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
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
    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous)
            .fill(DS.surfaceSheet)
            .frame(minHeight: 96)
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

/// MailRow(subject, snippet, meta)
private struct GenMailRow: View {
    let el: GenEl
    var body: some View {
        HStack(spacing: DS.Space.s3) {
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
        .background(DS.surfaceSheet,
                    in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
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
        .background(DS.surfaceSheet,
                    in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
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
                Color.clear.frame(height: 36)
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
                Text(el.str(4))
                    .dsText(.label12)
                    .foregroundStyle(coverInk.opacity(0.92))
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
            // able to tap it and go to it?") — the Pinned rows' tap, on
            // the one freshest thing. The id streams in last, so the card
            // simply isn't tappable until the line completes. "@week"
            // (the weekend recap, prd 54) routes to the surface's tap
            // handler instead — the ask, not a thing.
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
        HStack(spacing: DS.Space.s2) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                let kind = ThingKind.from(typeTag: item.tag)
                let hue = kind?.hue ?? DS.tint
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
                .accessibilityLabel("\(item.n) \(kind?.typeTagPlural ?? item.tag)")
            }
        }
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
