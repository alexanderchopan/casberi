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

/// `block` (§198): a top-level answer module's placeholder, before its own
/// line has streamed in — distinct from `tile`/`row`, which are a WIDGET's
/// own children (already-resolved, waiting on their smaller shapes).
enum GenSlot { case none, row, tile, block }

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
    /// Ask a follow-up FROM inside an answer (2026-07-22) — the Today brief's
    /// residue line ("The rest keeps circling Samsung ›") hands the agent a
    /// query rather than ejecting to a filtered feed. Ruling 9: staying is the
    /// default, and ruling 8 already says a new ask pushes a fresh answer onto
    /// the Stack, so this reuses the session model instead of inventing a
    /// list-push destination. nil outside the agent.
    var genAskRequest: ((String) -> Void)? {
        get { self[GenAskRequestKey.self] }
        set { self[GenAskRequestKey.self] = newValue }
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
    /// True when rendering inside the AGENT's answer column (Composer sets
    /// it around both its GenRender calls, 2026-07-20). Two renderers read
    /// it: `GenInsight` drops its "Noticed" eyebrow fallback (the question
    /// above an answer already labels it — "Noticed" was the old Home
    /// card's vocabulary and wrong on something you asked for), and
    /// `GenTagMap` tightens its cell heights (feed proportions oversized
    /// the cells at the agent's narrower answer width).
    var genAgentAnswerContext: Bool {
        get { self[GenAgentAnswerContextKey.self] }
        set { self[GenAgentAnswerContextKey.self] = newValue }
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
    /// A module's span (prd 58h bento) — small / wide / big. Always nil now
    /// that the board (its one setter, HomeScreen) retired 2026-07-20 — kept
    /// so `GenWidget`'s existing nil-span handling (the plain, unsized form)
    /// stays the only code path, rather than threading an Optional-removal
    /// through every reader for a distinction nothing sets anymore.
    var genSpan: ModuleSpan? {
        get { self[GenSpanKey.self] }
        set { self[GenSpanKey.self] = newValue }
    }
}

/// A module's span on the old board's bento grid: `small` was a 1×1 square,
/// `wide` a 2×1 band, `big` a 2×2 feature. The type survives the board
/// (2026-07-20) only because `genSpan` still reads as this Optional below —
/// nothing constructs a non-nil value anymore.
enum ModuleSpan: String, CaseIterable, Sendable {
    case small, wide, big
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

private struct GenAgentAnswerContextKey: EnvironmentKey {
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
private struct GenAskRequestKey: EnvironmentKey {
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
    /// Read only to pass down to `Stack`'s own children (§198) — a top-level
    /// module streaming in inside the agent's answer column gets a `.block`
    /// skeleton laid out immediately; the same doc rendered anywhere else
    /// (there is no other Stack-rooted context today, but the flag already
    /// exists for exactly this kind of agent-only distinction) keeps the old
    /// drop-until-resolved behavior.
    @Environment(\.genAgentAnswerContext) private var inAgentAnswer

    var body: some View {
        // AnyView is load-bearing (2026-07-06 crash fix): the component
        // switch nests recursively (Stack → Widget → rows...), and without
        // erasure the combined generic type got deep enough that
        // instantiating its metadata overflowed the stack — an intermittent
        // SIGSEGV ("excessive recursion") on first render of a new branch
        // combination, seen when pushing a project during onboarding demo.
        // Erasing at every nesting level keeps the type flat forever.
        // A `.block` module holds its skeleton until its OWN line has fully
        // arrived (§199, user: "the materializing i mean [is] a bit jittery")
        // — everywhere else, a partial line still mounts immediately (the
        // "props fill as tokens arrive" law), which is right for a component
        // that's just growing text, not one deriving LAYOUT from its args.
        // Scoped to `.block` (agent-answer-only) on purpose, so it's a known
        // gap: `StorePreview`'s static "Wallet" doc streams a top-level
        // `TagMap` under slot `.none` (no `genAgentAnswerContext`) and has the
        // SAME jitter class, unfixed — a one-time product-page preview
        // animation, not the daily-use surface this was reported against.
        if let el = els[id], slot != .block || el.isComplete {
            AnyView(component(el))
        } else {
            switch slot {
            case .row:   GenSkeletonRow().mountIn()
            case .tile:  GenSkeletonTile().mountIn()
            case .block: GenSkeletonBlock().mountIn()
            case .none:  EmptyView()   // unresolved refs drop
            }
        }
    }

    @ViewBuilder
    private func component(_ el: GenEl) -> some View {
        switch el.comp {
        case "Stack":
            // The brief's — and any agent answer's — own top-level modules
            // (§198, user: "make it look like it's drawing the components...
            // like they form rather than just appear even if streamed"). Root
            // resolves almost immediately (it's a short line, first in the
            // doc), so the instant the stream reaches it every module's
            // BLOCK lays out at once — the whole screen's shape is visible
            // before a single one has content — and each block crossfades to
            // its real component as that module's own line streams in.
            //
            // Arg 1 (optional, 2026-07-31) — the ids that OPEN A CHAPTER.
            // A composition with a ranked order (the Today brief's money →
            // subject → the agent's read → the things) drew as one
            // undifferentiated column, because the gap between two movements
            // was the same as the gap inside one. A chapter id gets extra air
            // above it, so the structure reads without a single header —
            // which the design law wants anyway (no eyebrows, no rules, no
            // hairlines).
            //
            // The gap is ADDITIVE, and modules do NOT all self-pad equally —
            // don't read a single number off this. There are two tiers: `s2`
            // for a bare module (`MoneyHero`, `DayNotes`, `TilePair`) and `s4`
            // for a card that carries a shadow (`GenWidget`, `GenTagMap`). So
            // a chapter lands at s2+s4 or s4+s4, i.e. 28 or 36 on iOS, against
            // 10 or 18 of glue. Uniform totals are not the invariant and never
            // were; the CONTRAST is — every chapter opens on at least twice
            // the air of the join it follows, which is what the eye reads.
            //
            // Absent on every other `Stack` emitter, and absence is a no-op:
            // an empty arg means an empty set means nobody is a chapter,
            // exactly as before.
            //
            // A chapter-carrying doc routes through `GenFrontPage` (§274,
            // 2026-08-01): on a wide surface the same chapters that earn
            // extra air become COLUMN seams — the brief lays out as a front
            // page instead of one narrow column with a third of a Mac window
            // empty either side. Narrow surfaces render exactly the single
            // column this ForEach always drew; a chapterless doc never
            // routes there at all.
            let chapters = genChapterIDs(el.str(1))
            if chapters.isEmpty {
                ForEach(el.refs(0), id: \.self) { ref in
                    GenRender(id: ref, els: els, slot: inAgentAnswer ? .block : .none)
                }
            } else {
                GenFrontPage(el: el, els: els, chapters: chapters,
                             inAgentAnswer: inAgentAnswer)
            }

        case "Hero":        GenHero(el: el).mountIn()
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
        // Same muted geometry as the preview, but STATIC (no breathing — nothing
        // is pending) and honest: a pinned wallet we couldn't reach with no
        // last-known card to show (2026-07-17). The subline names the fix; the
        // screen's pull-to-refresh is the retry.
        case "TagMapError": GenTagMap(id: id, el: el, preview: true, error: true).mountIn()
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
        // "KindBar" and "KindPills" retired here 2026-08-01 — no composer had
        // emitted either name in months, and both were chip rows whose tap set
        // the feed's kind filter. Their shared ref parser lives on as
        // `KindCountRow`. Every doc in this app is built by a deterministic
        // composer (the model writes prose, never element names), so a retired
        // element name can never arrive from a synthesis.

        // Shaped-feed grammar (docs/handoff-shaped-feeds.md) — display forms
        // of the shaped rows, so compositions can paint them; the interactive
        // twins live in Screens/ShapedRows.swift and belong to the List.
        case "TxRow":        GenTxRow(el: el).mountIn()
        case "AgendaRow":    GenAgendaRow(el: el).mountIn()
        case "MailRow":      GenMailRow(el: el).mountIn()
        case "PostRow":      GenPostRow(el: el).mountIn()
        case "TakeawayCard": GenTakeawayCard(el: el).mountIn()
        case "ApprovalCard": GenApprovalCard(el: el).mountIn()

        // Answer-column charts (2026-07-21, prd §146) — richer generative UI
        // for the agent's answers. Each draws a REAL visualization the answer
        // already had the data for (agent-brief ruling 13); none invents one.
        case "ValueSpark":   GenValueSpark(el: el).mountIn()
        case "Bars":         GenBars(el: el).mountIn()
        case "ChartCard":    GenChartCard(el: el).mountIn()
        case "StatRow":      GenStatRow(el: el).mountIn()
        case "AllocBar":     GenAllocBar(el: el).mountIn()

        // The Today brief's own modules (2026-07-22, prd §166) — the mosaic
        // (B2) with the synthesis card (B3). `DayNote` has no case of its
        // own: it only ever renders as a child of `DayNotes`, flat, the way
        // a Widget's rows do.
        case "DayNotes":     GenDayNotes(el: el, els: els).mountIn()
        case "DayLede":      GenDayLede(el: el).mountIn()
        case "MoneyHero":    GenMoneyHero(el: el).mountIn()
        case "TilePair":     GenTilePair(el: el, els: els).mountIn()
        case "MoversTile":   GenMoversTile(el: el).mountIn()
        case "NextTile":     GenNextTile(el: el).mountIn()
        case "WalletFlow":   GenWalletFlow(el: el).mountIn()
        case "SourceMix":    GenSourceMix(el: el).mountIn()
        case "LeadRow":      GenLeadRow(el: el).mountIn()
        case "LeadPost":     GenLeadPost(el: el).mountIn()
        case "AskMore":      GenAskMore(el: el).mountIn()

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
    /// The universal entrance honours Reduce Motion (2026-08-04, prd §299) —
    /// it wraps EVERY component the agent renders, so this one guard covers the
    /// whole answer column.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// One universal entrance, deliberately plain (prd §198). An earlier
    /// cut special-cased the agent's answer column with a blur+scale
    /// "materialize" — reverted (user: "how would you improve it" → skeleton-
    /// first assembly instead of the blur). A blur reads as a photo coming
    /// into focus, not as a component being drawn; the actual "forming" feel
    /// now comes from `GenSkeletonBlock` laying the screen's structure out
    /// immediately (§198) and from each component's own build (the money
    /// hero's rolling total and drawn sparkline, the bars rising from
    /// baseline) — richness that belongs to the content, not a generic wrapper.
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 3)
            .onAppear {
                guard !reduceMotion else { shown = true; return }
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

/// Insight(text, eyebrow?) — a synthesis line under a small eyebrow. Arg 1 is
/// the eyebrow, defaulting to "Noticed" (the cross-source connection) when
/// empty, so every existing caller is unchanged; Home's "While you were away"
/// card passes its own eyebrow through the same element.
private struct GenInsight: View {
    let el: GenEl
    @Environment(\.genProseStreaming) private var streaming
    @Environment(\.genAgentAnswerContext) private var inAgentAnswer

    @Environment(\.genThingOpen) private var thingOpen
    @Environment(\.openURL) private var openURL

    /// Arg 1 — the eyebrow. Empty arg + a normal context = "Noticed" (the
    /// cross-source connection card's own label, unchanged). Empty arg
    /// INSIDE an agent answer = no eyebrow at all (fix 2026-07-20): the
    /// question above the answer already labels it, and "Noticed" on
    /// something you explicitly asked for was a vocabulary leak from the
    /// old Home card. A caller who PASSES an eyebrow keeps it everywhere.
    private var eyebrow: String? {
        let e = el.str(1)
        if !e.isEmpty { return e }
        return inAgentAnswer ? nil : String(localized: "Noticed")
    }

    /// ONE eyebrow and ONE paragraph (user 2026-07-18, second pass: the
    /// three-mini-section card "hasn't earned that space" — Home now composes
    /// just-landed + while-you-were-away + the model's connection into a single
    /// flowing paragraph in the DOC, and this renders it compactly). The card
    /// keeps one tap (arg 2 a thing id to open; arg 3 "feed" routes to the
    /// feed instead) — the most specific door the composition had. Answer docs
    /// keep passing `Insight(text)` and render identically to before.
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            if let eyebrow {
                Text(eyebrow)
                    .dsText(.label12)
                    .foregroundStyle(DS.textSecondary)
            }
            if streaming {
                // The model is still writing — one small dot breathes after
                // the last character. No shimmer, no skeleton (§2).
                TimelineView(.animation) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    let phase = (sin(t * 2 * .pi) + 1) / 2
                    (Text(el.str(0))
                     + Text(" ●")
                        .font(DSTextStyle.indicator9.scaledFont)
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
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .onTapGesture {
            let id = el.str(2)
            if !id.isEmpty { thingOpen?(id) }
            else if el.str(3) == "feed", let url = URL(string: "casberi://feed") { openURL(url) }
        }
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
    @Environment(\.genAgentAnswerContext) private var inAgentAnswer

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
                // Inside an agent answer this header labels the answer's
                // EVIDENCE ("Found 6"), so it steps down to a quiet label
                // (design pass 2026-07-21). At card weight it was the largest
                // thing on the screen — outranking both the answer sentence
                // it supports and the question that was asked. Everywhere
                // else (Home board, store previews) it stays a card title.
                Text(LocalizedStringKey(el.str(0)))
                    .dsText(inAgentAnswer ? .subhead13 : .heading22)
                    .foregroundStyle(inAgentAnswer ? DS.textSecondary : DS.textPrimary)
                if !el.str(1).isEmpty {
                    Text(el.str(1))
                        .dsText(inAgentAnswer ? .subhead13 : .callout15)
                        .foregroundStyle(DS.textTertiary)
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
            //
            // Rendered FLAT (crash fix 2026-07-17): rows dispatch straight on
            // the child's component — the same switch `soloContent` already
            // uses — instead of GenRender → AnyView → component → mountIn per
            // row. Auto-pin (§117) multiplied the board's tiles and every tile
            // carried up to three of those ~12-level row subtrees inside an
            // EAGER MagazineLayout; a scroll-time AttributeGraph cascade over
            // that forest overflowed the 8MB main stack INSIDE
            // `GenWidget.card.getter` (KERN_PROTECTION_FAILURE on the stack
            // guard; the recurring deep-tree class — CLAUDE.md: "flatten the
            // composition tree, not more stack").
            // The card as a whole still mountIn()s, so entrance still animates;
            // a widget row's set is fixed (Row/MailRow/PostRow/TokenChip —
            // exactly what `appChild` emits), so the direct dispatch can't
            // strand a component the generic path would have caught: an unknown
            // comp draws the same skeleton slot GenRender's .row slot drew.
            ForEach(rowRefs, id: \.self) { ref in
                rowContent(ref)
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

    /// One row of the card, flat: the concrete row view for the child's
    /// component, no GenRender/AnyView/mountIn wrapper (see the crash-fix
    /// comment at the call site). An unresolved ref (still streaming) draws
    /// the same skeleton row the generic path's `.row` slot drew.
    @ViewBuilder private func rowContent(_ ref: String) -> some View {
        if let child = els[ref] {
            switch child.comp {
            case "Row":       GenRow(id: ref, el: child)
            case "MailRow":   GenMailRow(el: child)
            case "PostRow":   GenPostRow(el: child)
            case "TokenChip": GenTokenChip(el: child)
            // Shaped answer rows (2026-07-21) — a wallet transfer draws its
            // TxRow (asset mark, direction, amount) and an agenda item its
            // AgendaRow (time rail) inside an answer Widget, instead of the
            // generic Row. Answer-only: the board's `appChild` never emits
            // these, so the fixed-set flatten note above still holds there.
            case "TxRow":     GenTxRow(el: child)
            case "AgendaRow": GenAgendaRow(el: child)
            // The Today brief's promoted rows (2026-07-22) — answer-only,
            // like TxRow/AgendaRow above; the board's `appChild` never emits
            // these, so the fixed-set flatten note still holds.
            case "LeadRow":   GenLeadRow(el: child)
            case "LeadPost":  GenLeadPost(el: child)
            case "AskMore":   GenAskMore(el: child)
            default:          GenSkeletonRow()
            }
        } else {
            GenSkeletonRow()
        }
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
        TokenChartStyle.accent(change: chart?.change ?? 0, scheme: scheme)
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

/// The green-squares grid — a Canvas of rounded cells (imperative draw, so
/// 53×7 cells add ZERO depth to the Home view tree; a LazyVGrid of 371 shapes
/// would deepen the tree the launch-stack budget guards). GitHub green ramped
/// by the day's quartile; empty days wear the surface well. A nil year is the
/// muted skeleton (loading / unreachable) — never fake counts.
struct ContributionGraph: View {
    let year: ContributionYear?
    /// The minimum column count the grid always fills — 53 for the year graph
    /// (so a sparse corpus or a nil loading state still draws a full year), a
    /// smaller number for a windowed heatmap (the social recent-weeks grid).
    var minColumns: Int = 53

    private static let gap: CGFloat = 3
    /// The geometry every heatmap is measured against — a full year. Cell size
    /// is derived from THIS, never from the grid's own column count, so a
    /// windowed heatmap draws the same squares as the year graph and simply
    /// occupies less width (2026-07-21, user: the social charts "should be
    /// same size, they are too large"). Before this, the grid stretched its
    /// columns edge to edge, so cell size scaled inversely with the window —
    /// the 14-week social grid drew squares roughly six times the year
    /// graph's, and read as a different, fatter kind of chart.
    private static let referenceColumns = 53

    var body: some View {
        let weeks = year?.weeks ?? []
        let cols = max(weeks.count, minColumns)
        // A grid longer than a year (never today, but the type allows it)
        // measures against itself rather than overflowing the card.
        let reference = max(cols, Self.referenceColumns)
        Canvas { ctx, size in
            let gap = Self.gap
            let cell = min((size.width - gap * CGFloat(reference - 1)) / CGFloat(reference),
                           (size.height - gap * 6) / 7)
            guard cell > 0 else { return }
            // A short window sits against the card's TRAILING edge, not its
            // leading one: the last column is always the current week, and the
            // year graph puts today at the right. Left-aligned, a 14-week grid
            // put "now" mid-card with empty space after it, reading as time
            // that continues with nothing in it.
            let drawnWidth = CGFloat(cols) * cell + gap * CGFloat(cols - 1)
            let originX = max(0, size.width - drawnWidth)
            for c in 0..<cols {
                let week = c < weeks.count ? weeks[c] : nil
                for r in 0..<7 {
                    let day = (week.map { $0.days.count > r ? $0.days[r] : nil }) ?? nil
                    let rect = CGRect(x: originX + CGFloat(c) * (cell + gap),
                                      y: CGFloat(r) * (cell + gap),
                                      width: cell, height: cell)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 2, style: .continuous),
                             with: .color(Self.color(for: day)))
                }
            }
        }
        // Measured against the reference year too, so every heatmap card is
        // the same height whatever window it draws — the windowed grid ends
        // early on the trailing edge instead of growing taller.
        .aspectRatio(CGFloat(reference) / 7.0, contentMode: .fit)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// GitHub green, ramped by quartile; the well for empty days.
    static func color(for day: ContributionDay?) -> Color {
        guard let day, day.level > 0 else { return DS.surfaceWell }
        return DS.confirm.opacity(0.30 + 0.22 * Double(day.level - 1))
    }
}

// MARK: - Feed-head insight cards (per-source feed overviews)
//
// All four share ONE card chrome and header, and each renders FLAT — a single
// shallow body over a Canvas / one GeometryReader — so they mount safely at the
// eager feed head (the launch-stack law — CLAUDE.md: "flatten the composition
// tree, not more stack"). The
// data behind each is derived only from what the bridge really stored
// (`FeedInsight` / `FeedHeatmap`); the guards live there, so a card that reaches
// a view always has something real to draw.

/// The shared card surface + title row for the insight heroes.
private struct InsightCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) { content }
            .padding(.horizontal, DS.Space.s4)
            .padding(.vertical, DS.Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsWidgetSurface()
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s2)
    }
}

private struct InsightHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Text(title).dsText(.body17).foregroundStyle(DS.textPrimary)
            Text(subtitle).dsText(.subhead13).foregroundStyle(DS.textTertiary)
        }
    }
}

/// The anniversary as the card itself — a photograph taken on this exact day
/// in an earlier year, at a size worth looking at (2026-07-31).
///
/// `OnThisDay` has ridden inside the heatmap card since 2026-07-21 precisely so
/// it would never compete for a room's one hero slot, and that stays right
/// wherever the anniversary is a TITLE: a journal entry, a note, a highlight —
/// text that a line of text represents perfectly. A picture is the case that
/// doesn't fit. Rendering "Memory · Jan 3, 2019" beside a date label describes
/// a photograph the app is already holding in memory, which is the one thing a
/// row can't do and a tile can.
///
/// It takes the head only when it EXISTS, which on a modest library is a
/// handful of days a year — so it isn't a card competing with the room's
/// standing facts, it's a rank above them on the rare day it has something.
/// Nothing is invented: no match, no card, and no card without real pixels.
struct OnThisDayHero: View {
    let echo: OnThisDay.Echo
    var onTap: () -> Void

    /// Liveness guard (COROLLARY 5) — this view stores the echo's model and
    /// SwiftUI re-runs a leaf's body on that model's own observation.
    var body: some View {
        // `previewImageData` gates the card (no pixels, no card) but the
        // drawing is `PhotoWell`'s: it decodes ONCE into its own state instead
        // of re-decoding a full-size photograph on every body evaluation, and
        // it is the one image view in this app that honours
        // `redactionReasons` — a hand-rolled `Image` survives into the
        // app-switcher snapshot with hidePreviews ON, which for a private
        // photograph at 190pt is exactly the leak that guard exists to stop.
        if echo.thing.isLive, echo.thing.previewImageData != nil {
            Button {
                DSHaptic.selection()
                onTap()
            } label: {
                PhotoWell(thing: echo.thing, size: nil)
                    .frame(height: 190)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
                    .overlay(alignment: .bottomLeading) {
                        LinearGradient(colors: [.clear, .black.opacity(0.7)],
                                       startPoint: .center, endPoint: .bottom)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.widget,
                                                        style: .continuous))
                            .allowsHitTesting(false)
                        Text(echo.label)
                            .dsText(.body17).foregroundStyle(.white)
                            .padding(DS.Space.s3)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: DS.Radius.widget,
                                                   style: .continuous))
            }
            .buttonStyle(DSTileButtonStyle())
        }
    }
}

/// A calendar-heatmap card — the GitHub graph's chrome, generalized so any
/// source that reads as a consistency-over-time habit (journaling, training,
/// captures) can lead its feed with the same green-squares grid. GitHub and the
/// corpus-derived sources both draw through this one card.
struct CalendarHeatmapHero: View {
    let title: String
    let subtitle: String
    let year: ContributionYear?
    /// Passed through to the grid — 53 (a year) unless a windowed source
    /// (the social recent-weeks heatmap) draws fewer columns.
    var minColumns: Int = 53
    /// A real match from the same day in a prior year (delight pass
    /// 2026-07-21) — rides INSIDE this same card rather than competing for
    /// the feed's one-hero-per-source slot. nil renders nothing extra.
    var onThisDay: OnThisDay.Echo? = nil
    var onTapOnThisDay: (() -> Void)? = nil
    /// The year's draw-on (delight, 2026-08-03): a 0 → 1 mask sweeps the
    /// grid left to right, so the year fills the way it accrued — the
    /// balance sparkline's own draw-on grammar, at the heatmap's dose.
    /// Reduce Motion renders the full grid on the first frame.
    @State private var drawn: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        InsightCard {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                InsightHeader(title: title, subtitle: subtitle)
                Spacer(minLength: DS.Space.s2)
                // A year worth sharing (delight pass 2026-07-21) — the facts
                // as a line, the same honest voice the card itself wears; no
                // rendered image, just what the card already says.
                ShareLink(item: "\(title) — \(subtitle) 🍇", subject: Text(title)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.textTertiary)
                }
                .accessibilityLabel("Share")
            }
            ContributionGraph(year: year, minColumns: minColumns)
                .mask(alignment: .leading) {
                    GeometryReader { geo in
                        Rectangle().frame(width: geo.size.width * drawn)
                    }
                }
                .onAppear {
                    if reduceMotion { drawn = 1 } else {
                        withAnimation(.easeOut(duration: 0.6)) { drawn = 1 }
                    }
                }
            // `isLive` because this card HOLDS the echo's model across renders
            // and a heal can delete under it (COROLLARY 5 — a leaf view is
            // re-evaluated on the model's own observation, with no help from
            // the parent that built it).
            if let onThisDay, onThisDay.thing.isLive {
                Button {
                    DSHaptic.selection()
                    onTapOnThisDay?()
                } label: {
                    HStack(spacing: DS.Space.s2) {
                        // The picture itself, when the anniversary IS one
                        // (2026-07-31). Text-only was right while this card
                        // only ever appeared beside journals and note vaults,
                        // where a title is the thing; a Snapchat memory's
                        // title is a date, and a photograph from seven years
                        // ago is not something to describe in words when it's
                        // sitting in the store. Gated on `previewImageData` —
                        // never a fetch — so a journal or note anniversary,
                        // which is most of them, gets no placeholder square;
                        // `PhotoWell` then draws the bytes (decoded once, and
                        // redaction-aware, unlike a bare `Image`).
                        if onThisDay.thing.previewImageData != nil {
                            PhotoWell(thing: onThisDay.thing, size: 34)
                                .accessibilityHidden(true)
                        }
                        Text(onThisDay.label)
                            .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                        Spacer(minLength: DS.Space.s2)
                        Text(onThisDay.thing.title)
                            .dsText(.subhead13).fontWeight(.semibold)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .accessibilityHidden(true)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DS.textTertiary)
                    }
                    .padding(.top, DS.Space.s1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A ranked-bars leaderboard (top senders, subreddits, artists, played games).
/// One GeometryReader lays out every bar; the bars are proportional to the top
/// group, the count sits at the trailing edge.
struct LeaderboardHero: View {
    let board: FeedInsight.Leaderboard
    /// The bars' grow-on (delight, 2026-08-03): each bar grows from its
    /// seed width to its real share, staggered top to bottom — the chart
    /// drawing the ranking rather than presenting it pre-drawn. The same
    /// per-appearance contract as `RowEntrance` and the sparkline draw-on;
    /// Reduce Motion renders the final widths on the first frame.
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let rows = board.rows
        let maxV = max(rows.map(\.value).max() ?? 1, 1)
        InsightCard {
            InsightHeader(title: board.title, subtitle: board.subtitle)
            GeometryReader { geo in
                let w = geo.size.width
                let labelW = min(max(w * 0.4, 88), 148)
                let valueW: CGFloat = 40
                let barW = max(w - labelW - valueW - DS.Space.s2 * 2, 24)
                VStack(spacing: 8) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                        HStack(spacing: DS.Space.s2) {
                            Text(row.label)
                                .dsText(.callout15).foregroundStyle(DS.textPrimary)
                                .lineLimit(1).truncationMode(.tail)
                                .frame(width: labelW, alignment: .leading)
                            ZStack(alignment: .leading) {
                                Capsule().fill(DS.surfaceWell).frame(height: 8)
                                Capsule().fill(DS.tint.opacity(0.85))
                                    .frame(width: grown
                                           ? max(barW * CGFloat(row.value) / CGFloat(maxV), 4)
                                           : 4,
                                           height: 8)
                                    .animation(reduceMotion ? nil
                                               : DS.Motion.standard.delay(Double(i) * 0.05),
                                               value: grown)
                            }
                            .frame(width: barW)
                            Text(row.detail)
                                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                                .monospacedDigit().lineLimit(1)
                                .frame(width: valueW, alignment: .trailing)
                        }
                        .frame(height: 20)
                    }
                }
            }
            .frame(height: CGFloat(rows.count) * 28)
            .onAppear { grown = true }
        }
    }
}

/// A distribution bar — one stacked capsule split by share, with a legend below.
/// Bull/bear on a ticker feed, the arrival mix of a social feed.
struct DistributionHero: View {
    let dist: FeedInsight.Distribution
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let segments = dist.segments
        let total = max(segments.reduce(0) { $0 + $1.count }, 1)
        InsightCard {
            InsightHeader(title: dist.title, subtitle: dist.subtitle)
            GeometryReader { geo in
                let gaps = CGFloat(segments.count - 1) * 2
                HStack(spacing: 2) {
                    ForEach(segments) { seg in
                        color(seg.tone)
                            .frame(width: max((geo.size.width - gaps) * CGFloat(seg.count) / CGFloat(total), 3))
                    }
                }
                .clipShape(Capsule(style: .continuous))
            }
            .frame(height: 12)
            // The bar fills left to right (2026-08-04, prd §298) — a split is
            // read as proportions of one length, so revealing along that length
            // is the split being stated. The legend below simply follows.
            .chartWipe(reduceMotion: reduceMotion)
            HStack(spacing: DS.Space.s3) {
                ForEach(segments) { seg in
                    HStack(spacing: DS.Space.s1) {
                        Circle().fill(color(seg.tone)).frame(width: 7, height: 7)
                        Text("\(seg.label) \(seg.count)")
                            .dsText(.subhead13).foregroundStyle(DS.textSecondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func color(_ tone: FeedInsight.Tone) -> Color {
        switch tone {
        case .positive: TokenChartStyle.accent(up: true, scheme: scheme)
        case .negative: TokenChartStyle.accent(up: false, scheme: scheme)
        case .neutral:  DS.textTertiary
        case .accent:   DS.tint
        case .alt1:     .purple
        case .alt2:     .pink
        }
    }
}

/// A thumbnail mosaic — a 4-across wall of a source's own images (NFT art,
/// pins, product shots, video thumbs). `Color.clear` carries the aspect ratio so
/// the grid self-sizes; RemoteThumb handles caching and dead-image fallback.
struct ImageMosaicHero: View {
    let mosaic: FeedInsight.Mosaic
    /// The medium's own color, averaged from the newest piece of art, spent as
    /// a soft wash behind the shelf (prd §219). nil until it resolves — and it
    /// stays nil for a near-colorless average, because a grey wash is just
    /// dirt on the card. Media sources only: an OpenSea or Shopify shelf is
    /// whatever the seller uploaded, so those cards stay neutral.
    @State private var wash: Color?

    /// How this medium lays out: how many across, how many rows, and the tile
    /// aspect. A source with no declared medium keeps the square 4-across grid
    /// this card has always drawn.
    private var layout: (columns: Int, maxRows: Int, aspect: CGFloat) {
        guard let art = mosaic.art else { return (4, 2, 1) }
        return (art.shelf.columns, art.shelf.maxRows, art.aspect)
    }

    var body: some View {
        let l = layout
        let shown = Array(mosaic.tiles.prefix(l.columns * l.maxRows))
        let rows = max(1, Int(ceil(Double(shown.count) / Double(l.columns))))
        // The block's own aspect derives the height from the width: with
        // `columns` tiles of aspect `a` across and `rows` down, the whole
        // block is (columns · a / rows) wide-to-tall.
        let blockAspect = CGFloat(l.columns) * l.aspect / CGFloat(rows)
        InsightCard {
            InsightHeader(title: mosaic.title, subtitle: mosaic.subtitle)
            Color.clear
                .aspectRatio(blockAspect, contentMode: .fit)
                .overlay {
                    GeometryReader { geo in
                        let gap: CGFloat = 4
                        let tileW = (geo.size.width - gap * CGFloat(l.columns - 1)) / CGFloat(l.columns)
                        let tileH = tileW / l.aspect
                        let radius = min(DS.Radius.control, min(tileW, tileH) * 0.22)
                        VStack(spacing: gap) {
                            ForEach(0..<rows, id: \.self) { r in
                                HStack(spacing: gap) {
                                    ForEach(0..<l.columns, id: \.self) { c in
                                        let idx = r * l.columns + c
                                        if idx < shown.count {
                                            RemoteArt(urlString: shown[idx].url,
                                                      width: tileW, height: tileH,
                                                      fallback: mosaic.fallback,
                                                      freshness: shown[idx].freshness,
                                                      cornerRadius: radius)
                                        } else {
                                            Color.clear.frame(width: tileW, height: tileH)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                // The wash sits BEHIND the art and bleeds past its edges, so
                // the card glows in the medium's color rather than tinting the
                // words — the header stays plain ink, which keeps the type
                // ramp doing the hierarchy.
                .background {
                    if let wash {
                        RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous)
                            .fill(LinearGradient(colors: [wash.opacity(0.38), wash.opacity(0.05)],
                                                 startPoint: .top, endPoint: .bottom))
                            .padding(-DS.Space.s3)
                            .blur(radius: 18)
                            .allowsHitTesting(false)
                    }
                }
        }
        .task(id: mosaic.tiles.first?.url) { await loadWash() }
    }

    /// Reads the color off the newest art — an image the shelf is downloading
    /// anyway, so the wash costs no extra request.
    private func loadWash() async {
        guard mosaic.art != nil, let first = mosaic.tiles.first?.url else { return }
        guard case .image(let img, _) = await RemoteImageLoader.load(
            urlString: first, targetSide: 96) else { return }
        guard let color = RemoteImageLoader.averageColor(of: img) else { return }
        withAnimation(DS.Motion.standard) { wash = Color(uiColor: color) }
    }
}


/// A treemap of what a screenshot library is ABOUT — the terms and names OCR
/// lifts off the pixels (`Thing.ocrTopics`), sized by how many screenshots each
/// covers (2026-07-30, the Photos feed's hero, ahead of the capture-year
/// heatmap). §145 wash: one hue, opacity by share, the biggest cell brightest —
/// magnitude is the only thing the fill says, exactly as the wallet holdings
/// map and the All feed's themes map read.
///
/// Display-only, like `LeaderboardHero` and `DistributionHero`: every cell is a
/// fact the pixels state, and none is a door — the honesty rule bars a
/// half-wired scope filter, so the map presents rather than pretends to
/// navigate. The 4×3 unit-grid tiling lives in `UnitTreemap` (shared with the
/// receipts screen's reach map since 2026-08-04) — see its doc for why the
/// slots are rank-ordered rather than area-proportional.
struct TopicMapHero: View {
    let map: FeedInsight.TopicMap

    var body: some View {
        let cells = Array(map.cells.prefix(UnitTreemap<EmptyView>.maxCells))
        let maxCount = max(cells.first?.count ?? 1, 1)
        InsightCard {
            InsightHeader(title: map.title, subtitle: map.subtitle)
            UnitTreemap(count: cells.count, height: Self.boardHeight) { i in
                let cell = cells[i]
                VStack(alignment: .leading, spacing: 2) {
                    Text(cell.label)
                        .dsText(.callout15).fontWeight(.semibold)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(2).minimumScaleFactor(0.82)
                    Text("\(cell.count)")
                        .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                        .monospacedDigit()
                    Spacer(minLength: 0)
                }
                .padding(DS.Space.s3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background {
                    ZStack {
                        DS.surfaceSheet
                        DS.tint(magnitude: Double(cell.count) / Double(maxCount))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                }
            }
        }
    }

    private static let boardHeight: CGFloat = 200
}


/// A stream that is ON RIGHT NOW, at frame size (prd §219, 2026-07-25).
///
/// §164 already carved out the exception this cashes in: "a single item may
/// claim the head only while it is a LIVE STATE rather than a landed thing",
/// and until now Twitch spent that grant on nothing but sort order — its feed
/// led with no head at all, because a mosaic of expired stream frames would
/// claim broadcasts that ended. A stream that IS on has no such problem: the
/// frame is true for exactly as long as it's shown.
///
/// Honest by construction, twice over. The caller derives this row from
/// `TwitchIngest.liveRefs` (the source's own current-live set, never the row's
/// age), so when the broadcast ends the card doesn't fade or go stale — it
/// stops existing. And the frame loads `perishable`, so a second broadcast can
/// never wear the first one's picture out of the cache.
struct LiveStreamHero: View {
    let thing: Thing
    var onOpen: () -> Void

    /// Liveness guard (build 188 — see `ThingRowKeying.swift`). SwiftUI
    /// re-evaluates a LEAF view's body on the model's own observation,
    /// independent of the parent that made it, so a guard in the parent's
    /// `ForEach` closure cannot protect a row already in the tree. The
    /// original body moved to `liveBody`; everything it reads now sits behind
    /// this check.
    var body: some View {
        if thing.isLive { liveBody }
    }

    @ViewBuilder private var liveBody: some View {
        Button(action: onOpen) {
            Color.clear
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    GeometryReader { geo in
                        if let url = thing.previewImageURL, !url.isEmpty {
                            RemoteArt(urlString: url,
                                      width: geo.size.width, height: geo.size.height,
                                      fallback: "Twitch", perishable: true,
                                      cornerRadius: DS.Radius.widget)
                        } else {
                            ZStack {
                                DS.fillFaint
                                BridgeIcon(name: "Twitch", size: 44)
                            }
                        }
                    }
                }
                // A scrim only where the words are — the frame is the point,
                // and a full-surface dim would mute the one image on screen
                // that's actually happening right now.
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, .black.opacity(0.75)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 96)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            // The dot breathes (delight, 2026-08-03) — lawful
                            // looping motion because this card only EXISTS
                            // while the broadcast is live (`TwitchIngest.
                            // liveRefs` derives it; an ended stream doesn't
                            // fade, it stops existing), so the pulse can
                            // never claim liveness the card doesn't have.
                            Circle().fill(DS.confirm).frame(width: 7, height: 7)
                                .breathing()
                            Text("Live").dsText(.label12).foregroundStyle(.white)
                        }
                        Text(thing.title)
                            .dsText(.body17)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
                    .padding(DS.Space.s3)
                }
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
                .shadow(color: DS.cardShadow, radius: 18, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Live now, \(thing.title)"))
        .accessibilityAddTraits(.isButton)
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
    @Environment(\.openURL) private var openURL

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
                    .accessibilityHidden(true)
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
        // A URL-shaped id is a door, not a thing (a wallet's NFT strip,
        // 2026-07-14: the piece lives on OpenSea, not in the corpus) — the
        // tap opens it directly instead of the thing-id vocabulary.
        if thingId.hasPrefix("http"), let url = URL(string: thingId) {
            Button {
                DSHaptic.selection()
                openURL(url)
            } label: { frame }
            .buttonStyle(.plain)
        } else {
            frame.pinnedRowActions(id: thingId, openable: openable,
                                   open: thingOpen, unpin: nil, handoff: thingHandoff)
        }
    }
}

/// A flexible-size remote image — the same bytes `RemoteThumb` would fetch,
/// but scaled to FILL whatever frame the caller gives it instead of
/// RemoteThumb's fixed icon-square shape (which the large-form grid/hero/
/// attached-post-image layouts all need). Rides `RemoteImageLoader` — the
/// shared downsample + bounded decoded cache — since 2026-07-13: the first
/// pass decoded CDN originals at FULL resolution and held one per visible
/// tile, so a real Pinterest/RSS corpus put Home tens of full-res bitmaps
/// deep — a device-only jetsam kill mid-compose ("Home loads partway, then
/// the app dies"; the sim never reproduced it). 1200px covers a full-width
/// hero at 3× exactly.
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
                        .accessibilityHidden(true)
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
        switch await RemoteImageLoader.load(urlString: urlString, targetSide: 1200) {
        case .image(let ui, let fresh):
            // Fade only genuine arrivals; a cache hit lands flat (the same
            // arrival grammar RemoteThumb follows).
            if fresh {
                withAnimation(DS.Motion.standard) { image = ui }
            } else {
                image = ui
            }
        case .transientFailure, .dead:
            failed = !Task.isCancelled
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            // The glint fades a just-landed row's tint away; under Reduce
            // Motion it simply starts faded (2026-08-04, prd §299).
            guard !reduceMotion else { glinted = true; return }
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
        TokenChartStyle.accent(change: chart?.change ?? 0, scheme: scheme)
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
        .dsHover()
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
/// tried the same day and read as noise). Magnitude is size plus the §145
/// neutral tint wash (token maps first, extended to every map 2026-07-21 —
/// one hue, opacity by share, never a per-cell palette); identity is the
/// white label and the token/bridge icons.
private struct GenTagMap: View {
    let id: String
    let el: GenEl
    /// Preview mode (TagMapPreview): the starter shape before tags exist —
    /// muted fill, no tap targets, no weekend share.
    var preview = false
    /// Error mode (TagMapError): the preview's muted, untappable geometry, but
    /// STATIC — it does not breathe, because nothing is pending (2026-07-17).
    /// An unreachable pinned wallet with no last-known card to show; the
    /// subline names the fix. Implies `preview` at the call site.
    var error = false
    @Environment(\.genProjectTap) private var projectTap
    @Environment(\.genZoomNS) private var zoomNS
    @Environment(\.genModuleLarge) private var large
    @Environment(\.genSizeToggle) private var sizeToggle
    /// nil off the board; `small` gives the map a shorter, fewer-cell 1×1
    /// tile (prd 58h) — a treemap needs area, so it skips `wide`.
    @Environment(\.genSpan) private var span
    /// True inside the agent's own answer column (2026-07-20) — tightens
    /// `boardHeight` below; see `genAgentAnswerContext`'s own doc comment.
    @Environment(\.genAgentAnswerContext) private var inAgentAnswer
    /// The treemap's cell stagger, its weekend magnitude sweep and the
    /// preview's breathing loop all honour Reduce Motion (2026-08-04, prd
    /// §299). The breathe is the one that mattered most: a `repeatForever`
    /// under a preference asking for less motion is the worst case in the app.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A cell's tap stays in the agent (§225) rather than a no-op — see the
    /// cell button's own comment. nil off the board, exactly like
    /// `genProjectTap` outside it.
    @Environment(\.genAskRequest) private var askRequest
    /// The entrance plays once per screen appearance (§3); filter and theme
    /// re-renders never replay it.
    @State private var settled = false
    /// The starter preview breathes slowly — "waiting to fill". One of the
    /// app's two sanctioned liveness loops (the other: the berry while an
    /// answer is in flight, 2026-07-13) — each exists only while something
    /// real is pending, never as decoration.
    @State private var breathe = false

    /// Grid areas (col, row, w, h) on a 4×3 unit grid, largest-first — read
    /// from `UnitTreemap`, which owns the ONE table every treemap in the app
    /// tiles on. It is not spelled here (2026-08-07): a private copy of the
    /// table is exactly how the wallet's holdings map and the receipts / x402
    /// / topic maps came to disagree, which `UnitTreemap`'s own doc says must
    /// never happen ("the small map and the big one can never disagree about
    /// which is largest"). The six-cell layout was corrected on 2026-08-06 to
    /// run 4·2·2·2·1·1 — non-increasing, so a lower rank can never draw
    /// bigger — and this copy kept the inverted one, where rank 3 got a single
    /// unit while ranks 4 and 5 got two. `EmptyView` names the generic
    /// parameter and nothing else; `frames` is a pure static over the count.
    private var frames: [(Int, Int, Int, Int)] {
        UnitTreemap<EmptyView>.frames(items.count)
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
    /// Inside an agent ANSWER the map tightens to 160 (2026-07-20): feed
    /// proportions at the answer column's width left the big cells mostly
    /// empty air — same data, denser read. Token maps (the wallet's holdings)
    /// are 160 EVERYWHERE now (prd §145, 2026-07-21, user: "why does it need
    /// to be so large?") — 220 was inherited from the Home-board module era,
    /// sized for tag maps whose cells also stack a "N things" count line;
    /// token cells never show that line, so the map was holding room it
    /// never used. One height with the answer column, on purpose.
    private var boardHeight: CGFloat {
        if inAgentAnswer { return 160 }
        if span == .small { return 150 }
        if large { return 320 }
        return iconMode == "token" ? 160 : 220
    }

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
            if preview, !error, !reduceMotion {
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
                let on = !animated || settled || reduceMotion
                // An icon rides above the name in "source" (an exact bridge,
                // via BridgeIcon — no fetch, never wrong) or beside it in
                // "token" mode (a bundled local mark, or none at all rather
                // than a wrong one). A project cell carries neither — see
                // GenTagMap's iconMode doc.
                let label = cellLabel(item: item, frame: f)
                    .padding(iconMode == "token" && f.3 < 2 ? DS.Space.s2 : DS.Space.s3)
                    .frame(width: w, height: h, alignment: .topLeading)
                    .background {
                        // Tiles are CARDS, literally (2026-07-10, user):
                        // the exact sheet surface the Settings tiles and
                        // Pinned card use. Magnitude is size, the treemap's
                        // real voice; identity is the label ink and the
                        // token/bridge icons. TOKEN cells additionally wear
                        // the sanctioned magnitude wash (prd §145, 2026-07-21
                        // — the user re-ruled with the smaller map in front
                        // of them, amending 2026-07-10's no-wash ruling for
                        // this mode only): DS.tint(magnitude:) at the cell's
                        // true USD share, largest brightest. The preview
                        // breathes the surface itself: shape without
                        // claiming substance.
                        ZStack {
                            DS.surfaceSheet
                            if !preview {
                                // Every map wears it now, not just token maps
                                // (2026-07-21, user: "applying the same wash to
                                // the themes") — the Themes lede on the All
                                // feed was the last flat treemap in the app.
                                // One tint, opacity by share, biggest cell
                                // brightest. One hue on purpose: a per-theme
                                // palette was pitched the same day and declined
                                // ("I don't want all these random colors"), so
                                // magnitude stays the only thing the fill says.
                                // A TOKEN map's cell additionally wears the
                                // token's OWN color, at that same magnitude
                                // opacity (prd §158, 2026-07-21): hue is
                                // identity, size and saturation are still
                                // magnitude. A token whose brand color we
                                // don't actually know keeps the neutral wash —
                                // see TokenHue.
                                //
                                // The `iconMode` guard is load-bearing, not
                                // leftover: `item.tag` is a project NAME on a
                                // theme map, and a tag that happens to spell a
                                // ticker ("OP", "ARB") would otherwise paint
                                // that theme in a token's brand color — hue
                                // claiming an identity it doesn't have.
                                if iconMode == "token",
                                   let wash = TokenHue.wash(for: item.tag,
                                                            share: usdShare(of: item)) {
                                    wash
                                } else {
                                    DS.tint(magnitude: usdShare(of: item))
                                }
                            }
                        }
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
                            // A holdings cell with a route opens that token's
                            // own chart (2026-07-14); routeless (a native
                            // coin) — the whole map routes to the Wallet
                            // screen instead of a dead-end empty tag view
                            // (2026-07-10).
                            if iconMode == "token" {
                                // Carry the cell's own symbol (item.tag) into the
                                // sentinel so the quick sheet names the token from
                                // the first frame — Dexscreener only ever refines
                                // it (adds the full name), never supplies the
                                // ticker we already hold here. A symbol with a
                                // colon would break the parse, so guard it.
                                let sym = item.tag.contains(":") ? "" : item.tag
                                projectTap?(item.route.map { r in
                                    sym.isEmpty ? "@token:\(r)" : "@token:\(r):\(sym)"
                                } ?? "@wallet")
                            } else if inAgentAnswer, let askRequest {
                                // Stay in the agent (ruling 8/9) rather than a
                                // no-op (§225): `genProjectTap` is nil inside
                                // the agent's answer column (a Home-board-only
                                // route), so the brief's themes map cell did
                                // nothing at all when tapped. Bare name, the
                                // same convention `readingCard`'s own "See the
                                // rest" residual link already uses for a
                                // computed topic word — whatever answers a
                                // real tag also answers a theme cluster.
                                askRequest(item.tag)
                            } else {
                                projectTap?(item.tag)
                            }
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
    private func entrance(order: Int) -> Animation? {
        if reduceMotion { return nil }
        return isWeekend
            ? DS.Motion.standard.delay(Double(order) * 0.35 / 3)
            : DS.Motion.standard.delay(Double(order) * 0.035)
    }

    /// One cell's content. Token cells changed shape with the 160pt map
    /// (prd §145, 2026-07-21): a 1-unit-tall cell (~48pt) can't stack a 20pt
    /// icon over a 17pt label anymore, so the icon goes INLINE with the
    /// symbol — which is also what makes the smaller map fit at all. Cells
    /// state the value their area encodes (the "@v:" ref marker): bottom of
    /// a tall cell, trailing on a wide 1-unit cell, dropped on a 1×1 (no
    /// room — the area still speaks). Tag/source cells keep the stacked
    /// layout and the "N things" count line unchanged.
    @ViewBuilder
    private func cellLabel(item: KindCountRow.Item, frame f: (Int, Int, Int, Int)) -> some View {
        if iconMode == "token" {
            if f.3 >= 2 {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: DS.Space.s2) {
                        TokenIcon(symbol: item.tag, size: 20)
                        Text(item.tag)
                            .dsText(.body17)
                            .foregroundStyle(preview ? DS.textTertiary : DS.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                            .allowsTightening(true)
                    }
                    Spacer(minLength: 0)
                    if !preview, let value = item.value {
                        Text(value)
                            .dsText(.subhead13).fontWeight(.semibold)
                            .foregroundStyle(DS.textPrimary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                HStack(spacing: DS.Space.s2) {
                    TokenIcon(symbol: item.tag, size: 16)
                    Text(item.tag)
                        .dsText(.callout15)
                        .foregroundStyle(preview ? DS.textTertiary : DS.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .allowsTightening(true)
                    if !preview, f.2 >= 2, let value = item.value {
                        Spacer(minLength: 0)
                        Text(value)
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textSecondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
        } else {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                if iconMode == "source" {
                    BridgeIcon(name: item.tag, size: 20)
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
                // as unfinished). 1-unit-tall cells skip it (no vertical
                // room; the line would draw past the tile onto its neighbor).
                // "plain" mode skips it everywhere (2026-07-25, the Today
                // brief's themes map): where arrival volume is explicitly not
                // news, printing the tally the area already draws is the same
                // fact twice — and it's the half nobody asked for. The count
                // still arrives on the ref; it just sizes the cell now.
                if !preview, f.3 >= 2, iconMode != "plain" {
                    Text(item.n == 1 ? "1 thing" : "\(item.n) things")
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }

    /// The cell's true USD share of the whole map — the wash's magnitude.
    /// Cell weights are sqrt-scaled (`WalletIngest.treemapWeight`), so
    /// squaring undoes it: n² is proportional to the position's USD value.
    /// Through DS.tint(magnitude:) a ~45% position washes at ~0.16 opacity
    /// and a sliver at ~0.07 — the ladder the approved mockup wore.
    private func usdShare(of item: KindCountRow.Item) -> Double {
        let total = items.reduce(0.0) { $0 + Double($1.n) * Double($1.n) }
        guard total > 0 else { return 0 }
        return Double(item.n) * Double(item.n) / total
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
                    .accessibilityHidden(true)
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

/// A top-level answer module's placeholder (§198) — the card margins the
/// Today brief's OWN module family wears (`DayNotes`/`MoneyHero`/`TilePair`/
/// `Bars`/`SourceMix` all close on `.padding(.horizontal, s4).padding(.top,
/// s2)`), so the skeleton IS the layout rather than a generic loading bar: the
/// screen's full shape is visible before a single module has content, and each
/// block simply becomes its real component once that module's own line
/// streams in. The app has a SECOND top-padding convention too (`GenInsight`/
/// `GenWidget`, `s4` — `RootShell.modelDoc`'s "ins, res" answers) that this
/// skeleton doesn't match as closely; picked `s2` because the brief is what
/// this shipped for and is the majority of its own family, and either choice
/// is an 8pt one-time settle on resolve, not a functional gap.
///
/// A plain static fill, deliberately — a shimmering skeleton would be a
/// decorative loop, and this app sanctions those only while something real is
/// pending (`GenTagMap`'s starter preview is the surviving one; the agent's
/// breathing berry retired 2026-07-31, and THIS view took its place as the
/// in-flight state — see `Composer`'s answer stream).
struct GenSkeletonBlock: View {
    var minHeight: CGFloat = 96
    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous)
            .fill(DS.surfaceSheet)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s2)
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
                            .dsText(.badgeInitial11)
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

// MARK: - Answer-column charts (prd §146)

/// Shared CSV-number parsing for the answer charts — the series a composer
/// hands inline (a wallet's recorded value samples, per-day counts). Inline,
/// not a pointer like `TokenChip`, because these are LOCAL facts already read
/// (not a live fetch that could fail): the honest thing is to draw exactly
/// what was recorded. A quoted arg keeps its commas (the parser only splits at
/// depth 0 outside quotes), so the whole series arrives as one string.
private func genCSVDoubles(_ s: String) -> [Double] {
    s.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
}

/// `Stack`'s chapter ids — the comma-joined arg 1, as a set. A `Set` because
/// the Stack asks it a containment question once per child; a partial arg
/// mid-stream just yields a shorter set (the last id may still be arriving),
/// which costs a chapter its extra air for one frame and self-heals — never a
/// mis-parse, since ids are matched whole.
func genChapterIDs(_ s: String) -> Set<String> {
    Set(s.split(separator: ",")
         .map { $0.trimmingCharacters(in: .whitespaces) }
         .filter { !$0.isEmpty })
}

/// The Today brief as a FRONT PAGE (§274, 2026-08-01) — the chapter-carrying
/// `Stack` on a surface wide enough for columns.
///
/// The brief is the one document in the app that is MODULE-shaped rather than
/// prose-shaped, and on a Mac window a 700pt column left a third of the
/// canvas empty either side (user: "it still has gaps at the side"). The
/// chapters (§272-era) already mark where one movement ends and the next
/// begins, so they become the column seams: the masthead and the first
/// chapter — the money story, which ruling 2026-07-23 says is never split —
/// span the full width like a broadsheet's lead, and the remaining chapters
/// flow into two columns. It is a NEWSPAPER, not a bento: no module grows to
/// fill a cell (the module doctrine — a module is exactly as big as its
/// fact); width buys modules SIDE BY SIDE, never bigger ones.
///
/// Two stability rules, both for the ~20s progressive assembly:
///   • Blocks alternate columns BY INDEX, never by measured height — a block
///     landing later can never move an earlier one to rebalance, so the page
///     only ever appends.
///   • The width decision is MEASURED (`onGeometryChange`), not inferred
///     from idiom — a Mac window dragged narrow gets the single column, and
///     the same window dragged wide gets the columns back.
///
/// `qualifies` is consulted by BOTH deciders — the Composer's per-turn width
/// cap and this view's own layout — so "the cap widened but the column never
/// split" (a single file of modules stretched across 1040pt) is structurally
/// impossible, not just untested.
struct GenFrontPage: View {
    let el: GenEl
    let els: GenEls
    let chapters: Set<String>
    let inAgentAnswer: Bool
    @State private var width: CGFloat = 0

    /// Two readable columns (≥ ~390pt each) plus the gutter. Below this the
    /// single column is the better page, whatever the idiom says.
    private static let columnsFloor: CGFloat = 820

    /// Whether a doc has the STRUCTURE a front page needs: a root `Stack`
    /// carrying chapters, with at least two chapter blocks left over after
    /// the head. Width is deliberately not part of this — the caller asking
    /// (the Composer's turn cap) has no measurement yet, and a qualifying
    /// doc on a narrow window simply falls back to the single column below.
    static func qualifies(_ els: GenEls) -> Bool {
        guard let root = els["root"], root.comp == "Stack" else { return false }
        let chapters = genChapterIDs(root.str(1))
        guard !chapters.isEmpty else { return false }
        let segs = segments(refs: root.refs(0), chapters: chapters)
        return segs.count - headSegmentCount(segs) >= 2
    }

    var body: some View {
        let refs = el.refs(0)
        let segs = Self.segments(refs: refs, chapters: chapters)
        let headCount = Self.headSegmentCount(segs)
        Group {
            if width >= Self.columnsFloor, segs.count - headCount >= 2 {
                frontPage(segs: segs, headCount: headCount)
            } else {
                // The single column, exactly as the plain Stack draws it —
                // capped back to the reading column and centered, so a
                // qualifying doc in a `.wide` container on a narrow window
                // renders indistinguishably from the pre-§274 brief.
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    ForEach(refs, id: \.self) { module($0) }
                }
                .frame(maxWidth: PadLayout.readingMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        // Full proposed width, measured OUTSIDE the fallback's own cap — the
        // question is "what could the page use", not "what did it use".
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private func frontPage(segs: [[String]], headCount: Int) -> some View {
        let head = segs.prefix(headCount).flatMap { $0 }
        let blocks = Array(segs.dropFirst(headCount))
        // Alternation by index — see the stability rule in the header doc.
        let left = blocks.indices.filter { $0.isMultiple(of: 2) }.map { blocks[$0] }
        let right = blocks.indices.filter { !$0.isMultiple(of: 2) }.map { blocks[$0] }
        return VStack(alignment: .leading, spacing: DS.Space.s2) {
            ForEach(head, id: \.self) { module($0) }
            HStack(alignment: .top, spacing: DS.Space.s4) {
                column(left)
                column(right)
            }
        }
    }

    private func column(_ blocks: [[String]]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ForEach(blocks.flatMap { $0 }, id: \.self) { module($0) }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// One module, wearing the same chapter air the single column gives it.
    /// The column-topping chapters keep theirs too — the two columns open
    /// level with each other, and dropping it would put the first module of
    /// each column at a different distance from the head than every later
    /// chapter sits from its predecessor.
    private func module(_ ref: String) -> some View {
        GenRender(id: ref, els: els, slot: inAgentAnswer ? .block : .none)
            .padding(.top, chapters.contains(ref) ? DS.Space.s4 : 0)
    }

    /// The refs cut at every chapter opener. Segment 0 is whatever precedes
    /// the first chapter (the composer never marks the first id, so it is
    /// never empty in practice, but the walk tolerates it).
    private static func segments(refs: [String], chapters: Set<String>) -> [[String]] {
        var segs: [[String]] = []
        var cur: [String] = []
        for ref in refs {
            if chapters.contains(ref), !cur.isEmpty { segs.append(cur); cur = [] }
            cur.append(ref)
        }
        if !cur.isEmpty { segs.append(cur) }
        return segs
    }

    /// The head is at least the pre-chapter segment. A lone module there is a
    /// masthead line (the brief's lede), and a one-line masthead is not a
    /// lead story — the first chapter joins it, which in the brief is the
    /// money hero and everything glued to it (`pair`, `tmkt` — one story,
    /// never split, ruling 2026-07-23).
    private static func headSegmentCount(_ segs: [[String]]) -> Int {
        guard let first = segs.first else { return 0 }
        return first.count == 1 && segs.count > 1 ? 2 : 1
    }
}

/// ValueSpark(eyebrow, subline, "v0,v1,…") — a balance sparkline over recorded
/// value samples. Reuses `TokenChartPlot` so the wallet's own value line wears
/// the exact anatomy a token curve does; the delta pill is computed first→last,
/// the same math `WalletAsk.answer()`'s line uses, so the two never disagree.
/// Fewer than two points draws nothing (a one-point "line" is a dot pretending
/// to be a trend) — the composer only emits it once history spans.
private struct GenValueSpark: View {
    let el: GenEl
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    private var series: [Double] { genCSVDoubles(el.str(2)) }
    private var change: Double {
        guard let first = series.first, first > 0, let last = series.last else { return 0 }
        return (last - first) / first
    }
    private var accent: Color { TokenChartStyle.accent(change: change, scheme: scheme) }

    var body: some View {
        Group {
            if series.count >= 2 {
                let chart = TokenChart(closes: series, price: series.last ?? 0, change: change)
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    HStack(spacing: DS.Space.s2) {
                        Text(el.str(0)).dsText(.callout15).fontWeight(.semibold)
                            .foregroundStyle(DS.textPrimary)
                        Spacer(minLength: DS.Space.s2)
                        TokenDeltaPill(change: change, label: "")
                    }
                    TokenChartPlot(chart: chart, accent: accent, height: 90, pulses: false)
                        .mask(alignment: .leading) {
                            GeometryReader { geo in
                                Rectangle().frame(width: revealed ? geo.size.width : 0)
                            }
                        }
                    if !el.str(1).isEmpty {
                        Text(el.str(1)).dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.s4)
                .dsWidgetSurface()
                .padding(.horizontal, DS.Space.s4)
                .padding(.top, DS.Space.s2)
                .onAppear {
                    guard !revealed else { return }
                    if reduceMotion { revealed = true }
                    else { withAnimation(.easeOut(duration: 0.7)) { revealed = true } }
                }
            }
        }
    }
}

/// Bars(eyebrow, subline, "c0,c1,…", "l0,l1,…") — counts over time (things
/// saved per day, activity per day), hand-drawn as capsules so nothing draws
/// an axis or grid (the hairline law holds on charts too). The last bar reads
/// as "now" in full tint; earlier bars sit at a calmer opacity. An all-zero
/// series still draws its baseline row honestly (a quiet week is a real
/// answer, not an empty state).
private struct GenBars: View {
    let el: GenEl
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The skyline builds (delight, 2026-07-22): bars rise from the baseline
    /// with a small stagger, the TALLEST landing last — the day's shape
    /// assembling like a little skyline rather than popping in all at once.
    /// Shared by every `Bars` caller (the Today brief's hour strip, the
    /// per-source/category recap's weekly chart) — a nicer entrance for one
    /// component is a nicer entrance everywhere it's used.
    @State private var risen = false

    private var counts: [Double] { genCSVDoubles(el.str(2)) }
    private var labels: [String] {
        el.str(3).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }
    /// Each bar's RANK by height, ascending (0 = shortest, last = tallest) —
    /// the entrance delay follows this, not array index, so the tallest bar
    /// is the one that lands last regardless of where it sits in the strip.
    private var risingOrder: [Int] {
        let ranked = counts.indices.sorted { counts[$0] < counts[$1] }
        var order = [Int](repeating: 0, count: counts.count)
        for (rank, i) in ranked.enumerated() { order[i] = rank }
        return order
    }

    var body: some View {
        Group {
            if !counts.isEmpty {
                let peak = max(counts.max() ?? 1, 1)
                let order = risingOrder
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    if !el.str(0).isEmpty {
                        Text(el.str(0)).dsText(.callout15).fontWeight(.semibold)
                            .foregroundStyle(DS.textPrimary)
                    }
                    if !el.str(1).isEmpty {
                        Text(el.str(1)).dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    }
                    HStack(alignment: .bottom, spacing: DS.Space.s2) {
                        ForEach(Array(counts.enumerated()), id: \.offset) { i, c in
                            let last = i == counts.count - 1
                            let delay = reduceMotion ? 0 : Double(order[i]) * 0.04
                            VStack(spacing: DS.Space.s1) {
                                Spacer(minLength: 0)
                                // A zero count reads as a DOT, not a 2px sliver
                                // (2026-07-22) — at that height a "real" bar is
                                // indistinguishable from a rendering glitch; a
                                // small dot reads as "deliberately nothing".
                                if c <= 0 {
                                    Circle()
                                        .fill(last ? DS.tint.opacity(0.5) : DS.tint.opacity(0.25))
                                        .frame(width: 4, height: 4)
                                        .scaleEffect(risen ? 1 : 0.2)
                                        .opacity(risen ? 1 : 0)
                                        .animation(reduceMotion ? nil
                                                   : .spring(response: 0.4, dampingFraction: 0.7).delay(delay),
                                                   value: risen)
                                } else {
                                    Capsule(style: .continuous)
                                        .fill(last ? DS.tint : DS.tint.opacity(0.35))
                                        .frame(height: risen ? max(3, 64 * CGFloat(c / peak)) : 0)
                                        .animation(reduceMotion ? nil
                                                   : .spring(response: 0.46, dampingFraction: 0.68).delay(delay),
                                                   value: risen)
                                }
                                if i < labels.count {
                                    Text(labels[i]).dsText(.label12)
                                        .foregroundStyle(last ? DS.textSecondary : DS.textTertiary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 84)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.s4)
                .dsWidgetSurface()
                .padding(.horizontal, DS.Space.s4)
                .padding(.top, DS.Space.s2)
                .onAppear {
                    guard !risen else { return }
                    if reduceMotion { risen = true }
                    else {
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(30))
                            risen = true
                        }
                    }
                }
            }
        }
    }
}

/// ChartCard(symbol, chain, address) — a single token's FULL scrubbable curve
/// as an answer (the tall dose of `TokenChip`'s sparkline). Reuses
/// `TokenChartView`, which already owns its per-range fetch, the draw-on
/// reveal, and the press-then-drag scrub that lets a vertical scroll still win
/// (the DragGesture-vs-ScrollView law) — so it's safe inside the answer
/// column's ScrollView. A dead symbol falls back to a plain honest line.
private struct GenChartCard: View {
    let el: GenEl
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if !el.str(0).isEmpty {
                Text(el.str(0)).dsText(.callout15).fontWeight(.semibold)
                    .foregroundStyle(DS.textPrimary)
            }
            TokenChartView(chain: el.str(1), address: el.str(2)) {
                Text("Couldn't load this chart.")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.s4)
        .dsWidgetSurface()
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s2)
    }
}

/// StatRow(v0, l0, v1, l1, v2, l2) — up to three glanceable number tiles (a
/// tile with an empty value drops out). Neutral ink by ruling: a bare count
/// has no up/down direction to color (honesty §83) — any sign a value carries
/// lives in its own text ("+4.0%"), never in the tile's fill.
private struct GenStatRow: View {
    let el: GenEl
    private var tiles: [(value: String, label: String)] {
        [(value: el.str(0), label: el.str(1)),
         (value: el.str(2), label: el.str(3)),
         (value: el.str(4), label: el.str(5))]
            .filter { !$0.value.isEmpty }
    }

    var body: some View {
        Group {
            if !tiles.isEmpty {
                HStack(spacing: DS.Space.s2) {
                    ForEach(Array(tiles.enumerated()), id: \.offset) { _, t in
                        VStack(alignment: .leading, spacing: DS.Space.s1) {
                            Text(t.value).dsText(.heading22).foregroundStyle(DS.textPrimary)
                                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                            Text(t.label).dsText(.subhead13).foregroundStyle(DS.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DS.Space.s3)
                        .background(DS.surfaceWell,
                                    in: RoundedRectangle(cornerRadius: DS.Radius.widget,
                                                         style: .continuous))
                    }
                }
                .padding(.horizontal, DS.Space.s4)
                .padding(.top, DS.Space.s2)
            }
        }
    }
}

/// AllocBar(eyebrow, "label|usd,label|usd,…") — how the total splits across
/// watched wallets, one segmented bar. Monochrome by the one-tint law: every
/// segment is DS.tint, stepped down in opacity so proportion reads without a
/// rainbow. Labels below name each share ("Main 60% · Cold 40%").
private struct GenAllocBar: View {
    let el: GenEl
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private struct Seg { let label: String; let usd: Double }
    private var segs: [Seg] {
        el.str(1).split(separator: ",").compactMap { part -> Seg? in
            let f = part.split(separator: "|", maxSplits: 1)
            guard f.count == 2, let usd = Double(f[1].trimmingCharacters(in: .whitespaces)),
                  usd > 0 else { return nil }
            return Seg(label: f[0].trimmingCharacters(in: .whitespaces), usd: usd)
        }
    }

    var body: some View {
        let segs = segs
        let total = segs.reduce(0) { $0 + $1.usd }
        return Group {
            if segs.count >= 2, total > 0 {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    if !el.str(0).isEmpty {
                        Text(el.str(0)).dsText(.callout15).fontWeight(.semibold)
                            .foregroundStyle(DS.textPrimary)
                    }
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(Array(segs.enumerated()), id: \.offset) { i, s in
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(DS.tint.opacity(max(0.3, 1 - Double(i) * 0.28)))
                                    .frame(width: max(4, (geo.size.width - CGFloat(segs.count - 1) * 2)
                                                      * CGFloat(s.usd / total)))
                            }
                        }
                    }
                    .frame(height: 14)
                    // Fills along its own axis (2026-08-04, prd §298), like
                    // every other share-of-a-whole bar in the app.
                    .chartWipe(reduceMotion: reduceMotion)
                    Text(segs.map { "\($0.label) \(Int(($0.usd / total * 100).rounded()))%" }
                        .joined(separator: " · "))
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.s4)
                .dsWidgetSurface()
                .padding(.horizontal, DS.Space.s4)
                .padding(.top, DS.Space.s2)
            }
        }
    }
}

// MARK: - Today brief (prd §166 — the mosaic's own modules)

/// DayNotes([noteRefs]) — the Today brief's synthesis card: the agent's read
/// of the day, two or three observations, each a deterministic pattern that
/// actually fired (`TodayBrief.observations`). The card never pads: a day with
/// no pattern emits no `DayNotes` line at all, so this view always has
/// something real to say.
///
/// Children render FLAT (the eager-head lesson, CLAUDE.md): the note lines
/// dispatch directly rather than through GenRender → AnyView → mountIn, the
/// same discipline `GenWidget.rowContent` already keeps.
private struct GenDayNotes: View {
    let el: GenEl
    let els: GenEls

    var body: some View {
        let refs = el.refs(0).filter { els[$0]?.comp == "DayNote" }
        Group {
            if !refs.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    ForEach(refs, id: \.self) { ref in
                        if let child = els[ref] { GenDayNoteLine(el: child) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.s4)
                // The TINTED surface `Insight` already wears everywhere else
                // (2026-07-22), not a plain card: one grammar for agent voice
                // — tinted surface = the agent talking, ink cards = your
                // things. On `dsWidgetSurface` the synthesis card was
                // indistinguishable from the modules it's summarizing.
                .background(DS.tintDim,
                            in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .padding(.horizontal, DS.Space.s4)
                .padding(.top, DS.Space.s2)
            }
        }
    }
}

/// DayNote(glyph, text, thingID) — one observation. The glyph is the source's
/// own SF mark, in tint; the sentence carries the fact. A note that names a
/// real thing opens it (staying inside the agent, ruling 9); one that doesn't
/// is plain text, never a dead control.
private struct GenDayNoteLine: View {
    let el: GenEl
    @Environment(\.genThingOpen) private var thingOpen
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let id = el.str(2)
        let line = HStack(alignment: .top, spacing: DS.Space.s3) {
            Image(systemName: el.str(0).isEmpty ? "sparkles" : el.str(0))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.tint)
                .frame(width: 20)
                .padding(.top, 2)
                .accessibilityHidden(true)
            GenSignedText(el.str(1), scheme: scheme)
                .dsText(.callout15)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            // A note that opens a real thing SAYS so (honesty rule: a live
            // control must look live). One that names no thing carries no
            // chevron rather than a dead one.
            if !id.isEmpty {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.textTertiary)
                    .padding(.top, 3)
                    .accessibilityHidden(true)
            }
        }
        if id.isEmpty {
            line
        } else {
            Button { thingOpen?(id) } label: { line }
                .buttonStyle(.plain)
        }
    }
}

/// A sentence whose signed percentages wear their own direction — "+10.1%" in
/// the gain accent, "−3.2%" in the loss accent, the rest in the caller's ink.
/// Deterministic and local: it colors what the composer already wrote, and
/// never invents a figure. A value that rounds to flat (`0.0%`) keeps the
/// body ink, per §83 — no direction, no color.
private func GenSignedText(_ s: String, scheme: ColorScheme) -> Text {
    var out = Text("")
    var buffer = ""
    func flushPlain() {
        if !buffer.isEmpty { out = out + Text(buffer); buffer = "" }
    }
    // Split on spaces and color any token that IS a signed percentage. Token
    // granularity keeps this honest — a percentage embedded in a longer word
    // is left alone rather than half-colored.
    let parts = s.split(separator: " ", omittingEmptySubsequences: false)
    for (i, part) in parts.enumerated() {
        let token = String(part)
        let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
        if let pct = signedPercent(trimmed), abs(pct) >= 0.05 {
            flushPlain()
            let tail = token.dropFirst(trimmed.count)
            out = out + Text(trimmed)
                .foregroundStyle(TokenChartStyle.accent(change: pct / 100, scheme: scheme))
                .fontWeight(.semibold)
            if !tail.isEmpty { out = out + Text(String(tail)) }
        } else {
            buffer += token
        }
        if i < parts.count - 1 { buffer += " " }
    }
    flushPlain()
    return out
}

/// "+10.1%" / "−3.2%" → the number, or nil when the token isn't one.
private func signedPercent(_ token: String) -> Double? {
    guard token.hasSuffix("%"), let first = token.first,
          first == "+" || first == "-" || first == "\u{2212}" else { return nil }
    let body = token.dropLast()
        .replacingOccurrences(of: "\u{2212}", with: "-")   // real minus sign
    return Double(body)
}

/// The shared "biggest left, up to three stacked right" mini-treemap layout —
/// the money hero's holdings map and the brief's own source mix (2026-07-23)
/// are two instances of the same compact shape. Only the LAYOUT lives here;
/// each caller keeps its own cell face and its own share math (a holdings
/// cell's `n` is pre sqrt-scaled by `WalletIngest.treemapWeight`, so squaring
/// it recovers true USD proportion — a source cell's `n` is a raw
/// thing-count, so its share is linear). Cleanup, 2026-07-23: these had
/// drifted into two independently-maintained copies of the same ~30 lines.
private struct MiniTreemap<Cell: View>: View {
    let items: [KindCountRow.Item]
    let cell: (KindCountRow.Item, Int) -> Cell

    init(items: [KindCountRow.Item], @ViewBuilder cell: @escaping (KindCountRow.Item, Int) -> Cell) {
        self.items = items
        self.cell = cell
    }

    var body: some View {
        Group {
            if !items.isEmpty {
                HStack(spacing: DS.Space.s1) {
                    cell(items[0], 0)
                    if items.count > 1 {
                        VStack(spacing: DS.Space.s1) {
                            ForEach(Array(items.dropFirst().prefix(3).enumerated()), id: \.offset) { i, item in
                                cell(item, i + 1)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

private extension View {
    /// The chrome every mini-treemap cell wears — rounded wash background,
    /// bottom-leading content, and the largest-first staggered entrance
    /// (2026-07-22's delight pass, shared rather than copy-pasted per cell).
    func miniTreemapCellChrome<Background: View>(index: Int, cellsShown: Bool, reduceMotion: Bool,
                                                 @ViewBuilder background: () -> Background) -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.horizontal, DS.Space.s2)
            .padding(.vertical, DS.Space.s1)
            .background {
                ZStack { DS.surfaceSheet; background() }
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .scaleEffect(cellsShown ? 1 : 0.85)
            .opacity(cellsShown ? 1 : 0)
            .animation(reduceMotion ? nil
                       : .spring(response: 0.36, dampingFraction: 0.72).delay(Double(index) * 0.06),
                       value: cellsShown)
    }
}

/// MoneyHero(total, delta, "v0,v1,…", subline, [cells], anchor, txTitle,
/// txMeta, txID, rawTotal, rawAnchorTotal) — the Today brief's one fused
/// visualization (direction B2's hero): the combined total and its day move,
/// then the holdings treemap and the balance line SIDE BY SIDE, then what
/// actually settled.
///
/// Fused rather than stacked on purpose — the wallet is the only always-on
/// aggregate in the brief, so it earns both shapes at once, while every other
/// module carries exactly one. The compact treemap here draws the same cells
/// (and the same `TokenHue` washes at the same squared magnitude) the full
/// `TagMap` draws elsewhere, so the small read and the big one can't disagree
/// about which holding is largest.
/// DayLede(text, dateline, figure, direction) — the day brief's opening
/// sentence, in display type, above everything (2026-07-25, user: "that line
/// should be above wallet").
///
/// No surface, by design: it is a sentence on the page, not a card. The whole
/// point of putting it here rather than under the hero's total is that the
/// screen opens with WORDS — "Up $1,247 today. ETH did the lifting." — and
/// then hands the number the room to be a number in.
///
/// Three things landed here on 2026-07-31, all of them the same idea — that
/// this is a masthead and had been drawing as a caption:
///
///   • The DATELINE above it. The whisper capsule that opens this screen says
///     "Your Wednesday"; the screen itself named the day nowhere.
///   • `heading28` instead of `heading22`. See that rung's own note in
///     Typography: 22 is what every card title and tray header in the app
///     wears, so the sentence and the hero's `price40` under it — same rounded
///     bold face, eight points apart — read as one label-over-value unit.
///   • The FIGURE wears its direction. `GenSignedText` already colors signed
///     percentages inside the synthesis notes; the day's biggest number, in
///     the one sentence most likely to carry it, was the app's only uncolored
///     move. Same rule, and §83's corollary comes with it: the composer sends
///     no `direction` for a rung that isn't a gain or a loss (a health factor,
///     a handle, a deadline), so those stay in body ink.
///
/// Flat by law: two `Text`s in a `VStack`, no nesting beyond that. This draws
/// at the head of the agent's Stack, the exact position that has tipped the
/// main-thread stack three times (see CLAUDE.md's eager-head depth lesson).
private struct GenDayLede: View {
    let el: GenEl
    @Environment(\.colorScheme) private var scheme

    /// The sentence with its figure accented — and the plain sentence
    /// whenever the accent can't be placed with certainty. `range(of:)`
    /// rather than any parsing of the text: the composer hands over the exact
    /// substring it built the sentence from, so a miss means the two
    /// disagreed, and the honest response to that is no color at all.
    private var sentence: Text {
        let text = el.str(0)
        let figure = el.str(2)
        let direction = el.str(3)
        guard !figure.isEmpty, direction == "up" || direction == "down",
              let range = text.range(of: figure) else { return Text(text) }
        let accent = TokenChartStyle.accent(change: direction == "up" ? 1 : -1, scheme: scheme)
        return Text(String(text[text.startIndex..<range.lowerBound]))
            + Text(figure).foregroundStyle(accent)
            + Text(String(text[range.upperBound...]))
    }

    var body: some View {
        // Self-padded, like every other component in this file (the answer
        // column doesn't inset its children — `GenTagMap`, `GenWidget` and the
        // rest each own their horizontal margin). A bare `maxWidth: .infinity`
        // ran the sentence off both edges, starting left of the masthead above
        // it.
        VStack(alignment: .leading, spacing: 2) {
            if !el.str(1).isEmpty {
                Text(el.str(1))
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
            }
            sentence
                .dsText(.heading28)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Space.s4)
    }
}

private struct GenMoneyHero: View {
    let el: GenEl
    @Environment(\.colorScheme) private var scheme
    @Environment(\.genThingOpen) private var thingOpen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The total ROLLS from the day's anchor value to the current one on
    /// mount (delight, 2026-07-22) — the same odometer idiom the wallet
    /// feed's own hero balance already uses (`WalletFeedTiles`), so the number
    /// tells the day's story before the delta pill summarizes it. nil until
    /// the entrance fires, so the very first frame paints the FINAL number
    /// plainly rather than a flash of the anchor (no anchor means no move to
    /// roll — the honest case a fresh/flat wallet already falls into).
    @State private var displayedTotal: Double?
    /// The delta pill waits for the roll to settle (2026-07-22) — popping in
    /// WITH the rolling digits argued with itself about what to look at first.
    @State private var pillShown = false
    @State private var lineRevealed = false
    @State private var cellsShown = false

    private var items: [KindCountRow.Item] { KindCountRow.parse(el.refs(4), cap: 4) }
    private var series: [Double] { genCSVDoubles(el.str(2)) }
    private var rawTotal: Double? { Double(el.str(9)) }
    private var rawAnchor: Double? { Double(el.str(10)) }
    /// The day move as a fraction, parsed back off the composed "+1.5%" — the
    /// pill and the line's accent both key off it, so an empty delta simply
    /// shows neither rather than claiming flatness.
    private var change: Double? {
        let raw = el.str(1).replacingOccurrences(of: "%", with: "")
        guard !raw.isEmpty, let pct = Double(raw) else { return nil }
        return pct / 100
    }

    /// The same squared weighting `GenTagMap.usdShare` uses, so a cell's wash
    /// intensity is identical in both maps.
    private func share(_ item: KindCountRow.Item) -> Double {
        let total = items.reduce(0.0) { $0 + Double($1.n) * Double($1.n) }
        guard total > 0 else { return 0 }
        return Double(item.n) * Double(item.n) / total
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                // The wallet room's own money ramp (2026-07-22) — this was
                // `stat24`, the generic number tier, while every other total
                // in the app (WalletFeedTiles' own hero balance) speaks in the
                // rounded `price40` rung. Same fact, two voices; one wallet
                // grammar wins.
                Text(TokenStats.compact(displayedTotal ?? rawTotal ?? 0))
                    .dsText(.price40)
                    .foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity
                                       : .numericText(value: displayedTotal ?? rawTotal ?? 0))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: DS.Space.s2)
                if let change {
                    TokenDeltaPill(change: change, label: "")
                        .scaleEffect(pillShown ? 1 : 0.6)
                        .opacity(pillShown ? 1 : 0)
                }
            }
            HStack(alignment: .bottom, spacing: DS.Space.s3) {
                treemap
                    .frame(maxWidth: .infinity)
                if series.count >= 2 {
                    let c = change ?? 0
                    VStack(alignment: .trailing, spacing: 2) {
                        TokenChartPlot(chart: TokenChart(closes: series,
                                                         price: series.last ?? 0,
                                                         change: c),
                                       accent: TokenChartStyle.accent(change: c, scheme: scheme),
                                       height: heroHeight - 14,
                                       // Live-streaming's pulse would overclaim
                                       // here (this reads once, not per visit —
                                       // the 2026-07-11 ruling `ValueSpark`
                                       // already follows); the STATIC dot is
                                       // the honest twin, and the reveal mask
                                       // below makes it "land" exactly when
                                       // the line finishes drawing (2026-07-22).
                                       pulses: false, endpointDot: true)
                            // The line DRAWS (delight, 2026-07-22) — the same
                            // left-to-right reveal `GenValueSpark` already
                            // uses, so a static composed doc gets the same
                            // "this just arrived" feel a real chart earns.
                            .mask(alignment: .leading) {
                                GeometryReader { geo in
                                    Rectangle().frame(width: lineRevealed ? geo.size.width : 0)
                                }
                            }
                        // The line's own anchor — the same job ValueSpark's
                        // subline does ("since Jul 18"). Without it the curve
                        // claims a span it never states.
                        if !el.str(5).isEmpty {
                            Text(el.str(5))
                                .dsText(.label11)
                                .foregroundStyle(DS.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: heroHeight)
            // With no sparkline to host it (a stale last-known read has no
            // live curve), the anchor's "as of Xh ago" still shows — the
            // honesty marker (§83) must never depend on the curve being there.
            if series.count < 2, !el.str(5).isEmpty {
                Text(el.str(5))
                    .dsText(.label11)
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
            }
            // What settled. A NAMED transaction is a real thing, so it draws
            // as a real row — glyph, title, meta, chevron — not as tertiary
            // caption text (2026-07-22: dead-looking text that opens something
            // is an honesty bug, not a style choice). Only the no-single-
            // transaction cases fall back to the plain subline.
            if !el.str(6).isEmpty {
                Button { thingOpen?(el.str(8)) } label: {
                    HStack(spacing: DS.Space.s3) {
                        KindGlyph(kind: .transaction, size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(el.str(6))
                                .dsText(.callout15)
                                .foregroundStyle(DS.textPrimary)
                                .lineLimit(1)
                            if !el.str(7).isEmpty {
                                Text(el.str(7))
                                    .dsText(.subhead13)
                                    .foregroundStyle(DS.textTertiary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: DS.Space.s2)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DS.textTertiary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(el.str(8).isEmpty)
            } else if !el.str(3).isEmpty {
                Text(el.str(3))
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.s4)
        .dsWidgetSurface()
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s2)
        .onAppear { fireEntrance() }
    }

    /// One-shot entrance, gated on `displayedTotal == nil` the same way
    /// `GenTagMap`'s `settled`/`GenValueSpark`'s `revealed` guard their own
    /// mount animation — a re-render (theme change, Dynamic Type) must never
    /// replay it.
    private func fireEntrance() {
        guard displayedTotal == nil else { return }
        guard !reduceMotion, let rawTotal, let rawAnchor, rawAnchor > 0
        else {
            // No real anchor to roll from (a fresh wallet, or Reduce Motion) —
            // show the true number immediately, the honest static case.
            displayedTotal = rawTotal
            pillShown = true
            lineRevealed = true
            cellsShown = true
            return
        }
        displayedTotal = rawAnchor
        withAnimation(.easeOut(duration: 0.7)) { lineRevealed = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(30))
            // Each cell owns its own delayed spring via `.animation(value:)`
            // below — a plain set here, not a second `withAnimation` wrap.
            cellsShown = true
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) { displayedTotal = rawTotal }
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.62)) { pillShown = true }
        }
    }

    private var heroHeight: CGFloat { 84 }

    /// The compact map: the largest holding takes the left column, the rest
    /// stack beside it. Deliberately not the 4×3 template `GenTagMap` tiles —
    /// at this height a six-cell grid renders unreadable slivers.
    @ViewBuilder private var treemap: some View {
        MiniTreemap(items: items) { item, index in cell(item, index: index) }
    }

    private func cell(_ item: KindCountRow.Item, index: Int) -> some View {
        // The cell SHOWS its value (2026-07-22). The doc's cells already carry
        // one (`@v:$92` — `KindCountRow.Item.value`), and dropping it left
        // large empty rectangles labelled only by symbol: a treemap whose
        // whole point is magnitude, refusing to state the magnitude it has.
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Text(item.tag)
                .dsText(.label12)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let value = item.value, !value.isEmpty {
                Text(value)
                    .dsText(.label11)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        // Cells stagger in LARGEST FIRST (2026-07-22) — the render order
        // already IS magnitude order (the doc's cells arrive pre-sorted
        // descending, `WalletIngest.treemapCells`), so following index
        // order for the entrance delay is narrative order for free: ETH
        // enters first because ETH matters most.
        .miniTreemapCellChrome(index: index, cellsShown: cellsShown, reduceMotion: reduceMotion) {
            if let wash = TokenHue.wash(for: item.tag, share: share(item)) {
                wash
            } else {
                DS.tint(magnitude: share(item))
            }
        }
    }
}

/// LeadRow(title, meta, imageURL, thingID, source) — one item PROMOTED: its
/// art as a banner, the title on up to three full lines, meta beneath.
///
/// The brief's doctrine is "the thing itself, not a count" — but the first cut
/// used the ordinary one-line `Row` for its promoted read, which showed the
/// thing while cutting off what it is ("Apple is reportedly testing a MacB…",
/// caught on-device 2026-07-22). Feed rows elsewhere keep their one-line
/// discipline on purpose; a lead is one item GIVEN ROOM, which is the entire
/// meaning of promoting it.
///
/// 2026-07-31 finished that thought: the art led instead of sitting beside the
/// words as a 48pt square, which had left the screen's most-promoted module as
/// its least-promoted-looking one.
private struct GenLeadRow: View {
    let el: GenEl
    @Environment(\.genThingOpen) private var thingOpen

    /// A letterbox, not a 16:9 frame (2026-07-31). At the card's inner width
    /// (~333pt on a 6.3" screen) sixteen-by-nine is ~187pt of picture over a
    /// two-line title, which makes the module the image rather than the read.
    /// A banner states "this one has a face" and leaves the words the lead.
    private var bannerHeight: CGFloat { 128 }

    /// A banner is drawn only for art we have no reason to think is gone.
    /// `RemoteThumb`'s 2026-07-10 ruling — "a 404'd Steam header or expired
    /// frame must not read worse than having no art at all" — is written for a
    /// 48pt tile; at 333×128 a placeholder is seven times the hole, so a URL
    /// the loader has already blacklisted doesn't get a slot at all and the
    /// row degrades to the title-and-meta shape a lead with no image already
    /// has. A FRESH failure can't be known before the fetch, so that one falls
    /// to `RemoteArt`'s own `fallback` (the source's mark) below.
    private var showsBanner: Bool {
        let url = el.str(2)
        return !url.isEmpty && !RemoteImageLoader.isDead(url)
    }

    var body: some View {
        Button { thingOpen?(el.str(3)) } label: {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                // The art LEADS now, at the card's own width, where it used to
                // be a 48pt square beside the title. §166's doctrine for this
                // module is "the thing itself, not a count" and "a lead is one
                // item GIVEN ROOM" — but a thumbnail the size of a favicon,
                // under a card header, in a stack of full-width
                // visualizations, was the least promoted thing on a screen
                // whose whole argument is that this item is worth opening.
                // Inset rather than full-bleed on purpose: the row sits inside
                // `GenWidget`'s card, and bleeding to the card edge would mean
                // negative padding fighting the header's own inset.
                if showsBanner {
                    GeometryReader { geo in
                        RemoteArt(urlString: el.str(2),
                                  width: geo.size.width, height: bannerHeight,
                                  fallback: el.str(4),
                                  cornerRadius: DS.Radius.control)
                    }
                    .frame(height: bannerHeight)
                }
                VStack(alignment: .leading, spacing: 3) {
                    // `heading17` (the app's headline rung), not `callout15`
                    // semibold: with the art carrying the module's weight, a
                    // title at row size read as a caption under its own
                    // picture. Three lines rather than two — the two-line
                    // clamp is what cut "Apple is reportedly testing a MacB…"
                    // on device in the first place (see this type's own note),
                    // and a wider title block has fewer of them to fill.
                    Text(el.str(0))
                        .dsText(.heading17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if !el.str(1).isEmpty {
                        Text(el.str(1))
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.vertical, DS.Space.s2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(el.str(3).isEmpty)
    }
}

/// LeadPost(author, text, avatarURL, meta, thingID) — the social lead: the
/// post that names you, given the same room `LeadRow` gives a read. Distinct
/// from `PostRow` (which stays exactly as the board and the widget rows use
/// it) because it adds the meta line the brief needs — "12 replies · 2 more
/// mentions behind it" — and because a lead's words earn two lines.
private struct GenLeadPost: View {
    let el: GenEl
    @Environment(\.genThingOpen) private var thingOpen

    var body: some View {
        Button { thingOpen?(el.str(4)) } label: {
            // The avatar leads a HEADER row now rather than a column of its
            // own (2026-07-31), which gives the words the card's full width
            // instead of the 32pt-narrower gutter left beside a face. Someone
            // addressing you by name is the most human thing this screen
            // carries; it should not be the narrowest.
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                HStack(spacing: DS.Space.s2) {
                    RemoteThumb(urlString: el.str(2), size: 36, fallback: el.str(0), circular: true)
                    if !el.str(0).isEmpty {
                        Text(el.str(0))
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                // `body17` — the app's READING rung (Typography's 2026-07-25
                // reading-band pass), not `callout15`. These are a person's
                // actual words quoted in full; every other quotation of real
                // prose in the app reads at this size, and the composer
                // already clamps the post to 200 characters upstream, so the
                // five-line allowance is bounded rather than open-ended.
                Text(el.str(1))
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !el.str(3).isEmpty {
                    Text(el.str(3))
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.vertical, DS.Space.s2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(el.str(4).isEmpty)
    }
}

/// AskMore(label, query) — the residue, with somewhere to go. "The rest keeps
/// circling Samsung ›" hands the agent that query rather than ejecting to a
/// filtered feed: ruling 9 (staying is the default; a bare tap never ejects)
/// plus ruling 8 (a new ask pushes a fresh answer onto the Stack), so the
/// session model already had the right move and this just uses it.
private struct GenAskMore: View {
    let el: GenEl
    @Environment(\.genAskRequest) private var askRequest

    var body: some View {
        Group {
            // No handler (outside the agent) = no control, rather than a
            // control that does nothing — the honesty rule's oldest clause.
            if let askRequest, !el.str(1).isEmpty {
                Button { askRequest(el.str(1)) } label: {
                    HStack(spacing: DS.Space.s1) {
                        Text(el.str(0))
                            .dsText(.subhead13)
                            .foregroundStyle(DS.tint)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DS.tint)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.vertical, DS.Space.s2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// TilePair([tileRefs]) — the brief's glanceable pair, side by side.
///
/// NOT `Bento` (which is what this was first built on, caught on-device
/// 2026-07-22): Bento is a two-column `LazyVGrid`, so a day offering only ONE
/// tile — no watchlist watched, or nothing due — rendered a half-width card
/// beside an empty column, which reads as a layout bug rather than as "there
/// is one thing here". An HStack of equal-width children degrades honestly
/// instead: one tile simply spans the row.
private struct GenTilePair: View {
    let el: GenEl
    let els: GenEls

    var body: some View {
        let refs = el.refs(0).filter { els[$0] != nil }
        Group {
            if !refs.isEmpty {
                HStack(alignment: .top, spacing: DS.Space.s3) {
                    ForEach(refs, id: \.self) { ref in
                        if let child = els[ref] {
                            switch child.comp {
                            case "MoversTile": GenMoversTile(el: child)
                            case "NextTile":   GenNextTile(el: child)
                            default:           EmptyView()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, DS.Space.s4)
                .padding(.top, DS.Space.s2)
            }
        }
    }
}

/// MoversTile(label, "SYM|+4.2%|close,close,…;SYM|flat|close,…") — the
/// watchlist at a glance, as one half of the brief's tile pair. Rows join on
/// ";" (not ",") because each row's own closes are themselves comma-joined —
/// each row DRAWS its move (a tiny sparkline) rather than only stating it.
///
/// Unlike `StatRow`'s deliberately neutral counts, a price move HAS a
/// direction, so it wears one: gains and losses take the chart accent. A move
/// that rounds to flat is composed as the word "flat" upstream and reads in
/// tertiary ink — §83: no sign and no color for a change that rounds to zero.
private struct GenMoversTile: View {
    let el: GenEl
    @Environment(\.colorScheme) private var scheme
    @Environment(\.genThingOpen) private var thingOpen

    private struct Move { let symbol: String; let value: String; let closes: [Double]; let thingID: String }
    /// Tolerant on purpose: the composer always finishes a row with its third
    /// and fourth (closes, thing id) fields, but mid-STREAM a row's tail is
    /// still arriving character by character — requiring all four up front
    /// would hold the symbol and value off-screen until the whole line
    /// lands, instead of the row popping in immediately and the curve/tap
    /// completing a moment later (GenParser's "any prefix of any document
    /// renders" law).
    private var moves: [Move] {
        el.str(1).split(separator: ";").compactMap { part in
            let f = part.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false)
            guard f.count >= 2 else { return nil }
            let closes = f.count >= 3 ? genCSVDoubles(String(f[2])) : []
            let thingID = f.count == 4 ? String(f[3]) : ""
            return Move(symbol: f[0].trimmingCharacters(in: .whitespaces),
                        value: f[1].trimmingCharacters(in: .whitespaces),
                        closes: closes, thingID: thingID)
        }
    }

    private func ink(_ value: String) -> Color {
        guard let pct = Double(value.replacingOccurrences(of: "%", with: "")) else {
            return DS.textTertiary        // "flat" — no direction, no color
        }
        return TokenChartStyle.accent(change: pct / 100, scheme: scheme)
    }

    /// One watchlist line. `curve` is what `ViewThatFits` trades away first —
    /// the symbol and the move are the facts, the sparkline is their texture.
    ///
    /// The symbol also carries layout priority (2026-07-25). Before that it
    /// was the row's only compressible element — the value is `fixedSize`, the
    /// curve pinned at 44 — so in a narrow tile, or at a larger Dynamic Type
    /// size, the ticker absorbed the entire shortfall and drew as "E…", a row
    /// naming nothing.
    @ViewBuilder
    private func row(_ m: Move, curve: Bool) -> some View {
        HStack(spacing: DS.Space.s2) {
            Text(m.symbol)
                .dsText(.callout15)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
                .layoutPriority(1)
            // The row's own tiny curve (2026-07-23) — reusing `TokenPulse`'s
            // already-cached closes, so a watchlist row says the SHAPE of the
            // move, not only its sign. Flat draws in the value's own tertiary
            // ink (§83: no direction, no color).
            if curve, m.closes.count >= 2 {
                TokenChartPlot(chart: TokenChart(closes: m.closes,
                                                 price: m.closes.last ?? 0,
                                                 change: (Double(m.value.replacingOccurrences(of: "%", with: "")) ?? 0) / 100),
                               accent: ink(m.value),
                               height: 20,
                               pulses: false,
                               lineWidth: 1.5,
                               fillOpacity: 0)
                    .frame(width: 44)
            }
            Spacer(minLength: DS.Space.s2)
            Text(m.value)
                .dsText(.callout15).fontWeight(.semibold)
                .foregroundStyle(ink(m.value))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    var body: some View {
        let moves = moves
        return Group {
            if !moves.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text(el.str(0))
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textTertiary)
                    ForEach(Array(moves.enumerated()), id: \.offset) { _, m in
                        // A row opens its own watched token (§225) — the one
                        // module in the brief with no tap at all, until now;
                        // every other module already opens something.
                        Button { thingOpen?(m.thingID) } label: {
                            // All three parts, or the two that are the facts
                            // (2026-07-25). A flexible curve squeezed to a few
                            // points draws a vertical tick that reads as a
                            // rendering fault; ViewThatFits gives it its real
                            // 44 or drops it, and nothing in between.
                            ViewThatFits(in: .horizontal) {
                                row(m, curve: true)
                                row(m, curve: false)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(m.thingID.isEmpty)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.s4)
                // Both tiles stretch to the taller one (the same rule
                // `soloTileChrome` keeps for paired board tiles) — a short
                // card beside a tall one reads as a rendering fault, not as
                // "this one has less to say".
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .dsWidgetSurface()
            }
        }
    }
}

/// WalletFlow(windowLabel, "side|name|usd|count|other;…", inUSD, outUSD,
/// unpriced, spineAddress) — where the money moved, in the brief (§232).
///
/// A thin adapter, deliberately: it rebuilds `WalletFlow.Band` from the values
/// `TodayBrief.flowBand` serialised and hands it to the SAME `WalletFlowBand`
/// the wallet room draws, so the two can never diverge in appearance or in
/// what they claim. Nothing about the band's own rules (one shared scale, in
/// is green and out is never red, nothing tappable) is re-decided here.
///
/// It carries no `Thing` — `WalletFlowSource` reduced them to values at the
/// composer's boundary — so the liveness rules have nothing to bite on, which
/// is the same property the room's own card has.
private struct GenWalletFlow: View {
    let el: GenEl

    /// Rebuilt from the doc, or nil while the line is still arriving. A lane
    /// needs all five fields to mean anything (a half-parsed usd would draw a
    /// wrong-sized slab, which is worse than no slab), so an incomplete row is
    /// dropped rather than guessed at — and the `.block` slot holds the whole
    /// module behind a skeleton until its line completes anyway (§199).
    private var band: WalletFlow.Band? {
        var inLanes: [WalletFlow.Lane] = []
        var outLanes: [WalletFlow.Lane] = []
        for row in el.str(1).split(separator: ";") {
            let f = row.split(separator: "|", maxSplits: 4, omittingEmptySubsequences: false)
            guard f.count == 5, let usd = Double(f[2]), let count = Int(f[3]) else { continue }
            let isOther = f[4] == "1"
            let side = String(f[0])
            let lane = WalletFlow.Lane(id: "\(side):\(f[1])\(isOther ? ":other" : "")",
                                       name: String(f[1]), usd: usd,
                                       count: count, isOther: isOther)
            if side == "in" { inLanes.append(lane) } else { outLanes.append(lane) }
        }
        guard !inLanes.isEmpty || !outLanes.isEmpty,
              let inUSD = Double(el.str(2)), let outUSD = Double(el.str(3))
        else { return nil }
        return WalletFlow.Band(inLanes: inLanes, outLanes: outLanes,
                               inUSD: inUSD, outUSD: outUSD,
                               unpricedCount: Int(el.str(4)) ?? 0)
    }

    var body: some View {
        Group {
            if let band {
                WalletFlowBand(band: band, windowLabel: el.str(0),
                               spineAddress: el.str(5).isEmpty ? nil : el.str(5))
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, DS.Space.s2)
            }
        }
    }
}

/// NextTile(label, title, when, alert, thingID) — what's next, as the tile
/// pair's other half. Deadlines only (never calendar events — see
/// `TodayBrief.nextTile` for why that scoping is a ruling, not an omission).
/// The alert line carries the overdue tail in the loss accent; empty when
/// nothing is late.
private struct GenNextTile: View {
    let el: GenEl
    @Environment(\.colorScheme) private var scheme
    @Environment(\.genThingOpen) private var thingOpen

    var body: some View {
        let id = el.str(4)
        let card = VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(el.str(0))
                .dsText(.subhead13)
                .foregroundStyle(DS.textTertiary)
            Text(el.str(1))
                .dsText(.callout15).fontWeight(.semibold)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s1)
            Text(el.str(2))
                .dsText(.subhead13)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
            if !el.str(3).isEmpty {
                Text(el.str(3))
                    .dsText(.subhead13)
                    .foregroundStyle(TokenChartStyle.accent(change: -1, scheme: scheme))
                    .lineLimit(1)
                    .padding(.top, DS.Space.s1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.s4)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .dsWidgetSurface()
        if id.isEmpty {
            card
        } else {
            Button { thingOpen?(id) } label: { card }
                .buttonStyle(.plain)
        }
    }
}

/// SourceMix(eyebrow, subline, ["Source N", ...]) — the brief's WHERE-FROM
/// visualization (candidate A, 2026-07-23, user: "add A and B those are both
/// good components to have"), pairing the hour strip's WHEN. A compact,
/// self-contained cousin of the money hero's own mini-map — largest source
/// left, up to three more stacked beside it — rather than the board's full
/// `TagMap` (which carries pin/size-toggle/tap-to-feed chrome this smaller,
/// answer-column card doesn't need).
private struct GenSourceMix: View {
    let el: GenEl
    @State private var cellsShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// THREE cells — one big, two stacked (§194). Four (one big + three
    /// stacked) is what the money hero's map carries, but its cells are two
    /// bare text lines; a source cell also wears a `BridgeIcon`, and three of
    /// those stacked need ~190pt of intrinsic height. Forced into the map's
    /// frame they didn't compress — SwiftUI spills an over-tall child rather
    /// than clipping it, so the cells rendered straight out through the card's
    /// rounded edge (reported on-device 2026-07-23: "larger than the card and
    /// doesn't look good"). Three cells is also what the approved mockup drew,
    /// and the residual line names whatever they leave out.
    private var items: [KindCountRow.Item] { KindCountRow.parse(el.refs(2), cap: 3) }

    /// A source cell's magnitude is a raw thing-count (unlike the money
    /// hero's holdings cells, which `WalletIngest.treemapWeight` pre
    /// sqrt-scales) — so its share of the map is linear, not squared.
    private func share(_ item: KindCountRow.Item) -> Double {
        let total = items.reduce(0) { $0 + $1.n }
        guard total > 0 else { return 0 }
        return Double(item.n) / Double(total)
    }

    /// Taller than the money hero's 84 because every cell carries an icon on
    /// top of its two text lines. Sized so two stacked cells fit with real
    /// headroom rather than to-the-pixel — a to-the-pixel fit is one Dynamic
    /// Type step away from the overflow this replaced.
    private var mapHeight: CGFloat { 96 }

    var body: some View {
        let items = items
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    if !el.str(0).isEmpty {
                        Text(el.str(0))
                            .dsText(.callout15).fontWeight(.semibold)
                            .foregroundStyle(DS.textPrimary)
                    }
                    MiniTreemap(items: items) { item, index in cell(item, index: index) }
                        .frame(height: mapHeight)
                        // The backstop, not the fix (§194): the cell count and
                        // density above are what make this fit. But a map that
                        // somehow outgrows its frame again — an accessibility
                        // type size, a longer localized "N things" — must fail
                        // by cropping inside the card, never by drawing through
                        // its edge.
                        .clipped()
                    if !el.str(1).isEmpty {
                        Text(el.str(1))
                            .dsText(.label11)
                            .foregroundStyle(DS.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.s4)
                .dsWidgetSurface()
                .padding(.horizontal, DS.Space.s4)
                .padding(.top, DS.Space.s2)
                // A one-shot @State set — SwiftUI never replays a stale
                // value, so there's nothing here for a guard to protect
                // (unlike `GenMoneyHero.fireEntrance`'s multi-stage Task).
                .onAppear { cellsShown = true }
            }
        }
    }

    /// The icon rides INLINE with the name (§194) — stacked on its own line it
    /// made every cell a three-row block, which is what overflowed the map. The
    /// same move `GenTagMap.cellLabel` already makes for its short token cells,
    /// for the same reason: at this height a cell affords two rows, not three.
    private func cell(_ item: KindCountRow.Item, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: DS.Space.s1) {
                BridgeIcon(name: item.tag, size: 16)
                Text(item.tag)
                    .dsText(.label12)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(item.n == 1 ? String(localized: "1 thing") : String(localized: "\(item.n) things"))
                .dsText(.label11)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .miniTreemapCellChrome(index: index, cellsShown: cellsShown, reduceMotion: reduceMotion) {
            DS.tint(magnitude: share(item))
        }
    }
}

// MARK: - Kind-count refs

/// The parser for the `[Tag N, ...]` ref idiom every count-bearing element
/// reads — TagMap, the holdings and themes maps, the token strips.
///
/// It was a chip ROW too until 2026-08-01, when the only two elements that
/// rendered those chips (`KindBar`, `KindPills`) were deleted: no composer
/// had emitted either name in months, and their taps set the feed's kind
/// filter through a chip the person was never meant to manage (user: "i do
/// not want to see the x chips those are supposed to be internal only").
/// The parsing is untouched — it is the live half, and always was.
private enum KindCountRow {
    struct Item { let tag: String; let n: Int; var route: String? = nil; var value: String? = nil }

    /// "[Tag N, ...]" refs → items, count-ordered upstream. The one parser
    /// for the idiom — every map and strip reads it. `requireCount` drops
    /// refs with no trailing count: the cover uses it so a tag truncated by
    /// the stream never flashes a fallback chip (composed chips always carry
    /// counts, so nothing real is lost); bare tags elsewhere still count 1.
    /// A trailing " @t:chain:address" (holdings cells, 2026-07-14) is a
    /// route, never shown — it lets the cell's tap open that token's chart.
    /// " @v:$8.4K" (prd §145, 2026-07-21) is a display value the token cells
    /// SHOW — compact money form, guaranteed space-free by its builder.
    /// Both are sliced off the raw string (not re-tokenized) so every other
    /// ref keeps the old invariant: a bare ref renders exactly as written.
    static func parse(_ raw: [String], cap: Int = 5, requireCount: Bool = false) -> [Item] {
        raw.prefix(cap).compactMap { r in
            var body = r
            var route: String? = nil
            var value: String? = nil
            if let at = body.range(of: " @t:", options: .backwards),
               case let tail = body[at.upperBound...],
               !tail.isEmpty, !tail.contains(" ") {
                route = String(tail)
                body = String(body[..<at.lowerBound])
            }
            if let at = body.range(of: " @v:", options: .backwards),
               case let tail = body[at.upperBound...],
               !tail.isEmpty, !tail.contains(" ") {
                value = String(tail)
                body = String(body[..<at.lowerBound])
            }
            // A marker that hasn't finished ARRIVING yet (2026-07-22). Both
            // strips above require a complete `@x:value`, so mid-stream a cell
            // reads " @v" or " @v:" and the whole raw token became the label —
            // the Today brief's hero visibly flashed "ETH 95 @v" while its
            // treemap cells streamed in. Anything trailing that opens " @",
            // carries no space, and is too short to be a real marker is a
            // half-arrived one: drop it until the rest lands.
            if let at = body.range(of: " @", options: .backwards) {
                let tail = body[at.lowerBound...]
                if !tail.dropFirst().contains(" "), tail.count <= 4 {
                    body = String(body[..<at.lowerBound])
                }
            }
            let parts = body.split(separator: " ")
            if let last = parts.last, let n = Int(last) {
                return Item(tag: parts.dropLast().joined(separator: " "), n: n,
                            route: route, value: value)
            }
            return requireCount ? nil : Item(tag: body, n: 1, route: route, value: value)
        }
    }
}
