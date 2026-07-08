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
        switch source.lowercased() {
        case "calendar":            return Color.fixed("#ff3b30")
        case "gmail", "mail":       return Color.fixed("#ea4335")
        case "icloud mail":         return Color.fixed("#3693f3")
        case "chatgpt":             return Color.fixed("#ffffff")
        case "claude":              return Color.fixed("#d97757")
        case "reminders":           return Color.fixed("#ff9500")
        case "photos":              return Color.fixed("#5e9ee6")
        case "x", "twitter":        return Color.fixed("#000000")
        case "notes":               return Color.fixed("#ffcc00")
        case "safari":              return Color.fixed("#1d9bf6")
        case "wallet":              return Color.fixed("#2461ff")
        case "dexscreener":         return Color.fixed("#151a21")   // their dark field
        case "venice":              return Color.fixed("#0e2942")   // sampled from their deep-blue mark
        case "voice":               return Color.fixed("#ff375f")   // the voice kind's own pink
        case "apple health":        return Color.fixed("#ff2d55")
        case "strava":              return Color.fixed("#fc4c02")
        case "todoist":             return Color.fixed("#e44332")
        case "slack":               return Color.fixed("#4a154b")
        case "raindrop":            return Color.fixed("#0db4e7")
        case "readwise":            return Color.fixed("#087bff")
        case "rss":                 return Color.fixed("#f26522")
        case "farcaster":           return Color.fixed("#855dcd")
        case "bluesky":             return Color.fixed("#0285ff")
        case "cal.com":             return Color.fixed("#292929")
        case "calendly":            return Color.fixed("#006bff")
        default:                    return DS.gray300
        }
    }
}
