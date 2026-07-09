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
