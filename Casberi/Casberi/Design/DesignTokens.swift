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

    /// True when the person has asked the system for higher contrast — the
    /// ramp answers it by climbing (see the ratios on each tier below).
    private static var moreContrast: Bool { ContrastStore.shared.increased }

    /// Primary text — 100%. Brief §8: "white". 21:1 / 18.8:1.
    static let textPrimary    = Color.adaptive(dark: "#ffffff", light: "#000000")

    /// Secondary text. Contrast pass 2026-07-21: dark held at 60% (6.2:1, was
    /// already clear), LIGHT raised 60% → 84%. Apple's own `secondaryLabel`
    /// value measured 3.3:1 on our light page — under the 4.5:1 body-text bar,
    /// and this tier carries real sentences, not hints. 5.9:1 now.
    static var textSecondary: Color {
        if moreContrast {
            return Color.adaptive(dark: "#ebebf5c9", light: "#3c3c43")     // 10.1:1 / 9.1:1
        }
        return vividBackground
            ? Color.adaptive(dark: "#ffffffd9", light: "#000000c6")
            : Color.adaptive(dark: "#ebebf599", light: "#3c3c43d6")        //  6.2:1 / 5.9:1
    }

    /// Tertiary text — row metadata (timestamps, source names), placeholders,
    /// disabled glyphs. Contrast pass 2026-07-21: raised HARD, dark 30% → 49%
    /// and light 30% → 74%. At 30% this measured 2.3:1 dark and 1.7:1 light —
    /// the worst failure in the app, and it was reading `subhead13` metadata in
    /// every feed row, so it was informational text wearing a hint's tone.
    /// The tier stays visibly quieter than secondary; it is no longer unreadable.
    static var textTertiary: Color {
        if moreContrast {
            return Color.adaptive(dark: "#ebebf5a4", light: "#3c3c43e7")   //  7.0:1 / 7.0:1
        }
        return vividBackground
            ? Color.adaptive(dark: "#ffffff99", light: "#00000099")
            : Color.adaptive(dark: "#ebebf57e", light: "#3c3c43bd")        //  4.5:1 / 4.5:1
    }

    /// Between secondary and tertiary (CSS gray-800). Raised on the same pass.
    static var textQuaternary: Color {
        moreContrast
            ? Color.adaptive(dark: "#ebebf5c9", light: "#3c3c43")           // 10.1:1 / 9.1:1
            : Color.adaptive(dark: "#ebebf58c", light: "#3c3c43c9")         //  5.4:1 / 5.1:1
    }

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

    /// The crown pour's color (prd §204) — the person's choice of five,
    /// Casberi blue by default. `MainSurface.crownPour`'s ONLY consumer;
    /// never route a chip, glyph, or state fill through this — those stay on
    /// `DS.tint`, which alone carries the Increase Contrast guarantee.
    static var bleed: Color { themedBleed }

    /// Magnitude fill — tint at opacity scaled by a normalized count `t ∈ [0,1]`.
    /// Treemaps and project fills only (color rule: magnitude, not decoration).
    static func tint(magnitude t: Double) -> Color {
        let clamped = min(max(t, 0), 1)
        return tint.opacity(0.06 + 0.22 * clamped)
    }

    // MARK: - Semantic state  — orange attention, red destructive, green confirm

    /// The three keep Apple's system values by default — they read as native,
    /// and they mostly paint glyphs and fills, which answer to the 3:1 bar for
    /// non-text, not 4.5:1. Under Increase Contrast each drops to a measured
    /// ≥4.5:1 variant on our light surfaces (the light values are the weak
    /// ones: system orange measures 1.8:1 and green 1.8:1 on white), so the
    /// person who asked for contrast gets it wherever these DO carry words.
    static var attention: Color {
        moreContrast ? Color.adaptive(dark: "#ffb340", light: "#9b5a00")
                     : Color.adaptive(dark: "#ff9f0a", light: "#ff9500")
    }
    static var destructive: Color {
        moreContrast ? Color.adaptive(dark: "#ff7b70", light: "#c62e25")
                     : Color.adaptive(dark: "#ff453a", light: "#ff3b30")
    }
    static var confirm: Color {
        moreContrast ? Color.adaptive(dark: "#5ce07f", light: "#1f7936")
                     : Color.adaptive(dark: "#30d158", light: "#34c759")
    }

    // MARK: - Glass & overlays  — liquid glass, brief §8 / shell spec

    static let glassBg     = Color.adaptive(dark: "#1c1c1e8c", light: "#f9f9f9b8")
    static let glassStroke = Color.adaptive(dark: "#ffffff1a", light: "#0000000f")
    static let scrim       = Color.adaptive(dark: "#00000080", light: "#0000004d")

    // MARK: - Spacing scale  (CSS --ds-space-*)

    // Breathing-room pass (2026-07-25). The app read a bit dense — most visibly
    // where cards stack (the wallet), but the fix belongs to the whole app, not
    // one screen: everything routes through this scale, so loosening it here is
    // the single global lever. The three CONTENT-RHYTHM rungs — inter-element
    // gaps, card padding, section spacing — step up (they carry ~90% of the
    // app's spacing: s2/s3/s4 are used ~930×), while the atomic s1 stays tight
    // so deliberate groupings (caption↔number, icon↔label) don't drift, and the
    // rare macro rungs (s6/s8) hold so already-spacious areas don't blow out.
    // Names are now identifiers, not 4pt multiples — same convention the type
    // ramp uses ("names read as intent, not pixel counts").
    enum Space {
        static let s1: CGFloat = 4    // atomic — deliberately unchanged
        /// Mac density (2026-07-28): rows and cards were sized for a
        /// fingertip, and next to a system whose own text starts at 13pt
        /// that reads as the biggest "this is a stretched iPad app" tell —
        /// bigger than any single component fix, because it's every row at
        /// once. Scoped to s2–s4 (the values already tuned once, "was X"
        /// below) — s1 and s6 stay fixed on both platforms on purpose, and
        /// the type ramp and chip sizing rulings are untouched; this only
        /// changes the AIR between things, ~15–20% tighter, so the
        /// proportions survive intact rather than the components shrinking.
        #if targetEnvironment(macCatalyst)
        static let s2: CGFloat = 8    // was 10 (iOS), was 8 before that
        static let s3: CGFloat = 12   // was 14 (iOS), was 12 before that
        static let s4: CGFloat = 15   // was 18 (iOS), was 16 before that
        #else
        static let s2: CGFloat = 10   // was 8
        static let s3: CGFloat = 14   // was 12
        static let s4: CGFloat = 18   // was 16
        #endif
        static let s6: CGFloat = 24   // macro — unchanged
        static let s8: CGFloat = 32   // macro — unchanged
    }

    // MARK: - Layout (iPad content width — see `dsAdaptiveContentWidth()`)

    enum Layout {
        /// The single-column content cap on iPad (regular width class).
        ///
        /// This was a flat 900 for every screen, which is the number that made
        /// the app read as a phone stretched to fit (2026-07-25): at 900 a
        /// feed row put its title and its trailing metadata ~700pt apart, and
        /// a Settings row stranded its value at the far edge of a card
        /// floating in an otherwise empty canvas. There are two jobs here, not
        /// one — a READING column (a single file of rows) and a WIDE column
        /// (a grid, which answers width with more columns instead of longer
        /// rows) — so the token split in two. See `DSContentWidth`.
        static let iPadReadingMaxWidth: CGFloat = PadLayout.readingMaxWidth
        static let iPadWideMaxWidth: CGFloat = PadLayout.wideMaxWidth
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
