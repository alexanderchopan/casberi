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
///     Magnitude = a neutral lightness ramp scaled by count (`DS.ink(magnitude:)`,
///     2026-08-10 — supersedes the tinted wash on every treemap, and §158's
///     per-token brand hue on the wallet's holdings map; see `DS.ink`'s own doc).
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

    /// The neutral tone for an `IconChip` badge with no real identity or
    /// state to preview (2026-08-10 — the same "unknown gets no invented
    /// color" ruling `TokenHue`/`brandHue` follow, one level up). FIXED
    /// rather than adaptive: the badge grammar pairs this with either a
    /// SOLID fill + white glyph or a soft wash, both of which need to stay
    /// legible in both themes the way a real brand hue does — not swap
    /// toward an unreadable pastel in light mode the way the UI grays do.
    /// Apple's own systemGray, which is built for exactly this "works
    /// against anything" job.
    static let neutralBadge = Color.fixed("#6e6e73")

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

    /// A RAISED grouping container — the mirror of `surfaceWell`, for a box
    /// drawn ON a sheet whose job is to be SEEN as holding its contents rather
    /// than to sit behind them (user ruling 2026-08-11, the sources tray's
    /// category cards; see `SourcesTray.slotFill`).
    ///
    /// The two rungs are NOT interchangeable and the choice is about what the
    /// box is for: a well is a backing you look INTO (a chart, a cover, a media
    /// frame), so it recedes; this is a container holding the primary tappable
    /// content of its screen, so it must not sit below the plane that content
    /// lives on.
    ///
    /// **The two themes carry the lift differently, and that is forced rather
    /// than chosen.** In dark it steps away from `surfaceSheet` toward the
    /// light and the tone alone does the work. In LIGHT there is no room above
    /// `#ffffff`, so the fill can only break the plane and the lift itself is
    /// carried by `raisedShadow` — which is still the ladder's own rule ("tone
    /// AND a soft ambient shadow"), with the two halves weighted per theme
    /// instead of split evenly.
    ///
    /// **Opaque on purpose, though it is exactly `fillFaint` composited over
    /// `surfaceSheet`.** A translucent fill DOUBLES wherever two pieces of one
    /// bridged card overlap, and `SourcesTray` bridges a multi-column card by
    /// overlapping its slot pieces into the gap between them — so the alpha
    /// form paints a stripe of doubled density down the middle of every wide
    /// card. That is a hairline drawn by accident, in the app that has zero
    /// exceptions to the no-line rule. Reach for `fillFaint` when the fill is
    /// drawn once; reach for this when it is drawn in pieces.
    static let surfaceRaised = Color.adaptive(dark: "#1a1a1c", light: "#f8f8f8")

    /// The lift under a `surfaceRaised` container. **Transparent in DARK on
    /// purpose** — `cardShadow` is calibrated for a card on the BLACK page,
    /// and that same heavy black halo around a `#1a1a1c` card on a `#111113`
    /// sheet reads as a stroke drawn around the card rather than as air under
    /// it, which is the one thing the ladder exists to avoid. In dark the
    /// tonal step is the whole signal; in light it is the only signal.
    static let raisedShadow  = Color.adaptive(dark: "#00000000", light: "#0000001f")

    // MARK: - Tint (one accent)  — brief §8, principle 2

    /// The one tint. Routed through `ThemeStore` so the swap ("pink one line
    /// away") is a runtime choice; reading it in a body tracks the store.
    static var tint: Color { themedTint }
    /// Tint at rest-chip opacity.
    static var tintDim: Color { themedTintDim }

    /// The crown pour's color (prd §204) — the person's choice of six, and
    /// OFF by default since 2026-08-04 (`Ink`, which pours nothing rather than
    /// pouring black; see `ThemeStore.bleeds`). `MainSurface.crownPour`'s ONLY consumer;
    /// never route a chip, glyph, or state fill through this — those stay on
    /// `DS.tint`, which alone carries the Increase Contrast guarantee.
    static var bleed: Color { themedBleed }
    /// The bleed as a settings PREVIEW (see `themedBleedMark`) — never the
    /// pour itself, which is `bleed` and may legitimately be invisible.
    static var bleedMark: Color { themedBleedMark }

    /// Magnitude fill — tint at opacity scaled by a normalized count `t ∈ [0,1]`.
    /// Treemaps and project fills only (color rule: magnitude, not decoration).
    static func tint(magnitude t: Double) -> Color { wash(tint, magnitude: t) }

    /// The same magnitude ramp over a colour that ISN'T the tint — the one
    /// case being a cell that carries STATE as well as magnitude (an
    /// undeclared host on the receipts map wears `attention`). Shared rather
    /// than re-spelled at the call site so the two washes can never land on
    /// different opacity curves and read as different amounts of the same
    /// thing.
    static func wash(_ color: Color, magnitude t: Double) -> Color {
        color.opacity(0.06 + 0.22 * min(max(t, 0), 1))
    }

    /// The neutral magnitude fill every treemap cell wears now (2026-08-10,
    /// user: "i don't want brand hue... we need to match [the wallet's]
    /// style" — the deep-near-black tones the wallet's own cards already sit
    /// on, "Darker" of three depths tried against a real screenshot).
    /// Supersedes `tint(magnitude:)` on every `UnitTreemap`/`MiniTreemap`
    /// cell, AND §158's per-token brand hue (`TokenHue`, now deleted) on the
    /// wallet's own holdings map — that ruling gave hue an identity job on
    /// this same fill, and this ruling takes it back: every treemap in the
    /// app reads as one family again, magnitude the only thing any of them
    /// say, none of them the app's tint.
    ///
    /// A flat lightness step between two neutral tones, not an opacity ramp
    /// over a hue — floor and ceiling were picked by eye against the wallet's
    /// real `surfaceSheet` (`#111113` dark / `#ffffff` light) so the
    /// brightest cell visibly lifts off the card without the board asserting
    /// itself the way the tint wash did. Because the result is always fully
    /// opaque, a caller no longer needs a `surfaceWell` base under it to keep
    /// a low-magnitude cell from vanishing into the card (`X402RoomCard`'s
    /// and the receipts map's old workaround) — harmless to keep, since ink
    /// paints over it either way.
    static func ink(magnitude t: Double) -> Color {
        let clamped = CGFloat(min(max(t, 0), 1))
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .light
                ? Self.inkStep(clamped, floor: (0.9333, 0.9373, 0.9529), ceiling: (0.7843, 0.7922, 0.8196))
                : Self.inkStep(clamped, floor: (0.0745, 0.0745, 0.0863), ceiling: (0.1451, 0.1490, 0.1686))
        })
    }

    /// One lightness step, `t` of the way from `floor` to `ceiling` — the
    /// arithmetic `ink(magnitude:)` needs twice (light and dark), pulled out
    /// because a single expression combining both branches was too much for
    /// the type checker to resolve in reasonable time.
    private static func inkStep(_ t: CGFloat,
                                 floor: (CGFloat, CGFloat, CGFloat),
                                 ceiling: (CGFloat, CGFloat, CGFloat)) -> UIColor {
        UIColor(red: floor.0 + (ceiling.0 - floor.0) * t,
                green: floor.1 + (ceiling.1 - floor.1) * t,
                blue: floor.2 + (ceiling.2 - floor.2) * t,
                alpha: 1)
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

    // MARK: - Device naming (Mac Catalyst polish, 2026-07-31)

    /// True on the Mac Catalyst build — the one branch point every
    /// device-naming string below reads off, so it can't drift from the
    /// actual target.
    static var isMac: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }

    /// The on-device noun privacy/connect copy names — every "this
    /// iPhone"/"this Mac" claim in the app is a literal, checkable promise
    /// (see `NetworkReach.swift`), so it has to name the device it's
    /// actually running on, not hardcode the phone case.
    static var device: String { isMac ? "this Mac" : "this iPhone" }

    /// Where a denied permission sends you to re-grant it — Mac Catalyst has
    /// no "iOS Settings" app, so a denial copy pointing there is a dead
    /// instruction on Mac (the honesty rule).
    static var settingsAppName: String { isMac ? "System Settings" : "iOS Settings" }

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

    // MARK: - Motion  — ~250ms, one animation per moment

    /// SPRINGS since 2026-08-04 (the microanimation pass): the original
    /// `timingCurve(0.32, 0.72, 0, 1)` — the prototype's `--ds-ease` — was a
    /// fixed-duration curve, which a second transaction mid-flight RESTARTS
    /// rather than retargets. A spring keeps its velocity when interrupted,
    /// so a chip tapped mid-slide or a chrome fold reversed halfway feels
    /// continuous instead of snapping to a new start. `duration:`/`bounce:`
    /// are tuned to read the same as the old curve at rest (fast out, soft
    /// landing, no visible overshoot at bounce 0.15) — this is a feel change
    /// only under interruption, by design. `ChartEntrance` stays its own
    /// vocabulary on purpose (its doc explains the two-cadence ruling).
    enum Motion {
        static let duration: Double = 0.25
        /// The app-wide transition spring (was the prototype's `--ds-ease`).
        static let standard = Animation.spring(duration: duration, bounce: 0.15)
        /// Slightly longer for the composer bubble (prototype: 260ms).
        static let bubble = Animation.spring(duration: 0.3, bounce: 0.2)
        /// Press feedback — faster and livelier than a transition, because a
        /// finger is on the glass and the response has to feel attached to
        /// it. One token so every pressed control dips on the same clock.
        static let press = Animation.spring(duration: 0.2, bounce: 0.4)
    }
}


/// The press feel for tappable tiles and pills: a soft spring dip, matching
/// iOS's own control feedback (polish 2026-07-07; on `DS.Motion.press` since
/// the 2026-08-04 spring unification).
struct PressSpring: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(DS.Motion.press, value: configuration.isPressed)
    }
}

/// The press feel for a FEED ROW (2026-08-04). Rows can't use `PressSpring`'s
/// 0.96 dip: their card slab is a `listRowBackground`, which a ButtonStyle
/// can't reach, so a visible scale would shrink the content inside a
/// full-size slab. Instead: a near-imperceptible settle plus a dim — the
/// UIKit cell-highlight grammar, sprung. Shared here (not in FeedScreen) so
/// any future list of bare rows presses the same way.
struct RowPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(DS.Motion.press, value: configuration.isPressed)
    }
}
