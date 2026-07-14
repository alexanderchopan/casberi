import SwiftUI

/// Squircle app-icon stand-in. Gap list §9.6: letter/brand tiles stand in until
/// real app-icon assets ship per store guidelines. Radius follows the 22.37%
/// app-icon ratio. Brand colors are identity (color rule allows identity), and
/// they live here in the design layer — components never inline the hex.
struct AppIconTile: View {
    let source: String
    var size: CGFloat = 40

    private var brand: Color { DS.brandColor(for: source) }
    private var letter: String { String(source.prefix(1)).uppercased() }

    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.appIcon(size), style: .continuous)
            .fill(brand)
            .frame(width: size, height: size)
            .overlay(
                Text(letter)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.appIcon(size), style: .continuous)
                    .strokeBorder(.black.opacity(0.08), lineWidth: 1)
            )
    }
}

extension DS {
    /// Brand-color table for the icon stand-ins. Identity color, kept out of the
    /// component. Unknown sources fall back to the neutral gray fill.
    static func brandColor(for source: String) -> Color {
        brandHue(for: source) ?? DS.gray300
    }

    /// The hue itself, nil when the source has none — the gray fallback is
    /// a fill, not an identity, so surfaces that WEAR the hue (the thing
    /// sheet's wash) ask this and stay pure ink on nil (ruling 2026-07-10).
    static func brandHue(for source: String) -> Color? {
        switch source.lowercased() {
        case "calendar":            return Color.fixed("#ff3b30")
        case "gmail", "mail":       return Color.fixed("#ea4335")
        case "icloud mail":         return Color.fixed("#3693f3")
        case "chatgpt":             return Color.fixed("#ffffff")
        case "claude":              return Color.fixed("#d97757")
        case "gemini":              return Color.fixed("#4285f4")   // the sparkle's blue end
        case "reminders":           return Color.fixed("#ff9500")
        case "photos":              return Color.fixed("#5e9ee6")
        case "x", "twitter":        return Color.fixed("#000000")
        case "notes", "apple notes": return Color.fixed("#ffcc00")
        case "apple journal":       return Color.fixed("#a06ee1")   // Journal's lavender
        case "day one":             return Color.fixed("#44c0ff")   // Day One blue
        case "safari":              return Color.fixed("#1d9bf6")
        case "wallet":              return Color.fixed("#2461ff")
        case "kalshi":              return Color.fixed("#4fae7b")   // their green (matches the bundled logo)
        case "tokens":              return Color.fixed("#f5a623")   // coin gold — this app's own mark, not a vendor's (2026-07-13 rename)
        case "venice":              return Color.fixed("#0e2942")   // sampled from their deep-blue mark
        case "openclaw":            return Color.fixed("#e5342e")   // the agents' red (user, 2026-07-12)
        case "voice":               return Color.fixed("#ff375f")   // the voice kind's own pink
        case "apple health":        return Color.fixed("#ff2d55")
        case "strava":              return Color.fixed("#fc4c02")
        case "todoist":             return Color.fixed("#e44332")
        case "slack":               return Color.fixed("#4a154b")
        case "raindrop":            return Color.fixed("#0db4e7")
        case "readwise":            return Color.fixed("#087bff")
        case "rss":                 return Color.fixed("#f26522")
        case "farcaster":           return Color.fixed("#855dcd")
        case "pinterest":           return Color.fixed("#e60023")
        case "bluesky":             return Color.fixed("#0285ff")
        case "cal.com":             return Color.fixed("#292929")
        case "calendly":            return Color.fixed("#006bff")
        case "steam":               return Color.fixed("#1b2838")   // their dark navy
        case "obsidian":            return Color.fixed("#7c3aed")   // vault purple
        case "twitch":              return Color.fixed("#9146ff")
        case "reddit":              return Color.fixed("#ff4500")
        case "youtube":             return Color.fixed("#ff0000")
        case "substack":            return Color.fixed("#ff6719")
        case "podcasts":            return Color.fixed("#8a2be2")   // Apple Podcasts purple
        case "contacts":            return Color.fixed("#34c759")   // Contacts green
        case "kindle":              return Color.fixed("#f2a900")   // Amazon/Kindle amber
        default:                    return nil
        }
    }

    /// The brand hue normalized for the WASH surfaces — the feed's shape
    /// wash, the switch flood, the thing sheet, the app detail page. Raw
    /// brand hexes aren't a designed ramp: RGB-mixing them toward black
    /// shifted yellows to olive and browns, and left the near-black marks
    /// (Steam, Venice) as colorless smudges (user, 2026-07-13). Still one
    /// formula, no per-hue tables — keep the hue angle, pin saturation into
    /// a vivid band, and let the brand's OWN brightness through (user ruling
    /// 2026-07-13: the old 0.40–0.62 brightness band read as a deep muddy
    /// wash — the bleed should pop like the theme backgrounds' bright
    /// primaries and the app marks it inherits; only a floor for the darkest
    /// saturated marks and a ceiling shy of neon). Near-neutral marks
    /// (X, Cal.com, ChatGPT) return nil: no honest hue, no wash — the same
    /// ruling as `brandHue`'s nil. Identity uses (icons, the connect bloom)
    /// keep the true `brandHue`.
    static func washHue(for source: String) -> Color? {
        guard let brand = brandHue(for: source) else { return nil }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(brand).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        guard s >= 0.15 else { return nil }
        return Color(hue: h, saturation: max(s, 0.65),
                     brightness: min(max(b, 0.60), 0.95))
    }

    /// A brand hue's perceptual luminance (ITU-R BT.709), 0 (black) to 1
    /// (white) — used to catch hues too dark to read as a filled surface.
    private static func luminance(of color: Color) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
    }

    /// The brand hue as a CARD fill — a near-black brand mark (X's, #000000)
    /// would render its story card as an empty void, so a too-dark hue lifts
    /// toward the app tint instead of showing raw (design audit fix,
    /// 2026-07-12). Icons and other identity uses keep the true `brandHue`;
    /// only this fill-legibility path substitutes.
    static func legibleCardFill(for source: String) -> Color {
        let hue = brandHue(for: source) ?? DS.tint
        return luminance(of: hue) < 0.12 ? hue.mix(with: DS.tint, by: 0.6) : hue
    }
}
