import SwiftUI

/// Liquid glass and surface treatments, expressed as tokens so no component
/// reaches for a material, blur radius, or highlight directly.
///
/// On iOS 26+ the shell wears the system's real Liquid Glass (`glassEffect`,
/// interactive); earlier systems get the material recipe (translucent fill,
/// blur, highlight stroke). Same call site either way — the token decides.
///
/// Hairline separators died by amendment: rows separate by spacing and press
/// fills, groups by their card surfaces. Nothing draws a line.
/// Which glass recipe a floating element wears — the two the system actually
/// draws, expressed as a token so no call site names a material (2026-08-06).
///
/// `regular` is the default and the right answer for chrome over CONTENT: rows,
/// words, a feed. It frosts, and the frosting is what buys legibility over text
/// travelling underneath.
///
/// `clear` is for chrome over PIXELS. A photograph is already the brightest,
/// busiest thing on the screen, and a frosted disc over it reads as a smudge ON
/// the picture rather than a control floating above it. It is deliberately NOT a
/// taste option: `clear` withholds exactly the contrast `regular` provides, so
/// it is only correct where what's behind it is a picture we are showing
/// full-bleed on a dark ground — which in this app is `PhotoViewer` and nothing
/// else. Anything over rows keeps `regular`.
enum DSGlassVariant { case regular, clear }

/// A glass union — an id plus the namespace it lives in, threaded as ONE value
/// so a caller can't supply half of it (2026-08-06).
struct DSGlassUnion {
    let id: String
    let namespace: Namespace.ID
}

/// Glass numbers that are nobody's call site's business.
private enum DSGlassMetrics {
    /// The fixed doors' radius — they are 46pt circles, so half of that.
    ///
    /// One constant, because their union only merges cleanly if both shapes
    /// match: a door rounded differently from its partner reads as one shape
    /// smearing into another rather than as a single capsule.
    static let doorRadius: CGFloat = 23

    /// How much of a room's hue a tinted floating element takes (2026-08-06).
    ///
    /// Stated here, once, rather than per call site: the whole value of tinting
    /// the floating layer is that it says which room you're standing in, and a
    /// dose picked per element would let one bar shout while another whispers
    /// the same fact. Low on purpose — this is a lens over a hue, not a painted
    /// slab; past ~0.3 the glass stops reading as glass and the marks sitting
    /// on it start taking the colour too.
    static let tintDose: Double = 0.2
}

extension View {

