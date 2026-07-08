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
    /// Cover tap → the thing sheet (the surface resolves the id).
    var genCoverTap: ((String) -> Void)? {
        get { self[GenCoverTapKey.self] }
        set { self[GenCoverTapKey.self] = newValue }
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
}

private struct GenProseStreamingKey: EnvironmentKey {
    static let defaultValue = false
}

private struct GenCoverTapKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}
private struct GenCoverTopInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
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
        case "Widget":      GenWidget(el: el, els: els).mountIn()
        case "Row":         GenRow(el: el).mountIn()
        case "Suggest":     GenSuggest().mountIn()
        case "Skeleton":    GenSkeletonRow().mountIn()
        case "Chip":        GenChip(el: el).mountIn()
        case "Tile":        GenTile(el: el).mountIn()
        case "ProjectTile": GenProjectTile(el: el).mountIn()
        case "PhotoTile":   GenPhotoTile(el: el).mountIn()
        case "VoiceTile":   GenVoiceTile(el: el).mountIn()
        case "TagMap":      GenTagMap(el: el).mountIn()
        // The starter shape: same geometry, muted fill, nothing to tap — an
        // honest preview of the map that composes once things land.
        case "TagMapPreview": GenTagMap(el: el, preview: true).mountIn()
        case "Quiet":       GenQuiet(el: el).mountIn()
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
            Text(el.str(0).uppercased())
                .dsText(.label12).kerning(1)
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
            Text("NOTICED")
                .dsText(.label12).kerning(1)
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

