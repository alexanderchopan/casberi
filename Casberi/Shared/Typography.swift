import SwiftUI

/// The SF type ramp. Ported 1:1 from the prototype's `.t-*` classes, which are
/// the concrete visual spec. Brief §8 named the original size ramp
/// 34/22/17/15/13/12/10; the reading band (17/15/13 → 18/16/14, see below) was
/// raised a point each on 2026-07-25 so running text reads less like a manual.
///
/// Dynamic Type: every style scales with the person's text-size setting via
/// UIFontMetrics, anchored to its nearest system text style — the ramp keeps
/// its proportions while honoring accessibility sizes.
struct DSTextStyle {
    let size: CGFloat
    let weight: Font.Weight
    let tracking: CGFloat
    let lineHeight: CGFloat
    /// Anchor for Dynamic Type scaling.
    var relative: UIFont.TextStyle = .body
    var monospaced = false
    /// SF Rounded, for the DISPLAY tier only (2026-07-09) — the big headings
    /// read warmer and more personal, which suits a cover that says "this is
    /// YOUR week." Functional text (body, rows, labels) stays SF Pro Text,
    /// which scans crisper at UI sizes and keeps the app feeling native.
    var rounded = false

    /// SwiftUI `lineSpacing` is additive over the font's intrinsic leading; this
    /// approximates the CSS line-height without measuring UIFont metrics.
    var lineSpacing: CGFloat { max(0, lineHeight - size * 1.18) }

    /// The Dynamic-Type-scaled `Font` alone, for call sites that can't use the
    /// `dsText` view modifier — e.g. a segment inside a concatenated `Text`
    /// (`Text + Text`), which requires `Text`'s own `.font(_:)` overload to
    /// stay `Text`-typed rather than erasing to `some View`.
    var scaledFont: Font {
        let scaled = UIFontMetrics(forTextStyle: relative).scaledValue(for: size)
        return Font.system(size: scaled, weight: weight,
                            design: monospaced ? .monospaced : rounded ? .rounded : .default)
    }
}

extension DSTextStyle {
    // Prototype class → style. Names read as intent, not pixel counts.
    // Tracking is ZERO on both display rungs (2026-07-30). They carried +0.34
    // and +0.22 — positive letter-spacing, ported straight from the prototype
    // CSS, at exactly the two sizes where SF's own optical face wants letters
    // pulled TOGETHER rather than pushed apart. It also sat against §8's own
    // law ("no letter-spacing... `.kerning()` is banned"), which the rest of
    // the ramp already honours — every other rung here is 0. Nothing else about
    // these two changes: same size, same weight, same rounded face.
    static let heading34 = DSTextStyle(size: 34, weight: .bold,     tracking: 0,    lineHeight: 41, relative: .largeTitle, rounded: true)
    /// The LEDE rung (2026-07-31) — the day brief's opening sentence, and
    /// nothing else. It exists because the two display rungs either side of it
    /// are both wrong for a sentence: `heading22` is the card-and-tray TITLE
    /// rung (`DSTray`, `GenWidget`), so the brief's headline read as a label
    /// over the hero's `price40` rather than as the day said in words — same
    /// rounded bold face, eight points apart, one visual unit. And
    /// `heading34` is the COVER rung, sized for two-to-four-word statements: a
    /// real lede ("Up $1,247 today. ETH did the lifting, three days running.")
    /// runs three or four lines there and pushes the money hero — the crown by
    /// ruling — clean off the first screen. 28 keeps the crown visible while
    /// putting a full step of air between the sentence and the number.
    ///
    /// One caller, deliberately, the way `price48` is one caller: a second
    /// would flatten the hierarchy this exists to make.
    static let heading28 = DSTextStyle(size: 28, weight: .bold,     tracking: 0,    lineHeight: 34, relative: .title1, rounded: true)
    static let heading22 = DSTextStyle(size: 22, weight: .bold,     tracking: 0,    lineHeight: 28, relative: .title2, rounded: true)
    /// The LONG-POST rung (2026-08-02) — a social post's own words when there
    /// are enough of them to be a paragraph rather than a statement, and
    /// nothing else.
    ///
    /// It is the one rung ABOVE the reading band that is not display type, and
    /// that's the whole point. A post leads the sheet in the title's slot
    /// (`ThingSheetView.titleBlock`), so it wants to sit above `body17`; but
    /// `heading22` — the rung it used to fall back to, with no upper bound —
    /// is bold SF Rounded, a title face, and a 900-character cast set end to
    /// end in it reads as a wall: sustained bold flattens word shapes, and
    /// this file's own 2026-07-09 rule already says rounded is the display
    /// tier while running text stays SF Pro Text. So: 20pt REGULAR, SF Pro
    /// Text, with the reading band's open leading (`body17` is 18/26; a post
    /// is the whole screen's payload, so it gets one more point and two more
    /// of line height). Hierarchy still by size alone — nothing here is a
    /// trick the ramp doesn't already use.
    static let reading20 = DSTextStyle(size: 20, weight: .regular,  tracking: 0,    lineHeight: 30, relative: .title3)
    // Reading-band pass (2026-07-25). The app leaned on 13/15/17 for nearly
    // all its running text — a lot of real sentences (row sublines, wallet
    // metadata, DeFi stats) sat at 13pt, which read dense and document-like
    // ("like a technical manual", user). Each of these four rungs steps up one
    // point AND opens its line-height, so the reading band is both larger and
    // airier. The DISPLAY tier (heading22/34), MONEY rungs (price*/stat24), and
    // the micro-caption floor (label12/11, tab10) are deliberately untouched —
    // moving those would flatten the hierarchy the feed and wallet lean on.
    // Names keep their original pixel suffix as stable identifiers (the ~485
    // call sites are unchanged); the comment above the ramp already says "names
    // read as intent, not pixel counts".
    /// Also the app's ROW TITLE — a row's name is a heading for the line it
    /// leads, and the wallet room's own `rowTitle17` folded into this on
    /// 2026-08-03 (see the note where it used to live, below the money rungs).
    /// SF Pro Text, NOT rounded: prd §190 fixed the complaint *"we have
    /// different fonts"* with ONE font, and Typography's 2026-07-09 rule keeps
    /// rounded in the display tier while body, rows and labels stay Text. So a
    /// row title says "tappable" by WEIGHT — semibold against the subline's
    /// regular — never by a second typeface.
    static let heading17 = DSTextStyle(size: 18, weight: .semibold, tracking: 0,    lineHeight: 24, relative: .headline)
    static let body17    = DSTextStyle(size: 18, weight: .regular,  tracking: 0,    lineHeight: 26, relative: .body)
    static let callout15 = DSTextStyle(size: 16, weight: .regular,  tracking: 0,    lineHeight: 23, relative: .subheadline)
    static let subhead13 = DSTextStyle(size: 14, weight: .regular,  tracking: 0,    lineHeight: 21, relative: .footnote)
    static let label12   = DSTextStyle(size: 12, weight: .medium,   tracking: 0,    lineHeight: 16, relative: .caption1)
    static let tab10     = DSTextStyle(size: 10, weight: .medium,   tracking: 0,    lineHeight: 12, relative: .caption2)
    static let mono12    = DSTextStyle(size: 12, weight: .regular,  tracking: 0,    lineHeight: 16, relative: .caption1, monospaced: true)