    /// The floating glass treatment for the composer pill and the tab capsule.
    /// Pass a `glassID` + namespace to join the shell's glass morph: elements
    /// sharing a container flow between shapes instead of swapping.
    ///
    /// `tint` re-colours the glass to a room's own hue — see
    /// `DSGlassMetrics.tintDose` for how much, and `RootShell`'s agent-bar call
    /// for when. nil is the neutral default and stays the answer everywhere the
    /// hue would be decoration rather than information.
    @ViewBuilder
    func dsGlass(cornerRadius: CGFloat,
                 variant: DSGlassVariant = .regular,
                 tint: Color? = nil,
                 glassID: String? = nil, in namespace: Namespace.ID? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            let base: Glass = variant == .clear ? .clear : .regular
            let glass = (tint.map { base.tint($0.opacity(DSGlassMetrics.tintDose)) } ?? base)
                .interactive()
            if let glassID, let namespace {
                self
                    .glassEffect(glass, in: shape)
                    .glassEffectID(glassID, in: namespace)
            } else {
                self.glassEffect(glass, in: shape)
            }
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                // `clear` skips the frosting fill — the material alone, so the
                // picture behind it stays a picture.
                .background(variant == .clear ? Color.clear : DS.glassBg, in: shape)
                .background(tint?.opacity(DSGlassMetrics.tintDose) ?? Color.clear, in: shape)
                .overlay(shape.strokeBorder(DS.glassStroke, lineWidth: 1))
                .clipShape(shape)
                // A lighter cast over pixels: the shadow exists to separate the
                // control from a busy page, and over a photo on black ground
                // there is nothing to separate it from.
                .shadow(color: variant == .clear ? DS.glassShadowClear : DS.glassShadow,
                        radius: 12, x: 0, y: 8)
        }
    }

    /// Two glass shapes that are ONE substance (2026-08-06).
    ///
    /// Both views must sit in the same `DSGlassContainer`, and the union is what
    /// makes the merge deterministic: it fuses the pair regardless of the gap
    /// between them, where leaning on the container's `spacing` to bridge them
    /// depends on a layout constant nobody edits with this in mind (the
    /// whisper/bar pair's own note, from the other direction — there the merge
    /// is the thing to PREVENT, which is why that container passes spacing 0).
    ///
    /// Reach for it only where the two shapes really are one object. The shell's
    /// bottom cluster is coordinated and NOT fused by ruling (2026-07-22, the
    /// double-bar read), so this is not a general tidy-up.
    @ViewBuilder
    func dsGlassUnion(_ union: DSGlassUnion?) -> some View {
        if #available(iOS 26.0, *), let union {
            self.glassEffectUnion(id: union.id, namespace: union.namespace)
        } else {
            self
        }
    }

    /// A fixed door at the head of the source strip — the avatar and the
    /// catalogue, which are one object and had never rendered as one
    /// (2026-08-06).
    ///
    /// The strip's own comment has said since 2026-07-20 that "the doors and the
    /// 'All' chip wear the floating material", and only the catalogue door ever
    /// did — the avatar wore a flat gray well beside it. Both wear glass now, at
    /// one shared radius, joined into a single continuous shape. That is the
    /// hierarchy the layout already builds and never drew: these two sit OUTSIDE
    /// the scroll because they are furniture, the app icons scroll past because
    /// they are content, and a merged capsule says so at a glance where two
    /// identical circles in a row of circles could not.
    func dsGlassDoor(_ union: DSGlassUnion?) -> some View {
        dsGlass(cornerRadius: DSGlassMetrics.doorRadius)
            .dsGlassUnion(union)
    }

    /// Glass that arrives AS GLASS (2026-08-06) — the system's own materialize,
    /// so a floating element that appears grows its lens in rather than fading
    /// in like any other view.
    ///
    /// For chrome that arrives on its own schedule and is legitimately new: the
    /// whisper, which shows once a day, and the outcome toast. NOT for chrome
    /// that is simply always there.
    ///
    /// Reduce Motion takes `.identity`, which is the system's own still form of
    /// this transition, not a hand-rolled fallback.
    @ViewBuilder
    func dsGlassMaterialize() -> some View {
        if #available(iOS 26.0, *) {
            modifier(DSGlassMaterialize())
        } else {
            self
        }
    }
}

@available(iOS 26.0, *)
private struct DSGlassMaterialize: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.glassEffectTransition(reduceMotion ? .identity : .materialize)
    }
}

extension View {

    /// Tinted prominent glass — the one primary action sitting on a glass
    /// surface (the composer's Save). Falls back to a flat tint fill.
    @ViewBuilder
    func dsGlassProminent(tint: Color, cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            self.background(tint, in: shape)
        }
    }
}

/// Wraps the shell's floating elements so their glass merges and morphs as one
/// substance (iOS 26). Below 26 it is a plain passthrough.
struct DSGlassContainer<Content: View>: View {
    var spacing: CGFloat = DS.Space.s3
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

extension View {
    /// The one sheet-surface treatment for cards, tiles, and trays.
    /// No border (anti-pattern: borders on cards) — the sheet fill plus a soft
    /// ambient shadow carry elevation (elevation ladder, 2026-07-12). Content
    /// never wears glass — glass is the floating layer only.
    func dsCard(cornerRadius: CGFloat = DS.Radius.card) -> some View {
        dsElevatedSurface(cornerRadius: cornerRadius)
    }

