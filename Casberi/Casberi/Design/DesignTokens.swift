import SwiftUI

/// The token layer. Ported from the prototype's `src/index.css` `:root` block
/// and reconciled against build brief §8, which is treated as law.
///
/// Rules this layer enforces (brief §8, §12):
///   • Every value routes through a token. Components hold zero raw hex.
///   • One tint (`DS.tint`). One-line swap changes the whole interactive family.
///   • One sheet surface token for cards, tiles, trays. Washes are dead.
///   • Text ramp: primary (white) / secondary (60%) / tertiary (30%).
///   • Color carries identity, state, or magnitude — never decoration.
///     Magnitude = tint at opacity scaled by count (`DS.tint(magnitude:)`).
///
/// RECONCILIATION NOTE (flagged for M0 review): the prototype CSS renders
/// cards at radius 18 / sheets 22, but brief §8 *and* PRD design-principle 1
/// both state cards 10 / sheets 16 / app-icons 22.37%. The user set §8 as law,
/// so the radius tokens below follow §8. `control` (12) and `pill` come from
/// the prototype for the values §8 does not name.
enum DS {

    // MARK: - Surfaces & grays  (dark / light)

    /// Page background — live-themed (mode, curated color, photo-implies-dark).
    static var page: Color { themedPage }
    /// Elevated background (nav glass base, some tiles).
    static let background100  = Color.adaptive(dark: "#1c1c1e", light: "#ffffff")
    /// The one sheet-surface token — cards, tiles, trays. Brief §8.
    static let surfaceSheet   = Color.adaptive(dark: "#111113", light: "#ffffff")

    static let gray100  = Color.adaptive(dark: "#2c2c2e", light: "#e5e5ea")
    static let gray200  = Color.adaptive(dark: "#3a3a3c", light: "#d1d1d6")
    static let gray300  = Color.adaptive(dark: "#48484a", light: "#c7c7cc")
    static let gray400  = Color.adaptive(dark: "#545458a6", light: "#3c3c434a")
    static let gray600  = Color.adaptive(dark: "#5a5a5e", light: "#aeaeb2")

    // MARK: - Text ramp  (primary / secondary / tertiary)

    /// True while a vivid background (bright primary or photo) is in force —
    /// the quiet 60/30 ramp that works on black washes out against loud color,
    /// so the ramp brightens (ruling 2026-07-06, "hard to read").
    private static var vividBackground: Bool {
        ThemeStore.shared.backgroundPhoto != nil
            || ThemeStore.shared.background.name != "Default"
    }

    /// Primary text — 100%. Brief §8: "white".
    static let textPrimary    = Color.adaptive(dark: "#ffffff", light: "#000000")
    /// Secondary text — 60% on the quiet page, 85% on a vivid one.
    static var textSecondary: Color {
        vividBackground
            ? Color.adaptive(dark: "#ffffffd9", light: "#000000c6")
            : Color.adaptive(dark: "#ebebf599", light: "#3c3c4399")
    }
    /// Tertiary text — 30% quiet / 60% vivid. Also placeholder / disabled glyphs.
    static var textTertiary: Color {
        vividBackground
            ? Color.adaptive(dark: "#ffffff99", light: "#00000099")
            : Color.adaptive(dark: "#ebebf54d", light: "#3c3c434d")
    }
    /// Between secondary and tertiary (CSS gray-800).
    static let textQuaternary = Color.adaptive(dark: "#ebebf573", light: "#3c3c4373")

    // MARK: - Fills

    static let fillFaint  = Color.adaptive(dark: "#ffffff0a", light: "#00000008")
    static let fillLine   = Color.adaptive(dark: "#ffffff1a", light: "#00000014")
    static let fillStrong = Color.adaptive(dark: "#ffffff29", light: "#00000024")

    // MARK: - Elevation ladder  (2026-07-12 — depth by tone, never by line)