    // Rungs added by the Dynamic Type pass (2026-07-21). Each one existed
    // already as a raw `.system(size:)` somewhere — frozen while its
    // neighbours grew. They are here rather than folded into the nearest
    // existing rung so the fix costs nothing visually: same size, same
    // weight, now scaled.
    /// The row's project tag — one step under `label12`.
    static let label11   = DSTextStyle(size: 11, weight: .medium,   tracking: 0,    lineHeight: 15, relative: .caption2)
    /// Monospaced body — command cards, diagnostic log lines.
    static let mono13    = DSTextStyle(size: 13, weight: .regular,  tracking: 0,    lineHeight: 18, relative: .footnote, monospaced: true)
    /// A device-flow user code: the one string on its screen, read aloud off
    /// the glass and typed into another device. Monospaced so the character
    /// groups stay even, and display-sized because it IS the screen.
    static let monoCode34 = DSTextStyle(size: 34, weight: .bold,    tracking: 0,    lineHeight: 41, relative: .largeTitle, monospaced: true)

    // The Big money rungs (prd §102, 2026-07-17) — token money's three
    // deliberate off-ramp sizes: the sheet's hero price, its stat cards, the
    // fat feed row's price. Display-tier rounded bold, and routed through
    // this ramp precisely so they SCALE with Dynamic Type like everything
    // else (raw `.font(.system(size:))` froze while neighbors grew).
    /// The portfolio rung (prd §157, 2026-07-21) — one step above `price40`,
    /// for the single biggest number in the app: the wallet room's combined
    /// total. A money app's confidence lives in its numerals, and at 40 beside
    /// its own caption the total read as one more label. Nothing else earns
    /// this size; a second user would flatten the hierarchy it exists to make.
    static let price48 = DSTextStyle(size: 48, weight: .bold, tracking: 0, lineHeight: 52, relative: .largeTitle, rounded: true)
    static let price40 = DSTextStyle(size: 40, weight: .bold, tracking: 0, lineHeight: 44, relative: .largeTitle, rounded: true)
    static let stat24  = DSTextStyle(size: 24, weight: .bold, tracking: 0, lineHeight: 28, relative: .title2, rounded: true)
    static let price16 = DSTextStyle(size: 16, weight: .bold, tracking: 0, lineHeight: 20, relative: .callout, rounded: true)
    // `rowTitle17` lived here and is GONE (2026-08-03). It was the wallet
    // room's private row-title rung (prd §212, 2026-07-25) at size 17 — and it
    // was authored at its literal NAME on the same day the reading-band pass
    // moved `body17` and `heading17` from 17 to 18, so it shipped a full point
    // under the room's own body text. A wallet-manager row's name sat 1pt below
    // the field above it and the door below it: invisible as hierarchy, visible
    // as a mistake, and read by the user as the screen having "three different
    // sizes" when 17 and 18 don't separate, they wobble.
    //
    // Correcting it to 18 made it byte-identical to `heading17` — same size,
    // same semibold, same SF Pro Text — which is a duplicate rung, exactly the
    // drift a named ramp exists to prevent. So it folded into `heading17`,
    // which the app ALREADY titles rows with: a person in `FollowImportSheet`,
    // a language, a starter pack, and — decisively — `entry.name` in
    // `AddressBookViews`, the same address-book entry the wallet manager was
    // rendering one point smaller two screens away.
    //
    // Its one piece of reasoning worth keeping is recorded on `heading17`
    // above: SF Pro Text, never the rounded money face, per prd §190.