    /// The elevated widget-card surface — the one sheet fill at the widget
    /// radius, lifted off the page by the ambient card shadow. The Home board's
    /// tiles and every gen-UI module card route through this so the lift lives
    /// in ONE place, not hand-copied per renderer (elevation ladder 2026-07-12).
    /// `fillOpacity` below 1 lets whatever is BEHIND the card read through it
    /// (prd §160, 2026-07-21) — the crown pour, in practice. An opaque card on
    /// the pour punches a hole in the one atmospheric move the shell makes; at
    /// ~0.82 the field still travels under the surface while the card keeps its
    /// edge and its lift. Still a fill, never a material: glass is the floating
    /// layer's alone (design law), and this is content.
    func dsWidgetSurface(cornerRadius: CGFloat = DS.Radius.widget,
                         fillOpacity: Double = 1) -> some View {
        dsElevatedSurface(cornerRadius: cornerRadius, fillOpacity: fillOpacity)
    }

    /// The shared sheet-fill-plus-shadow recipe. The shadow rides the FILL
    /// SHAPE (a simple rounded rect), not the composited view — so Core
    /// Animation casts it from a cheap path instead of rasterizing each card's
    /// content offscreen every scroll frame (matches `dsSheetSurface`, which
    /// shadows the clipped shape rather than the live view).
    private func dsElevatedSurface(cornerRadius: CGFloat,
                                   fillOpacity: Double = 1) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(DS.surfaceSheet.opacity(fillOpacity))
                .shadow(color: DS.cardShadow, radius: 18, x: 0, y: 6)
        }
    }

    /// A grouped-list row background that lifts the whole SECTION as one card.
    /// The sheet fill carries the ambient card shadow; in an inset-grouped List
    /// the rows are gapless, so a row's shadow falls on the adjacent same-color
    /// row and vanishes — only the section's outer silhouette casts, reading as
    /// one lifted card rather than a stack of shadowed rows (ladder 2026-07-12).
    /// Cursor-aware everywhere for free (Mac polish, 2026-07-28) — every row
    /// was designed for a finger, which has no concept of hover, and on Mac
    /// that reads as a dead app the instant the cursor moves without
    /// anything responding. `.hoverEffect` is folded in HERE rather than
    /// added at each of this modifier's 27 call sites, so a screen that
    /// adopts `dsListCardRow()` gets Mac hover with no separate decision.
    /// It's the same pointer API iPad has carried since Catalyst's
    /// inception (a physical pointer on iPad and a Mac cursor are the same
    /// UIKit interaction underneath), so it's a no-op on touch.
    func dsListCardRow() -> some View {
        listRowBackground(
            DS.surfaceSheet.shadow(color: DS.cardShadow, radius: 18, x: 0, y: 6)
        )
        .hoverEffect(.automatic)
    }

    /// The same cursor-aware treatment for anything that ISN'T a List row —
    /// the source chips, the avatar/catalogue doors, a card grid tile.
    func dsHover(_ effect: HoverEffect = .automatic) -> some View {
        hoverEffect(effect)
    }

    /// Grow a small control's TAP TARGET to the 44pt floor without growing what
    /// it DRAWS (2026-08-13, the accessibility sweep).
    ///
    /// The distinction is the whole point, and it is what ten shipped controls
    /// got wrong: a 30pt circle with a 30pt frame is a 30pt target, and the fix
    /// is not to draw a bigger circle — that would rewrite the visual rhythm of
    /// every row it sits in. The drawn face keeps its own frame (and its own
    /// background, which is why this goes AFTER the `.background`, never before)
    /// and a `minWidth`/`minHeight` floor grows only the box around it, which
    /// `contentShape` then makes hittable in full.
    ///
    /// A `min` frame rather than the padding/negative-padding trick, and that is
    /// deliberate: the trick keeps the layout byte-identical but relies on
    /// hit-testing OUTSIDE the layout bounds, which is exactly the kind of thing
    /// that works until a `.clipped()` appears three levels up and then fails
    /// silently and invisibly. This costs a few points of space in a handful of
    /// rows and cannot fail quietly. A control that must be 44pt to be usable
    /// should occupy 44pt.
    ///
    /// `shape` should match what the control looks like, so the corners of a
    /// circular button don't swallow taps meant for its neighbour.
    func dsTapTarget<S: Shape>(_ shape: S = Rectangle(),
                               size: CGFloat = DS.Hit.min) -> some View {
        modifier(DSTapTarget(shape: shape, size: size))
    }

    /// A view whose WHOLE FACE is one tap target — a bundle row, a roster slot,
    /// a project tile, an agent card (2026-08-13, the accessibility sweep).
    ///
    /// `contentShape(…)` + `onTapGesture` is a complete control for touch and
    /// for a pointer and carries NOTHING for VoiceOver: no trait, so it is never
    /// announced as activatable, and no action, so a double-tap does nothing.
    /// This states both. `children: .combine` is the right merge here and not a
    /// shortcut — the whole face does ONE thing, so it should be ONE stop rather
    /// than four fragments the reader has to reassemble, and any button among
    /// those children survives as a custom action rather than being lost.
    ///
    /// Use `dsCardLead` instead where the container holds ranked rows that must
    /// stay individually reachable; the two differ on exactly that.
    func dsTapCard() -> some View {
        accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
    }

    /// The card-level tap, made reachable (2026-08-13, the accessibility sweep).
    ///
    /// **The bug this fixes is a dead end, not an inconvenience.** A room head
    /// puts `contentShape(Rectangle())` + `onTapGesture` on the whole card and
    /// opens `room.lead` — and neither of those adds a trait or an action, so
    /// VoiceOver has nothing to announce and nothing to activate. That would be
    /// merely untidy if the lead were also a row, and it is NOT: every one of
    /// these cards draws `drawn.dropFirst()` on purpose ("the lead is already in
    /// the headline, and repeating its name directly underneath is the card
    /// arguing with itself"). So the card's most important destination — the
    /// biggest rail, the busiest currency, the segment that needs you — was
    /// reachable by touch and by pointer and by nothing else.
    ///
    /// Applied to the HEADLINE, not the card, and that is the load-bearing part.
    /// A `Text` is already an accessibility element, so a trait and an action
    /// attach to something real and VoiceOver activates it on a double-tap.
    /// Putting them on the card container instead would mean either
    /// `children: .contain` (traits and actions on a container are not reliably
    /// surfaced) or `children: .combine` (which flattens the ranked rows below
    /// into one announcement and costs their individual buttons) — and the
    /// headline is where the lead is NAMED anyway, so this is also the honest
    /// place for it. The sighted whole-card gesture is untouched.
    func dsCardLead(_ hint: Text, perform action: @escaping () -> Void) -> some View {
        accessibilityAddTraits(.isButton)
            .accessibilityHint(hint)
            // `.default` is what a VoiceOver double-tap fires — the same
            // gesture that would have activated a real Button here.
            .accessibilityAction(.default, action)
    }

    /// A Mac hover tooltip (2026-08-01). Mac-ONLY on purpose, and the gate is
    /// the whole reason this wrapper exists rather than a bare `.help()`.
    ///
    /// `help(_:)` renders a tooltip on Mac but sets the ACCESSIBILITY HINT
    /// everywhere else — so on iPhone a chip already labelled "Photos" would
    /// gain the hint "Photos", and VoiceOver reads label then hint. The
    /// tooltip's whole value is on a pointer surface; the hint's cost is on a
    /// touch one. Gating separates them.
    ///
    /// Why the source chips need it at all: they are icon-only 56pt circles
    /// with no labels (ruling 2026-07-09), which works on a phone because the
    /// strip is short and thumb-learned. A Mac rail can hold a dozen sources
    /// at once, a cursor can rest on one without committing to it, and the
    /// tooltip is the only affordance that names a mark you don't recognize
    /// without making you click into the room to find out. It renders nothing
    /// until hover, so the no-labels ruling is untouched.
    @ViewBuilder
    func dsTooltip(_ text: String) -> some View {
        #if targetEnvironment(macCatalyst)
        help(text)
        #else
        self
        #endif
    }

    /// A modal sheet / tray surface with the overlay shadow.
    func dsSheetSurface() -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous)
        return self
            .background(DS.surfaceSheet, in: shape)
            .clipShape(shape)
            // `DS.cardShadow`, not a pinned black: its DARK value is exactly
            // the 0.55 this used to hardcode, so dark is byte-identical, while
            // light drops to 0.12 — the pinned value was a dark-page shadow
            // cast onto a white one, four and a half times too heavy.
            .shadow(color: DS.cardShadow, radius: 16, x: 0, y: 12)
    }
}

