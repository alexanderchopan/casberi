import SwiftUI

/// Hex → Color, plus an adaptive (dark, light) builder.
///
/// This is the ONLY place raw hex strings are allowed to live. Every token in
/// `DS` is built from these helpers; components downstream reference tokens by
/// name and never touch a hex literal (build brief §8 — "components hold zero
/// raw hex").
extension Color {

    /// Accepts `#RGB`, `#RRGGBB`, `#RRGGBBAA` (with or without leading `#`).
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)

        let r, g, b, a: Double
        switch s.count {
        case 3: // RGB
            r = Double((value >> 8) & 0xF) / 15
            g = Double((value >> 4) & 0xF) / 15
            b = Double(value & 0xF) / 15
            a = 1
        case 6: // RRGGBB
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        case 8: // RRGGBBAA
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        default:
            r = 0; g = 0; b = 0; a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// Builds a single token that resolves to `dark` or `light` per the active
    /// interface style. Backed by a dynamic `UIColor` so it composes with
    /// SwiftUI materials, strokes, and shadows without an asset catalog.
    static func adaptive(dark: String, light: String) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .light ? light : dark
            return UIColor(Color(hex: hex))
        })
    }

    /// A token whose value does not change across light/dark (e.g. the tint).
    static func fixed(_ hex: String) -> Color { Color(hex: hex) }

    /// True when the color is light enough that WHITE ink reads poorly on it —
    /// the signal a brand fill (ChatGPT's white, Notes' yellow) needs DARK ink
    /// instead. Resolves through UIColor so fixed and adaptive colors alike
    /// report a real luminance. Rec. 601 luma, thresholded high so only the
    /// genuinely pale brands flip.
    var isLight: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (0.299 * r + 0.587 * g + 0.114 * b) > 0.7
    }
}
