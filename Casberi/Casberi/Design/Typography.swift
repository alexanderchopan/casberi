import SwiftUI

/// The SF type ramp. Ported 1:1 from the prototype's `.t-*` classes, which are
/// the concrete visual spec. Brief §8 names the size ramp 34/22/17/15/13/12/10.
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
}

extension DSTextStyle {
    // Prototype class → style. Names read as intent, not pixel counts.
    static let heading34 = DSTextStyle(size: 34, weight: .bold,     tracking: 0.34, lineHeight: 41, relative: .largeTitle, rounded: true)
    static let heading22 = DSTextStyle(size: 22, weight: .bold,     tracking: 0.22, lineHeight: 28, relative: .title2, rounded: true)
    static let heading17 = DSTextStyle(size: 17, weight: .semibold, tracking: 0,    lineHeight: 22, relative: .headline)
    static let body17    = DSTextStyle(size: 17, weight: .regular,  tracking: 0,    lineHeight: 22, relative: .body)
    static let callout15 = DSTextStyle(size: 15, weight: .regular,  tracking: 0,    lineHeight: 20, relative: .subheadline)
    static let subhead13 = DSTextStyle(size: 13, weight: .regular,  tracking: 0,    lineHeight: 18, relative: .footnote)
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
    static let price40 = DSTextStyle(size: 40, weight: .bold, tracking: 0, lineHeight: 44, relative: .largeTitle, rounded: true)
    static let stat24  = DSTextStyle(size: 24, weight: .bold, tracking: 0, lineHeight: 28, relative: .title2, rounded: true)
    static let price16 = DSTextStyle(size: 16, weight: .bold, tracking: 0, lineHeight: 20, relative: .callout, rounded: true)
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
