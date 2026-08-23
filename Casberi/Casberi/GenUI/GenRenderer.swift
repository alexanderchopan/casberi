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
    /// Opens a source's ROOM from a brief section header (prd §386j) — the
    /// brief as the app's index. nil everywhere the doc is not the brief, so
    /// a header outside it simply isn't a door.
    var genRoomOpen: ((String) -> Void)? {
        get { self[GenRoomOpenKey.self] }
        set { self[GenRoomOpenKey.self] = newValue }
    }
    /// True on a live answer's tree — cited rows glint once on mount.
    var genCitationGlint: Bool {
        get { self[GenCitationGlintKey.self] }
        set { self[GenCitationGlintKey.self] = newValue }
    }
}

/// Press a sentence, see its evidence (2026-08-14, prd §384): tapping an
/// answer's prose re-glints the grounding rows beneath it — provenance you
/// can FEEL by poking the claim, not just a badge to read. A process-wide
/// tick rather than per-tree plumbing: one answer surface is on screen at a
/// time, and both ends gate on `genAgentAnswerContext`, so a bump can only
/// ever reach rows in the agent's own column. (Several settled turns stacked
/// on screen all answer the same poke — accepted: every glinted row IS
/// evidence for the prose above it, so nothing false is highlighted.)
@MainActor
@Observable
final class GenEvidenceGlint {
    static let shared = GenEvidenceGlint()
    var tick = 0
    private init() {}
}