    /// A recessed WELL — cover/chart/media backings that sit BELOW the card
    /// plane. In dark it steps toward the page (darker than `surfaceSheet`);
    /// in light it dips back to a soft gray under the white card. The tonal
    /// step alone carries the recess — no inner stroke (that reads as a line).
    static let surfaceWell   = Color.adaptive(dark: "#080809", light: "#e9e9ef")
    /// The ambient shadow a card casts to lift off the page. Not a hairline:
    /// soft, wide, low-opacity — the iOS-native way a surface says "surface".
    /// Heavy in dark (a `#111` card on `#000` needs it), whisper-light in light.
    static let cardShadow    = Color.adaptive(dark: "#0000008c", light: "#0000001f")

    // MARK: - Tint (one accent)  — brief §8, principle 2

    /// The one tint. Routed through `ThemeStore` so the swap ("pink one line
    /// away") is a runtime choice; reading it in a body tracks the store.
    static var tint: Color { themedTint }
    /// Tint at rest-chip opacity.
    static var tintDim: Color { themedTintDim }

    /// Magnitude fill — tint at opacity scaled by a normalized count `t ∈ [0,1]`.
    /// Treemaps and project fills only (color rule: magnitude, not decoration).
    static func tint(magnitude t: Double) -> Color {
        let clamped = min(max(t, 0), 1)
        return tint.opacity(0.06 + 0.22 * clamped)
    }

    // MARK: - Semantic state  — orange attention, red destructive, green confirm

    static let attention   = Color.adaptive(dark: "#ff9f0a", light: "#ff9500")
    static let destructive = Color.adaptive(dark: "#ff453a", light: "#ff3b30")
    static let confirm     = Color.adaptive(dark: "#30d158", light: "#34c759")

    // MARK: - Glass & overlays  — liquid glass, brief §8 / shell spec

    static let glassBg     = Color.adaptive(dark: "#1c1c1e8c", light: "#f9f9f9b8")
    static let glassStroke = Color.adaptive(dark: "#ffffff1a", light: "#0000000f")
    static let scrim       = Color.adaptive(dark: "#00000080", light: "#0000004d")

    // MARK: - Spacing scale  (CSS --ds-space-*)

    enum Space {
        static let s1: CGFloat = 4
        static let s2: CGFloat = 8
        static let s3: CGFloat = 12
        static let s4: CGFloat = 16
        static let s6: CGFloat = 24
        static let s8: CGFloat = 32
    }

    // MARK: - Layout (iPad content width — see `dsAdaptiveContentWidth()`)

    enum Layout {
        /// The single-column content cap on iPad (regular width class).
        /// Wide enough to read as intentional, not cramped; narrow enough
        /// that a row/text block never touches the physical screen edges.
        static let iPadContentMaxWidth: CGFloat = 900
    }

    // MARK: - Radii  (brief §8 is law; control/pill fill the gaps §8 omits)

    enum Radius {
        static let card: CGFloat  = 10   // §8 law (prototype rendered 18)
        static let sheet: CGFloat = 16   // §8 law (prototype rendered 22)
        static let control: CGFloat = 12 // prototype
        static let pill: CGFloat = 9999
        /// App-icon squircle ratio — brief §8: 22.37%.
        static let appIconRatio: CGFloat = 0.2237
        static func appIcon(_ size: CGFloat) -> CGFloat { size * appIconRatio }
    }

    // MARK: - Motion  — 250ms, Apple sheet curve, one animation per moment

    enum Motion {
        static let duration: Double = 0.25
        /// cubic-bezier(.32, .72, 0, 1) — the prototype's `--ds-ease`.
        static let standard = Animation.timingCurve(0.32, 0.72, 0, 1, duration: duration)
        /// Slightly longer for the composer bubble (prototype: 260ms).
        static let bubble = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.26)
    }
}


/// The press feel for tappable tiles and pills: a soft spring dip, matching
/// iOS's own control feedback (polish 2026-07-07).
struct PressSpring: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.5),
                       value: configuration.isPressed)
    }
}