/// Widget(title, count?, children) — a sheet card of rows.
private struct GenWidget: View {
    let el: GenEl
    let els: GenEls
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text(el.str(0)).dsText(.heading22).foregroundStyle(DS.textPrimary)
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

/// Row(title, tag, source, time)
private struct GenRow: View {
    let el: GenEl
    var body: some View {
        HStack(spacing: DS.Space.s3) {
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
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
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

/// TagMap(eyebrow, subline, ["Label N", ...]) — treemap, magnitude fill:
/// tint at opacity scaled by count (the color rule's magnitude clause).
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

    private struct Item { let tag: String; let n: Int }
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

    private var items: [Item] {
        el.refs(2).prefix(6).map { raw in
            let parts = raw.split(separator: " ")
            if let last = parts.last, let n = Int(last) {
                return Item(tag: parts.dropLast().joined(separator: " "), n: n)
            }
            return Item(tag: raw, n: 1)
        }
    }

    private var isWeekend: Bool {
        let wd = Calendar.current.component(.weekday, from: .now)
        return wd == 1 || wd == 7
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !el.str(0).isEmpty {
                HStack {
                    Text(el.str(0).uppercased())
                        .dsText(.label12).kerning(1)
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
                // Air before the cells — with or without a subline (the map
                // sat flush under the eyebrow when the subline was absent).
                .padding(.bottom, el.str(1).isEmpty ? DS.Space.s3 : 0)
            }
            if !el.str(1).isEmpty {
                Text(el.str(1))
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
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
        let maxN = max(1, items.map(\.n).max() ?? 1)
        ZStack(alignment: .topLeading) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                let f = frames[i]
                let w = uw * CGFloat(f.2) + gap * CGFloat(f.2 - 1)
                let h = uh * CGFloat(f.3) + gap * CGFloat(f.3 - 1)
                let on = !animated || settled
                let label = Text(item.tag)
                    .dsText(.body17)
                    .foregroundStyle(preview ? DS.textTertiary : DS.textPrimary)
                    .lineLimit(item.tag.contains(" ") ? 2 : 1)
                    .minimumScaleFactor(0.4)
                    .allowsTightening(true)
                    .padding(DS.Space.s3)
                    .frame(width: w, height: h, alignment: .topLeading)
                    .background(
                        // V3b: the tile wears ITS project's hue (magnitude
                        // still rides opacity) — one color per project,
                        // matching its tag ink in the feed. Preview mutes the
                        // fill flat: shape without claiming substance.
                        ProjectHue.color(for: item.tag)
                            .opacity((preview ? 0.14
                                      : 0.30 + 0.45 * Double(item.n) / Double(maxN))
                                     * (isWeekend && animated && !on ? 0 : 1)),
                        in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                Group {
                    if preview {
                        label   // nothing behind the cell yet — no tap target
                    } else {
                        Button {
                            DSHaptic.selection()
                            projectTap?(item.tag)
                        } label: { label }
                        .buttonStyle(PressSpring())
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
        let card = VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text(el.str(0).uppercased())
                .dsText(.label12).kerning(1)
                .foregroundStyle(DS.textSecondary)
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

    private struct Item { let tag: String; let n: Int }

    private var items: [Item] {
        el.refs(1).prefix(5).map { raw in
            let parts = raw.split(separator: " ")
            if let last = parts.last, let n = Int(last) {
                return Item(tag: parts.dropLast().joined(separator: " "), n: n)
            }
            return Item(tag: raw, n: 1)
        }
    }

    var body: some View {
        let total = max(1, items.map(\.n).reduce(0, +))
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if !el.str(0).isEmpty {
                Text(el.str(0).uppercased())
                    .dsText(.label12).kerning(1)
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

/// Quiet(line) — a quiet moment earns the berry: the mark draws itself on,
/// one plain line under it. A fact, not a nudge (§5 polish).
private struct GenQuiet: View {
    let el: GenEl

    var body: some View {
        QuietStateView(line: el.str(0))
    }
}

/// The shared quiet-state body — Home's quiet day and Feed's empty state use
/// the same moment.
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
            Text(el.str(0).uppercased())
                .dsText(.label12).kerning(1).foregroundStyle(DS.textSecondary)
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
            Text(el.str(0).uppercased())
                .dsText(.label12).kerning(1).foregroundStyle(DS.textSecondary)
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

// MARK: - Cover (docs/handoff-home.md — the full-bleed header; H7)

/// Extracted cover bleed — dominant color per thing id, cached. Desaturated
/// ~20% and brightness-capped so the vivid text ramp always passes.
enum CoverBleed {
    private static var cache: [String: Color] = [:]

    static func cached(_ id: String) -> Color? { cache[id] }

    static func extract(from image: UIImage, id: String) -> Color {
        if let hit = cache[id] { return hit }
        guard let ci = CIImage(image: image) else { return .black }
        let extent = ci.extent
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ci,
            kCIInputExtentKey: CIVector(cgRect: extent),
        ])
        guard let out = filter?.outputImage else { return .black }
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: kCFNull as Any]).render(
            out, toBitmap: &pixel, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: nil)
        var r = CGFloat(pixel[0]) / 255, g = CGFloat(pixel[1]) / 255, b = CGFloat(pixel[2]) / 255
        // Desaturate ~20% toward the mean, then cap brightness for the ramp.
        let mean = (r + g + b) / 3
        r = r + (mean - r) * 0.2; g = g + (mean - g) * 0.2; b = b + (mean - b) * 0.2
        let brightness = max(r, g, b)
        if brightness > 0.55 {
            let k = 0.55 / brightness
            r *= k; g *= k; b *= k
        }
        let color = Color(red: r, green: g, blue: b)
        cache[id] = color
        return color
    }
}

/// Cover(eyebrow, title, subline, thingId, dateline) — the composition stays
/// dumb (it only names facts); everything smart lives here: image lookup by
/// thingId, bleed extraction, theme fallbacks. Height is decided before first
/// paint from the args alone — a thingId means the 250pt image canvas, none
/// means the 140pt quiet cover — so the streamed skeleton never jumps.
private struct GenCover: View {
    let el: GenEl
    @Environment(\.modelContext) private var modelContext
    @Environment(\.genCoverTap) private var coverTap
    @Environment(\.genCoverTopInset) private var topInset
    @State private var image: UIImage?
    @State private var bleed: Color?

    private var thingID: String { el.str(3) }
    private var hasImage: Bool { !thingID.isEmpty }
    private var photoTheme: Bool { ThemeStore.shared.backgroundPhoto != nil }

    /// The quiet cover's wash color. Nil while the document is still
    /// streaming (the 6th arg hasn't arrived) — painting the fallback early
    /// flashed blue before the real color landed. "quiet" = Casberi blue
    /// (a quiet day or the weekend recap, no lead kind).
    private var quietWash: Color? {
        let tag = el.str(5)
        if tag.isEmpty { return nil }
        if tag == "quiet" { return DS.tint }
        return ThingKind.from(typeTag: tag)?.hue ?? DS.tint
    }

    /// The cover's top edge in global space — 0 at rest (the cover leads the
    /// scroll under the status bar). Positive = overscrolled down, negative =
    /// scrolled away.
    @State private var slotMinY: CGFloat = 0

    /// Overscroll stretch (§4): the image canvas grows to fill the pull.
    /// Normal scroll gets nothing — no parallax.
    private var stretch: CGFloat { hasImage ? max(0, slotMinY) : 0 }

    /// The date line fades over the first 60pt of scroll so it never collides
    /// with the nav doors (§4).
    private var datelineFade: Double {
        let gone = Double(max(0, -slotMinY)) / 60.0
        return 1.0 - min(1.0, gone)
    }

    var body: some View {
        Group {
            if hasImage {
                // The layout slot stays fixed; the canvas rides a bottom-
                // aligned overlay so a pull extends it upward (stretchy
                // header) without a feedback loop on the measurement.
                Color.clear
                    .frame(height: 250 + topInset)
                    .overlay(alignment: .bottom) {
                        canvas.frame(height: 250 + topInset + stretch)
                    }
            } else {
                canvas.frame(minHeight: 150 + topInset)
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .global).minY
        } action: { slotMinY = $0 }
        .task(id: thingID) { await load() }
    }

    private var canvas: some View {
        ZStack(alignment: .bottomLeading) {
            // Canvas: the image under its scrims, or the quiet themed gradient.
            if hasImage {
                DS.fillFaint   // the pre-image skeleton — same height, no jump
                if let image {
                    GeometryReader { geo in
                        Image(uiImage: image)
                            .resizable().scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()   // canvas clip only — text lives in padding
                    }
                }
                scrims
            } else {
                // The quiet cover is a SOLID bright field of the lead thing's
                // kind color — the Fantastical move (user ruling): the whole
                // band is the primary color, slightly lighter at the top,
                // never fading into dark. Same block in both modes. Until the
                // stream delivers the color, the page shows — no blue flash.
                if let wash = quietWash {
                    LinearGradient(
                        colors: [wash.mix(with: .white, by: 0.12),
                                 wash.mix(with: .black, by: 0.08)],
                        startPoint: .top, endPoint: .bottom
                    )
                } else {
                    DS.themedPage
                }
            }

            // The text block: bottom-anchored on the image canvas, centered on
            // the quiet cover (that tall flat top edge read as waste). The
            // measured top inset is reserved INSIDE the canvas so nothing
            // renders under the status bar or nav buttons.
            VStack(spacing: 0) {
                Color.clear.frame(height: topInset)
                // Reserve the dateline's band so the cover text can't crowd it
                // (the quiet cover centers its text — without this the eyebrow
                // landed a few points under the date).
                if !el.str(4).isEmpty {
                    Color.clear.frame(height: 36)
                }
                textBlock
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: hasImage ? .bottomLeading : .leading)
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(Rectangle())
        // The color arrives with the stream — ease it in, don't snap.
        .animation(DS.Motion.standard, value: el.str(5))
        // The date line rides the top edge, centered between the nav buttons;
        // it fades over the first 60pt of scroll (§4).
        .overlay(alignment: .top) {
            if !el.str(4).isEmpty {
                Text(el.str(4).uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .kerning(1.4)
                    .foregroundStyle(coverInk.opacity(0.92))
                    .padding(.top, topInset + DS.Space.s2)
                    .opacity(datelineFade)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if hasImage { coverTap?(thingID) } }
    }

    /// Bleed at the top (dateline zone), the page at the bottom (no seam).
    /// Photo wallpaper in force: skip the bleed, strengthen the scrim — the
    /// cover's content photo wins; the wallpaper stays behind the page below.
    @ViewBuilder
    private var scrims: some View {
        let top: Color = photoTheme ? .black.opacity(0.55)
            : (bleed ?? .black).opacity(0.55)
        // A base dim under the gradients: busy images (screenshots of UI,
        // dense photos) read as a photo BEHIND the text, never as layers
        // bleeding through (2026-07-07).
        Color.black.opacity(0.35)
        LinearGradient(colors: [top, .clear],
                       startPoint: .top, endPoint: .center)
        LinearGradient(colors: [.clear, photoTheme ? .black.opacity(0.75) : DS.themedPage],
                       startPoint: .center, endPoint: .bottom)
    }

    /// White over a photo (scrims) or a bright color field (Fantastical
    /// pattern); the page's own ink for the beat before the color streams in.
    private var coverInk: Color {
        hasImage || quietWash != nil ? .white : DS.textPrimary
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(el.str(0).uppercased())
                .dsText(.label12).kerning(1)
                .foregroundStyle(coverInk.opacity(0.7))
            Text(el.str(1))
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(coverInk)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            if !el.str(2).isEmpty {
                Text(el.str(2))
                    .dsText(.subhead13)
                    .foregroundStyle(coverInk.opacity(0.85))
            }
        }
        .padding(DS.Space.s4)
    }

    private func load() async {
        guard hasImage, image == nil else { return }
        // Resolve the thing locally (the doc only names facts).
        guard let uuid = UUID(uuidString: thingID) else { return }
        let all = (try? modelContext.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.id == uuid }
        ))) ?? []
        guard let ref = all.first?.sourceRef else { return }
        // Sample things carry the bundled photo (same rule as PhotoWell).
        if ref.hasPrefix("sample:") {
            if let ui = UIImage.demoSample(for: ref) {
                image = ui
                if let hit = CoverBleed.cached(thingID) {
                    bleed = hit
                } else {
                    let id = thingID
                    bleed = await Task.detached(priority: .utility) {
                        CoverBleed.extract(from: ui, id: id)
                    }.value
                }
            }
            return
        }
        let assetID = ref.replacingOccurrences(of: "phasset:", with: "")
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = assets.firstObject else { return }
        let loaded: UIImage? = await withCheckedContinuation { cont in
            var reported = false
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: 1200, height: 900),
                contentMode: .aspectFill, options: nil
            ) { img, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !degraded, !reported { reported = true; cont.resume(returning: img) }
            }
        }
        guard let loaded else { return }
        image = loaded
        // Extraction off-main, cached per thing id.
        if let hit = CoverBleed.cached(thingID) {
            bleed = hit
        } else {
            let id = thingID
            let color = await Task.detached(priority: .utility) {
                CoverBleed.extract(from: loaded, id: id)
            }.value
            withAnimation(DS.Motion.standard) { bleed = color }
        }
    }
}

// MARK: - Kind pills (replaces KindBar on Home — identity color, one row)

/// KindPills(eyebrow, [Tag N, ...]) — one pill per kind, count-ordered, max 5.
private struct GenKindPills: View {
    let el: GenEl
    @Environment(\.openURL) private var openURL

    private struct Item { let tag: String; let n: Int }

    private var items: [Item] {
        el.refs(1).prefix(5).map { raw in
            let parts = raw.split(separator: " ")
            if let last = parts.last, let n = Int(last) {
                return Item(tag: parts.dropLast().joined(separator: " "), n: n)
            }
            return Item(tag: raw, n: 1)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if !el.str(0).isEmpty {
                Text(el.str(0).uppercased())
                    .dsText(.label12).kerning(1)
                    .foregroundStyle(DS.textSecondary)
            }
            HStack(spacing: DS.Space.s2) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    let kind = ThingKind.from(typeTag: item.tag)
                    let hue = kind?.hue ?? DS.tint
                    Button {
                        open(item.tag)
                    } label: {
                        HStack(spacing: DS.Space.s1) {
                            Image(systemName: kind?.symbol ?? "circle.dashed")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(hue)
                            Text("\(item.n)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(DS.textPrimary)
                                .contentTransition(.numericText())
                                .animation(DS.Motion.standard, value: item.n)
                        }
                        .padding(.horizontal, DS.Space.s3)
                        .frame(minHeight: 34)
                        .background(hue.opacity(0.15), in: Capsule(style: .continuous))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(PressSpring())
                    .accessibilityLabel("\(item.n) \(kind?.typeTagPlural ?? item.tag)")
                }
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s4)
    }

    private func open(_ tag: String) {
        DSHaptic.selection()
        FeedFilter.shared.tag = tag
        if let url = URL(string: "casberi://feed") { openURL(url) }
    }
}