extension View {
    /// iOS 26 soft scroll edges — content melts under BOTH pieces of floating
    /// chrome that ride every screen: the source-chip strip at the top and the
    /// agent bar at the bottom. Each floats OVER the scroll view (the strip via
    /// `MainSurface`'s `safeAreaInset(.top)`, the bar hosted in `RootShell`'s
    /// own ZStack), so scrolled content travels under both — the soft edge
    /// dissolves the rows as they pass, so nothing collides with either bar.
    ///
    /// The bottom edge pairs with the agent bar exactly the way the top edge
    /// pairs with the strip (2026-07-23): the bar had the same geometry as the
    /// strip — content passing beneath it — but no dissolve, so rows met its
    /// glass with a hard edge. One `Edge.Set` call softens the pair.
    /// The LEADING edge joins them on a regular-width surface (2026-08-10),
    /// and only there — that is where `MainSurface` hangs the source rail,
    /// and the rail is the same geometry as the strip one axis over: chrome
    /// the content now travels beneath (see `MainSurface.body`). Without it
    /// rows meet the rail's glass with a hard edge, which is the exact
    /// mismatch the bottom edge was added to fix for the agent bar in
    /// 2026-07-23.
    ///
    /// Gated on the size class rather than added to the set unconditionally:
    /// there is no rail on iPhone, so a leading effect there would dissolve
    /// the left edge of every row on 62 screens against no chrome at all —
    /// a fade that reads as a rendering fault because nothing explains it.
    /// The gate is the same one `PadLayout` uses, for the same reason.
    func dsSoftScrollEdges() -> some View {
        modifier(DSSoftScrollEdges())
    }
}