    // Small decorative accents (2026-07-24 drift fix) — each already existed
    // as a raw `.system(size:)` on real Text, unscaled and unnamed.
    /// The streaming-response "still writing" dot (GenRenderer).
    static let indicator9    = DSTextStyle(size: 9,  weight: .regular, tracking: 0, lineHeight: 12, relative: .caption2)
    /// A token's fallback avatar initial when no logo art exists (GenRenderer).
    static let badgeInitial11 = DSTextStyle(size: 11, weight: .bold, tracking: 0, lineHeight: 15, relative: .caption2)
    /// The onboarding step card's giant background numeral — accessibility-hidden,
    /// sighted-only decoration, so nothing else earns this size (mirrors `price48`'s reasoning).
    static let flourish148 = DSTextStyle(size: 148, weight: .heavy, tracking: 0, lineHeight: 150, relative: .largeTitle, rounded: true)

    // Widget/Live Activity rungs (2026-07-24 drift fix) — CasberiWidgets.swift
    // couldn't reach this file before it lived in Shared/, so every widget
    // label was a raw, unscaled size. Sizes/weights are unchanged from what
    // shipped; only the plumbing changed. `heading17` and `label11` already
    // covered two of the widget's sizes exactly and are reused as-is.
    /// The Live Activity's "Recording" chrome label and its lock-screen timer.
    static let widgetChrome15  = DSTextStyle(size: 15, weight: .semibold, tracking: 0, lineHeight: 20, relative: .subheadline)
    /// Dynamic Island's compact-trailing timer.
    static let widgetTimer13   = DSTextStyle(size: 13, weight: .semibold, tracking: 0, lineHeight: 18, relative: .footnote)
    /// The accessory-rectangular widget's eyebrow, and the hero widget's new-count ring badge.
    static let widgetEyebrow11 = DSTextStyle(size: 11, weight: .semibold, tracking: 0, lineHeight: 15, relative: .caption2)
    /// The accessory-rectangular widget's title line.
    static let widgetTitle14   = DSTextStyle(size: 14, weight: .bold, tracking: 0, lineHeight: 19, relative: .footnote)
    /// The accessory-rectangular widget's subline.
    static let widgetSubline11 = DSTextStyle(size: 11, weight: .regular, tracking: 0, lineHeight: 15, relative: .caption2)
    /// The default-family hero widget's title line.
    static let widgetTitle17   = DSTextStyle(size: 17, weight: .bold, tracking: 0, lineHeight: 22, relative: .callout)
    /// The default-family hero widget's subline.
    static let widgetSubline12 = DSTextStyle(size: 12, weight: .regular, tracking: 0, lineHeight: 16, relative: .caption1)
    /// The medium widget's treemap cell terms (2026-08-03) — semibold so a
    /// one-word theme reads against its own cell's fill at a glance.
    static let widgetTreemapTerm12 = DSTextStyle(size: 12, weight: .semibold, tracking: 0, lineHeight: 15, relative: .caption1)
    /// The medium widget's recent-item row title, under the treemap.
    static let widgetRecentTitle12 = DSTextStyle(size: 12, weight: .semibold, tracking: 0, lineHeight: 16, relative: .caption1)
}

private struct DSTextModifier: ViewModifier {
    let style: DSTextStyle
    // Reading the size category invalidates the view when the setting changes.
    @Environment(\.sizeCategory) private var sizeCategory

    func body(content: Content) -> some View {
        let scaled = UIFontMetrics(forTextStyle: style.relative)
            .scaledValue(for: style.size)
        content
            .font(Font.system(size: scaled, weight: style.weight,
                              design: style.monospaced ? .monospaced
                                    : style.rounded ? .rounded : .default))
            .tracking(style.tracking)
            .lineSpacing(style.lineSpacing)
    }
}

extension View {
    /// Applies a token type style (font + tracking + line height), scaled for
    /// Dynamic Type.
    func dsText(_ style: DSTextStyle) -> some View {
        modifier(DSTextModifier(style: style))
    }
}
