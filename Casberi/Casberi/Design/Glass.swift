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
extension View {

    /// The floating glass treatment for the composer pill and the tab capsule.
    /// Pass a `glassID` + namespace to join the shell's glass morph: elements
    /// sharing a container flow between shapes instead of swapping.
    @ViewBuilder
    func dsGlass(cornerRadius: CGFloat,
                 glassID: String? = nil, in namespace: Namespace.ID? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            if let glassID, let namespace {
                self
                    .glassEffect(.regular.interactive(), in: shape)
                    .glassEffectID(glassID, in: namespace)
            } else {
                self.glassEffect(.regular.interactive(), in: shape)
            }
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .background(DS.glassBg, in: shape)
                .overlay(shape.strokeBorder(DS.glassStroke, lineWidth: 1))
                .clipShape(shape)
                .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 8)
        }
    }

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

    /// A modal sheet / tray surface with the overlay shadow.
    func dsSheetSurface() -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous)
        return self
            .background(DS.surfaceSheet, in: shape)
            .clipShape(shape)
            .shadow(color: .black.opacity(0.55), radius: 16, x: 0, y: 12)
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
    @ViewBuilder
    func dsSoftScrollEdges() -> some View {
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        } else {
            self
        }
    }
}