private struct DSSoftScrollEdges: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            let edges: Edge.Set = horizontalSizeClass == .regular
                ? [.top, .bottom, .leading]
                : [.top, .bottom]
            content.scrollEdgeEffectStyle(.soft, for: edges)
        } else {
            content
        }
    }
}

extension View {
    /// Real glass on a shape that MOVES — the travelling selection fill in the
    /// source strip (prd §359).
    ///
    /// Separate from `dsGlass` because the two want opposite things from their
    /// tint. `dsGlass(tint:)` doses a hue onto a resting surface at
    /// `DSGlassMetrics.tintDose` so the surface stays a surface; this wraps a
    /// shape that is ALREADY the accent at full strength and only wants the
    /// material's own lensing and specular edge over it, so it takes no tint of
    /// its own. Passing the accent through `dsGlass` instead would wash it to
    /// 20% and lose the one cue that has to be unmistakable.
    @ViewBuilder
    func dsGlassBlob() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
        } else {
            self
        }
    }
}

/// The 44pt floor, applied around whatever the control draws. See
/// `View.dsTapTarget(_:size:)` for why the drawn size and the target size are
/// two different numbers.
private struct DSTapTarget<S: Shape>: ViewModifier {
    let shape: S
    let size: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(minWidth: size, minHeight: size)
            .contentShape(shape)
    }
}