extension EnvironmentValues {
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
private struct GenRoomOpenKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}

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
            // The QUIET set (arg 2, prd §386d) — modules saying exactly what
            // they said last time this brief was shown, one step back so the
            // things that MOVED carry the eye. A reading, not a state: the
            // module is fully legible, fully interactive and fully spoken by
            // VoiceOver; only its visual weight yields. Absent everywhere but
            // the brief, and an empty arg is a no-op.
            //
            // 0.68 rather than a real fade: the module still has to be
            // READABLE — a step under half would trade a hierarchy cue for a
            // contrast failure, which is the wrong trade on the app's one
            // daily screen.
            let quiet = Set(genChapterIDs(el.str(2)))
            if chapters.isEmpty {
                ForEach(el.refs(0), id: \.self) { ref in
                    GenRender(id: ref, els: els, slot: inAgentAnswer ? .block : .none)
                        .opacity(quiet.contains(ref) ? 0.68 : 1)
                        // Addressable, so the brief's own section chips can
                        // scroll to a heading (prd §386i). `ForEach`'s
                        // `id: \.self` gives the row an identity for DIFFING;
                        // `ScrollViewProxy` needs an explicit `.id` to have
                        // something to scroll TO.
                        .id(ref)
                }
            } else {
                GenFrontPage(el: el, els: els, chapters: chapters,
                             quiet: quiet, inAgentAnswer: inAgentAnswer)
            }

        case "Section":     GenSection(el: el).mountIn()
        case "ClusterMap":  GenClusterMap(el: el).mountIn()
        case "DayFold":     GenDayFold(el: el).mountIn()
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
        case "Alerts":       GenAlerts(el: el).mountIn()
        case "Runway":       GenRunway(el: el).mountIn()
        case "ContactSheet": GenContactSheet(el: el).mountIn()
        case "Faces":        GenFaces(el: el).mountIn()

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
        case "Dial":         GenDial(el: el).mountIn()
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

    /// Re-glint the grounding rows under this claim (prd §384). Shared by the
    /// tap gesture and its VoiceOver rotor action so the two can never drift
    /// into doing different things — both are only attached inside an answer.
    private func glintEvidence() {
        DSHaptic.selection()
        GenEvidenceGlint.shared.tick += 1
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
            } else if inAgentAnswer {
                Text(el.str(0))
                    .dsText(.callout15)
                    .foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    // Press the claim, see the evidence (prd §384): inside an
                    // answer, tapping the prose re-glints the grounding rows
                    // beneath it. A supplementary gesture, not a control — no
                    // affordance is drawn, nothing navigates, and a doc with
                    // no rows simply answers with stillness.
                    .contentShape(Rectangle())
                    .onTapGesture { glintEvidence() }
                    // VoiceOver cannot perform a bare tap gesture, so the same
                    // move is offered as a rotor ACTION rather than a Button:
                    // this is supplementary and draws no affordance, and a
                    // button trait would announce a control that isn't one.
                    //
                    // The branch is what scopes it. `inAgentAnswer` is an
                    // environment flag that is FALSE everywhere else this
                    // prose renders, so an unconditional action would offer
                    // every VoiceOver user a rotor entry that does nothing —
                    // the dead control the honesty rule bans, and the exact
                    // defect App Store review rejected the Mac build for under
                    // 2.1(a), one surface over.
                    .accessibilityAction(named: Text("Show the evidence")) {
                        glintEvidence()
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
        // The agent-voice card's own elevated tone (2026-08-10) — the
        // ceiling step of the same neutral ramp every treemap now shares
        // (`DS.ink(magnitude: 1)`), not a hue. It still separates from a
        // plain `dsWidgetSurface` card the way the old tint wash did; it
        // just says "the agent is speaking" with lightness instead of color.
        .background(DS.ink(magnitude: 1), in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s4)
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .onTapGesture {
            let id = el.str(2)
            if !id.isEmpty { thingOpen?(id) }
            else if el.str(3) == "feed", let url = URL(string: "casberi://feed") { openURL(url) }
        }
        .dsTapCard()
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
    /// A pressed cell reports its day (prd §384) — nothing on this grid is
    /// just a picture. nil (the default) keeps every existing mount exactly
    /// as it was: no gesture, no hit shape, a Canvas and nothing else.
    var onPick: ((ContributionDay) -> Void)? = nil

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
        // The press (prd §384): a tap names the day under the finger. The
        // inverse of the Canvas's own cell arithmetic, run against the same
        // constants — a Canvas has no per-cell views to hit-test, so the
        // overlay computes (col, row) from the location and the closure gets
        // the REAL `ContributionDay`, count and date, never a guess. A tap in
        // a gap resolves to the nearest cell (a 7–11pt square is under the
        // 44pt floor by construction; forgiveness is the only honest target
        // here). Only mounted when a caller asked — a display-only grid stays
        // a Canvas and nothing else.
        .overlay {
            if onPick != nil {
                GeometryReader { geo in
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(SpatialTapGesture().onEnded { value in
                            pick(at: value.location, size: geo.size)
                        })
                        // …and on a Mac the cursor alone names the day
                        // (2026-08-17), with no click. A press is the honest
                        // gesture on a 7–11pt square under a finger; a pointer
                        // has no such constraint, and requiring a click to
                        // read a cell is asking for a commitment to get an
                        // answer. Routed through `pick` — the SAME inversion
                        // the tap uses — so hover can never name a different
                        // day than a click on the same cell.
                        .macHoverScrub { point in
                            guard let point else { return }
                            pick(at: point, size: geo.size, silent: true)
                        }
                }
            }
        }
    }

    /// The Canvas math, inverted. Any drift between this and the draw loop
    /// mis-names a day, which is why both read the same `gap`/`reference`
    /// constants and the same trailing-aligned origin.
    /// `silent` suppresses the selection haptic. A tap is a deliberate act and
    /// deserves the tick; a cursor crossing the grid would fire one per cell,
    /// which on a trackpad is a stutter rather than feedback.
    private func pick(at point: CGPoint, size: CGSize, silent: Bool = false) {
        guard let onPick else { return }
        let weeks = year?.weeks ?? []
        guard !weeks.isEmpty else { return }
        let cols = max(weeks.count, minColumns)
        let reference = max(cols, Self.referenceColumns)
        let gap = Self.gap
        let cell = min((size.width - gap * CGFloat(reference - 1)) / CGFloat(reference),
                       (size.height - gap * 6) / 7)
        guard cell > 0 else { return }
        let drawnWidth = CGFloat(cols) * cell + gap * CGFloat(cols - 1)
        let originX = max(0, size.width - drawnWidth)
        let col = Int(((point.x - originX) / (cell + gap)).rounded(.down))
        let row = Int((point.y / (cell + gap)).rounded(.down))
        guard col >= 0, col < weeks.count, row >= 0, row < 7,
              weeks[col].days.count > row else { return }
        if !silent { DSHaptic.selection() }
        onPick(weeks[col].days[row])
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
    ///
    /// TWO TREATMENTS since 2026-08-17 (prd §398), and the split is what the
    /// thing IS: a photograph is drawn, an entry is read.
    ///
    /// Until then this card was pixels or nothing — which was right while
    /// Snapchat's memories were the only room that reached it, and became a
    /// silent hole the moment the journal rooms did. A non-nil echo with no
    /// pixels drew an EmptyView, and because the anniversary SUPPRESSES every
    /// card below it in `shapedSections`, the room's whole head slot went blank
    /// on exactly the days it had something to say.
    var body: some View {
        if echo.thing.isLive {
            if echo.thing.previewImageData != nil { picture } else { words }
        }
    }

    /// The photograph, at a size worth looking at.
    ///
    /// The drawing is `PhotoWell`'s: it decodes ONCE into its own state instead
    /// of re-decoding a full-size photograph on every body evaluation, and it is
    /// the one image view in this app that honours `redactionReasons` — a
    /// hand-rolled `Image` survives into the app-switcher snapshot with
    /// hidePreviews ON, which for a private photograph at 190pt is exactly the
    /// leak that guard exists to stop.
    private var picture: some View {
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

    /// The entry itself — what you wrote on this day, in the room where that is
    /// the whole object.
    ///
    /// It leads with the DATE rather than the title, which inverts every other
    /// card in this app and is the point: the finding here is not what the entry
    /// says, it is that it was written on today's date some years ago. The words
    /// underneath are the payoff, and there are more of them than a feed row
    /// affords (five lines against three) because a journal entry read back is
    /// the one thing in this room worth stopping on.
    ///
    /// `bodyBelowTitle` for the excerpt, so the opening line isn't printed twice
    /// — the same defect §398 fixed in `ExcerptRow`, and it would have been
    /// louder here, at heading size directly above its own repeat.
    private var words: some View {
        Button {
            DSHaptic.selection()
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(echo.label)
                    .dsText(.label12).fontWeight(.semibold)
                    .foregroundStyle(DS.legibleCardFill(for: echo.thing.source))
                Text(echo.thing.title)
                    .dsText(.heading22)
                    .foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                if let body = IngestSupport.bodyBelowTitle(echo.thing.content,
                                                           title: echo.thing.title) {
                    Text(body)
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(5)
                        .multilineTextAlignment(.leading)
                        .padding(.top, DS.Space.s1)
                }
            }
            .padding(DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsWidgetSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(echo.label). \(echo.thing.title)"))
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
    /// The pressed day (prd §384) — named IN PLACE, in the subtitle's own
    /// slot, so the answer appears where the eye already is and the card
    /// never changes height. Auto-reverts; a fresh press restarts the clock.
    @State private var picked: ContributionDay?
    @State private var pickedClear: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pickedLabel: String? {
        guard let picked else { return nil }
        let count = picked.count == 0
            ? String(localized: "nothing")
            : "\(picked.count)"
        guard let date = picked.date else {
            return picked.count == 0
                ? String(localized: "Nothing that day")
                : String(localized: "\(picked.count) that day")
        }
        let day = date.formatted(.dateTime.month(.abbreviated).day())
        return "\(day) · \(count)"
    }

    var body: some View {
        InsightCard {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                InsightHeader(title: title, subtitle: pickedLabel ?? subtitle)
                Spacer(minLength: DS.Space.s2)
                // A year worth sharing (delight pass 2026-07-21) — the facts
                // as a line, the same honest voice the card itself wears; no
                // rendered image, just what the card already says.
                ShareLink(item: "\(title) — \(subtitle) 🍇", subject: Text(title)) {
                    Image(systemName: "square.and.arrow.up")
                        .dsGlyph(13)
                        .foregroundStyle(DS.textTertiary)
                }
                .accessibilityLabel("Share")
            }
            ContributionGraph(year: year, minColumns: minColumns, onPick: { day in
                // Press a day, read the day (prd §384). The label swaps into
                // the subtitle slot and reverts on its own — a reading, not a
                // mode.
                withAnimation(DS.Motion.standard) { picked = day }
                pickedClear?.cancel()
                pickedClear = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2.5))
                    guard !Task.isCancelled else { return }
                    withAnimation(DS.Motion.standard) { picked = nil }
                }
            })
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
                            .dsGlyph(11)
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
    /// What a tapped row opens, when the room it is in has somewhere to go
    /// (2026-08-18, prd §396). Nil for every board whose rows are subreddits,
    /// artists, publications or books — a row that looks tappable and isn't is
    /// the dead control the honesty law bans, so the row is only ever wrapped
    /// in a button when a destination was handed in.
    var onPick: ((FeedInsight.LeaderRow) -> Void)?
    /// The row the room is currently narrowed to, when the board is acting as
    /// a SWITCHER rather than a reading (2026-08-23, prd §455).
    ///
    /// The board keeps every row while the room shows one — the venue
    /// switcher's rule (§357), and the reason this card is not narrowed along
    /// with the rows it heads: a control that collapses to the one option you
    /// already picked is a control you cannot leave.
    var selected: String?
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
                        bar(row, index: i, labelW: labelW, barW: barW,
                            valueW: valueW, maxV: maxV)
                    }
                }
            }
            .frame(height: CGFloat(rows.count) * 28)
            .onAppear { grown = true }
        }
    }

    /// One ranked row. Wrapped in a button only when `onPick` was given, so a
    /// board with nowhere to go keeps exactly the plain row it has always
    /// drawn — no hit target, no press state, no promise.
    @ViewBuilder
    private func bar(_ row: FeedInsight.LeaderRow, index i: Int,
                     labelW: CGFloat, barW: CGFloat, valueW: CGFloat,
                     maxV: Int) -> some View {
        if let onPick {
            Button {
                DSHaptic.selection()
                onPick(row)
            } label: {
                barBody(row, index: i, labelW: labelW, barW: barW,
                        valueW: valueW, maxV: maxV)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dsHover()
        } else {
            barBody(row, index: i, labelW: labelW, barW: barW,
                    valueW: valueW, maxV: maxV)
        }
    }

    private func barBody(_ row: FeedInsight.LeaderRow, index i: Int,
                         labelW: CGFloat, barW: CGFloat, valueW: CGFloat,
                         maxV: Int) -> some View {
        // A selection DIMS the others rather than tinting itself a new colour:
        // the bar's hue already means magnitude, and a second meaning on the
        // same channel is how a chart starts lying. Weight carries the label.
        let isOn = selected == row.label
        let dimmed = selected != nil && !isOn
        return HStack(spacing: DS.Space.s2) {
            Text(row.label)
                .dsText(.callout15).fontWeight(isOn ? .semibold : .regular)
                .foregroundStyle(dimmed ? DS.textSecondary : DS.textPrimary)
                .lineLimit(1).truncationMode(.tail)
                .frame(width: labelW, alignment: .leading)
            ZStack(alignment: .leading) {
                Capsule().fill(DS.surfaceWell).frame(height: 8)
                Capsule().fill(DS.tint.opacity(dimmed ? 0.28 : 0.85))
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
/// heatmap). The neutral ink ramp (`DS.ink(magnitude:)`, 2026-08-10): a
/// lightness step, opacity by share, the biggest cell brightest — magnitude
/// is the only thing the fill says, exactly as the wallet holdings map and
/// the All feed's themes map read.
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
                        DS.ink(magnitude: Double(cell.count) / Double(maxCount))
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
                                BridgeIcon(name: "Twitch", size: DS.Mark.tile)
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
                .dsGlyph(15)
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
                        .dsGlyph(24, weight: .medium)
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

/// `Section(title, qualifier)` — a named division of the brief (2026-08-15,
/// prd §386g, user: "what happened to our section headers or whatever? we had
/// those too. i don't see those here").
///
/// They had never been built: they were drawn in a mockup, flagged as an open
/// ruling and never chased. Until now the brief separated its movements with
/// AIR alone (the `Stack`'s chapter gaps), which cannot say WHAT a run of
/// cards is about — and that is precisely what let the money hero, the movers
/// and the sankey end up on either side of the deadlines without anyone
/// noticing they had been split.
///
/// **Sentence case, never caps** — §8's ban on ALL-CAPS eyebrows is absolute,
/// and this is the one place it would have been tempting to break. The
/// qualifier is a quiet count or window beside the word ("Needs you · 3"),
/// carried as its own arg so it can never be typed into the title and inherit
/// its weight.
///
/// No rule, no line, no background: the design law forbids the divider a
/// header usually leans on, so the header earns its separation with AIR above
/// it and weight in the word itself.
struct GenSection: View {
    let el: GenEl
    @Environment(\.genRoomOpen) private var roomOpen

    /// Arg 2 — the section's identity hue, as a NAME rather than a hex.
    ///
    /// **The DOT is gone (2026-08-15, prd §386l, user: "i want better section
    /// headers too, no bullets").** A coloured bullet is a legend entry with
    /// nothing to look up: it sat beside six headings, meant a different
    /// thing in each, and taught the reader nothing they could not read in
    /// the word next to it. The hue survives where it does real work — the
    /// nav chip, where several sections sit side by side and colour is the
    /// only thing distinguishing them at a glance.
    /// The section's SF Symbol, keyed off the same hue name so the glyph and
    /// the tint can never disagree about which section this is (2026-08-16).
    /// One table, read by the digest card; a name with no entry gets the
    /// neutral dot rather than a wrong noun.
    static func symbol(_ hue: String) -> String {
        switch hue {
        case "attention": return "exclamationmark.triangle.fill"
        case "confirm":   return "checkmark.circle.fill"
        case "tint":      return "chart.line.uptrend.xyaxis"
        case "life":      return "sun.max.fill"
        case "work":      return "hammer.fill"
        case "meaning":   return "sparkles"
        default:          return "circle.fill"
        }
    }

    static func hue(_ name: String) -> Color {
        switch name {
        case "attention": return DS.attention
        case "confirm":   return DS.confirm
        case "tint":      return DS.tint
        // Green, not the old purple "#bf5af2" (user ruling 2026-08-15, on the
        // deck mockups: "that pink looks like its from a different place").
        // Deliberately a hex of its own rather than `DS.confirm`: this is an
        // IDENTITY hue (which section), confirm is a SEMANTIC one (something
        // went right), and aliasing them would weld the two so a future
        // confirm retune silently recolors the day's whole section.
        case "life":      return Color.fixed("#30d158")
        case "work":      return Color.fixed("#5e9eff")
        case "meaning":   return Color.fixed("#ff9f0a")
        default:          return DS.textTertiary
        }
    }

    /// Arg 3 — the room this section summarises, when one exists (prd §386j).
    /// The brief becomes the app's INDEX: every section that stands for a real
    /// room gets a door to it, so a summary is one tap from its detail. Empty
    /// for the sections that summarise no single room ("Your day" spans every
    /// source; "What goes together" is the corpus itself), and those draw no
    /// chevron rather than a door that goes nowhere (§83).
    private var room: String { el.str(3) }

    var body: some View {
        let header = VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                // BIGGER, and the size is the point (prd §386l). At
                // `callout15` a heading and the card title under it were the
                // same weight in nearly the same size, so the page read as a
                // list of cards rather than as a document with movements.
                // `heading22` is the ramp's own section voice — the day
                // headers in the feed already use it, so the brief now
                // matches the surface it summarises.
                Text(el.str(0))
                    .dsText(.heading22)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if !room.isEmpty {
                    Image(systemName: "chevron.right")
                        .dsGlyph(13)
                        .foregroundStyle(DS.textTertiary)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
            }
            // The qualifier is a READING, on its own line — "3 late, 1 today"
            // rather than a bare count clinging to the title. It is the one
            // thing a header can say that the cards under it cannot say
            // together, so it earns the line.
            if !el.str(1).isEmpty {
                Text(el.str(1))
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s6)
        .padding(.bottom, DS.Space.s1)

        Group {
            if room.isEmpty {
                header
            } else {
                Button { roomOpen?(room) } label: { header.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .dsTapCard()
            }
        }
        // SCROLLSPY (prd §386j) — each header reports where it is, so the nav
        // above can say which section you are actually IN rather than only
        // where you could jump. `.global` because the nav lives outside this
        // scroll view and the two need one shared frame of reference.
        .background {
            GeometryReader { geo in
                // QUANTIZED to 24pt steps (prd §386k): a raw `minY` changes on
                // every scroll frame, so every frame republished the
                // preference and re-ran the reader's closure for the whole
                // scroll — 120 times a second on ProMotion, to answer a
                // question ("which section am I in?") whose answer changes a
                // handful of times per screenful. Rounded, the dict is
                // byte-equal between steps and SwiftUI doesn't call the
                // reader at all; 24pt is far finer than any section is tall,
                // so the spy can't miss a boundary.
                Color.clear.preference(key: GenSectionOffsetKey.self,
                                       value: [el.str(0): (geo.frame(in: .global).minY / 24).rounded() * 24])
            }
        }
    }
}

/// Where each section heading currently sits, keyed by its title. Merged
/// rather than replaced, so every heading in the document contributes and the
/// reader sees them all at once (prd §386j).
struct GenSectionOffsetKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// `ClusterMap(title, subtitle, "x|y|source;…", "label|x|y|radius;…")` — the
/// semantic map as a real BRIEF MODULE (2026-08-15, prd §386j).
///
/// It had been a docked panel card floating below the document, which left
/// its section header ("What goes together") standing over nothing — and an
/// orphaned header reads as misplaced wherever you put it, which is the real
/// reason the section felt wrong at the end of the brief rather than an
/// argument about its position.
///
/// **Draws through `ScatterFigure`, the panel's own view**, rather than a
/// second implementation: the map is the one figure in the app whose POSITION
/// carries meaning, and two renderers would eventually disagree about what
/// "near" looks like. The doc grammar's job here is only to carry the
/// projection across — the maths stays in `AgentPanelFigures.scatter`, which
/// composes it off the main actor before this line is ever written.
private struct GenClusterMap: View {
    let el: GenEl
    @Environment(\.genAskRequest) private var askRequest
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The pressed cluster, named in the subtitle's slot — the §384
    /// press-reveals-a-fact grammar, and the only honest thing a cluster can
    /// say about itself without threading every thing's id through the doc:
    /// its own name and how many things sit in it.
    @State private var picked: AgentPanel.DotCluster?
    @State private var clear: Task<Void, Never>?

    private var dots: [AgentPanel.Dot] {
        el.str(2).split(separator: ";").compactMap { row in
            let f = row.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard f.count >= 3, let x = Double(f[0]), let y = Double(f[1]) else { return nil }
            return AgentPanel.Dot(x: x, y: y, source: f[2])
        }
    }
    private var clusters: [AgentPanel.DotCluster] {
        el.str(3).split(separator: ";").compactMap { row in
            let f = row.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard f.count >= 4, let x = Double(f[1]), let y = Double(f[2]),
                  let r = Double(f[3]), !f[0].isEmpty else { return nil }
            return AgentPanel.DotCluster(label: f[0], x: x, y: y, radius: r)
        }
    }

    var body: some View {
        let dots = dots, clusters = clusters
        Group {
            if !dots.isEmpty, !clusters.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    if !el.str(0).isEmpty {
                        Text(el.str(0))
                            .dsText(.callout15).fontWeight(.semibold)
                            .foregroundStyle(DS.textPrimary)
                    }
                    if let subtitle = pickedLine ?? (el.str(1).isEmpty ? nil : el.str(1)) {
                        Text(subtitle)
                            .dsText(.subhead13)
                            .foregroundStyle(picked == nil ? DS.textTertiary : DS.textPrimary)
                            .lineLimit(2)
                    }
                    ScatterFigure(dots: dots, clusters: clusters,
                                  halos: 1, drift: 1, words: 1)
                        .frame(height: 236)
                        // A pressed cluster names itself; a press that lands
                        // near nothing does nothing rather than guessing.
                        // The overlay supplies the SIZE the hit test needs —
                        // `ScatterFigure` positions in its own 0…1 space, so
                        // without the measured frame there is nothing to
                        // normalise the touch against.
                        .overlay {
                            GeometryReader { geo in
                                Color.clear
                                    .contentShape(Rectangle())
                                    .gesture(SpatialTapGesture().onEnded { value in
                                        pick(clusters, at: value.location, in: geo.size)
                                    })
                            }
                        }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.s4)
                .dsWidgetSurface()
                .padding(.horizontal, DS.Space.s4)
                .padding(.top, DS.Space.s2)
            }
        }
    }

    private var pickedLine: String? {
        picked.map { String(localized: "\($0.label) — tap again to ask about it") }
    }

    /// Nearest cluster CENTRE within reach of the touch. A second press on
    /// the SAME cluster asks about it (the §225 route the treemap cells
    /// already take), so one gesture reveals and the next acts.
    private func pick(_ clusters: [AgentPanel.DotCluster], at point: CGPoint,
                      in size: CGSize) {
        // `ScatterFigure` insets by 16 and places at `inset + v * (extent -
        // 2·inset)`; this is that mapping run forwards so the comparison
        // happens in POINTS, where "within a finger's reach" is meaningful —
        // normalised units would make the reach depend on the frame.
        let inset: CGFloat = 16
        let px = { (v: Double) in inset + CGFloat(v) * max(1, size.width - inset * 2) }
        let py = { (v: Double) in inset + CGFloat(v) * max(1, size.height - inset * 2) }
        let reach: CGFloat = 60
        let hit = clusters
            .map { ($0, hypot(px($0.x) - point.x, py($0.y) - point.y)) }
            .filter { $0.1 <= reach }
            .min { $0.1 < $1.1 }?.0
        guard let hit else { return }
        if picked?.label == hit.label {
            askRequest?(hit.label)
            return
        }
        DSHaptic.selection()
        withAnimation(DS.Motion.standard) { picked = hit }
        clear?.cancel()
        clear = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(DS.Motion.standard) { picked = nil }
        }
    }
}

/// `DayFold(shots, faces, marks, subline)` — what today was MADE of, as one
/// card (2026-08-15, prd §386g, user: "i love the idea of the fold what today
/// was made of into one card").
///
/// Replaces three stacked cards that each answered the same question from a
/// different angle: `ContactSheet` ("what you saw"), `Faces` ("who's around")
/// and `SourceMix` ("where today came from"). Three cards for one subject is
/// the shape this whole pass has been removing everywhere else, and it cost
/// three of the brief's slots to say one thing.
///
/// The pictures lead because they ARE the day rather than an abstraction of
/// it (`WidgetDayLead`'s own ladder makes the same call); the people and the
/// rooms share the line beneath, since both are "who and where", and the
/// subline carries every remainder so nothing is silently dropped.
private struct GenDayFold: View {
    let el: GenEl
    @Environment(\.genThingOpen) private var thingOpen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Shot { let url: String, id: String }
    private struct Person { let handle: String, avatar: String }

    private var shots: [Shot] {
        el.str(0).split(separator: ";").compactMap { row in
            let f = row.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard let u = f.first, !u.isEmpty else { return nil }
            return Shot(url: u, id: f.count > 1 ? f[1] : "")
        }
    }
    private var people: [Person] {
        el.str(1).split(separator: ";").compactMap { row in
            let f = row.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard let h = f.first, !h.isEmpty else { return nil }
            return Person(handle: h, avatar: f.count > 1 ? f[1] : "")
        }
    }
    private var marks: [String] {
        el.str(2).split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        let shots = shots, people = people, marks = marks
        Group {
            if !shots.isEmpty || !people.isEmpty || !marks.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    if !shots.isEmpty {
                        HStack(spacing: 5) {
                            ForEach(Array(shots.prefix(4).enumerated()), id: \.offset) { i, shot in
                                Button { thingOpen?(shot.id) } label: {
                                    RemoteArt(urlString: shot.url, width: 74, height: 74,
                                              fallback: nil, cornerRadius: DS.Radius.control)
                                }
                                .buttonStyle(PressLift())
                                .disabled(shot.id.isEmpty)
                                .chartArrival(index: i, reduceMotion: reduceMotion)
                            }
                        }
                    }
                    if !people.isEmpty || !marks.isEmpty {
                        HStack(spacing: DS.Space.s2) {
                            // The faces overlap into a roster the way they do
                            // in `GenFaces` — smaller here, because this card
                            // states three things and none may take the page.
                            HStack(spacing: -8) {
                                ForEach(Array(people.prefix(4).enumerated()), id: \.offset) { _, p in
                                    PersonBadge(handle: p.handle, avatar: p.avatar, size: 30)
                                }
                            }
                            Spacer(minLength: DS.Space.s2)
                            HStack(spacing: 4) {
                                ForEach(Array(marks.prefix(3).enumerated()), id: \.offset) { _, m in
                                    BridgeIcon(name: m, size: DS.Face.badge, circular: true)
                                }
                            }
                        }
                    }
                    if !el.str(3).isEmpty {
                        Text(el.str(3))
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textTertiary)
                            .lineLimit(2)
                    }
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

/// One face in the fold — the avatar when there is one, the handle's initial
/// when there isn't (`AssetMark`'s no-invented-hue rule: a monogram on the
/// neutral ramp, never a colour we guessed for a person).
private struct PersonBadge: View {
    let handle: String
    let avatar: String
    let size: CGFloat

    var body: some View {
        Group {
            if !avatar.isEmpty {
                RemoteArt(urlString: avatar, width: size, height: size,
                          fallback: nil, cornerRadius: size / 2)
            } else {
                Circle()
                    .fill(DS.gray100)
                    .overlay(
                        // The SIGIL is not an initial (prd §386g, seen on the
                        // sim: a roster of "U N S @"). A handle may lead with
                        // "@" on Bluesky, "u/" on Reddit or "/" on a channel;
                        // the first LETTER OR DIGIT is the person's, the
                        // punctuation is the network's.
                        Text(String(handle.first(where: { $0.isLetter || $0.isNumber })
                                    ?? handle.first ?? " ").uppercased())
                            .dsText(.label11).fontWeight(.bold)
                            .foregroundStyle(DS.textSecondary))
                    .frame(width: size, height: size)
            }
        }
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(DS.surfaceSheet, lineWidth: 2))
        .accessibilityLabel(Text(handle))
    }
}

/// Coach(text) — the one-time teaching line: emphasized neutral words on the
/// page (2026-08-10, was tint — a tip doesn't need a hue to read as a tip),
/// retired forever by the surface once the lesson is learned (the flag lives
/// with the surface, not here).
private struct GenCoach: View {
    let el: GenEl
    var body: some View {
        Text(el.str(0))
            .dsText(.subhead13)
            .foregroundStyle(DS.textSecondary)
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
    @Environment(\.genAgentAnswerContext) private var inAgentAnswer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// One glint per mount (delight 2026-07-13): a cited row flashes a
    /// whisper of tint as it lands in a live answer, then settles.
    @State private var glinted = false
    /// The evidence re-glint (prd §384): a pressed sentence replays the flash
    /// on the rows beneath it — settled turns included, where the mount glint
    /// never ran. Armed by the press, so the background exists only when a
    /// glint (either kind) can draw.
    @State private var replayArmed = false

    var body: some View {
        // Arg 6, when present, is WHY this row is in a result — the passage
        // that matched (2026-08-13, `KeptAskComposers.snippet`). Absent for
        // every other emitter, and `str` answers "" past the end of the args,
        // so a five-arg Row written before this existed is untouched.
        let snippet = el.str(6)
        let row = HStack(spacing: DS.Space.s3) {
            TagGlyph(tag: el.str(1), size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(el.str(0))
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                if !snippet.isEmpty {
                    Text(snippet)
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(el.str(3)).dsText(.subhead13).foregroundStyle(DS.textTertiary)
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s3)
        .background {
            if glintOn || replayArmed {
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
        .onChange(of: GenEvidenceGlint.shared.tick) {
            // A pressed sentence re-glints its rows (prd §384). Only rows
            // that stand for a THING (arg 4) — a decorative row is not
            // evidence — and only inside the agent's answer column.
            guard inAgentAnswer, !el.str(4).isEmpty else { return }
            replayArmed = true
            glinted = false
            if reduceMotion {
                // Less motion, same information: the glow states, then clears
                // without the fade.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(700))
                    glinted = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.9).delay(0.15)) { glinted = true }
            }
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
                .dsTapCard()
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
        .dsTapCard()
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

/// VoiceTile(span, title, subline) — waveform over a caption. Neutral bars
/// (2026-08-10, was tint) — the same illustrative-not-data grammar
/// `GenPhotoTile`'s placeholder shades just above use: this waveform isn't
/// real audio, so it shouldn't wear a color that implies it means something.
private struct GenVoiceTile: View {
    let el: GenEl
    private let bars: [CGFloat] = [8, 14, 20, 12, 18, 8, 16, 22, 10, 14, 6, 12]
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, h in
                    Capsule().fill(DS.gray300).frame(width: 3, height: h)
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
                            .dsGlyph(11)
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
                        // token/bridge icons. Every map wears the same
                        // neutral ink ramp (2026-08-10, `DS.ink(magnitude:)`)
                        // — a lightness step, opacity by share, biggest cell
                        // brightest. One neutral ramp on purpose, twice over:
                        // a per-theme palette was pitched and declined
                        // ("I don't want all these random colors", 2026-07-21)
                        // for the themes map, and this ruling now retires
                        // §158's later carve-out for TOKEN cells too ("i
                        // don't want brand hue really", 2026-08-10) — hue no
                        // longer does identity work anywhere on this fill;
                        // that job stays with the label ink and the
                        // token/bridge icons. The preview breathes the
                        // surface itself: shape without claiming substance.
                        ZStack {
                            DS.surfaceSheet
                            if !preview {
                                DS.ink(magnitude: usdShare(of: item))
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
                            // See the note on the smaller cell below — 0.4
                            // floored this at ~7pt.
                            .minimumScaleFactor(0.7)
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
                        // See the note on the 4-unit cell above — 0.4 floored
                        // this at ~6pt.
                        .minimumScaleFactor(0.7)
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
                    BridgeIcon(name: item.tag, size: DS.Mark.badge)
                }
                Text(item.tag)
                    .dsText(.body17)
                    // Plain primary ink, exactly like a Settings tile's
                    // title (2026-07-10, user) — colored label inks were
                    // tried the same day and read as noise.
                    .foregroundStyle(preview ? DS.textTertiary : DS.textPrimary)
                    .lineLimit(item.tag.contains(" ") ? 2 : 1)
                    // 0.7, not the 0.4 this carried until 2026-08-13: at 0.4
                    // an 18pt cell label floors at 7pt, which is under the
                    // legibility bar at ANY Dynamic Type setting and cancels
                    // the ramp exactly where someone who raised their text size
                    // is looking. A long term truncates now instead of
                    // shrinking to nothing — a name you can read the start of
                    // beats a name you can read none of.
                    .minimumScaleFactor(0.7)
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
                        BridgeIcon(name: name, size: DS.Face.row, circular: true)
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
                    .dsGlyph(14)
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

/// The shared breathing loop every `GenSkeleton*` fill uses (2026-08-09,
/// reverses the 2026-07-31 "plain static fill" ruling — see `GenSkeletonBlock`
/// below for why). One gentle opacity pulse, not a sweeping gradient: this is
/// a loading state, not decoration, so it should read as "waiting" at a
/// glance and nothing more. Honors Reduce Motion by never animating at all —
/// the fill just sits at full opacity, identical to the old static behavior.
private struct GenSkeletonPulse: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = false

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion || lit ? 1 : 0.5)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                    lit = true
                }
            }
    }
}

private extension View {
    func genSkeletonPulse() -> some View { modifier(GenSkeletonPulse()) }
}

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
        .genSkeletonPulse()
    }
}

struct GenSkeletonTile: View {
    var minHeight: CGFloat = 96
    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous)
            .fill(DS.surfaceSheet)
            .frame(minHeight: minHeight)
            .genSkeletonPulse()
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
/// PULSES now (2026-08-09, user: "i don't want to see something say
/// 'thinking' i'd rather see it look like generative UI preparing to
/// populate" — measured live: the on-device brief read alone takes ~2.1s,
/// and a perfectly static gray block for two full seconds against this app's
/// black chrome reads as nothing happening, not as loading). This reverses
/// the 2026-07-31 ruling ("a shimmering skeleton would be a decorative loop,
/// sanctioned only while something real is pending") — every call site of
/// this view genuinely IS something real pending by construction, so the
/// restraint argument didn't hold once a wait got long enough to matter. One
/// gentle opacity breathe, not a sweep — see `GenSkeletonPulse`.
struct GenSkeletonBlock: View {
    var minHeight: CGFloat = 96
    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous)
            .fill(DS.surfaceSheet)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s2)
            .genSkeletonPulse()
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

/// `Faces(label, subline, "handle|avatarURL|count|thingID;…")` — who turned up,
/// as faces sized by how often (2026-08-10, user: "life should be rich with
/// avatars").
///
/// The treemap already tells you Life's subjects and draws them as lettered
/// rectangles; people are the one thing in this corpus with a FACE, and
/// rendering them as more rectangles was the specific poverty this fixes.
/// Size carries frequency — the same grammar the treemap uses for area, moved
/// onto a shape that can also be a likeness.
///
/// A monogram where a bridge gave us no avatar, never a blank or a silhouette:
/// `RemoteThumb`'s own fallback, so the circle is always a real circle and the
/// row never has a hole in it. That matters more here than elsewhere because
/// avatar coverage is genuinely uneven — Farcaster, Bluesky, Nostr, RSS,
/// Stocktwits and GitHub all populate `authorAvatarURL`, while an X archive or
/// a TikTok save names the person and carries no picture.
private struct GenFaces: View {
    let el: GenEl
    @Environment(\.genThingOpen) private var thingOpen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Person {
        let handle: String, avatar: String, count: Int, id: String
    }

    private var people: [Person] {
        el.str(2).split(separator: ";").compactMap { row in
            let f = row.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard f.count >= 4, !f[0].isEmpty else { return nil }
            return Person(handle: f[0], avatar: f[1], count: Int(f[2]) ?? 1, id: f[3])
        }
    }

    /// Diameter from rank, not from the raw count — a person who appeared 40
    /// times beside one who appeared twice would otherwise draw a face and a
    /// dot. The treemap's `sqrt` reasoning, solved by ranking instead: the
    /// order is the claim, and every face stays big enough to be a face.
    private func size(_ i: Int) -> CGFloat { [64, 56, 50, 44, 40, 38].indices.contains(i) ? [64, 56, 50, 44, 40, 38][i] : 36 }

    var body: some View {
        let people = people
        Group {
            if people.count >= 3 {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    if !el.str(0).isEmpty {
                        Text(el.str(0))
                            .dsText(.callout15).fontWeight(.semibold)
                            .foregroundStyle(DS.textPrimary)
                    }
                    if !el.str(1).isEmpty {
                        Text(el.str(1))
                            .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    }
                    // A horizontal roster rather than a wrapping cluster: the
                    // faces are different SIZES, and a wrap packs unequal
                    // circles into ragged rows that read as an accident. One
                    // line, biggest first, also makes the ranking the reading
                    // order — the app's own strip idiom (the source chips, the
                    // kept pills), bottom-aligned so the sizes step down from a
                    // shared baseline instead of floating.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .bottom, spacing: DS.Space.s3) {
                            ForEach(Array(people.enumerated()), id: \.offset) { i, p in
                                Button { thingOpen?(p.id) } label: {
                                    VStack(spacing: 5) {
                                        // An INITIAL in the person's own hue
                                        // where no avatar came down, not
                                        // `RemoteThumb`'s bridge fallback:
                                        // that one resolves a BRIDGE name to
                                        // an app icon, so handing it a handle
                                        // drew the same generic glyph for
                                        // everybody and made five distinct
                                        // people identical (seen on the sim,
                                        // 2026-08-10). `ProjectHue` keys the
                                        // colour off the name, so a person
                                        // keeps their circle between opens.
                                        if p.avatar.isEmpty {
                                            Circle()
                                                .fill(ProjectHue.color(for: p.handle))
                                                .overlay(
                                                    Text(String(p.handle.prefix(1)).uppercased())
                                                        .dsText(.heading17)
                                                        .foregroundStyle(.white)
                                                )
                                                .frame(width: size(i), height: size(i))
                                        } else {
                                            RemoteThumb(urlString: p.avatar,
                                                        size: size(i),
                                                        fallback: p.handle,
                                                        circular: true)
                                        }
                                        Text(p.handle)
                                            .dsText(.label12)
                                            .foregroundStyle(DS.textTertiary)
                                            .lineLimit(1)
                                            .frame(maxWidth: size(i) + 16)
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(p.id.isEmpty)
                                .chartArrival(index: i, reduceMotion: reduceMotion)
                            }
                        }
                    }
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

/// `ContactSheet(label, subline, "url|thingID;…", moreCount)` — what you
/// actually SAW, as its own pictures (2026-08-10).
///
/// The brief had no image module at all before this: every one of its
/// visualizations is geometry standing in for data — a treemap's rectangles, a
/// bar's height, a runway's dots — and the Life scope is the one place the
/// corpus holds real photographs (measured on a demo corpus: 99 of 277 Life
/// things carry a picture, against 4 of 71 for Money and 1 of 74 for Work).
/// Drawing them is therefore both the most different thing this screen can do
/// and the one most specific to what Life IS. A treemap of Life's tags is a
/// diagram of your life; this is your life.
///
/// Deliberately NOT `GenPhotoTile`, which draws four flat grey rounded
/// rectangles as an illustration of "photos exist". These are the bytes.
///
/// The tail is COUNTED, never truncated silently (§300's folded-tail rule): a
/// sheet that shows nine of ninety and says so is honest, one that shows nine
/// and stops looks like a quiet library.
private struct GenContactSheet: View {
    let el: GenEl
    @Environment(\.genThingOpen) private var thingOpen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Shot { let url: String; let id: String }

    private var shots: [Shot] {
        el.str(2).split(separator: ";").compactMap { row in
            let f = row.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard let u = f.first, !u.isEmpty else { return nil }
            return Shot(url: u, id: f.count > 1 ? f[1] : "")
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 74), spacing: 6)]

    var body: some View {
        let shots = shots
        Group {
            if !shots.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    if !el.str(0).isEmpty {
                        Text(el.str(0))
                            .dsText(.callout15).fontWeight(.semibold)
                            .foregroundStyle(DS.textPrimary)
                    }
                    if !el.str(1).isEmpty {
                        Text(el.str(1))
                            .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    }
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(Array(shots.enumerated()), id: \.offset) { i, shot in
                            Button { thingOpen?(shot.id) } label: {
                                RemoteArt(urlString: shot.url,
                                          width: 74, height: 74,
                                          fallback: nil,
                                          cornerRadius: DS.Radius.control)
                            }
                            .buttonStyle(PressLift())
                            .disabled(shot.id.isEmpty)
                            .chartArrival(index: i, reduceMotion: reduceMotion)
                        }
                    }
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

/// `Runway(label, "dueEpoch|source;…", nowEpoch)` — the deadlines ahead of you
/// on ONE shared time axis (2026-08-10, user: "suggest some new visualizations
/// we can put on work and life that are different from each other and
/// different than rest of the app").
///
/// It is the brief's only shared time axis, and that is what makes it new
/// rather than a fourth way to draw a ranking. Every other module here shows
/// magnitude — a treemap's area, a bar's height, a sparkline's slope — and
/// answers "how much". This answers WHEN, with the gap between two dots
/// meaning real elapsed time, so a wall of four deadlines in one afternoon and
/// four spread over a fortnight draw as visibly different shapes. A list
/// cannot say that: `AgentPanel.Figure.runway`'s own rule, "one dot on an axis
/// is a dot", is the same observation from the other side.
///
/// NOW is the fixed reference and always drawn, even when nothing is overdue —
/// a dot's distance from the present is the entire reading, so an axis that
/// silently rescaled to start at the first deadline would make "due in an
/// hour" and "due in three weeks" look identical.
///
/// The axis is a FILL, not a rule — the no-hairlines ban is about lines that
/// divide, and this is a measured extent (`ShareBar`'s own reasoning).
private struct GenRunway: View {
    let el: GenEl
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Dot { let at: Date; let source: String }

    private var now: Date {
        Date(timeIntervalSince1970: Double(el.str(2)) ?? Date.now.timeIntervalSince1970)
    }

    private var dots: [Dot] {
        el.str(1).split(separator: ";").compactMap { row in
            let f = row.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard let secs = Double(f.first ?? "") else { return nil }
            return Dot(at: Date(timeIntervalSince1970: secs),
                       source: f.count > 1 ? f[1] : "")
        }
    }

    /// The window always CONTAINS now, so an overdue item pushes the left edge
    /// back and everything ahead stays right of the marker. Padded by a
    /// twentieth on each side so a dot at either extreme isn't clipped by the
    /// track's own end. A plain method, not a `let` inside the body: a `func`
    /// declared inside a `ViewBuilder` doesn't compile, and inlining the maths
    /// per dot recomputes the window on every element.
    private func window(_ dots: [Dot], _ now: Date) -> (start: Double, span: Double) {
        let times = dots.map(\.at.timeIntervalSince1970) + [now.timeIntervalSince1970]
        let lo = times.min() ?? 0, hi = times.max() ?? 1
        let pad = max((hi - lo) * 0.05, 1)
        let start = lo - pad
        return (start, max((hi + pad) - start, 1))
    }

    /// Dot centres, nudged just enough to stay countable (2026-08-13).
    ///
    /// Three deadlines in one afternoon land within a few points of each other
    /// on a fortnight-wide axis and drew as one smear — so the axis said
    /// "something is happening around now" where the honest reading is "THREE
    /// things are due around now", and a count is exactly what a pile-up is.
    /// Each dot is pushed right to clear the previous one by a hair under its
    /// own diameter, in time order, so a cluster reads as a cluster of a
    /// KNOWABLE size.
    ///
    /// Bounded on purpose: the nudge is at most one dot width per collision and
    /// never re-orders, so at any scale a reader can actually judge — which
    /// half of the fortnight, before or after now — the picture is unchanged.
    /// Beyond that the axis was never claiming point accuracy; it carries no
    /// tick marks and its two labels are its ends.
    private func spread(_ dots: [Dot], win: (start: Double, span: Double),
                        width w: CGFloat) -> [CGFloat] {
        let gap: CGFloat = 11   // one dot (10) plus a hairline of daylight
        var out: [CGFloat] = []
        var last: CGFloat = -.greatestFiniteMagnitude
        for dot in dots {
            let raw = CGFloat((dot.at.timeIntervalSince1970 - win.start) / win.span) * w
            let placed = max(raw, last + gap)
            out.append(placed)
            last = placed
        }
        return out
    }

    var body: some View {
        let dots = dots
        let now = now
        let win = window(dots, now)
        Group {
            if dots.count >= 2 {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    if !el.str(0).isEmpty {
                        Text(el.str(0))
                            .dsText(.callout15).fontWeight(.semibold)
                            .foregroundStyle(DS.textPrimary)
                    }
                    GeometryReader { geo in
                        let w = geo.size.width
                        let nowX = CGFloat((now.timeIntervalSince1970 - win.start) / win.span) * w
                        // Computed ONCE per layout, not per dot: the nudge is
                        // cumulative, so asking for it inside the ForEach would
                        // rebuild the whole run for every element.
                        let xs = spread(dots, win: win, width: w)
                        ZStack(alignment: .topLeading) {
                            Capsule()
                                .fill(DS.gray100)
                                .frame(height: 4)
                                .offset(y: 13)
                            // NOW — a full-height mark, so it reads as the
                            // axis's origin rather than as another deadline.
                            Capsule()
                                .fill(DS.textTertiary)
                                .frame(width: 2, height: 18)
                                .offset(x: nowX - 1, y: 6)
                            ForEach(Array(dots.enumerated()), id: \.offset) { i, dot in
                                let dx = xs.indices.contains(i) ? xs[i] : 0
                                // Overdue wears attention, ahead wears the
                                // neutral ramp — the ONE thing on this axis
                                // that colour is allowed to say, because
                                // "already past" is a different state, not a
                                // bigger quantity (§300's own rule for the
                                // undeclared-host cell).
                                Circle()
                                    .fill(dot.at < now ? DS.attention : DS.textSecondary)
                                    .frame(width: 10, height: 10)
                                    .offset(x: min(max(dx - 5, 0), max(w - 10, 0)), y: 10)
                                    .chartArrival(index: i, reduceMotion: reduceMotion)
                                    // A runway says the SHAPE of what's coming
                                    // and deliberately names only its two ends
                                    // (see `spread` — the labels are the ends,
                                    // and a label per dot would be a list, not
                                    // a rail). On a Mac the cursor can ask any
                                    // dot which one it is without spending a
                                    // label on it. Overdue is said out loud
                                    // rather than left to the hue, since the
                                    // colour is the only thing carrying it and
                                    // colour alone is not a reading.
                                    .dsTooltip(dot.at < now
                                               ? String(localized: "\(dot.source) — was due \(dot.at.formatted(.dateTime.month(.abbreviated).day()))")
                                               : String(localized: "\(dot.source) — \(dot.at.formatted(.dateTime.month(.abbreviated).day()))"))
                            }
                        }
                    }
                    .frame(height: 30)
                    HStack {
                        Text(el.str(3).isEmpty ? "now" : el.str(3))
                            .dsText(.label12).foregroundStyle(DS.textTertiary)
                        Spacer(minLength: 0)
                        if !el.str(4).isEmpty {
                            Text(el.str(4))
                                .dsText(.label12).foregroundStyle(DS.textTertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Space.s4)
                .padding(.top, DS.Space.s2)
            }
        }
    }
}

/// `Alerts(eyebrow, "title|meta|source|thingID;…")` — the things in this scope
/// that WANT SOMETHING, called out above everything else (2026-08-10, user:
/// "we have things that qualify as alerts like disputes … they should be shown
/// as their own thing as a call out in some way b/c they are more important").
///
/// Its membership is NOT a judgement made here: `TodayBrief.alertsCard` runs
/// the shipped `NotifySweep.classify` and keeps the `.alarm` class, ranked by
/// `NotifyKind.severity`. That is deliberate and is the whole reason this is
/// trustworthy — the app already decides, mechanically and under a 79-assertion
/// self-test, what is worth breaking into someone's day for. A second opinion
/// living in the brief would drift from the lock screen's within a month, and
/// then a dispute would be an emergency in one place and a list item in the
/// other.
///
/// Drawn as a distinct BLOCK rather than as rows in a card, and it is the one
/// module in the brief allowed `DS.attention`: everything else here reports,
/// and this is the only thing that asks. A per-row severity hue was drawn
/// first and cut — five rows in three colours reads as a status dashboard and
/// makes the least urgent row look like a warning; rank already carries
/// severity, so colour would be saying it twice.
private struct GenAlerts: View {
    let el: GenEl
    @Environment(\.genThingOpen) private var thingOpen

    private struct Item {
        let title: String, meta: String, source: String, id: String
    }

    /// Semicolon-separated rows, pipe-separated fields — the `WalletFlow`
    /// lane grammar, which is already the app's shape for "several records in
    /// one arg". Short of four fields the row is dropped rather than padded:
    /// a half-parsed alert is the one kind this module must never draw.
    private var items: [Item] {
        el.str(1).split(separator: ";").compactMap { row in
            let f = row.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard f.count >= 4, !f[0].isEmpty else { return nil }
            return Item(title: f[0], meta: f[1], source: f[2], id: f[3])
        }
    }

    var body: some View {
        let items = items
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    // The eyebrow row goes with its WORDS (prd §386g). Under
                    // a section header the title is empty, and the glyph alone
                    // is a warning triangle floating over nothing — punctuation
                    // with no sentence. The rows below already wear the
                    // attention hue where they carry it.
                    if !el.str(0).isEmpty {
                        HStack(spacing: DS.Space.s2) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .dsGlyph(13)
                                .foregroundStyle(DS.attention)
                                .accessibilityHidden(true)
                            Text(el.str(0))
                                .dsText(.callout15).fontWeight(.semibold)
                                .foregroundStyle(DS.textPrimary)
                        }
                    }
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        Button { thingOpen?(item.id) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .dsText(.heading17)
                                    .foregroundStyle(DS.textPrimary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .multilineTextAlignment(.leading)
                                HStack(spacing: DS.Space.s1) {
                                    if !item.source.isEmpty {
                                        BridgeIcon(name: item.source, size: DS.Mark.inline)
                                    }
                                    if !item.meta.isEmpty {
                                        Text(item.meta)
                                            .dsText(.subhead13)
                                            .foregroundStyle(DS.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(item.id.isEmpty)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.s4)
                // The one tinted surface in the brief. `attention` at low
                // opacity rather than `dsWidgetSurface` — against the neutral
                // cards below it this reads as a different KIND of thing at a
                // glance, which is the entire request.
                .background(DS.attention.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .padding(.horizontal, DS.Space.s4)
                .padding(.top, DS.Space.s2)
            }
        }
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
    /// Modules that said exactly this last time (prd §386d) — see the Stack
    /// branch's own note. Defaulted so the `qualifies`-only callers and any
    /// non-brief front page need not know about it.
    var quiet: Set<String> = []
    let inAgentAnswer: Bool
    @State private var width: CGFloat = 0
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The miniature sparkline's draw-on (§299's entrance for a data-shaped
    /// drawing). One flag for the page: only one section composes a spark.
    @State private var sparkDrawn: CGFloat = 0
    /// The section header's own door (§386j) — the digest card opens the room
    /// its section stands for, which is what replaced the accordion.
    @Environment(\.genRoomOpen) private var roomOpen

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
        return segs.count - headSegmentCount(segs, els: els) >= 2
    }

    var body: some View {
        let refs = el.refs(0)
        let segs = Self.segments(refs: refs, chapters: chapters)
        let headCount = Self.headSegmentCount(segs, els: els)
        Group {
            if width >= Self.columnsFloor, segs.count - headCount >= 2 {
                frontPage(segs: segs, headCount: headCount)
            } else {
                // The single column — THE DECK since 2026-08-15 (user, on the
                // approved mockups: "i want what was mocked up"). The head run
                // (masthead, lede) stays bare on the ink; every chapter block
                // after it renders as a card. Same segments the two-column
                // page cuts, so the phone and the Mac disagree about layout
                // and never about grouping.
                // QUIET SECTIONS PAIR UP (mockup C, 2026-08-16): two
                // consecutive sections whose every module said what it said
                // last time share one row at half width — Health's Favorites
                // rhythm, and the honest form of the step-back: a section
                // that changed gets the full slab it earned, a quiet one
                // stops costing a screenful. Consecutive only, so the
                // pairing can never reorder the clock's own permutation.
                let blocks = Array(segs.dropFirst(headCount))
                let rows: [[[String]]] = blocks.reduce(into: []) { acc, seg in
                    if segIsQuiet(seg), let last = acc.last, last.count == 1,
                       let prev = last.first, segIsQuiet(prev) {
                        acc[acc.count - 1].append(seg)
                    } else {
                        acc.append([seg])
                    }
                }
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    ForEach(segs.prefix(headCount).flatMap { $0 }, id: \.self) { module($0) }
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        if row.count == 2 {
                            HStack(alignment: .top, spacing: DS.Space.s3) {
                                deckCard(row[0])
                                deckCard(row[1])
                            }
                        } else {
                            deckCard(row[0])
                        }
                    }
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
        return VStack(alignment: .leading, spacing: DS.Space.s3) {
            ForEach(head, id: \.self) { module($0) }
            HStack(alignment: .top, spacing: DS.Space.s4) {
                column(left)
                column(right)
            }
        }
    }

    private func column(_ blocks: [[String]]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { deckCard($0.element) }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// A headed section whose every module is in the quiet set — the pairing
    /// test AND the card-dim test, one definition so the two can't disagree.
    ///
    /// A section that renders ITS OWN MODULES is never quiet (2026-08-16,
    /// device shot: "Your day" sat dimmed at 0.68 with a row of photographs
    /// inside it, and dimmed photographs read as a failed image load, not as
    /// "you have seen this"). The step-back is a contrast device for a
    /// DIGEST — three lines of text whose point is that they haven't
    /// changed; applied to visible content it just looks broken. A roomless
    /// section is exactly the one that shows its contents (see `deckCard`'s
    /// door note), so the two rules are already the same test.
    private func segIsQuiet(_ seg: [String]) -> Bool {
        guard let first = seg.first, let header = els[first],
              header.comp == "Section", !header.str(3).isEmpty else { return false }
        return seg.count > 1 && seg.dropFirst().allSatisfy { quiet.contains($0) }
    }

    /// One chapter block as a DECK CARD — ON INK (2026-08-15, second ruling
    /// of the night, superseding the hue-ground version shipped hours
    /// earlier: "it all looks vibecoded now"). The card GROUPING survives —
    /// it is real structure, and the brief reads as movements because of it —
    /// but the ground returns to the ink slab for every section, because four
    /// saturated slabs stacked is colour saying nothing four times. The
    /// page's whole colour budget now belongs to the lede card above
    /// (`GenDayLede`), one bright object per screen; section identity stays
    /// where colour does navigation, the docked nav chips. The modules'
    /// own internal colours — treemap blues, chart accents, semantic
    /// green/red — get their ink ground back, which is what they were
    /// designed against.
    ///
    /// Quiet returns to the §386d dim, applied to the CARD's content as one
    /// piece rather than per module — all the cards share a ground now, so
    /// opacity is again the only contrast device, and whole-card reads as
    /// intentional where per-module read as patchy.
    @ViewBuilder
    private func deckCard(_ seg: [String]) -> some View {
        let isQuiet = seg.count > 1 && seg.dropFirst().allSatisfy { quiet.contains($0) }
        // BLACK CARDS WITH THEIR SEPARATION (2026-08-15, two user rulings
        // minutes apart: "it's fine if it is black cards", then "i like the
        // card separations, but not gray"): `surfaceSheet` (#111113) over the
        // composer's pure-black `inkGround` — an edge, not a gray box. Never
        // a stroke instead; no hairlines, zero exceptions.
        //
        // **A SECTION CARD IS A DIGEST NOW** (2026-08-16, user, holding the
        // approved mock against the built brief: "the day brief DOES NOT
        // LOOK LIKE THIS"). They were right, and the gap was density: the
        // deck pass shipped the mock's skeleton — black ground, cards, the
        // blue lede — while each card still contained its section's FULL
        // modules, heatmaps and sankeys and face rows, when the mock's whole
        // point is three lines: the section name small, ONE reading big, one
        // quiet subline. So a headed card now renders exactly that, and the
        // modules live behind a tap — expand in place, collapse again — so
        // nothing composed is lost, it just stops being the landing. The
        // readings come from the modules' own STRUCTURED args (a MoneyHero's
        // arg 0 is the compact total, an Alerts row is `title|meta|…`),
        // never parsed out of localized prose — the MoneyReceipt rule.
        if let headerRef = seg.first, let header = els[headerRef],
           header.comp == "Section" {
            digestCard(headerRef: headerRef, header: header,
                       members: Array(seg.dropFirst()), quietCard: isQuiet)
        } else {
            // The headless trailing run (the leads, anything unfiled) keeps
            // the plain card — there is no section name to digest under.
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ForEach(seg, id: \.self) { module($0, inCard: true) }
            }
            .opacity(isQuiet ? 0.68 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.s4)
            .background(DS.inkCard,
                        in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
        }
    }

    /// One section as the mock's three lines, modules behind the tap.
    @ViewBuilder
    private func digestCard(headerRef: String, header: GenEl,
                            members: [String], quietCard: Bool) -> some View {
        let title = header.str(0)
        let qualifier = header.str(1)
        // THE ACCORDION IS GONE (2026-08-16, user: "why does the daily brief
        // have accordians that is so weird"). Correct, and it was named as
        // wrong in this pass's own Apple analysis before being built anyway:
        // Apple never unfolds a summary card — Health, Fitness and Weather
        // all NAVIGATE from the summary to a detail. So the card is a door
        // where it has somewhere to send you (the section's own room, an arg
        // it has carried since §386j), and where it doesn't — "Your day"
        // spans every source — its modules render INLINE beneath the digest,
        // because a section with nowhere to go must not hide its contents
        // behind a control that goes nowhere (§83).
        let room = header.str(3)
        let hasDoor = !room.isEmpty
        let stat = qualifier.isEmpty ? digestStat(members) : qualifier
        let sub = digestSub(members)
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Button {
                guard hasDoor else { return }
                DSHaptic.selection()
                roomOpen?(room)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: DS.Space.s2) {
                        // THE TINTED GLYPH (2026-08-16) — the element that
                        // makes a Health card read as a Health card, named in
                        // this pass's own analysis and then left out of the
                        // build, which is most of why the result "still
                        // doesn't look like the mockups". Identity lives HERE
                        // now: a small symbol in the section's hue, so the
                        // card itself stays ink and colour annotates rather
                        // than contains.
                        Image(systemName: GenSection.symbol(header.str(2)))
                            .dsGlyph(11)
                            .foregroundStyle(GenSection.hue(header.str(2)))
                            .frame(width: 22, height: 22)
                            .background(GenSection.hue(header.str(2)).opacity(0.14),
                                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        Text(title)
                            .dsText(.subhead13).fontWeight(.semibold)
                            .foregroundStyle(DS.textSecondary)
                        Spacer(minLength: 0)
                        // Points RIGHT — it navigates. No chevron at all when
                        // there is nowhere to go.
                        if hasDoor {
                            Image(systemName: "chevron.right")
                                .dsGlyph(11)
                                .foregroundStyle(DS.textTertiary)
                        }
                    }
                    if !stat.isEmpty {
                        HStack(alignment: .center, spacing: DS.Space.s3) {
                            // VALUE AND UNIT ARE SEPARATE (2026-08-16) —
                            // Apple's summary signature: "96°", "12,482 steps",
                            // the figure at full weight and its noun small and
                            // grey beside it. Ours rendered "3 late" as one
                            // string, which is a sentence in a headline slot
                            // and reads ragged down a column where every other
                            // card leads with a bare figure. Split on the
                            // FIRST space and only when the head is numeric —
                            // a name-led reading ("mara +12 on your cast")
                            // must stay whole, since its subject is the name.
                            let parts = statSplit(stat)
                            // Attention ink ONLY for the late-reading (the
                            // qualifier §386l composes for Needs you) — a
                            // money total in orange would be an alarm about
                            // nothing.
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(parts.value)
                                    .dsText(.heading28)
                                    .foregroundStyle(!qualifier.isEmpty && header.str(2) == "attention"
                                                     ? DS.attention : DS.textPrimary)
                                    .monospacedDigit()
                                    .lineLimit(1).minimumScaleFactor(0.7)
                                if !parts.unit.isEmpty {
                                    Text(parts.unit)
                                        .dsText(.subhead13).fontWeight(.semibold)
                                        .foregroundStyle(DS.textTertiary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            // THE MINIATURE (mockup C, 2026-08-16): no summary
                            // card ships without its picture of the number
                            // moving — Health's own rule, and the reason the
                            // three-line digest read as a settings list. Drawn
                            // from the modules' STRUCTURED args the digest
                            // already holds; a section with no honest
                            // miniature draws none (never a decorative one).
                            digestMini(members)
                        }
                    }
                    // SILENT when the modules are right below (2026-08-16,
                    // device shot: "950 more · 176 people" appeared twice,
                    // once as this line and once on the fold card an inch
                    // beneath it). The sub is a STAND-IN for contents you
                    // cannot see — a roomless section shows its own, so the
                    // stand-in becomes an echo. Never the same fact told
                    // twice (§386g's own leads-vs-observations rule).
                    if !sub.isEmpty, hasDoor {
                        Text(sub)
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textTertiary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasDoor)
            // A roomless section shows its own modules — see the door note
            // above. These are the visual ones ("Your day"'s contact sheet,
            // faces, the map), so inline is also where they read best.
            if !hasDoor {
                ForEach(members, id: \.self) { module($0, inCard: true) }
            }
        }
        // The §386d step-back, whole-card (see the plain branch above).
        .opacity(quietCard ? 0.68 : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.s4)
        .background(DS.inkCard,
                    in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
        // The nav's scroll target AND its where-am-I spy — the header module
        // is no longer mounted, so the card takes over both of the jobs it
        // did: `scrollTo(headerRef)` lands here, and the offset preference
        // (quantized, §386k's re-run lesson) keeps the docked chips' blob
        // tracking the section under the fold.
        .id(headerRef)
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: GenSectionOffsetKey.self,
                                       value: [title: (geo.frame(in: .global).minY / 24).rounded() * 24])
            }
        }
    }

    /// A reading split into its figure and its noun — "3 late" → ("3",
    /// "late"), "$12,482" → ("$12,482", ""). Splits only when the head is
    /// genuinely numeric, so a NAME-led reading survives whole: "mara +12 on
    /// your cast" is a subject, not a measurement, and shrinking "on your
    /// cast" to a unit would make the card claim a quantity it isn't
    /// reporting. Purely presentational — the reading itself is unchanged.
    private func statSplit(_ stat: String) -> (value: String, unit: String) {
        guard let space = stat.firstIndex(of: " ") else { return (stat, "") }
        let head = String(stat[stat.startIndex..<space])
        let tail = String(stat[stat.index(after: space)...])
        // A head that starts with a digit or a currency mark, and a tail short
        // enough to BE a noun rather than a clause.
        let numeric = head.first.map { $0.isNumber || "$€£¥+-".contains($0) } ?? false
        guard numeric, !tail.contains(" · "), tail.count <= 12 else { return (stat, "") }
        return (head, tail)
    }

    /// The big line, from a member's own structured args. Only the modules
    /// whose arg IS a headline figure — never a derived sum, never prose.
    private func digestStat(_ members: [String]) -> String {
        for ref in members {
            guard let el = els[ref] else { continue }
            if el.comp == "MoneyHero" { return el.str(0) }
        }
        return ""
    }

    /// The trailing miniature — a shrunk chart from a member's own args.
    /// Three honest shapes and no fourth: a sparkline where a series exists
    /// (MoneyHero's CSV, ValueSpark's CSV), a count of attention dots where
    /// only a count exists (the alerts — their rows carry no dates, and
    /// placing invented positions on a time rail would be §83's fake status
    /// in miniature). Direction ink comes from the composed delta's own
    /// sign, a structured arg, not parsed prose.
    @ViewBuilder
    private func digestMini(_ members: [String]) -> some View {
        // FOUR SAMPLES MINIMUM (2026-08-16, device shot: the Money card's
        // spark drew as a flat run with one drop — two points make a
        // straight line and three make a tick, neither of which is a
        // sparkline, and both read as a broken graphic rather than a quiet
        // week). Under the floor the card shows no miniature at all, which
        // is the same refusal `digestMini` makes everywhere else.
        if let el = members.compactMap({ els[$0] }).first(where: { $0.comp == "MoneyHero" }),
           genCSVDoubles(el.str(2)).count >= 4 {
            let vals = genCSVDoubles(el.str(2))
            let up = el.str(1).hasPrefix("+")
            let flat = el.str(1).isEmpty
            miniSpark(vals, ink: flat ? DS.textTertiary
                      : TokenChartStyle.accent(change: up ? 1 : -1, scheme: scheme))
        } else if let el = members.compactMap({ els[$0] }).first(where: { $0.comp == "ValueSpark" }),
                  genCSVDoubles(el.str(2)).count >= 4 {
            miniBars(genCSVDoubles(el.str(2)))
        } else if let el = members.compactMap({ els[$0] }).first(where: { $0.comp == "Alerts" }) {
            let n = min(el.str(1).split(separator: ";").count, 4)
            HStack(spacing: 5) {
                ForEach(0..<max(n, 1), id: \.self) { _ in
                    Circle().fill(DS.attention).frame(width: 7, height: 7)
                }
            }
        }
    }

    /// The sparkline DRAWS ITSELF on, left to right — the same arrival the
    /// wallet headline's own curve plays, at the miniature's dose. A line
    /// whose shape is the data must not simply be there (§299).
    private func miniSpark(_ vals: [Double], ink: Color) -> some View {
        let lo = vals.min() ?? 0, hi = vals.max() ?? 1
        let span = max(hi - lo, 0.0001)
        return Canvas { ctx, size in
            var path = Path()
            for (i, v) in vals.enumerated() {
                let x = size.width * CGFloat(i) / CGFloat(max(vals.count - 1, 1))
                let y = size.height * (1 - CGFloat((v - lo) / span)) * 0.86 + size.height * 0.07
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(path, with: .color(ink),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 68, height: 28)
        .mask(alignment: .leading) {
            GeometryReader { geo in
                Rectangle().frame(width: geo.size.width * (reduceMotion ? 1 : sparkDrawn))
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.7).delay(0.2)) { sparkDrawn = 1 }
        }
    }

    /// Bars are SIZED FROM DATA, so they arrive rather than appear — the
    /// §299 motion law, caught here by its own audit on this pass's first
    /// full run. `chartArrival` is the shared entrance every other
    /// data-sized drawing in the app already uses (the exposure card's
    /// rows, the deposit shares), so the miniature can't drift from them and
    /// Reduce Motion is honoured inside it rather than re-checked here.
    private func miniBars(_ vals: [Double]) -> some View {
        let hi = max(vals.max() ?? 1, 0.0001)
        let shown = Array(vals.suffix(8))
        let hue = GenSection.hue("work")
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(shown.enumerated()), id: \.offset) { i, v in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(hue.opacity(i == shown.count - 1 ? 1 : 0.4))
                    .frame(width: 5, height: max(4, 24 * CGFloat(v / hi)))
                    .chartArrival(index: i, reduceMotion: reduceMotion)
            }
        }
        .frame(height: 26, alignment: .bottom)
    }

    /// The quiet line under it — first member that carries one.
    private func digestSub(_ members: [String]) -> String {
        for ref in members {
            guard let el = els[ref] else { continue }
            switch el.comp {
            case "MoneyHero":
                let s = el.str(3); if !s.isEmpty { return s }
            case "Alerts":
                // rows are `title|meta|source|id` joined by ";" — structured,
                // not prose (see `alertsCard`).
                if let row = el.str(1).split(separator: ";").first {
                    let parts = row.split(separator: "|", omittingEmptySubsequences: false)
                    let title = parts.count > 0 ? String(parts[0]) : ""
                    let meta = parts.count > 1 ? String(parts[1]) : ""
                    if !title.isEmpty {
                        return meta.isEmpty ? title : "\(title) · \(meta)"
                    }
                }
            case "DayFold":
                let s = el.str(3); if !s.isEmpty { return s }
            case "ValueSpark":
                let s = el.str(0); if !s.isEmpty { return s }
            default: break
            }
        }
        return ""
    }

    /// One module. Inside a DECK CARD the chapter's top air and the
    /// per-module quiet dim both stand down: the card's own margin is the air
    /// now, and the card's ink-vs-hue ground carries the whole quiet contrast
    /// (dimming white words on a saturated fill reads as a rendering bug, not
    /// as "you have seen this"). The head run — outside any card — keeps
    /// both behaviours exactly as §386d shipped them.
    private func module(_ ref: String, inCard: Bool = false) -> some View {
        GenRender(id: ref, els: els, slot: inAgentAnswer ? .block : .none)
            .padding(.top, !inCard && chapters.contains(ref) ? DS.Space.s4 : 0)
            .opacity(!inCard && quiet.contains(ref) ? 0.68 : 1)
            // Addressable HERE TOO (prd §386n, user: "the chips at top of the
            // composer do not lead to anywhere when user presses them").
            //
            // §386i put `.id(ref)` on the plain `Stack` branch and the chips
            // worked. §386i's own AMENDMENT then made `chapters` non-empty so
            // the Mac would lay out in two columns — and a chapter-carrying
            // doc routes through THIS view instead, where the ids did not
            // exist. `scrollTo` on an id nothing claims is a silent no-op, so
            // the fix for one platform's layout broke the other's navigation
            // with nothing on screen and nothing in a log to say so.
            //
            // Every layout path here funnels through this one function, so
            // the single column, the head run and the two-column blocks are
            // all addressable from one line.
            .id(ref)
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
    private static func headSegmentCount(_ segs: [[String]], els: GenEls = [:]) -> Int {
        guard let first = segs.first else { return 0 }
        // A SECTION IS NEVER IN THE HEAD (2026-08-16, from a device shot: the
        // brief's FIRST section rendered as a bare header with its module
        // loose beneath it, while every later section drew as a proper card —
        // one screen, two grammars).
        //
        // The rule below predates the cards: when the head was "masthead plus
        // the money story", a lone first segment pulled the next one up to
        // join it so the lead story spanned the page. Now the segments after
        // the head ARE the cards, so pulling one up silently un-cards it.
        // Sectioned docs take head = 1 (the lede alone); the old behaviour
        // survives for a doc whose chapters carry no `Section` — the scoped
        // briefs, which have no headers at all.
        if segs.count > 1, let opener = segs[1].first, els[opener]?.comp == "Section" {
            return 1
        }
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
    /// Scrub (prd §384): the answer's own curve reads back under the finger —
    /// the sample's value swaps into the delta pill's slot while pressed, so
    /// the figure in an answer is interrogable, not an illustration.
    @State private var scrubIndex: Int?

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
                        if let scrubIndex, series.indices.contains(scrubIndex) {
                            // One claim at a time: mid-scrub the slot states
                            // the sample, not the range's delta.
                            Text(TokenChartStyle.priceText(series[scrubIndex]))
                                .dsText(.callout15).fontWeight(.semibold)
                                .foregroundStyle(DS.textPrimary)
                                .contentTransition(.numericText())
                        } else {
                            TokenDeltaPill(change: change, label: "")
                        }
                    }
                    TokenChartPlot(chart: chart, accent: accent, height: 90, pulses: false,
                                   cursorIndex: scrubIndex,
                                   onScrub: { i in
                                       withAnimation(DS.Motion.standard) { scrubIndex = i }
                                   })
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
                // The elevated surface `Insight` already wears everywhere
                // else (2026-08-10, was a tint wash until the treemap-ink
                // pass retired hue-as-category app-wide): one grammar for
                // agent voice — the neutral ramp's ceiling tone
                // (`DS.ink(magnitude: 1)`), ink cards = your things. On
                // `dsWidgetSurface` the synthesis card was indistinguishable
                // from the modules it's summarizing; lightness alone still
                // separates them.
                .background(DS.ink(magnitude: 1),
                            in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .padding(.horizontal, DS.Space.s4)
                .padding(.top, DS.Space.s2)
            }
        }
    }
}

/// DayNote(glyph, text, thingID) — one observation. The glyph is the source's
/// own SF mark, now in the same neutral ramp (2026-08-10, was tint) — the
/// sentence carries the fact. A note that names a real thing opens it
/// (staying inside the agent, ruling 9); one that doesn't is plain text,
/// never a dead control.
private struct GenDayNoteLine: View {
    let el: GenEl
    @Environment(\.genThingOpen) private var thingOpen
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let id = el.str(2)
        let line = HStack(alignment: .top, spacing: DS.Space.s3) {
            Image(systemName: el.str(0).isEmpty ? "sparkles" : el.str(0))
                .dsGlyph(14)
                .foregroundStyle(DS.textSecondary)
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
                    .dsGlyph(12)
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
/// (and the same `DS.ink` washes at the same squared magnitude) the full
/// `TagMap` draws elsewhere, so the small read and the big one can't disagree
/// about which holding is largest.
/// DayLede(text, dateline, figure, direction) — the day brief's opening
/// sentence, in display type, above everything (2026-07-25, user: "that line
/// should be above wallet").
///
/// No surface, by design: it is a sentence on the page, not a card. The whole
/// point of putting it here rather than under the hero's total is that the
/// screen opens with WORDS — "Up $1,247 today." — and
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

    /// The monument's annotation ink — semantic, resolved from the composed
    /// tone, never parsed out of the figure.
    private func toneInk(_ tone: String) -> Color {
        switch tone {
        case "attention": return DS.attention
        case "up":        return TokenChartStyle.accent(change: 1, scheme: scheme)
        case "down":      return TokenChartStyle.accent(change: -1, scheme: scheme)
        default:          return DS.textSecondary
        }
    }

    var body: some View {
        // THE MONUMENT (2026-08-16, mockup C — retires the blue lede card of
        // the night before). The brief now opens the way Weather opens: the
        // day's one figure enormous and thin, its annotation word in the
        // semantic ink, and the sentence demoted to the quiet line beneath.
        // Blue returns to being chrome only (chips, berry, send) so the
        // monument owns the screen. args 4/5/6 are composed by TodayBrief's
        // clock; when they're empty the sentence stands alone at heading28 —
        // never a padded figure.
        //
        // The raw `.font(.system(size:))` on TEXT is deliberate and lawful —
        // the ramp audit's own doc scopes itself to glyphs ("the type ramp is
        // not" frozen) — because 74pt is a MONUMENT, a rung the reading ramp
        // should not carry: nothing else may ever borrow it without this
        // comment moving too.
        VStack(alignment: .leading, spacing: 2) {
            if !el.str(4).isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
                    Text(el.str(4))
                        .font(.system(size: 74, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    if !el.str(5).isEmpty {
                        Text(el.str(5))
                            .dsText(.heading17).fontWeight(.semibold)
                            .foregroundStyle(toneInk(el.str(6)))
                    }
                }
                sentence
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            } else {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s2)
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
                            .dsGlyph(12)
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
            DS.ink(magnitude: share(item))
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
                    // The source's own mark leads the meta line (2026-08-10,
                    // user: "there should be icons of where something is from
                    // on the list items"). `str(4)` has always carried the
                    // source — it was reachable ONLY as `RemoteArt`'s fallback,
                    // so a row with no banner (which is every row in a runway
                    // of deadlines) said nothing about where it came from, and
                    // four reminders from three different apps read as one
                    // undifferentiated list. Drawn at meta scale, beside the
                    // meta rather than above the title: which app this is from
                    // is context for the fact, not the headline.
                    if !el.str(1).isEmpty || !el.str(4).isEmpty {
                        HStack(spacing: DS.Space.s1) {
                            if !el.str(4).isEmpty {
                                BridgeIcon(name: el.str(4), size: DS.Mark.inline)
                            }
                            if !el.str(1).isEmpty {
                                Text(el.str(1))
                                    .dsText(.subhead13)
                                    .foregroundStyle(DS.textTertiary)
                                    .lineLimit(1)
                            }
                        }
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
                            .dsGlyph(11)
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
/// Dial(eyebrow, "hour|recency|source;…") — a week of things on a 24-hour
/// clock, as the answer ladder's WHEN rung (2026-08-16).
///
/// A THIN ADAPTER, the shape `GenWalletFlow` already uses for `WalletFlowBand`:
/// the drawing, its floor, its entrance choreography and its per-source hues are
/// `FigureView`'s, and nothing about them is re-decided here. That matters more
/// than usual for this one — the dial is not a new figure. It was built for the
/// agent panel, shipped there, and lost its only caller when the panel was
/// deleted (§386p); this re-homes it rather than drawing it again.
///
/// `.band`: full width, and `DialFigure` sizes off `min(width, height)` and
/// centres, so a wide slot draws the same circle a square one would and simply
/// gives it room to breathe.
///
/// It carries no `Thing` — the marks are three scalars each by the time they
/// reach the document — so the liveness rules have nothing to bite on.
private struct GenDial: View {
    let el: GenEl
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Rebuilt from the doc. A mark needs all three fields to mean anything (a
    /// half-parsed hour would place a dot at the wrong time of day, which is
    /// the one thing this figure claims), so an incomplete row is dropped
    /// rather than guessed at — and while the line is still streaming the whole
    /// module simply waits below its floor.
    private var marks: [AgentPanel.DialMark] {
        el.str(1).split(separator: ";").compactMap { row in
            let f = row.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard f.count == 3, let hour = Double(f[0]), let recency = Double(f[1]),
                  hour >= 0, hour <= 24 else { return nil }
            return AgentPanel.DialMark(hour: hour, recency: recency, source: String(f[2]))
        }
    }

    var body: some View {
        let figure = AgentPanel.Figure.dial(marks)
        Group {
            if !figure.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    if !el.str(0).isEmpty {
                        Text(el.str(0)).dsText(.callout15).fontWeight(.semibold)
                            .foregroundStyle(DS.textPrimary)
                    }
                    FigureView(figure: figure, slot: .band, hue: DS.tint,
                               rising: nil, reduceMotion: reduceMotion)
                        .frame(height: 150)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, DS.Space.s4)
                .padding(.top, DS.Space.s2)
            }
        }
    }
}

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
                BridgeIcon(name: item.tag, size: DS.Mark.inline)
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
            DS.ink(magnitude: share(item))
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
